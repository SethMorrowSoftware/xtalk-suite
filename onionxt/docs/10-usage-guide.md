# 10 - Usage Guide (for any OXT / LiveCode app)

OnionXT is useful to any OpenXTalk / LiveCode app that wants an anonymous socket or a serverless,
self-authenticating inbound address. This is the from-zero guide: how to load the
library, point it at a tor daemon, dial out, publish an onion service, handle the callbacks, compose
SodiumXT for the parts OnionXT deliberately does not do, and read the honesty caveats.

> OnionXT has run on a real OXT engine against a live tor daemon: dialing, control-port SAFECOOKIE auth,
> publishing a v3 onion, serving an inbound request (viewable in Tor Browser), and bootstrap are all
> confirmed. The optional Mode B tor launch is the one path not yet exercised. If something misbehaves,
> the [Troubleshooting](../README.md#troubleshooting) section covers the failure modes seen during bring-up.

## 1. Start a tor daemon

OnionXT talks to a locally-running tor; it does not embed or ship one. Any of these works:

- **Tor Browser** - SOCKS on `127.0.0.1:9150`. Note it does **not** expose a control port by default, so
  the Service/onion features are unavailable until you enable one (control `9151`).
- **System tor** (a package on Linux/macOS, a Windows service, or the Tor Expert Bundle `tor.exe`) with
  the bring-up `torrc` below.

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

**The key distinction:** tor opens the **SOCKS** port by default, but it does **not** open a **control**
port unless you ask for one. So dialing out (section 3) works against a stock tor with zero config, while
publishing an onion service and reading bootstrap/events (section 4) need the control port enabled first.
A refused control connection surfaces as a clear error (on Windows, `Error 10061`, `WSAECONNREFUSED`);
it means nothing is listening on that port, i.e. the control port is not enabled or you have the wrong
port number.

### Enabling the control port

Pick whichever fits how you run tor:

- **Command-line flags (no file to edit).** tor accepts any `torrc` option as a flag, so add:
  ```
  tor --ControlPort 9051 --CookieAuthentication 1
  ```
  (append these to your launch shortcut/script/command), then restart tor.
- **A `torrc` file (persistent).** Put the three lines above in a plain-text file named exactly `torrc`
  (no extension; in Notepad, save with *Save as type: All Files* and the name in quotes), then launch
  `tor -f /path/to/torrc`. Typical default locations: Linux `/etc/tor/torrc`; macOS Homebrew
  `/opt/homebrew/etc/tor/torrc` (Intel `/usr/local/etc/tor/torrc`); Windows `%APPDATA%\tor\torrc` or
  next to `tor.exe`.

**Verify it took.** After restarting, tor's log gains a second listener line next to the SOCKS one:

```
[notice] Opening Socks listener on 127.0.0.1:9050
[notice] Opening Control listener on 127.0.0.1:9051      <- this line is the proof
```

Prefer **cookie auth** (`CookieAuthentication 1`) over `HashedControlPassword` for local use: tor writes a
`control_auth_cookie` file in its `DataDirectory`, and OnionXT finds it automatically (it asks tor
`PROTOCOLINFO` for the path and does SAFECOOKIE auth, so you never hand a password to the app). Keep the
control port on `127.0.0.1` only; never bind it to a routable address.

## 2. Load the library

Put `onionxt.livecodescript` in the message path so its `ox*` handlers resolve, for example:

```
start using stack "onionxt"          -- if you wrap the script in a stack
-- or insert the script of the library into the back / a library stack
```

If you also want deterministic onion addresses, SAFECOOKIE control auth, or offline address validation,
load **SodiumXT** the same way (**ABI >= 6** for the deterministic-onion and SAFECOOKIE paths): OnionXT
composes its `sx*` primitives and degrades to a clear error when one is missing (see section 7). Tell OnionXT which object your callbacks live in:

```
oxSetCallbackOwner the long id of me
```

(If you skip this, OnionXT dispatches callbacks to the topStack, which is usually but not always your
app's stack.)

## 3. Dial a host through Tor (outbound)

`oxDial` reports a stream handle immediately; the SOCKS handshake finishes asynchronously and your
stream callback receives `"open"` (or `"error"`). The far end never learns your IP, and the name is
resolved inside Tor (ATYP=3), never by a local DNS lookup.

```
local sStream

on connectOut
   oxSetSocksPort 9050                      -- 9150 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxDial "example.onion", 80               -- a .onion or a clearnet name
   put the result into sStream
   if sStream is not an integer then
      answer "Dial failed:" && sStream      -- a mapped SOCKS error string
      exit connectOut
   end if
   oxSetStreamCallback sStream, "onStream"
end connectOut

on onStream pStream, pEvent, pData
   if pEvent is "open" then
      -- The tunnel is live. OnionXT does not encrypt: seal with SodiumXT first
      -- if you need confidentiality/integrity. textEncode before writing text.
      oxWrite pStream, textEncode("hello" & numToChar(10), "UTF-8")
   else if pEvent is "data" then
      put pData after field "log"            -- your protocol frames the bytes
   else if pEvent is "closed" then
      put "-- closed --" & return after field "log"
   else if pEvent is "error" then
      answer "Stream error:" && pData        -- already torn down; fail closed
   end if
end onStream
```

Close a stream you are done with (idempotent): `oxCloseStream sStream`.

## 4. Publish an onion service (inbound)

Being reachable needs the control port. `oxConnectControl` connects and authenticates asynchronously;
watch the status callback for `"control","authenticated"`, then publish. OnionXT starts the loopback
listener before `ADD_ONION`, so a peer that connects the instant the descriptor publishes is answered.

```
local sService

on goOnline
   oxSetControlPort 9051                     -- 9151 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback "onPeer"
   oxConnectControl                          -- completes via onStatus
end goOnline

on onStatus pKind, pInfo
   if pKind is "control" and pInfo is "authenticated" then
      oxCreateService 80, 8080               -- virtual port 80 -> loopback 8080
      put the result into sService
   else if pKind is "service" then
      put "Reachable at" && pInfo into field "myAddress"   -- <56>.onion
   else if pKind is "serviceReady" then
      -- The descriptor uploaded; the address is now reachable from the network.
   else if pKind is "bootstrap" then
      set the label of this stack to "Tor" && pInfo & "%"  -- coalesced to ~4 Hz
   end if
end onStatus

on onPeer pStream, pService, pPeerAddr
   -- A remote peer reached your onion. pStream is a fresh inbound stream handle
   -- that behaves exactly like a dialed one; register a callback and reply.
   oxSetStreamCallback pStream, "onPeerStream"
end onPeer

on onPeerStream pStream, pEvent, pData
   if pEvent is "data" then
      oxWrite pStream, pData                  -- echo (seal with SodiumXT in real use)
   end if
end onPeerStream
```

Remove a service (idempotent): `oxRemoveService sService`.

## 5. Deterministic, reproducible addresses

`oxCreateService` lets Tor pick a random key. For an address that survives a reinstall and doubles as a
published identity key, derive it from a 32-byte seed (composes SodiumXT; see section 7):

```
oxCreateServiceFromSeed tSeed, 80, 8080      -- same seed -> same .onion, always
```

And convert between an address and its ed25519 public key (base32 is pure; the checksum needs SodiumXT
SHA3-256, so `oxAddressFromPublicKey` returns a clear error if that primitive is absent):

```
put oxPublicKeyFromAddress("....onion") into tPubKey   -- 32 bytes, no crypto needed
put oxAddressFromPublicKey(tPubKey) into tAddress       -- needs sxSha3_256
if oxIsValidAddress(tPasted) then ...                   -- structural, + checksum if available
```

## 6. Shutdown

There is no deterministic unload hook in OXT, so free what you opened, for example on `closeStack`.
`oxShutdown` closes every stream, removes every service, and disconnects control, and is safe to call
twice:

```
on closeStack
   oxShutdown
end closeStack
```

## 7. What OnionXT does NOT do (compose SodiumXT)

OnionXT is a transport and a naming layer. It adds **no cryptography**. The bytes it carries are
protected only if you sealed them with SodiumXT before `oxWrite` and open them after the `"data"`
event. A few OnionXT features compose SodiumXT primitives and degrade to a clear error string when the
primitive is missing (see docs/08); check availability with:

```
put oxTransportInfo() into tInfo            -- an array of capability flags
-- tInfo["safeCookieAuth"]     needs sxHmacSha256 + sxRandomBytes  (SodiumXT ABI >= 6)
-- tInfo["deterministicOnion"] needs sxSignSeedToExpandedKey       (SodiumXT ABI >= 6)
-- tInfo["offlineAddress"]     needs sxSha3_256                    (deferred; libsodium has no SHA-3)
```

When a primitive is absent, OnionXT falls back where it safely can (SAFECOOKIE -> COOKIE control auth,
for instance) and otherwise returns `"OnionXT: ... needs SodiumXT sxXxx (see docs/08)"` rather than
hand-rolling a hash.

## 8. Honesty caveats (read before you ship)

- **Tor is not total anonymity.** It defends the network path against a non-global adversary. Traffic
  correlation by a global passive adversary, a compromised local tor daemon, and descriptor/activity
  timing all remain (docs/01, docs/09). Say "IP-anonymous against a non-global adversary," not
  "untraceable."
- **The address authenticates the key, not the person.** Reaching `<56>.onion` proves you reached the
  holder of that ed25519 key, but if you were tricked into using the wrong address, Tor faithfully
  connects you to the attacker. Pin or verify the address (bind it into a SodiumXT signature at first
  contact) exactly as any secure-messaging layer verifies keys at first contact.
- **Seal your payload.** OnionXT moves bytes; confidentiality, integrity, and replay protection are
  SodiumXT's job and must be done.
- **Bootstrapping is slow and visible.** A cold tor takes tens of seconds; an onion service takes
  seconds more to publish. Surface progress from the status callback; never freeze the UI.

## 9. Callback and error reference

| Callback | Signature | Delivered when |
|---|---|---|
| status | `pKind, pInfo` | control state, bootstrap %, service address/ready, raw events |
| stream | `pStream, pEvent, pData` | `open` / `data` / `closed` / `error` on a dialed or inbound stream |
| peer   | `pStream, pService, pPeerAddr` | a remote peer connected to a published service |

Commands that yield a handle (`oxDial`, `oxCreateService`, `oxCreateServiceFromSeed`) report the integer
handle through `the result` on success, or a human-readable `"OnionXT: ..."` string on failure; test
`the result is an integer`. Other commands report empty on success or an error string on failure. Every
wire error fails closed and tears the resource down; there is no silent fallback to an unproxied or
unauthenticated path.
