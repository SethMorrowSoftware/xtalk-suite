# 06 - Using OnionXT as a Pluggable Transport

OnionXT is useful standalone (an anonymous socket, a serverless self-authenticating address), but it is
also designed to slot underneath a higher-layer secure-messaging or peer-to-peer protocol as a
**transport**: the layer that provides rendezvous, dial, listen, and send/recv, while the protocol above
owns envelopes, sessions, and encryption. This document describes the transport seam OnionXT exposes so
any such protocol can plug in.

## The transport seam

A transport-agnostic protocol seals a message (with SodiumXT, say), then hands the ciphertext to a
transport that provides four things: a rendezvous point, the ability to listen / be reachable, the
ability to dial a peer, and a byte pipe. OnionXT provides each:

| The protocol needs | How OnionXT provides it |
|---|---|
| rendezvous point | an onion address derived from an ed25519 identity key (doc 04) |
| listen / be reachable | a published v3 onion service + loopback accept loop |
| dial a peer | `oxDial <peer>.onion` through SOCKS5 |
| send / recv bytes | `oxWrite` / the stream callback |
| identity <-> address | the onion address IS the ed25519 public key (no separate key distribution) |

The thin wrappers `oxTransportDial` and `oxTransportInfo` (doc 05) make this seam explicit: a caller
dials a rendezvous address (a full `.onion`, or a 32-byte ed25519 key / 64-hex string that OnionXT maps
to an address first), and queries which optional capabilities are available so it can negotiate and fall
back visibly rather than silently.

## Rendezvous mapping

- A contact's identity typically already includes an ed25519 signing key. Map that key (or a per-contact
  subkey) to an onion address with `oxAddressFromPublicKey`. The contact publishes a service at the
  matching address with `oxCreateServiceFromSeed`.
- Because the address authenticates the key, **first-contact verification gets stronger**: dialing the
  address and completing the onion rendezvous proves the far end holds the key, closing the active MITM
  that a rendezvous-controlling attacker could otherwise attempt. The protocol should still pin the
  address and bind it into the contact record, so a later address swap is detected.
- For unlinkable, rotating rendezvous, derive an **epoch-scoped** onion key from a shared secret and an
  epoch counter, so the address rotates and a passive observer cannot link epochs. This costs an
  onion-service republish per epoch; treat cadence as a tuning knob (descriptor publication is not free).

## What plugging in gains

- Moves "no IP anonymity by default" and "rendezvous metadata leak" from unsolved to solved at the IP
  layer. Peers no longer exchange IPs; DHT lookups and direct peer links stop leaking the fact and the
  endpoints of contact.
- Keeps working through NAT and hostile networks: onion services need no port forwarding and connect
  outbound only.

## What the protocol above must still do (honesty)

- **Seal everything with SodiumXT (or your own crypto).** OnionXT does not encrypt. Tor protects the
  path; the message-level "right recipient, intact content, no replay" guarantees are the protocol's job.
- **Not claim more than Tor gives.** Traffic correlation, local-daemon trust, and descriptor timing all
  remain (doc 01, doc 09). Onion transport is a strong IP-metadata improvement, not anonymity against a
  global passive adversary.
- **Negotiate, not assume.** If more than one transport is available, advertise which each side speaks
  and negotiate; fall back cleanly when Tor is unavailable, and make the fallback visible (never silently
  downgrade anonymity). `oxTransportInfo` gives the caller the capability flags to make that decision.

This is the composition principle OnionXT runs on: it adds a transport and a naming property, invents no
crypto, and lets the layer above decide when to use it.
