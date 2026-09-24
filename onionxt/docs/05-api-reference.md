# 05 - Public API Reference (`ox*`)

The public surface OnionXT exposes to an app (or to a higher-layer protocol built on top of it), all
livecodescript handlers in `src/onionxt.livecodescript`. **Commands report through `the result`**
(handle-yielding commands report the handle there); **functions return a value**. Which paths are
engine-proven and which are still "verified statically; needs an OXT pass + a live-Tor pass" is the
evidence ledger in CLAUDE.md.

Naming: public `oxPascalCase`. Handles are small integers or the engine's socket ids; a stale handle
is a clean error, never a crash. Every open has a matching idempotent close.

## Configuration

| Handler | Kind | Purpose |
|---|---|---|
| `oxSetSocksPort pPort` | command | Set the loopback SOCKS port (default 9050; Tor Browser 9150). |
| `oxSetControlPort pPort` | command | Set the loopback control port (default 9051; Tor Browser 9151). |
| `oxSetControlPassword pPassword` | command | Store the password used when the daemon offers HASHEDPASSWORD auth (doc 03 step 2). Only needed for that auth method. |
| `oxSetCallbackOwner pObjectLongId` | command | Name the object whose script holds the app callbacks. If unset, callbacks dispatch to the topStack; set it explicitly (`the long id of me`). |
| `oxSetStatusCallback pHandlerName` | command | Register the status callback: control state, bootstrap %, service address / ready, notices, coalesced to <= ~4 Hz. |
| `oxSetPeerCallback pHandlerName` | command | Register the handler called when a peer connects to a published service (delivers a new inbound stream handle). |
| `oxVersion()` | function | OnionXT version string, and (once connected) the tor version from `GETINFO version`. |

Host is always `127.0.0.1`; it is not configurable (loopback-locked, CLAUDE.md socket gotcha 6).

## Control connection and bootstrap

| Handler | Kind | Purpose |
|---|---|---|
| `oxConnectControl` | command | Open and authenticate the control connection asynchronously (PROTOCOLINFO, then the best auth method); the outcome arrives as `control` status (`authenticated`, or `authfailed: ...` / `error: ...`). Reports an error at once only if a connection is already open. |
| `oxDisconnectControl` | command | Close the control connection. Idempotent. |
| `oxIsControlAuthenticated()` | function | True once the control connection has authenticated. |
| `oxBootstrapProgress()` | function | 0..100 from `STATUS_CLIENT` / `GETINFO status/bootstrap-phase`. |
| `oxIsReady()` | function | True once the daemon is bootstrapped to 100 AND the control connection is authenticated. Per-service readiness (descriptor uploaded) is `oxServiceIsReady` / the `serviceReady` status event. |

## Outbound: dialing

| Handler | Kind | Purpose |
|---|---|---|
| `oxDial pHost, pPort` | command | SOCKS5 CONNECT (ATYP=3) to `pHost:pPort` through Tor. Reports a stream handle in `the result` at once, or an argument error; a SOCKS failure arrives later as the stream's `error` event. `pHost` is resolved in Tor, never locally. |
| `oxWrite pStream, pData` | command | Write `Data` (already sealed by the app) to a connected stream. Reports empty, or an error string when the stream is not open or the engine's write fails (the write result is read since 2026-09-09; verified statically, needs an OXT pass). |
| `oxSetStreamCallback pStream, pHandlerName` | command | Register the handler the engine-side read loop calls with inbound `Data` on this stream. |
| `oxStreamState pStream` | function | The stream's current state string (`"unknown"` for a stale or never-opened handle). |
| `oxCloseStream pStream` | command | Close and forget the stream. Idempotent. |

Reads are asynchronous: each inbound chunk reaches the stream callback as a `data` event, and the app
reassembles its own frames.

## Inbound: onion services

| Handler | Kind | Purpose |
|---|---|---|
| `oxCreateService pVirtualPort, pLocalPort` | command | Start the loopback listener on `pLocalPort`, then `ADD_ONION NEW:ED25519-V3 Flags=Detach` mapping `pVirtualPort` -> `127.0.0.1:pLocalPort`. Reports a service handle; the `<56>.onion` address arrives with the `service` status event (and `oxServiceAddress`). |
| `oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort` | command | As above, but deterministic: composes SodiumXT `sxSignSeedToExpandedKey` (ABI >= 6) to turn the 32-byte `pSeed` into the ED25519-V3 expanded key, so the same seed always yields the same `.onion`. |
| `oxPublishService pVirtualPort, pLocalPort` | command | Publish-only: `ADD_ONION` maps `pVirtualPort` -> `127.0.0.1:pLocalPort` but OnionXT starts no accept loop, so an EXTERNAL server can own that port. Teardown `DEL_ONION`s and leaves that socket alone. The external server must enforce loopback itself. |
| `oxRemoveService pService` | command | `DEL_ONION` and stop the listener (a listener OnionXT owns; a publish-only service has none). Idempotent. |
| `oxServiceAddress pService` | function | The `.onion` address of a published service. |
| `oxServiceIsReady pService` | function | True once that service's descriptor is uploaded (the `serviceReady` status event has fired for it). |

## Address helpers (pure, no network)

| Handler | Kind | Purpose |
|---|---|---|
| `oxAddressFromPublicKey pEd25519Pub` | function | Encode a 32-byte ed25519 public key as a `<56>.onion` address. The checksum composes SodiumXT ABI 7's `sxSha3_256` (doc 08 gap #2, shipped 2026-08-11); against an older SodiumXT it still returns the clear capability error. |
| `oxPublicKeyFromAddress pOnionAddress` | function | Decode a `.onion` back to its 32-byte ed25519 public key. base32-decode + strip checksum/version. |
| `oxIsValidAddress pOnionAddress` | function | Structural + (when SHA3-256 is available) checksum validation of a pasted address. |

## The pluggable transport seam (`oxTransport*`)

The thin, uniform facade a higher-layer protocol codes against (doc 06), so the Tor transport can
be swapped for another without touching the protocol layer. Each wraps the corresponding core
handler and reports the same way:

| Handler | Kind | Purpose |
|---|---|---|
| `oxTransportInfo()` | function | An array: `transport` ("ox"), `version`, and the capability flags `safeCookieAuth`, `deterministicOnion`, `offlineAddress` (doc 10 section 7). |
| `oxTransportDial pAddress, pPort` | command | Dial a full `.onion`, or a 32-byte ed25519 key / 64-hex string mapped to its address first (wraps `oxDial`; port defaults to 80). |
| `oxTransportListen pSeed, pVirtualPort, pLocalPort` | command | Listen at a deterministic, seed-derived address (wraps `oxCreateServiceFromSeed`). |
| `oxTransportSend pStream, pData` | command | Send bytes on a transport stream (wraps `oxWrite`). |
| `oxTransportRecv pStream, pHandlerName` | command | Register where inbound bytes are delivered (wraps `oxSetStreamCallback`). |

## Lifecycle

| Handler | Kind | Purpose |
|---|---|---|
| `oxShutdown` | command | Close every stream, remove every service, disconnect control. Idempotent; call it when the app closes (for example on `closeStack`) since OXT has no deterministic unload hook. |

## Optional Mode B: launching tor (not the default; not yet run on an engine)

The recommended base is Mode A, an already-running daemon (doc 07). Mode B is flagged `VERIFY:` in the
source:

| Handler | Kind | Purpose |
|---|---|---|
| `oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort` | command | Write `<pDataDir>/onionxt-torrc` (the ports, default 9050 / 9051, cookie auth, `DataDirectory`, `__OwningControllerProcess`, and tor's log to `<pDataDir>/onionxt-tor.log`) and `open process` tor with `-f` it. `the result` is an `"OnionXT: ..."` reason if either argument is empty, the torrc write fails or `open process` reports a failure; the SOCKS and control ports are pointed at the launched tor only after a launch is accepted. Does not wait for bootstrap: poll `oxConnectControl` / `oxBootstrapProgress`. |
| `oxStopTor` | command | Send `SIGNAL SHUTDOWN` if control is authenticated, then disconnect control (idempotent). |

## Callbacks the app implements

| Callback | Signature | Delivered when |
|---|---|---|
| status | `pKind, pInfo` | `control` state, `bootstrap` 0..100, `ready`, `service` (the address), `serviceReady`, `notice`, raw `event` lines; coalesced |
| stream | `pStream, pEvent, pData` | `open`, `data` (an inbound chunk), `closed`, or `error` (the stream is already torn down), on a dialed or inbound stream |
| peer | `pStream, pService, pPeerAddr` | a remote peer reached a published service; register a stream callback on the fresh `pStream` |

## Handlers the ENGINE calls (in the script, not in the app-facing API)

`src/onionxt.livecodescript` defines fourteen public handlers an app must never call: eleven callbacks
and the three engine socket messages, which carry the one integration hazard whose symptom is a
**hang rather than an error** (the rule below, and [doc 10 section 2](10-usage-guide.md)).

**Eleven `ox*` callbacks OnionXT arms itself** (`open socket` / `read from socket` / `accept
connections ... with message`, or a self-sent watchdog `send ... to me in <timeout>`), called with the
socket id the engine minted. The two watchdogs are self-sent, and `oxStreamDeadline`'s argument is a
STREAM HANDLE, not a socket id:

| Handler | Armed by | Called when |
|---|---|---|
| `oxCtlOpened pSocketID` | `open socket` to the control port | the control TCP connection is up; starts the line reader and sends `PROTOCOLINFO 1`. |
| `oxCtlLine pSocketID, pData` | `read ... until crlf with message` | one control line arrived; demultiplexes `650` events from command replies (doc 03 framing). |
| `oxCtlDeadline pSocketID` | `send ... to me in` (watchdog, not a socket message) | the control handshake watchdog expires; tears down an unauthenticated connection. |
| `oxSocksOpened pSocketID` | `open socket` to the SOCKS port | the proxy TCP connection is up; writes the `05 01 00` greeting. |
| `oxSocksMethod pSocketID, pData` | `read ... for 2 with message` | the 2-byte method selection arrived (doc 02 step 1). |
| `oxSocksReplyHead pSocketID, pData` | `read ... for 4 with message` | the fixed 4-byte reply head arrived; `REP != 0` fails closed here. |
| `oxSocksReplyLen pSocketID, pData` | `read ... for 1 with message` | the ATYP=3 `BND.ADDR` length byte arrived. |
| `oxSocksReplyDone pSocketID, pData` | `read ... for N with message` | the rest of the reply is consumed; the socket is now a tunnel. |
| `oxStreamData pSocketID, pData` | `read ... with message` (no quantifier) | a chunk arrived on a live stream, dialed or inbound; delivers `data` and re-arms. |
| `oxStreamDeadline pStream` | `send ... to me in` (watchdog; takes a STREAM HANDLE, not a socket id) | a dialed stream's handshake watchdog expires. |
| `oxPeerAccepted pSocketID` | `accept connections on port ... with message` | Tor forwarded an inbound onion connection to the local listener; **enforces the loopback guard** before reading a byte. |

Each tests its argument first and exits on a miss, so calling one by hand is a clean no-op that
exercises nothing, which is why the suite's coverage gate carries these eleven as written exemptions.

**Three engine socket MESSAGES**, whose names are the engine's (no `ox` prefix) and which reach the
message path, not a handler OnionXT named. Each is a thin wrapper: it calls a named function, exits if
that consumed the event, and otherwise passes.

| Message | Named function | What OnionXT does with it |
|---|---|---|
| `socketError pSocketID, pError` | `oxSocketError pSocketID, pError` | arrives instead of `socketClosed` when a socket fails; fails the owning stream closed, or reports and disconnects the control connection. |
| `socketClosed pSocketID` | `oxSocketClosed pSocketID` | the far side closed cleanly; delivers `closed` to the stream's app callback and forgets it, or marks control disconnected. |
| `socketTimeout pSocketID` | `oxSocketTimeout pSocketID` | REPEATS every `socketTimeoutInterval` while a read is pending, so it is fatal only during a handshake; a connected stream ignores it. |

Each named function answers ONE question, *was that socket mine, and did I handle it?*, returning
`"true"` when it consumed the event and `"false"` for somebody else's socket. They exist for an
EMBEDDER: every socket library declares the three engine names and one script cannot define a name
twice, so `tools/sync-demo-embeds.py` drops the three wrappers for a registered (app, library) pair and
the app calls `oxSocketError(...)` etc. from its own handler exactly where it would pass. No logic is
copied, so nothing goes stale; nocloud's `nocloudquickshare.livecodescript` was the first app to carry
OnionXT this way. The split is **verified statically**; the own-socket branches are unchanged and keep
their engine evidence, and the wrapper form needs a live-Tor re-pass.

> **Integration rule: if your stack defines any of these three, it must `pass` the ones that are not
> yours.** A handler that does not forward the message can swallow it before OnionXT's copy runs.
> Nothing errors: the failed dial never reports, the closed stream never delivers `closed`, the
> stalled handshake never times out. The symptom is a hang. nocloud and torrent-quickshare arrived at
> the same guard independently (act only on your own sockets, `pass` everything else);
> [doc 10 section 2](10-usage-guide.md) gives the pattern. The exact message-path ordering is the
> engine's: **verified statically; needs an OXT pass** to state precisely.

## Error model

- Handle-yielding commands (`oxDial`, `oxCreateService`, `oxCreateServiceFromSeed`, `oxPublishService`,
  the `oxTransportDial` / `oxTransportListen` wrappers, onion-httpd's `oxhServe`) report the handle;
  test `the result is an integer`. Other commands report empty on success. Failure is a human-readable
  `"OnionXT: ..."` string, never a bare numeric code.
- Asynchronous failures (mapped SOCKS REP codes, control `4xx`/`5xx`, timeouts, closed sockets) arrive
  through the stream `error` event or the status callback.
- Every wire error fails closed and tears the resource down; there is no silent fallback to an
  unproxied or unauthenticated path (CLAUDE.md rule 4).

## What is deliberately NOT here

- No encryption, framing, or session logic: OnionXT moves bytes; the app (or the protocol layered on
  top of it) seals them with SodiumXT and owns their framing.
- No blocking read/connect variants: the whole surface is callback-driven so the one interpreter
  thread never blocks on the network (CLAUDE.md async model).
