# 05 - The Relay Client (nxr*)

> STATUS: verified statically; needs an OXT pass + a live-relay pass. Nothing in
> `src/nostr-relay.livecodescript` has run on a real engine. The ws:// path uses
> `open socket` exactly as OnionXT's engine-proven SOCKS client does; the wss://
> path uses `open secure socket`, which NOTHING in this suite has ever exercised.
> The full VERIFY list is at the end of this document.

The relay client is the stateful half of NostrXT: an RFC 6455 websocket client over
engine sockets that speaks the NIP-01 relay protocol. It COMPOSES the pure-compute
core (`src/nostrxt.livecodescript` does the url parsing, handshake derivation,
frame encode/decode, message build/parse, and event verification); this file owns
only sockets, buffers and handles. Load the core first.

**The two-file split is load-bearing** (the onion-httpd precedent): this layer
defines the engine's `socketError` / `socketClosed` / `socketTimeout` handlers,
which the embedded OnionXT layer also defines, and the suite-paste generator
refuses - as it must - an assembly defining one handler twice. So the relay layer
is deliberately NOT in the suite paste; it ships in the demo embed, and its
offline paths run as probe-guarded harness sections that SKIP in the paste.

## The state machine

```
nxrConnect
   |            TCP (or TLS) connects; engine sends nxrWsOpened
connecting  ------------------------------------------------------+
   |                                                              |
handshake      the upgrade request is written; the 101 response   |
   |           and Sec-WebSocket-Accept echo validate             |
   |                                                              |
open           frames flow; REQ/EVENT/AUTH out, the relay         |
   |           protocol in; ping answered, close echoed           |
   |                                                              |
closing        a close frame arrived; one close echoed back       |
   |                                                              |
gone           torn down: socket closed, tables cleared -----------+
               (any failure at any stage jumps straight here)
```

`nxrConnect` returns an integer relay handle through `the result` immediately (so
callers test `the result is an integer`); everything after that is asynchronous
and arrives through the callback. `nxrState` reports the current state, and
`"unknown"` for a handle that is gone or never existed - a stale handle into any
nxr* verb is a clean refusal or a clean no-op, never a crash.

A watchdog guards the whole left edge: a handshake that has not reached `open`
within the deadline (`kNxrHandshakeTimeout`, 20 seconds) fails closed, because a
stalled peer accepts TCP and then hangs, and timeouts are mandatory (the OnionXT
socket rules, inherited whole).

## The RFC 6455 pieces

The pure math lives in the core (`nxWs*`); this layer drives it:

- **Upgrade request** (`nxWsHandshakeRequest`): `GET <path> HTTP/1.1` with `Host`
  (port included only when not 80/443, as section 4.1 asks of a client),
  `Upgrade: websocket`, `Connection: Upgrade`, a fresh 16-random-byte
  `Sec-WebSocket-Key`, and `Sec-WebSocket-Version: 13`. CRLF line endings, blank
  line terminated.
- **Accept validation** (`nxWsAcceptFor`): the server must echo
  `base64(SHA-1(key || GUID))`. The status line must contain ` 101 ` and the
  accept must match BYTE-EXACT (`is` folds case and the accept is base64, so the
  compare goes through the byte-exact helper). A relay answering 200 is a web
  page, not a websocket: fail closed. Header names, by contrast, compare
  case-insensitively - HTTP's own rule, the one place the folded compare is the
  correct one.
- **Client masking, always on** (`nxWsFrameEncode`): RFC 6455 requires a client to
  mask every frame; every outbound frame draws a fresh 4-byte mask. The mask
  defends proxy caches, not confidentiality, which is why its randomness may fall
  back to the engine's `random()` when SodiumXT is absent - key material never
  comes through that path (`nxKeyGenerate` refuses outright instead).
- **Frame length forms** (`nxWsFrameDecode`): 7-bit (< 126), 16-bit (prefix 126),
  and 64-bit (prefix 127, high word required zero). Both directions cap at
  `kNxWsMaxFrame` (8 MiB) so a hostile length prefix hits a wall, not memory.
- **Fragmentation reassembly**: a text frame without FIN opens a fragment buffer;
  continuation frames append; FIN delivers the reassembled message. Control frames
  interleave legally mid-fragment. A continuation with nothing to continue, a
  fragmented control frame, reserved bits set (no extension was negotiated), or an
  oversized control frame (> 125 bytes) are all unrecoverable: fail closed, tear
  down.
- **Ping / pong**: an inbound ping is answered with a pong carrying the same
  payload; inbound pongs are ignored. `nxrPing` sends a liveness probe.
- **Close echo**: an inbound close gets one close echoed back (best effort), then
  teardown. An app-initiated `nxrDisconnect` sends close code 1000 first when the
  link is open.

## Buffer caps and fail-closed rules

Two caps, one policy: a peer that streams bytes without ever completing anything
must hit a wall, not exhaust memory.

| Cap | Constant | Value |
|---|---|---|
| single frame | `kNxWsMaxFrame` | 8 MiB |
| receive buffer / fragmented message | `kNxrMaxBuffer` | 16 MiB |

Every wire error - framing violation, cap breach, handshake mismatch, socket error
- fails closed the same way: the `"error"` callback fires with the reason, then
the relay tears down (`"disconnected"` fires once, the socket closes if the engine
still lists it, the tables clear). Teardown is idempotent; `nxrShutdown` closes
every relay and is safe to call twice (there is no deterministic unload hook in
OXT, so the app frees what it opens, for example on `closeStack`). An UNPARSEABLE
relay message, by contrast, is surfaced as a `"notice"` rather than a teardown:
the app learns its relay is misbehaving, and one garbage message does not cost a
connection that is otherwise framing correctly.

## The callback contract

`nxrSetCallback pRelay, pHandlerName` registers a handler per relay; it is
dispatched (try-guarded; a missing handler is a clean no-op) to the owner set by
`nxrInit` (default: the topStack) as:

```
<handler> pRelay, pKind, pArgOne, pArgTwo
  pKind = "open"          handshake complete; the relay is usable
  pKind = "event"         pArgOne = subscription id, pArgTwo = the raw
                          event JSON. VERIFIED (id + signature) before
                          delivery unless nxrSetVerify turned that off.
  pKind = "invalid"       pArgOne = subscription id, pArgTwo = why the
                          event was refused (failed verify, or CoinXT
                          absent while verification is on - fail closed)
  pKind = "eose"          pArgOne = subscription id
  pKind = "ok"            pArgOne = event id, pArgTwo = "true" or
                          "false", then a tab, then the relay's reason
  pKind = "closed"        pArgOne = subscription id, pArgTwo = reason
  pKind = "notice"        pArgOne = the notice text
  pKind = "auth"          pArgOne = the NIP-42 challenge (also kept for
                          nxrChallenge; answer with nxAuthBuild +
                          nxEventSign + nxrAuth)
  pKind = "error"         pArgOne = the failure; the relay is torn down
  pKind = "disconnected"  pArgOne = the reason; the relay is gone
```

(That block is the contract verbatim from `src/nostr-relay.livecodescript`'s
header; the header is authoritative if the two ever disagree.) The dispatch is
try-guarded in BOTH directions on purpose: a throwing app handler must not break
the socket state machine, so the exception is swallowed - the app broke, the
transport must not.

### Verification is ON by default, and "invalid" means exactly this

A new relay handle verifies every inbound event (rule 2 of this member: verify,
then trust - see `01-protocol-model.md`). An `"event"` callback therefore means:
the event parsed, its id recomputed from its fields through the canonical
serializer, and its BIP-340 signature verified. Anything less arrives as
`"invalid"` with the subscription id and the reason - including the fail-closed
case where CoinXT is absent while verification is on: no crypto means no
verification means NO events delivered as trusted, never unverified events
delivered quietly. `nxrSetVerify pRelay, false` is the per-relay, eyes-open opt
out for an app that wants raw delivery and does its own checking.

## The NIP-42 auth flow

A relay wanting authentication sends `["AUTH", <challenge>]` at a time of its
choosing. The flow through this member:

1. The relay layer captures the challenge (readable later via `nxrChallenge`) and
   fires the `"auth"` callback with it.
2. The app builds the kind 22242 event: `nxAuthBuild(relayUrl, challenge)` - both
   the relay url and the challenge go into tags, which is what the relay checks.
3. The app signs it: `nxEventSign(tEvent, tSeckeyHex, empty)`.
4. The app answers: `nxrAuth pRelay, tSignedEvent`. The core refuses to wrap an
   unsigned event or a non-22242 event, so a broken flow fails at the client, with
   a reason, before a malformed AUTH reaches the wire.

The relay's verdict comes back as an `"ok"` callback keyed by the auth event's id,
like any publish; a relay that gates a subscription behind auth says so with a
`"closed"` callback whose reason starts `auth-required:`.

## The socket-message pass-through rule

`socketError`, `socketClosed` and `socketTimeout` are the ENGINE's names, delivered
to every socket user in a stack; they are the one part of any socket library's
surface an unrelated script can intercept by accident. This layer acts ONLY on
socket ids it owns (its ids carry a `|nxr<handle>` suffix and map through its own
table) and **passes** everything else, exactly as the family rule requires -
OnionXT defines the same three handlers, and both layers ship in the same demos.

Why swallowing one is a SILENT HANG, not an error: a failed dial whose
`socketError` was eaten never reports; a closed stream whose `socketClosed` was
eaten never delivers `closed`; a stalled handshake whose `socketTimeout` was eaten
never times out. Nothing throws, nothing logs - the state machine upstream simply
waits forever for a message that was consumed downstream. No gate can see it
(the suite's engine notes carry the class; two shipping apps re-derived the guard
independently before it became a written family rule). `socketTimeout` has one
subtlety of its own: it REPEATS while a read is pending, so this layer treats it
as fatal only during the handshake - on an open relay, an idle read timing out is
normal and is deliberately ignored.

## ws:// vs wss://, honestly

- **ws://** (`open socket`): every idiom on this path - async open with a message,
  the one persistent `read ... with message`, short reads reassembled by the
  framing layer, named socket ids stored verbatim - is the shape OnionXT proved on
  a real engine against a live tor daemon. That is evidence the IDIOMS work, not
  that this file does: the label stays "needs an OXT pass + a live-relay pass".
- **wss://** (`open secure socket`): THE open transport question. Nothing in this
  suite has ever opened a secure socket, and the suite's engine notes
  (`OXT-ENGINE-NOTES.md` under the repository root's `docs/`) have no entry on TLS
  sockets - so certificate verification behaviour, TLS version support, SNI, and
  how a TLS failure is delivered (a `socketError`? which text?) are all unmeasured
  engine questions. The code is written on the assumption that failure arrives as
  a `socketError` message, like the plain form, and says VERIFY at the call site.
  Most public relays are wss-only, so the first live-relay pass will meet this
  question immediately; whatever the engine actually does must be recorded in the
  suite engine notes, and this document updated, before any wss claim upgrades.
- A **.onion relay** over OnionXT's transport seam is the future third form (the
  anonymity path, `01-protocol-model.md`); it is a composition plan, not code.

## The engine-behaviour VERIFY list

Everything socket-related here is engine-unproven; these are the specific claims
an OXT pass must confirm or correct (record results in the suite engine notes and
promote or fix the labels in the source):

1. `open socket to <host:port|name> with message` connects asynchronously and
   fires the message; failure arrives as `socketError`. (OnionXT-proven idiom;
   unproven in this file's hands.)
2. `open secure socket` - all of it: whether certificates verify by default,
   against what store, how failure is delivered, which TLS versions negotiate.
   Nothing in the tree has an answer.
3. The persistent no-quantifier `read from socket ... with message` streams bytes
   as they arrive, chunk by chunk, without blocking to EOF (OnionXT-proven on a
   SOCKS tunnel; unproven on a websocket byte stream).
4. `socketTimeout` repeats while a read is pending (documented assumption,
   inherited from OnionXT, where it also remains unforced).
5. `the socketTimeoutInterval` this layer sets at connect time is an ENGINE-GLOBAL
   property: whether (and how much) it disturbs another library's sockets in the
   same app is an open question - assume it does until measured, and note that
   OnionXT sets the same property around its own handshakes.
6. `base64Encode`'s exact line-wrap behaviour (`nxB64Encode` strips both break
   bytes defensively; the wrap width and presence on-engine are unmeasured).
7. `sha1Digest` produces the RFC accept value on-engine (it is the one
   engine-proven builtin hash in this tree - riptide relies on it - but not in
   this composition).
8. The close handshake against a real relay: whether the engine delivers the
   final `socketClosed` before or after the echoed close frame flushes, and
   whether writes to a closing socket error or vanish.
9. The whole NIP-42 flow against a relay that actually demands auth, and the
   `"ok"` / `"closed"` reason texts real relays send.

Until every line above has met an engine, the honest summary of this document is
its status line: verified statically; needs an OXT pass + a live-relay pass.
