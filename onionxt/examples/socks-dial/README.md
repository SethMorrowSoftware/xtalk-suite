# Example: dial a host through Tor's SOCKS5 proxy

The thinnest OnionXT slice: dial a `.onion` (or clearnet) host through Tor and read the reply. No control
port is needed just to dial.

## Prerequisite

A running tor daemon with a SOCKS proxy on loopback:

- Tor Browser: SOCKS on `127.0.0.1:9150`.
- System tor: SOCKS on `127.0.0.1:9050`, from this `torrc`:

```
SocksPort 9050
```

## Run

1. Load the library into the message path, for example `start using stack "onionxt"`.
2. Open `dial-example.livecodescript` as a card/stack script (it expects a field named `response`).
3. Set the SOCKS port in `onDialClearnet` / `onDialOnion` to match your daemon (9050 or 9150).
4. Trigger `onDialOnion` (or `onDialClearnet`).

The example dials, waits for the `"open"` stream event, writes a minimal HTTP/1.0 request, and appends
each inbound chunk to the `response` field. OnionXT does not encrypt: this raw HTTP is fine for a demo,
but a real protocol should seal its bytes with SodiumXT before `oxWrite`.

## What to notice

- The name is handed to Tor as-is (ATYP=3); OnionXT never does a local DNS lookup, so no address leaks.
- `oxDial` returns a handle immediately; success or failure arrives later on the stream callback.
- A bad or offline `.onion` comes back as a mapped SOCKS error string on the `"error"` event, not a hang.
