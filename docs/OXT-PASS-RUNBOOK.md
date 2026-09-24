# The OXT engine pass runbook

**Scope: the whole suite. Audience: the person sitting at a real OpenXTalk engine.**
This file holds OPEN engine work only. A closed leg is one line in section 8; its
full record lives in the member's `CLAUDE.md` evidence ledger. Open work that is
not an engine leg is in [WORK-PLAN.md](WORK-PLAN.md).

> **Read [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) first, and add to it after.**
> It lists what the engine does that no gate predicted, with verbatim symptoms.

Everything labelled "verified statically; needs an OXT pass" waits on a session
like this. OXT has no headless way to compile or run `.lcb` / `.livecodescript`,
so CI proves the native shims and the pure-compute vectors but never that a
binding **loads**, that a foreign declaration **marshals**, or that a handler
**returns what the docs say**.

**The evidence rule.** A result flips a label only on a dated, recorded run (4.1:
the full result text plus OXT version, OS/arch, date and loaded extensions). A leg
that only partly ran records exactly the part that ran. Every session ends with
4.1's copy-back, then ONE label pass covering exactly what ran ("After the pass").

---

## The session plan

The open backlog is partitioned by the resources each leg needs, so whoever gets
engine time runs the session that matches what they have. Each table's `#` is a
stable citation key (code and docs cite "S1 row P", "S1 item 4", "S2 item 2", "S4
item 3"); rows are in run order. Each leg's green criterion and the labels it
flips are in its section-1.2 row.

| Session | Resources |
|---|---|
| S1 | one machine, no daemon |
| S2 | one machine plus tor: a system tor with the 2.3 torrc; Tor Browser for reach checks; a tor BINARY on disk for Mode B; curl |
| S3 | two machines on one LAN (not guest wifi, which isolates devices), UDP allowed; a second network (a phone hotspot) for the srflx done-criteria |
| S4 | two machines plus tor on both; packet capture on both ends; Tor Browser on the follower |
| S5 | a Mac, or a Windows box (32-bit engines too, where they exist) |
| NET / 2NET / 3M / PERSON | internet only (a public relay, testnet coins, a real swarm) / two machines on different networks / three machines / a human judgement |

On a day with more than one resource, run S1 first: it is the cheapest signal.
Trap 5.1.1 (quit and relaunch OXT before every torrent-bearing paste) governs
every session.

### S1 - one machine, no daemon (estimate 3-4 h for all of it)

A Windows engine, then a Linux one (x64 or x86); **the Linux machine needs glibc
2.38 or newer** to load all six native members (2.1). All six packaged extensions
installed from the current tree (section 2). **This is the first engine contact
for the 2026-09-12 binaries** (release run 34657390798 from `0f17ab5`, committed
as `421bab3`): record which DLL/`.so` row loaded; a regression is a finding about
those builds, not about the script.

| # | Run | Expect / record | ~min |
|---|---|---|---|
| 0 | `tests/preflight.livecodescript` (3.2) | six LOADED; Box2Dxt found 4 | 5 |
| 1 | `tests/suite-selftest.livecodescript` | RECORD every member total (below), do not match it; wait for `summary` (4.1.1); row 31 | 30 |
| P | engine-notes probes, message box | row P | 5 |
| Q | coinxt ABI 7 + silent-payment receive | row Q (its wallet half needs NET) | 20 |
| 3 | `riptide-social`, then `torrent-quickshare` and `torrent-dht-channels`, one fresh launch each | rows 35, 37 | 20 |
| 2 | `holde-em/src/holdem.livecodescript` standalone, then `heRunSelftest` in the message box | ends `==== N pass, 0 fail, M skip ====` and `RESULT: green`; row 14 | 15 |
| 4 | holde-em hotseat in item 2's launch: 2-3 hands, blinds to showdown, a side pot if you can | hands complete, no error dialog; the header names `kHeVersion` **0.25.3**, harness **44**. Stretch: row 42's 6-seat exit | 15 |
| 5 | the remaining demo re-opens, one fresh launch each | rows 37, 38 | 60 |
| 6 | standalone `enet-selftest`, then `datachannel-selftest` | green, no `RUN NOT FINISHED` trailer (4.2, 4.3) | 10 |
| S | `nocloud/src/nocloudquickshare.livecodescript`, then its checklist's web-link half | row 22; row 46 if time allows | 75 |

Item 1's last records, to record against rather than match: sodiumxt 106,
torrentxt 101, onionxt 61, coinxt 290 (before ABI 7's six new lines), enetxt 34
and datachannelxt 39 (sync halves), nostrxt 274/0/2, riptide 0 failed with 2
skips (the live anon-service legs; 391/0 on 2026-08-24), box2dxt at harness v31 (374 expected), holde-em at
v0.25.3 / harness 44 with 0 failed and 5 live-transport skips. Whole paste:
2,373/0/3 (2026-08-24), 2440/2/3 (2026-08-27, both failures environmental). A new
total is not a regression by itself; a red line is.

### S2 - one machine plus tor (~3 h with setup)

S1's install; a system tor per 2.3 with its `Opening Control listener` line
confirmed; Tor Browser (SOCKS 9150, trap 5.3); a tor binary on disk for item 2;
curl for item 5. Every stack here carries its script layers (holde-em since
2026-08-27, nocloud since 2026-08-24) except `torrent-quickshare`, the one
`NOT_EMBEDDED` demo in `tools/sync-demo-embeds.py` (its own socket handlers carry
clearweb logic), which keeps an optional `start using stack "onionxt"`. Re-read
traps 5.3, 5.3.1, 5.4, 5.8. Items 3, 4 and 6 each take THE torrent session.

| # | Run | Row | ~min |
|---|---|---|---|
| 1 | `onionxt-demo` against the live daemon (the cheapest daemon-config disqualifier) with the B.12 probes; then the onion-httpd spike | 44 | 30 |
| 2 | `tests/suite-closing-pass.livecodescript` leg **F** (Mode B + onion echo) on 9250/9251 beside the system tor (5.3.1) | 4 | 25 |
| 3 | `torrent-quickshare`, Tor toggle ON, the single-machine halves | 5 | 25 |
| 4 | #31 in `torrent-dht-channels` | 21 | 25 |
| 5 | riptide phase 7 serving: `riptide/docs/two-machine-runbook.md` phase 7, steps 1-5 | 19 | 30 |
| 6 | holde-em onion-table bring-up | 20 | 20 |
| 7 | the Tor half of `nocloud/docs/oxt-pass-checklist.md` | 22 | 25 |
| 8 | onionxt's live negative paths | 44 | 20 |
| 9 | the onion round trip (two OXT processes) | 44 | 30 |

### S3 - two machines, no daemon (~3-4 h)

The current extensions on BOTH machines; `tests/suite-closing-pass.livecodescript`
pasted on both (nothing to `start using`); one LAN with UDP allowed, plus a
second network for srflx; riptide identities per the two-machine runbook's setup
(DIFFERENT for the call, the SAME for the mesh), every riptide device on the
post-2026-09-09 build (the LAN domain tags changed); one OXT process per stack
instance (5.1). Trap 5.5 if anything loopback-flavoured fails. **Open the right
port, on the right machine:**

| Leg | Port | On which machine |
|---|---|---|
| closing-pass leg B | UDP 27300 (`kEnetPort`) | inbound, on the machine that clicks Host |
| closing-pass legs C/D/E | libtorrent's listen port, dynamic: `btListenPort` (section A prints it) | inbound on both is ideal; the DHT usually traverses without it |
| riptide call + mesh | UDP 27099 (`kLanPort`) | inbound, on the mesh host |
| enet LAN chat demo | UDP 27099 (`kEcPort`) | inbound, on the machine that clicks Host |

| # | Run | Row | ~min |
|---|---|---|---|
| 1 | closing-pass legs B-E on both machines (leg A closed 2026-08-15: skip it) | 6 | 75 |
| 2 | riptide phase 5: the call, then the typing lane | 16 | 35 |
| 3 | riptide phase 6: welcome round, sync payload, stranger test | 17 | 35 |
| 4 | holde-em 2d re-run on v0.25.3 | 18 | 40 |
| 5 | holde-em 2e timed liveness session | 28 | 40 |
| 6 | member demos on two machines: `enet-lan-chat`, `datachannel-dht-chat`, `torrent-dht-channels` / `torrent-rp1-chat` | 6 | 45 |
| 7 | riptide's phase-3 faststart re-run and phase-6 steps 7-8 | 41 | 30 |

### S4 - two machines plus tor (~3 h)

S3's state plus S2's tor prerequisites on BOTH machines (the follower dials
through its own SOCKS; item 4's POST needs curl and SOCKS on the posting machine);
Tor Browser on the follower; packet capture on both ends for items 2-3; give the
DHT its seconds (5.7); publish onions fresh (5.4).

| # | Run | Row | ~min |
|---|---|---|---|
| 1 | #32: A publishes an anon channel, B follows by the CARD only | 21 | 30 |
| 2 | #33: B downloads a release entirely over the onion | 21 | 40 |
| 3 | the two-machine Quick Share Model C gate | 5 | 30 |
| 4 | riptide phase 7, the finishing half | 19 | 30 |
| 5 | holde-em 2f exit: a multi-hand onion session | 20 | 45 |

### S5 - a Mac, or a Windows box

**Windows (~1 h per bitness).** Rows 23 and 47: install the current packages, run
the preflight and the suite paste, record OS, bitness and `put sxVersion()`. A
64-bit-only day proves only `x86_64-win32`: say so. Spare time goes to S1.

**Mac (~1 h, then S1 as time allows).** Row 24: an ordinary engine pass, not a
build session (CI built every universal dylib: release run 12, 2026-08-27, rebuilt
2026-09-12). Install the six packages, run the preflight and the suite paste,
`put b2Version()` (4), then the box2dxt spike for row 38's R1. Record the
first-load behaviour verbatim (2.1).

### NET, 2NET and 3M legs

These fit no S-session: row 34 (nostrxt relay receive, NIP-42, `ws://`, a bad
certificate); row 41's phase-8 live leg; row 43 (coinxt broadcast, wallet
surface, Core regtest); row 45 (torrentxt on a real swarm); rows 39-40 (2NET);
row 42's oracle round (3M + tor).

---

## 1. What is open

### 1.1 What CI proves, and what only an engine can

| Layer | Who proves it | Headless? |
|---|---|---|
| native shim over the vendored library | the member's smoke test under ASan/UBSan (+ TSan for datachannelxt) and its golden/record/KAT harnesses | yes, on every touch |
| pure-compute script logic | the KAT tools and the family interpreter (`check-script-vectors.py` and siblings) | yes |
| cross-member handler names | `tools/check-handler-calls.py` | yes, names only |
| cross-member crypto | `tests/cross-member-test.py` (ctypes over the built shims): one seed gives one ed25519 key in libsodium and libtorrent; libtorrent's DHT key is SodiumXT's expanded key; libtorrent verifies a libsodium BEP44 signature and refuses one for a different seq; `ENX_MAX_MESSAGE == DCX_MAX_MESSAGE == 60000` | yes |
| **the `.lcb` binding and every `.livecodescript`** | **an engine, and nothing else** | **no** |

So an engine failure is unlikely to be a handler-name typo or a crypto
disagreement: expect marshalling, ordering and environment. A failing
cross-member check points at the binding, not the crypto.

### 1.2 The open inventory

Row numbers are stable (code and docs cite them); closed numbers are in section 8
and are never reused. Every dated result also becomes one row in the member's
`CLAUDE.md` evidence ledger.

| Row | Leg | Where | Green looks like / record | Flips |
|---|---|---|---|---|
| P | the engine-notes probes (engine notes 2.4 and 2.5, DOCUMENTED until run) | S1 | One line at a time in any stack's message box; record EXACTLY what prints. (a) `put 9007199254740993 + 0`, then `put (9007199254740992 + 1 = 9007199254740992)`: `9007199254740992` (or a neighbour, never `...993`), then `true`; the `+ 0` matters, since a bare literal may echo its own spelling. (b) `put "abc" into x`, then `put (x is not an integer or x < 1)`: `true` with NO error (a silent text comparison); then `put (x is not an integer or x + 0 < 1)`: an ENGINE ERROR. If that last line prints `true` the engine short-circuits: REWRITE 2.5, do not promote it | 2.4 and 2.5 to OBSERVED, with the date and the exact text |
| Q | coinxt ABI 7 and silent-payment receiving | S1 (+ NET for the wallet: a backend, a little testnet coin) | The "secp256k1 keys" section's six `cxPubkeyCombine` lines green (G+G is 2G, one key is itself, the intermediate-infinity sum, three refusals): the first `Data`-of-many-keys shape this binding has marshalled. Then `coinxt/examples/coin-wallet.livecodescript` on TESTNET with the test seed (never a seed holding real value: OXT script memory is not locked, per the custody section of `coinxt/docs/wallet.md`): Receive shows a `tsp1...` address and "Copy silent-payment address" fills the clipboard; pay it from Send; on Tools, with a backend chosen, paste the paying transaction ALONE and press Inspect: it logs `Asked <host> for the N transaction(s) these inputs spend`, then "finished", and the result box repaints `FOUND:` with the taproot address from the socket callback (the unproven half); Addresses gains the record; Save writes an `sp` line; a second Inspect scans without a request. Offline: one prevout script per input below the transaction. A refusal on the mac dylib is a finding about the build: say which | `cxPubkeyCombine` and `cwSpScan` in `coinxt/CLAUDE.md` (its Status paragraph) and `coinxt/docs/wallet.md` |
| 4 | onionxt Mode B, closing-pass leg F (record per 4.7) | S2 item 2 | `oxLaunchTor` writes its torrc and starts tor; the control port authenticates against the LAUNCHED tor; bootstrap reaches 100%; the onion echo returns exact bytes both ways; `oxStopTor` twice. Also the first OnionXT-to-OnionXT dial on record | the Mode B VERIFY item in `onionxt/CLAUDE.md` (the processId / open process line); the intro of `onionxt/docs/10-usage-guide.md`; `onionxt/docs/07-tor-lifecycle.md` Mode B; engine note 6.3 |
| 5 | Quick Share over Tor, Model C | S2 item 3; S4 item 3 | One machine: a Tor share code minted with NO torrent created and NO DHT call (the mutual exclusion is the invariant); folder-serving renders in Tor Browser; optionally a second OXT process receives the code. Two machines (the 12.4 gate of `docs/ONIONXT-INTEGRATION-PLAN.md`): a real file both directions with the toggle ON, byte-identical (sha256), an onion-only capture, passphrase reject then decrypt, downgrade refusal | both honesty comments in `torrentxt/examples/torrent-quickshare.livecodescript` (near the `kTorCodePrefix` constants and above the Model C block); the 12.3 register items that ran |
| 6 | the two-machine legs | S3 items 1, 6 | Closed: riptide propagation (2026-08-13), media + DMs (2026-08-15). On 2026-08-27 the maintainer reported rp1 chat and the DHT-signalled WebRTC chat WORKING across two machines on one LAN; for those, the closing-pass PASS lines and row 40 remain. Owed: leg B (enet chat: "peer connected", text and binary with a NUL echoed byte-exact, a graceful disconnect); leg C (seed/leech with a hash-verified payload, plus resume saved to disk and re-added across an OXT restart); leg D (rp1 chat over a DHT rendezvous); leg E (dc chat signalled over the real DHT; the selected-pair line records host vs srflx); `enet-lan-chat` (joins/leaves announced, lines relayed through one `enBroadcast`, RTT on the dashboard); `datachannel-dht-chat` (Host, room code, Join, OPEN in 10-30 s, the direct/TURN readout); `torrent-dht-channels` and `torrent-rp1-chat` between two machines | `enetxt/CLAUDE.md`'s LAN-chat line; both chat demos' headers; the two-machine seed/leech and resume line of `torrentxt/CLAUDE.md`'s Status |
| 14 | holde-em deal-path re-pass | S1 item 2 | The fold rewrote `heXorSeedsHex` (its ignored `repeat ... step 2`) and `heDeckFromStreamKey` (its throw-in-catch); green is those sections matching their KAT pins. Closable at inference strength, as row 26 was (work plan): section 11's "seeds XOR" and "full shuffled deck" assertions ran green in every folded run from 2026-08-17 on, and engine note 3.1 (OBSERVED: `step` is not honoured) answers which stream the pre-fold runs dealt from | the re-pass note on the two deal handlers in `holde-em/CLAUDE.md` |
| 16 | riptide phase 5, the call and typing lane (script: the two-machine runbook's phase 5) | S3 item 2, across two networks | `CALL CONNECTED: direct peer-to-peer channel open` on both sides with a `via` line (`typ srflx` across two networks is the done-criterion); `the far side is typing...` appears and clears; hang-up leaves the DM alive | `riptide/CLAUDE.md`, phase 5 |
| 17 | riptide phase 6, the LAN mesh | S3 item 3 | `ADMITTED - the host ... Mesh is mutual.`; `draft from <name> seq N applied` in BOTH directions, converging; `[typing]` then `[quiet]` on a kill; `feed seq N adopted`; `a peer FAILED admission (not your device)` for a stranger, with no record crossing. Steps 7-8: row 41 | `riptide/CLAUDE.md`, phase 6 |
| 18 | holde-em 2d, online Level 0 over rp1, on v0.25.3 | S3 item 4 (3+ seats via extra instances) | several hands complete on every seat; receipts match; the audit verdicts land in the net feed; the lobby overlay is dismissed at handStart (the 2026-08-27 defect, fixed statically) | the 2d status in `holde-em/CLAUDE.md` |
| 19 | riptide phase 7, the anon persona over Tor | S2 item 5 (serving); S4 item 4 (finishing) | Serving (two-machine runbook phase 7, steps 1-5): the anon feed page renders in Tor Browser; `/prekey` returns 264 hex and `rsVerifyPrekey` proves it; a curl POST to `/dm` answers `accepted`, and `refused` when mangled or replayed. Finishing: B builds a sealed intro with its PUBLIC identity and POSTs it to A's onion through tor; `accepted`, A's Anon card logs the PROVEN sender handle, and a trace shows zero `bt*` calls for the persona | `riptide/CLAUDE.md`, phase 7; the two-machine runbook's phase-7 intro |
| 20 | holde-em 2f onion tables | S2 item 6 (bring-up); S4 item 5 (exit) | Bring-up: the lobby Tor pill walks its states; the invite prints as `<64hex>@<56base32>.onion`; the offline-derived address equals `oxServiceAddress` at publish. Exit: a multi-hand onion session joined by that invite, failures only where scripted, each fail-closed and readable; a real host-stream loss, redial and a trimmed resync | the 2f status in `holde-em/CLAUDE.md` |
| 21 | Quick Share Channels anon, #31-#33 (the 12.3 register's numbering in `docs/ONIONXT-INTEGRATION-PLAN.md`; the criteria are carried here in full) | #31: S2 item 4; #32, #33: S4 items 1, 2 | **#31** (`torrent-dht-channels`): Anonymous ON drives the `chTor` pill to "Tor: ready" with the onion service up; OFF is refused while an `onion:` release is listed (removal offered; built 2026-09-24) and otherwise leaves every clearnet channel bit-for-bit unchanged; tor absent shows the fail-closed messages and public channels are untouched; `chVerifyOnionIdentity` passes offline; the `chTor` pill and `chAnon` button fit the unchanged 1180x640 window. **#32**: A publishes an anon channel; B follows by the CARD only; the signed feed arrives over the onion with the DHT OFF for that channel; releases list; the live `oxServiceAddress == chChannelOnionAddr(pub)` byte-compare holds (else `svc=` is the source of truth and the derivability claim drops, settling D-04); an old 2-field card recovers via the `chDashOnce` onion-retry. **#33**: B downloads a release entirely over the onion (swarm and DHT off); byte-identical (sha256); an encrypted release auto-decrypts; the transfers row shows the teal `Onion` source; a capture shows ZERO swarm/DHT traffic for that file on both ends; a publisher restart prunes the stranded relIds (`chPruneStrandedAnon`), and a follower asking for a relId the publisher no longer serves sees "not currently available" (built 2026-09-24), not a zero-byte file or a downgrade alarm | tick the register items themselves |
| 22 | the nocloud HTTP-host checklist, `nocloud/docs/oxt-pass-checklist.md` (69 items; its own record sheet) | S1 item S (web link); S2 item 7 (Tor) | Web link: sections 0-6a over `/<token>/` from a LAN browser plus `curl -i`, a second-origin page for section 5; the boot record reads all 49 controls PASS; the D-10 mtime probe is in section 4; section 2's "without JSON" needs a relaunch; budget 60-75 min. Tor: sections 1, 1a and 4 over the `.onion`; `/_qs/transparency` answers `both_ends_hidden:true`; HEAD gives 0 body bytes; concurrent shares see only their own routes. Sections 7-8: row 46 | the checklist; the stack header's re-pass label; D-10 on the mtime probe |
| 23 | sodiumxt's Windows DLLs: MSVC builds with libsodium 1.0.22, committed 2026-09-12 (the 2026-08-24 x64 proof ran on a mingw DLL that no longer ships) | S5 | On `x86_64-win32` AND `x86-win32`: LOADED at ABI 10; the full SodiumXT section (106) green, including SHA3, ristretto and the ABI-10 ChaCha20 xor; `put sxVersion()` shows `libsodium 1.0.22`. A 64-bit-only day proves only `x86_64-win32` | the Windows rows of `sodiumxt/CLAUDE.md`'s committed-binaries table; the root README's 32-bit note |
| 24 | the first Mac engine load (the builds closed 2026-08-27) | S5 | No OXT engine has loaded any of the six universal dylibs. Green: the preflight shows six LOADED, the suite paste's member sections run, `put b2Version()` returns 4; arm64, and Intel if available; record the first-load / Gatekeeper behaviour (2.1) | each native member's mac line; 2.1 |
| 28 | holde-em 2e liveness, a timed multi-machine session | S3 item 5 | a seat times out on wall clocks; the time-bank arms once per hand; two misses sit a seat out; a late joiner is seated at a hand boundary with identical fold state; a dial failure mid-redial still lets the election conclude; a parked table resumes when a seat returns; also attempt the recorded KNOWN EDGE | the 2e status in `holde-em/CLAUDE.md` |
| 31 | box2dxt's folded total | S1 item 1 | RECORD the v31 total, do not match it (v29 read 374, v30 375, v31 expects 374: different harnesses). `b2kFell` / `b2kSensorEnter` / `b2kContact` are dispatched by literal name: zero events means the fold's prefixing is wrong, not the dispatcher. On Linux the `playLoudness` line is an observation, not a verdict (engine note 5.4) | the STATUS of `box2dxt/examples/box2dxt-selftest.livecodescript`; `box2dxt/CLAUDE.md` |
| 34 | nostrxt's live relay, the inbound half (the send half closed 2026-08-24) | NET; a local relay for `ws://` | From `nostrxt/examples/nostrxt-demo.livecodescript` with CoinXT and SodiumXT: a REQ answered with EVENTs that VERIFY through the callback (no `REFUSED`), then EOSE; a NOTICE and a CLOSED observed; NIP-42 (`ok <id>: true` for the kind-22242 event, a `closed` reason starting `auth-required:`; message-box work until the demo gains a button); a deliberately BAD certificate (self-signed, expired or wrong-host): a `socketError` means refused, reaching "the server did not upgrade" means it fails OPEN; record it in engine note 6.8 WHATEVER it is. `ws://` is now the unproven form: its own leg against nostr-rs-relay or strfry on loopback | the STATUS header and the VERIFY at the `open secure socket` call in `nostrxt/src/nostr-relay.livecodescript`; `nostrxt/docs/05-relay-client.md`; `nostrxt/docs/07-capabilities-required.md` |
| 35 | riptide's phase-8 boot re-paste | S1 item 3 | The v11 boot ran 2026-08-29 at 9 passed / 1 failed; the FAIL was the self-check's own card-scope defect (engine note 5.6), fixed in the carried `scMissing`. Owed: one fresh paste reading **10 passed / 0 failed**; then the Nostr card offline: with CoinXT, Create/unlock shows `npub1...`; with no relay, Post reports "not sent"; Save/Load round-trips the RIPTAPP1 store. The re-land's `openStack` is byte-identical to the engine-proven body, and `riptide/tools/check-demo-boot.py` boots it headlessly (a model, not an engine) | `riptide/CLAUDE.md`'s v11 label; `riptide/examples/README.md`'s phase-8 label |
| 37 | the demo re-open fleet: restyled 2026-08-14 and re-carried since, so each stack needs a fresh open (its handler-logic evidence stands) | S1 items 3, 5; one fresh launch each | Copy the boot self-check block, or record a human judgement for a non-adopter. `start-here.livecodescript` (the launcher, itself an adopter; pasted into a stack saved in the repo root, per its header): self-check green and its LOADED line naming the installed extensions. `torrent-quickshare`, `torrent-dht-channels`, `torrent-client`, `torrent-rp1-chat`: self-check green, the card look, no error dialog on open or close. `onionxt-demo` with NO tor: its probes FAIL CLOSED (that is the pass), then the About tab's `oxSelfTest` green; the onion-httpd spike builds. `datachannel-loopback` (no engine record of its own yet): Connect gives connected + open on both sides, chat in both panes. `coinxt-demo` (no self-check): the test mnemonic's published BIP-84 / BIP-44 / ETH addresses, sign/verify, the P2WPKH and EIP-1559 transactions decode. `sodium-demo` (no self-check): all 7 tabs build, the About self-test green, the tamper case rejected. `nostrxt-demo`'s `ndTests` button ("Run nxSelfTest"): the "relay layer, offline paths" section, including `nxrSocketError` disowning a foreign socket, which SKIPs in the paste and has no engine record anywhere: 17 sections, 0 failed, 0 skipped. With one machine, a two-machine demo is recorded as "UI built, session started, no second peer available" | each stack header's re-pass label; the member's ledger |
| 38 | the five box2dxt games; risk R1 | S1 item 5 (Windows, Linux); R1 also S5 | `box2dxt-demo`, `-platformer`, `-slingshot`, `-contraption-builder`, `-spike-gamekit` from `start-here.livecodescript` (no self-check: a human judgement): each builds on its FIRST open (the 2026-08-27 launcher fix is itself unverified: engine note 5.5); the contraption Images panel does not throw; the platformer card fade reveals the level and the L7 vertical camera works; slingshot's own seven-item list passes. R1: `box2dxt-spike-gamekit` on Linux and a Mac, recording the S1-S12 verdicts | each example's STATUS; `box2dxt/CLAUDE.md` |
| 39 | `enet-internet-chat` across two networks | 2NET | The Host needs enetxt + torrentxt and UPnP UDP 27199 (or a forward); on one network the invite cannot hairpin (2026-08-27; the watchdog names it). Green: the pill reads INTERNET LIVE with a non-RFC-1918 remote; RTT/loss from `enPeerStatus`; a same-LAN run reads LAN ONLY | `enetxt/CLAUDE.md`, README and getting-started |
| 40 | datachannelxt's two-network call; browser interop | 2NET; S1 + a browser | Leg E or the DHT chat across two networks: a `srflx` / `prflx` selected pair (record `relay` honestly if both NATs force TURN). Browser interop needs a browser-peer page first (work plan): the channel opens, text arrives as a string, `dcSendData` as an ArrayBuffer | `datachannelxt/CLAUDE.md`'s open list; the root README row |
| 41 | riptide: phase 8 live; the faststart re-run; phase-6 steps 7-8 | NET; S3; S3 + a third device | Phase 8 (the two-machine runbook's phase 8, steps 0-9): the npub resolves in a web client; relays `OPEN`; `publish -> true`; a verified follow timeline (needs row 34's receive leg); both bridge halves (needs an app bridge reader, work plan); the guard refuses `nostr` for anon. Faststart: playback starts while visibly below 100% (measured negative 2026-08-27, fixed the same day). Steps 7-8: the media handoff and the three-device relay | `riptide/CLAUDE.md`; the spec's phase-8 item |
| 42 | holde-em's Phase 1 exit; the Phase 3 oracle round | S1 + PERSON; 3M + tor | A full 6-seat hotseat session with side pots and all 17 cards on screen, plus a confirming eye on the 720p layout. Two players and a non-playing onion oracle: kill the oracle mid-hand, then void and resume | `holde-em/CLAUDE.md` |
| 43 | coinxt's network legs | NET; S2 + NET; S1 + a local node | Four-family broadcast: legacy P2PKH is done in substance (the 2026-09-02 spend, section 8), so record it; owed are native P2WPKH from the wallet, EIP-1559 from the demo on Sepolia (broadcast externally), EIP-155 from the message box (`cxEthLegacySighash` / `cxEthLegacyEncode`). The wallet's post-2026-09-04 surface: BOLT11 and a runestone Inspect, BIP-322 from a taproot wallet checked in Core or Sparrow, a vault release after its height, the Ordinals and Vault screens, testnet4 with BIP-329 labels, Electrum on the mainnet onion. Use testnet, or the public test mnemonic for the mainnet Electrum leg; never a seed holding real value, because OXT script memory is not locked (the custody section of `coinxt/docs/wallet.md`). A Bitcoin Core 26+ regtest node: the Node-screen sandbox, `core-rpc`, `core-cli` (+ tor for `core-tor`), per section 9 of `coinxt/docs/bitcoin-core-plan.md` | the "What has not run on an engine or a node" section and the "Not run against a node" line in `coinxt/docs/wallet.md`; the coinxt README's broadcast line |
| 44 | onionxt's live probes | S2 items 1, 8, 9 (the round trip also S4) | Demo (S2 item 1): `onionxt-demo` against the system tor: the control connection authenticates, bootstrap progress seeds from GETINFO (trap 5.8), a service publishes and is reachable in Tor Browser; then the onion-httpd spike (`onionxt/examples/onion-httpd/spike.livecodescript`): Start, Share Folder, REACHABLE, and the listing renders and downloads in Tor Browser. B.12: a second service on the same local port refused; the raw accepted socket id recorded (settles engine note 6.2's live half); a stale `close socket` tolerated; the topStack callback owner; `oxWrite` into a closed stream errors. Negative paths: a wrong cookie gives authfailed, a bad onion gives a mapped REP, a stalled daemon times out cleanly. Round trip: `onionxt/examples/onion-roundtrip/roundtrip-example.livecodescript` with two OXT processes (or machines), tor and sodiumxt, a sealed round trip (fix the fields it reads first, work plan) | `onionxt/CLAUDE.md`; the VERIFY lines in `onionxt/src/onionxt.livecodescript`; the re-pass labels in the `onionxt-demo` and spike headers |
| 45 | torrentxt on a real swarm | NET; S1 per platform | A legal ISO magnet through to `torrentFinished` with a hash match; `btMoveStorage` actually moving and `btRemoveTorrent` actually deleting (`btMoveStorage`'s stale-id refusal is engine-proven, 2026-08-17; `btRemoveTorrent` has no refusal check, only the non-delete teardown call); a packaged fresh install per platform | `torrentxt/CLAUDE.md` |
| 46 | nocloud checklist sections 7-8 | S1 + a standalone build | 7, the webapp over a web link: Theater/Music `206`, `?dl` `.wav`, `pushState` reload/paste/Back, the `file://` fallback. 8: fail-closed launches without SodiumXT and without TorrentXT, each after an uninstall and a fresh launch (the TorrentXT-absent guard of 2026-09-09: window built, a "No transport" status line, no engine dialog); a clean shutdown via a standalone's Cmd-Q | the checklist's tallies |
| 47 | platform rows with no engine record | S5 (32-bit engines where they exist) | `x86-win32` for torrentxt and coinxt (coinxt's 32-bit DLL has never executed, even in CI) and sodiumxt (row 23); `x86-linux` for sodiumxt and torrentxt; the first Windows run of libtorrent 2.1.1. Green: the preflight LOADED and the member's sections green on that row, bitness recorded | the platform tables in each member's README and `CLAUDE.md` |

---

## 2. Install order and prerequisites

### 2.1 Platforms: check yours first

Every native member (sodiumxt, torrentxt, enetxt, datachannelxt, coinxt,
box2dxt) commits all five platforms (`x86_64-linux`, `x86-linux`,
`x86_64-win32`, `x86-win32`, `universal-mac`) plus `MANIFEST.sha256`;
`ls <member>/src/code/` is ground truth. The current binaries come from the
2026-09-12 release run, which no engine has loaded yet (S1). onionxt, nostrxt,
riptide and the apps are pure script.

- **macOS.** Every dylib is a genuine two-slice universal build (arm64 + x86_64),
  tested by CI on the runner that built it, and unsigned (the linker's ad-hoc
  signature, no notarization; accepted 2026-08-23). No OXT engine has loaded any
  of them (row 24), and Gatekeeper/quarantine behaviour is unrecorded: if macOS
  refuses a library, record the exact dialog or error and what cleared it (for
  example `xattr -dr com.apple.quarantine` on the downloaded package). If a Mac
  throws `SodiumXT: ABI mismatch`, the package predates release run 12
  (2026-08-27): repackage from the current `src/code/`, do not debug the member.
- **Windows.** The DLLs carry different upstream versions from Linux and mac:
  sodiumxt's are MSVC builds with libsodium 1.0.22 (D-08) and torrentxt's carry
  libtorrent 2.1.1 from vcpkg, against the pinned 1.0.20 and 2.0.11 elsewhere.
- **Linux glibc floors** (the highest `GLIBC_` version each committed `.so`
  needs, from `objdump -T`). An S1 Linux machine needs 2.38+ to load all six;
  Ubuntu 22.04 (2.35), Debian 12 (2.36) and RHEL 9 (2.34) cannot load
  datachannelxt, nor torrentxt's 32-bit build.

| Member | x86_64-linux | x86-linux |
|---|---|---|
| sodiumxt | 2.33 | 2.33 |
| torrentxt | 2.28 (manylinux, static OpenSSL) | 2.38, plus `libssl.so.3` |
| enetxt | 2.14 | 2.28 |
| datachannelxt | 2.38 | 2.38 |
| coinxt | 2.25 | 2.25 |
| box2dxt | 2.17 | 2.34 |

### 2.2 Dependencies and install order

**sodiumxt goes first: everything that composes anything composes it.** onionxt
needs sodiumxt ABI >= 6 AND a tor with the CONTROL port. torrentxt runs alone,
but its demos use sodiumxt (passphrase lock, private channels) and onionxt (Tor
mode); `datachannel-dht-chat` needs torrentxt for its DHT signalling. nostrxt
composes coinxt (BIP-340, sha256, ECDH) and sodiumxt; riptide composes sodiumxt,
torrentxt, coinxt and nostrxt (plus enetxt / datachannelxt per leg and onionxt
for the anon persona). enetxt, datachannelxt and box2dxt are independent.

Install the six packaged extensions through `Tools > Extension Manager`, in
order: sodiumxt (`org.openxtalk.library.sodium`), torrentxt
(`org.openxtalk.library.torrent`), enetxt (`org.openxtalk.library.enet`),
datachannelxt (`org.openxtalk.library.datachannel`), coinxt
(`org.openxtalk.library.coin`; 2.4), box2dxt (`org.openxtalk.box2dxt` - NOT
`org.openxtalk.library.*`). The native library resolves from inside the
extension: no loose library, no `sudo`, no `LD_LIBRARY_PATH`, no rename. onionxt,
nostrxt and riptide are pure-script layers, not packages: the suite paste and
every registered demo embed the layers they call (3.2); a real project uses
`start using` on the sources under `<member>/src/`.

**Verify each one loaded** (the preflight does all of this in one paste):

```
put sxVersion()          -- sodiumxt, e.g. "SodiumXT 0.1.0 (libsodium 1.0.20)"
put btStartSession()     -- torrentxt: a handle > 0. Then btStopSession it.
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put oxVersion()          -- onionxt (after start using, or in a carrying demo)
put cxKeccak256Len()     -- coinxt: prints 32
put b2Version()          -- box2dxt: prints the shim ABI, 4
```

`cxCheckABI` is declared `returns nothing`, so `put cxCheckABI()` proves nothing:
call it as a COMMAND, where silence is the pass and it THROWS on skew. `handler
not found` means the extension is not installed or not loaded: fix it first.

### 2.3 Tor: the daemon and the exact torrc

onionxt talks to a LOCALLY running tor; it does not embed, ship or (by default)
launch one. **tor opens SOCKS by default but never a control port unless asked**
(dialling out works against a stock tor; publishing a service and bootstrap events
do not), and **Tor Browser exposes no control port** (SOCKS `9150`; control `9151`
only if you enable it). The bring-up `torrc`, verbatim:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

Or as flags: `tor --ControlPort 9051 --CookieAuthentication 1`. `torrc` lives at
`/etc/tor/torrc` (Linux), `/opt/homebrew/etc/tor/torrc` (macOS Homebrew; Intel
`/usr/local/etc/tor/torrc`) or `%APPDATA%\tor\torrc` (Windows). Restart tor and
confirm the proof line in its log:

```
[notice] Opening Control listener on 127.0.0.1:9051
```

Prefer cookie auth over `HashedControlPassword` (tor writes the cookie; onionxt
reads it). Match the app ports: system tor 9050/9051; Tor Browser 9150/9151 only
if you enabled control.

### 2.4 coinxt

Nothing to build: all five libraries are committed at ABI 7 (44 `cnx_*`
exports). A local rebuild is `cd coinxt && sh native/build.sh pack` (a cross
build names its target: `pack x86-linux`). From `coinxt/`,
`python3 tools/package-extension.py --assemble` stages the package,
`--refresh-manifest` records a newly packed platform, and
`--lib <path> --platform-id universal-mac` installs a library built elsewhere and
REFUSES one missing any `cnx_*` export. Details: `coinxt/CLAUDE.md`.

---

## 3. The run order

### 3.1 The paste-and-reopen procedure (every stack)

Every selftest and demo is a single stack script that builds its own UI:

1. `File > New Mainstack` (a one-card stack).
2. `Object > Stack Script`.
3. Copy ALL of the `.livecodescript` file from a text editor, paste it into the
   stack script, and Apply.
4. **Close the stack window, then reopen it.** Reopening fires `openStack`, which
   builds the UI and starts the run; nothing happens until you do. (Or, from the
   message box: `send "openStack" to this stack`.)
5. When done, **close the window** so `closeStack` runs the clean shutdown
   (sessions flushed, hosts destroyed, `dcCleanup` / `enDeinitialize` /
   `btStopSession`).

**Never `File > Open Stack` a `.livecodescript` file:** a script-only stack opened
from disk does not build its GUI (engine note 5.5). Two harnesses are functions:
put the script where its handlers are in scope (a stack script, or a script-only
stack you `start using`) and call `put sxSelfTest()`
(`sodiumxt/examples/sodium-tests.livecodescript`) or `put oxSelfTest()`
(`onionxt/examples/onionxt-tests.livecodescript`).

### 3.2 Order of play

**The preflight first.** `tests/preflight.livecodescript` answers "can this
machine run the pass at all?" in one paste. `tools/build-preflight.py` generates
it and READS the expected ABIs from the C shims (sodiumxt 10, torrentxt 11,
enetxt 2, datachannelxt 1, coinxt 7, box2dxt 4), so nothing is retyped on a bump.
Only Box2Dxt reports the number it FOUND; the other five guards are private and
throw without exposing it, so their rows are a three-way verdict: LOADED / NOT
INSTALLED / ABI SKEW. A SKIP means not installed, not a defect; an ABI SKEW is the
defect it saves a session over. It ran green on its first outing, 2026-08-17.

**Then the suite paste**, `tests/suite-selftest.livecodescript`. It carries TEN
folded harnesses (sodiumxt, onionxt, coinxt, torrentxt, the sync halves of enetxt
and datachannelxt, nostrxt, riptide, box2dxt with the b2k Kit, holde-em) plus the
embedded script layers (coinxt, onionxt, riptide, the b2k Kit, nostrxt); an
absent member SKIPs. By design it does NOT fold the ENet/DataChannel async
loopbacks (S1 item 6) or holde-em's live game (unreachable by
`tools/check-suite-selftest.py` check 7d; S1 items 2 and 4). It is BREADTH; the
per-member harnesses are depth. ONE compile error takes the whole paste down
(43,366 lines, about 2 MB, on 2026-09-23). A layer-probe FAIL means the paste is
damaged: re-copy the whole file; a stale `start using` copy of a layer is
shadowed for the harness's own calls. **Coverage:** run
`python3 tools/check-suite-coverage.py`, never transcribe it. It read 864/878 on
2026-09-23; the 14 exemptions are all onionxt's (9 engine socket events, 2
watchdogs, 3 live-daemon: `oxLaunchTor`, `oxStopTor`, `oxTransportDial`). The
box2dxt row measures the Kit, not the raw `b2*` binding; holde-em's row is
advisory and not summed.

**Getting the paste onto the engine.** You never need Python on the OXT machine:
the suite paste and the preflight are generated and committed, each generator's
`--check` in the gate set keeps them fresh, and the demos carry their generated
regions the same way (`tools/sync-demo-embeds.py`,
`box2dxt/tools/sync-embedded-kit.py`). Three ways: (1) `git pull`; (2) the
`suite-selftest` artifact of any `suite gates` CI run (the paste, the coverage
report and this runbook; needs a GitHub login); (3) let OXT fetch it, from the
message box, then close and reopen the stack (3.1):

```
set the script of stack "SuiteSelfTest" to \
   URL "https://raw.githubusercontent.com/SethMorrowSoftware/xtalk-suite/main/tests/suite-selftest.livecodescript"
```

GitHub needs TLS 1.2+, so an old SSL build fails the fetch (a fetch problem, not
a harness problem). Pin a commit sha in place of `main` to reproduce a run.

**The standalone harnesses, for depth**, in order: `put sxSelfTest()` (no I/O;
everything composes sodiumxt, so a failure here invalidates the rest);
`enetxt/tests/enet-selftest.livecodescript` (loopback UDP, the fastest detector of
blocked loopback, 5.5); `datachannelxt/tests/datachannel-selftest.livecodescript`
(two WebRTC peers in one process); `torrentxt/tests/torrent-selftest.livecodescript`
(nothing else torrent-flavoured open, 5.1; 4.4); `put oxSelfTest()` (pure, offline,
tears down live state, 5.6); `coinxt/tests/coin-selftest.livecodescript` (4.6);
`box2dxt/examples/box2dxt-selftest.livecodescript` (card hooks: click RUN ALL
TESTS); holde-em's `heRunSelftest` (S1 item 2).

**The demos print their own record.** Fifteen stacks (the count
`tools/check-demo-selfcheck-drift.py` prints) run a boot self-check on open and
print a block into their own log, from `== boot self-check (nothing is hosted,
connected, or bound) ==` to the `n passed, m failed, k skipped` count line. **No
count line means the run is not finished** (the delayed-write probe lands 400 ms
in). An absent extension SKIPs, never FAILs; every observed value prints beside
its assertion; the status line paints red only on failure. Where it prints:
`onionxt-demo` in the About tab's `about:testlog`; the onion-httpd spike in
`demo:out`; `riptide-social` in the Feed card's `raIdOut`; `datachannel-loopback`
in the A-side log; every other adopter in its one log. Not adopters (record a
human judgement): `coinxt-demo`, `sodium-demo` and the five box2dxt games.

**The closing pass**, `tests/suite-closing-pass.livecodescript`: one stack for the
remaining multi-resource legs, each section printing PASS lines. A (dc local
async) closed 2026-08-15: skip it. B enet chat, C seed/leech plus resume across
an OXT restart, D rp1 chat over a DHT rendezvous and E dc chat signalled over the
real DHT need two machines (S3 item 1); F, Mode B plus the onion echo, needs one
machine and a tor binary (S2 item 2). It carries the ox* layer (install sodiumxt,
torrentxt, enetxt and datachannelxt on each machine) and takes THE torrent session
(5.1). Its header still counts "seven" live-Tor handlers; three remain.

---

## 4. What to record

### 4.1 How to copy a result back

- **Demos:** select the boot self-check block in the demo's log and copy it.
- **The suite paste, the preflight and the self-building selftests:** click
  **Copy results**: line 1 is `passed / failed / skipped / total`, a blank line,
  then every per-check line. On an older paste whose first copied line is not a
  count, click the selftest window so it is the default stack and run:

  ```
  set the clipboardData["text"] to (the text of field "stSummary" of this stack) & \
     return & (the text of field "stResults" of this stack)
  ```

- **Function harnesses** (`sxSelfTest()`, `oxSelfTest()`): copy the message box.

Copy the FULL text, not the count: the per-check lines let a failure be diagnosed
without a second session. With every result record the **OXT version, OS and
architecture, the date, and which extensions were loaded** (this cycle, also which
DLL/`.so` row). A result with no environment cannot become a claim.

#### 4.1.1 Wait for the `summary` section

The suite paste (and enetxt's and datachannelxt's own harnesses) ends with two
live loopbacks on a 33 ms timer chain with a 40-second deadline (`kStDeadlineMs`).
The report re-renders every tick, so mid-run it simply STOPS growing and reads
like a hang. Until `stReportDone` it ends with this trailer, which `Copy results`
carries and announces:

```
      RUN NOT FINISHED - this is NOT the end of the report.
      An async section is still running. Wait for the SUMMARY
      section at the bottom, then Copy.
```

**The run is over when the last section is `summary`.** On 2026-08-19 a fully
green Windows run was copied early and ended inside `CROSS: the 60000-byte budget
both transports share`. The async half is the last ~27 checks and the only part
that takes wall-clock time.

### 4.2 datachannelxt

A green standalone re-run needs no label work (the async loopback closed
2026-08-15): tick it; this cycle it is also the first standalone run on the
2026-09-12 binaries. Open: rows 6 (leg E, the DHT chat), 37
(`datachannel-loopback`) and 40. Leave `datachannelxt/CLAUDE.md`'s rule about not
claiming unobserved behaviour alone: it is policy, not a label.

### 4.3 enetxt

A green standalone re-run needs no label work (the async loopback closed
2026-08-13): tick it; this cycle it is also the first standalone async run since
the `sEnPolling` rename and on the 2026-09-12 binaries. Open: rows 6 (leg B, the
LAN chat demo) and 39.

### 4.4 torrentxt

A pass is `torrent-selftest` green at 101 checks, specifically the signed-puts
section: `btDhtBep44SignBuf` determinism, `btDhtPutSigned`, `btDhtGetPeers`,
`btAddInfohash`, `btMapPort` / `btUnmapPort` handling "no mapper", and
`btRp1Enable` / `btRp1SetToken` / `btRp1Send` / `btRp1Poll` handling "no peer".
It deliberately does NOT prove async DHT/tracker results, a real rp1 exchange, or
the positive paths of `btMoveStorage` and `btRemoveTorrent`-with-delete (row 45):
do not record those as passed. Copy the full `stResults`. On the 2026-09-12
binaries a green run is also the first engine run of libtorrent 2.1.1 on Windows,
and it flips the `load_torrent_buffer` status in `torrentxt/CLAUDE.md`.

### 4.5 sodiumxt

`put sxSelfTest()` or the suite paste's section: 106 checks at ABI 10, SHA3,
ristretto and ChaCha20 included. Record `put sxVersion()` (libsodium 1.0.22 on
Windows, 1.0.20 elsewhere). The Windows re-proof is row 23.

### 4.6 coinxt

- The address checks are the BIPs' own examples: `cxBtcAddressP2WPKH` of G must
  equal `bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4` (BIP-173) and
  `cxBtcAddressP2TR` of x-only G must equal
  `bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0` (BIP-350).
- The script logic executes headlessly on every push, so a failure here is more
  likely a PARSER difference than arithmetic: record the exact line.
- If anything fails, read the phase-4 sections first: the test mnemonic walks
  `m/44'/0'/0'/0/0`, `m/84'/0'/0'/0/0` and `m/44'/60'/0'/0/0`, and a mis-derived
  path still looks like a valid address.
- `handler not found` in phase 3+ while earlier sections pass: the paste is
  truncated; re-copy it.
- `cxBtcAddressP2TR` deliberately does NOT tweak; `cxBtcAddressP2TRFromInternal`
  is the BIP-341 path.
- `cxCheckABI` throwing "ABI mismatch" means the package and its library came from
  different commits: reinstall. ABI 7's new surface is row Q.
- Settled 2026-08-08, do not re-litigate: the five `.lcb` FFI questions were all
  answered on the side the code assumed; neither fallback (`CUInt`, `optional
  Pointer`) was needed.

### 4.7 onionxt (rows 4 and 5)

- **`oxSelfTest()`** needs no daemon; with sodiumxt absent its ABI-6 section
  SKIPs, a legitimate recorded outcome, not a pass.
- **Mode B (row 4):** `oxLaunchTor` writes its torrc, starts the process, and the
  control port becomes connectable. Record `the processId`, whether tor
  bootstrapped (read it through the control port: OnionXT has no stdout capture,
  so "Bootstrapped 100%" on stdout cannot be recorded through it), whether the
  child exits cleanly on shutdown, and which ports (5.3.1).
- **Quick Share over Tor (row 5):** a file's bytes cross an onion stream with
  **no torrent created and no DHT call**, both ends see the transfer complete,
  and folder-serving renders in Tor Browser. Tick the specific
  `docs/ONIONXT-INTEGRATION-PLAN.md` 12.3 items you exercised, never the register
  as a whole.

### 4.8 The suite summary

Once the member labels are updated, the last edit is the root `README.md` status
matrix, in the same follow-up pass, so the front door never claims more than the
members.

### 4.9 nostrxt (row 34)

The core's folded run is engine-proven (274/0/2, 2026-08-24). Copy the suite
paste's `NostrXT` line and any red lines into `nostrxt/CLAUDE.md`, with: the
NIP-44 seam verdict lines (against ABI 10+, "the official encrypt_decrypt vector
decrypts" and "and re-encrypts byte-identically"; against an older SodiumXT, the
fail-closed pair); the event C UTF-8 line (a FAIL is an engine-notes finding, not
a nostrxt bug to patch around); and which sections SKIPped and why (CoinXT absent
vs the relay layer absent). Those counts set the measured floor that replaces the
placeholder floor 1 at `stMergeReturned "NostrXT"` in
`tests/suite-selftest.core.livecodescript` (still open). The TLS result, WHATEVER
it is, goes to engine note 6.8.

---

## 5. Known traps

Each of these has already cost someone a debugging round.

### 5.1 Only ONE torrentxt session per OXT process

Close every other torrent-flavoured stack before `torrent-selftest` (its header
says so) and run one demo per OXT instance; for a two-party test use two machines,
not two windows. The suite paste holds THE session until its window closes, so
close it before `torrent-selftest`. It fails soft the other way: if the session is
taken, its torrent sections SKIP with a note.

#### 5.1.1 RESTART OXT BEFORE EVERY torrent-bearing PASTE

The one-session latch lives in the C shim, and its only key is the integer handle
`btStartSession` returned. TorrentXT exports nothing that enumerates or releases a
session (`live_session_count()` is a C++ test hook, not FFI), and the harness
keeps the handle in a script local, so **re-pasting or editing the stack script**
clears the local while the C-side session runs on, orphaned for the rest of that
engine launch. (A run that throws no longer strands it: every synchronous section,
folded harness and `stProbe` is contained, `stPump`'s poll blocks and render are
each wrapped in try/catch so the run converges to teardown, and `stRun` releases
the session before clearing the handle, so `send "openStack"` is safe.) The next
run reports `TorrentXT: ABSENT - TorrentXT is installed but a session is already
live in this process ...`, and **the only remedy is to quit and relaunch OXT.** Do
NOT hunt for a handle: they are `(generation << 16) | slot`, so the first is
`65536` and a search finds it at once - and if the owner is a real client stack,
`btStopSession` pauses it, flushes its resume data and joins its threads out from
under it. So:

1. **Quit and relaunch OXT before every paste** of the suite paste,
   `torrent-selftest` or any torrent-bearing stack: "I edited the script" means
   "I restart the engine". The other members tolerate a re-paste.
2. **Within one launch, re-run only with the Re-run button**, or by closing and
   reopening the window (both run `stCleanup`).
3. **If a run dies with an error dialog, click Re-run BEFORE you touch the
   script.**

TorrentXT's absence also silently drops `CROSS: one seed, one identity` and
`CROSS: SodiumXT signs a BEP44 item TorrentXT accepts`; it cost the 2026-08-09
pass 85 checks.

### 5.2 A stack must be CLOSED and REOPENED

Pasting is not running: `openStack` builds the UI and starts the run. If nothing
happens after a paste, you skipped 3.1 step 4. `send "openStack" to this stack` is
safe; recompiling the script is the one loss path (5.1.1).

### 5.3 Tor Browser exposes no control port

Use a system tor on `127.0.0.1:9051`, or Tor Browser on `9151` with the port
explicitly enabled. A refused control connection (`Error 10061` /
`WSAECONNREFUSED` / "connection refused") means nothing is listening there, not
an onionxt bug. Confirm the `Opening Control listener` line before blaming script.

### 5.3.1 Mode B collides with the daemon you already run

`oxLaunchTor` defaults to SocksPort 9050 / ControlPort 9051, the ports a system
tor holds, so with S2's daemon up a second tor binds nothing and starts and dies.
It reads like "Mode B is broken"; it is a port collision. Two ways through, the
first better: **pass explicit high ports**, `oxLaunchTor tPath, tDir, 9250, 9251`
(both daemons coexist, Mode A stays up for the other S2 items, `oxLaunchTor` sets
the socks/control ports for the rest of the API, and the port arguments are proven
to marshal); or **stop the system daemon**, run leg F alone, then restart it.
Record WHICH: "Mode B on 9250/9251 beside a running system tor" and "Mode B on
9050/9051 with the system daemon stopped" are different claims, and only the
first proves the ports are honoured.

### 5.4 An ephemeral ADD_ONION service dies with its control connection

A control-socket drop un-publishes the service while its descriptor lingers about
three hours, so a later visit fails at rendezvous with `Unable to find any hidden
service associated identity key` (an empty browser response). onionxt passes
`Flags=Detach` by default, and teardown still `DEL_ONION`s. If an onion "works and
then does not", check whether the control connection dropped; always test a
FRESHLY published address.

Bind errors: `accept connections on port` sets `the result`. `Error 10013`
(`WSAEACCES`: Hyper-V / WSL2 / Docker reserve TCP ranges, often including 8080;
list them with an admin `netsh int ipv4 show excludedportrange protocol=tcp`) or
`Error 10048` (`WSAEADDRINUSE`): pick another LOCAL port such as 8090 or 9099, and
leave the VIRTUAL port at 80.

### 5.5 UDP to loopback may be blocked on your machine

The enet and dc loopbacks run over UDP on 127.0.0.1; a machine or security agent
that blocks all UDP fails them (the dc harness fails with a note rather than
hanging). If both fail, suspect the machine, test UDP loopback independently, and
record an **environment** failure, distinct from a binding failure (seen
2026-08-27: the only 2 failures of 2445).

### 5.6 onionxt's selftest tears down live state, on purpose

`oxSelfTest()` really calls `oxDisconnectControl` / `oxShutdown`, closing any open
control connection, streams or services: run it in a fresh session. It also
RESETS `oxSetSocksPort` / `oxSetControlPort` / `oxSetControlPassword` to their
defaults, so set ports AFTER it. The dispatch setters are restored to owner `me`,
status `onStatus`, no peer callback - what `onionxt-demo` sets in `preOpenStack` -
so running it from the demo's About tab leaves the demo working.

### 5.7 Give the DHT a few seconds

A new torrentxt session bootstraps into the swarm; "no peers" in the first seconds
is expected. Both peers must be online at the same time.

### 5.8 Bootstrap events fire only while bootstrapping

A tor already at 100% sends no `STATUS_CLIENT BOOTSTRAP` events; onionxt seeds its
progress from `GETINFO status/bootstrap-phase` on connect. A bar at 0 against a
bootstrapped daemon is cosmetic, not a hang.

---

## 6. If it fails

The goal: **one failure diagnosable without a second session.** Capture, every
time:

1. **The full result text,** not the count; the neighbours carry the context.
2. **The exact handler** from the failing line, with its arguments if shown.
3. **The last error, immediately:** `put sxLastError()`, `put btLastError()`,
   `put enLastError()`, `put dcLastError()`. onionxt has no `oxLastError`: capture
   `the result` ("OnionXT: ...") at the failure point. coinxt's handlers THROW
   ("CoinXT: cxSha256: ..."): wrap the call in `try` / `catch` and record the
   error verbatim.

   **The shim last-error cannot see the POLL PUMP.** A throw in the DRAIN
   (`dcPoll` / `enPoll`) or the DISPATCH is script-side and makes a demo go
   quiet. The pumps keep their own note (`dispatch of <name> failed: ...`,
   `dcPoll failed on drain #N: ...`, `enPoll failed on host ...`).
   `enet-lan-chat`'s `ecDashOnce` and `datachannel-dht-chat`'s `wxDashOnce` print
   it (`* event pump problem:` / `Event dispatch problem:`) and then CLEAR it, so
   **copy the demo's log line FIRST**. The fallback is `put dcPollLastError()` /
   `put enPollLastError()` (stack-script handlers: query with the demo as top
   stack); it is the PRIMARY query for `datachannel-loopback`, which reads the
   note only from its connect watchdog. `dcPollClearError` / `enPollClearError`
   reset it. Engine note 6.6 has the 2026-08-18 record.
4. **The environment:** OXT version, OS/arch, the loaded extensions and versions,
   and for Tor the daemon and ports.

Then: rule out the machine (5.5) and a second session (5.1); re-run once with the
Re-run button (non-reproduction is itself a finding); and classify it as a bind
failure ("would not load", "handler not found") or a behaviour failure ("ran and
returned the wrong bytes"), which route to different fixes.

**ABI skew:** if handlers resolve but behave nonsensically, check that library and
binding are one ABI. The guards: `_checkABI()` (torrentxt, enetxt,
datachannelxt); `sPrepare()` (sodiumxt, on every `sx*` call: a skew throws
`SodiumXT ABI mismatch ... Reinstall the packaged extension.` and takes riptide
and onionxt's SHA3 / deterministic-onion / offline-address paths with it); the
public `cxCheckABI` (coinxt); `b2Version()` (box2dxt, which returns the number).

---

## 7. The tick sheet (open legs only)

Keys are the session items of the session plan; the row each one serves is in
brackets.

```
Environment: OXT ______  OS/arch ______  glibc ______  date ______
DLL/.so rows loaded (the 2026-09-12 set): ___________________________
(S2+) tor ControlPort 9051 + CookieAuthentication 1, log line seen ___

S1 [ ] 0 preflight ____/____/____ sxVersion ______ layers: ox ___ cx ___ nx ___
         LOADED / NOT INSTALLED / ABI SKEW: SodiumXT ___ TorrentXT ___
         enetxt ___ DataChannelXT ___ CoinXT ___  Box2Dxt found ___ vs ___
   [ ] 1 suite paste ____/____/____ (summary reached ___)  sodiumxt ___
         torrentxt ___ onionxt ___ coinxt ___ enetxt ___ dc ___ nostrxt ___
         riptide ___ box2dxt v31 [31] ___ holde-em v0.25.3/44 ___
   [ ] P 2^53 + 1 printed as ______  `or` with arithmetic: ERROR / printed ____
   [ ] Q cxPubkeyCombine x6 ___ tsp1 ___ Inspect FOUND: ___ sp line ___
   [ ] 3 riptide boot [35] ____/____/____ npub ___ "not sent" ___ RIPTAPP1 ___
         [37] quickshare ___ dht-channels ___
   [ ] 2 heRunSelftest RESULT ______ deal sections [14] ___
   [ ] 4 hotseat v0.25.3: hands ___ side pot ___ 6-seat exit [42] ___
   [ ] 5 [37] start-here ___ torrent-client ___ rp1-chat ___ onionxt-demo ___
         httpd spike ___ dc-loopback ___ coinxt-demo ___ sodium-demo ___
         nostrxt ndTests ___   [38] first open: demo ___ platformer ___
         slingshot ___ contraption ___ spike ___
   [ ] 6 standalone enet-selftest ___ datachannel-selftest ___
   [ ] S nocloud web link [22] ______ mtime probe ______ sections 7-8 [46] ____
S2 [ ] 1 onionxt-demo live ___ B.12 [44] ______ httpd spike ___
   [ ] 2 leg F [4]: ports ____/____ processId ______ bootstrapped ___ exits ___
   [ ] 3 quickshare Tor ON [5]: no torrent ___ no DHT call ___ Tor Browser ___
   [ ] 4 #31 [21] ______
   [ ] 5 riptide serving [19]: page ___ prekey ___ dm accepted/refused ___
   [ ] 6 holde-em bring-up [20]: pill ___ invite ___ == oxServiceAddress ___
   [ ] 7 nocloud Tor half [22] ______
   [ ] 8 onionxt negative paths [44] ______   [ ] 9 round trip [44] ______
S3 [ ] 1 closing pass [6] B ____ C (restart ___) ____ D ____ E (pair ____) ____
   [ ] 2 riptide call [16]: CONNECTED ___ via ______ typing ___
   [ ] 3 riptide mesh [17]: welcome ___ draft converges ___ stranger ___
   [ ] 4 holde-em 2d [18]: machines ___ seats ___ receipts ___ overlay ___
   [ ] 5 holde-em 2e [28] ______
   [ ] 6 [6] enet-lan-chat ___ dc-dht-chat ___ dht-channels / rp1-chat ___
   [ ] 7 [41] faststart below 100% ___ phase-6 steps 7-8 ___
S4 [ ] 1 #32 [21] ______ byte-compare ___   [ ] 2 #33 [21] ______ capture ___
   [ ] 3 Model C gate [5]: sha256 ___ capture ___ passphrase ___ downgrade ___
   [ ] 4 riptide finishing [19]: accepted ___ proven sender ___ zero bt* ___
   [ ] 5 holde-em 2f exit [20] ______
S5 [ ] [23] sodiumxt MSVC DLLs: x86_64-win32 ___ x86-win32 ___ libsodium ____
   [ ] [47] x86-win32: torrentxt ___ coinxt ___ x86-linux: sodiumxt ___ torrentxt ___
   [ ] [24] Mac arm64 ___ Intel ___: preflight ___ paste ______ b2Version ___
            first-load / Gatekeeper behaviour ______
   [ ] [38] R1 spike verdicts: Linux ______ Mac ______
NET[ ] [34] nostrxt: EVENT verify ___ EOSE ___ NOTICE ___ CLOSED ___ NIP-42 ___
            bad certificate REFUSED / FAILS OPEN ___  ws:// local relay ___
   [ ] [41] riptide phase 8 live ______
   [ ] [43] coinxt: P2WPKH ___ EIP-1559 ___ EIP-155 ___ wallet ____ Core ____
   [ ] [45] torrentxt: ISO magnet ___ move ___ remove+delete ___ install ___
   [ ] [39] enet-internet-chat ____  [ ] [40] dc two-network ____ browser ____
   [ ] [42] holde-em oracle round (3M + tor) ______
AFTER  [ ] result text saved, each with its environment
       [ ] one label pass: member ledgers and labels first, root README last
```

---

## After the pass

Every result becomes a documentation edit, in ONE follow-up pass: members first
(a row in the member's `CLAUDE.md` evidence ledger, then the labels its row here
names), the root `README.md` LAST, so the front door never claims more than the
members. Anything not observed stays "verified statically; needs an OXT pass"
("+ live-Tor pass" for Tor). A leg that closes leaves this runbook: one line in
section 8, and out of 1.2, the session tables and the tick sheet. A partial pass
honestly recorded is worth more than a full pass generously described. Before
adding a question here, grep the carried lesson books: an engine session is the
most expensive way to learn something already written down (the `itemDelimiter`
question was withdrawn because `coinxt/templates/CLAUDE.md` rule 5 answered it).

---

## 8. Engine record (closed)

One line per dated record, so a closed row stays findable here while the member
ledgers change. Full records: each member's `CLAUDE.md`, and
`docs/OXT-ENGINE-NOTES.md` for engine behaviour. "Not recorded" means the pasted
results carried no platform.

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| before 2026-08-08 (undated here) | OXT + a live tor | onionxt bring-up | the live-Tor core confirmed: SOCKS dial, SAFECOOKIE, ADD_ONION with Detach, inbound accept, streams both ways, events; the `oxh*` hosting layer rendered in Tor Browser (`onionxt/CLAUDE.md`) |
| 2026-08-07 | not recorded | `enet-selftest` standalone | green, all tests pass |
| 2026-08-08 | not recorded | first suite paste, all six members | green, zero failures, no skips. Closed row 1 (datachannelxt's first engine evidence: a live loopback negotiated, byte-exact round trip, the -4 refusal at 60001 bytes, a cap-sized payload, `dcCleanup`) and row 2 (coinxt phase 1: binds resolve, ABI guard, `UIntSize` as a return type, an empty `Data` through `MCDataGetBytePtr`, vectors byte-exact) |
| 2026-08-09 | not recorded | suite paste | the `dcCleanup()` statement call failed the whole compile (engine note 3.3); a lost torrent session cost 85 checks and both CROSS BEP44 sections (trap 5.1.1) |
| 2026-08-10 | not recorded | folded deep harnesses | 454 member checks, 1 red: coinxt 205/206, `cxHdDerivePath` "m/" fail-open (engine note 2.2), fixed the same day; the first paste hit trap 5.1.1 |
| 2026-08-10 | not recorded | re-run, script layers embedded | 455 member checks + the core, ZERO failures: sodiumxt 68, onionxt 40, coinxt 207/207, torrentxt 96, enetxt sync 21, dc sync 23, both loopbacks, clean teardown. Closed row 3 and coinxt phases 2-4; a C `int` flag (33 vs 65) and `Boolean` returns marshal; all 31 `dc*` handlers called |
| 2026-08-12 | Windows x64, SodiumXT ABI 7 (mingw DLL) | suite paste | 617 folded, 0 failed; sodiumxt 71. Closed rows 7 (riptide phase 1, 89/89), 8 (coinxt phase 5, 230/230), 9 (onion offline address, 43/43, `offlineAddress` true) and 10 (riptide phase 2 live feed, 133/133) |
| 2026-08-13 | not recorded | regenerated suite paste | 617 folded, 0 failed |
| 2026-08-13 | not recorded | `enet-selftest` standalone | green end to end, including the `enHostStatus` pair and the `enPeerStatus` statistics |
| 2026-08-13 | two machines (maintainer's account) | `riptide-social` | feeds published and received both directions over the live DHT, every post ingest-verified: phase 2's done-criterion, row 6's riptide propagation leg |
| 2026-08-15 | not recorded | `datachannel-selftest` standalone | green end to end with the async loopback (real SDP with candidates, roles, gathering, a selected pair, text and binary with NUL, a cap-sized send): closing-pass leg A |
| 2026-08-15 | two machines | `riptide-social` | media fetched and played, DMs both ways (phases 3-4) |
| 2026-08-15 | not recorded | suite paste, riptide section | three `rsBytesAreUtf8` refusal checks RED; fixed, green 2026-08-20 |
| 2026-08-16 | not recorded | suite paste x3, holde-em folded | the third run green, holde-em 507/0 (v0.24.3, harness v40); runs 1-2 found two liveness defects (`holde-em/CLAUDE.md`) |
| 2026-08-17 | Windows x86_64, NT 10.0, OXT 9.6.3 | preflight (its first run), suite paste | preflight six LOADED. 1,836 folded, 0 failed, 7 skips: holde-em 538, box2dxt 374 (v29), riptide 338, coinxt 278, torrentxt 101, sodiumxt 99, onionxt 61, dc 26, enet 21; ABIs sodium 9, torrent 11, enet 2, dc 1, coin 6, box2d 4 (read). Closed rows 11 (ristretto255, run at ABI 9), 12 (coinxt WIF), 15 (holde-em Level 2), 25 (sodiumxt ABI 9 batch algebra), 26 (4e named; 4d inferred from the member total), 27 (Phase 5 DLEQ), 30 (coinxt ABI 6 Schnorr/Taproot) and 32 (holde-em's fold compiles). Confirmed the onionxt loopback-guard fix and its eight socket-id fixtures, torrentxt's stale-id refusal legs and `btAddMagnet`, `dcSendText` NUL -3, box2dxt's duck collision filter, holde-em's sit-out election and the `heHandStart` ante check |
| 2026-08-17 | same pass | holde-em hotseat, 3 hands | the `heAwardedPot` display defect found (`pot 2400` shown for an awarded 784); fixed in v0.24.5 |
| 2026-08-18 | Linux | suite paste | box2dxt 373/1 at v29 (`playLoudness` readback, engine note 5.4); suite totals not captured |
| 2026-08-18 | Linux (both); Windows (dht-chat) | `enet-lan-chat`, `datachannel-dht-chat`, one machine each | UI built, no second peer; faults found and fixed (engine notes 1.7, 6.6, 6.7); re-runs reported working (maintainer's account) |
| 2026-08-19 | Windows | suite paste | fully green but copied early (it ended inside the CROSS budget section): the origin of 4.1.1's trailer |
| 2026-08-20 | Windows | suite paste | 1,981/0/1 (1,982), both loopbacks and teardown included; folded 1,868: sodiumxt 99, onionxt 61, coinxt 278, torrentxt 101, enetxt 34, dc 39, box2dxt 375 (v30), riptide 338/0/2, holde-em 543/0/5. Closed row 13 (riptide's phase-6 sync records, the phase-7 serving seams and the three UTF-8 refusals). `playLoudness` read back exact (24 -> 24, 73 -> 73) |
| 2026-08-21 | Linux | suite paste, box2dxt | v30 374/1: `playLoudness` reads back a constant 0 (engine note 5.4), hence harness v31 |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | preflight, suite paste | six LOADED; 2,373/0/3 (2,376). nostrxt 274/0/2, its first contact (closed row 33); coinxt's BIP-341 section, 12 checks (290/290); sodiumxt's ABI-10 ChaCha20 7/7, 106/106 (on the x64 mingw DLL, since replaced); holde-em v42 584/0; riptide 391/0 |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | `nostrxt-demo` | boot 9/9; connect, handshake, publish and ok-true on wss://nos.lol, the suite's first `open secure socket` (engine note 6.8): row 34's send half |
| 2026-08-27 | two machines, one LAN | suite paste, two-machine demos | 2440/2/3 (2445); holde-em 667/0 at v0.25.2 / harness 43, the first run carrying onionxt; the 2 failures were both loopbacks stalled on blocked UDP to 127.0.0.1 (environment, 5.5). rp1 chat and the DHT-signalled WebRTC chat work across the two machines; `enet-internet-chat` cannot connect on one network (hairpin); holde-em 2d joins worked but the hand dealt under the lobby overlay (fixed in v0.25.3, statically) |
| 2026-08-27 | not recorded (two machines) | `riptide-social` media playback | playback visibly mid-download measured NEGATIVE as then wired (Play unlocked on file existence, a hollow allocated file); fixed the same day (`raMediaFrontReady`); the re-run is row 41 |
| 2026-08-27 | CI, release run 12 | universal-mac builds | row 24's builds closed: the first universal dylibs for torrentxt, enetxt, datachannelxt and coinxt, and sodiumxt's refreshed to ABI 10; no engine loaded them |
| 2026-08-29 | not recorded | `riptide-social` phase-8 first landing | `openStack` broke with `Chunk: no target found`; reverted the same day |
| 2026-08-29 | not recorded | `riptide-social` re-land, then the v11 boot | the re-land reported working (maintainer's account); the v11 boot read 9 passed / 1 failed / 0 skipped, every capability true, all five cards built; the FAIL was the self-check reporting all 63 off-card controls missing (engine note 5.6), fixed in the carried block |
| 2026-09-01 to 09-03 | not recorded, testnet | `coin-wallet` | engine logs in `coinxt/CLAUDE.md`; a testnet spend, txid `7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, accepted by the Esplora onion mirror over Tor (2026-09-02); Electrum over Tor (2026-09-03) |
| 2026-09-15 to 09-20 | the maintainer's engine | archivext (row 36) | first contact: harness 357/2/0, then 363/0/0; demo boot 11/11; live legs and a gallery run. The member left for its own repository 2026-09-21; its records are engine notes 2.7, 3.4, 5.7-5.10 and 6.9 |

**Closed row numbers** (never reused; member docs and dated records cite some
of them): 1, 2, 3 (2026-08-08/10); 7, 8, 9, 10 (2026-08-12); 11, 12, 15, 25, 26,
27, 30, 32 (2026-08-17); 13 (2026-08-20); 33 (2026-08-24); 24's builds
(2026-08-27; its engine half stays open). Row 29 was a note (CI's committed-binary
execution lanes), not a leg; row 36 (archivext) left with its member on
2026-09-21.
