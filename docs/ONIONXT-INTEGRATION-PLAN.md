# Model C - the anonymous transport

**Scope:** the optional Tor onion transport in torrentxt's QuickShare and DHT Channels demos
(`torrentxt/examples/torrent-quickshare.livecodescript`, `torrentxt/examples/torrent-dht-channels.livecodescript`)
over onionxt + sodiumxt. nocloud's Quick Share carries its own copy of the QuickShare layer (user page:
`nocloud/docs/what-it-hides.md`); riptide's anon rail reuses the BTXO framing (3.3).

> **Old name, stable numbers.** About 75 comments in the two demos and `torrentxt/tests/onion_frame_golden.py` cite
> this file by section ("section 6.7 guard 3", "section 3.3 step 6b", "section 12.2") and the runbook ticks the
> 12.3 register by `#`, so the name and sections 3, 6, 7, 10, 12, 13 and 14 keep their meanings (4 and 8 were
> folded into 3). On 2026-09-23 it absorbed the three anon-transport pages (the overview, the threat model and
> the onboarding guide; deleted, git history has them) and dropped its build instructions: the code is
> built, so the code is the record of how.

## 1. What Model C is, and where it stands

### 1.1 Status

Every behavioural claim here is **verified statically; needs an OXT + live-Tor pass**. Proven so far:

- **The `ox*` surface itself:** onionxt's own engine pass against a live tor daemon and Tor Browser, SAFECOOKIE
  auth included (recorded in `onionxt/CLAUDE.md`); `oxSelfTest()` 43/43 on 2026-08-12 (Windows x64, SodiumXT
  ABI 7), re-encoding the torproject and DuckDuckGo onions byte-exactly and refusing a tampered address.
- **The offline half of the identity equivalence (#27):** libsodium and libtorrent derive the same ed25519
  public key from one seed. Engine-green through the script layer in the suite paste's "CROSS: one seed, one
  identity" section (the 2026-08-08 pass, per the status line of `tests/cross-member-test.py`), and since
  2026-08-17 measured natively against the built shims by that file in `suite-gates.yml`'s cross-member job
  (`CROSSMEMBER_REQUIRE_ALL=1`), which runs on any push touching sodiumxt/ or torrentxt/.
- **The wire formats, off-engine:** `torrentxt/tests/onion_frame_golden.py` pins the BTXO framing, the BTXTOR1
  code and `qsSafeLeaf`, and since 2026-08-23 the Channels BTXC/BTXF frames and `chSafeLeaf` (12.2).

Not yet proven: **the composition**, torrentxt's Tor path end to end on an engine with a real daemon on each of two
machines: runbook row 5 (QuickShare; 12.4), row 21 (Channels; #31-#33) and the section 13 fresh-user exit. When
row 5 passes, this label becomes a dated record and #28's measured figure replaces "unmeasured". Built 2026-08-15
(section 10); open work is tracked in the suite work plan (docs/WORK-PLAN.md).

### 1.2 What it is

The demos' default path is public BitTorrent, where both IPs are visible to the swarm. Model C adds an **OPTIONAL**
transport beside it, off by default: the file bytes travel **onion-to-onion** over an OnionXT stream and **no
torrent is ever created**. It needs OnionXT + SodiumXT + a local tor daemon and **fails closed**: a missing piece
disables the toggle with its reason and never regresses a clearnet feature. It changes **zero compiled
extensions** (demo-script work only; `BTX_ABI_VERSION` did not move).

**THE invariant (enforced in code, not advised).** An anon payload calls none of `btCreateTorrent` /
`btAddTorrentFile` / `btAddMagnet` / `btDhtPutMutable` / `btDhtGetMutable`. Anon and clearnet are mutually
exclusive per payload. No failure path falls back from Tor to the swarm: it aborts, never downgrades, never
queues. The "via Tor" (QuickShare) and teal "Onion" (Channels) transfer-row tags make the mode visible.

**Scoping caveat.** The host still runs one DHT/LSD-enabled `btStartSession`, so it remains a visible DHT node.
"Both IPs hidden" is scoped to the anon file bytes, not to the machine's network presence.

### 1.3 The user summary

The sentence every other claim must stay consistent with (7.1 read as prose; D-05 signed the copy off 2026-08-27):

> Model C hides WHERE (both IPs) and, composed with SodiumXT, WHAT and authenticates WHO. It does not hide WHEN,
> HOW MUCH, or THAT-you-use-Tor, and plaintext-anon does not authenticate the sender.

**It hides** both IPs from each other (the receiver sees only a `.onion`, the sender only an inbound circuit) and
from the network (no swarm, tracker or DHT entry carries the file or either address); the bytes and filename in
transit; and the payload from the DHT. **It does NOT hide** that you use Tor; timing and volume from a watcher of
both ends; anything from your local tor daemon, which is trusted (7.5); or the sender of a plaintext transfer.
**Honest limits, told to users:** throughput is modest and UNMEASURED (quote no number until #28 measures one);
above 256 MiB the demos warn and offer the public swarm with the explicit caveat that it reveals your IP, never
silently (D-11); no resume, an interrupted transfer restarts from byte 0; and the sender's window must stay open,
because the service lives in it and an ADD_ONION service dies with its control connection (runbook trap 5.4).

## 2. Ground rules

One interpreter thread, never blocked (3.5); fail-closed probes mirroring `sCanEncrypt`; the honesty convention.
Every handler is `<pfx>Onion...` (`qs` / `ch`); the draft spellings `qsOn*`, `sAnon`, `sOxReady`, `sStaged`,
`sAnonRows` are retired. One wire protocol: BTXO (3.3), BTXC/BTXF on top (6.4), the `BTXTOR1:` code (5.2); the
draft `BTXON1` / `BTXQS2:` / typed SELECT/META/DATA/FIN scheme is deleted and not tested. Every onion constant is a
literal declared before first use (3.2).

## 3. Shared foundation - the onion-transport layer (both demos)

Each demo carries its own copy under its prefix; its contract is 1.2's mutual-exclusion invariant.

### 3.1 The two-stage capability probe

| State | Meaning | Lifetime |
|---|---|---|
| `sHasOnion` | `oxVersion()` resolves in a `try` AND `sCanEncrypt` | STATIC: probed once at start |
| `sTorReady` | control authenticated AND bootstrap at 100 | LIVE: cached for the UI only |

- `sHasOnion` includes `sCanEncrypt` because OnionXT needs SodiumXT even for plaintext ("needs SodiumXT" reads
  distinctly from "no Tor"). **Every go/no-go re-reads `oxIsReady()` at the moment of use** (`<pfx>OnionReadyNow`).
- As built (`onionxt/docs/05-api-reference.md`): `oxIsReady()` = bootstrap 100 AND control authenticated.
  Descriptor upload is separate, the `serviceReady` status event / `oxServiceIsReady`, and an address is
  advertised only after `serviceReady`. (The original plan wrongly folded the descriptor into `oxIsReady`.)
- **Mid-bootstrap an anon action is REFUSED** and retried by the user: no pending-action queue. Either probe false
  leaves every clearnet feature untouched.

### 3.2 Tor lifecycle - constants, ports, pill, stop

As-built constants, identical in both demos:

| Constant | Value | Constant | Value |
|---|---|---|---|
| `kOnionMagic` | `"BTXO"` | `kOnionPumpTick` | 15 ms |
| `kOnionVer` | 1 | `kOnionSendTimeout` / `kOnionRecvTimeout` | 30000 / 60000 ms idle |
| `kOnionVPort` | 80 | `kOnionPublishTimeout` | 90000 ms |
| `kOnionChunk` | 65536 | `kOnionMaxName` | 1024 |
| `kFlagEnc` | 1 (flags bit0) | `kOnionMaxTotal` | 8589934592 (8 GiB) |
| `kTorSocksPort` / `kTorControlPort` | 9050 / 9051 | `kAnonSizeWarn` | 268435456 (256 MiB) |
| `kTorSocksPortTB` / `kTorControlPortTB` | 9150 / 9151 (Tor Browser) | | |

QuickShare adds `kTorCodePrefix = "BTXTOR1:"` and `kQsVerify = "BTXQSVERIFY"`. Channels adds
`kOnionFeedCap = 65536`, `kChanReqMagic = "BTXC"`, `kChanReqVer = 1`, `kFeedFrameMagic = "BTXF"`,
`kFeedFrameVer = 1`, `kVerbFeed = 1`, `kVerbFile = 2` and `kChRowOnion = "0,150,150"`.

- **Ports:** `oxConnectControl` tries 9051, then 9151 exactly once (the Tor Browser pair), SOCKS set to match
  (9050 / 9150). Loopback 127.0.0.1 only: a remote control port hands full deanonymization to that host. No
  custom ports. The ephemeral loopback port is `20000 + random(40000)` (`chPickPort`; the same in QuickShare).
- **Mobile is unsupported**, with its own fail-closed reason (built 2026-09-24; until then a mobile engine landed in
  "no daemon"). Both demos check `the platform` (`iphone` / `android`) first (`qsOnionOnMobile` /
  `chOnionOnMobile`): no `ox*` call is made, the pill reads `Tor: not on this device`, and every refusal names the
  device rather than a missing daemon or extension. Verified statically; needs an OXT pass on a mobile engine.
- **Start** (tail of `qsStart` / `chStart`, only when `sHasOnion`): ports, callbacks, connect 9051 then 9151; never
  block on bootstrap. On the first ready transition Channels calls `chOnionBringUpServices` (6.3). **Stop**
  (BEFORE `btStopSession`): close streams, remove services, disconnect, delete temps; idempotent.

The pill (`qsTorPill` / `chTor`), repainted only by `<pfx>OnionPill`:

| Pill | Meaning |
|---|---|
| `Tor: not on this device` | a phone or tablet (`the platform` is `iphone` or `android`); toggle disabled |
| `Tor: no extension` / `Tor: needs SodiumXT` | OnionXT not in the message path / SodiumXT missing; toggle disabled |
| `Tor: no daemon` | no control port authenticated on 9051 or 9151; toggle disabled |
| `Tor: connecting NN%` | bootstrapping; toggle enabled, actions refused until ready |
| `Tor: ready` | anonymous sends and receives will work |

### 3.3 The framed, chunked file-streaming protocol (BTXO)

The byte layout is normative in 12.2: a header (magic, version, flags, `nameLen`, name, `totalLen`), data frames
(`len` u32, then bytes), and a zero-length terminator. The receiver waits for 8 bytes, reads `nameLen`, then waits
for `nameLen + 8` more. Binary discipline only (`numToByte` / `byteToNum` / `binaryEncode` / `binaryDecode`).
**`"n"` is big-endian u16 and `"N"` big-endian u32; `"m"` is NOT a big-endian u16 code.** LiveCode has no u64,
so `totalLen` travels as hi:u32 then lo:u32 (`div` / `mod 4294967296`, `"NN"`); numbers are doubles, exact to
2^53.

**The dialer speaks first** with the 4-byte `"BTXO"` go request (in Channels, a BTXC request, 6.4); then the
server sends the header. QuickShare's server auto-detects BTXO versus HTTP `GET ` / `HEAD ` (Tor Browser) and
closes on anything else.

**SafeLeaf** (`qsSafeLeaf` / `chSafeLeaf`, separate copies, both golden-pinned): basename only (strip through the
last `/` or `\`), strip a drive colon and leading dots, reject `..`, surviving separators and control characters,
map empty to `"shared-file"`. Apply it to BOTH the code name and the header name, before opening the temp AND
again before the final move. The header name is a display label plus a sanitized leaf, never a path.

**Bounded buffers:** reject `len > kOnionChunk`, `nameLen > kOnionMaxName` and `totalLen > kOnionMaxTotal`
BEFORE appending or allocating (`0xFFFFFFFF` is an immediate abort and close), and drain and compact the buffer
every call so it holds at most one chunk plus a partial frame. **Free disk** is checked before the temp opens
(`qsOnionDiskShortfall` / `chOnionDiskShortfall`, built 2026-09-24): `diskSpace()` on the temp's disk and on the
save folder's, each against `totalLen` (2x when encrypted), failing closed with a readable reason. A disk that
cannot be measured is not a refusal; the write-failure abort stays the backstop. Verified statically; needs an
OXT + live-Tor pass (`diskSpace()` has no engine record in the suite yet).

**Integrity is layered:** the circuit's own; with `kFlagEnc`, `crypto_secretstream`'s per-chunk authentication
and final tag (truncation is caught on decrypt); for plaintext, the `totalLen` check. **The plaintext path does
NOT authenticate the endpoint**, and the anon badge must never imply it.

**SENDER** (per-stream state keyed by the stream handle):

1. With a passphrase, encrypt first to a temp `.enc` (`qsEncryptFile` / `chEncryptFile`), set `kFlagEnc`, stream
   that. **Register every temp for cleanup at creation, BEFORE the encrypt that can throw.**
2. On the go request (or BTXC request), send the header.
3. Each pump tick sends ONE frame; at EOF send the terminator, close the file and stream, delete the temp.
4. **No writability gate:** OnionXT has no writable callback, so the pump paces on `kOnionPumpTick` plus
   `oxWrite`'s error return (an `oxStreamState` gate could misread a live stream and stall forever). Never a
   tight `repeat`, never `send ... in 0`.
5. Concurrent serves go round-robin, one frame across the active streams per tick.
6. **One file handle per serve:** LiveCode keys open files by path, so a shared open lets the first `close`
   truncate a second reader. (a) QuickShare allows one active receiver at a time. (b) Channels re-opens per read
   (open / seek / read / close within one tick, `chOnionSendPump`), so a release fans out.
7. A self-arming send watchdog, armed at accept, aborts on an idle gap beyond `kOnionSendTimeout`.

**RECEIVER:** (1) register the stream callback before any byte can arrive; (2) header: validate magic, version and
`nameLen`, then name and `totalLen`, SafeLeaf the name, **register the temp for cleanup immediately**, open it;
(3) body: drain every complete frame, rejecting `len > kOnionChunk` before waiting for it; zero length is done;
(4) done: `got == total` or abort, then decrypt (or move) into the save folder as `SafeLeaf(name)`; (5) a close or
socket error before done aborts: close, delete the temp, clear state, log; (6) **watchdogs are SELF-ARMING at
dial/accept**, not only refreshed on data, so a dialed stream that delivers zero bytes still aborts, and timeouts
measure the idle gap, not the total; (7) temps are deleted on abort, after a decrypt, and in `<pfx>OnionStop`.

**No resume:** the header carries no offset; an interrupted transfer restarts from byte 0 (accepted, told to users).

### 3.4 The onion service side

- **OnionXT owns the accept loop.** Neither demo calls `accept connections on`: OnionXT binds the ephemeral
  loopback port passed to `oxCreateServiceFromSeed` and delivers inbound streams through `oxSetPeerCallback`.
  Channels finds the channel from the BTXC key, not `pService` (`oxGuessService` is best-effort).
- **QuickShare:** `oxCreateServiceFromSeed(sxRandomBytes(32), 80, port)`, a fresh unlinkable `.onion` per share
  and no persistent presence oracle. **Channels:** `oxCreateServiceFromSeed(channelSeed, 80, port)`, a
  deterministic `.onion` bound to the channel pubkey (6.1), linkable by design.
- **Advertise only when reachable:** a code or feed carries an address only after `serviceReady`. The 90 s
  publish timeout tears down a half-built service and re-enables the drop.
- **Loopback scope:** 127.0.0.1 only; a stream not opening with an expected magic (or, in QuickShare, an HTTP
  verb) is closed at once. Any local process can still reach the port: a known limit of the demos.
- **Counts:** one service per QuickShare session (a new drop replaces it), one per anon channel, each on its own
  port; N live at once is an open 12.3 row. One global `oxSetStatusCallback`: if co-hosted, one dispatcher fans out.

### 3.5 Coexistence with the `btPoll` loop, and the threading rules

- The BitTorrent drain is unchanged (250 ms `btPoll`, 1 s dash, Channels' 60 s `chChannelTick`). OnionXT's status,
  peer and per-stream callbacks are ordinary engine messages on the same queue: cooperative and interleaved, never
  concurrent, no locking. Library-delivered callbacks pin the defaultStack at entry (suite engine note 5.3).
- **Never block:** `oxDial` is asynchronous everywhere (callback first, first write gated on ready, watchdog armed
  at dial); files move in bounded 64 KiB slices, one frame per tick; `sxEncryptFile` / `sxDecryptFile`, the one
  legitimate multi-hundred-ms pause, runs once, outside the pump. The pump runs only while a send is in flight and
  re-arms at >= 15 ms, never `in 0`, so it never starves the poll or the 1 s repaint; inbound is event-driven.
- The anon path emits no libtorrent events; its progress lives in `sOnionXfers` (QuickShare) / `sOnionXfer`
  (Channels), shown in the same transfers table.

## 5. QuickShare as built

| Passphrase | Tor | Transport | Contents | Share code |
|---|---|---|---|---|
| empty | off (default) | BitTorrent | plaintext | bare 40/64-hex info-hash |
| set | off | BitTorrent | SodiumXT `.enc` | `BTXQS1:...` |
| empty | on | onion stream | plaintext; **sender NOT authenticated** | `BTXTOR1:<onion>:<b64name>::` |
| set | on | onion stream | SodiumXT `.enc` (**recommended**) | `BTXTOR1:<onion>:<b64name>:<b64salt>:<b64verify>` |

- **UI:** a "Send privately over Tor" checkbox (`qsTorToggle`) and `qsTorPill`, in the kit-v2 card look. The
  pill disables the toggle with its reason whenever the environment cannot honour it, so the mode is never left
  armed. Receiving needs no toggle: a pasted `BTXTOR1:` code routes itself.
- **The code (5.2):** `BTXTOR1:<onion>:<b64 SafeLeaf name>:<b64 Argon2id salt>:<b64 sealed kQsVerify
  verifier>`; the last two fields are empty for plaintext, so the code ends `::`. Parsing on `:` is safe because
  a v3 onion (56 base32 characters + `.onion`) and base64 never contain `:`. **A pre-Model-C build must reject
  the unknown prefix cleanly** (register #17).
- **Send (5.3):** `qsShareFile`'s first branch takes the anon path and returns before any `btCreateTorrent` /
  `btAddTorrentFile` call; not ready means refuse ("Tor is still connecting - watch the pill, then drop the file
  again."), never clearnet. Above `kAnonSizeWarn`, proceed only on explicit confirmation (D-11). A passphrase
  encrypts exactly as the public encrypted path does (Argon2id key from the passphrase + a fresh salt,
  `crypto_secretstream`, `kQsVerify` sealed with `sxSecretBox` as the verifier). A fresh random-seed service per
  share; the code appears only after `serviceReady` (up to a minute). **One active share** (a new drop replaces
  the service) and **one active receiver**; a sequential retry reuses the code, and the service persists until
  replaced, withdrawn or stopped.
- **Folders (5.3):** an anon folder is served as a browsable `http://<onion>/` page for Tor Browser, always
  plaintext (a browser cannot decrypt). A plaintext single file can opt in via "Serve as web download".
  **"Share via web link" is a separate DIRECT CLEARNET mode and anonymizes nothing.**
- **Receive (5.4):** refuse an invalid address or a missing OnionXT with a message. **The passphrase is
  verified LOCALLY before any dial**, against the sealed verifier: a wrong passphrase costs zero network. **A
  plaintext code needs explicit confirmation** past: "Your IP address stays hidden, but the sender is NOT
  verified - anyone who intercepts the code could substitute a file. Ask your friend for a passphrase for a
  verified transfer." Re-read readiness; dial asynchronously (`oxDial` returns an integer handle through
  `the result` at once; a failure is an `"OnionXT: ..."` string, so test `the result is an integer`).
- **Downgrade refusal (5.4):** if the code carried a verifier, the header MUST set `kFlagEnc`, else abort with
  "This share was supposed to be encrypted but arrived unencrypted - do not trust it." An encrypted header with
  no passphrase in the code aborts with "This file is encrypted but the code had no passphrase - ask your friend
  to re-share."
- **Transfers and fallbacks (5.5, 5.6):** onion rows are tagged "via Tor" ("(locked)" when encrypted). A sender
  going offline aborts the receiver, which can retry the code from byte 0 while the sender's window stays open.

## 6. DHT Channels - Model C design (built 2026-08-15)

An anon channel's **feed AND files** travel over the channel's own onion service, never DHT or BitTorrent. Anon
is orthogonal to the channel passphrase, and they compose:

| anon | pass | Menu label | Transport gives |
|---|---|---|---|
| off | empty | `Name` | public swarm + public DHT feed (the default) |
| off | set | `Name (private)` | swarm of ciphertext; secretbox feed on the DHT |
| on | empty | `Name (anon)` | feed + files over Tor; IPs hidden; no DHT graph; sender authenticated only by the pubkey-bound onion |
| on | set | `Name (private) (anon)` | Tor route AND SodiumXT contents (recommended) |

### 6.1 Identity - an anon channel needs no new key

A channel's BEP44 identity `btDhtKeypair(seed)["publicKey"]` and `oxCreateServiceFromSeed(seed, ...)` expand the
same seed, so **`chChannelOnionAddr(pub) = oxAddressFromPublicKey(sxHex2Bin(pub))`**: a follower holding the card's
64-hex key computes the `.onion` locally. **Privacy caveat (in `chHelp`):** the onion is linkable to the channel
pubkey by design (use a separate channel with an independent seed for unlinkability), and the stable address is a
presence oracle (7.6). **The `svc=<onion>` feed line** is the contingency: built at serve time by `chAnonFeedText`,
parsed by `chRefreshSubs` into `sFollowSvc`; if the equivalence ever failed, `svc=` is the source of truth.

**`chVerifyOnionIdentity` is the hard gate**, run once at `chStart`, offline:

1. A fixed, reproducible test seed.
2. `btDhtKeypair(seed)["publicKey"]` against `sxSignKeypairFromSeed(seed)`'s key, byte for byte: the real
   cross-implementation check (a codec self-round-trip would only prove the codec is self-inverse).
3. The codec is self-consistent: `oxPublicKeyFromAddress(chChannelOnionAddr(pub)) == pub`.
4. **VERIFY-on-service** (needs Tor, in `chOnionServiceFor`): `oxServiceAddress(handle) ==
   chChannelOnionAddr(pub)` byte for byte; a mismatch withdraws the service, sets `sOnionIdentityOk` false and
   disables anon, a hard safety stop.

Any failure disables anon with a loud log: a mismatched onion is worse than none. The offline codec needs SodiumXT
ABI 7 (`sxSha3_256`); on an older SodiumXT anon is DISABLED, never shipped with a silently wrong address. Steps
1-3 are #27's offline half (engine-green, 1.1); step 4 is its live half, still open, which settles D-04 (14.3).

### 6.2 Persistence

- `sChannels[i]["anon"]` (`"true"` / empty) rides the existing sealed `uChannels` path. **`chDeleteChannel` MUST
  copy `["anon"]` into the rebuilt array** (REQUIRED), or deleting any channel clears every survivor's flag.
- Follower side: `sFollowAnon` mirrored to `uFollowAnon`. **Backward compatibility (#17):** an old saved stack
  has no `uFollowAnon`, so it defaults empty.
- **`chSetAnon`** (modeled on `chSetPrivacy`) refuses without `sHasOnion` or `sOnionIdentityOk`, explains, then
  offers On / Off / Cancel. **Turning ON is a HARD BLOCK while any clearnet magnet release or live `sMineHashes`
  seed exists:** it offers one-click removal (`btRemoveTorrent` each) and never warns-and-proceeds. ON brings the
  service up; OFF withdraws it and re-announces the feed on the DHT, and **turning OFF is the same hard block while
  any `onion:` release is listed** (one-click removal of those releases and their serve entries; 7.3). Anon is
  whole-channel.

### 6.3 Per-channel service lifecycle (publisher)

`chOnionServiceFor pIndex` (guarded on anon + `sOnionIdentityOk` + ready; idempotent; one deterministic service
per anon channel on its own port; VERIFY-on-service; reachable on `serviceReady`). `chOnionBringUpServices` runs
from the first ready transition and defensively from `chChannelTick`, so services recover after a Tor restart
without blocking `chStart`. `chOnionWithdrawService pub` removes a service and its subscribers (from `chSetAnon`
Off, `chDeleteChannel`, `chOnionStop`). `chActivate` brings up the active anon channel; `chStop` calls
`chOnionStop` before `btStopSession`.

### 6.4 Feed rendezvous over the onion

The BTXC request and BTXF frame are normative in 12.2. The BTXC key is the 64-hex channel pubkey, and **the
server checks it OWNS the key and the channel is anon**, else closes. The BTXF value is exactly the `chFeedValue`
bytes (plaintext, or `BTXENC2:` + secretbox), at most `kOnionFeedCap`, repeatable for live push.

- **Serve** (`chOnionPeer` -> `chOnionServeStream` -> `chOnionServeRequest`). FEED: a BTXF reply, and the stream
  is **subscribed**: capped at 32 per channel, oldest evicted, de-duped by handle, pruned on close AND on each
  push. FILE: the serve map (6.5), streamed over BTXO with re-open-per-read (3.3 step 6b); a missing entry gets a
  zero-total BTXO header (named "unavailable", or the stored name) and an immediate terminator, which the
  follower's `chOnionRecvData` reads as "release not currently available" BEFORE its downgrade test, with an
  `onion n/a` row (built 2026-09-24; found statically 2026-09-23, when a plaintext follower saved a zero-byte file
  and logged success and an encrypted one raised the downgrade alarm). `chOnionPublishFile` refuses an empty file,
  so a real release never sends that shape. Verified statically; needs an OXT + live-Tor pass.
- **Push on change:** `chOnionPushFeed` writes a fresh BTXF frame to every subscriber: real-time, not the 60 s
  DHT tick.
- **Nonce discipline (M9):** every push RE-SEALS through `chFeedValue`, never a cached nonce and ciphertext,
  and `sxSecretBox` draws a fresh random nonce per call (sodiumxt's contract), so no keystream is reused. The KAT
  the design asked for (two seals of one value differ and each opens) is not in the tree yet.
- **Follow** (`chOnionFollowFetch`): not ready means a placeholder; dial the derived address (or `svc=`); send a
  BTXC FEED request on stream-ready; feed each BTXF value through the UNCHANGED `chReadFeed` (plaintext /
  `LOCKED` / `BADPASS`). Passphrase, BEP44 signature and empty-feed handling are unchanged; only the byte source
  moved. Never "try onion, then DHT" for an anon channel: the branch points are 6.7.

### 6.5 Anonymous file delivery

An anon release streams on demand over the onion, never as a torrent. Only item 2 of the `r=` feed line changes:
`magnet:?xt=urn:btih:...` for public releases, `onion:<relId>` for anon ones (items 3-4 stay `enc` and origName
when encrypted). `relId` is 16 hex characters from `sxRandomBytes(8)` (`chAllocRelId`); the `.onion` is never
embedded in the locator.

- **`chOnionPublishFile`** (the anon fork of `chPublishFile`): ONE file (a folder is refused), the size warning,
  encryption when the channel is private (temp registered first), an entry in the in-memory serve map
  `sOnionServe[pub:relId]`, then the UNCHANGED `chAddReleaseAndPublish`. No `btCreateTorrent`,
  `btAddTorrentFile`, `sMineHashes` or magnet is reachable.
- **Restart durability is prune-on-load** (`chPruneStrandedAnon`, D-12): the serve map is empty after a restart,
  so stranded `onion:` releases are dropped from the feed with a log rather than advertised un-serveably. A
  persisted `uOnionServe` is reserved for a product.
- **`chOnionDownload`:** refuse if not ready (no swarm fallback), dial, BTXC FILE request, the 3.3 receiver with
  `chSafeLeaf(origName)`, downgrade refusal and auto-decrypt.
- **`chDownloadSelected` forks on the locator:** `onion:` calls `chOnionDownload` and NEVER `btAddMagnet`.
  **`chCopySelectedMagnet`** gives the no-magnet message for an anon release instead of copying.

### 6.6 Composition with the passphrase

Anon hides WHO and WHERE (both IPs; no magnet and no DHT feed, so the follow graph and swarm membership never
appear). The passphrase hides WHAT, from the peer and at rest, **and authenticates the sender**, which plaintext
anon does not. `anon + pass` reuses every crypto handler untouched (`chFeedValue` / `chReadFeed`, `chFileKey` /
`chEncryptFile` / `chDecryptFile`) and only changes the transport; `chHelp` and the `chSetAnon` prompt recommend it.

### 6.7 The deanonymization guard - exact branch points

**An anon channel calls none of `btCreateTorrent` / `btAddTorrentFile` / `btAddMagnet` / `btDhtPutMutable` /
`btDhtGetMutable`, ever.** Enforced at (the code cites these numbers):

1. **`chPublishFile`, first line:** anon diverts to `chOnionPublishFile` and exits.
2. **`chPublishActiveFeed`, top:** anon calls `chOnionPushFeed` and returns 0, never `btDhtPutMutable`.
3. **`chChannelTick` publish loop:** anon channels skip the DHT put; their subscribers are pushed over Tor.
4. **`chChannelTick` follower loop, `chLoadFollows`, `chRefreshAll`, `chFollow`:** an anon follow uses
   `chOnionFollowFetch`, never `btDhtGetMutable` (which would publish the follow interest and the real IP).
5. **`chHandleEvent` `dhtMutableItem`:** DHT values for an anon follow are ignored; a stale artifact of the
   channel's public past must not overwrite the onion feed.
6. **`chSetAnon` turning ON:** the hard block of 6.2. Never warn-and-proceed.
7. **`chAddMagnetManual`:** intentionally UNAFFECTED, a manual, user-chosen clearnet download into the user's
   own folder, never a channel publish. Do not "fix" it.

**Quick drop** (`chPin` / `chFetchCode`, over `btDhtPutImmutable` / `btDhtGetImmutable`) is clearnet by design and
outside the invariant: it must stay visibly labelled public and never render under an anon badge (a guard of the
original 7.3 design). Found statically 2026-09-23 unlabelled; since 2026-09-24 its section title reads "Quick drop
(PUBLIC, not anonymous) - text goes on the open DHT from your IP; anyone with the code can read it", and the
`chPin` / `chFetchBtn` tooltips and the help text say the same. Its behaviour is unchanged; the labels need an OXT
re-pass.

The 6.5 download fork completes the set (the code cites it as "6.5 / 6.7 guard 3"). A silent mix, an anon feed
entry carrying a `magnet:` locator, is structurally impossible: `chOnionPublishFile` writes only `onion:<relId>`,
and `chPublishFile`'s clearnet body is unreachable for an anon channel.

### 6.8 Badges, follower status, and the offline channel

- **Badges:** `Name (anon)` in the menu, `[ANON: served over Tor ...]` in the now-publishing line, the `chTor`
  pill. **Onion rows** join the transfers table with the source `Onion` in teal (`0,150,150`) and states
  `onion up` / `onion down` / `onion done` / `onion error`; pruned in `chStop`.
- **The card is `Name | key | anon`** (the key is always item 2; names never contain `|`). `chCopyKey` appends
  `| anon`; `chFollow` parses the third field into `sFollowAnon`.
- **Stripped-tag hazard:** an old 2-field card or a stripped `| anon` makes the follower try the DHT first, a
  **one-time clearnet interest leak** before the onion retry; say so plainly. The mitigation: a public follow
  that never answers is probed over the onion (the `chDashOnce` watchdog), and an anon answer **promotes** the
  follow to anon (`chApplyAnonFeed`). A public-but-slow probe writes no offline placeholder.
- **An offline anon channel** (no DHT cache backs it) shows `(anonymous - Tor still connecting)` when local Tor
  is not ready, `(anonymous - offline)` when the dial fails or times out, and the real feed (or `LOCKED` /
  `BADPASS`) once a BTXF arrives; placeholders retry on the 60 s tick. No silent fallback to the swarm.

### 6.9 / 6.10 Where the code lives, and the as-built deltas

The plan's edit-point inventory is retired; the code is the record (the `chOnion*` / `chAnon*` families plus
`chVerifyOnionIdentity`, `chChannelOnionAddr`, `chIsAnonChannel`, `chSetAnon`, `chAllocRelId`,
`chPruneStrandedAnon`, `chSafeLeaf`; stack prop `uFollowAnon`). Pinned formats were followed exactly (BTXC/BTXF,
`onion:<relId>`, `svc=`, `chChannelOnionAddr`, the offline byte-compare, the 6.7 guards). Where the design left a
choice, or the shipped OnionXT ABI answered it, the build chose (each stated in its section): (1) OnionXT owns the
accept loop (3.4); (2) no writability gate (3.3 sender step 4); (3) the dialer speaks first, and QuickShare
auto-detects BTXO versus HTTP (3.3); (4) QuickShare folders are a plaintext `http://<onion>/` page, superseding the
design's refuse-with-message default, while Channels still refuses folders (5, 6.5); (5) QuickShare has one active
share and one active receiver (5); (6) Channels fans out by re-open-per-read (3.3 step 6b); (7) 32 subscribers per
channel (6.4); (8) prune-on-load (6.5); (9) the `svc=` line is built at serve time (6.1); (10) the three-field card
with promotion (6.8); (11) `chVerifyOnionIdentity` as the hard gate, needing SodiumXT ABI 7 (6.1).

## 7. Security model and honesty

Both demos run ONE `btStartSession` with DHT and LSD enabled and announce to a public tracker; every clearnet
leak traces to a payload reaching that session. The core rule: **anon content never enters the BitTorrent
session.**

### 7.1 Guarantees

"Peer" is the other person's app; "third party" is a swarm/DHT participant, tracker operator or on-path observer
who is not the peer; "GPA" is a global passive adversary watching both ends' guards.

| Property | QuickShare-anon | Channels-anon | Notes |
|---|---|---|---|
| Sender / publisher IP, from the peer | Hidden | Hidden | the peer sees only a `.onion` |
| Sender / publisher IP, from third parties | Hidden | Hidden | traffic never leaves Tor (7.2) |
| Receiver / follower IP, from the peer and third parties | Hidden | Hidden | the receiver dials out through Tor |
| File bytes in transit | Hidden | Hidden | layer-encrypted circuit end to end |
| File bytes, from the receiving peer / at rest | Exposed unless SodiumXT | Exposed unless SodiumXT | the `.enc` opens only under the passphrase |
| Real filename / release title | Hidden from third parties | Hidden from third parties | rides inside the stream / feed |
| Feed contents and subscription graph | n/a | Hidden from third parties | served and fetched over the onion only |
| **Sender authenticity, plaintext** | **NOT provided** | **NOT provided** | a swapped code or card redirects to an impostor |
| **Sender authenticity, with passphrase** | **Provided** | **Provided (+ BEP44 on the feed)** | secretstream authenticates under the shared key |
| That you use Tor | Not hidden | Not hidden | your ISP / guard sees a Tor connection |
| Timing, volume, burst shape | Not hidden | Not hidden | a GPA can correlate (7.6) |
| The app's DHT presence | Not hidden | Not hidden | the host is still a DHT node |
| Channel online-presence | n/a | **Leaks a coarse oracle** | the stable `.onion` shows "reachable now" (7.6) |

### 7.2 Why onion-to-onion (Model A rejected)

**Model A, torrent-over-Tor through a SOCKS exit, was rejected:** UDP DHT/uTP cannot ride Tor (OnionXT is TCP
streams and onion services only) and would leak around the proxy, so there is no honest "anonymous DHT"; a hostile
exit can log, tamper or inject, and trackers embed the announced IP; and mixing anonymized and non-proxied
announces for one info-hash deanonymizes instantly. **Model C, onion-to-onion, never touches an exit and never
leaves Tor**: no exit to trust, no clearnet destination, no UDP to leak.

### 7.3 The mixing trap and the guards

**The trap:** the same payload over the onion AND on the swarm lets a third party correlate the content with the
info-hash and read the real IP off the DHT or tracker. So anon and clearnet are mutually exclusive per payload,
enforced at branch points rather than requested of the user. **As built:** QuickShare's anon branch returns
before any torrent call, and a `BTXTOR1:` code only ever reaches `oxDial`; LSD announces only torrents, so it
cannot leak an anon file. Channels enforces the seven 6.7 branch points; its Quick drop stays outside them,
labelled public (6.7). Channels also refuses to flip anon either way while releases of the other kind are listed
(the original design's guard 5): ON while a magnet release exists (6.2), and, since 2026-09-24, OFF while an
`onion:` release exists, because `chSetAnon` OFF re-announces the whole feed on the DHT and would have made the
anon releases' titles DHT-visible (plaintext unless the channel has a passphrase). Both offer one-click removal;
the OFF half is verified statically; needs an OXT + live-Tor pass (#31).

**Designed but not built** (found statically 2026-09-23; open):

- QuickShare: re-dropping a file already shared anonymously, with the toggle off, seeds it publicly with no
  confirmation. The design asked for an explicit "yes, also seed this publicly" that visibly drops the badge.

### 7.4 Composing with SodiumXT

**Tor alone:** both IPs hidden, bytes encrypted in transit; the peer gets plaintext, plaintext lands on both
disks, and the sender is not authenticated. **SodiumXT alone** (the clearnet encrypted mode): contents secret;
the info-hash and both IPs public. **Both (recommended):** IPs hidden, contents secret, sender authenticated;
residual GPA correlation, Tor-use visibility, the presence oracle (7.6) and trust in the local daemon (7.5).

### 7.5 Trust boundary: the local tor daemon

OnionXT speaks SOCKS5 on `127.0.0.1:9050` / `9150` and control on `9051` / `9151`. **The local tor is inside the
trust boundary:** it sees every `.onion` you dial, holds and serves your onion-service keys, and if compromised
can impersonate your service or deanonymize you. It does NOT see plaintext when a passphrase is layered on.
Loopback only, always.

### 7.6 Metadata and timing a global observer can still use

- **Correlation:** fixed 64 KiB slices at one frame per tick make a distinctive flow (a total near the plaintext
  size plus a small constant, a start, a duration, a steady cadence). Onion services are not designed to resist a
  GPA. **Padding or jitter is neither built nor claimed**; it would raise the cost, not defeat a GPA.
- **Descriptor timing:** publishing announces reachability; anyone holding an address can watch the HSDirs for
  when it is online. QuickShare's fresh random onion per share avoids a persistent oracle; Channels' stable
  address trades that back for findability, and says so. Steering large media to the swarm re-introduces the IP
  leak, so that steer always carries its caveat and is never auto-applied (D-11).

### 7.7 Positioning and the honesty convention

Public BitTorrent/DHT stays the default; anon is explicit and off by default. QuickShare-anon is "hand a sensitive
document directly to one colleague without exposing either IP, the contents, or an info-hash"; Channels-anon is "a
small, trusted, signed feed whose publisher's IP is not on the DHT". **Never market it as "untraceable"**: the
GPA, Tor-use, presence-oracle, plaintext-not-authenticated and local-tor caveats sit in plain language next to the
toggle. **The badge never outruns the transport:** if a guard cannot confirm the invariant for a payload, the
"anonymous" label does not appear. Every anonymity claim stays labelled "verified statically; needs an OXT +
live-Tor pass" until a dated two-machine record exists.

### 7.8 Adversary tiers

"Defeated" means by design, assuming the invariants hold, until the two-machine pass observes each refusal.
"Passphrase" means the SodiumXT layer (Argon2id key, `crypto_secretstream` file, the sealed verifier).

| Adversary | Tries to | Model C gives you | They still get |
|---|---|---|---|
| **Wire observer** (ISP, LAN operator, anyone on-path near an end) | read or log traffic; learn who talks to whom | defeated for content and endpoints: an encrypted connection into Tor | THAT you use Tor, when, and roughly how much |
| **Malicious peer** (the other end) | learn your IP; feed you a substituted file | your IP: defeated. Substitution: defeated ONLY with a passphrase (the verifier binds the code to the key, per-chunk authentication, the downgrade refusal) | on plaintext, everything but your IP; an intercepted code can be answered by an impostor |
| **Malicious relay or exit** | tamper at an exit; correlate at a relay | exits are structurally irrelevant onion-to-onion; a relay sees layer-encrypted cells | one hop's timing and volume; a hostile guard knows you use Tor |
| **Third-party network participant** (DHT nodes, trackers, swarm peers) | enumerate who shares what | defeated for the anon payload: no torrent, info-hash, DHT entry or announce | the HOST is still a visible DHT node |
| **Global passive adversary** | correlate a send with a receive by shape | **OUT OF SCOPE, not defeated** | start, duration, byte count and the one-frame-per-tick cadence make a matchable flow |

The residual risk users most often get wrong: **plaintext does not authenticate** - an "anonymous" plaintext
transfer hides the route and nothing else about the sender. And where using Tor is itself the risk, Model C does
not help.

## 9. API surface

- **9.1 Zero changes to any compiled extension.** TorrentXT is untouched (no `btx_*` symbol added). OnionXT is
  used as shipped (`onionxt/docs/05-api-reference.md`): `oxVersion`, the port setters, `oxConnectControl` /
  `oxDisconnectControl`, the status / peer / stream callback setters, `oxBootstrapProgress` / `oxIsReady` /
  `oxIsControlAuthenticated`, `oxDial` / `oxWrite` / `oxCloseStream`, `oxCreateServiceFromSeed` /
  `oxRemoveService` / `oxServiceAddress`, and the address helpers `oxAddressFromPublicKey` /
  `oxPublicKeyFromAddress` / `oxIsValidAddress`. SodiumXT is the existing path (`sxEncryptFile` /
  `sxDecryptFile`, `sxPwHash`, `sxSecretBox` / `sxSecretBoxOpen`, `sxSignKeypairFromSeed`, `sxRandomBytes`,
  `sxHex2Bin`).
- **9.2 Packaging.** A standalone needs the SodiumXT and TorrentXT packaged extensions plus the onionxt SCRIPT
  library (`org.openxtalk.library.onion` is the id it goes by, not an installable package; OnionXT has no native
  library). A packaged app is **not anon-capable out of the box**: no tor is bundled (D-07). The probe must report
  "needs SodiumXT" distinctly from "no Tor". A packaged `.exe` / `.app` passing the single-machine probe on a
  clean machine has not been recorded.
- **9.3 Dependencies.** OnionXT needs SodiumXT even for plaintext: ABI >= 6 (`sxSignSeedToExpandedKey`,
  SAFECOOKIE through `sxHmacSha256`) and ABI 7 (`sxSha3_256`, for Channels' offline identity check).
  `torrent-quickshare` does not embed onionxt (its own `socketError` / `socketClosed` / `socketTimeout` bodies
  would collide; `NOT_EMBEDDED` in `tools/sync-demo-embeds.py`), so Tor there needs `start using`;
  `torrent-dht-channels` carries onionxt embedded.
- **9.4 Non-goals:** `btx_connect_peer(session, "onion:<addr>")` onion torrents (needs UDP over Tor, which
  OnionXT cannot do); a native onion-aware webseed or fan-out; an `oxWriteFile` / `oxSendFile` C-side splice
  (files ride BTXO over `oxWrite`, and the bounded script pump keeps the ceiling honest).

## 10. Phase status

A phase closes on its observed on-engine gate, never on the static gates.

| Phase | Built | Gate | Status |
|---|---|---|---|
| 0 - probe and plumbing | QuickShare with Phase 1; Channels 2026-08-15 (the `chTor` pill and `chAnon` "Anonymous..." button, in the stack's own builder rather than the ui-kit block, inside the unchanged 1180x640 window) | one machine with tor: ON reaches ready and brings up a service; OFF leaves clearnet unchanged; tor absent fails closed; the offline byte-compare passes | pending: QuickShare in runbook row 5 (S2); Channels is #31 |
| 1 - QuickShare send/receive | 2026-08-15 | the 12.4 two-machine gate | pending: runbook row 5 (S4) |
| 2 - Channels feed over the onion | 2026-08-15 | #32 | pending (S4) |
| 3 - Channels file delivery | 2026-08-15 | #33 | pending (S4) |
| 4 - docs, threat model, onboarding | written 2026-08-15; merged here 2026-09-23 | a FRESH USER on each of macOS, Windows and Linux, following only section 13, completes a two-machine anon transfer | pending: **writing the pages is not passing the gate** |

## 11. Design decisions settled in the plan

One service per QuickShare session and one per anon channel (3.4); Channels anon is whole-channel, default off
(6.2); the QuickShare key is ephemeral (3.4); QuickShare one active receiver, Channels re-open-per-read (3.3); if the
seed / onion-pubkey equivalence ever fails, `svc=` is the source of truth (6.1). The rest became section 14 or 9.2.

## 12. Testing and verification

Static gate first, KATs second; the two-machine human pass is the proof. **12.1:** torrentxt's
`tools/run-gates.sh` runs the unified checker over both demos and every `tests/*golden*.py`; the Channels boot
self-check asserts the identity byte-compare passed at start.

### 12.2 The normative frame table and the KATs

All framing integers are big-endian; a length beyond its cap is **rejected before allocation**, from the length
field alone.

| Element | Bytes |
|---|---|
| file header (once) | `"BTXO"` (4), version u8 = `0x01`, flags u8 (bit0 `kFlagEnc`, bits 1-7 zero), `nameLen` u16 (`"n"`), name (UTF-8), `totalLen` u64 as hi:u32 then lo:u32 (`"NN"`) |
| data frame | `len` u32 (`"N"`; `1 <= len <= kOnionChunk`, enforced on BOTH sides), then the bytes |
| terminator | `len` u32 = 0 (`00 00 00 00`) |
| channels request | `"BTXC"` (4), ver u8, verb u8 (1 = FEED, 2 = FILE), keyLen u16 (`"n"`), key, idLen u16 (`"n"`), id (the relId; empty for FEED) |
| channels feed frame | `"BTXF"` (4), ver u8, valLen u32 (`"N"`, <= `kOnionFeedCap`), value |

**Pinned in `torrentxt/tests/onion_frame_golden.py`:** the header round trip and hex; the encrypted flag with a
total above 4 GiB; full-stream reassembly of a multi-frame payload (fed whole); the empty file; the
oversized-frame rejection; both `BTXTOR1` layouts; `qsSafeLeaf` against traversal and injection shapes; BTXC and
BTXF byte for byte, with incremental arrival, cap boundaries and version / magic refusals; `chSafeLeaf` on its own
rows and in agreement with `qsSafeLeaf`. **Asked for and not pinned yet:** BTXO split-buffer reassembly (the
header and a data frame each cut across two reads; the design called it critical), a truncated `BTXTOR1:` code
refused cleanly, the `nameLen` / `totalLen` cap rejections as golden rows, `qsKeyOpensVerifier` refusing a wrong
passphrase, and nonce freshness (M9).

### 12.3 The on-engine VERIFY register

Tick results HERE, by `#`, with the date, platform and what ran (runbook rows 5 and 21 point here).

| # | Question | Status |
|---|---|---|
| #22 | the whole `ox*` ABI | CLOSED 2026-09-23: the in-tree `onionxt/`, engine-passed against a live daemon |
| #6 | `oxDial` sync or async, and its success test | CLOSED 2026-09-23: an integer handle through `the result` at once, async completion; failure is an `"OnionXT: ..."` string |
| #23 | what `oxIsReady()` means | CLOSED 2026-09-23: bootstrap 100 + control authenticated; the descriptor is `serviceReady` |
| #24 | a writable / backpressure callback | CLOSED 2026-09-23: none exists; the 15 ms tick shipped; slow-circuit behaviour rides #28 |
| #25 | the inbound accept model | CLOSED 2026-09-23: OnionXT owns the listener (3.4) |
| cookie auth | how `oxConnectControl` authenticates | CLOSED 2026-09-23: SAFECOOKIE, proven on a live daemon (onionxt) |
| #26 | the SodiumXT dependency and floor | CLOSED 2026-09-23: required even for plaintext; ABI >= 6, ABI 7 for offline checksums |
| codec KATs | the address codec on known onions | CLOSED 2026-08-12: engine-green, `oxSelfTest()` 43/43, Windows x64, SodiumXT ABI 7 |
| #27 offline | one seed, one ed25519 key in libtorrent and libsodium | CLOSED: engine-green in the suite paste's CROSS section 2026-08-08; native in CI since 2026-08-17 (1.1) |
| #30 | the pill / toggle rects do not overlap the header controls | OPEN, rides runbook row 37 (the demo re-open fleet): record it when `torrent-quickshare` is re-opened. The `qsTorPill` rect (`430,8,612,32`) is unchanged; the kit-v2 restyle moved the toggle and tagline; `check-stack-size.py` checks the window size only |
| #17 | backward compatibility: a pre-Model-C QuickShare rejects a `BTXTOR1:` code cleanly (5.2); an old saved Channels stack defaults `uFollowAnon` empty (6.2, built) | OPEN for the QuickShare half: static, answerable from the pre-2026-08-15 `qsGetFile` in git history |
| #27 live | `oxServiceAddress == chChannelOnionAddr(pub)` on a real service | OPEN: rides #32; settles D-04 |
| concurrent services | N services live at once; a second service on the same local port refused | OPEN |
| #28 | throughput in MB/s on two machines | OPEN: quote no number until measured |
| #31 | Channels single machine (S2): Anonymous ON drives `chTor` to "Tor: ready" and brings up the service; OFF is refused while an `onion:` release is listed (removal offered; built 2026-09-24) and otherwise leaves every clearnet channel bit-for-bit unchanged; tor absent shows the fail-closed messages and public channels are untouched; `chVerifyOnionIdentity` passes offline; the pill and `chAnon` fit the unchanged 1180x640 window | OPEN |
| #32 | Channels feed (S4): A publishes an anon channel; B follows by the CARD only and pulls the signed feed over the onion with the DHT OFF for that channel; releases list; the BEP44 signature verifies; the live `oxServiceAddress == chChannelOnionAddr(pub)` compare holds (else `svc=` is the source of truth and the derivability claim drops); an old 2-field card recovers through the `chDashOnce` onion retry | OPEN |
| #33 | Channels files (S4): B downloads a release entirely over the onion (swarm and DHT off), sha256-identical; an encrypted release auto-decrypts; the row shows the teal `Onion` source; a capture shows ZERO swarm/DHT traffic for that file on both ends; a publisher restart prunes stranded relIds (`chPruneStrandedAnon`), and a follower asking for a relId the publisher no longer serves sees "not currently available" (built 2026-09-24), not a zero-byte file or a downgrade alarm | OPEN |

### 12.4 The Phase 1 gate - the two-machine pass

Two tor-ready machines (runbook row 5, S4). A anon-shares a file; B pastes the `BTXTOR1:` code and gets it
**byte-identical (sha256)**. On both hosts `ss -tunp` shows the only peer is `127.0.0.1:9050` / `9051` (or
`9150` / `9151`), with **no DHT or uTP**. Repeat with a passphrase: a wrong one is refused up front, the file
decrypts to its real name, and a plaintext-header downgrade is refused. Path-traversal names land in the save
folder. With the toggle off or tor absent, clearnet is untouched. Every section 10 gate runs the same way (sha256,
a capture, the refusals, the toggle-off / tor-absent check). Report "verified on OXT, two machines" - never a
runtime claim observed only statically.

## 13. Onboarding - from nothing to an anonymous transfer

**A completed walkthrough on real hardware IS runbook row 5; a fresh user failing it is a Phase 4 finding, not a
user error.** You need **two machines, not two windows** (torrentxt allows one session per process, and a
one-machine two-party test proves much less), each with OpenXTalk, a local tor and three suite members. **Mobile is
unsupported:** the toggle stays disabled and every public feature still works.

### 13.1 Step 1 - a tor daemon, per platform

**tor opens SOCKS by default but NOT a control port unless asked**, and the demos need both. The suite ships no
tor (D-07). The goal is three `torrc` lines (or `tor --ControlPort 9051 --CookieAuthentication 1`):

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

After restarting tor, confirm the proof line `[notice] Opening Control listener on 127.0.0.1:9051` in its log.

- **Linux:** `sudo apt install tor`; add the lines to `/etc/tor/torrc`; `sudo systemctl restart tor`. Cookie auth
  means the app's user must read tor's cookie file: on Debian/Ubuntu add the user to `debian-tor` and log in again.
- **macOS:** `brew install tor`, then `brew services start tor`; the torrc is `/opt/homebrew/etc/tor/torrc`
  (Intel: `/usr/local/etc/tor/torrc`).
- **Windows:** the Tor Expert Bundle (a bare `tor.exe`) with the torrc at `%APPDATA%\tor\torrc`; leave it running.
- **Tor Browser:** the demos probe its pair (9150 / 9151), but **Tor Browser exposes no control port by default**
  (runbook trap 5.3). Prefer the daemon.

### 13.2 Step 2 - the extensions, and how the demo detects readiness

1. **sodiumxt** (`org.openxtalk.library.sodium`) through `Tools > Extension Manager`; required even for a
   plaintext anon transfer, because OnionXT builds onion identities on it.
2. **torrentxt** (`org.openxtalk.library.torrent`) the same way.
3. **onionxt** is NOT a packaged extension; it is pure LiveCodeScript. For QuickShare, open
   `onionxt/src/onionxt.livecodescript` as a stack and `start using` it (`onionxt/docs/10-usage-guide.md`);
   `torrent-dht-channels` carries it embedded.

Check from the message box: `put sxVersion()`, `put oxVersion()`, `put btStartSession()` (above 0; then
`btStopSession` it: a leftover session is runbook trap 5.1). Restart OXT before each torrent-bearing paste (trap
5.1.1). Readiness, each stage gating the next: OnionXT loads, SodiumXT works, control authenticates (9051, then
9151), bootstrap reaches 100, and for a sender the descriptor uploads within 90 s. Short of the stage an action
needs, it fails closed: aborts, never downgrades, never queues.

### 13.3 Fail-closed states and troubleshooting

What QuickShare shows (Channels has its own equivalents). Every row fails closed: the public features keep
working, and nothing marked anonymous is ever quietly sent over the public swarm.

| What the user sees | Likely cause | Fix |
|---|---|---|
| pill `Tor: no extension` or `Tor: needs SodiumXT`, toggle disabled; a pasted `BTXTOR1:` code refused with an install hint | 13.2 incomplete on this machine (SodiumXT missing reads distinctly from "no Tor") | install sodiumxt; `start using` onionxt |
| pill `Tor: no daemon`; log "No Tor control port answered on 127.0.0.1:9051 or 9151 (reason) - start Tor (or Tor Browser) and reopen this stack to use the private-send features." | no tor running, tor with the control port off (the stock default), or relying on Tor Browser | 13.1: add `ControlPort 9051` + `CookieAuthentication 1`, restart tor, look for the "Opening Control listener" line, reopen the stack |
| `Tor: no daemon` although tor runs with `ControlPort 9051` | authentication failing, commonly the app cannot read tor's cookie file | Linux: add the user to `debian-tor` and log in again; check the torrc says `CookieAuthentication 1` |
| `Tor: not on this device` on a phone or tablet | mobile is unsupported (3.2; this state was "no daemon" until 2026-09-24) | use a desktop |
| `Tor: no daemon` with a custom ControlPort in the torrc | the demos probe exactly 9051, then 9151 | move tor to the standard pair |
| `Tor: connecting NN%` and "Tor is still connecting - watch the pill, then drop the file again." | bootstrap incomplete: a firewall, a captive portal, a network that blocks Tor | fix the network; watch tor's log. The action is refused now and retried by you; nothing is queued or sent on clearnet |
| "Tor could not publish the private address in time. Make sure the pill says 'ready', then try again." (after 90 s) | the descriptor did not upload (weak connectivity; clock skew is a classic culprit) | check the clock, let tor settle, drop the file again; the half-built service was cleaned up |
| B: "The sender went offline before the transfer finished. Try the code again." | A closed the window, A re-dropped a file (a new code replaces the old), B's circuit is not built yet, or a side went offline mid-transfer (a failed dial arrives as an async stream error; its text is not shown) | A re-shares, keeps the window open and sends the NEW code; B retries after a moment; anon transfers restart from byte 0 |
| B: "The private (Tor) download stalled - closing it. Try the code again." | a stalled circuit (the idle watchdog fired) | retry from the code |
| B: "Not enough free disk space for this transfer: it needs about ..." | the free-disk pre-check (3.3): the file, or twice it when encrypted, does not fit on the temp or save disk | free space and retry the code; nothing was downloaded |
| "This share was supposed to be encrypted but arrived unencrypted - do not trust it." | the downgrade refusal: the code promised encryption, the stream claimed plaintext | do not trust the file; re-share; if it recurs, treat the path between you as hostile |
| the link to tor fails although the network is fine | a local firewall filtering loopback | allow OXT and tor on localhost 9050 / 9051 (9150 / 9151) |

### 13.4 Step 3 - the transfer, machine A to machine B

On BOTH machines paste `torrentxt/examples/torrent-quickshare.livecodescript` into the STACK script of a new
one-card stack, then close and reopen it (runbook trap 5.2). Wait for `Tor: ready` on both.

1. **A:** type a passphrase (recommended: without one the sender is not verified and the bytes arrive plaintext).
2. **A:** tick **"Send privately over Tor"** and drop a file. After up to a minute of "Publishing a private Tor
   address..." a code beginning `BTXTOR1:` appears.
3. **A:** send the code to B over any channel and the passphrase over a DIFFERENT one. **Keep A's window open**
   (runbook trap 5.4).
4. **B:** paste the code, type the passphrase, click Download. A wrong passphrase is refused at once, before any
   network traffic: that is the verifier working. A plaintext code shows a "sender is NOT verified" confirmation
   that must be accepted explicitly.
5. Both lists show a "via Tor" row; B's file lands under its real name. **Run `sha256sum` on both machines:
   byte-identical delivery is the pass criterion.** (A dropped FOLDER becomes a plaintext `http://<onion>/` page.)

## 14. Owner decisions

Numbered as [OPEN-DECISIONS.md](OPEN-DECISIONS.md) cites them ("decision 14.3").

1. **Tor delivery - DECIDED 2026-08-27 (D-07):** document-install, indefinitely; bundling a tor binary is
   revisited only for a product aimed at a non-technical audience.
2. **Large-file policy - RATIFIED 2026-08-27 (D-11):** warn at 256 MiB; steer to clearnet only with the explicit
   IP caveat; NEVER auto-downgrade.
3. **Which `.onion`-derivability wording ships - OPEN (D-04).** Until the live half of #27 passes (it rides #32),
   no suite document or UI publishes the strong claim "your channel card alone is the anon locator"; the `svc=`
   line is the shipped fallback. Passes: the strong wording ships. Fails: the `svc=` wording ships and the claim
   drops. Recommendation: pre-approve both now, so the S4 run flips a label instead of waiting on copy.
   **Finding, 2026-09-23:** Channels' in-app copy is ahead of this decision: the `chAnon` tooltip, the help text
   and the `chSetAnon` dialog all say the channel is "reachable from the channel card alone".
4. **Positioning and threat-model copy - SIGNED OFF 2026-08-27 (D-05):** ships as written (IP hiding and payload
   privacy claimed; Tor-use visibility and timing/volume disclaimed; the unproven legs carry honesty labels).
5. **Channels serve-map durability - RATIFIED 2026-08-27 (D-12):** prune stranded relIds on restart for the
   demos; persist `uOnionServe` only for a product, where its on-disk footprint can be stated.
