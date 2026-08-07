# Example: the two-instance onion round trip

The headline milestone (IMPLEMENTATION-PLAN.md phase 4): two OXT instances talk over Tor with no server
and no clearnet. Instance A publishes a v3 onion service and accepts; instance B dials A's `.onion`; a
SodiumXT-sealed message travels B -> A and A -> B; both IPs stay hidden behind Tor.

This example shows the OnionXT surface and the composition story. The sealing calls are SodiumXT (`sx*`)
and are illustrative: OnionXT adds no crypto, it only moves the sealed bytes.

## Prerequisite

A tor daemon with both ports on loopback and cookie auth. Reference `torrc`:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

For Tor Browser use `9150` / `9151` and enable the control port + cookie auth in its config. Load both
`onionxt.livecodescript` and `sodiumxt` into the message path, and set a shared key both instances hold
(in a real app this comes from a key agreement / a pinned contact, not a hardcode).

## Run

1. In instance A, call `startServiceA`. Watch the status label for the bootstrap percent, then read the
   published address from the `myAddress` field once the `"service"` status fires. Wait for
   `"serviceReady"` before telling B the address (the descriptor must upload first).
2. In instance B, call `dialServiceB` with A's address. B seals `"ping"`, dials, and on `"open"` sends
   it; A opens it, seals `"pong:ping"`, and sends it back; B shows the reply.

## What to notice

- Neither instance ever learns the other's IP. B connects to an address that *is* A's ed25519 public
  key, so completing the rendezvous authenticates A for free (pin the address to detect a later swap).
- OnionXT delivers raw bytes; every payload here is sealed and opened with SodiumXT. If you remove the
  sealing, the transport still works but the bytes are unprotected - that is exactly the boundary
  OnionXT draws.
- The inbound stream A gets in `onPeer` behaves identically to the outbound stream B got from `oxDial`.
