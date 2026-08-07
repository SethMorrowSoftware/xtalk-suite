# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in the OnionXT repository.

> **Read the docs first.** [docs/00-overview.md](docs/00-overview.md) (architecture),
> [docs/01-threat-model.md](docs/01-threat-model.md) (what Tor does and does not promise),
> [docs/02-socks5-client.md](docs/02-socks5-client.md) and [docs/03-control-port.md](docs/03-control-port.md)
> (the two wire protocols, byte for byte), and [docs/04-onion-rendezvous.md](docs/04-onion-rendezvous.md)
> (the onion-address-is-a-public-key idea) are the source of truth for WHAT OnionXT is.
> [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) is the phased HOW. This file is the operational
> as-built record and the hard-won-lesson list, in the same spirit as the `CLAUDE.md` files in our
> sibling projects Box2Dxt, ShowControl, TorrentXT, and SodiumXT. Most of the OXT/LCB and
> FFI lessons below were paid for in full while building those; they are carried here so we do not
> pay for them twice. The socket-I/O lessons are the new ones and are called out as such.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`, even in comments and strings. Comment the *why*, densely; match the surrounding
style.

## What this is

**OnionXT** is a Tor transport and rendezvous layer for OpenXTalk (OXT) / the xTalk family. It lets an
xTalk app (1) dial any TCP endpoint anonymously through Tor's SOCKS5 proxy, and (2) create and reach
**v3 onion services**, whose address is itself an ed25519 public key, giving serverless,
self-authenticating, IP-anonymous rendezvous. It talks to a **locally-running tor daemon**; it does
not embed, reimplement, or (by default) ship Tor.

```
tor daemon (running separately)
   127.0.0.1:9050  SOCKS5 proxy   ->  outbound: OnionXT dials a .onion or a clearnet host
   127.0.0.1:9051  control port   ->  inbound:  OnionXT publishes an onion service, reads events
      |
OnionXT (public ox*)   src/onionxt.livecodescript
   |- SOCKS5 client        engine socket I/O, RFC 1928 + Tor SOCKS extensions
   |- control-port client  engine socket I/O, the Tor control protocol (line-based text)
   |- local accept loop    Tor forwards inbound onion connections to a loopback port we accept on
        |- composes SodiumXT (sx*) for ed25519 identity, deterministic onion keys, payload sealing
        |- exposes a pluggable transport seam (oxTransport*) any higher-layer protocol can use
```

The core is **livecodescript**, not LCB and not C, because the pieces it needs (`open socket`,
`read from socket`, `write to socket`, `accept connections on port`) are LiveCode Script engine
commands, not LCB library calls. An optional thin LCB or C helper is justified only for pure-compute
work that script does badly (fast binary framing, base32, an ed25519 key expansion), and only after
an on-engine pass shows script is too slow or too awkward. Default to script; reach for native last.

## How OnionXT differs from its siblings (read this before you assume)

OnionXT inherits differently from each sibling. Do not cargo-cult any of them wholesale.

1. **Unlike SodiumXT, OnionXT does no cryptography and is not one-shot.** SodiumXT is bytes in,
   bytes out, no state, no I/O. OnionXT owns **long-lived network state**: open SOCKS streams, a
   persistent control-port connection, published onion services, and an accept loop. Its whole job is
   I/O. Crypto is delegated to SodiumXT (rule 1 below).
2. **Unlike SodiumXT, OnionXT is asynchronous and event-driven, like TorrentXT.** Sockets connect,
   read, and accept on their own schedule; the control port pushes unsolicited `650` event lines.
   So TorrentXT's discipline comes BACK: never block the one interpreter thread on the network, drive
   everything by socket callbacks (`with message`), and treat the flow as a state machine, not a
   straight line of blocking calls (see "The asynchronous, event-driven model" below).
3. **Unlike TorrentXT, OnionXT wraps no C engine and (by default) no C at all.** TorrentXT wrapped
   libtorrent behind a C++ shim. OnionXT wraps two simple wire protocols spoken over ordinary engine
   sockets. There is usually no FFI line to firewall. The FFI section below is carried for the day a
   helper shim is justified, and is explicitly gated on "if and only if you add a shim."
4. **OnionXT is a transport, not a protocol suite.** A higher-layer protocol defines envelopes,
   ratchets, and channels. OnionXT just moves bytes anonymously and provides an address. It has no
   opinion about what those bytes are; the app (or the protocol layered on top) owns the payload and
   its encryption.

## The rules that make this safe and correct

1. **Add no cryptography. Compose SodiumXT (ABI >= 6).** ed25519 identity keys, the deterministic
   onion-key expansion (`sxSignSeedToExpandedKey`), SAFECOOKIE HMAC (`sxHmacSha256`), and every
   protected payload byte are SodiumXT calls (`sx*`). There is no OnionXT cipher, KDF, or signature. A
   still-missing primitive (SHA3-256 for the offline v3 address checksum, doc 08 gap #2, deferred) is an
   upstream SodiumXT feature request, never a hand-rolled hash here.
2. **Trust the onion address, verify the daemon, distrust the network.** A v3 onion address is an
   ed25519 public key (doc 04): connecting to it authenticates the far end for free, so treat the
   address as the contact's identity and pin it. The **local tor daemon is trusted** (it sees your
   SOCKS targets and your onion keys if you let it generate them); document that boundary loudly. The
   network beyond Tor is fully untrusted and sees only onion-routed ciphertext.
3. **Never leak the payload or the target outside Tor.** Dial `.onion` and clearnet hosts through the
   SOCKS proxy using **ATYP=3 (domain name)** so Tor resolves names (never do a local DNS lookup for a
   target: that is a DNS leak, and for a `.onion` it is meaningless). Do not open a direct socket to a
   peer "to save a hop"; that defeats the entire point.
4. **Fail closed on every wire error.** A SOCKS reply with a non-zero REP field, a control-port `5xx`,
   a short read, or a closed socket is an error that returns cleanly to the caller and tears down the
   stream, never a silent fallback to an unproxied or unauthenticated path.
5. **Own the lifecycle.** Every opened socket, every published onion service (`ADD_ONION`), and every
   accept listener must have an explicit, idempotent close/`DEL_ONION`/`close socket`. There is no
   deterministic unload hook in OXT, so document that the app frees what it opens (for example on
   `closeStack`), and make every teardown safe to call twice.

## Commands

**Static gate for the script layer** (the only automated safety net; OXT has no headless compile):
```sh
python3 tools/check-livecodescript.py
```
Carried verbatim from SodiumXT/TorrentXT. It checks every `.lcb` and `.livecodescript` for
smart/curly quotes and em/en dashes, handler / `if` / `repeat` / `unsafe` / `try` balance,
constants-declared-before-use, the prefixed-token-shadow trap (`tExt` == `text`), and the
`put ... into ... after` malformation. A script change is only "done" once this passes.

**There is no headless way to compile or run `.livecodescript` on OXT.** So say **"designed and
statically reasoned; needs an on-engine pass"** and let the user confirm on the engine. Do not claim
a socket handshake "works" until it has actually shaken hands with a real tor daemon.

**Manual on-engine bring-up needs a tor daemon.** The cheapest is Tor Browser (SOCKS on
`127.0.0.1:9150`) or a system `tor` (SOCKS `9050`, control `9051`). The control port must be enabled
and an auth method configured in `torrc` (see doc 03). Document the exact `torrc` lines in the
example so a tester can reproduce.

**If, and only if, OnionXT grows its own C shim**, build it under gcc ASan + UBSan exactly as
SodiumXT does, treat any third-party headers as system headers (`-isystem`) so their warnings do not
pollute `-Wall -Wextra`, and bump an ABI version + a `checkABI()` guard on every ABI change.

## Socket and engine I/O gotchas (the NEW hard-won lessons; verify each on-engine)

These are OnionXT's own territory, not carried from a sibling, so treat every one as a hypothesis to
confirm on the engine and record the result here as it is learned.

1. **Binary, not text.** SOCKS5 is a binary protocol. Read and write with byte discipline: build
   requests with `numToByte` / `binaryEncode`, parse replies with `byteToNum` / `binaryDecode`, and
   index with `byte x to y of`. Never use `char`, `line`, or `word` on socket data (they are
   Unicode- and delimiter-aware and will mangle bytes). Keep `the useUnicode` / encoding assumptions
   out of the socket path entirely.
2. **Blocking reads freeze the UI; use callback reads.** `read from socket s for N` (no `with
   message`) blocks the single interpreter thread until N bytes arrive or it times out. That is
   acceptable only in a short, bounded handshake with a timeout set, and never on the moment-to-moment
   UI path. Prefer `read from socket s for N with message gotBytes` so the read is asynchronous and
   the engine calls `gotBytes` when the bytes are ready. Model the SOCKS handshake and the control
   protocol as **state machines** driven by those callbacks (this is TorrentXT's poll/drain lesson,
   re-inherited).
3. **A socket read can return short; frame every message by length.** Reassemble until you have the
   exact number of bytes the protocol says the next field is. SOCKS replies are mostly fixed-size
   until the variable BND.ADDR; the control protocol is line-delimited (`\r\n`), so read until CRLF
   and remember that a `250-` prefix means "more lines follow" and `250 ` (space) means "last line".
4. **`open socket` is asynchronous too.** Use `open socket to "127.0.0.1:9050" with message
   socketReady`; do not assume the socket is usable on the next line. A connection failure arrives as
   a `socketError` message, not a thrown error. Wire both.
5. **Inbound onion traffic needs a local listener.** After `ADD_ONION ... Port=<virt>,127.0.0.1:<local>`,
   Tor forwards connections that reach your onion's virtual port to `127.0.0.1:<local>`. Your app must
   already be running `accept connections on <local> with message onPeer` so those forwarded
   connections are answered. Bind the listener to loopback only; never `0.0.0.0`.
6. **Loopback only, always.** The SOCKS proxy, the control port, and the onion-forward target are all
   `127.0.0.1`. Binding or connecting any of them to a routable interface leaks or exposes. Hardcode
   loopback and make the ports configurable but loopback-locked.
7. **Timeouts and teardown are mandatory.** Set `the socketTimeoutInterval` (or an explicit timer)
   around every handshake; a tor daemon that is still bootstrapping will accept the TCP connection and
   then stall. On any timeout, `close socket` and surface a clean error.
8. **`socketError`, closed peers, and half-open states are normal, not exceptional.** Handle a peer
   that vanishes mid-handshake as an ordinary path, not a crash. Every `open`/`accept` gets a matching
   error handler and a matching `close`.

## The SOCKS5 dial path (doc 02 is the byte-level spec)

- Greet with `05 01 00` (version 5, one method, no-auth). Expect `05 00` back. If the server picks a
  method other than `00`, fail closed (Tor's SOCKS does not need auth on loopback).
- CONNECT request: `05 01 00 03 <len> <host-bytes> <port-hi> <port-lo>`. ATYP `03` = domain name; put
  the full `<base32>.onion` (or clearnet hostname) as the host so **Tor** resolves it. Port is 2 bytes
  big-endian.
- Reply: `05 REP 00 ATYP BND.ADDR BND.PORT`. `REP == 00` is success and the socket is now a tunnel;
  anything else is failure. Map Tor's SOCKS extended errors (0xF0..0xF6: onion descriptor invalid,
  introduction failed, rendezvous failed, missing client auth, bad onion address, etc.) to clear
  messages, because those are the ones a user will actually hit.
- After success, the socket carries whatever bytes you write. OnionXT does not encrypt them; that is
  SodiumXT's job one layer up.

## The control-port path (doc 03 is the command-level spec)

- Connect to the control port, then **authenticate before anything else** or every command returns
  `514 Authentication required`. Support the three methods in priority order: NULL (`AUTHENTICATE`),
  SAFECOOKIE / COOKIE (read the cookie file named by `GETINFO`/`PROTOCOLINFO`, send the hex), and
  HashedControlPassword (`AUTHENTICATE "password"`). Detect which the daemon offers with
  `PROTOCOLINFO 1` before authenticating.
- Create an ephemeral onion service with `ADD_ONION NEW:ED25519-V3 Port=<virt>,127.0.0.1:<local>`.
  The reply gives `ServiceID=<56-char-base32>` (the address minus `.onion`) and, unless you pass
  `Flags=DiscardPK`, `PrivateKey=ED25519-V3:<base64>`. Persist the private key if the address must
  survive a restart, or derive it deterministically (doc 04) so it is reproducible from a seed.
- `Flags=Detach` keeps the service alive after the control connection closes; without it, the service
  dies with the connection (which is often what you want for a short session).
- `DEL_ONION <ServiceID>` removes a service. `SETEVENTS <classes>` subscribes to async `650` events
  (`CIRC`, `STREAM`, `HS_DESC`, `STATUS_CLIENT` for bootstrap). Read `650` lines the same way as
  command replies but route them to the event state machine, not to the pending-command continuation.
- The protocol is CRLF-line-based text, so it is far friendlier than SOCKS: still frame by CRLF, and
  still remember the `250-` (continues) vs `250 ` (final) distinction.

## FFI / C-ABI conventions (carried verbatim; applies ONLY if you add a shim)

OnionXT v1 has no foreign handlers, so you will rarely touch this. But if you add a helper shim (fast
binary framing, base32, ed25519 key expansion, or launching a bundled tor), these rules are law. This
is the single most expensive thing the family has learned. Change nothing here without a very good
reason.

- **Byte buffers cross as `Pointer` + `CInt` length. An LCB `Data` does NOT auto-bridge to a `void*`.**
  The Language Reference is explicit: "No automatic bridging from Data or String to Pointer exists"; a
  `Data` marshals as an opaque `MCDataRef`. So an **out** buffer is a raw block from the engine
  `<builtin>` `MCMemoryAllocate`, passed as a real `Pointer`; the shim returns bytes written, or
  `-needed` (negative required size) if the block was too small, and the LCB layer re-allocates,
  retries, and copies back with `MCDataCreateWithBytes`. An **in** buffer passes
  `MCDataGetBytePtr(theData)` plus its length. `<builtin>` handlers resolve by **name**, so they carry
  no leading underscore; our own foreign decls keep a private-name convention.
- **`MCMemoryAllocate`'s size is C `size_t`, so it marshals as `UIntSize`, NOT `CUInt`.** A 4-byte int
  into an 8-byte size slot on a 64-bit build corrupts the heap. `UIntSize` is what the proven
  htmltidy / TorrentXT / SodiumXT bindings use.
- **There is no 64-bit foreign int.** Values that can exceed 2^31 cross as decimal `ZStringUTF8`
  strings, parsed in the shim.
- **Reals cross as `double`, booleans as `int` (0/1).** Exported C ABI symbols keep a stable prefix
  (`onx_`); never rename one once shipped (the `.lcb` `binds to` strings reference it by name; a
  rename is a silent bind failure at load).
- **Never RETURN a bridged C string** (`ZStringUTF8` / `NativeCString`) from a foreign handler: the
  engine adopts the returned pointer and later `free()`s it, so a static or library-owned return is
  `free()`-on-static, heap corruption on the first call. Fill a caller buffer and return length /
  `-needed` instead.
- **Pass a null pointer only through an `optional Pointer`** parameter; a plain `Pointer` rejects
  `nothing`.
- **Bump the ABI version on any ABI change**, and have the `.lcb` `checkABI()` throw a clear
  "reinstall the extension" error on skew instead of corrupting memory on first use. Expose every
  length constant from the shim as a function; never hardcode a size in LCB.
- **`textEncode` / `textDecode` are NOT available to an LCB module** (they are livecodescript only), so
  bytes cross as `Data` and a String is built from filled bytes with `MCStringCreateWithBytes`. Keep
  text<->Data conversion in the livecodescript layer.

## Handles and long-lived state

- **Script-side state is the norm here.** A published onion service, an open control connection, and a
  live SOCKS stream are all tracked in script-local tables keyed by a small integer or the socket id
  the engine returns. A stale or closed id must be a clean no-op / error, never a crash. Provide an
  explicit, idempotent free for each (`oxCloseStream`, `oxRemoveService`, `oxDisconnectControl`), and
  free what you open (there is no deterministic LCB unload hook), for example on `closeStack`.
- **If any of this ever moves into a C shim**, use a generation-tagged handle table exactly as
  SodiumXT's secretstream / multipart-hash tables do: positive 32-bit ints, `0` invalid, a stale or
  recycled handle a clean error, with an explicit idempotent free. Do not round-trip a raw pointer or
  an opaque struct through script.

## The asynchronous, event-driven model (re-inherited from TorrentXT)

OXT runs script, the FFI, and rendering on ONE interpreted thread, and the network does not wait for
it. Therefore:

- **Never block the interpreter thread on the network.** A SOCKS handshake, a control command, an
  onion-descriptor publication, and a peer connection are all asynchronous. Model each protocol as a
  state machine driven by `open socket ... with message`, `read from socket ... with message`, and
  `accept connections on ... with message`. Do not busy-wait, and do not `wait ... with messages` in a
  loop where a callback would do.
- **Keep status updates at <= ~4 Hz.** Bootstrap progress, circuit build, and descriptor upload can
  each fire many events; coalesce them before touching a field, exactly as SodiumXT's performance
  playbook warns for its blocking crypto.
- **Bootstrapping is slow and user-visible.** A cold tor daemon can take tens of seconds to reach
  100% bootstrap, and an onion service takes seconds more to publish its descriptor before it is
  reachable. Surface this as explicit progress (read `STATUS_CLIENT`/`GETINFO status/bootstrap-phase`
  and `HS_DESC`), never as a frozen UI.

## LiveCodeScript / LCB / OXT gotchas (carried; OXT is stricter than LiveCode)

1. **No smart/curly quotes** (U+201C/201D/2018/2019) anywhere, even in a comment or string: they fail
   OXT compilation. ASCII `"` and `'` only. The static checker enforces zero.
2. **Avoid names whose stem shadows an engine token even when prefixed.** The nastiest case is a
   prefixed name whose full spelling IS a reserved token: `tExt` (t + "Ext") is literally `text`, so
   xTalk evaluates it as the keyword, not a variable. It compiles and silently misbehaves. The checker
   flags any `t/p/s/k`-prefixed name that lowercases to a reserved word; use a different stem. (Watch
   `tSend`: `send` is a reserved command; use `tSender`.)
3. **Prefix conventions:** `t` handler-local, `p` parameter, `s` script/module-local, `k` constant.
   Public API `oxPascalCase`; C ABI (if any) `onx_snake_case`. The public `ox` stem is deliberate: it
   avoids `oxt_`, which would read as "OpenXTalk" (OXT) and confuse, and it is not a reserved word.
4. **Constants must be literal and declared before first use** (OXT resolves a constant by lexical
   position; a forward reference silently evaluates to nothing).
5. **`unsafe ... end unsafe` brackets every foreign call** in LCB; keep all declarations at the **top**
   of a handler (a nested `local` has broken whole-script compilation). Irrelevant to the pure-script
   core, but law the moment a shim appears.
6. **Commands report via `the result`; functions return a value.** Match the API shapes in doc 05: a
   dial that must report success/failure and yield a socket is a command reporting through `the
   result` plus an out variable, or a function returning a small record; pick one shape and hold it.
7. **`itemDelimiter` / `lineDelimiter` are global mutable state**: set them immediately before use.
   The control protocol is CRLF-delimited; set `the lineDelimiter to crlf` right where you parse, and
   restore it, because other code assumes `lf`.
8. **`is a <type>` only accepts** number / integer / boolean / point / rect / date / color. There is
   no `is a string`. To sniff bytes, check length / content, not a type.
9. **A whole `.livecodescript` compiles as a unit:** a syntax error in one handler breaks the whole
   script, and the engine may report it at the first line it tries to run. When "it broke" at an
   unrelated line, suspect a compile error elsewhere in the same script, and re-run the static gate.
10. **Socket ids are the engine's, not yours.** `open socket to host` and `accept connections`
    identify sockets by their host:port string (and a numeric suffix for multiples). Store the exact id
    the engine hands you and use it verbatim in `read` / `write` / `close`; do not reconstruct it.

## Protocol correctness rules (the part a transport most easily gets wrong)

- **Byte-exact framing.** One wrong length prefix, one big- vs little-endian port, or one `char`
  instead of `byte` and the handshake silently corrupts. Build and parse against doc 02 / doc 03 field
  by field, and put the fixed byte strings in a comment next to the code.
- **Resolve names in Tor, never locally.** ATYP=3 for every target. A local `hostNameToAddress` on a
  target is a deanonymizing DNS leak; for a `.onion` it cannot even succeed.
- **Authenticate the control port before the first command**, and prefer SAFECOOKIE over a plaintext
  password. Treat the cookie file path from `PROTOCOLINFO` as authoritative; do not guess it.
- **Verify or pin the onion address.** Connecting to a v3 onion authenticates the far end to its
  ed25519 key; the remaining risk is connecting to the *wrong* address, so pin the contact's address
  (or bind it to a SodiumXT signature) exactly as any secure-messaging layer verifies keys at first
  contact.
- **Negative paths are the tests.** A bad address -> SOCKS REP failure surfaced; a stalled daemon ->
  timeout and clean teardown; a wrong control cookie -> auth failure, not a hang; a duplicate close ->
  no-op. Write these before the happy path.
- **Never present Tor as a total anonymity guarantee.** Traffic correlation, a hostile local daemon,
  guard discovery, and descriptor-timing metadata remain; ship them labeled (doc 01, doc 09).

## As-built notes (v1 implementation)

The library is implemented in one file, `src/onionxt.livecodescript`, and has now RUN ON A REAL OXT
ENGINE against a live tor daemon (and Tor Browser). The core socket behaviours below are confirmed
on-engine; the one path not yet exercised is the optional Mode B tor launch (still `VERIFY:` in the
source). Keep recording on-engine results here as they are learned (that is what this section is for).

Design decisions worth knowing before you touch the code:

- **Everything is a handle plus a callback.** `oxDial` / `oxCreateService` / `oxCreateServiceFromSeed`
  return an integer handle through `the result` immediately and complete asynchronously; the app learns
  the outcome through the status / stream / peer callbacks (signatures in doc 05 and the file header).
  A command that yields a handle returns the integer on success or an `"OnionXT: ..."` string on
  failure, so callers test `the result is an integer`. Inbound (accepted) and outbound (dialed) streams
  are unified into the same tables, so `oxWrite` / `oxCloseStream` / the `"data"` event work identically.
- **The control port is a single-in-flight pipeline.** One command at a time, the rest queued; a
  continuation (run when a reply completes) enqueues the next command while the old label is still in
  flight, and `oxCtlLine` then clears the label and drains the queue. `650` event lines are demuxed from
  command replies by their leading status code. `itemDelimiter` is saved and restored around every use.
- **Crypto is composed, never hand-rolled. OnionXT requires SodiumXT ABI >= 6** for the
  deterministic-onion and SAFECOOKIE paths (the SOCKS dial path, Tor-generated onions, and
  COOKIE/NULL/HASHEDPASSWORD auth need no SodiumXT). Each `sx*` primitive is called DIRECTLY and wrapped
  in `try/catch`: an absent handler raises a catchable execution error, so a missing primitive degrades
  to a clear `"needs SodiumXT sxXxx"` error (or a safe fallback, e.g. SAFECOOKIE -> COOKIE) and the
  return value comes back unambiguously (this replaced an earlier `dispatch function` approach whose
  `it`/`the result` semantics were murky). ABI 6 SHIPPED gaps #1 (`sxSignSeedToExpandedKey`) and #3
  (`sxHmacSha256`); only gap #2 (SHA3-256, offline checksum) stays deferred. base32 and the base64
  encode are pure byte ops; the ed25519 scalar clamp now lives inside SodiumXT's expansion helper.
- **base32 keeps its bit-buffer small, and uses no `^`/`div`/`mod`.** The accumulator is masked to its
  pending bits each step so a 35-byte address never builds a 280-bit integer (precision loss past 2^53).
  It routes integer division/modulo through `oxIntDiv`/`oxIntMod` and powers through `oxPow2` (some OXT
  parsers reject `^` in a compound expression). The KAT in `tools/onion-kat.py` pins the answers.

Confirmed on-engine (promoted from `VERIFY:`):

1. `read ... until crlf` returns the trailing CRLF; `oxStripLineEnd` removes it. Control auth / GETINFO /
   events all parse correctly.
2. `read ... for N with message` delivers exactly N raw bytes on a binary socket (the SOCKS handshake).
3. The no-quantifier `read ... with message oxStreamData` streams available bytes as they arrive and does
   NOT block to EOF - a dialed SOCKS tunnel and an inbound onion HTTP request both deliver chunk by chunk.
4. `accept connections on port` accepts Tor-forwarded loopback connections; the loopback guard now
   accepts every loopback spelling (`127.x` / `::1` / `localhost` / empty), not just "127.0.0.1".
5. Publish -> serve -> remove works; `oxRemoveService` / `oxShutdown` close the listener and DEL_ONION.
6. `dispatch ... to <owner>` resolves app callbacks (onStatus / onPeer / onStreamData) and the `sx*`
   primitives (SAFECOOKIE composes `sxHmacSha256`); an absent handler is a clean miss.
7. `socketError` reaches the library and is surfaced / failed-closed (e.g. 10061 refused, 10013 listen
   denied); `socketClosed` cleans up. (The `socketTimeout`-repeats detail stays the documented
   assumption; no stalled-handshake case was forced.)

Also confirmed on-engine: the **hosting layer** `src/onion-httpd.livecodescript` (public `oxh*`). It
serves HTTP over an onion on OnionXT's accept loop (the composition path, via the new publish-only
`oxPublishService` that ADD_ONIONs without OnionXT taking the socket, plus its `external` teardown guard).
A full static site, a browsable file share (`oxhServeFiles` auto-generates a directory listing from
`the files` / `the folders` - NOT `the detailedFiles`, which is a compile-time "bad factor" on OXT), and
dynamic routes all render in Tor Browser. The **main tabbed demo** (`examples/onionxt-demo.livecodescript`)
now composes this layer for its Service tab too: "Serve page" registers a `/` route (`oxhRoute`) that
replies with the editable HTML, and "Share folder" drops that route (`oxhUnroute`) and calls
`oxhServeFiles`, so the two modes switch live at the SAME onion with no republish (the demo's own inline
serving was retired). `oxhUnroute` was added for exactly this runtime route swap. It ships two ways: as
libraries (`start using` onionxt + onion-httpd) and as paste-and-run standalones generated by
`tools/build-standalone.py`, which now emits TWO: `examples/onion-httpd/standalone.livecodescript` (the
file-sharing spike) and `examples/onionxt-demo-standalone.livecodescript` (the full tabbed demo, bundling
onionxt + onion-httpd + onionxt-tests + the demo so the About-tab self-test runs with nothing else loaded).
It concatenates the parts and refuses to build on a name collision.

Still `VERIFY:` (not yet exercised):

8. `the processId` / `open process` for the optional Mode B tor launch (the default is assume-running).

New hard-won lessons from bring-up (each cost a real debugging round; mirrored in the README/docs
troubleshooting):

- **An ephemeral `ADD_ONION` service dies with its control connection.** A transient control-socket drop
  (or a reconnect) un-publishes it while its descriptor lingers in the DHT ~3h, so a later visit hits
  `Unable to find any hidden service associated identity key` at rendezvous (an empty response). OnionXT
  now passes `Flags=Detach` by default; teardown still `DEL_ONION`s it.
- **`accept connections on port` sets `the result` on a bind failure - check it.** A reserved or blocked
  local port (Windows `Error 10013` WSAEACCES: Hyper-V / WSL2 / Docker reserve TCP ranges; `10048` is
  in-use) otherwise silently produces an onion whose traffic Tor forwards to a dead port. `oxStartService`
  now fails closed with the error; pick another local port (keep the virtual port 80).
- **`STATUS_CLIENT BOOTSTRAP` events only fire WHILE bootstrapping.** Connecting to a tor already at 100%
  delivers none, so a UI seeded at 0 stays there. Query `GETINFO status/bootstrap-phase` once on connect
  to seed it, then let the events update it.
- **The control port must be enabled explicitly** (`ControlPort` + an auth method in `torrc`): tor opens
  SOCKS by default but no control port, and Tor Browser exposes none. A refused connect is `Error 10061`.

## Git / workflow

- Develop on a per-task branch (e.g. `claude/...`); commit there, open a **draft PR** if none exists.
  Do not push to `main` without explicit permission.
- A `.livecodescript` / `.lcb` change is "done" once `tools/check-livecodescript.py` passes and it has
  had (or is clearly flagged as needing) an on-engine pass against a real tor daemon. A transport
  change is "done" once a two-instance onion round-trip (instance A publishes a service, instance B
  dials it through SOCKS, a sealed payload makes the trip and back) works on the engine.
- A change that adds or touches a C shim bumps its ABI version and `checkABI()` in the same change, and
  if it bundles a native binary, refreshes the committed binary and a `MANIFEST.sha256` in the same
  change (the SodiumXT model).
- A change that needs a new SodiumXT primitive (doc 08) is split: the upstream SodiumXT feature lands
  first (with its own ABI bump and tests), then OnionXT composes it.
- **No em-dashes** in committed prose or docs (house style). Use hyphens, commas, colons, parentheses.
- **Match the surrounding style:** comment the *why*, densely, as the siblings do.
