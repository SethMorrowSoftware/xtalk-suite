# The OXT engine pass runbook

**Scope: the whole suite. Audience: the person sitting at a real OpenXTalk engine.**

> **Read [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) first, and add to it after.**
> It is the list of things the engine does that no gate here predicted - the
> verbatim symptoms, what each one broke, and whether anything now catches it.
> Most of it was paid for in sessions like the one you are about to run, and the
> fastest way to make that cost worth paying twice is to write down what you see.

Everything in this repository that reads *"verified statically; needs an OXT pass"*
is waiting on this session, and only on this session. OXT is a GUI runtime with no
headless way to compile or run `.lcb` / `.livecodescript`, so CI can prove the native
shims and the pure-compute vectors but can never prove that a binding **loads**, that
a foreign declaration **marshals**, or that a handler **returns what the docs say**.
That is the gap this session closes.

---

## THE SPARSE-ACCESS SESSION PLAN (2026-08-15)

**Engine access is sparse now, so this section is the scheduler: the entire
open backlog, partitioned into session types by the resources each item
actually needs, so whoever gets engine time runs the highest-yield script for
whatever they have that day and spends zero minutes deciding.** Items cite the
section-1.2 inventory by number - rows 11-24 were added with this plan (the
2026-08-14/15 builds) - and #31-#33 cite the VERIFY register in
`docs/ONIONXT-INTEGRATION-PLAN.md` section 12.3 by that register's own
numbering, not this inventory's. Everything else in this runbook applies as
written: section 2 for installs and the exact torrc, 3.1 for paste-and-reopen,
section 5 for the traps (5.1.1 - quit and relaunch OXT before every
torrent-bearing paste - governs every session below), section 6 for failure
capture, 4.1 for copying results back, and the "After the pass" rule for the
label edits (members first, root `README.md` last). This plan schedules
passes; it claims none - every "flips" below happens only on a dated recorded
result, and a leg that only partly ran is recorded as exactly the part that
ran.

On a day with more than one resource, run the sessions in order anyway: S1 is
the cheapest signal, and its restyle re-opens de-risk every later leg, so
S1's hour is the right first hour of every longer session.

### S1 - one machine, one hour, no daemon (~60 min; +35 min stretch)

Prerequisites, once: a Linux or Windows engine, x64 or x86 (every native
member's library is committed for those - section 2.1); all six packaged
extensions installed from the current tree, with SodiumXT repackaged at
**ABI 10** (section 3.2 step -1; on a non-mac row, repackage normally). The
coinxt, onionxt and riptide script layers are embedded in the suite paste -
no `start using` step for item 1. No tor, no second machine. Items 1 and 2,
and each torrent-flavoured stack in items 3 and 5, want a fresh OXT launch
(trap 5.1.1).

Ordered by yield per minute - **but note when that ordering was computed.** The
ranking below predates the 2026-08-17 Windows pass, which closed inventory rows
11, 12, 15, 25, 26, 27, 30 and 32 in one blockquote. The table is deliberately
NOT renumbered (its item numbers are cited from the tick sheet, from section 3.2
and from the inventory rows), but the yield behind it has moved: items 1 and 2
now buy mostly standing regression cover plus row 13 and row 14, while items 3
and 5 - the restyle re-opens, which no engine has confirmed at all - and the
demo rows are where the unproven surface actually is. Read the ordering as a
route, not as a priority claim:

| # | Run | Expect | Record | ~min |
|---|---|---|---|---|
| 1 | `tests/suite-selftest.livecodescript` (paste + reopen per 3.1) | green `stSummary`, zero failures. **REVISED 2026-08-19: this cell used to promise FOUR first-time settlements and only ONE of them is still owed.** The 2026-08-17 Windows blockquote closed the ristretto255 ABI-8 section (row 11), the coinxt WIF section (row 12) and - with rows 25, 26, 27, 30 and 32 - most of the rest of the S1 backlog, and nobody annotated this cell afterwards. **SETTLED 2026-08-20** (Windows, 1981 passed / 0 failed / 1 skipped, 1982 total - the whole paste, both live loopbacks, teardown and summary): row 13 closed, and with it the last first-time settlement this cell owed. The paragraph below is kept as the record of what was owed and why. What genuinely remained first-time here was **row 13's two halves**: riptide's **"phase 6 - LAN sync records (drafts, feed state, presence)"** plus the serving seams (`rsAnonFeedPage` / `rsAnonPrekeyBody` / `rsAnonAcceptDm`) inside **"phase 7 - the anon persona, the guard, and BTXO framing"**, and the three malformed-UTF-8 refusal checks that came back RED on 2026-08-15 - the `rsBytesAreUtf8` fix's first observed run. Whether either ran or SKIPped in the 2026-08-18 Linux pass is not recorded anywhere in this tree, so row 13 stays open on both platforms. Everything else this paste buys is **standing regression value**, which is not nothing: **1,982 checks** as of the 2026-08-20 Windows run (1,868 of them across the nine folded harnesses, the rest the core's own probe, cross-member and teardown sections) and it is the cheapest signal in the runbook | flips row 13's labels (riptide's compute-half phase-6/7 sentences). Tick: BREADTH - and BREADTH is the line that most needs filling in, because the 2026-08-18 Linux pass reached this file only as a box2dxt number. Rows 11 and 12 are already ticked from 2026-08-17 | 12 |
| 2 | `holde-em/src/holdem.livecodescript` (paste + reopen), then `heRunSelftest` in the message box | the report panel ends `==== N pass, 0 fail, M skip ====` and `RESULT: green`; ~~**section 16** (`heTestLevel2Run`) RUNS rather than SKIPs on an ABI-8 SodiumXT (row 15)~~ **CLOSED 2026-08-17** - the blockquote reports holde-em's Level 2 and Phase 5 DLEQ green FOLDED, so section 16 is regression cover here, not a first result; **section 17** (`heTestOnionRun`) pins the 2f headless slice; the deal sections drive the two rewritten handlers - `heXorSeedsHex`, `heDeckFromStreamKey` - against the KAT pins (row 14) | flips row 14 (the fold blockquote's "needs an OXT re-pass" on both deal handlers) and row 15 (the L2 `sx*` call shapes). Tick: rows 14-15 | 12 |
| 3 | the three HIGHEST-GATING restyle re-opens (the 2026-08-14 blockquote), one OXT launch each: `torrentxt/examples/torrent-quickshare.livecodescript` (gates item 5 and the #31-#33 stack), `torrentxt/examples/torrent-dht-channels.livecodescript` (gates #31-#33), `riptide/examples/riptide-social.livecodescript` (gates rows 16/17/19; unlock an identity, confirm build + pump) | each window BUILDS in the v2 card look, the probe/status line is clean, no error dialog on open or close | each flips its own "UI unified 2026-08-14; needs an OXT re-pass" label; tick the matching DEMOS rows - "UI built, probe clean, no live leg" is the honest wording on a no-daemon day | 12 |
| 4 | holde-em hotseat: 2-3 hands in item 2's launch (blinds through showdown; force a side pot if you can) | hands complete with no error dialog; the report header names `kHeVersion` 0.24.5 and the harness version | first post-fold hotseat evidence on the v0.24.5 tree (0.24.3 when this row was written; the awarded-pot fix and the sit-out election fix moved it). Tick: the hotseat line in the ADDED block | 10 |
| 5 | the remaining restyle re-opens: `onionxt/examples/onionxt-demo.livecodescript` (probes must FAIL CLOSED with no tor - that IS tonight's pass), `enetxt/examples/enet-lan-chat.livecodescript`, `datachannelxt/examples/datachannel-loopback.livecodescript`, `torrentxt/examples/torrent-client.livecodescript` (fresh launch), `coinxt/examples/coinxt-demo.livecodescript` | as item 3 | as item 3; tick the DEMOS rows | 14 |
| S | STRETCH: `nocloud/src/nocloudquickshare.livecodescript`, then the web-link half of `nocloud/docs/oxt-pass-checklist.md` (sections 0-6a over a LAN web link; skip every Tor column) | per that checklist's own action -> expected lines | row 22's web-link half; the checklist file is its own record sheet | 35 |

### S2 - one machine plus a tor daemon (~3 h with setup)

Prerequisites, once: S1's install state, plus a system tor with the
section-2.3 torrc (`SocksPort 9050` / `ControlPort 9051` /
`CookieAuthentication 1`) and the `Opening Control listener` log line
confirmed; Tor Browser for the reach checks (its SOCKS is 9150 - trap 5.3); a
tor BINARY on disk for Mode B (item 2); `onionxt/src/onionxt.livecodescript`
in the message path for items 3, 6 and 7 ONLY - `torrent-quickshare` is
deliberately NOT embedded (its own `socketError` / `socketClosed` /
`socketTimeout` carry real clearweb logic that a carried OnionXT layer would
define twice; the reason is written out in `NOT_EMBEDDED` in
`tools/sync-demo-embeds.py`), and holde-em and nocloud are APPLICATIONS rather
than registered demos, so each still wants the optional `start using`. Items 1,
2, 4 and 5 carry the onionxt layer embedded since 2026-08-17 and need no wiring
at all: `onionxt/examples/onionxt-demo.livecodescript`,
`tests/suite-closing-pass.livecodescript`,
`torrentxt/examples/torrent-dht-channels.livecodescript` and
`riptide/examples/riptide-social.livecodescript` are each ONE paste (4.5), and
riptide-social carries `onion-httpd` too - so the old "plus
`onion-httpd.livecodescript` for item 5, the riptide demo refuses without it"
step is gone, and nothing else in S2 that lacks an embed calls a single `oxh*`
handler. Curl for item 5's /dm POST.
Re-read traps 5.3, 5.4 and 5.8. Items 3, 4 and 6 each take THE torrent
session - fresh OXT launch each (5.1.1). Setup ~15 min.

| # | Run | Expect | Record | ~min |
|---|---|---|---|---|
| 1 | `onionxt/examples/onionxt-demo.livecodescript` against the live daemon - the cheapest daemon-config disqualifier, so it goes first | control connects and authenticates, bootstrap seeds (trap 5.8), a service publishes and is reachable | runbook row 11 of section 3.2; exercises the service/control side of the seven live-daemon coverage exemptions. Tick: DEMOS "onionxt demo vs live tor" | 20 |
| 2 | `tests/suite-closing-pass.livecodescript`, leg **F** only (Mode B + onion echo) | F's PASS lines: `oxLaunchTor` starts a real tor (`the processId`, `Bootstrapped 100%`), then a listen + self-dial through the Tor network with exact bytes both ways | closes inventory item 4 (the 4.7 Mode B flips) + demo row 15 + the `oxTransport*` half of the live-Tor exemptions. Tick: closing-pass F | 25 |
| 3 | `torrentxt/examples/torrent-quickshare.livecodescript`, Tor toggle ON - item 5's single-machine halves | a Tor share code minted with NO torrent created and NO DHT call (the mutual exclusion); the folder-serving mode renders in Tor Browser. Optional full trip on one box: a SECOND OXT process can receive the code - the Tor path holds no torrent and each process owns its own session | the 4.7 "Quick Share over Tor" flips for exactly what ran; the capture/passphrase legs of the 12.4 gate stay S4. Tick: DEMOS "torrent-quickshare with Tor toggle ON" | 25 |
| 4 | **#31**, Channels Phase 0: `torrentxt/examples/torrent-dht-channels.livecodescript`, Anonymous ON / OFF / tor-absent | `Tor: ready` on the pill with the onion service up; OFF leaves every clearnet channel bit-for-bit unchanged; tor-absent shows the fail-closed messages; `chVerifyOnionIdentity` passes offline; pill + button fit the unchanged 1180x640 window | tick #31 in the 12.3 register itself (4.7's rule: tick the specific items, not the register); tick row 21's #31 half here | 25 |
| 5 | riptide persona serving: `riptide/docs/two-machine-runbook.md` phase 7, steps 1-5 on one machine | the anon feed page renders in Tor Browser; `/prekey` returns 264 hex and `rsVerifyPrekey` proves it; a curl POST to `/dm` answers `accepted` and a mangled or replayed one `refused` | row 19's single-machine half (the phase-7 serving label in `riptide/CLAUDE.md`); the second-machine delivery + zero-`bt*` trace stay S4. Tick: row 19 serving half | 30 |
| 6 | holde-em onion-table bring-up: Create a table with the onion transport in `holde-em/src/holdem.livecodescript` | the lobby Tor line walks the pill states; the invite prints as `<64hex>@<56base32>.onion`; the offline-derived address MATCHES `oxServiceAddress` at publish | row 20's single-machine half; the 2f exit (multi-hand, two machines) stays S4. Tick: row 20 bring-up half | 20 |
| 7 | the Tor half of `nocloud/docs/oxt-pass-checklist.md` (routes, headers and `/_qs/transparency` over the `.onion`; the concurrent Tor + web shares item) | per the checklist's lines; `/_qs/transparency` answers `both_ends_hidden:true` over Tor | row 22's Tor half; the checklist file is the record | 25 |

### S3 - two machines, no daemon (~3 h)

Prerequisites, once: the current tree's extensions installed on BOTH machines
(section 2); `tests/suite-closing-pass.livecodescript` pasted on both for
item 1 — **one paste, nothing to `start using`**: the ox* layer leg F needs is
carried inside that file; the same LAN — **not guest wifi**, which isolates
devices — with UDP allowed; for item 2's done-criterion, two DIFFERENT networks
(one machine on a phone hotspot); riptide identity discipline per the
two-machine runbook's setup table (DIFFERENT identities for the call, the SAME
identity for the mesh); one OXT process per stack instance in item 4 (trap 5.1).

**Open the right port, on the right machine.** This paragraph used to name only
27099, which is not the port item 1 uses — an operator preparing the firewall
from it opens the wrong one for the first thing they run, and finds out fifteen
seconds into a stall, on the other machine.

| Item | Port | On which machine |
|---|---|---|
| 1 — closing pass leg B | **UDP 27300** (`kEnetPort`) | inbound, on the machine that clicks **Host** |
| 1 — legs C/D/E | libtorrent's listen port, **dynamic** — read it with `btListenPort`; section A prints it | inbound on both is ideal; the DHT usually traverses without it |
| 2, 3 — riptide call + mesh | **UDP 27099** (`kLanPort`) | inbound, on the machine that hosts the mesh |
| 3 — enet LAN chat demo | **UDP 27099** (`kEcPort`) | inbound, on the machine that clicks **Host** |

Trap 5.5 if anything loopback-flavoured fails.

| # | Run | Expect | Record | ~min |
|---|---|---|---|---|
| 1 | `tests/suite-closing-pass.livecodescript`, legs **B-E** on both machines (leg A closed standalone 2026-08-15 - skip it) | each leg's PASS lines; C includes resume saved to disk and re-added across an OXT restart | closes the two-machine legs the row-18 table maps: enet chat (item 6's enetxt leg + demo row 8), seed/leech + resume, rp1 chat (row 14's legs), dc chat via the real DHT (row 13's shape). Tick: closing-pass B-E | 75 |
| 2 | riptide phase 5 (`riptide/docs/two-machine-runbook.md`): the call, then the typing lane | both sides `CALL CONNECTED: direct peer-to-peer channel open` with a `via` line (`typ srflx` on the two-network run is the done-criterion); `the far side is typing...` appears and clears; hang-up leaves the DM conversation alive | row 16; flips the phase-5 bullet in `riptide/CLAUDE.md` on a dated report. Tick: row 16 | 35 |
| 3 | riptide phase 6 (same runbook): welcome round, sync payload, stranger test | `ADMITTED - the host ... Mesh is mutual.`; `draft from <name> seq N applied` BOTH directions and the draft CONVERGES; `[typing]` then `[quiet]` on a kill; `feed seq N adopted`; `a peer FAILED admission (not your device)` for the stranger, with no record crossing | row 17; flips the phase-6 bullet. Tick: row 17 | 35 |
| 4 | holde-em 2d: a multi-hand online session over rp1 (extra stack instances fill seats to three or more) | hands complete on every seat; receipts match; the live audit verdicts land in the net feed | row 18; the 2d "needs the multi-machine OXT pass" line in `holde-em/IMPLEMENTATION-PLAN.md`. Tick: row 18 | 40 |

### S4 - two machines plus tor (~3 h)

Prerequisites, once: S3's two-machine state plus S2's tor prerequisites on
BOTH machines (the follower dials through its own SOCKS; item 4's POST needs
curl + SOCKS on the posting machine); Tor Browser on the follower; a
packet-capture tool on both ends for items 2 and 3's zero-swarm/DHT proof;
give the DHT its bootstrap seconds (trap 5.7) and publish onions fresh
(trap 5.4).

| # | Run | Expect | Record | ~min |
|---|---|---|---|---|
| 1 | **#32**, Channels Phase 2: A publishes an anon channel; B follows by the CARD only | the signed feed arrives over the onion with the DHT off for that channel; releases list; the live `oxServiceAddress == chChannelOnionAddr(pub)` byte-compare holds | tick #32 in the 12.3 register; tick row 21 | 30 |
| 2 | **#33**, Channels Phase 3: B downloads a selected release entirely over the onion | byte-identical (sha256); the teal `Onion` transfers row; packet capture shows ZERO swarm/DHT traffic for that file on both ends; a publisher restart prunes the stranded relIds | tick #33 in the 12.3 register; tick row 21 | 40 |
| 3 | the two-machine Quick Share Model C gate (item 5 + the plan's 12.4): a real file both directions with the Tor toggle ON | byte-identical delivery (sha256), onion-only capture, passphrase reject then decrypt, downgrade refusal | the 4.7 "Quick Share over Tor" flips, and the 12.3 ticks for exactly what ran. Tick: the DEMOS Tor-toggle row's two-machine half | 30 |
| 4 | riptide phase 7, the finishing half: B verifies the served prekey, builds the sealed intro with its PUBLIC identity, and POSTs it to A's onion through tor | `accepted`, and A's Anon card logs the PROVEN sender handle; a trace shows zero `bt*` calls for the persona | row 19 closed; flips the phase-7 bullet in `riptide/CLAUDE.md` and the two-machine runbook's phase-7 intro. Tick: row 19 | 30 |
| 5 | holde-em 2f exit: a multi-hand onion table session on two machines | join by the `<64hex>@<56base32>.onion` invite; multiple hands complete over the onion transport; failures only where scripted, each fail-closed with a readable reason | row 20 closed; flips the 2f entries in `holde-em/CLAUDE.md` and `holde-em/IMPLEMENTATION-PLAN.md`. Tick: row 20 | 45 |

### S5 - a Mac, or a Windows box

**Windows (~1 h).** Row 23: install the current packages (both bitnesses if
both engines exist) and run S1's item 1, the suite paste. This is the ABI-8
mingw DLL re-proof - the exact precedent is the 2026-08-12 pass that proved
the ABI-7 DLL. Expect the SodiumXT section green INCLUDING the SHA3 and
ristretto checks; record OS/arch and which DLL row ran. A 64-bit-only day
proves only `x86_64-win32` - say so, and the `x86-win32` row keeps its note.
Flips: the "needs its Windows engine pass" notes on the two Windows rows of
`sodiumxt/CLAUDE.md`'s ABI table. Tick: row 23. Spend any remaining time on
the rest of S1 - it counts double as Windows evidence.

**Mac (~3 h build, then S1's hour).** Row 24, in this order: sodiumxt manual
`lipo` build to ABI 10 (its CLAUDE.md mac row; per step -1, do NOT repackage
SodiumXT on this machine before the build lands); coinxt
`cd coinxt && sh native/build.sh pack` (2.4; use `tools/package-extension.py
--lib ... --platform-id universal-mac` for a lipo pair); enetxt and
datachannelxt local builds + their `tools/package-extension.py`; torrentxt
last (build + codesign + notarize - needs credentials). Then run S1 on the
Mac: that single hour is the first mac evidence for four members. Flips:
`sodiumxt/CLAUDE.md`'s mac ABI row and the section-2.1 gaps. Tick: row 24.

**The totals, for planning a calendar:** S1 ~1 h (+35 min stretch); S2 ~3 h
including setup; S3 ~3 h; S4 ~3 h; S5 ~1 h on Windows, ~4 h on a Mac (3 h
build + the S1 hour). Every session ends the same way: 4.1's copy-back for
each result, then ONE follow-up label pass covering exactly the items that
ran.

---

> ## The 2026-08-17 pass: THE LARGEST GREEN RUN THE PROJECT HAS HAD
>
> **Windows, x86_64, NT 10.0, OXT 9.6.3. 1,836 folded member checks, ZERO
> failures, 7 skips - every skip a live-transport or daemon leg that no
> single machine can run.** The previous best on record was 617 folded
> checks (2026-08-13). All six packaged extensions loaded at the exact ABI
> their guard expects: SodiumXT 9, TorrentXT 11, enetxt 2, DataChannelXT 1,
> CoinXT 6, Box2Dxt 4 (the last one READ, not inferred).
>
> | member | checks | member | checks |
> |---|---|---|---|
> | holde-em | 538 | torrentxt | 101 |
> | box2dxt | 374 | sodiumxt | 99 |
> | riptide | 338 | onionxt | 61 |
> | coinxt | 278 | datachannelxt | 26 |
> | | | enetxt | 21 |
>
> **`tests/preflight.livecodescript` ran first and did its job on its first
> outing** - six LOADED rows in about a minute, and the two script-layer SKIPs
> correctly explained as not-needed-for-the-paste. It was written the same day
> and had never been executed.
>
> ### What this pass proved for the FIRST TIME
>
> Everything below shipped between 2026-08-15 and 2026-08-17 and had never met
> an engine. All of it came back green:
>
> - **coinxt BIP-340 Schnorr and the BIP-341 Taproot tweak (ABI 6)** - all 19
>   published Schnorr vectors including the 10 negatives, and the wallet
>   vectors: key-path output key, script-tree root, the tweaked private key
>   signing for the tweaked public key, and `cxBtcAddressP2TR` confirmed still
>   NOT tweaking (the deliberate non-change that keeps existing calls
>   spendable).
> - **coinxt WIF** - all four framing legs plus the refusals, including the one
>   that matters: an xprv is refused on its payload LENGTH, not its version byte.
> - **SodiumXT ristretto255, ABI 8 AND ABI 9** - the mask/unmask roundtrip, the
>   batch over 3 points, `k*(P+Q) == k*P + k*Q` (the DLEQ-shaped identity), and
>   the failure the batch API exists to get right: one bad point fails the whole
>   batch, NAMING index 2 of 3.
> - **holde-em's Level 2 + Phase 5 DLEQ** - a wrong unmask refused INSTANTLY and
>   named, with no audit round; all five cheater bots detected and attributed.
> - **box2dxt at harness v29: 374/0.** Run 5 predicted "369/0, fully green"; the
>   extra five are the checks added on 2026-08-17. The prediction held.
>
> ### The five 2026-08-17 fixes, each confirmed by the check written for it
>
> This is the part worth reading, because each line is a defect found by
> READING and closed before an engine ever saw it:
>
> - **onionxt's loopback guard fail-open.** `ok  the guard refuses an empty host
>   (it used to accept one)`, and all eight socket-id fixtures parse correctly -
>   including `[::1:54321]` -> host `[::1]`, the bare-IPv6 shape that used to
>   yield EMPTY and be ACCEPTED by a guard its own comment calls
>   security-critical.
> - **torrentxt's three "untestable" refusal legs.** `btMoveStorage on a stale id
>   refuses, moving nothing`; `btSetFilePriorities on a stale id refuses`;
>   `btAddTorrentWithResume refuses garbage resume bytes` **`...and says why (the
>   shim ran, it did not short-circuit)`**. Writing real checks instead of
>   exemptions was the right call, and this run is the proof - plus `btAddMagnet
>   returns a handle`, the fourth.
> - **datachannelxt.** `dcSendText refuses an embedded NUL with -3`, the refusal
>   cleared the shim last-error, and the four stale-handle assertions now read
>   the exact `-2` rather than `< 0`.
> - **box2dxt's duck rebuild dropping the collision filter.** MASK, GROUP and
>   CATEGORY each survived the duck/stand rebuild, proven by three separate
>   landing outcomes.
> - **holde-em's host election.** `a SITTING-OUT seat is not electable (spec 9
>   live seats)` and `the sat-out key is gone from the candidate set entirely`.
>
> **And one the coverage ratchet found.** `ante: short SB posts from the
> post-ante stack (heHandStart P0 fix)` - `heHandStart` survived only inside a
> test LABEL, which is exactly the gap the string-blanking convention was built
> to expose on the day it was built. It is a real check now, and it passes.
>
> ### The hotseat session found a defect the gates could not
>
> **Three hands of real hotseat play, reported back as a transcript, and its
> third hand is poker-inconsistent**: heads-up, a 392 all-in called by a 2008
> stack, reported `pot 2400` for an awarded pot of **784**. Everything else
> about it was right - chips conserved, `settle-verified` passed, all three
> deals re-derived - and that is exactly why nothing caught it. The history
> line summed `handBy`, every seat's total COMMITMENT, and a bet nobody calls
> is RETURNED. The money was never wrong; only the number on screen was,
> inflated by precisely the 1616 that went straight back.
>
> Fixed the same day in `heAwardedPot` (extracted from a forty-line fold loop
> so it could be pinned at all), mirrored in `tools/fold-kat.py`, and pinned
> five ways in harness section 21 plus a new canned uncalled-bet session. A
> mutation test confirms the shape: with the old code restored, the stacks,
> conservation and settle-verified checks all still PASS and only the two pot
> assertions fire - which is the transcript's signature exactly.
>
> **It was not the only instance.** The repo's OWN canned ante session had
> reported `pot 9` since the day it was written, where the awarded pot is 8:
> the big blind's blind is uncalled by one chip when the small blind folds.
> Nothing pinned that figure either. Both are pinned now.
>
> The lesson is the one this tree keeps relearning from a different angle: the
> deltas reconcile under BOTH readings, so every check that existed - chip
> conservation, settlement re-derivation, the independent fold - stayed green
> over a wrong number. Only a human reading a real session noticed.
>
> ### What it did NOT close
>
> The 7 skips are the honest remainder and every one needs a resource this
> session did not have: riptide's anon onion service create + serving (2, tor);
> holde-em's live onion table, the three-machine oracle round, the
> onion-hosted oracle, the live timed table and the live tor redial (5). The
> ENet and DataChannel **async loopbacks** stay deliberately unfolded. Nothing
> here touches the two-machine legs (S3/S4) or the macOS/Windows-package gaps.

---

> ## The 2026-08-08 pass: what it closed
>
> **`tests/suite-selftest.livecodescript` ran green on a real engine with all six
> members installed — zero failures.** That was the suite's first runtime evidence.
> It closed inventory **item 1** (datachannelxt had no engine evidence at all; it now
> has a live loopback that negotiated, opened, and round-tripped byte-for-byte) and
> inventory **item 2** (coinxt's binding had never been loaded; it now loads and
> returns the pinned vectors byte-exact, closing coinxt phase 1). Both of the design
> bets coinxt was carrying came back good: **`UIntSize` works as a foreign RETURN
> type**, and **`MCDataGetBytePtr` marshals an empty `Data`** through a plain
> `Pointer`. Neither documented fallback was needed. It also promoted the
> cross-member compositions from "verified statically" to observed.
>
> **What it did NOT close, and why this runbook is still live.** The suite selftest is
> a *sampler* — roughly a dozen handlers per member, chosen as the headline paths and
> the cross-member seams. The deeper per-member harnesses were not run, so inventory
> **item 3** (coverage added after the earlier passes) is only partly retired, and
> items **4**, **5**, and **6** are untouched: they need a tor daemon or a second
> machine, and this run used neither. Sections 2-7 below still apply as written; work
> section 4 member by member and record only what your run actually exercised.

> ## The 2026-08-10 pass: the deep harnesses, and one red line
>
> **The folded suite harness ran with every member's own deep self-test included —
> 454 member-harness checks plus the core sampler — and exactly ONE check failed.**
> sodiumxt 68/68, onionxt 40/40, torrentxt 96/96, enetxt (sync half) 21/21,
> datachannelxt (sync half) 23/23, coinxt **205/206**, every cross-member seam and
> both live loopbacks green. That largely retires inventory item 3, and for coinxt
> it retires the phase-1/2 handler residual and answers both phase-2 marshalling
> bets on the side the code assumed (the C `int` flag marshals — 33 vs 65 came back
> distinct — and `Boolean` returns work: `cxVerify` answered both true and false).
>
> **The red line was a real fail-open, and no gate could have seen it.**
> `cxHdDerivePath(tNode, "m/")` returned the node unchanged instead of throwing:
> the engine ignores ONE trailing delimiter when counting items, so after
> `replace "/" with comma` the path "m/" counts as a single item and the level
> loop — where the empty-level check lives — never runs. The headless gate had
> that exact negative vector and passed it, because `lcs-interp.py` counted items
> with a bare Python `split()`, which sees two. The interpreter now models the
> engine's rule, the gate reproduced the engine's failure headlessly before the
> parser was touched, and the parser now refuses a trailing separator outright.
> The fix got its OXT pass the same day (next blockquote): "an empty level is
> refused" and "a trailing separator is refused" both came back green, on the
> real engine, from the folded harness.
>
> **The first paste of the night hit trap 5.1.1 exactly as written** — a live
> TorrentXT session from an earlier run made the probe SKIP TorrentXT and held UDP
> 27196 out from under the enet loopback. Quitting and relaunching OXT cleared
> both, and the second paste ran the full suite. The trap's remedy is confirmed:
> restart OXT before every paste.

> ## The 2026-08-10 re-run: ALL GREEN, and the embed proven
>
> **The self-contained harness — the folded deep self-tests plus the coinxt and
> onionxt script layers embedded in the paste itself — ran green end to end:
> 455 member-harness checks plus the whole core sampler and every cross-member
> section, ZERO failures.** sodiumxt 68/68, onionxt 40/40, coinxt **207/207**,
> torrentxt 96/96, enetxt (sync half) 21/21, datachannelxt (sync half) 23/23,
> both live loopbacks, the 60000-byte budget on both transports, and a clean
> teardown (`btStopSession` released THE session). The probe reported
> "CoinXT (script layer): present" from the paste alone — no `start using` step,
> so the stale-layer failure mode that cost the earlier re-run cannot recur.
>
> **What this run closed.** The trailing-separator fix is now an engine result
> ("an empty level is refused" / "a trailing separator is refused", both green),
> which closes coinxt phases 2, 3 and 4 outright — every one of its 65 public
> handlers has now executed on a real engine. Inventory **item 3 is CLOSED**
> (the post-pass additions to the sodiumxt, torrentxt and enetxt harnesses all
> ran, folded), and the **item-1 residual is closed at the synchronous level**:
> the suite harness calls all 31 public `dc*` handlers by name. What the folds
> deliberately leave standalone — the enet and datachannel member harnesses'
> own ASYNC loopbacks (the live `enHostStatus` / `dcSendText` /
> `dcBufferedAmount` halves) — is recorded in each harness's coverage note.
> What remains of this runbook is items **4, 5 and 6**: a live tor daemon and a
> second machine.

This runbook is ordered for **shortest feedback first**: the cheapest thing that can
disqualify an evening runs before the thing that takes an hour to set up.

- Section 1: what is unproven, and why each one matters.
- Section 2: install order and prerequisites (including the exact `torrc`).
- Section 3: the run order, and the paste-and-reopen procedure (given once).
- Section 4: what to record, and which claims each result unlocks.
- Section 5: known traps, so you do not rediscover them.
- Section 6: if it fails, what to capture so there is no second session.
- Section 7: the tick sheet.

---

> ## The 2026-08-14 unification: what it re-opens
>
> **Every demo stack and every pasteable harness was unified that day** — the
> UI kit moved to v2 (the card look) and every demo now carries it verbatim
> (`tools/check-ui-kit-drift.py` enforces adoption); the five harness windows
> share one carried scaffold (`tools/check-harness-scaffold-drift.py`); and
> each conversion also landed that stack's audit fixes (validated
> create/connect returns, watchdogs on silent waits, fail-closed probes,
> guarded teardown, version-guarded rebuilds). Two consequences for this
> runbook:
>
> 1. **A restyled stack is a re-opened stack.** Every converted file's
>    honesty label says "UI unified 2026-08-14; needs an OXT re-pass". The
>    LOGIC evidence recorded in the pass blocks above still stands for the
>    handlers it names — but the stacks as wholes (layout, builders, status
>    plumbing, the new watchdog paths) have not run since the restyle. The
>    next engine session should START by re-opening one converted demo per
>    member and confirming it builds its window and probes cleanly, before
>    working new legs.
> 2. **The paste artifacts behave the same, plus.** The harnesses gained a
>    Copy-results button (paste runs back verbatim - stop retyping), SKIP
>    counts in every summary line, and red/green/amber per-line coloring.
>    A rebuilt stack picks the new layout up automatically (version-guarded
>    rebuilds); a stack saved from an older layout rebuilds once on open.

## 1. What is unproven, and why it matters

### 1.1 The layer map

Every member is three layers, and they have very different evidence behind them:

| Layer | Who proves it | Reachable headless? |
|---|---|---|
| Native shim over the vendored library | the member's C/C++ smoke test under ASan/UBSan (+ TSan for datachannelxt), plus the golden/record/KAT harnesses | **Yes.** CI runs it on every touch. |
| Pure-compute script logic (base32, addresses, vectors) | `onionxt/tools/onion-kat.py`, `coinxt/tools/coin-kat.py`, the `record_golden_test.py` suites | **Yes.** |
| Cross-member handler names | `tools/check-handler-calls.py` (suite root) | **Yes**, names only. |
| **The `.lcb` binding and every `.livecodescript`** | **an engine, and nothing else** | **No.** This is tonight. |

`tools/check-handler-calls.py` is worth knowing about before you start: it already
proved that every `sx*` / `bt*` / `en*` / `dc*` / `ox*` / `oxh*` / `cx*` / `rs*` call
in the suite resolves to a handler that exists. So a failure tonight is very unlikely to be a
typo in a handler name; expect marshalling, ordering, and environment instead.

### 1.2 The honest inventory

**Proven already (do not re-litigate, but a regression here is a red flag):**

| Member | What is proven | Evidence |
|---|---|---|
| sodiumxt | shim vs libsodium | `sodiumxt/tests/sodium_smoke_test.c` under ASan/UBSan; and the `.lcb` is described as on-engine-verified in `coinxt/src/coinxt.lcb` (the `UIntSize`-as-parameter precedent) |
| torrentxt | shim vs libtorrent, rp1, record layout | `torrentxt/tests/torrent_smoke_test.cpp`, `rp1_integration_test.cpp`, `record_handle_test.cpp`, `bep44_golden_test.py`, `fileserver_golden.py` |
| enetxt | shim vs ENet, and **the script layer** | `enetxt/tests/enet_smoke_test.cpp`; `enetxt/CLAUDE.md` records: "The OXT runtime pass happened 2026-08-07: `tests/enet-selftest.livecodescript` runs green in OXT - all tests pass." |
| datachannelxt | shim vs libdatachannel | `datachannelxt/tests/datachannel_smoke_test.cpp`, green under **both** ASan and TSan |
| onionxt | **the core socket paths, on a real engine against a live tor daemon** | `onionxt/CLAUDE.md`, "Confirmed on-engine (promoted from `VERIFY:`)" items 1-7, plus the `oxh*` hosting layer |
| coinxt | the native hash surface | `coinxt/native/build.sh asan` self-test + `coinxt/tools/coin-kat.py` against public vectors |
| **cross-member** | **the four invariants that span two members** | `tests/cross-member-test.py` drives the built sodiumxt and torrentxt shims through ctypes and measures them: libsodium and libtorrent derive the **same** ed25519 public key from one seed; libtorrent's DHT secret key **is** SodiumXT's expanded key and **not** its `seed \|\| pk` one; libtorrent **verifies** a libsodium BEP44 signature and **refuses** one made for a different seq; `ENX_MAX_MESSAGE == DCX_MAX_MESSAGE == 60000`. |

> **What that last row buys you tonight.** The cross-member sections of
> `tests/suite-selftest.livecodescript` are the suite's headline claims, and they
> used to be entirely unproven. Most of what they assert is not a script question
> at all - "do two C libraries agree on a public key?" is answerable headless, and
> now it is answered. So those sections still need the engine, but for something
> **narrower**: the FFI marshalling and script plumbing that reach those
> libraries, not the cryptography underneath. If a cross-member check fails on the
> engine tonight, the crypto is already known-good, so look at the binding.

**NOT proven. This is the work.** Ranked by how much a pass buys you:

| # | Unproven thing | Why it matters | The label that says so |
|---|---|---|---|
| 1 | ~~**datachannelxt has never had an engine pass at all.**~~ **CLOSED 2026-08-08.** | The member now has engine evidence: `dcInit`, a stale-handle no-op, peer and channel creation, a live loopback that negotiated and opened both ends, a byte-for-byte payload round-trip, the `-4` refusal at 60001 bytes, a payload at the SCTP-negotiated cap, and `dcCleanup`. **Residual closed at the synchronous level 2026-08-10**, and **the async residual CLOSED 2026-08-15**: the member harness ran STANDALONE green end to end - a real SDP carrying candidates, offer/answer roles, gathering complete both peers, a selected pair, text and binary (embedded NUL included) byte-for-byte, and a cap-sized send. Nothing in the dc selftest is static anymore; what remains for this member is browser interop and a two-network call. | Labels updated in `datachannelxt/README.md`, `datachannelxt/examples/README.md`, `datachannelxt/docs/getting-started.md`, `datachannelxt/tests/datachannel-selftest.livecodescript`, and `datachannelxt/src/datachannel.lcb`. |
| 2 | ~~**coinxt's binding is brand new and has never been loaded.**~~ **CLOSED 2026-08-08 — and it closed coinxt phase 1.** | All five numbered questions in the `.lcb` header were answered, each on the side the code assumed: the module loads and binds resolve; the ABI guard holds (transitively — `sPrepare()` is the whole body of `cxCheckABI()` and every wrapper calls it); **`UIntSize` works as a foreign RETURN type**; **`MCDataGetBytePtr` marshals an empty `Data`** (`cxKeccak256("")` returned `c5d2…a470` instead of throwing); and the vectors are byte-exact. Neither fallback — `CUInt`, `optional Pointer` — was needed. **Residual CLOSED 2026-08-10:** the folded coin-selftest ran every public handler by name on a real engine — the 12 phase-1 stragglers (`cxCheckABI` by name at last), all 15 phase-2 curve handlers, and the whole of phases 3 and 4 — at 207/207 on the re-run. Nothing in coinxt is "verified statically" any more. | Labels updated in `coinxt/src/coinxt.lcb` (STATUS block), `coinxt/CLAUDE.md`, `coinxt/IMPLEMENTATION-PLAN.md`, and the root `README.md` row. |
| 3 | ~~**The selftests grew after their passes; the new sections are static-only.**~~ **CLOSED 2026-08-10.** | The folded suite harness ran every member's own deep self-test on a real engine, twice in one day, green: torrentxt's whole harness including the v9-v11 surface (`btDhtGetPeers`, `btAddInfohash`, `btMapPort`/`btUnmapPort`, the `btRp1*` quartet) at 96/96; enetxt's isolated teardown section (`enDisconnectNow` / `enResetPeer` / `enSetPeerTimeout` / `enSetHostBandwidth`) inside its 21/21 sync half; and the complete `sxSelfTest()` at 68/68, attached-signature form, keyed hashing and preset accessors included. The one extended section the folds exclude is the live `enHostStatus` pair inside enetxt's own async loopback. | Labels updated 2026-08-10 in `torrentxt/tests/torrent-selftest.livecodescript` + `torrentxt/README.md`, `enetxt/tests/enet-selftest.livecodescript` + `enetxt/CLAUDE.md`, and `sodiumxt/docs/api-reference.md`. |
| 4 | **onionxt Mode B (launching tor as a child process) has never run.** | It is the one remaining `VERIFY:` in an otherwise on-engine-proven member, and it is what a turnkey app would ship. | `onionxt/CLAUDE.md`, "Still `VERIFY:` (not yet exercised)" item 8: "`the processId` / `open process` for the optional Mode B tor launch (the default is assume-running)." Also the intro blockquote in `onionxt/docs/10-usage-guide.md` and `onionxt/docs/07-tor-lifecycle.md` Mode B. |
| 5 | **torrentxt's Tor path (Quick Share Model C) has never run against a daemon.** | It is a cross-member composition, so it is the one place three members must agree at runtime. | `torrentxt/examples/torrent-quickshare.livecodescript` (two places): "Every ox* handler is OnionXT's published ABI; this is verified statically ... and NEEDS an on-engine OXT pass with a running Tor daemon before any runtime claim." Register: `docs/ONIONXT-INTEGRATION-PLAN.md` section 12.3. |
| 6 | **Two-machine behaviour, for every member that has it.** enetxt's LAN chat, torrentxt's rp1 chat and Channels, datachannelxt's DHT chat. The riptide phase-2 propagation leg CLOSED 2026-08-13 (riptide-social on two machines, feeds both directions - which also means a signed BEP44 put propagated between real machines over the live DHT); the member demo legs remain. | Loopback proves the binding; only a second machine proves the transport. | `enetxt/CLAUDE.md`: "Still un-exercised: the LAN chat demo between two real machines." `torrentxt/examples/README.md`: rp1 chat "needs a live peer to show anything, so it is a two-machine test by nature." |

Items 1, 2 and 3 are **all closed**, residuals included: every member's deep
self-test has run on a real engine via the folded suite harness (the 2026-08-10
passes), and BOTH async-loopback residuals have since closed standalone - enetxt
2026-08-13, datachannelxt 2026-08-15. No member-selftest label stands anywhere.

**Offline work then added THREE new surfaces, and the 2026-08-12 Step-0 paste
(Windows x64, SodiumXT ABI 7 installed) closed all three in one run — the run
also proved the mingw64-built sodiumxt DLL loads and passes on a real Windows
engine:**

| # | New offline surface (added 2026-08-11) | What a green run proves | Status |
|---|---|---|---|
| 7 | **riptide phase 1** (`rs1rsSelfTest`, the 7th folded member) | the `RIPTKEY1` Argon2id-sealed seed, the KDF subkey tree, handle <-> `.onion` both ways, the `RSH1`/`RSP1` wire formats with strict parse and the tamper-evident post chain | **CLOSED 2026-08-12** (Windows x64): 89/89, 0 skipped, hasSha3 true |
| 8 | **coinxt phase 5 transactions** (`stRunTransactions`) | the BIP-143 native-P2WPKH signed tx byte-for-byte (both sighash algorithms + witness + txid), the EIP-155 spec tx, and the EIP-1559 typed tx. Also EXECUTED headlessly (`check-script-vectors.py`, 251 checks) - which caught and fixed a would-be-red line: `cxBtcTxEncode` refused the reference tx because its trailing-empty scriptSig collapses under the engine's trailing-delimiter chunk rule | **CLOSED 2026-08-12**: coinxt 230/230, the signed tx byte-for-byte on engine, both new refusals firing |
| 9 | **onion offline-address emission** (`oxAddressFromPublicKey` / `oxIsValidAddress`) | now that SodiumXT ABI 7 ships `sxSha3_256`, the checksum works: a 32-byte key renders a real `<56>.onion`, and a tampered address is refused | **CLOSED 2026-08-12**: real onions re-encoded byte-exactly, tamper refused, `offlineAddress` true (43/43) |

**One surface was added after that run and has now received its engine pass:**

| # | New surface | What a green run proves | Status |
|---|---|---|---|
| 10 | **riptide phase 2, the live feed layer** (inside `rs1rsSelfTest`, no extra step: the folded live-feed section drives the suite's own session) | the pure-script BEP44 buffer matches `btDhtBep44SignBuf` byte-for-byte; `rsPublishImmutable`/`rsPublishPost` return the oracle's pinned targets (libtorrent's SHA-1 agrees); `btDhtPutSigned` ACCEPTS `rsPublishHead`'s SodiumXT signature over the script-assembled buffer; the lookups are accepted; and the ingest verifiers pass/refuse their synthetic golden events. NOT covered by one machine: propagation - phase 2's done-criterion (a second machine walks the chain), which then CLOSED 2026-08-13 via the riptide-social two-machine run (item 6's riptide leg) | **CLOSED 2026-08-12**: riptide 133/133, 0 skipped; canonical buffer, real-session puts/requests, and ingest verifiers all green; propagation followed 2026-08-13 |

What remains is entirely environmental: items **4 and 5 need a live tor daemon**
(one evening with `ControlPort 9051` covers both), and item **6 needs a second
machine** for its member-demo legs. The riptide legs have been closing steadily:
propagation 2026-08-13 (the suite's first two-machine result), media and
both-ways DMs 2026-08-15. The riptide phase 5-7 legs (the dc call, the LAN
mesh, the anon persona over Tor) are inventoried below since 2026-08-15 (rows
16, 17 and 19) - `riptide/docs/two-machine-runbook.md` is their script,
written for exactly these sessions - and the sparse-access session plan at the
top of this runbook is the scheduler for all of it.

**The 2026-08-14/15 builds added the surfaces below (rows 11-24; rows 25-32 were
added later, and the table now runs 11-32).** They were ALL OPEN when this
paragraph was written. They are not now: the 2026-08-17 Windows blockquote above
closed rows **11, 12, 15, 25, 26, 27, 30 and 32** in one run, and each of those
rows carries its dated annotation in place.
Each row names the session type that closes it; the plan at the top orders the
work inside each session. Row 21's #31-#33 are the
`docs/ONIONXT-INTEGRATION-PLAN.md` section-12.3 register's own numbering,
kept as pointers so the same fact is never book-kept twice:

| # | New surface | What a green run proves | The label that says so | Session |
|---|---|---|---|---|
| 11 | ~~**sodiumxt ristretto255** (ABI 8)~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): "the mask/unmask roundtrip, the batch over 3 points, `k*(P+Q) == k*P + k*Q` (the DLEQ-shaped identity), and the failure the batch API exists to get right: one bad point fails the whole batch, NAMING index 2 of 3" - the blockquote above, whose member table records sodiumxt at 99 checks. The ABI seen was **9** (its own line: "SodiumXT 9"), so the section ran at ABI 9 rather than at the ABI 8 this row was written against. Row kept for the record: **sodiumxt ristretto255** (ABI 8, built 2026-08-15; C KATs green under ASan/UBSan, cross-checked against the independent RFC 9496 reference) | the five `sxRistretto*` handlers marshal on a real engine (Data in and out, the Boolean predicate, throw-as-detection) - the suite paste's "ristretto255 (ABI 8)" section runs instead of SKIPping | `sodiumxt/docs/api-reference.md`, the ristretto section ("verified statically; needs an OXT pass") and the status blockquote's "one exception" note; also holde-em's Workstream U "still open" line | **CLOSED 2026-08-17** |
| 12 | ~~**coinxt WIF**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): "all four framing legs plus the refusals, including the one that matters: an xprv is refused on its payload LENGTH, not its version byte" - the blockquote above, whose member table records coinxt at 278 checks, at CoinXT ABI **6**. Row kept for the record: **coinxt WIF** (`cxWifEncode` / `cxWifDecode`, built 2026-08-15 - the last two coinxt handlers with no engine run) | the three-argument call shape, the boolean flag both directions, the array return, and both refusal paths | `coinxt/README.md` (the status sentence and the WIF paragraph), `coinxt/CLAUDE.md` (the WIF entry), `coinxt/docs/api-reference.md` (the intro and the WIF note) | **CLOSED 2026-08-17** |
| 13 | ~~**riptide 0.9.0 compute additions in the suite paste**~~ **CLOSED 2026-08-20** (Windows, suite paste, 1981/0/1). riptide folded at **338 passed / 0 failed / 2 skipped**, and all three named surfaces ran green inside it: the phase-6 LAN sync-records section (drafts, feed state, presence, media handoff), the phase-7 serving seams - `rsAnonFeedPage` ("the anon feed page bytes match golden"), `rsAnonPrekeyBody` ("the GET /prekey body matches golden") and `rsAnonAcceptDm` ("accepts the hex-posted sealed intro", plus its five refusal legs) - and **all three `rsBytesAreUtf8` checks that were RED on 2026-08-15**, now "refused, not thrown" in the challenge, the response and the welcome. The 2 skips are the live-tor anon-service legs, which were never this row's criteria | the compute halves run green on an engine; the LIVE criteria stay rows 16, 17 and 19 | `riptide/CLAUDE.md`, the phase-6 and phase-7 bullets (their compute-half sentences only) | S1 |
| 14 | **holde-em deal-path re-pass** (the fold's two rewrites: `heXorSeedsHex` lost its ignored `repeat ... step 2`, `heDeckFromStreamKey` lost its throw-in-catch) | the rewritten handlers match the KAT pins on-engine - and settles which stream the PRE-fold on-engine runs dealt from | `holde-em/CLAUDE.md`, the fold blockquote's "needs an OXT re-pass" sentence | S1 |
| 15 | ~~**holde-em Level 2 compute**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): the blockquote's "holde-em's Level 2 + Phase 5 DLEQ - a wrong unmask refused INSTANTLY and named, with no audit round", inside holde-em's 538 folded checks with zero failures. Row kept for the record: **holde-em Level 2 compute** (harness section 16, `he1heTestLevel2Run`, behind the ABI-8 probe). **CORRECTED 2026-08-17: it IS in the suite paste** - holde-em folded as the ninth harness on 2026-08-16 (commit `7f55839`) and the paste now carries **380** `he1*` handlers, so this row runs inside row 1 and costs no separate launch. The "STILL NOT in the paste / run it as its own paste" text that stood here was written before the fold and would have spent an OXT launch re-pasting a 15k-line stack for a section already on screen. **The standalone paste is still wanted - but by row 4, for hotseat PLAY, not for this harness**: `check-suite-selftest.py`'s check 7d deliberately keeps `heRunSelftest` UNREACHABLE in the fold (it drives an overlay, the clipboard and `msg`), so the folded run exercises the compute and never the game | the `sx*` call shapes the L2 algebra assumes, and the 24 pinned `l2_*` values on-engine (the 4f deal-time budget stays orchestration-era work) | `holde-em/IMPLEMENTATION-PLAN.md`, the Phase 4 blockquote; `holde-em/CLAUDE.md`, the L2 entry | **CLOSED 2026-08-17** |
| 16 | **riptide phase 5** - the dc call plus the spec-6.2 typing lane (both demo wiring, never run) | `CALL CONNECTED` on both sides, a `typ srflx` `via` line across two networks, the typing indicator appearing and clearing | `riptide/CLAUDE.md`, the phase-5 bullet; the script is `riptide/docs/two-machine-runbook.md` phase 5 | S3 |
| 17 | **riptide phase 6** - the LAN mesh live: the welcome round, the draft-appears done-criterion, the stranger test | mutual admission, drafts converging both directions, presence expiring, the stranger refused with nothing crossing | `riptide/CLAUDE.md`, the phase-6 bullet; the script is the two-machine runbook phase 6 | S3 |
| 18 | **holde-em 2d** - online Level 0 play, multi-machine (written v0.17.0, netsim-pinned on one machine) | a multi-hand rp1 session across real machines with receipts matching on every seat | `holde-em/IMPLEMENTATION-PLAN.md`, the 2d status line ("needs the multi-machine OXT pass") | S3 |
| 19 | **riptide phase 7** - the anon persona live over Tor (the 8.2/8.3 serving built 2026-08-15) | single-machine half: the onion reachable, the feed page + `/prekey` + `/dm` on a live tor; finishing half: the anon delivery from a second machine and the zero-`bt*` trace | `riptide/CLAUDE.md`, the phase-7 bullet; `riptide/docs/two-machine-runbook.md`, the phase-7 intro | S2 + S4 |
| 20 | **holde-em 2f onion tables** (v0.20.0, built 2026-08-15) | single-machine half: the bring-up states and the offline-derived address matching `oxServiceAddress` at publish; the exit: a multi-hand onion table session on two machines with a running tor | `holde-em/CLAUDE.md`, the 2f entry; `holde-em/IMPLEMENTATION-PLAN.md`, the 2f status | S2 + S4 |
| 21 | **Quick Share Channels anon, #31 / #32 / #33** - POINTERS ONLY: built 2026-08-15, registered in `docs/ONIONXT-INTEGRATION-PLAN.md` section 12.3, and ticked THERE per 4.7's rule | #31: the single-machine ON / OFF / tor-absent behaviour; #32: the card-only anon follow with the DHT off; #33: the onion-only release download with a clean capture | the three 12.3 register rows themselves | #31 S2; #32/#33 S4 |
| 22 | **nocloud HTTP-host checklist** (`nocloud/docs/oxt-pass-checklist.md`: routes, headers, conditional GET, CORS, the editor, shutdown - over BOTH transports) | per that file's own action -> expected lines; it is its own record sheet | the checklist's intro paragraph ("verified statically; needs an OXT pass") | web-link half S1 stretch; Tor half S2 |
| 23 | **sodiumxt mingw DLLs' Windows re-proof** (`x86_64-win32` + `x86-win32`; the pair owing the pass is now the ABI-10 one cross-built 2026-08-23, which superseded the ABI-9 pair of 2026-08-15 this row was written against - the row survives every rebuild because the debt does; the 2026-08-12 ABI-7 pass is the precedent) | the DLLs load and the full SodiumXT section - SHA3, ristretto AND the ABI-10 ChaCha20 xor - runs green on a real Windows engine | the "needs its Windows engine pass" notes on the two Windows rows of `sodiumxt/CLAUDE.md`'s ABI table | S5 |
| 24 | **the macOS builds** - sodiumxt `universal-mac` lipo ABI 6 -> **10** (was written as 6 -> 8 before the 2026-08-15 DLEQ bump, then 6 -> 9 before the 2026-08-23 ChaCha20 bump; the gap grows every bump this row goes unbuilt, and it BLOCKS every crypto-dependent test on a Mac); first mac dylibs for torrentxt / enetxt / datachannelxt / coinxt (coinxt is now ABI 6) | a Mac stops being the one platform that cannot run the suite paste; S1 on the Mac afterwards is four members' first mac evidence | `sodiumxt/CLAUDE.md`, the mac ABI row; the section-2.1 platform table's gaps | S5 |
| 25 | ~~**sodiumxt ABI 9 - the DLEQ/batch algebra**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): the blockquote's ristretto bullet says "ABI 8 AND ABI 9" and names the batch's atomic-failure contract observed from script - one bad point failing the whole batch, NAMING index 2 of 3, which is exactly what this row asked for. **This row has no tick line**: the ADDED block is scoped to rows 11-24 by its own header, and rows 25-32 were never given lines. Row kept for the record: **sodiumxt ABI 9 - the DLEQ/batch algebra** (`sxRistrettoAdd` / `Sub` / `ScalarMultBase` / `ScalarMultBatch` / `ScalarAdd` / `ScalarMul`, built 2026-08-15). Row 11 covers ABI 8's five handlers ONLY; these six are a separate never-marshalled surface, and holde-em's Phase 5 proofs sit directly on them | the six handlers marshal on a real engine - in particular `sxRistrettoScalarMultBatch`, whose whole point is ONE FFI crossing for all 52 card points, and whose atomic-failure contract (any bad element fails the call with a 1-based index, nothing usable in out) has never been observed from script | `sodiumxt/docs/api-reference.md`, the ABI 9 section; `sodiumxt/CLAUDE.md`'s ABI table row for 9 | **CLOSED 2026-08-17** |
| 26 | ~~**holde-em 4d/4e - void-and-audit + the cheater bots**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3) - with the two halves carrying DIFFERENT strengths of evidence, and that difference is the point. The 4e half is named outright by the blockquote: "all five cheater bots detected and attributed". The 4d void-and-audit half is NOT named there; what stands behind it is that harness sections 18-19 ran inside holde-em's 538 folded checks with zero failures, which is an INFERENCE from the member total rather than a line of the record. No tick line (see row 25). Row kept for the record: **holde-em 4d/4e - void-and-audit + the cheater bots** (v0.22.0, built 2026-08-15; harness sections 18-19) | the void-and-audit state machine runs on-engine: a bad shuffle/unmask step voids the hand, bets return, and the mandatory full-reveal audit NAMES THE SIGNER of the first bad step. The five scripted attacks (deck-stacker, duplicate-point shuffler, rollback replayer, wrong-scalar unmasker, deal staller) are each detected and correctly attributed | `holde-em/IMPLEMENTATION-PLAN.md` Phase 4d/4e blockquotes; `holde-em/CLAUDE.md` v0.22.0 entry | **CLOSED 2026-08-17** (4e named; 4d inferred) |
| 27 | ~~**holde-em Phase 5 - Chaum-Pedersen DLEQ proofs**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): "a wrong unmask refused INSTANTLY and named, with no audit round" - which is this row's own done-criterion, in the blockquote's words. No tick line (see row 25). Row kept for the record: **holde-em Phase 5 - Chaum-Pedersen DLEQ proofs** (v0.22.0; derandomized nonce, domain-tagged Fiat-Shamir, batch verification, soundness pinned negatively) | on a `dleq=1` table a wrong unmask step is refused INSTANTLY rather than costing a void-and-audit round - the whole point of the phase - and forged proofs still verify false on a real engine | `holde-em/holdem-spec.md` 7.4; `holde-em/CLAUDE.md` Phase 5 entry | **CLOSED 2026-08-17** |
| 28 | **holde-em 2e liveness** (v0.23.0+, built 2026-08-16: act timers + time-bank on the signed cfg, sit-out/return, late-join seating, bounded onion redial under the election watchdog) | single-machine half: the pure prescriptions, the wire round-trips, and harness section 20. What only a TIMED MULTI-MACHINE session can prove: a seat really timing out on wall clocks, the bank visibly arming once per hand, two misses auto-sitting a seat out, a late joiner seated at a hand boundary reaching identical fold state, and - after the 2026-08-16 review fixes - that a dial failure mid-redial still lets the election CONCLUDE, and that a parked table resumes when a seat returns | `holde-em/CLAUDE.md` v0.23.0/v0.24.0 contracts; `holde-em/IMPLEMENTATION-PLAN.md` 2e completion note | S1 for the static half; **S3/S4** for the timed session |
| 29 | **the committed-binary execution lanes** (`native-coinxt.yml` since Phase 4, `native-sodiumxt.yml` since 2026-08-16) | NOTHING on an engine - this row is here so the pass does not re-prove it by hand. CI now dlopen()s the COMMITTED Linux libraries and drives coinxt's published vectors + `cnx_memzero`, and sodiumxt's RFC 9496 [1..3]B, group law, scalarmult, batch and point validation. So on Linux the blobs you install are executed artifacts, not merely hashed ones. Windows and macOS blobs get no such lane and remain rows 23 and 24 | `coinxt/CLAUDE.md`, `sodiumxt/CLAUDE.md` (the 2026-08-16 entries) | n/a - read before planning S5 |
| 30 | ~~**coinxt ABI 6 - BIP-340 Schnorr + the BIP-341 Taproot tweak**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): "all 19 published Schnorr vectors including the 10 negatives, and the wallet vectors: key-path output key, script-tree root, the tweaked private key signing for the tweaked public key, and `cxBtcAddressP2TR` confirmed still NOT tweaking". The FFI shapes this row asked about are recorded in `docs/OXT-ENGINE-NOTES.md` section 4 with 2026-08-17 as their first-proven date: an empty `Data` in an OPTIONAL argument slot, the three-argument foreign call, and an array return read back by name. No tick line (see row 25). Row kept for the record: **coinxt ABI 6 - BIP-340 Schnorr + the BIP-341 Taproot tweak** (built 2026-08-16 on a second vendored library, upstream bitcoin-core/secp256k1; 19 published BIP-340 vectors incl. 10 negative and 14 BIP-341 wallet vectors green in CI, ASan clean) | the script layer marshals on a real engine - specifically `cxSchnorrSign`'s three-argument shape, an empty `Data` reaching the shim as length 0 in an OPTIONAL slot (proven for an empty INPUT in 2026-08-08, never for an optional argument), `cxSchnorrVerify`'s Boolean in both directions, and `cxTaprootTweak`'s array return read back by name. Also that `cxBtcAddressP2TR` and `cxBtcAddressP2TRFromInternal` really do differ on the same 32 bytes - the double-tweak trap this design exists to avoid | `coinxt/docs/api-reference.md` ABI 6 section; `coinxt/CLAUDE.md`'s dated rule-change entry | **CLOSED 2026-08-17** |
| 31 | **box2dxt as the eighth folded harness** (2026-08-16). The suite paste grew from ~13.7k to **20,616 lines** and now carries box2dxt's harness plus the b2k Kit as a fourth embedded script layer; suite coverage went 411/429 to **724/742**. Read this BEFORE planning S1: the paste is half again as large. **CORRECTED 2026-08-19: this row's "372 of its assertions have never run" is SUPERSEDED, and the stale claim misled further than the stale number did.** box2dxt HAS run folded, green: **374/0 at harness v29** in the 2026-08-17 Windows pass recorded in the blockquote above, and **373/1 at v29 on Linux 2026-08-18** - and that one failure was the HARNESS being wrong about the engine, not the Kit (`playLoudness` readback; `docs/OXT-ENGINE-NOTES.md` 5.4). The harness is at **v30** now. Its own header records 375 where v29 had 374 - one assertion added when the playLoudness check became two self-diagnosing assertions plus a printed observation (commit `597ce0c`: one `stAssert` removed, two added in `stTestEngineContracts`). That 375 was what the HEADER RECORDED and not an observed result until **2026-08-20, when v30 ran folded on Windows at 375/0** - the header's number and the engine's now agree, and `playLoudness` reported `Win32: 24->24, 73->73` with the readback EXACT, which is the engine note 5.4 behaviour the two new self-diagnosing assertions were written to name | that box2dxt's 50 harness handlers and its full assertion set run green folded at v30 - and the operative instruction is that the next pass **RECORDS the v30 total, it does not match a number**: neither 372 nor 374 is the expectation, and a delta against either is not a regression. Including 13 NEW 'Kit API coverage' sections written in one pass against a member whose own ledger warns to expect first-contact arithmetic errors, so treat a failure there as suspect-the-test first. Also that the Kit's message path works: `b2kFell` / `b2kSensorEnter` / `b2kContact` are dispatched by LITERAL name and are the fold's only unprefixed handlers - if those three report zero events, the prefixing is wrong, not the dispatcher | `box2dxt/CLAUDE.md` fold record; `tools/check-suite-coverage.py` (the b2k row, and the 245-handler open item beside it) | S1 |
| 32 | ~~**holde-em as the NINTH folded harness**~~ **CLOSED 2026-08-17** (Windows x86_64, NT 10.0, OXT 9.6.3): the fold COMPILED - 1,836 folded member checks across nine harnesses with ZERO failures, `he1heSelfTest` reporting readably at **538** checks in the per-member table, and no stray timer symptom in the cross-member async phase. No tick line (see row 25). Row kept for the record: **holde-em as the NINTH folded harness** (2026-08-16). The suite paste grew from 20,616 to **34,130 lines** and 928 to **1,308 handlers**; suite coverage is unchanged at **724/742** because holde-em deliberately has no row in that ratchet (its game and its harness are one file, so any scan measures the game naming its own API - the numbers are beside `tools/check-suite-coverage.py`'s member list). Read this BEFORE planning S1: the paste is two-thirds larger again, and ONE compile error takes all 34k lines down | that the fold COMPILES at all - this is the first paste of it, and it is the only fold carrying a whole application rather than a test file. Then that `he1heSelfTest` reports readably: the core needs EXACTLY ONE line of its report to parse as `n passed, m failed`, which was verified statically against every string literal in the file but never on an engine. Then its 21 sections themselves - the evaluator, betting and side pots, the deal ladder to Level 2 and the DLEQ audit, the signed wire, and the netplay/oracle/liveness loopbacks - none of which has run inside another paste. Watch specifically for a stray timer: the sweep is widened to the `he1` prefix by the fold, and if anything holde-em armed is still ticking it will fire during the cross-member async phase, after the member has already reported | `holde-em/CLAUDE.md` fold record; `tools/check-suite-selftest.py` checks 7d/7e (the reachability and guest-behaviour invariants) | **CLOSED 2026-08-17** |
| 33 | **nostrxt as the TENTH folded harness, and the whole member's first engine contact** (2026-08-23). The paste grew to carry the nx* core as a fifth embedded script layer plus the folded 17-section harness (prefix `nx1`); suite coverage went 724/742 to **829/843** with ZERO new exemptions. Nothing in this member has ever met an engine | that the fold COMPILES (one bad line takes the whole paste); that `nx1nxSelfTest` reports readably; then the sections themselves - the canonical serializer producing the oracle's exact bytes (event ids depend on it), the JSON parser's refusals, bech32/NIP-19 against the published examples, the NIP-44 schedule against the official vectors, the MAC-before-cipher order and the `sxChaCha20IetfXor` seam (round-tripping the official payload vector against an ABI-10 SodiumXT, asserting the fail-closed capability error against an older one - the branch the section takes IS a finding, record it), websocket framing math, and every fail-closed argument path. The signing sections need CoinXT installed (they SKIP otherwise, counted); the nxr* relay section SKIPS here BY DESIGN (the layer is not in the paste; its offline paths run in the demo). UTF-8 event C is a genuine engine question: it measures `textDecode` round-trip fidelity for non-BMP content, and a FAIL is a real finding about engine text handling, not noise | `nostrxt/CLAUDE.md`, the As-built notes ("nothing has met an engine yet"); `nostrxt/README.md`, the status section; the root `README.md` release-matrix row | S1 |
| 34 | **the nostrxt live-relay RECEIVE leg** (`nostrxt/examples/nostrxt-demo.livecodescript`: subscribe, the EVENT/EOSE/CLOSED/NOTICE callbacks, NIP-42 auth). **Half of this row closed 2026-08-24**: the demo opened wss://nos.lol, handshook, signed a kind-1, published it and got its ok-true back - so connect/handshake/publish/confirm is done, and that run was also the suite's first `open secure socket` (now `docs/OXT-ENGINE-NOTES.md` **6.8**). What is left is everything INBOUND, plus two things the successful run could not measure: what the engine does with an INVALID certificate (it met an ordinary public host, so verification is unproven in BOTH directions - point it at a self-signed or expired host and record the answer), and how a TLS failure is delivered. Note the inversion: **ws:// is now the unproven form**, so a local relay (e.g. nostr-rs-relay on loopback) is no longer the safe warm-up - it is its own separate leg, with a NEW resource, a relay binary, the way S2 needs a tor binary | a REQ answered with EVENTs that VERIFY through the callback; EOSE; a NOTICE and a CLOSED observed; the NIP-42 challenge/auth round trip; then, separately, the bad-certificate observation recorded in `docs/OXT-ENGINE-NOTES.md` 6.8 WHATEVER it turns out to be | `nostrxt/src/nostr-relay.livecodescript`, the STATUS header and the narrowed VERIFY block at the `open secure socket` call; `nostrxt/docs/05-relay-client.md`; `nostrxt/docs/07-capabilities-required.md` gap #2 | one machine + a public wss relay (the proven path); + a local relay daemon for the ws:// leg; + a deliberately bad-certificate host for the TLS question |

---

## 2. Install order and prerequisites

### 2.1 Check your platform FIRST

Committed binaries are uneven, and this decides what is even runnable tonight.
`ls <member>/src/code/` is the ground truth:

| Member | Committed platforms | If your platform is missing |
|---|---|---|
| sodiumxt | all five (`x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`, `universal-mac`) + `MANIFEST.sha256` — but the mac dylib is **ABI 6, four behind the ABI 10 code**: see the warning under this table before testing sodiumxt on a Mac | n/a on Linux/Windows; on macOS the dylib needs its `lipo` rebuild |
| torrentxt | four (Linux x64/x86, Windows x64/x86); `universal-mac/` holds only a `README.md` (**no macOS dylib**) | dispatch `release-binaries.yml` (its `mac-lipo` job builds this member's universal dylib since 2026-08-23) or build it: `torrentxt/docs/building.md`, then `torrentxt/tools/package-extension.py` |
| enetxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | dispatch `release-binaries.yml` (universal mac lane since 2026-08-23) or build locally, then `enetxt/tools/package-extension.py` |
| datachannelxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | dispatch `release-binaries.yml` (its `mac-lipo` job, since 2026-08-23) or build locally, then `datachannelxt/tools/package-extension.py` |
| box2dxt | all five (`x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`, `universal-mac`) + `MANIFEST.sha256` - the only member whose committed mac dylib is not knowingly ABI-stale, and it is a genuine two-architecture Mach-O (x86_64 + arm64). Since 2026-08-23 `tools/check-binary-freshness.py` READS this dylib on every gate run: 370 exports, byte-identical in both slices, matching the shim's 370 definitions and the `.lcb`'s 370 binds, with ABI 4 decoded from both slices' machine code - so the file is verified the way the ELF/PE binaries are. What is still true: **no Mac has ever loaded it**; that half needs an OXT pass on a Mac | n/a on Linux/Windows. On macOS it is the one member worth TRYING - `put b2Version()`, which the 2026-08-17 Windows preflight READ as 4 rather than inferring it - but treat a throw there as unproven-binary, not as a member bug; the rebuild is `box2dxt/docs/building.md` then `box2dxt/tools/package-extension.py` |
| onionxt | n/a, pure LiveCodeScript | n/a |
| coinxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | dispatch `release-binaries.yml` (universal mac lane since 2026-08-23, both slices KAT-driven) or build it: `cd coinxt && sh native/build.sh pack` puts it straight into `src/code/`; see 2.4 |

**On Linux (x64 or x86) and on Windows (x64 or x86), every member's library is
already in the repo** — the 2026-08-08 release run committed all four platforms for
all five native members, which is what made that day's suite pass possible on a
stock checkout.

> **ON A MAC, SODIUMXT WILL THROW ON EVERY CALL, AND THAT IS NOT A BUG TO REPORT.**
> The committed `universal-mac` dylib is at **ABI 6**; `sodium.lcb` declares
> `kSXTABIVersion is 10` and `sPrepare()` checks **strict equality**, so every `sx*`
> handler throws
> `"SodiumXT: ABI mismatch - the native sodium library does not match this extension"`
> before it does any work. It is not a broken build and not a bad install: the dylib
> is simply four ABI bumps stale (7 added the AEAD surface, 8 the ristretto255
> group, 9 the DLEQ/batch algebra, 10 the raw ChaCha20 xor), because macOS was the one platform CI could not
> build for and the `lipo` build was done by hand (since 2026-08-23
> `release-binaries.yml` carries universal mac lanes for all six members, so the
> unblock is a workflow dispatch; the committed dylib stays ABI 6 until one runs). Consequences for a pass on a Mac:
> **every sodiumxt test, and everything downstream of it — the sealed lanes, the
> Level 0 committed shuffle, all of holde-em's online and Level 2 play, riptide's
> whole crypto layer — cannot run there at all.** Do not spend a Mac session on
> them; record "blocked: sodiumxt universal-mac at ABI 6" once and move to what a
> Mac can actually prove (the pure-script layers, onionxt, and the UI passes). The
> unblock is inventory row 24, and it is a build, not a debug.

**macOS is the gap for four of the six.** TWO members ship a `universal-mac` dylib:
sodiumxt's is knowingly **ABI 6**, four behind the ABI 10 code (the warning below),
and box2dxt's is - since 2026-08-23 - READ and verified by `check-binary-freshness.py`
on every gate run (370 exports identical in both slices, ABI 4 decoded from both
slices' machine code), though no Mac has ever loaded it. torrentxt, enetxt,
datachannelxt and coinxt need a mac dylib built (codesign/notarize is NOT a gate on
that: unsigned distribution was accepted 2026-08-23). Until 2026-08-23 CI deliberately built no macOS lane — `macos-15`
runners are arm64-only, so a naive automated lane would emit a thin dylib and silently
regress sodiumxt's genuine two-architecture binary into one that fails on every Intel
Mac. `release-binaries.yml` now carries universal mac lanes for ALL SIX members (both
slices asserted at birth; torrentxt and datachannelxt via a two-slice-lipo job) — but
no dispatch has run them yet, so on a Mac TODAY, still expect to build (or dispatch)
before you can run any member but sodiumxt.

### 2.2 The dependency graph (this is the install order)

```
   sodiumxt   (no dependencies; install FIRST, everything else composes it)
      |
      +---> onionxt        needs sodiumxt ABI >= 6, AND a local tor daemon
      |                    with the CONTROL PORT enabled
      |
      +---> torrentxt      independent of sodiumxt to RUN, but its demos use
      |        |           sodiumxt for optional encryption (passphrase lock,
      |        |           private channels) and onionxt for the Tor mode
      |        |
      |        +---> datachannelxt's flagship demo (datachannel-dht-chat)
      |              needs TORRENTXT installed for its DHT signaling
      |
      +---> enetxt         fully independent; nothing composes it
      +---> datachannelxt  independent to RUN; the flagship demo needs torrentxt
      +---> coinxt         independent; nothing composes it yet
      +---> box2dxt        fully independent; nothing composes it. Its b2k Kit
                           is pure script over this one binding
```

Install in this order:

1. **sodiumxt** (`org.openxtalk.library.sodium`). Everything that composes anything
   composes this one.
2. **torrentxt** (`org.openxtalk.library.torrent`).
3. **enetxt** (`org.openxtalk.library.enet`).
4. **datachannelxt** (`org.openxtalk.library.datachannel`).
5. **onionxt** (`org.openxtalk.library.onion`). Not a packaged extension: copy
   `onionxt/src/onionxt.livecodescript` and `onionxt/src/onion-httpd.livecodescript`
   into your app and `start using` them - or, for testing, just open the demo:
   `onionxt/examples/onionxt-demo.livecodescript` and
   `onionxt/examples/onion-httpd/spike.livecodescript` each CARRY those libraries
   embedded, so they are one paste with no wiring. (Before 2026-08-17 those were
   separate generated `*-standalone` twins; `tools/sync-demo-embeds.py` embeds in
   place instead, so there is one file to open, not two. It is for whoever EDITS a
   part, not for the tester - see `onionxt/docs/10-usage-guide.md`.) If all you are
   running is the SUITE harness, skip this step: it embeds the whole ox* surface
   itself.
6. **coinxt**: see 2.4.
7. **box2dxt** (`org.openxtalk.box2dxt` - note the shape: it is NOT
   `org.openxtalk.library.*` like the other five, so copy it from
   `box2dxt/src/box2dxt.lcb` rather than pattern-matching the neighbours). This
   is the SIXTH packaged extension, and it is the one this list used to omit:
   section 7's row 0 requires six, and the section-7 preflight block expects a
   Box2Dxt ABI line, so a tester following only steps 1-6 arrived at the tick
   sheet a member short.

Packaged members install through `Tools > Extension Manager` like any OXT extension;
the native library resolves automatically from inside the extension. No loose library,
no `sudo`, no `LD_LIBRARY_PATH`, no rename.

**Verify each one loaded before you go further.** From the message box:

```
put sxVersion()          -- sodiumxt, e.g. "SodiumXT 0.1.0 (libsodium 1.0.20)"
put btStartSession()     -- torrentxt: a handle > 0. Then btStopSession it.
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put oxVersion()          -- onionxt (after start using)
put cxKeccak256Len()     -- coinxt, if you got it installed: prints 32
put b2Version()          -- box2dxt: prints the shim ABI, 4 on this tree
```

`cxCheckABI` is deliberately NOT in that list, and the reason is a kind mismatch worth
knowing: it is declared `returns nothing` (`coinxt/src/coinxt.lcb`), so `put
cxCheckABI()` prints a blank line and proves nothing. Call it as a **command**
(`cxCheckABI` on its own line); it THROWS on ABI skew, so silence is the pass. Then use
`cxKeccak256Len()` as the probe that actually prints, because it returns a value **and**
is the first exercise of the novel `UIntSize` return type (section 4.6, item 3).

A `handler not found` here means the extension is not installed or not loaded, and
nothing downstream will work. Fix it now, not during a demo.

### 2.3 Tor: the daemon and the exact torrc

onionxt talks to a **locally running** tor daemon. It does not embed, ship, or (by
default) launch one. Two facts that cost real debugging rounds:

- **tor opens the SOCKS port by default but does NOT open a control port unless you
  ask.** Dialling out works against a stock tor with zero config; publishing an onion
  service and reading bootstrap events do not.
- **Tor Browser exposes no control port at all.** Its SOCKS is `9150`; if you want
  control you must enable it yourself on `9151`.

The bring-up `torrc`, quoted verbatim from `onionxt/docs/07-tor-lifecycle.md` and
`onionxt/docs/10-usage-guide.md`:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

Equivalent as flags, if you would rather not edit a file:

```
tor --ControlPort 9051 --CookieAuthentication 1
```

Typical `torrc` locations: Linux `/etc/tor/torrc`; macOS Homebrew
`/opt/homebrew/etc/tor/torrc` (Intel `/usr/local/etc/tor/torrc`); Windows
`%APPDATA%\tor\torrc`. Restart tor, then **confirm the proof line in tor's log**:

```
[notice] Opening Control listener on 127.0.0.1:9051
```

Prefer cookie auth over `HashedControlPassword`: tor writes the cookie file itself and
onionxt reads it, so no password ever crosses your hands. In the app, match the ports:
system tor is SOCKS `9050` / control `9051`; Tor Browser is SOCKS `9150` / control
`9151` **only if you enabled it**.

### 2.4 coinxt: nothing to build on Linux or Windows; macOS is a build away

coinxt ships **four committed libraries** - `x86_64-linux`, `x86-linux`,
`x86_64-win32`, `x86-win32` - each pinned in `coinxt/src/code/MANIFEST.sha256`. Those
are the exact files the engine dlopen()s when `coinxt/src/coinxt.lcb` binds
`c:coinxt>`, so **on Linux and Windows, 32- or 64-bit, there is nothing to build**:
coinxt installs like any other member and the run below is just a run.

> **All four are current as of the 2026-08-16 Schnorr/Taproot change (ABI 6)**, and
> since 2026-08-17 the SUITE gate `tools/check-binary-freshness.py` says so about
> all four on every push. The member copy named here until then said so about only
> TWO of them - it reads ELF and printed a SKIP for each Windows DLL, so this
> sentence was a live instance of the repo's own overstated-coverage lesson
> sitting in the runbook. The suite gate reads PE too: 43/43 binds resolved and
> ABI 6 decoded from the export table on both DLLs. One note on how
> the `x86-linux` one was produced: the environment that built the other three has
> no 32-bit libc, so it was cross-compiled with **Zig** (`zig cc -target
> x86-linux-gnu.2.25`) rather than `gcc -m32`. The artifact is a 32-bit i386 ELF
> with exactly the 43 `cnx_*` exports, needing only `libc.so.6` at the documented
> GLIBC 2.25 floor, and CI **executes** it against the published vectors on every
> push (see the "Execute the COMMITTED library's vectors" step in
> `native-coinxt.yml`), which is a stronger check than any other committed library
> had before. If you would rather ship a gcc-built one, running
> `release-binaries.yml` replaces it and the same CI step will re-verify it.

**macOS is the only gap**, and it is the same gap the native members share
(box2dxt, folded home 2026-08-14, is the one already shipping all five
platforms - it has a 2.1 row of its own now, and has been the EIGHTH folded
harness since 2026-08-16): until 2026-08-23 CI built no macOS lane on purpose (the
runners are arm64-only, so a naive automated lane would emit a thin dylib; the
release workflow's universal mac lanes now exist but are dispatch-driven). Build it
first - one command, and it puts the file where the engine expects it:

```
cd coinxt && sh native/build.sh pack
```

(That derives the platform from `uname`, which is right for a native build. A cross build must name
its target - `sh native/build.sh pack x86-linux` - or it files the library under the build machine's
platform instead of the target's.)

`pack` is not the same as the plain `lib` target. It names the output `coinxt.<ext>`
(not `libcoinxt.<ext>` - the engine resolves the `c:coinxt>` token to the bare name),
drops it under `src/code/<arch>-<platform>/`, narrows the exported surface to the 16
`cnx_*` entry points via `src/coinxt.map`, and strips it. It prints the exported
symbol list so you can see what you got; if the list is longer than 16 names your
linker refused the version script and said so - the library still works, but do not
commit that one.

The committed Linux build needs only `libc.so.6` and floors at **glibc 2.25** (2017),
which is lower than the sodiumxt binary this suite already ships on five platforms, so
an engine old enough to be a problem here has a bigger problem already. The build is
byte-reproducible: rebuilding on the same toolchain reproduces the committed file
exactly, so `pack` does not dirty the manifest gate.

coinxt now has **`tools/package-extension.py`** too, which used to be the one manual
step left here. It deliberately does not build - `pack` owns that, and a second
implementation of the one step that must not drift would be worse than the gap - but it
does the three things `pack` leaves undone:

```
python3 tools/package-extension.py --assemble          # stage build/package/ for the IDE
python3 tools/package-extension.py --refresh-manifest  # record a newly packed platform
python3 tools/package-extension.py --lib <path> --platform-id universal-mac
```

The `--lib` form is the one that matters on a Mac: it installs a library built
elsewhere (your `lipo` output, or a CI artifact) and **refuses it** if it does not
export all 16 `cnx_*` entry points, because a partial library binds at load and then
fails at first use. It refreshes the manifest in the same action, since installing a
library without recording it just moves the failure to the integrity gate. It never
invents a signing identity: a macOS dylib still wants codesigning and the package still
wants notarizing before public release.

---

## 3. The run order

### 3.1 The paste-and-reopen procedure (identical for every stack below)

Every selftest and demo in this suite is a **single stack script** that builds its own
UI. There are no helper stacks and no manual layout. Do this once per stack:

1. `File > New Mainstack` (a one-card stack).
2. `Object > Stack Script`.
3. Open the `.livecodescript` file in a text editor, copy **all** of it, paste into the
   stack script, and Apply / compile.
4. **Close the stack window, then reopen it.** Reopening fires `openStack`, which is
   what builds the UI and starts the run. Nothing visible happens until you do.
   (If you would rather not close it: `send "openStack" to this stack` from the
   message box.)
5. When you are done, **close the window** so `closeStack` runs the clean shutdown
   (sessions flushed, hosts destroyed, `dcCleanup` / `enDeinitialize` / `btStopSession`).

Two of the harnesses are **functions**, not self-building stacks. For those, put the
script where its handlers are in scope (set it as a stack script, or `start using` a
script-only stack) and call it from the message box:

```
put sxSelfTest()     -- sodiumxt/examples/sodium-tests.livecodescript
put oxSelfTest()     -- onionxt/examples/onionxt-tests.livecodescript
```

### 3.2 Order of play

**Step -1 - check WHICH SodiumXT binary your platform has before you repackage.**

Do this first if you are about to reinstall the extension, because it is the one
pre-flight mistake that can cost the whole session rather than one line. The `.lcb`
and the native library ship in the same package and `sPrepare()` compares their ABI
numbers on **every** `sx*` call, so a package built from a tree whose binary for YOUR
platform is stale throws
`"SodiumXT ABI mismatch ... Reinstall the packaged extension."` from the first call
onward. That is not a degraded run: it takes the entire SodiumXT section, the whole of
riptide (hard SodiumXT dependency), and onionxt's SAFECOOKIE / deterministic-onion /
offline-address paths with it, and the failure text points at your install rather than
at the real cause.

As of 2026-08-23 the committed binaries are at **ABI 10 everywhere except
`universal-mac`**, which stays at **ABI 6** - now FOUR behind - until the manual
`lipo` build (the currency table with the reasons lives in `sodiumxt/CLAUDE.md`;
ABI 8 added the ristretto255 surface, ABI 9 the DLEQ/batch algebra, and ABI 10
(2026-08-23) the raw ChaCha20 xor NIP-44 composes; the two Windows rows are mingw
cross-builds per that file's proven fallback recipe, awaiting their Windows
engine pass like the 2026-08-11 DLL before them). On an ABI-10 row: repackage
normally and the SHA3 / offline onion-address / ristretto checks run - the
2026-08-12 Windows x64 pass did exactly this at ABI 7, green. On the mac row:
**do not repackage SodiumXT** - keep the older package, where `sxSha3_256` and
`sxRistretto*` simply do not exist and every composing member degrades the way
it was written to,
which the harness tracks rather than hard-asserts. Either way the run is useful;
mixing the two is what is not.

**Step 0 - the one-run entry point (do this first, always).**

`tests/suite-selftest.livecodescript` is the suite-wide stack: it probes each
extension, **skips what is absent**, and reports pass / fail / skip. Paste and reopen
it per 3.1. It is the cheapest possible signal: in one run it tells you which
extensions the engine can actually see and which broad areas are already unhappy,
before you have invested in any per-member setup. Treat its skips as a checklist of
what you still have to install.

Do **not** treat a green suite selftest as a substitute for the per-member harnesses.
It is breadth; the per-member selftests are depth.

Do **not** copy its report until the last section reads `summary`, either: the run
ends in two live loopbacks on a timer chain and stops looking busy long before it
is done. See 4.1.1 - this cost a round trip on 2026-08-19.

**How complete is it, exactly.** Not a judgement call any more -
`tools/check-suite-coverage.py` measures it, and the gate set runs it on every push.
**The table below is a TRANSCRIPTION of that tool's output, not a second source**, so
run `python3 tools/check-suite-coverage.py` before you trust a cell: the tool is the
authority and its numbers move on every fold. Transcribed 2026-08-19. The gate is
current by construction; a hand-copied table is REMEMBERED by construction, which is
exactly how the previous version of this table sat three days stale (sodiumxt 61,
coinxt 78, riptide 72, no box2dxt row at all) under a sentence promising it was
current.

| member | public handlers the harness calls | not reachable offline |
|---|---|---|
| sodiumxt | 72 / 72 | - |
| onionxt | 27 / 45 | 18 |
| coinxt | 90 / 90 | - |
| torrentxt | 85 / 85 | - |
| enetxt | 23 / 23 | - |
| datachannelxt | 31 / 31 | - |
| riptide | 83 / 83 | - |
| box2dxt (kit) | 313 / 313 | - |
| **total** | **724 / 742** | **18** |
| holde-em | 121 / 330 - **ADVISORY, and NOT summed into the total above** | - |

Two things about the shape of that table, both of them the gate's own decisions
rather than this document's.

**The box2dxt row is labelled "box2dxt (kit)" because that is what the gate
measures.** It counts the b2k Kit's public surface and deliberately leaves the raw
`b2*` `.lcb` binding OUTSIDE this ratchet - the block in
`tools/check-suite-coverage.py` headed "BOX2DXT IS MEASURED AS ITS KIT" says so
at length. A row reading plain "box2dxt
313/313" would claim a coverage figure for a surface nothing has measured, which is
the same overstatement this table was rewritten to remove.

**The holde-em row is printed but not added in, and adding it would break the
arithmetic rather than improve it.** The eight enforced rows share one denominator
rule; holde-em's splits a single file into a game region and a harness region and
asks a reachability question across the cut, so - in the gate's own words in
`tools/check-suite-coverage.py` - "Adding 121/330 into 724/742 would produce a
ratio that means neither thing, and the headline number is the one people quote."
The row is advisory: it prints in both modes so CI
records the number, and it does not fail the build. Its split, as the gate reports it:
209 named by nothing that runs - 20 live-transport, 9 engine-media, 41 host-window,
139 no-test.

The eighteen are onionxt's, all of them, and they are the only handlers in the suite
with a written excuse. The split, read out of `UNTESTABLE` in
`tools/check-suite-coverage.py`: **nine engine-events**, **two WATCHDOGS**
(`oxCtlDeadline` and `oxStreamDeadline`, each armed by a self-sent
`send ... to me in <timeout>` - not socket callbacks at all), and **seven live-daemon**
handlers. Read the per-handler reasons there rather than a summary here, because the
summary that stood in this paragraph until 2026-08-19 - "eleven are engine socket
callbacks (the engine calls them with a socket id no harness can mint)" - is a reason
the gate itself has since WITHDRAWN as wrong twice: every one of those handlers opens
by TESTING its argument and exits on a miss, so a synthetic id exercises the guard and
nothing else. That is a fine thing to be exempt from, but it is not what the old text
claimed. The gate fails if a new handler lands without either a check or an entry
there, and it fails on a stale excuse too, so "what does this not touch" has an answer
you can read instead of being the thing nobody re-asks after seeing a big line count.

Two things that number does *not* claim. It counts handlers **reached**, not handlers
tested well - depth is the member vector gates' job. And onionxt's seven live-daemon
handlers are exactly what rows 5 and 7 below exist for, so a green step 0 does not
retire them.

**You can download the harness instead of cloning.** Every `suite gates` CI run
uploads a `suite-selftest` artifact containing `tests/suite-selftest.livecodescript`,
the coverage report above, and this runbook. The committed file is always the built
one (the gate set runs `build-suite-selftest.py --check`, which fails on a stale copy),
so the artifact and the repository can never disagree.

#### You never need Python on the OXT machine

The harness is **generated where Python lives and committed** — on a dev machine or in
CI, never on the engine box. `tools/build-suite-selftest.py` is a build-time tool for
whoever edits a member harness; the tester's input is a finished ~1.5 MB
`.livecodescript`. The same is true of `tests/preflight.livecodescript`, the PREREQ
one-paste: `tools/build-preflight.py` generates it because its six expected-ABI
numbers are READ from the C shims, so a hand-copied number could go stale silently.
So the answer to
"can the generation be automated, or is it a separate step?" is: **it is already
automated, and it already happens somewhere else.** Both generated pastes are
committed, and each generator's `--check` in the gate set is what guarantees the
committed copy is the one the sources produce.

The demos are not generated files, but they carry generated REGIONS with the same
contract: `tools/sync-demo-embeds.py` embeds each pure-script library into the demos
that call it, and `box2dxt/tools/sync-embedded-kit.py` does the same for the b2k Kit
inside box2dxt's selftest - both `--check` in the gate set. So a demo is one paste
too, with nothing to wire and nothing to build on the engine box. Before 2026-08-17
onionxt did this with two generated `*-standalone` twins instead; those files and
their generator are gone (see the install step above).

Three ways to get it onto the engine, cheapest last:

1. `git pull` — the file is right there in `tests/`.
2. Download the `suite-selftest` CI artifact (needs a GitHub login).
3. **Let OXT fetch it itself.** The repository is public, so the raw URL needs no
   auth and no tooling at all. In the message box:

   ```
   set the script of stack "SuiteSelfTest" to \
      URL "https://raw.githubusercontent.com/SethMorrowSoftware/xtalk-suite/main/tests/suite-selftest.livecodescript"
   ```

   then close and reopen that stack per 3.1. Verified from outside the engine: that URL
   returns HTTP 200, `text/plain`, and bytes **identical** to the committed file.

   Two honest caveats on option 3. Whether `put URL "https://..."` works is an
   **engine** question this repo cannot settle headlessly — it is the standard libURL
   idiom and the IDE loads libURL, but GitHub requires TLS 1.2+, so an older SSL build
   fails here rather than anywhere interesting. If it does, fall back to 1 or 2; that is
   a fetch problem, not a harness problem. And `main` moves: pin the commit sha in place
   of `main` in that URL if you need the exact file a previous run used.

**Step 1 - the per-member selftests, in this order.**

Ordered by (value of the result) divided by (setup cost):

| Order | Stack | Needs | Why here |
|---|---|---|---|
| 0 | **`tests/suite-selftest.livecodescript`** — **START HERE.** | all six packaged extensions installed (box2dxt is the sixth, folded 2026-08-16); the coinxt, onionxt, Riptide, b2k-Kit and (since 2026-08-23) nostrxt script layers are embedded in the paste (any absent member SKIPs) | **The whole suite in one paste.** It carries all **ten** folded harnesses: sodiumxt's `sxSelfTest`, onionxt's `oxSelfTest`, coinxt's sections, torrentxt's full harness, the synchronous halves of enetxt and datachannelxt, nostrxt's `nxSelfTest`, Riptide's sections (phases 1-4, 6, 7 + the 8.3 sealed-anon-DM crypto), **box2dxt's physics + b2k Kit harness** (folded 2026-08-16, commit `ef73172`, which took suite coverage 411/429 -> 724/742) and **holde-em's** (folded the same day, commit `7f55839`, 380 `he1*` handlers - the only fold that carries a whole APPLICATION, because its game and its tests are one file). If this is green, rows 1, 4, 5, and 6 are redundant unless chasing a failure. The deliberate exceptions are the ENet and DataChannel **async loopbacks** in rows 2 and 3, and - by `check-suite-selftest.py` check 7d - holde-em's live game, which stays unreachable from the folded harness. |
| 1 | `sodiumxt/examples/sodium-tests.livecodescript` (`put sxSelfTest()`) | sodiumxt only | No I/O at all, no network, runs in a second. Everything else composes sodiumxt, so a failure here invalidates results further down. |
| 2 | `enetxt/tests/enet-selftest.livecodescript` | enetxt only | Loopback UDP on 127.0.0.1, no daemon, no second machine. Also the fastest way to discover a machine that blocks loopback UDP, which would also sink datachannelxt (see trap 5.5). |
| 3 | `datachannelxt/tests/datachannel-selftest.livecodescript` | datachannelxt only | Two real WebRTC peers in one process: offer, answer, ICE, DTLS, SCTP, text and binary round-trips, teardown. Its synchronous half ran green folded into the suite harness 2026-08-10 (every public `dc*` handler called by name); what only THIS stack still adds is its own async loopback's live halves - `dcSendText` on an open channel, `dcBufferedAmount`, `dcGatheringState`, `dcSelectedCandidatePair`, the `dcBufferedLow` event after a cap-sized send, and the a=candidate / offer-answer-role pins. |
| 4 | `torrentxt/tests/torrent-selftest.livecodescript` | torrentxt only, **and nothing else torrent-flavoured open** | 96 checks in the current harness. Read trap 5.1 first: one session per OXT process. |
| 5 | `onionxt/examples/onionxt-tests.livecodescript` (`put oxSelfTest()`) | onionxt + sodiumxt; **no daemon needed** | Deliberately pure and offline: address/base32 vectors, fail-closed contracts, idempotent teardown, and the two sodiumxt ABI-6 primitives. Read trap 5.6: it really does tear down live state. |
| 6 | `coinxt/tests/coin-selftest.livecodescript` | coinxt packaged; the script layer is EMBEDDED in the file since 2026-08-17 (`tools/sync-demo-embeds.py`), so no `start using` step - see 4.6 | Drives the whole public `cx*` surface (90 handlers): the `.lcb` handlers (hashes, curve, the two BIP-32 tweaks, the BIP-39 wordlist) and the `src/coinxt.livecodescript` ones (encodings, addresses, BIP-39/32/44, and the phase-5 transaction KATs - BIP-143 / EIP-155 / EIP-1559). Phases 1-4 ran green folded 2026-08-10 (207/207 on the re-run); **phase 5 (`stRunTransactions`) closed 2026-08-12 at 230/230** - after the headless-execution net (`check-script-vectors.py`, 251 checks) caught and fixed a trailing-empty-scriptSig defect that would have failed `cxBtcTxEncode` on that very run. Fully synchronous. See 4.6. |

**Step 2 - the demos (depth on real transports).**

> **EVERY DEMO BELOW NOW PRINTS ITS OWN RECORD (2026-08-20).** Until this
> change a demo pass produced a human judgement - "the window built, it looked
> right" - and no honesty label can quote that, which made the fleet-wide
> re-pass the most expensive engine time in this project and the least
> recoverable. Eleven runnable stacks now run a **boot self-check** on open and
> print a pasteable block into their own log: every control the script names or
> builds, that nothing is live at boot, the library surface and the CARRIED
> script layer, and one delayed-write probe. Open the demo, read the block,
> paste it. Nothing in it hosts, connects, binds a port or takes a singleton -
> the operator is about to do that for real.
>
> Three conventions worth knowing before you read one:
> **an absent extension SKIPs, never FAILs** (a missing member is an
> environment); **every observed value prints beside its assertion**, so a
> failure names what it saw rather than only what it wanted; and the block
> **paints the status line red only when something failed**, because a green
> demo's own "Ready ..." line is the more useful thing to be reading and a red
> one's log may be on a tab nobody has clicked.
>
> The last line of every block is the count. If you do not see it, the run is
> not finished - the delayed-write probe lands 400 ms in.
>
> The plumbing is a carried block (`tools/demo-selfcheck.livecodescript`, gate
> `tools/check-demo-selfcheck-drift.py`); the assertions belong to each demo.
> **Not adopters, with reasons:** `coinxt-demo` and `sodium-demo` have no log
> surface - their output fields ARE the demonstration - and both members are
> covered by their own folded harnesses (278 and 99 checks); the five box2dxt
> examples are games, exempt from the UI kit by written reason, with the Kit at
> 375/375 in the paste.

| Order | Demo | Needs |
|---|---|---|
| 7 | `datachannelxt/examples/datachannel-loopback.livecodescript` | datachannelxt only (the helpers are embedded) |
| 8 | `enetxt/examples/enet-lan-chat.livecodescript` | enetxt only (the helpers are embedded); **two machines** for the real test |
| 9 | `torrentxt/examples/torrent-quickshare.livecodescript` | torrentxt (+ sodiumxt for the passphrase lock) |
| 10 | `torrentxt/examples/torrent-client.livecodescript` | torrentxt |
| 11 | onionxt against a live daemon: `onionxt/examples/onionxt-demo.livecodescript` (paste-and-run: it embeds the ox* layer, the httpd and its own tests) | sodiumxt packaged + tor with the control port |
| 12 | `torrentxt/examples/torrent-quickshare.livecodescript` **with the Tor toggle on** | torrentxt + onionxt + sodiumxt + tor daemon. Inventory item 5. |
| 13 | `datachannelxt/examples/datachannel-dht-chat.livecodescript` | datachannelxt **and** torrentxt (the helpers are embedded); **two machines** |
| 14 | `torrentxt/examples/torrent-dht-channels.livecodescript` and `torrent-rp1-chat.livecodescript` | torrentxt; **two machines** |
| 15 | onionxt **Mode B**: `oxLaunchTor` against a real tor binary. Inventory item 4. | a tor binary on disk |
| 16 | `coinxt/examples/coinxt-demo.livecodescript` - the phase-6 demo: mnemonic to accounts, addresses, sign/verify, and a decoded, signed BTC + ETH transaction | coinxt packaged (the script layer is embedded); sodiumxt optional (only the Generate button needs it) |
| 17 | `riptide/examples/riptide-social.livecodescript` - the phase 1-7 flagship on four cards (Feed + media, Messages + Call, Devices, Anon). **TWO-MACHINE RECORD**: feeds both directions 2026-08-13; media fetched-and-played and DMs both ways 2026-08-15. The remaining legs (the call, the mesh, anon over Tor) are scripted in `riptide/docs/two-machine-runbook.md`, which supersedes this row for riptide | sodiumxt + torrentxt (+ enetxt/datachannelxt per leg) packaged; the rs*, ox* and httpd script layers are EMBEDDED; takes THE torrent session (trap 5.1) |
| 18 | `tests/suite-closing-pass.livecodescript` - ONE stack for the remaining legs, so the closing sessions are a checklist, not an expedition. Six sections, each printing PASS lines: **A** datachannel local async (item 3's still-static live halves, single machine), **B** enet two-machine chat (closes item 8), **C** torrent seed/leech with a hash-verified payload plus resume saved to disk and re-added across an OXT restart, **D** rp1 chat over a DHT rendezvous (with C, closes item 14's legs), **E** datachannel chat signaled over the real DHT (closes item 13's shape), **F** Mode B `oxLaunchTor` plus a live onion echo - listen, dial your own onion through the Tor network, exact bytes both ways (closes item 15 and the seven live-Tor coverage exemptions' `oxTransport*` half) | sodiumxt + torrentxt + enetxt + datachannelxt packaged; **no onionxt wiring for F** - this stack has CARRIED the ox* layer embedded since 2026-08-17 (`tools/sync-demo-embeds.py`), so it is one paste; takes THE torrent session (trap 5.1); **install on both machines** for B/C/D/E |

Items 8, 13, and 14 are genuine two-machine tests; item 18 packages their
remaining legs (and items 3 and 15) into one paste-on-both-machines stack, so
prefer it when the goal is closing labels rather than exercising a specific
demo's own UI. If you only have one machine tonight, run them anyway to the
point where the UI builds and the session starts, and record exactly that:
"UI built, session started, no second peer available."
That is still a real result and it is honest.

---

## 4. What to record

### 4.1 How to copy a result back

**The demos, first, because there are eleven of them and it is one gesture.**
Each prints its boot self-check into its own log field on open; select that
block and copy it. There is no button - the demos are demos, and a Copy button
on every one of them is chrome that has to be maintained in eleven places.
The block is bounded top and bottom: it starts at
`== boot self-check (nothing is hosted, connected, or bound) ==` and ends at
the `n passed, m failed, k skipped` count line. **If the count line is not
there, the run is not finished** - the delayed-write probe lands 400 ms in, and
the line above the gap says so.

Where each block prints, when it is not obvious: onionxt-demo uses the About
tab's `about:testlog`, onion-httpd/spike uses `demo:out`, riptide-social uses
the Feed card's `raIdOut`, and datachannel-loopback uses the A-side log. Every
other adopter has one log and uses it.

The three self-building selftests (torrentxt, enetxt, datachannelxt) share one UI:
a bold `stSummary` field carrying the passed / failed / total counts (green when
clean, red when not), a scrolling `stResults` field of per-check lines, and an
`stRerun` button. `tests/suite-selftest.livecodescript` (step 0) shares that UI and adds
a **`Copy results`** button: click it and the whole record is on the clipboard -
the `passed / failed / skipped / total` counts as the first line, then a blank
line, then every per-check line. Paste that straight into your notes.

Until 2026-08-20 the button copied the per-check lines ONLY and this section
taught a message-box incantation to fetch the counts across by hand; the counts
ride along now, so there is nothing to remember. If you are on an older paste and
the first line is not a count, click the selftest window so it is the default
stack and run:

```
set the clipboardData["text"] to (the text of field "stSummary" of this stack) & \
   return & (the text of field "stResults" of this stack)
```

**Copy the full result text, not just the summary count** - the per-check lines
are what let a failure be diagnosed without a second session.

For the two function-style harnesses (`sxSelfTest()`, `oxSelfTest()`), the message box
already holds the full report; copy it directly.

Alongside each result, record: **OXT version, OS and architecture, the date, and
which extensions were loaded.** A result with no environment attached cannot be
turned into a claim.

#### 4.1.1 WAIT FOR THE `summary` SECTION. A run that looks finished usually is not.

The suite harness (and enetxt's and datachannelxt's own) ends with **async**
sections: two live loopbacks driven by a 33 ms timer chain, with a **40-second**
worst-case deadline (`kStDeadlineMs`). The report is a live surface - it is
re-rendered on every tick - so while those run the list simply STOPS growing at
whatever section the pump had reached, with nothing to say it is mid-run. Copy
then and you get a report that ends in the middle of a section and reads exactly
like a hang.

That is not hypothetical: it is what happened to the 2026-08-19 Windows pass. A
**fully green** run came back ending inside `CROSS: the 60000-byte budget both
transports share`, missing the enet and datachannel loopback deliveries, the
CROSS OnionXT capabilities, teardown and the summary - and nothing in the text
could tell an early Copy from a stalled pump.

**The run is over when the report's last section is `summary`,** and only then.
Since 2026-08-20 an unfinished report prints its own trailer -

```
      RUN NOT FINISHED - this is NOT the end of the report.
      An async section is still running. Wait for the SUMMARY
      section at the bottom, then Copy.
```

- and `Copy results` carries that trailer onto the clipboard and says so in its
dialog, so an early copy can no longer be mistaken for a complete one in either
direction. The trailer lives in `tools/harness-scaffold.livecodescript`, so
every carrier of the scaffold gets it.

**It settled the question on its first outing, and the answer was the dull one.**
The next 2026-08-20 paste came back carrying the trailer - proof the run was
still live rather than hung - and the run after it, same build, waited and
completed: **1981 passed, 0 failed, 1 skipped, 1982 total**, through both live
loopbacks, the shared-budget cross-checks, teardown and the summary. **(The
record moved again 2026-08-24, same platform: 2,373 passed, 0 failed, 3
deliberate skips, 2,376 total - the growth is nostrxt's 274-check first
engine run, coinxt's BIP-341 section, sodiumxt's ABI-10 ChaCha20, holde-em's
v42 batch-path checks and riptide's kind-C/BTXO rails, all green on first
contact; docs/REMAINING-WORK.md's 2026-08-24 banner carries the detail.)** So all
three truncated pastes were early copies and nothing was ever wrong with the
pump. Worth knowing for the next time a report stops somewhere surprising: the
async half is the last ~27 checks and it is the only part of the run that takes
wall-clock time.

### 4.2 datachannelxt (inventory item 1 - CLOSED, async residual included)

The first-engine-evidence flips were applied after the 2026-08-08 and
2026-08-10 passes, and **the standalone async run happened 2026-08-15,
green end to end**: the live halves this section used to enumerate -
`dcSendText` on an open channel, `dcBufferedAmount` live, `dcGatheringState`
complete (2) on both peers, a populated `dcSelectedCandidatePair`, the
offer/answer-role and a=candidate pins, a cap-sized send, clean teardown -
are all dated results now, recorded in `datachannelxt/README.md` and
`datachannelxt/CLAUDE.md`. **A green re-run needs no label work.** What this
member still owes is browser interop (a real Chrome/Firefox peer) and a
two-network call with real NAT traversal - neither is a selftest leg.

Leave `datachannelxt/CLAUDE.md`'s *rule* about not claiming unobserved behaviour
alone - that is policy, not a status label.

### 4.3 enetxt (inventory item 3 - CLOSED; the standalone async ran 2026-08-13)

The standalone run this section existed for has happened: on 2026-08-13
`enetxt/tests/enet-selftest.livecodescript` ran green END TO END on a real engine -
the live `enHostStatus` pair (connected, then zero peers after the
disconnect), the `enPeerStatus` statistics (rtt >= 0, packetLoss within
0..1, populated packet/byte counters), and the full echo/broadcast/binary
loopback with a graceful close. Nothing in that file is verified statically
any more, and the labels were flipped the same day. A green RE-run needs no
label work - record it in the tick sheet. The member's one remaining
un-exercised surface is the LAN chat between two real machines (item 6).

If you also run the LAN chat between two machines, that retires the last line of that
same blockquote: "Still un-exercised: the LAN chat demo between two real machines."

### 4.4 torrentxt (inventory item 3)

**A pass looks like:** green summary across its 96 checks, and specifically the
**signed-puts section**: `btDhtBep44SignBuf` determinism, `btDhtPutSigned`,
`btDhtGetPeers`, `btAddInfohash`, `btMapPort` / `btUnmapPort` handling "no mapper"
cleanly, and `btRp1Enable` / `btRp1SetToken` / `btRp1Send` / `btRp1Poll` handling "no
peer" cleanly.

**What it deliberately does not prove:** async DHT and tracker results (they arrive
later as events), a real rp1 message exchange (two machines), and the two destructive
handlers it skips on purpose (`btMoveStorage`, `btRemoveTorrent`-with-delete). Do not
record those as passed.

**Copy back:** the full `stResults` text.

**What flips:** nothing is left to flip for a green re-run - the labels this
section used to enumerate were applied after the 2026-08-10 pass (the harness
COVERAGE NOTE and the README status paragraph both carry the dated result).
Record the run in the tick sheet; a FAILURE, of course, still gets the full
section-6 treatment.

### 4.5 sodiumxt (inventory item 3)

**A pass looks like:** `put sxSelfTest()` returns a per-check report ending in a
PASSED summary with zero failures, including the sections added after the recorded
pass: the attached-signature form, seed-derived keypairs, keyed hashing, and the
diagnostics / preset accessors.

**Copy back:** the whole message-box report.

**What flips:** nothing for a green re-run - the api-reference caveat this
section used to name was retired after the 2026-08-10 pass, and the 2026-08-12
ABI-7 run (71 checks) is recorded there too. Record the run in the tick sheet.

### Setup the suite harness NO LONGER needs: the two `start using` lines

Three layers ship as a **pure-script library** that is not part of any installed
extension — `coinxt/src/coinxt.livecodescript` (encoders, addresses, the whole
HD layer, and the phase-5 transaction builders), `onionxt/src/onionxt.livecodescript`
(the entire ox* surface), and (since 2026-08-11) `riptide/src/riptide.livecodescript`
(the rs* capstone app layer). The suite harness used to require the first two in the
message path before pasting; **since the embed, it does not**.
`tools/build-suite-selftest.py` folds all three libraries into
`tests/suite-selftest.livecodescript` verbatim, so the one paste carries the code
its tests call, and `--check` pins the set to one tree.

That closes both failure modes the old setup step carried, and the second one
cost a real pass:

- **Forgot the line entirely**: ten coinxt sections reporting FAIL
  "handler not found", which reads exactly like a broken library and was one
  missing line.
- **A STALE layer left loaded** (2026-08-10): a freshly built harness pasted
  into an engine whose in-memory coinxt stack predated a parser fix reported
  the exact two failures that fix had closed — red lines that read as "the fix
  does not work" and meant "the fix was not loaded". With the layer embedded,
  the harness and the library cannot skew; a `start using` copy that is also
  loaded is simply shadowed for the harness's own calls (same-script wins).

The probes for the three layers remain, as tripwires rather than setup checks: a
`FAIL` on one now means the generated paste itself is damaged, not that a step
was missed.

**And since 2026-08-17 the standalone harnesses do not need them either.**
`tools/sync-demo-embeds.py` carries each pure-script layer into the files that
call it, so `coinxt/tests/coin-selftest.livecodescript`,
`onionxt/examples/onionxt-demo.livecodescript`,
`tests/suite-closing-pass.livecodescript` and
`riptide/examples/riptide-social.livecodescript` are each ONE paste with no
wiring. The registry in that tool is the list; a demo that is deliberately NOT
embedded is recorded there with its reason (today: `torrent-quickshare`, whose
own `socketError`/`socketClosed`/`socketTimeout` would collide with OnionXT's -
it keeps its optional `start using stack "onionxt"` for the Tor leg).

**`start using` is still the right thing in a real project.** The sources under
`<member>/src/` remain the single source of truth and the correct dependency;
the embeds exist so a READER can open a demo without wiring it.

### 4.6 coinxt (inventory item 2 — CLOSED 2026-08-08; this is now the residual)

**PHASE 3+ COMES FROM A SECOND LAYER, and both pastes now carry it.**
The hash and curve handlers come from the `.lcb` extension. The encoders and address
builders come from `coinxt/src/coinxt.livecodescript`, which is a SCRIPT. The SUITE
harness embeds that script (see "Setup the suite harness NO LONGER needs" above),
and since 2026-08-17 so does the standalone `coin-selftest` paste, so neither
needs `start using stack "coinxt"`.

If every phase-3+ section fails with `handler not found` while the earlier ones pass,
that is the symptom of the script layer not being present - which now means the
paste itself is damaged or truncated, not that a setup step was missed. Re-copy
the whole file and re-run before reporting anything.

**The address checks are stronger than they look.** `cxBtcAddressP2WPKH` of G must equal
`bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4` and `cxBtcAddressP2TR` of x-only G must equal
`bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0` - and those are not
CoinXT's expectations. They are **BIP-173's and BIP-350's own example addresses**, because
hash160(G) is the witness program in the first and x-only G is the program in the second.
And the script layer's LOGIC is executed headlessly on every push
(`coinxt/tools/check-script-vectors.py` runs the real `.livecodescript` through a small
interpreter), so a failure here is much more likely to be a PARSER difference than an
arithmetic one - which is exactly the thing only an engine run can settle. Record the
exact failing line.

**The five numbered questions in the `.lcb` header are answered.** The 2026-08-08
pass confirmed all of them, each on the side the code assumed: the module loads and
binds resolve, the ABI guard holds, **`UIntSize` works as a foreign RETURN type**,
**`MCDataGetBytePtr` marshals an empty `Data`** (`cxKeccak256("")` returned
`c5d2…a470` rather than throwing), and the vectors are byte-exact. Neither
documented fallback — `CUInt`, `optional Pointer` — is needed. Do not re-litigate
them; the `.lcb` header now records the answers instead of the questions.

**What is left is coverage — and since 2026-08-08 there is a lot more of it.** That
run called 4 of the then-16 public handlers, because coinxt had no self-building
harness. It has one now, and **phases 2, 3 and 4 have all since landed** - the
secp256k1 curve, the encodings and addresses, and the HD wallet layer - so the same
single paste now carries the entire public surface instead of 16 handlers:

> **Run `coinxt/tests/coin-selftest.livecodescript`.** Same paste-and-reopen
> procedure as every other member (section 3.1), same green/red UI, same
> `Re-run` button. It drives **all 90** public `cx*` handlers (the phase-2
> framing in this blockquote predates phases 3-5; the COUNT has been kept
> current since, and is `python3 tools/check-suite-coverage.py`'s coinxt row) —
> `cxCheckABI` by
> name at last, all thirteen `*Len` accessors, every digest, both HMACs, PBKDF2,
> and the whole curve surface, then the script layer's encoders, addresses,
> BIP-39 mnemonics and BIP-32 derivation — against the same published vectors
> `coinxt/tools/coin-kat.py` and `coinxt/tools/check-script-vectors.py` pin.

**A question this runbook used to ask here has been WITHDRAWN, and why is worth
one paragraph.** It asked you to determine whether `the itemDelimiter` is a
local property in OXT, because coinxt's script layer depends on the default in
26 places. That was a waste of an engine slot: the family's own portable lesson
book — `coinxt/templates/CLAUDE.md` rule 5, carried into that member verbatim —
already records that `itemDelimiter` and `lineDelimiter` are **global mutable
state**, to be set immediately before a parse and restored afterward. OnionXT
has been doing exactly that at six sites for as long as it has existed. Do not
spend engine time on it; the remedy is known (save, set, use, restore) and the
work is ordinary editing. **Before adding a question to this runbook, grep the
carried lesson books — an engine session is the most expensive way to learn
something already written down.**

**Read the phase-4 sections first if anything fails.** BIP-39 and BIP-32 are the
only part of coinxt where a wrong answer still looks like a right one: a
mis-packed mnemonic is still twelve English words, and a mis-derived path is still
a valid address. The harness ends with the test mnemonic every wallet ships with
walking down `m/44'/0'/0'/0/0`, `m/84'/0'/0'/0/0` and `m/44'/60'/0'/0/0`; if those
three lines are green, coinxt agrees with every other wallet in the world about
what a seed phrase means.

**This run has now happened (2026-08-10, folded into the suite harness), and both
of its open questions were answered on the side the code assumed.** The two
marshalling shapes that were new to this binding, kept here for the record of
what a failure would have looked like:

- **a foreign handler taking a C `int` FLAG** — `cxPublicKey(tSeckey, true/false)`.
  If the flag does not marshal, the giveaway is that both calls return the same
  length instead of 33 and 65. Phase 1 had no boolean crossing the FFI at all.
- **public handlers returning `Boolean` rather than `Data`** — `cxVerify` and
  `cxSeckeyIsValid`. Every phase-1 handler returned `Data`, so this is untested
  ground; a mismarshal would most likely throw or return empty rather than
  `true`/`false`.

**A pass looks like:** `stSummary` green, zero failures. Sections in order: the ABI
guard (**ABI 6** now), the thirteen length accessors, Keccak-256, SHA3-256
**and the aliasing trap** (SHA3 and Keccak differ by a padding byte alone, so a
crossed wire is a plausible wrong answer and on Ethereum a wrong address), SHA-2,
RIPEMD-160, RFC 4231 HMAC cases 1 and 2, the BIP-39 seed vector, empty-input
marshalling across every digest, digest independence, the two hash fail-closed
guards — then the curve: keys (private key 1 must give the generator **G**), RFC 6979
signing (the published `sha256("Satoshi Nakamoto")` signature, byte for byte, and
signing twice must agree), verification (**true** for good, **false** for tampered /
wrong key / wrong digest), recoverable signing and `cxRecover` round-tripping to the
signer, ECDH agreeing from both sides, and six curve fail-closed guards.

**Copy back:** the full `stResults` text.

**Note (this 4.6 text predates phases 3-5).** Phases 3 (encodings/addresses), 4
(HD wallets/mnemonics) and 5 (transactions) all shipped after this section was
written, and `coin-selftest` now drives all **90** handlers, not just the curve.
That count was **78** until 2026-08-16, and the twelve that closed the gap are
not all one story: **ten** are the ABI-6 Schnorr/Taproot handlers
(`cxSchnorrSign`, `cxSchnorrVerify`, `cxSchnorrSignatureLen`, `cxXOnlyPubkey`,
`cxXOnlyPubkeyLen`, `cxTaprootTweak`, `cxTaprootTweakPubkey`,
`cxTaprootTweakSeckey`, `cxTaprootOutputLen`, `cxBtcAddressP2TRFromInternal`;
commit `affdf1c`, 2026-08-16) and **two** are the WIF pair (`cxWifEncode` /
`cxWifDecode`; commit `f228b9f`, 2026-08-15), which this runbook's inventory row
12 tracks separately and which lumping into "Schnorr" would contradict.
Expect green sections for hex/Base58Check/Bech32/RLP/addresses, BIP-39/32/44,
and the phase-5 `stRunTransactions` KATs (BIP-143 / EIP-155 / EIP-1559) - the
last of which is NEW offline surface (runbook inventory item 8) having its first
engine pass. **Schnorr/BIP-340 and the BIP-341 tweak SHIPPED 2026-08-16 at ABI 6**
(commit `affdf1c`, upstream bitcoin-core/secp256k1 vendored), so the sentence that
stood here - "the only genuinely-absent surface is Schnorr" - is retired; expect
`cxSchnorrSign`/`cxSchnorrVerify` and the tweak among the sections instead, all of
them having their FIRST engine pass. `cxBtcAddressP2TR` is deliberately UNCHANGED
and still encodes an output key it is GIVEN: making it tweak would turn every
existing correct call into a permanently unspendable double tweak, so the full
BIP-341 path is a separately named handler. The one surface genuinely absent is a
BIP-341 **sighash builder** - coinxt signs a sighash it is handed and cannot
compute one.

**What flips:** the "PHASE 2 STATUS" block and the "STILL VERIFIED STATICALLY"
paragraph in the `coinxt/src/coinxt.lcb` header, the matching sentences in
`coinxt/CLAUDE.md` (both the phase-1 residual and the phase-2 as-built note), the
residuals in `coinxt/IMPLEMENTATION-PLAN.md`, the Status section of
`coinxt/README.md`, the api-reference status blockquote, and the coinxt row in the
root `README.md`. A green run retires the phase-1 residual (12 handlers) and the
phase-2 one (15 handlers) at once, and closes phase 2 outright.

> **All four committed libraries are current for ABI 6**, including `x86-linux`
> (cross-compiled with Zig; see 2.4). So `cxCheckABI` should be silent on every
> supported platform. If it does throw "ABI mismatch — reinstall CoinXT", that is
> the stale-binary guard working, not a phase-2 defect: it means the extension you
> installed and its bundled library came from different commits, and reinstalling
> the packaged extension is the fix.

> The harness's expected values are hand-copied literals, so
> `coinxt/tools/check-selftest-vectors.py` re-derives every one of them on every push
> (against `hashlib`/`hmac` where Python has an independent implementation, against
> the published table otherwise). It is in the always-on gate set and needs no
> compiler. A drifted expectation would turn a real regression into a green run,
> which in a money library is the worst failure mode there is.

### 4.7 onionxt (inventory items 4 and 5)

**`oxSelfTest()` pass:** a PASSED summary with zero failures. Note that it needs no
daemon; if sodiumxt is absent, the ABI-6 section **skips** rather than fails, and a
skip is a legitimate recorded outcome, not a pass.

**Mode B (item 4) pass:** `oxLaunchTor` writes its torrc, starts the process, and the
control port becomes connectable. Record `the processId`, whether stdout carried
`Bootstrapped 100%`, and whether the child exits cleanly on shutdown.

**What flips for Mode B:**

- `onionxt/CLAUDE.md`, "Still `VERIFY:` (not yet exercised)" item 8 - move it into the
  "Confirmed on-engine" list, with what you saw.
- `onionxt/docs/10-usage-guide.md`, the intro blockquote: "The optional Mode B tor
  launch is the one path not yet exercised."
- `onionxt/docs/07-tor-lifecycle.md`, Mode B.

**Quick Share over Tor (item 5) pass:** a file's bytes make the trip over an onion
stream with **no torrent created and no DHT call** (that mutual exclusion is the
invariant to watch), both ends see the transfer complete, and the folder-serving mode
renders in Tor Browser.

**What flips:**

- `torrentxt/examples/torrent-quickshare.livecodescript`, both honesty comments (near
  the `kTorCodePrefix` constants and above the Model C block).
- `docs/ONIONXT-INTEGRATION-PLAN.md`, the VERIFY register in section 12.3 - tick the
  specific numbered items you exercised, not the register as a whole.

### 4.8 The suite summary

Once the per-member labels are updated, the last edit is the root `README.md`:
the **Release status** table and the honesty-convention paragraph beneath it. Do that
in the same follow-up pass, so the suite front door and the members never disagree.

---

### 4.9 nostrxt (inventory items 33 and 34 - the member with NO engine evidence yet)

Everything is first-time here, so record generously. The folded run (item 33)
rides the suite paste: copy the `NostrXT` line of the per-member table and any
red lines verbatim into `nostrxt/CLAUDE.md`'s As-built notes. Three specific
things to write down:

- The UTF-8 event C check ("event C id matches (raw UTF-8 content)"): pass or
  fail, it is the suite's first measurement of `textDecode` round-trip
  fidelity for non-BMP content - if it fails, that is an engine-notes entry
  (section 2, evaluation), not a nostrxt bug to patch around silently.
- The NIP-44 seam section's verdict lines. Against a current SodiumXT (ABI
  10+, where `sxChaCha20IetfXor` shipped 2026-08-23) the expected record is
  "the official encrypt_decrypt vector decrypts" plus "and re-encrypts
  byte-identically" - the first engine evidence for the complete NIP-44
  path. Against an older installed SodiumXT the same section asserts "the
  untampered vector reaches the cipher and fails closed" plus "naming the
  primitive absent from the installed SodiumXT" - either way, copy the
  lines.
- Which sections SKIPped and why (CoinXT absent vs the relay layer absent):
  the counts feed the member's first measured floor, which replaces the
  placeholder floor 1 in `tests/suite-selftest.core.livecodescript`'s
  `stMergeReturned "NostrXT"` call site.

The live-relay legs (item 34) are the demo's: label flips live in
`nostrxt/src/nostr-relay.livecodescript`'s STATUS header, `nostrxt/CLAUDE.md`
gotcha 7, and `nostrxt/docs/05-relay-client.md`. The wss:// result - WHATEVER
it is - goes to `docs/OXT-ENGINE-NOTES.md` section 6 as the suite's first TLS
socket measurement.

## 5. Known traps

These are all from the members' own hard-won notes. Each cost someone a debugging
round already.

### 5.1 Only ONE torrentxt session per OXT process

TorrentXT allows one live session at a time per process. **Close every other
torrent-flavoured stack before running `torrent-selftest.livecodescript`** (the
selftest header says so explicitly), and run one demo per OXT instance. For a
two-party test use two machines, not two windows on one machine. A second session in
the same process is the classic "why is nothing working" of this member.

**This bites the run order in section 3.2 directly.** `tests/suite-selftest.livecodescript`
from step 0 calls `btStartSession` and holds THE session until its window closes, so
**close it before step 4**. It fails soft in the other direction (if the session is
already taken, its torrent sections SKIP with a note rather than failing), so the damage
runs one way only: leave step 0 open and step 4 has nothing to start.

#### 5.1.1 RESTART OXT BEFORE EVERY PASTE. A lost session handle never comes back.

**Read this before your second paste of the night.** It cost the 2026-08-09 pass the
entire TorrentXT surface (85 checks) *and* both cross-member BEP44 sections, which is
more coverage than any other single failure in that run.

The one-session latch lives in the C shim. The only key that opens it is the integer
handle `btStartSession` returned, and **TorrentXT exports nothing that enumerates
sessions or releases one you can no longer name** (`live_session_count()` is a C++
test hook in `torrent_shim.h`, deliberately not part of the FFI). The harness keeps
that handle in a script local. So anything that destroys the script local while the
session is still live orphans the session **for the rest of that engine launch**:

- **Re-pasting or editing the stack script.** Recompiling a script clears its script
  locals; the C-side session is untouched and keeps running. This is the common one,
  because "install the fix and run it again" is the entire loop of an engine pass.
- **A run that died before its teardown.** Teardown happens at the *end* of the async
  pump. An uncaught error earlier skips it and leaves the session up. Narrowed by the
  same change: every synchronous section, every folded member harness and `stProbe`
  itself are now individually contained, so a throw costs one FAIL line rather than
  the run. `stPump` is still uncontained, so an ASYNC-phase throw can still skip
  teardown - that leaks one run, not the launch, because the next `stRun` releases it.
- ~~**`send "openStack" to this stack`**~~ **CLOSED.** This was a third loss path
  until the same change that added this trap: `stRun` now releases the session
  (`btStopSession`) before it clears the handle, so openStack re-entry is safe.
  Listed here because it is exactly the kind of stale warning that trains an
  operator to restart after every green run, which is its own tax.

The next run then reports:

```
      TorrentXT: ABSENT - TorrentXT is installed but a session is already live
      in this process ...
```

and there is no other stack to close, because the thing holding the session is your
own last run. **Once the handle is gone, the only remedy is to quit and relaunch
OXT** - nothing you can type releases it *then*, and nothing distinguishes it from a
genuinely foreign owner:
the shim answers both cases with the same refusal. **Do not go hunting for a handle to
stop.** A session handle is `(generation << 16) | slot`, so the first one a process
mints is exactly `65536` and a search would find it on the first guess - and if the
owner turns out to be a real client stack, `btStopSession` pauses it, flushes its
resume data and joins its threads out from under an app that is still holding torrent
handles.

So run the torrent-bearing harnesses this way:

1. **Quit and relaunch OXT before every paste** of
   `tests/suite-selftest.livecodescript` or `torrent-selftest.livecodescript`.
   Treat "I edited the script" as "I have to restart the engine". Every other member
   tolerates a re-paste: ENet and DataChannel rebuild their hosts each pass and the
   four pure members hold no process state at all. TorrentXT is the only one where a
   re-paste costs you a whole subsystem.
2. **Within one launch, re-run only with the harness's own Re-run button**, or by
   closing and reopening the stack window. Both paths run `stCleanup`, which stops the
   session and takes a fresh one. `send "openStack"` and a fresh paste do not.
3. **If a run dies mid-way with an error dialog, click Re-run BEFORE you touch the
   script.** That releases the session. Once you have recompiled, the handle is gone
   and only a relaunch will do.

The cost of getting this wrong is larger than it looks, so it is worth stating plainly:
TorrentXT is the only member whose absence *also* silently removes coverage belonging
to other members. A run that skips it skips `CROSS: one seed, one identity` and
`CROSS: SodiumXT signs a BEP44 item TorrentXT accepts` with it, and those two sections
are the reason the suite harness exists.

### 5.2 A stack must be CLOSED and REOPENED

Pasting the script is not running it. `openStack` is what builds the UI and starts the
run, and it does not fire on paste. If nothing happens after you paste, you skipped
step 4 of section 3.1. Escape hatch: `send "openStack" to this stack`. This used to be
unsafe for a torrent-bearing harness that had already run once in the launch; `stRun`
now releases the session before clearing its handle, so it is fine. See trap 5.1.1 for
the one loss path that remains, which is recompiling the script.

### 5.3 Tor Browser exposes no control port

tor opens SOCKS by default and a control port **never** unless asked, and Tor Browser
does not expose one at all. Use a system tor on `127.0.0.1:9051`, or Tor Browser on
`9151` **with the port explicitly enabled**. A refused control connection is
`Error 10061` / `WSAECONNREFUSED` / "connection refused" and means nothing is
listening there - it is not an onionxt bug. Confirm the
`Opening Control listener on 127.0.0.1:9051` line in tor's log before blaming script.

### 5.3.1 Mode B will collide with the daemon you already have running

**`oxLaunchTor` defaults to SocksPort 9050 and ControlPort 9051** - exactly the
ports a system tor already holds. If you are running S2 in the normal way (a
system daemon up, per 2.3), then leg F's `oxLaunchTor` launches a SECOND tor
against those same ports, the bind fails, and the symptom is a tor that starts
and dies rather than an error OnionXT can report. It reads like "Mode B is
broken". It is a port collision.

Added 2026-08-17 because nothing in this tree said so, and Mode B is the one
path in onionxt that has never had an engine pass - so the first person to run
it is the most likely to misread the failure as the defect it is meant to find.

Two ways through, and the first is better:

- **Pass explicit high ports:** `oxLaunchTor tPath, tDir, 9250, 9251`. Both
  daemons coexist, Mode A stays up for the other items, and `oxLaunchTor`
  calls `oxSetSocksPort`/`oxSetControlPort` for you, so the rest of the API
  follows the launched one automatically. This also proves the port arguments
  actually marshal, which the defaults never would.
- **Stop the system daemon first**, run leg F alone, then restart it. Simpler
  to reason about, but it costs you the daemon every other S2 item wants.

Either way, record WHICH you did: "Mode B on 9250/9251 beside a running system
tor" and "Mode B on 9050/9051 with the system daemon stopped" are different
claims, and only the first proves the ports are honoured.

### 5.4 An ephemeral ADD_ONION service dies with its control connection

A transient control-socket drop (or a reconnect) un-publishes the service while its
descriptor lingers in the DHT for about three hours. A later visit then hits
`Unable to find any hidden service associated identity key` at rendezvous, which
surfaces in a browser as an empty response. onionxt passes `Flags=Detach` by default to
survive this, and teardown still `DEL_ONION`s. **If a published onion "works and then
does not", check whether the control connection dropped, and always test against a
freshly published address rather than one from an earlier run.**

Related bind trap: `accept connections on port` sets `the result` on failure. A
reserved or blocked local forward port produces `Error 10013` (`WSAEACCES` - on
Windows, Hyper-V / WSL2 / Docker reserve whole TCP ranges, and `8080` is a frequent
casualty; list them with admin `netsh int ipv4 show excludedportrange protocol=tcp`) or
`Error 10048` (`WSAEADDRINUSE`). Pick a different **local** port such as `8090` or
`9099`; leave the **virtual** port at 80 so browsers reach `http://<address>.onion/`.

### 5.5 UDP to loopback may be blocked on your machine

Both `enet-selftest` and `datachannel-selftest` run a live loopback over UDP on
127.0.0.1. A machine (or a host firewall, or an endpoint-security agent) that blocks
**all** UDP, even to itself, fails the loopback section. The datachannelxt harness is
built for this: its async phase has a deadline and fails the loopback section **with a
note rather than hanging**. So:

- If enetxt's loopback fails and datachannelxt's loopback also fails, suspect the
  machine, not the members. Test UDP loopback independently before concluding anything.
- Record it as an **environment** failure, distinct from a binding failure. They are
  very different findings.

### 5.6 onionxt's selftest tears down live state, on purpose

OnionXT's connection / service / stream state is a script-local singleton shared by the
whole message path, and `oxSelfTest()` proves teardown is idempotent by actually
calling `oxDisconnectControl` / `oxShutdown`. **If a live demo session has an open
control connection, streams, or published services, running the selftest closes them.**
Run it in a fresh session, or expect it to tear down whatever is open.

It also **resets the configuration**: the new "configuration setters" section walks
`oxSetSocksPort` / `oxSetControlPort` / `oxSetControlPassword` and clears them back to
their defaults on the way out, so a non-default port you set by hand before running it
is gone afterwards. Set your ports *after* the selftest, not before. The three dispatch
setters are deliberately restored rather than cleared — to owner `me`, status
`onStatus`, no peer callback — which is exactly the configuration
`onionxt/examples/onionxt-demo.livecodescript` establishes in `preOpenStack`, so running the
selftest from the demo's About tab leaves the demo working.

### 5.7 Give the DHT a few seconds

A brand-new torrentxt session has to bootstrap into the swarm. Quick Share, Channels,
and the datachannelxt DHT chat all need peers found before the first transfer. "No
peers" in the first few seconds is expected, not a failure. Both peers must be online
at the same time.

### 5.8 Bootstrap events only fire while bootstrapping

Connecting to a tor already at 100% delivers no `STATUS_CLIENT BOOTSTRAP` events, so a
UI seeded at 0 stays at 0 and looks stuck. onionxt queries
`GETINFO status/bootstrap-phase` once on connect to seed it. A progress bar sitting at
0 against an already-bootstrapped daemon is cosmetic, not a hang.

---

## 6. If it fails

The goal of this section is simple: **make one failure diagnosable without a second
engine session.** Capture all four of these, every time:

1. **The full result text.** Not the summary count - the whole `stResults` field (or
   the whole message-box report). The failing line's neighbours carry the context.
2. **The exact handler that failed.** The selftests name the handler in each check
   line; quote it verbatim, including the arguments if the line shows them.
3. **The member's last-error string,** queried from the message box immediately after
   the failure, before you do anything else:

   | Member | Query |
   |---|---|
   | sodiumxt | `put sxLastError()` |
   | torrentxt | `put btLastError()` |
   | enetxt | `put enLastError()` |
   | datachannelxt | `put dcLastError()` |
   | onionxt | no `oxLastError`: the failing command returns an `"OnionXT: ..."` string through `the result`, so capture `the result` at the failure point |
   | coinxt | no `cxLastError`: the `cx*` handlers **throw**, with the handler named in the message (`"CoinXT: cxSha256: ..."`), so wrap the call in `try` / `catch` and record the caught error verbatim |

   **The shim last-error cannot answer for the POLL PUMP, and the pump is where
   this suite's quietest failures live.** Three stacks in the 3.2 run order embed
   the poll helpers - `datachannelxt/examples/datachannel-loopback.livecodescript`
   (row 7), `enetxt/examples/enet-lan-chat.livecodescript` (row 8) and
   `datachannelxt/examples/datachannel-dht-chat.livecodescript` (row 13) - and
   those pumps keep a failure note of their own. `dcLastError()` / `enLastError()`
   report the last SHIM call; a throw inside the DRAIN (`dcPoll` / `enPoll`) or
   inside the DISPATCH is a script-side error the shim never sees, and it is the
   failure that makes a demo simply go quiet. The note names what threw: the event
   for a dispatch fault (`dispatch of <name> failed: ...`), the DRAIN NUMBER for a
   drain fault (`dcPoll failed on drain #N: ...`, `enPoll failed on host ...`),
   and - for datachannel - a poll target that stopped resolving.

   **CAPTURE THE DEMO'S OWN LOG FIRST.** `enet-lan-chat`'s `ecDashOnce` and
   `datachannel-dht-chat`'s `wxDashOnce` read the note about once a second, print
   it (`* event pump problem:` / `Event dispatch problem:`) and then CLEAR it - so
   by the time you reach the message box the note is usually gone, into the log
   line you are being asked to copy. Copy that line verbatim; it is the whole
   product of the pass.

   `put dcPollLastError()` / `put enPollLastError()` is the fallback for those
   two, and it is the PRIMARY query for `datachannel-loopback`, which reads the
   note only from its connect watchdog and only when the channel never opened -
   otherwise nothing consumes it and it is still sitting there. These are
   stack-script handlers, not extension handlers, so query them with the demo
   stack as the top stack. `dcPollClearError` / `enPollClearError` clear the note
   by hand if you want a second attempt to report fresh instead of repeating the
   first failure.

   (Read off the shipped helpers and the demos that consume them - verified
   statically; needs an OXT pass. The dated part is `docs/OXT-ENGINE-NOTES.md`
   6.6, which records the 2026-08-18 Linux and Windows reports and why the drain,
   not only the dispatch, had to be guarded.)

4. **The environment.** OXT version, OS and architecture, which extensions were loaded
   (`sxVersion()` / `enLibraryVersion()` / `dcLibraryVersion()` / `oxVersion()`), and
   for anything Tor-flavoured, which daemon and which ports.

Then, before filing it:

- **Rule out the machine.** If it is a loopback failure, check trap 5.5.
- **Rule out a second session.** If it is torrentxt, check trap 5.1.
- **Re-run once with the `stRerun` button.** A failure that does not reproduce is
  itself a finding worth recording (it usually means a timing or teardown-ordering
  issue), and it is much cheaper to notice now than to rediscover later.
- **Note whether it is a bind failure or a behaviour failure.** "The module would not
  load / the handler was not found" is a different class of bug from "the handler ran
  and returned the wrong bytes", and they route to different fixes.

An ABI-mismatch symptom is worth calling out by name: if a member's handlers resolve
but behave nonsensically, check that the installed native library and the binding are
the same ABI version. Every member carries a guard for exactly this: `_checkABI()` in
torrentxt / enetxt / datachannelxt, `sPrepare()` in sodiumxt, and the public
`cxCheckABI` in coinxt. A stale committed binary against a newer binding is a real and
previously seen failure mode.

---

## 7. The tick sheet

Copy this into your notes and fill it in as you go. Lines marked `[x] 2026-08-08`
are already done and recorded — leave them as history and fill in the rest.

```
Environment: OXT version ______  OS/arch ______  date ______

PREREQ  <- one paste answers all but the last line: tests/preflight.livecodescript
[ ] platform binaries present or fetched (section 2.1)
[ ] tests/preflight.livecodescript pasted + reopened (3.1). It prints ONE
    found-vs-expected ABI table; screenshot it, or use its Copy results button.
       summary:  ____ passed  ____ failed  ____ skipped
       engine:   platform ______  processor ______  engine version ______
       SodiumXT ......... LOADED / NOT INSTALLED / ABI SKEW
       TorrentXT ........ LOADED / NOT INSTALLED / ABI SKEW
       enetxt ........... LOADED / NOT INSTALLED / ABI SKEW
       DataChannelXT .... LOADED / NOT INSTALLED / ABI SKEW
       CoinXT ........... LOADED / NOT INSTALLED / ABI SKEW
       Box2Dxt .......... found ABI ______ vs expected ______ (the one READ number)
       OnionXT script layer present? ____   CoinXT script layer present? ____
       NostrXT script layer present? ____
    The expected numbers are printed BY the table - `tools/build-preflight.py`
    reads them out of the six C shims and `--check` re-derives them on every
    push - so nothing here needs retyping when an ABI is bumped. A SKIP is not a
    defect: that member is simply not installed on this machine. An ABI SKEW is,
    and it is the one this saves a session over - a mac with sodiumxt's
    universal-mac dylib blocks every sodiumxt test AND everything downstream,
    and this finds it at minute two instead of minute fifteen.
    NOTE: only Box2Dxt can report the number it FOUND. The other five guards are
    private handlers that throw an ABI message without exposing the value, so
    their rows are a three-way verdict rather than a comparison - the table says
    so rather than faking a column.
[ ] tor running with ControlPort 9051 + CookieAuthentication 1?  log line seen? ___

BREADTH
[x] tests/suite-selftest.livecodescript      2026-08-08: GREEN, zero failures,
                                             all six members present (no skips)
                                             2026-08-10: GREEN, the deep folds +
                                             embedded script layers; the re-run
                                             was 455 member checks + the core,
                                             ZERO failures (coinxt 207/207)
                                             2026-08-12: GREEN, 617 folded
                                             member checks, ZERO failures;
                                             riptide phase 2 was 133/133
                                             2026-08-13: GREEN, the
                                             REGENERATED harness (the widened
                                             enet/dc standalone async halves
                                             behind it), 617 folded checks,
                                             zero failures (platform not
                                             recorded in the pasted results)
                                             2026-08-17 (Windows, x86_64,
                                             NT 10.0, OXT 9.6.3): GREEN,
                                             1,836 folded member checks, ZERO
                                             failures, 7 skips - see the pass
                                             blockquote in this file for the
                                             per-member table. (No new number
                                             here: all four figures are that
                                             blockquote's. This line exists so
                                             BREADTH stops being three days
                                             stale.)
                                             2026-08-18 (Linux): the suite
                                             paste ran with ONE failure -
                                             box2dxt's "playLoudness readback".
                                             box2dxt's own section was 373
                                             passed / 1 failed at harness v29;
                                             the numbers and the diagnosis are
                                             in that harness's header
                                             (`box2dxt/examples/box2dxt-selftest.livecodescript`)
                                             and in OXT-ENGINE-NOTES 5.4.
                                             The SUITE-WIDE passed / failed /
                                             skipped counts were NOT captured.
                                             The Linux pass is commit 597ce0c;
                                             the only description of the whole
                                             paste from that session is commit
                                             7812241's "~1900-check", which is
                                             an approximation and is left as
                                             one here rather than promoted into
                                             a total. Arch and engine version
                                             were not recorded in the pasted
                                             results either.
                                             COMPARABILITY: the failing check
                                             was rewritten the same day and the
                                             harness is v30 now - one assertion
                                             MORE than v29 - so neither this
                                             total nor the 2026-08-17 one is
                                             comparable to a future v30 run,
                                             and no v30 total has been observed
                                             on any platform.

DEPTH (per-member selftests)  <- closed 2026-08-10 via the folded suite runs
[ ] nostrxt folded sections (nx1, inside the suite paste - item 33): summary
    line ____ passed ____ failed ____ skipped; event C utf-8 verdict ____;
    NIP-44 seam verdict ____
[ ] nostrxt live relay (item 34): ws:// handshake/REQ/publish ____ ;
    wss:// observed behaviour recorded in engine notes? ____
[x] sodiumxt   sxSelfTest()                   2026-08-12: 71/0 (latest folded run)
[x] enetxt     enet-selftest                  2026-08-10: 21/0 (folded, twice);
               async loopback standalone 2026-08-07; and CLOSED 2026-08-13:
               the standalone ran green end to end WITH the live status
               assertions (enHostStatus pair, enPeerStatus rtt/packetLoss/
               counters, zero peers after disconnect). Nothing static
               remains in this file; two-machine LAN chat rides item 6
[x] datachannelxt  datachannel-selftest (sync)  2026-08-10: 23/0 (folded, twice);
               and CLOSED 2026-08-15: the standalone ran green end to end WITH
               the async loopback (real SDP w/ candidates, offer/answer roles,
               gathering complete both peers, selected pair, text + binary incl
               NUL, cap-sized send). Nothing static remains in this file;
               browser interop + a two-network call ride outside the selftest
[x] torrentxt  torrent-selftest               2026-08-10: 96/0 (folded, twice;
               shares the core's single session by design)
[x] onionxt    oxSelfTest()                   2026-08-10: 40/0, 3 sha3 skips by
                                             design (docs/08 gap #2). NOTE: gap #2
                                             is now SHIPPED (SodiumXT ABI 7), so on
                                             an ABI-7 engine those 3 are no longer
                                             skips - the offline-address checks run
[x] onionxt    offline .onion address        2026-08-12 (Windows x64, ABI 7):
                                             43/0 - the ex-skips ran; torproject
                                             + DuckDuckGo onions re-encoded
                                             byte-exactly, tamper refused,
                                             offlineAddress advertised true
                                             -> ITEM 9 CLOSED
[x] coinxt     .lcb items 1-5 in order        2026-08-08: 1:PASS 2:PASS(via sPrepare)
                                             3:PASS UIntSize return works
                                             4:PASS empty Data marshals
                                             5:PASS vectors byte-exact
                                             -> PHASE 1 CLOSED
[x] coinxt     coin-selftest                  2026-08-10: 205/206, then 207/207
                                             on the re-run (the red line was the
                                             "m/" fail-open, fixed same day)
                                             -> PHASES 2-4 CLOSED
[x] coinxt     coin-selftest phase 5         2026-08-12 (Windows x64): 230/230,
                                             the BIP-143 signed tx byte-for-byte
                                             on engine, both new refusals firing.
                                             The headless net (251 checks) had
                                             caught + fixed the trailing-empty-
                                             scriptSig defect first.
                                             -> PHASE 5 CLOSED
[x] riptide    rsSelfTest() phases 1-2       2026-08-12: 133/133 combined, 0 skipped;
                                             phase 1's first 89 checks cover the
                                             sealed key file, KDF tree, handle <->
                                             onion, RSH1/RSP1, and post chain;
                                             -> ITEM 7 / PHASE 1 CLOSED. The live
                                             feed sections: BEP44 buffer vs
                                             btDhtBep44SignBuf, golden targets
                                             from real puts, btDhtPutSigned
                                             accepting the script-built buffer's
                                             signature, ingest verifiers
                                             -> ITEM 10 CLOSED; propagation
                                             (second machine) rides item 6

DEMOS
[ ] datachannel-loopback     (if it goes quiet: dcPollLastError() - section 6
                             item 3's poll-pump paragraph; this is the ONE
                             stack where that note is usually still sitting
                             there unconsumed)
[x] enet-lan-chat            (one machine / two machines: ONE)
    2026-08-18, Linux: UI built, session started, hosting on port, no second
    peer available. The run was NOT clean - the dashboard threw every second,
    from ONE fault: `the number of keys of sPeers` in the status line, which
    does not parse (OXT-ENGINE-NOTES 1.7). It was fixed the same session. A
    stack pin (5.3) landed one commit earlier and did NOT stop it; the throw
    was in the ARGUMENT, evaluated at the call site, so it never reached the
    handler the pin protects. This line said "twice over" until the sweep of
    2026-08-19 traced it - two fixes is not two faults. Re-run after the fixes reported working on single-machine
    testing; environments not captured, maintainer's dated account. Two
    machines still OWED: inventory row 6 and closing-pass leg B are unchanged.
    If it goes quiet, read the demo's own log first, then enPollLastError() -
    section 6 item 3's poll-pump paragraph.
[ ] torrent-quickshare
[ ] torrent-client
[ ] onionxt demo vs live tor
[ ] torrent-quickshare with Tor toggle ON     (no torrent created? ______)
[x] datachannel-dht-chat     (needs torrentxt + two machines)
    2026-08-18, Linux: UI built, chat hosted, no second peer available. The run
    threw in the poll pump (OXT-ENGINE-NOTES 6.6), which the instrumented pump
    then traced to the dcLocalDescription event/handler collision (6.7); a
    second report narrowed the drain half on Windows. Re-run after the fixes
    reported working on single-machine testing; environments not captured,
    maintainer's dated account. Two machines still OWED: inventory row 6 and
    closing-pass leg E are unchanged. If it goes quiet, read the demo's own log
    first, then dcPollLastError() - section 6 item 3's poll-pump paragraph.
[ ] torrent-dht-channels / torrent-rp1-chat   (two machines)
[ ] onionxt Mode B: oxLaunchTor               processId: ______  bootstrapped: ___
[ ] coinxt-demo (phase 6: mnemonic -> decoded, signed BTC+ETH tx)
[ ] sodium-demo
[ ] onion-httpd spike (Share a Folder; needs a tor daemon)
[ ] suite-closing-pass legs                    (which legs ran: ______)
--  box2dxt's five GAMES had no rows here until 2026-08-17, so no session was
--  ever told to open them. Its selftest runs inside the suite paste; these do
--  not, and each is a window nobody has confirmed builds.
[ ] box2dxt-demo               (the showcase: shapes, joints, events)
[ ] box2dxt-platformer         (levels, camera, player states)
[ ] box2dxt-slingshot
[ ] box2dxt-contraption-builder
[ ] box2dxt-spike-gamekit
[x] riptide-social  2026-08-13: TWO machines - identities created on both
                    sides, feeds published and received in BOTH directions
                    through the real DHT; every rendered post ingest-verified
                    -> PHASE 2's DONE-CRITERION MET (the riptide leg of item
                    6). Environments not captured; maintainer's dated account
[ ] suite-closing-pass (row 18; ONE stack for the legs still open above)
      A dc local async      CLOSED 2026-08-15 standalone   (skip this leg)
      B enet chat           (two machines)                 PASS lines: ______
      C seed/leech + resume (two machines; restart? _____) PASS lines: ______
      D rp1 chat            (two machines)                 PASS lines: ______
      E dc chat via DHT     (two machines; pair: ________) PASS lines: ______
      F Mode B + onion echo (single machine + tor binary)  PASS lines: ______

ADDED 2026-08-15 (inventory rows 11-24; the sparse-access plan at the top
maps each to a session type - S1 one machine, S2 +tor, S3 two machines,
S4 two machines +tor, S5 mac/windows)
[x] 11 suite paste: "ristretto255 (ABI 8)" RAN, not skipped     ABI seen: 9
       2026-08-17 (Windows x86_64, NT 10.0, OXT 9.6.3): ABI 8 AND ABI 9 both
       ran - mask/unmask roundtrip, batch over 3 points, k*(P+Q) identity, and
       one bad point failing the whole batch naming index 2 of 3. sodiumxt
       reported 99 checks in that run's per-member table. The "ABI seen" answer
       is the preflight's own "SodiumXT 9" line
[x] 12 suite paste: "WIF (wallet import format)" green
       2026-08-17 (same run): all four framing legs plus the refusals,
       including an xprv refused on payload LENGTH, not version byte. coinxt
       reported 278 checks at CoinXT ABI 6
[ ] 13 suite paste: LAN-sync section + serving seams + the three
       UTF-8 refusal re-pass lines all green
[ ] 14 holde-em deal re-pass: heXorSeedsHex / heDeckFromStreamKey
       lines green (pre-fold stream question answered? ______)
[x] 15 holde-em section 16 (L2) RAN, not skipped   sx* shapes ok? yes
       2026-08-17 (same run): Level 2 + Phase 5 DLEQ green FOLDED - a wrong
       unmask refused INSTANTLY and named, with no audit round; all five
       cheater bots detected and attributed. holde-em reported 538 checks
[ ] -- holde-em hotseat on v0.24.5 (hands played: ___  side pot? ___)
[ ] -- restyle re-opens (UI built, probe clean): quickshare ___
       dht-channels ___  riptide-social ___  onionxt-demo ___
       enet-lan-chat ___  dc-loopback ___  torrent-client ___
       coinxt-demo ___  nocloud ___   (record per DEMOS rows too)
[ ] 22 nocloud checklist: web-link half ______   Tor half ______
[ ] 21 Channels  #31 ___  #32 ___  #33 ___  (tick the 12.3 register itself)
[ ] 19 riptide phase 7: serving half (page/prekey/dm) ______
       anon delivery + zero-bt* trace ______
[ ] 20 holde-em 2f: bring-up states ___  address == oxServiceAddress? ___
       two-machine multi-hand onion session ______
[ ] 16 riptide phase 5 call  CONNECTED? ___  via: ______  typing lane ___
[ ] 17 riptide phase 6 mesh  welcome ___  draft criterion ___  stranger ___
[ ] 18 holde-em 2d online session (machines: ___  seats: ___  receipts ___)
[ ] 23 Windows ABI-8 re-proof   x86_64-win32: ___   x86-win32: ___
[ ] 24 mac builds: sodiumxt lipo ABI8 ___  coinxt ___  enetxt ___
       datachannelxt ___  torrentxt (signed?) ___  then S1 run: ______
--  THIS BLOCK STOPS AT 24 BY CONSTRUCTION - its header scopes it to inventory
--  rows 11-24, and rows 25-32 were added later without tick lines. So the
--  2026-08-17 closures of rows 25, 26, 27, 30 and 32 are recorded on the
--  INVENTORY ROWS THEMSELVES and nowhere here. Row 31 (box2dxt) has run folded
--  and green but is deliberately NOT closed: the harness is at v30 and no v30
--  total has been observed on any platform, so the next pass RECORDS the v30
--  total rather than matching 372 or 374.

FOLLOW-UP
[ ] result text saved for every run above
[ ] honesty labels listed in section 4 updated in one pass
[ ] root README.md release-status table reconciled last
```

---

> **After the pass.** Every result recorded here becomes a documentation edit, and the
> point of section 4 is that the edits are already enumerated: each item names the exact
> file and the exact sentence to change. Do them in **one** follow-up pass, members
> first and the root `README.md` last, so the suite front door never claims more than
> the members do. Anything you did not observe stays labelled "verified statically;
> needs an OXT pass" (Tor paths: "+ live-Tor pass"). A partial pass honestly recorded is
> worth more than a full pass generously described.
