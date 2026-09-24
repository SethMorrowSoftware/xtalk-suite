# CLAUDE.md - OnionXT

Guidance for Claude Code in the OnionXT member of the xtalk-suite monorepo. The numbered docs say WHAT
OnionXT is (docs/02-03 the wire protocols byte for byte, docs/04 the address-is-a-key idea, docs/05 the
API); this file holds the rules, gotchas, as-built decisions and engine evidence. Family-wide engine
behaviour is the suite's `docs/OXT-ENGINE-NOTES.md`, cited below as "engine note N.N".

## What this is

**OnionXT** is a Tor transport and rendezvous layer for OpenXTalk (OXT): dial any TCP endpoint
anonymously through Tor's SOCKS5 proxy, and create and reach **v3 onion services**, whose address is an
ed25519 public key (serverless, self-authenticating, IP-anonymous rendezvous). It talks to a **locally
running tor daemon** (SOCKS `127.0.0.1:9050`, control `127.0.0.1:9051`; Tor Browser is SOCKS `9150` with
no control port by default) and does not embed, reimplement or by default ship Tor.

- **Pure LiveCodeScript.** `open socket`, `read from socket`, `write to socket` and `accept connections`
  are engine COMMANDS, not LCB calls. A native helper comes only after an engine pass shows script too
  slow; none has been needed.
- **Unlike SodiumXT**, OnionXT owns long-lived network state (streams, a control connection, published
  services, an accept loop) and is asynchronous and event-driven: TorrentXT's never-block discipline.
- **Unlike TorrentXT**, it wraps no C engine, so there is normally no FFI line to firewall.
- **A transport, not a protocol.** The app (or a protocol above the `oxTransport*` seam) owns the payload
  and its encryption; all crypto is composed from SodiumXT (`sx*`).

```
src/onionxt.livecodescript      the library, public ox* (SOCKS5, control port, services, seam)
src/onion-httpd.livecodescript  HTTP hosting over the accept loop, public oxh*
examples/                       onionxt-demo, onionxt-tests (offline oxSelfTest), onion-httpd/,
                                socks-dial/, onion-roundtrip/
docs/                           01-08 and 10; file names and numbers are cited, keep them
tools/                          run-gates.sh and the four gates it runs
templates/CLAUDE.md             the portable family template, byte-identical with coinxt's copy
```

## Rules

Rules 1-5 are cited by number from the source, the tests, `tools/onion-kat.py` and the docs.

1. **Add no cryptography. Compose SodiumXT (ABI >= 6).** ed25519 identity, the onion-key expansion
   (`sxSignSeedToExpandedKey`), SAFECOOKIE HMAC (`sxHmacSha256`) and every protected payload byte are
   `sx*` calls. A missing primitive is an upstream SodiumXT feature landed first (its own ABI bump and
   tests), never a hand-rolled hash here: SHA3-256 shipped that way (ABI 7, `sxSha3_256`, 2026-08-11).
2. **Trust the onion address, verify the daemon, distrust the network.** A v3 address IS the ed25519
   key (docs/04): pin it as the contact's identity. The local tor daemon is TRUSTED (it sees SOCKS
   targets and any key it generates); say so loudly. The network beyond Tor is untrusted.
3. **Never leak the payload or the target outside Tor.** ATYP=3 for every target so Tor resolves it;
   never a local DNS lookup; never a direct socket to a peer "to save a hop".
4. **Fail closed on every wire error.** A non-zero REP, a control `5xx`, a short read or a closed
   socket returns a clean error and tears the resource down; never fall back to an unproxied or
   unauthenticated path.
5. **Own the lifecycle.** Every socket, `ADD_ONION` and listener has an idempotent close / `DEL_ONION` /
   `close socket`. OXT has no unload hook, so the app frees what it opens (on `closeStack`).
6. **Honesty.** OXT cannot compile `.livecodescript` headlessly: anything not seen on an engine is
   "verified statically; needs an OXT pass + a live-Tor pass". A handshake works only once it has shaken
   hands with a real tor. Never present Tor as total anonymity (docs/01).
7. **House style.** No em/en dashes or curly quotes in any `.md` (`tools/check-docs-style.py`); ASCII
   only in `.lcb` / `.livecodescript`, comments and strings included (curly quotes fail OXT
   compilation). Comment the why, densely.
8. **The library is carried.** `src/onionxt.livecodescript` is embedded verbatim in the suite paste
   (`python3 tools/build-suite-selftest.py`) and in every stack `tools/sync-demo-embeds.py` registers
   (the README's generated section lists all eight). An edit needs both regenerations and is not done
   until every carrier has been re-run on an engine.
9. **Done means.** A script change: `bash tools/run-gates.sh` passes and it has had (or is flagged as
   needing) an engine pass against a real tor. A transport change: a two-instance onion round trip works
   on an engine. Per-task branch, draft PR, no push to `main` without permission.

## The asynchronous, event-driven model

- **Never block the interpreter thread on the network.** Script, rendering and FFI share ONE thread.
  Every protocol is a state machine driven by `open socket` / `read from socket` / `accept connections`
  `... with message`; no busy-wait, no `wait ... with messages` loop where a callback would do.
- **Keep status updates at <= ~4 Hz** (`kOxStatusThrottle` = 250 ms): coalesce event floods.
- **Bootstrapping is slow and user-visible.** A cold tor takes tens of seconds, a descriptor seconds
  more: surface `STATUS_CLIENT` / `GETINFO status/bootstrap-phase` and `HS_DESC` progress.

## Handles and long-lived state

State lives in script-local tables keyed by a small integer handle or the engine's socket id. A stale
id is a clean no-op or error, never a crash. Idempotent frees: `oxCloseStream`, `oxRemoveService`,
`oxDisconnectControl`, `oxShutdown`. If state ever moves into C, use a generation-tagged handle table as
SodiumXT does, never a raw pointer.

## Socket and engine I/O gotchas ("socket gotcha N"; 1-4 and 8 are engine-confirmed)

1. **Binary, not text.** `numToByte` / `binaryEncode` to build, `byteToNum` / `binaryDecode` to parse,
   `byte x to y of` to index; never `char` / `line` / `word` on socket data.
2. **A `read ... for N` without `with message` blocks the one thread.** Use callback reads.
3. **Reads return short; frame by length.** Control lines are CRLF: `250-` continues, `250 ` is final.
4. **`open socket` is asynchronous**; a failure arrives as a `socketError` message, not a throw.
5. **Inbound needs the loopback listener first**: `accept connections on port <local> with message ...`
   running before (or with) `ADD_ONION ... Port=<virt>,127.0.0.1:<local>`.
6. **Loopback only, always.** SOCKS, control and the forward target are `127.0.0.1`; ports configurable.
7. **Timeouts are mandatory.** A bootstrapping tor accepts TCP and then stalls; bound every handshake
   (`socketTimeout` repeats while a read is pending: engine note 6.1).
8. **`socketError`, closed peers and half-open states are normal paths**; every `open` / `accept` gets
   an error handler and a matching `close`.

## LiveCodeScript / OXT gotchas (cited as "gotcha N")

1. No curly quotes anywhere, even in a comment (engine note 1.4).
2. **Prefixed-token shadow**: `tExt` IS `text`, `tOp` IS `top` (engine note 1.5); use `tSender`,
   `tReplyOp`.
3. Prefixes `t`/`p`/`s`/`k`; public `oxPascalCase`; a C ABI `onx_snake_case` (`oxt_` reads as "OXT").
4. Constants are literal and declared before first use (engine note 1.3).
5. LCB only: `unsafe` around every foreign call, declarations at handler top.
6. Commands report via `the result`; functions return a value.
7. **`itemDelimiter` / `lineDelimiter` are global mutable state** (engine note 2.3): set
   `the lineDelimiter to crlf` where the control protocol is parsed, and restore it.
8. `is a` accepts only number / integer / boolean / point / rect / date / color.
9. A script compiles as a unit: an error at an unrelated line means a compile error elsewhere.
10. **Socket ids are the engine's**: store and reuse them verbatim; never rebuild one (engine note 6.2).
11. `bitAnd` / `bitOr` / `bitXor` are operators, not functions.
12. `^`, `div` and `mod` inside a compound expression are rejected by some OXT parsers ("double binary
    operator"), which is why base32 routes through `oxIntDiv` / `oxIntMod` / `oxPow2`.
13. `binaryDecode` fills an out variable and returns a count.
14. `accept connections on port N with message "name"` needs `port` and a quoted message name.
15. Private handlers are unreachable through `with message`, `send` or `dispatch`: callbacks are public.

## Protocol traps (docs/02 and docs/03 are the specs)

- CONNECT uses ATYP `03` with the full `<56>.onion`; the port is built by hand, big-endian
  (`numToByte(p div 256) & numToByte(p mod 256)`), because `binaryEncode "S"` is host order.
- REP `0xF0`-`0xF7` appear only with `ExtendedErrors` on the SocksPort; map `0x01` / `0x04` too.
- `PROTOCOLINFO 1` before auth; SAFECOOKIE > COOKIE > NULL > HASHEDPASSWORD. The `AUTHCHALLENGE` reply
  is ONE final `250 ` line: a parser waiting for a later `250 OK` hangs.
- `ADD_ONION ED25519-V3:` takes the 64-byte EXPANDED key in standard padded base64 (`base64Encode`), not
  `sxBin2Base64`. `Flags=Detach` by default. `650` events are demuxed by status code.

## Bring-up traps (each cost an engine round)

- **Empty response after a reconnect**: an ephemeral service dies with its control connection while
  its descriptor lingers ~3 h ("Unable to find any hidden service associated identity key"). Fix:
  `Flags=Detach` by default; teardown still `DEL_ONION`s.
- **An onion forwarding to a dead port**: `accept connections` reports a bind failure ONLY in `the
  result` (Windows 10013 from Hyper-V / WSL2 / Docker reserved ranges, 10048 in use). Fix:
  `oxStartService` fails closed; change the local port, keep virtual port 80.
- **A dead tunnel reported as sent**: `write to socket` sets `the result` on failure, and `oxWrite`
  discarded it until 2026-09-09 (93 call sites and nocloud's onion send pump never saw a failure). Now
  captured on the next line; verified statically, needs an OXT pass.
- **A bootstrap bar stuck at 0**: `STATUS_CLIENT BOOTSTRAP` fires only WHILE bootstrapping. Fix: query
  `GETINFO status/bootstrap-phase` once on connect.
- **Control refused (10061)**: tor opens no control port unless asked; Tor Browser exposes none.
- **Callbacks are DELAYED handlers** with no defaultStack guarantee (engine note 5.3). Pin at the entry
  (`set the defaultStack to the short name of this stack`); the suite's `tools/check-timer-stack-pin.py`
  holds it (its 2026-09-09 widening found 6 unpinned chains here, 18 in stacks carrying OnionXT).
- **Swallowing a socket message is a HANG**: `socketError` / `socketClosed` / `socketTimeout` are the
  engine's names, so a stack defining one must `pass` sockets that are not its own (docs/10 section 2).
  OnionXT's own three pass foreign sockets since 2026-08-23 (held by the suite's
  `tools/check-cross-library-names.py`); since 2026-08-24 their logic is `oxSocketError` /
  `oxSocketClosed` / `oxSocketTimeout` ("true" when consumed, "false" if foreign) and
  `tools/sync-demo-embeds.py` drops the thin `on socket*` wrappers per (app, library) pair.
- **The self-test runs inside the demo**: `testConfigurationSetters` restores the dispatch setters to
  the demo's own (owner `me`, status `onStatus`, no peer callback); ports reset and live state is torn
  down (runbook trap 5.6).

## FFI / C-ABI conventions (only if a shim is ever added)

Prefix `onx_`. Bytes cross as `Pointer` + `CInt` length (LCB `Data` does not auto-bridge; the
`MCMemoryAllocate` size is `UIntSize`); no 64-bit foreign int (decimal `ZStringUTF8`); never RETURN a
bridged C string; null only via `optional Pointer`; never rename an export; ABI bump + `checkABI()`
throwing "reinstall"; gcc ASan + UBSan, headers `-isystem`, binary + `MANIFEST.sha256` in one change.

## As-built notes: design decisions

- **A handle plus a callback.** `oxDial` / `oxCreateService` / `oxCreateServiceFromSeed` return an
  integer handle through `the result` (or an `"OnionXT: ..."` string: test `the result is an integer`)
  and complete through the callbacks. Inbound and dialed streams share one table.
- **The control port is a single-in-flight pipeline**: a continuation enqueues the next command while
  the old label is in flight; `oxCtlLine` clears the label and drains the queue.
- **`sx*` calls are made directly inside `try/catch`**, degrading to "needs SodiumXT sxXxx" or a safe
  fallback (SAFECOOKIE -> COOKIE); this replaced a `dispatch function` approach with murky semantics.
- **base32 masks its accumulator** each step, so a 35-byte address never builds a 280-bit integer
  (exact only to 2^53: engine note 2.4); `tools/onion-kat.py` pins it.
- **`oxPublishService` is publish-only**: `ADD_ONION` without the socket, an `external` teardown guard;
  the external server must enforce loopback.
- **`oxhUnroute`** exists for the demo's live swap between `oxhRoute "/"` and `oxhServeFiles` at the
  SAME onion. onion-httpd lists folders with `the files` / `the folders`; `the detailedFiles` is a
  compile-time "bad factor" on OXT.
- **The loopback guard parses by SHAPE**: `oxHostOfSocket` drops `|name`, unbrackets, else takes
  everything up to the LAST colon; an empty host is a REFUSAL, printed with the raw id.
- **Coverage**: the suite's `tools/check-suite-coverage.py` prints this member's ratio. Its exemptions
  are the 11 engine socket callbacks and watchdogs (docs/05), and nothing else. From the four wrong
  ones deleted 2026-08-20: an exemption describes what the WRAPPER needs. The last three "live-daemon"
  ones (`oxLaunchTor`, `oxStopTor`, `oxTransportDial`) went 2026-09-24: each has a refusal before any
  I/O, which the harness now calls by name (empty arguments; an empty address; unauthenticated, and
  guarded so it can never reach the `SIGNAL SHUTDOWN` leg). Never hand `oxTransportDial` a non-empty
  non-onion host in a test: that dials for real.
- **Mode B checks its launch (2026-09-24)**: `oxLaunchTor` reads `the result` of the torrc write and of
  `open process`, returns an `"OnionXT: ..."` reason on either, and re-points the ports only after an
  accepted launch; the torrc sends tor's log to `<pDataDir>/onionxt-tor.log` so the unread pipe is not
  where tor writes (docs/07). Verified statically; needs an OXT pass + a live-Tor pass.
- **The two SOCKS timeouts are told apart (2026-09-24)**: `oxStreamDeadline` and `oxSocketTimeout`
  build their reason through `oxSocksTimeoutReason`, same `SOCKS handshake timed out` prefix, then the
  path and the stalled stage (docs/02); harness section 12 pins the difference.

## Engine evidence ledger

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| pre-suite, undated | Windows, OXT, live system tor and Tor Browser | bring-up: SOCKS dial, SAFECOOKIE, GETINFO / SETEVENTS, `ADD_ONION` publish -> serve -> remove, Tor-forwarded accept, streams both ways, bootstrap and `HS_DESC`; `oxh*` site, file share and routes in Tor Browser; the demo's Service-tab swap and About self-test | confirmed; engine facts 1-7 below |
| 2026-08-08 | OXT, suite paste | daemon-free paths: `oxVersion`, `oxPublicKeyFromAddress` (byte-exact), `oxIsValidAddress` negatives, `oxTransportInfo` | green; capability flags honest (`offlineAddress` false before ABI 7) |
| 2026-08-10 | OXT, suite paste, twice (the re-run with the real `src/` embedded) | `oxSelfTest()` folded | 40/0 both times, 3 SHA3 skips by design |
| 2026-08-12 | Windows x64, SodiumXT ABI 7, suite paste | `oxSelfTest()` folded | 43/0: torproject and DuckDuckGo onions re-encoded byte-exactly, tamper refused, `offlineAddress` true |
| 2026-08-17 | Windows x86_64, NT 10.0, OXT 9.6.3, suite paste | `oxSelfTest()` folded, incl. section 10 (loopback guard) | 61/0; the guard refuses an empty host; all eight socket-id fixtures parse |
| 2026-08-20 | Windows, suite paste whole run (1981/0/1) | `oxSelfTest()` folded | 61 passed; its 1 skip printed inline and merged |
| 2026-08-27 | two-machine session, suite paste (2440/2/3) | `oxSelfTest()` folded; holde-em, which embeds onionxt, at 667/0 | every folded member green (the 2 fails were live loopbacks, environment); holde-em's onionxt embed compiled |
| 2026-09-02 | coin-wallet (carries onionxt), engine log | Esplora over Tor: `oxDial` to a v3 onion `:80`, 147 circuits, testnet broadcast `7978bdd2...`; later a v2 onion | green; one real `SOCKS handshake timed out` failed closed and was retried; the v2 onion got "general SOCKS server failure" (OnionXT's REP `0x01` mapping), failed closed |
| 2026-09-03 | coin-wallet, engine logs 6-12 | Electrum over Tor (v3 onion, port 143): 173 dials, then one kept stream per sync; Esplora over one HTTP/1.1 stream; the autotest over Electrum on Tor | green; autotest 41 passed, 0 failed, 4 skipped in 248 s |

Confirmed on-engine (promoted from `VERIFY:`):

1. `read ... until crlf` returns the trailing CRLF; `oxStripLineEnd` removes it.
2. `read ... for N with message` delivers exactly N raw bytes on a binary socket.
3. A no-quantifier `read ... with message` streams chunks as they arrive, not to EOF.
4. `accept connections on port` accepts Tor-forwarded loopback connections. That record confirmed
   only the branch that ran: the pre-2026-08-17 parse gave every IPv6-shaped id an EMPTY host, which
   the guard ACCEPTED (fail-open: `::ffff:203.0.113.9:1234` is routable). The shape parser and its
   eight fixtures ran green 2026-08-17; the raw id a live accept hands `oxPeerAccepted` is still to be
   recorded (engine note 6.2). A comment describing a branch is not evidence the branch runs.
5. Publish -> serve -> remove; `oxRemoveService` / `oxShutdown` close the listener and `DEL_ONION`.
6. `dispatch ... to <owner>` resolves app callbacks and `sx*` primitives; a missing one is a clean miss.
7. `socketError` reaches the library and fails closed (10061, 10013); `socketClosed` cleans up. A real
   stalled handshake failed closed in the 2026-09-02 coin-wallet log, which cannot say which "SOCKS
   handshake timed out" path fired (the `oxStreamDeadline` watchdog or `oxSocketTimeout`). The two
   reasons differ since 2026-09-24, so the next stall on record will say (item 13).

Still `VERIFY:` (not yet exercised):

8. Mode B: `oxLaunchTor` / `oxStopTor`, `open process`, the `oxProcessId` accessor,
   `__OwningControllerProcess` (engine note 6.3); since 2026-09-24 also the torrc-write and
   `open process` result checks (what `the result` holds on success and on failure) and the
   `Log notice file` line (the log appears and the pipe stays quiet).
9. The four inline hypotheses (runbook B.12): a second service on an in-use local port refused; the
   accepted-socket id format; a stale `close socket` tolerated; the topStack as default callback owner.
10. An OnionXT-to-OnionXT onion dial and the two-instance sealed round trip (`examples/onion-roundtrip`).
11. The 2026-08-23 foreign-socket `pass` lines and the 2026-08-24 wrapper split, on a live socket.
12. The 2026-09-09 `oxWrite` result capture and callback pins.
13. The live negatives: wrong cookie, stalled daemon (and which of the two timeout reasons it
    reports), peer vanishing mid-handshake, a descriptor that never publishes, and an `ExtendedErrors`
    `0xF*` REP for a well-formed v3 onion that does not exist.
    (The bad-onion leg with a mapped REP `0x01` on a retired v2 onion failed closed on an engine on
    2026-09-02: the coin-wallet ledger row.)

## Status

The live-Tor core and `oxh*` hosting are engine-proven (ledger above). The offline `oxSelfTest()` ran
green folded into every dated suite pass above from 2026-08-10, and `tools/onion-kat.py` pins the
pure-compute paths headlessly. The harness's 2026-09-24 additions (the three live-daemon names on
their refusal paths, section 12's timeout reasons) have not run on an engine: verified statically;
needs an OXT pass. Static only ("verified statically; needs an OXT pass + a live-Tor
pass"): items 8-13, and the demo and spike as whole stacks since their 2026-08-14 move onto the suite
UI kit. Open work is tracked in the suite's `docs/WORK-PLAN.md`.

## Build and gates

`bash tools/run-gates.sh` (what CI and the suite's `build-all.sh --gates` run): the unified static gate
`tools/check-livecodescript.py`, `tools/check-docs-style.py`, `tools/onion-kat.py --check` (base32,
address, seed-expansion and HMAC KATs) and `tools/check-selftest-vectors.py --check` (re-derives every
vector hand-copied into the harness). Nothing compiles. Engine bring-up: docs/07, docs/10 section 1.
