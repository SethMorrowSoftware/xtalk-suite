# 05 - Public API Reference (`ox*`)

The public surface OnionXT exposes to an app (or to a higher-layer protocol built on top of it). Shapes
follow the family convention: **commands report status through `the result`** (and yield handles through
out-style conventions), **functions return a value**. All are livecodescript handlers in the v1 core.
This surface is implemented in `src/onionxt.livecodescript`; the core paths (SOCKS dial, control
auth, onion publish/serve/remove, the accept loop) are confirmed on-engine against a live tor
daemon (see CLAUDE.md "As-built notes"). The one path not yet exercised is the optional Mode B
tor launch (`oxLaunchTor` / `oxStopTor`), still flagged VERIFY in the source.

Naming: public `oxPascalCase`. Handles are small integers or the engine's socket ids; a stale handle
is a clean error, never a crash. Every open has a matching idempotent close.

## Configuration

| Handler | Kind | Purpose |
|---|---|---|
| `oxSetSocksPort pPort` | command | Set the loopback SOCKS port (default 9050; Tor Browser 9150). |
| `oxSetControlPort pPort` | command | Set the loopback control port (default 9051; Tor Browser 9151). |
| `oxSetControlPassword pPassword` | command | Store the password used when the daemon offers HASHEDPASSWORD auth (doc 03 step 2). Only needed for that auth method. |
| `oxSetCallbackOwner pObjectLongId` | command | Name the object whose script holds the app callbacks (onStatus / onPeer / onStreamData). If unset, callbacks dispatch to the topStack; setting it explicitly removes any ambiguity. |
| `oxVersion()` | function | OnionXT version string, and (once connected) the tor version from `GETINFO version`. |

Host is always `127.0.0.1`; it is not configurable (loopback-locked, CLAUDE.md socket gotcha 6).

## Control connection and bootstrap

| Handler | Kind | Purpose |
|---|---|---|
| `oxConnectControl` | command | Open + authenticate the control connection (PROTOCOLINFO, then the best auth method). Reports success/failure in `the result`. |
| `oxDisconnectControl` | command | Close the control connection. Idempotent. |
| `oxIsControlAuthenticated()` | function | True once the control connection has authenticated. |
| `oxBootstrapProgress()` | function | 0..100 from `STATUS_CLIENT` / `GETINFO status/bootstrap-phase`. |
| `oxIsReady()` | function | True once the daemon is bootstrapped to 100 AND the control connection is authenticated. Per-service readiness (descriptor uploaded) is `oxServiceIsReady` / the `serviceReady` status event. |

The app sets a callback (for example `oxSetStatusCallback pHandlerName`) to receive coalesced
bootstrap / event updates at <= ~4 Hz.

## Outbound: dialing

| Handler | Kind | Purpose |
|---|---|---|
| `oxDial pHost, pPort` | command | SOCKS5 CONNECT (ATYP=3) to `pHost:pPort` through Tor. Reports a stream handle in `the result`, or a mapped SOCKS error. `pHost` is a `.onion` or clearnet name; it is resolved in Tor, never locally. |
| `oxWrite pStream, pData` | command | Write `Data` (already sealed by the app) to the stream. |
| `oxSetStreamCallback pStream, pHandlerName` | command | Register the handler the engine-side read loop calls with inbound `Data` on this stream. |
| `oxStreamState pStream` | function | The stream's current state string (`"unknown"` for a stale or never-opened handle). |
| `oxCloseStream pStream` | command | Close and forget the stream. Idempotent. |

Reads are asynchronous: OnionXT reads the tunneled socket `with message` and hands each chunk of
`Data` to the registered stream callback. The app reassembles application-level frames (OnionXT does
not know the app's framing).

## Inbound: onion services

| Handler | Kind | Purpose |
|---|---|---|
| `oxCreateService pVirtualPort, pLocalPort` | command | `ADD_ONION NEW:ED25519-V3` mapping `pVirtualPort` -> `127.0.0.1:pLocalPort`, after ensuring a loopback listener is accepting on `pLocalPort`. Reports the full `<56>.onion` address and a service handle. |
| `oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort` | command | As above, but deterministic: composes SodiumXT `sxSignSeedToExpandedKey` (ABI >= 6) to turn the 32-byte `pSeed` into the ED25519-V3 expanded key, so the same seed always yields the same `.onion`. |
| `oxPublishService pVirtualPort, pLocalPort` | command | Publish-only: `ADD_ONION` maps `pVirtualPort` -> `127.0.0.1:pLocalPort` but OnionXT does NOT start an accept loop, so an EXTERNAL server (e.g. LiveCode's built-in HTTPD Library) can own that port. Teardown `DEL_ONION`s but leaves that socket alone. The external server must enforce loopback itself (reject non-127.0.0.1 peers). |
| `oxRemoveService pService` | command | `DEL_ONION` and stop the listener (a listener OnionXT owns; a publish-only service has none). Idempotent. |
| `oxServiceAddress pService` | function | The `.onion` address of a published service. |
| `oxServiceIsReady pService` | function | True once that service's descriptor is uploaded (the `serviceReady` status event has fired for it). |
| `oxSetPeerCallback pHandlerName` | command | Register the handler called when a peer connects to a published service (delivers a new inbound stream handle). |

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
| `oxTransportInfo()` | function | A small record describing this transport (name, whether it is connected, whether seed-derived offline addressing is available). |
| `oxTransportDial pAddress, pPort` | command | Dial an address through the transport (wraps `oxDial`). |
| `oxTransportListen pSeed, pVirtualPort, pLocalPort` | command | Listen at a deterministic, seed-derived address (wraps `oxCreateServiceFromSeed`). |
| `oxTransportSend pStream, pData` | command | Send bytes on a transport stream (wraps `oxWrite`). |
| `oxTransportRecv pStream, pHandlerName` | command | Register where inbound bytes are delivered (wraps `oxSetStreamCallback`). |

## Lifecycle

| Handler | Kind | Purpose |
|---|---|---|
| `oxShutdown` | command | Close every stream, remove every service, disconnect control. Idempotent; call it when the app closes (for example on `closeStack`) since OXT has no deterministic unload hook. |

## Optional Mode B: launching tor (NOT the default; still needs its on-engine pass)

The recommended, tested base is Mode A: an already-running tor daemon. Mode B launches one for you
and is still flagged `VERIFY:` in the source (not yet exercised on-engine):

| Handler | Kind | Purpose |
|---|---|---|
| `oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort` | command | Write a minimal torrc and `open process` a tor daemon with those ports. |
| `oxStopTor` | command | Stop a tor launched by `oxLaunchTor`. |

## Callbacks the app implements

| Callback | Delivered when |
|---|---|
| status callback | bootstrap progress, circuit/descriptor events (coalesced). |
| stream callback (per dialed stream) | inbound `Data` arrives on that stream. |
| peer callback (per service) | a remote peer connects to a published service; yields a new inbound stream handle to register a stream callback on. |

## Error model

- Commands set `the result` to empty on success, or to a clear, human-readable error string on
  failure (mapped SOCKS REP codes, control `4xx`/`5xx`, timeouts, closed sockets). Never a raw numeric
  code with no explanation.
- Every wire error fails closed and tears the resource down; there is no silent fallback to an
  unproxied or unauthenticated path (CLAUDE.md rule 4).

## What is deliberately NOT here

- No encryption, framing, or session logic: OnionXT moves bytes; the app (or the protocol layered on
  top of it) seals them with SodiumXT and owns their framing.
- No blocking read/connect variants: the whole surface is callback-driven so the one interpreter
  thread never blocks on the network (CLAUDE.md async model).
