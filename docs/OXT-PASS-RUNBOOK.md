# The OXT engine pass runbook

**Scope: the whole suite. Audience: the person sitting at a real OpenXTalk engine.**

Everything in this repository that reads *"verified statically; needs an OXT pass"*
is waiting on this session, and only on this session. OXT is a GUI runtime with no
headless way to compile or run `.lcb` / `.livecodescript`, so CI can prove the native
shims and the pure-compute vectors but can never prove that a binding **loads**, that
a foreign declaration **marshals**, or that a handler **returns what the docs say**.
That is the gap this session closes.

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
| 1 | ~~**datachannelxt has never had an engine pass at all.**~~ **CLOSED 2026-08-08.** | The member now has engine evidence: `dcInit`, a stale-handle no-op, peer and channel creation, a live loopback that negotiated and opened both ends, a byte-for-byte payload round-trip, the `-4` refusal at 60001 bytes, a payload at the SCTP-negotiated cap, and `dcCleanup`. **Residual closed at the synchronous level 2026-08-10:** the folded suite harness calls all 31 public `dc*` handlers by name and its datachannelxt sections ran green twice; only the member harness's own ASYNC loopback halves (live `dcSendText`, `dcBufferedAmount`, `dcGatheringState`, `dcSelectedCandidatePair`, the a=candidate pins) remain standalone work. | Labels updated in `datachannelxt/README.md`, `datachannelxt/examples/README.md`, `datachannelxt/docs/getting-started.md`, `datachannelxt/tests/datachannel-selftest.livecodescript`, and `datachannelxt/src/datachannel.lcb`. |
| 2 | ~~**coinxt's binding is brand new and has never been loaded.**~~ **CLOSED 2026-08-08 — and it closed coinxt phase 1.** | All five numbered questions in the `.lcb` header were answered, each on the side the code assumed: the module loads and binds resolve; the ABI guard holds (transitively — `sPrepare()` is the whole body of `cxCheckABI()` and every wrapper calls it); **`UIntSize` works as a foreign RETURN type**; **`MCDataGetBytePtr` marshals an empty `Data`** (`cxKeccak256("")` returned `c5d2…a470` instead of throwing); and the vectors are byte-exact. Neither fallback — `CUInt`, `optional Pointer` — was needed. **Residual CLOSED 2026-08-10:** the folded coin-selftest ran every public handler by name on a real engine — the 12 phase-1 stragglers (`cxCheckABI` by name at last), all 15 phase-2 curve handlers, and the whole of phases 3 and 4 — at 207/207 on the re-run. Nothing in coinxt is "verified statically" any more. | Labels updated in `coinxt/src/coinxt.lcb` (STATUS block), `coinxt/CLAUDE.md`, `coinxt/IMPLEMENTATION-PLAN.md`, and the root `README.md` row. |
| 3 | ~~**The selftests grew after their passes; the new sections are static-only.**~~ **CLOSED 2026-08-10.** | The folded suite harness ran every member's own deep self-test on a real engine, twice in one day, green: torrentxt's whole harness including the v9-v11 surface (`btDhtGetPeers`, `btAddInfohash`, `btMapPort`/`btUnmapPort`, the `btRp1*` quartet) at 96/96; enetxt's isolated teardown section (`enDisconnectNow` / `enResetPeer` / `enSetPeerTimeout` / `enSetHostBandwidth`) inside its 21/21 sync half; and the complete `sxSelfTest()` at 68/68, attached-signature form, keyed hashing and preset accessors included. The one extended section the folds exclude is the live `enHostStatus` pair inside enetxt's own async loopback. | Labels updated 2026-08-10 in `torrentxt/tests/torrent-selftest.livecodescript` + `torrentxt/README.md`, `enetxt/tests/enet-selftest.livecodescript` + `enetxt/CLAUDE.md`, and `sodiumxt/docs/api-reference.md`. |
| 4 | **onionxt Mode B (launching tor as a child process) has never run.** | It is the one remaining `VERIFY:` in an otherwise on-engine-proven member, and it is what a turnkey app would ship. | `onionxt/CLAUDE.md`, "Still `VERIFY:` (not yet exercised)" item 8: "`the processId` / `open process` for the optional Mode B tor launch (the default is assume-running)." Also the intro blockquote in `onionxt/docs/10-usage-guide.md` and `onionxt/docs/07-tor-lifecycle.md` Mode B. |
| 5 | **torrentxt's Tor path (Quick Share Model C) has never run against a daemon.** | It is a cross-member composition, so it is the one place three members must agree at runtime. | `torrentxt/examples/torrent-quickshare.livecodescript` (two places): "Every ox* handler is OnionXT's published ABI; this is verified statically ... and NEEDS an on-engine OXT pass with a running Tor daemon before any runtime claim." Register: `docs/ONIONXT-INTEGRATION-PLAN.md` section 12.3. |
| 6 | **Two-machine behaviour, for every member that has it.** enetxt's LAN chat, torrentxt's rp1 chat and Channels, datachannelxt's DHT chat. | Loopback proves the binding; only a second machine proves the transport. | `enetxt/CLAUDE.md`: "Still un-exercised: the LAN chat demo between two real machines." `torrentxt/examples/README.md`: rp1 chat "needs a live peer to show anything, so it is a two-machine test by nature." |

Items 1, 2 and 3 are **all closed**: every member's deep self-test had run on a
real engine via the folded suite harness (as of the 2026-08-10 passes), and the
residuals that remain (the enet and datachannel member harnesses' own async
loopback halves) are small, named in each harness's coverage note, and closable by
one standalone paste each.

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
| 10 | **riptide phase 2, the live feed layer** (inside `rs1rsSelfTest`, no extra step: the folded live-feed section drives the suite's own session) | the pure-script BEP44 buffer matches `btDhtBep44SignBuf` byte-for-byte; `rsPublishImmutable`/`rsPublishPost` return the oracle's pinned targets (libtorrent's SHA-1 agrees); `btDhtPutSigned` ACCEPTS `rsPublishHead`'s SodiumXT signature over the script-assembled buffer; the lookups are accepted; and the ingest verifiers pass/refuse their synthetic golden events. NOT covered by one machine: propagation - phase 2's done-criterion (a second machine walks the chain) is item 6's session | **CLOSED 2026-08-12**: riptide 133/133, 0 skipped; canonical buffer, real-session puts/requests, and ingest verifiers all green |

What remains is entirely environmental: items **4 and 5 need a live tor daemon**
(one evening with `ControlPort 9051` covers both), and item **6 needs a second
machine** (including riptide phase 2's propagation half). Plan those as their
own sessions.

---

## 2. Install order and prerequisites

### 2.1 Check your platform FIRST

Committed binaries are uneven, and this decides what is even runnable tonight.
`ls <member>/src/code/` is the ground truth:

| Member | Committed platforms | If your platform is missing |
|---|---|---|
| sodiumxt | all five (`x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`, `universal-mac`) + `MANIFEST.sha256` | n/a |
| torrentxt | four (Linux x64/x86, Windows x64/x86); `universal-mac/` holds only a `README.md` (**no macOS dylib**) | build it: `torrentxt/docs/building.md`, then `torrentxt/tools/package-extension.py` |
| enetxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | build locally, then `enetxt/tools/package-extension.py` |
| datachannelxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | build locally, then `datachannelxt/tools/package-extension.py` |
| onionxt | n/a, pure LiveCodeScript | n/a |
| coinxt | four (Linux x64/x86, Windows x64/x86) + `MANIFEST.sha256`; **no macOS** | build it: `cd coinxt && sh native/build.sh pack` puts it straight into `src/code/`; see 2.4 |

**On Linux (x64 or x86) and on Windows (x64 or x86), every member's library is
already in the repo** — the 2026-08-08 release run committed all four platforms for
all five native members, which is what made that day's suite pass possible on a
stock checkout.

**macOS is the one gap left.** Only sodiumxt ships a real `universal-mac` dylib; the
other four need a manual `lipo` build (and, for torrentxt, codesigning and
notarization). CI deliberately builds no macOS lane — `macos-15` runners are
arm64-only, so an automated lane would emit a thin dylib and silently regress
sodiumxt's genuine two-architecture binary into one that fails on every Intel Mac.
So on a Mac, expect to build before you can run any member but sodiumxt.

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
```

Install in this order:

1. **sodiumxt** (`org.openxtalk.library.sodium`). Everything that composes anything
   composes this one.
2. **torrentxt** (`org.openxtalk.library.torrent`).
3. **enetxt** (`org.openxtalk.library.enet`).
4. **datachannelxt** (`org.openxtalk.library.datachannel`).
5. **onionxt** (`org.openxtalk.library.onion`). Not a packaged extension: copy
   `onionxt/src/onionxt.livecodescript` and `onionxt/src/onion-httpd.livecodescript`
   into your app and `start using` them, or paste one of the two **already-built**
   standalones - `onionxt/examples/onion-httpd/standalone.livecodescript` and
   `onionxt/examples/onionxt-demo-standalone.livecodescript`. Both are committed and
   gated current, so there is nothing to run here:
   `onionxt/tools/build-standalone.py` is for whoever EDITS a part, not for the
   tester (see `onionxt/docs/10-usage-guide.md`). (If all you are running is the
   SUITE harness, skip this step: it embeds the whole ox* surface itself.)
6. **coinxt**: see 2.4.

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

> **All four are current as of the phase-4 change (ABI 4)**, and
> `coinxt/tools/check-binary-freshness.py` says so on every push. One note on how
> the `x86-linux` one was produced: the environment that built the other three has
> no 32-bit libc, so it was cross-compiled with **Zig** (`zig cc -target
> x86-linux-gnu.2.25`) rather than `gcc -m32`. The artifact is a 32-bit i386 ELF
> with exactly the 30 `cnx_*` exports, needing only `libc.so.6` at the documented
> GLIBC 2.25 floor, and CI **executes** it against the published vectors on every
> push (see the "Execute the COMMITTED library's vectors" step in
> `native-coinxt.yml`), which is a stronger check than any other committed library
> had before. If you would rather ship a gcc-built one, running
> `release-binaries.yml` replaces it and the same CI step will re-verify it.

**macOS is the only gap**, and it is the same gap four of the five native members
have: CI builds no macOS lane on purpose (the runners are arm64-only, so an
automated lane would emit a thin dylib). Build it first - one command, and it puts
the file where the engine expects it:

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

As of 2026-08-12 (release run 31551536144) the committed binaries are at **ABI 7
everywhere except `universal-mac`**, which stays at **ABI 6** until the manual
`lipo` build (the currency table with the reasons lives in `sodiumxt/CLAUDE.md`).
On an ABI-7 row: repackage normally and the SHA3 / offline onion-address checks
run - the 2026-08-12 Windows x64 pass did exactly this, green. On the mac row:
**do not repackage SodiumXT** - keep the older package, where `sxSha3_256` simply
does not exist and every composing member degrades the way it was written to,
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

**How complete is it, exactly.** Not a judgement call any more - `tools/check-suite-coverage.py`
measures it, and the gate set runs it on every push, so the number below is current
rather than remembered:

| member | public handlers the harness calls | not reachable offline |
|---|---|---|
| sodiumxt | 61 / 61 | - |
| onionxt | 27 / 45 | 18 |
| coinxt | 78 / 78 | - |
| torrentxt | 85 / 85 | - |
| enetxt | 23 / 23 | - |
| datachannelxt | 31 / 31 | - |
| riptide | 35 / 35 | - |
| **total** | **340 / 358** | **18** |

The eighteen are onionxt's, all of them, and they are the only handlers in the suite
with a written excuse: eleven are **engine socket callbacks** (the engine calls them
with a socket id no harness can mint) and seven need a **live tor daemon**. Both lists
are in `tools/check-suite-coverage.py` with a per-handler reason, and the gate fails if
a new handler lands without either a check or an entry there. So "what does this not
touch" has an answer you can read, instead of being the thing nobody re-asks after
seeing a big line count.

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
whoever edits a member harness; the tester's input is a finished ~430 KB
`.livecodescript`. The same is true of the two onionxt standalones. So the answer to
"can the generation be automated, or is it a separate step?" is: **it is already
automated, and it already happens somewhere else.** All three generated files are
committed, and `--check` in the gate set is what guarantees the committed copy is the
one the sources produce.

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
| 0 | **`tests/suite-selftest.livecodescript`** — **START HERE.** | all five packaged extensions installed; the coinxt, onionxt, and Riptide script layers are embedded in the paste (any absent member SKIPs) | **The whole suite in one paste.** It carries all seven member harnesses: sodiumxt's `sxSelfTest`, onionxt's `oxSelfTest`, coinxt's 28 sections, torrentxt's full harness, the synchronous halves of enetxt and datachannelxt, and Riptide phases 1-2 against the suite's session. If this is green, rows 1, 4, 5, and 6 are redundant unless chasing a failure. The two deliberate exceptions are the ENet and DataChannel **async loopbacks** in rows 2 and 3. |
| 1 | `sodiumxt/examples/sodium-tests.livecodescript` (`put sxSelfTest()`) | sodiumxt only | No I/O at all, no network, runs in a second. Everything else composes sodiumxt, so a failure here invalidates results further down. |
| 2 | `enetxt/tests/enet-selftest.livecodescript` | enetxt only | Loopback UDP on 127.0.0.1, no daemon, no second machine. Also the fastest way to discover a machine that blocks loopback UDP, which would also sink datachannelxt (see trap 5.5). |
| 3 | `datachannelxt/tests/datachannel-selftest.livecodescript` | datachannelxt only | Two real WebRTC peers in one process: offer, answer, ICE, DTLS, SCTP, text and binary round-trips, teardown. Its synchronous half ran green folded into the suite harness 2026-08-10 (every public `dc*` handler called by name); what only THIS stack still adds is its own async loopback's live halves - `dcSendText` on an open channel, `dcBufferedAmount`, `dcGatheringState`, `dcSelectedCandidatePair`, the `dcBufferedLow` event after a cap-sized send, and the a=candidate / offer-answer-role pins. |
| 4 | `torrentxt/tests/torrent-selftest.livecodescript` | torrentxt only, **and nothing else torrent-flavoured open** | 96 checks in the current harness. Read trap 5.1 first: one session per OXT process. |
| 5 | `onionxt/examples/onionxt-tests.livecodescript` (`put oxSelfTest()`) | onionxt + sodiumxt; **no daemon needed** | Deliberately pure and offline: address/base32 vectors, fail-closed contracts, idempotent teardown, and the two sodiumxt ABI-6 primitives. Read trap 5.6: it really does tear down live state. |
| 6 | `coinxt/tests/coin-selftest.livecodescript` | coinxt packaged, **plus its script layer in the message path** (`start using stack "coinxt"`) - see 4.6 | Drives the whole public `cx*` surface (78 handlers): the `.lcb` handlers (hashes, curve, the two BIP-32 tweaks, the BIP-39 wordlist) and the `src/coinxt.livecodescript` ones (encodings, addresses, BIP-39/32/44, and the phase-5 transaction KATs - BIP-143 / EIP-155 / EIP-1559). Phases 1-4 ran green folded 2026-08-10 (207/207 on the re-run); **phase 5 (`stRunTransactions`) closed 2026-08-12 at 230/230** - after the headless-execution net (`check-script-vectors.py`, 251 checks) caught and fixed a trailing-empty-scriptSig defect that would have failed `cxBtcTxEncode` on that very run. Fully synchronous. See 4.6. |

**Step 2 - the demos (depth on real transports).**

| Order | Demo | Needs |
|---|---|---|
| 7 | `datachannelxt/examples/datachannel-loopback.livecodescript` | datachannelxt + `datachannel-helpers.livecodescript` |
| 8 | `enetxt/examples/enet-lan-chat.livecodescript` | enetxt + `enet-helpers.livecodescript`; **two machines** for the real test |
| 9 | `torrentxt/examples/torrent-quickshare.livecodescript` | torrentxt (+ sodiumxt for the passphrase lock) |
| 10 | `torrentxt/examples/torrent-client.livecodescript` | torrentxt |
| 11 | onionxt against a live daemon: `onionxt/examples/onionxt-demo.livecodescript`, or the paste-and-run standalone `onionxt/examples/onionxt-demo-standalone.livecodescript` | onionxt + sodiumxt + tor with the control port |
| 12 | `torrentxt/examples/torrent-quickshare.livecodescript` **with the Tor toggle on** | torrentxt + onionxt + sodiumxt + tor daemon. Inventory item 5. |
| 13 | `datachannelxt/examples/datachannel-dht-chat.livecodescript` | datachannelxt **and** torrentxt; **two machines** |
| 14 | `torrentxt/examples/torrent-dht-channels.livecodescript` and `torrent-rp1-chat.livecodescript` | torrentxt; **two machines** |
| 15 | onionxt **Mode B**: `oxLaunchTor` against a real tor binary. Inventory item 4. | a tor binary on disk |
| 16 | `coinxt/examples/coinxt-demo.livecodescript` - the phase-6 demo: mnemonic to accounts, addresses, sign/verify, and a decoded, signed BTC + ETH transaction | coinxt, with `start using stack "coinxt"` first; sodiumxt optional (only the Generate button needs it) |
| 17 | `riptide/examples/riptide-social.livecodescript` - the phase-1/2 flagship: identity, publish over the real DHT, and the verified chain walk. Single machine = the honest half; **two machines** = phase 2's done-criterion (item 6; procedure in `riptide/examples/README.md`) | sodiumxt + torrentxt + `start using stack "riptide"`; takes THE torrent session (trap 5.1) |

Items 8, 13, and 14 are genuine two-machine tests. If you only have one machine
tonight, run them anyway to the point where the UI builds and the session starts, and
record exactly that: "UI built, session started, no second peer available."
That is still a real result and it is honest.

---

## 4. What to record

### 4.1 How to copy a result back

The three self-building selftests (torrentxt, enetxt, datachannelxt) share one UI:
a bold `stSummary` field carrying the passed / failed / total counts (green when
clean, red when not), a scrolling `stResults` field of per-check lines, and an
`stRerun` button. `tests/suite-selftest.livecodescript` (step 0) shares that UI and adds
a **`Copy results`** button: click it and the per-check lines are already on the
clipboard. It copies `stResults` only, so read the `stSummary` counts across yourself.

Click the selftest window so it is the default stack, then from the message box:

```
set the clipboardData["text"] to (the text of field "stSummary" of this stack) & \
   return & (the text of field "stResults" of this stack)
```

Paste that whole block into your notes. **Copy the full result text, not just the
summary count** - the per-check lines are what let a failure be diagnosed without a
second session.

For the two function-style harnesses (`sxSelfTest()`, `oxSelfTest()`), the message box
already holds the full report; copy it directly.

Alongside each result, record: **OXT version, OS and architecture, the date, and
which extensions were loaded.** A result with no environment attached cannot be
turned into a claim.

### 4.2 datachannelxt (inventory item 1 - CLOSED; this is now the async residual)

The first-engine-evidence flips this section used to enumerate were applied
after the 2026-08-08 and 2026-08-10 passes (the README honesty notes, the
COVERAGE NOTE, the root release row - all carry dated results now). What a
STANDALONE run of `tests/datachannel-selftest.livecodescript` settles today is
the async loopback's live halves, the one part the folded suite deliberately
excludes.

**A pass looks like:** `stSummary` green, zero failures - and specifically the
live halves: `dcSendText` on an open channel, `dcBufferedAmount` on a live
channel, `dcGatheringState` reporting complete (2) on both peers, a populated
`dcSelectedCandidatePair`, the `dcBufferedLow` EVENT after the cap-sized send
(the channel is armed at 4096; the payload is far above it), the a=candidate /
offer-answer-role pins, and clean teardown. The synchronous surface also runs
(it is the same file), but those checks are re-confirmation, not news.

**Copy back:** the full `stResults` text.

**What flips:**

- `datachannelxt/tests/datachannel-selftest.livecodescript`, the COVERAGE NOTE
  sentence beginning "Still verified statically: this file's own async
  loopback" - replace with the dated result.
- `datachannelxt/README.md`, the "What remains **verified statically**"
  sentence naming the same live halves.
- This runbook's tick-sheet row for datachannelxt, and the root `README.md`
  release row's "only the member harness's own async live halves stay static"
  clause.

Leave `datachannelxt/CLAUDE.md`'s *rule* about not claiming unobserved behaviour
alone - that is policy, not a status label.

### 4.3 enetxt (inventory item 3)

**A pass looks like:** green summary, and specifically the loopback's **live
status assertions** - `enHostStatus` asserted stale (empty), live (peerCount,
address), and again AFTER the disconnect (zero peers), plus the `enPeerStatus`
statistics half (rtt >= 0, packetLoss within 0..1, the packet/byte counters
populated). Those are the only parts of this member the folded suite runs have
not already turned into runtime results.

**Copy back:** the full `stResults` text, so the new sections are visibly green.

**What flips:**

- `enetxt/tests/enet-selftest.livecodescript`, the COVERAGE NOTE sentence naming
  "the loopback's LIVE status assertions" as the one part still verified
  statically.
- `enetxt/CLAUDE.md`, the Phase-1 blockquote's "Still un-exercised" sentence,
  and the matching sentence at the end of `enetxt/README.md`'s Development
  section.

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

**The `start using` lines are still required for a member's STANDALONE
harness.** `coinxt/tests/coin-selftest.livecodescript` and onionxt's own
examples are pasted without the suite's embeds, so running one of those alone
still needs its layer in the message path:

```
start using stack "coinxt"     -- before coin-selftest standalone
start using stack "onionxt"    -- before onionxt's standalone examples
```

### 4.6 coinxt (inventory item 2 — CLOSED 2026-08-08; this is now the residual)

**PHASE 3+ IS A SECOND, SEPARATE LOAD — when running coinxt's harness STANDALONE.**
The hash and curve handlers come from the `.lcb` extension. The encoders and address
builders come from `coinxt/src/coinxt.livecodescript`, which is a SCRIPT. The SUITE
harness carries that script embedded (see "Setup the suite harness NO LONGER needs"
above), but a standalone paste of `coin-selftest` does not, so there it must be in
the message path first:

```
start using stack "coinxt"     -- or insert its script into the back
```

If every phase-3+ section fails with `handler not found` while the earlier ones pass,
that is the symptom of the script not being loaded - a setup problem, not a defect.
Fix it and re-run before reporting anything.

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
> `Re-run` button. It drives **all 78** public `cx*` handlers (this "31" and the
> phase-2 framing below predate phases 3-5) — `cxCheckABI` by
> name at last, all thirteen `*Len` accessors, every digest, both HMACs, PBKDF2,
> and the whole curve surface, then the script layer's encoders, addresses,
> BIP-39 mnemonics and BIP-32 derivation — against the same published vectors
> `tools/coin-kat.py` and `tools/check-script-vectors.py` pin.

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
guard (**ABI 4** now), the thirteen length accessors, Keccak-256, SHA3-256
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
written, and `coin-selftest` now drives all **78** handlers, not just the curve.
Expect green sections for hex/Base58Check/Bech32/RLP/addresses, BIP-39/32/44,
and the phase-5 `stRunTransactions` KATs (BIP-143 / EIP-155 / EIP-1559) - the
last of which is NEW offline surface (runbook inventory item 8) having its first
engine pass. The only genuinely-absent surface is Schnorr/BIP-340, deferred with
Taproot; `cxBtcAddressP2TR` encodes an output key it is GIVEN and does not tweak.

**What flips:** the "PHASE 2 STATUS" block and the "STILL VERIFIED STATICALLY"
paragraph in the `coinxt/src/coinxt.lcb` header, the matching sentences in
`coinxt/CLAUDE.md` (both the phase-1 residual and the phase-2 as-built note), the
residuals in `coinxt/IMPLEMENTATION-PLAN.md`, the Status section of
`coinxt/README.md`, the api-reference status blockquote, and the coinxt row in the
root `README.md`. A green run retires the phase-1 residual (12 handlers) and the
phase-2 one (15 handlers) at once, and closes phase 2 outright.

> **All four committed libraries are current for ABI 4**, including `x86-linux`
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
`examples/onionxt-demo.livecodescript` establishes in `preOpenStack`, so running the
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

PREREQ
[ ] platform binaries present or fetched (section 2.1)
[ ] sxVersion() ......... loaded?  result: ______
[ ] btStartSession() .... loaded?  result: ______   (then btStopSession)
[ ] enLibraryVersion() .. loaded?  result: ______
[ ] dcLibraryVersion() .. loaded?  result: ______
[ ] oxVersion() ......... loaded?  result: ______
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

DEPTH (per-member selftests)  <- closed 2026-08-10 via the folded suite runs
[x] sodiumxt   sxSelfTest()                   2026-08-12: 71/0 (latest folded run)
[x] enetxt     enet-selftest (sync half)      2026-08-10: 21/0 (folded, twice);
               the async loopback ran standalone 2026-08-07; still open: its
               live status assertions (the enHostStatus pair + the enPeerStatus
               statistics and post-disconnect count, added 2026-08-13)
               <- one paste closes it
[x] datachannelxt  datachannel-selftest (sync)  2026-08-10: 23/0 (folded, twice);
               still open: its own async-loopback halves (live dcSendText,
               dcBufferedAmount, gathering/candidate-pair, and the dcBufferedLow
               event after a cap-sized send, added 2026-08-13)
               <- one paste closes it
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
[ ] datachannel-loopback
[ ] enet-lan-chat            (one machine / two machines: ______)
[ ] torrent-quickshare
[ ] torrent-client
[ ] onionxt demo vs live tor
[ ] torrent-quickshare with Tor toggle ON     (no torrent created? ______)
[ ] datachannel-dht-chat     (needs torrentxt + two machines)
[ ] torrent-dht-channels / torrent-rp1-chat   (two machines)
[ ] onionxt Mode B: oxLaunchTor               processId: ______  bootstrapped: ___
[ ] coinxt-demo (phase 6: mnemonic -> decoded, signed BTC+ETH tx)
[ ] riptide-social (one machine / two machines: ______)  <- item 6's vehicle

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
