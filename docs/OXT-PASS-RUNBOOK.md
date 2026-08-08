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
proved that every `sx*` / `bt*` / `en*` / `dc*` / `ox*` / `oxh*` / `cx*` call in the
suite resolves to a handler that exists. So a failure tonight is very unlikely to be a
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
| 1 | ~~**datachannelxt has never had an engine pass at all.**~~ **CLOSED 2026-08-08.** | The member now has engine evidence: `dcInit`, a stale-handle no-op, peer and channel creation, a live loopback that negotiated and opened both ends, a byte-for-byte payload round-trip, the `-4` refusal at 60001 bytes, a payload at the SCTP-negotiated cap, and `dcCleanup`. **Residual:** that covered 20 of the 35 public `dc*` handlers; `tests/datachannel-selftest.livecodescript` covers all 35 and has still not been run. | Labels updated in `datachannelxt/README.md`, `examples/README.md`, `docs/getting-started.md`, `tests/datachannel-selftest.livecodescript`, and `src/datachannel.lcb`. |
| 2 | ~~**coinxt's binding is brand new and has never been loaded.**~~ **CLOSED 2026-08-08 — and it closed coinxt phase 1.** | All five numbered questions in the `.lcb` header were answered, each on the side the code assumed: the module loads and binds resolve; the ABI guard holds (transitively — `sPrepare()` is the whole body of `cxCheckABI()` and every wrapper calls it); **`UIntSize` works as a foreign RETURN type**; **`MCDataGetBytePtr` marshals an empty `Data`** (`cxKeccak256("")` returned `c5d2…a470` instead of throwing); and the vectors are byte-exact. Neither fallback — `CUInt`, `optional Pointer` — was needed. **Residual:** 12 of the 16 public handlers were not called by name (`cxCheckABI`, the six `*Len` accessors, `cxSha512`, `cxHmacSha256`, `cxHmacSha512`, `cxPbkdf2HmacSha512`). | Labels updated in `coinxt/src/coinxt.lcb` (STATUS block), `coinxt/CLAUDE.md`, `coinxt/IMPLEMENTATION-PLAN.md`, and the root `README.md` row. |
| 3 | **The selftests grew after their passes; the new sections are static-only.** torrentxt, enetxt, and sodiumxt all had coverage added in the "test coverage" follow-up commit, which post-dates every recorded pass. | A green run from an older, smaller harness does not cover handlers added later. The extended sections are where new binding bugs would hide. | `torrentxt/tests/torrent-selftest.livecodescript` COVERAGE NOTE: the v9-v11 surface (`btDhtBep44SignBuf`, `btDhtPutSigned`, `btDhtGetPeers`, `btAddInfohash`, `btMapPort`/`btUnmapPort`, `btRp1*`) "proves the .lcb wrappers, once an engine runs it (verified statically until then)". `enetxt/tests/enet-selftest.livecodescript` COVERAGE NOTE: the isolated `enDisconnectNow` / `enResetPeer` / `enSetPeerTimeout` / `enSetHostBandwidth` section, "verified statically; it needs an OXT pass to become a runtime result". `sodiumxt/docs/api-reference.md`: "The recorded on-engine pass predates those additions, so the newer checks are verified statically and need an OXT pass to become a runtime result." |
| 4 | **onionxt Mode B (launching tor as a child process) has never run.** | It is the one remaining `VERIFY:` in an otherwise on-engine-proven member, and it is what a turnkey app would ship. | `onionxt/CLAUDE.md`, "Still `VERIFY:` (not yet exercised)" item 8: "`the processId` / `open process` for the optional Mode B tor launch (the default is assume-running)." Also the intro blockquote in `onionxt/docs/10-usage-guide.md` and `onionxt/docs/07-tor-lifecycle.md` Mode B. |
| 5 | **torrentxt's Tor path (Quick Share Model C) has never run against a daemon.** | It is a cross-member composition, so it is the one place three members must agree at runtime. | `torrentxt/examples/torrent-quickshare.livecodescript` (two places): "Every ox* handler is OnionXT's published ABI; this is verified statically ... and NEEDS an on-engine OXT pass with a running Tor daemon before any runtime claim." Register: `docs/ONIONXT-INTEGRATION-PLAN.md` section 12.3. |
| 6 | **Two-machine behaviour, for every member that has it.** enetxt's LAN chat, torrentxt's rp1 chat and Channels, datachannelxt's DHT chat. | Loopback proves the binding; only a second machine proves the transport. | `enetxt/CLAUDE.md`: "Still un-exercised: the LAN chat demo between two real machines." `torrentxt/examples/README.md`: rp1 chat "needs a live peer to show anything, so it is a two-machine test by nature." |

Items 1 and 2 used to be "the whole evening" — the only two places where an entire
member was unwitnessed. **Both are now closed.** For a short session today, the
highest value is item 3: run the deeper per-member harnesses
(`tests/datachannel-selftest.livecodescript` first, since it has the largest
uncovered surface, then `torrent-selftest`, then `enet-selftest`, then
`sxSelfTest()`). Items 4, 5 and 6 need a tor daemon or a second machine and should
be planned as their own sessions.

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
   into your app and `start using` them, or build a paste-and-run standalone with
   `onionxt/tools/build-standalone.py` (see `onionxt/docs/10-usage-guide.md`).
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

### 2.4 coinxt: doable on Linux x86_64, a build away everywhere else

coinxt now ships **`coinxt/src/code/x86_64-linux/coinxt.so`**, pinned in
`coinxt/src/code/MANIFEST.sha256`. That is the exact file the engine dlopen()s when
`coinxt/src/coinxt.lcb` binds `c:coinxt>`, so **on Linux x86_64 there is nothing to
build**: coinxt installs like any other member and the run below is just a run.

On any other platform, build it first - one command, and it puts the file where the
engine expects it:

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

There is still **no `tools/package-extension.py`** for coinxt, so wrapping the `.lcb`
plus the binary into an installable extension is the one manual step left. That is the
only remaining cost, and it is now the same cost as any hand-packaged member - not the
highest on this list.

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

**Step 0 - the one-run entry point (do this first, always).**

`tests/suite-selftest.livecodescript` is the suite-wide stack: it probes each
extension, **skips what is absent**, and reports pass / fail / skip. Paste and reopen
it per 3.1. It is the cheapest possible signal: in one run it tells you which
extensions the engine can actually see and which broad areas are already unhappy,
before you have invested in any per-member setup. Treat its skips as a checklist of
what you still have to install.

Do **not** treat a green suite selftest as a substitute for the per-member harnesses.
It is breadth; the per-member selftests are depth.

**Step 1 - the per-member selftests, in this order.**

Ordered by (value of the result) divided by (setup cost):

| Order | Stack | Needs | Why here |
|---|---|---|---|
| 1 | `sodiumxt/examples/sodium-tests.livecodescript` (`put sxSelfTest()`) | sodiumxt only | No I/O at all, no network, runs in a second. Everything else composes sodiumxt, so a failure here invalidates results further down. |
| 2 | `enetxt/tests/enet-selftest.livecodescript` | enetxt only | Loopback UDP on 127.0.0.1, no daemon, no second machine. Also the fastest way to discover a machine that blocks loopback UDP, which would also sink datachannelxt (see trap 5.5). |
| 3 | `datachannelxt/tests/datachannel-selftest.livecodescript` | datachannelxt only | **The single highest-value run of the night.** Two real WebRTC peers in one process: offer, answer, ICE, DTLS, SCTP, text and binary round-trips, teardown. First engine evidence this member has ever had. |
| 4 | `torrentxt/tests/torrent-selftest.livecodescript` | torrentxt only, **and nothing else torrent-flavoured open** | About 70 checks. Read trap 5.1 first: one session per OXT process. |
| 5 | `onionxt/examples/onionxt-tests.livecodescript` (`put oxSelfTest()`) | onionxt + sodiumxt; **no daemon needed** | Deliberately pure and offline: address/base32 vectors, fail-closed contracts, idempotent teardown, and the two sodiumxt ABI-6 primitives. Read trap 5.6: it really does tear down live state. |
| 6 | coinxt: no harness stack; drive `coinxt/src/coinxt.lcb` by hand | coinxt packaged (the Linux x86_64 library is committed; elsewhere run `pack` first - 2.4) | Follow the numbered engine-pass list in the `.lcb` header, in order. See 4.6. |

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

### 4.2 datachannelxt (inventory item 1)

**A pass looks like:** `stSummary` green, zero failures. The run covers the whole
synchronous surface (including `dcCreateChannelEx`, `dcSetBufferedLowThreshold`,
`dcLocalDescriptionType`, `dcChannelProtocol`, `dcSetLocalDescription`), stale handles
behaving as harmless no-ops, a **live loopback** that actually connects, text and
binary messages round-tripping byte for byte, the drain's arrays carrying the
documented keys, and idempotent close / free / cleanup. It also pins the non-trickle
signalling contract: a live local description carries `a=candidate`, and the
offer/answer roles match the flow.

**Copy back:** the full `stResults` text.

**What flips:** this is the member's *first ever* engine evidence, so a green run flips
its whole script layer from designed to observed. Update these labels:

- `datachannelxt/README.md`, the "Honesty note" block ("No OXT engine run has been
  recorded for this member yet") - replace with the dated result.
- `datachannelxt/examples/README.md`, the same honesty note.
- `datachannelxt/docs/getting-started.md`, the honesty note in the intro.
- `datachannelxt/tests/datachannel-selftest.livecodescript`, the COVERAGE NOTE
  sentence "no such pass is recorded for this member yet".
- Root `README.md`, the release-status row: "Phases 1-2 (data channels); script layer
  needs an OXT pass".

Leave `datachannelxt/CLAUDE.md`'s *rule* about not claiming unobserved behaviour
alone - that is policy, not a status label.

### 4.3 enetxt (inventory item 3)

**A pass looks like:** green summary, and specifically the **isolated teardown
section** (`enDisconnectNow`, `enResetPeer`, `enSetPeerTimeout`, `enSetHostBandwidth`
against a client host pointed at a dead port) plus `enHostStatus` asserted both stale
(empty) and live (peerCount, address). Those are the sections added after the
2026-08-07 pass.

**Copy back:** the full `stResults` text, so the new sections are visibly green.

**What flips:**

- `enetxt/tests/enet-selftest.livecodescript`, the COVERAGE NOTE line "The harness
  itself is verified statically; it needs an OXT pass to become a runtime result."
- `enetxt/CLAUDE.md`, the Phase-1 blockquote: add the new date and note that the
  extended coverage is now included, alongside the existing 2026-08-07 record.

If you also run the LAN chat between two machines, that retires the last line of that
same blockquote: "Still un-exercised: the LAN chat demo between two real machines."

### 4.4 torrentxt (inventory item 3)

**A pass looks like:** green summary across roughly 70 checks, and specifically the
**signed-puts section**: `btDhtBep44SignBuf` determinism, `btDhtPutSigned`,
`btDhtGetPeers`, `btAddInfohash`, `btMapPort` / `btUnmapPort` handling "no mapper"
cleanly, and `btRp1Enable` / `btRp1SetToken` / `btRp1Send` / `btRp1Poll` handling "no
peer" cleanly.

**What it deliberately does not prove:** async DHT and tracker results (they arrive
later as events), a real rp1 message exchange (two machines), and the two destructive
handlers it skips on purpose (`btMoveStorage`, `btRemoveTorrent`-with-delete). Do not
record those as passed.

**Copy back:** the full `stResults` text.

**What flips:**

- `torrentxt/tests/torrent-selftest.livecodescript`, the COVERAGE NOTE clause "this
  file proves the .lcb wrappers, once an engine runs it (verified statically until
  then)".
- `torrentxt/README.md`, the status paragraph that says runtime behaviour "is marked
  'verified statically; needs an OXT pass' and confirmed by a human in the IDE".

### 4.5 sodiumxt (inventory item 3)

**A pass looks like:** `put sxSelfTest()` returns a per-check report ending in a
PASSED summary with zero failures, including the sections added after the recorded
pass: the attached-signature form, seed-derived keypairs, keyed hashing, and the
diagnostics / preset accessors.

**Copy back:** the whole message-box report.

**What flips:**

- `sodiumxt/docs/api-reference.md`, "See also": "The recorded on-engine pass predates
  those additions, so the newer checks are verified statically and need an OXT pass to
  become a runtime result."

### 4.6 coinxt (inventory item 2)

There is no self-building harness. Drive the numbered list in the header of
`coinxt/src/coinxt.lcb`, **in order**, and record the answer to each:

1. The module compiles and loads, and the `c:coinxt>` binds resolve. (A renamed or
   missing export is a silent bind failure at load, so this is the gate.)
2. `cxCheckABI()` returns cleanly against the shipped binary (ABI 2).
3. **`UIntSize` as a foreign RETURN type** (the `cx*Len` accessors return C `size_t`).
   This is the genuinely novel one: `UIntSize` is proven in this family as a
   *parameter*, never as a return. If the engine rejects it, the documented fallback is
   `CUInt`, and the `.lcb` comment must be updated with what you actually saw.
   **Write down the exact error text if it rejects.**
4. `MCDataGetBytePtr` on an **empty** `Data`. The C side is safe either way (the shim
   substitutes a valid one-byte source when the length is 0), so the open question is
   the **marshalling**, not the hashing. If the engine imports a null byte pointer as
   `nothing`, the plain `Pointer` slot rejects it and `cxKeccak256("")` **throws instead
   of returning a digest** - which is the very first thing item 5 tries, so a failure
   here will look like a vector failure and is not one. The documented fallback is
   `optional Pointer` on the IN-buffer parameters; the shim needs no change.
   **Write down the exact error text if it throws.**
5. The vectors themselves, from script, byte for byte: `cxKeccak256("")` must be
   `c5d2...a470`, and the rest of `coinxt/tools/coin-kat.py`.

**A pass looks like:** all five, in order, with item 5 byte-exact.

**What flips:**

- `coinxt/src/coinxt.lcb`, the `STATUS: VERIFIED STATICALLY; NEEDS AN OXT PASS` block
  (and specifically the `UIntSize` return-type note in item 3).
- `coinxt/CLAUDE.md`: "Phase 1, the `.lcb` foreign module - WRITTEN; verified
  statically, needs an OXT pass."
- `coinxt/IMPLEMENTATION-PLAN.md`, the status blockquote. Per that plan, **phase 1
  closes** when `cxKeccak256` and friends return the pinned vectors from a real engine.
  This one result closes a phase.
- Root `README.md`, the coinxt release-status row.

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

### 5.2 A stack must be CLOSED and REOPENED

Pasting the script is not running it. `openStack` is what builds the UI and starts the
run, and it does not fire on paste. If nothing happens after you paste, you skipped
step 4 of section 3.1. Escape hatch: `send "openStack" to this stack`.

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

DEPTH (per-member selftests)  <- this block is now the open work
[ ] sodiumxt   sxSelfTest()                   ___ passed ___ failed
[ ] enetxt     enet-selftest                  ___ passed ___ failed
               (the isolated teardown section is the part still unproven)
[ ] datachannelxt  datachannel-selftest       ___ passed ___ failed   <- highest value
               (15 of 35 dc* handlers untouched by the suite pass)
[ ] torrentxt  torrent-selftest               ___ passed ___ failed
               (~70 checks; the suite pass covered 11 handlers)
[ ] onionxt    oxSelfTest()                   ___ passed ___ failed ___ skipped
[x] coinxt     .lcb items 1-5 in order        2026-08-08: 1:PASS 2:PASS(via sPrepare)
                                             3:PASS UIntSize return works
                                             4:PASS empty Data marshals
                                             5:PASS vectors byte-exact
                                             -> PHASE 1 CLOSED

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
