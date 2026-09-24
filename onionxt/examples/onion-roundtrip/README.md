# Example: the two-instance onion round trip

Two OXT instances talk over Tor with no server and no clearnet. Instance A publishes a v3 onion service
and accepts; instance B dials A's `.onion`; a SodiumXT-sealed message travels B -> A and A -> B; both
IPs stay hidden behind Tor. The sealing calls are SodiumXT (`sx*`) and illustrative: OnionXT adds no
crypto, it only moves the sealed bytes.

**Status: not yet run on an engine** ("verified statically; needs an OXT pass + a live-Tor pass"). It
is the member's open two-instance milestone, tracked in the suite's `docs/WORK-PLAN.md`.

## Prerequisite

A tor daemon with both ports on loopback and cookie auth. Reference `torrc`:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

For Tor Browser use `9150` / `9151` and enable the control port and cookie auth in its config. Load both
`onionxt.livecodescript` and `sodiumxt` into the message path, and set a shared key both instances hold
(in a real app it comes from a key agreement or a pinned contact, never a hardcode). The script writes
to fields named `myAddress` and `state` that it does not create: build them on the host card first.

## Run

1. In instance A, call `startServiceA`. The stack title shows the bootstrap percent. Read the address
   from the `myAddress` field once the `"service"` status fires. Wait for `"serviceReady"` (the
   descriptor must upload first) before giving B the address.
2. In instance B, call `dialServiceB` with A's address. B seals `"ping"`, dials, and on `"open"` sends
   it; A opens it, seals `"pong:ping"`, and sends it back; B shows the reply.

## What to notice

- Neither instance learns the other's IP. B connects to an address that *is* A's ed25519 public key,
  so completing the rendezvous authenticates A for free (pin the address to detect a later swap).
- OnionXT delivers raw bytes; every payload here is sealed and opened with SodiumXT. Remove the sealing
  and the transport still works, but the bytes are unprotected: exactly the boundary OnionXT draws.
- The inbound stream A gets in `onPeer` behaves identically to the outbound stream B got from `oxDial`.
