# Anonymous transport threat model

**Scope: torrentxt + onionxt + sodiumxt. Audience: anyone deciding whether
Model C's protection is enough for their situation - and anyone writing copy
that claims what it protects.**

> **Status.** The guards described here exist in the built QuickShare code and
> pass the static gates; their *behaviour* - each refusal actually refusing, on
> a real engine against a live daemon - is pending the two-machine pass
> (`docs/OXT-PASS-RUNBOOK.md` item 5). Until that pass, every "defeats" claim in
> this page is design intent, verified statically. And per the plan's section 14
> (item 4), the exact user-facing wording of what "anonymous" promises is
> **owner-sign-off copy**: this page states the facts; the in-app phrasing that
> ships carries Seth's explicit approval, which is still OPEN.

What Model C is and how the built path works is `docs/anon-transport.md`; the
full security analysis it summarizes is `docs/ONIONXT-INTEGRATION-PLAN.md`
section 7. This page organizes the same facts by adversary, because "is it
safe" always means "safe against whom".

## The one-sentence summary

Carried verbatim from the plan (section 7.1), because it is the sentence every
other claim must stay consistent with:

> Model C hides WHERE (both IPs) and, composed with cryptoXT, WHAT and
> authenticates WHO. It does not hide WHEN, HOW MUCH, or THAT-you-use-Tor, and
> plaintext-anon does not authenticate the sender.

## Adversary tiers

"Defeated" below means: by design, assuming the invariants in this page hold;
see the status note. "Passphrase" means the optional cryptoXT layer (Argon2id
key derivation, `crypto_secretstream` file sealing, the sealed verifier in the
share code).

| Adversary | What they can try | What Model C gives you | What they still get |
|---|---|---|---|
| **Wire observer** (your ISP, LAN operator, anyone on-path near either endpoint) | Read or log your traffic; identify who you talk to and what you transfer | Defeated for content and endpoints: they see an encrypted connection into the Tor network, nothing more - no peer IP, no filename, no bytes | THAT you use Tor, when, and roughly how much traffic moved |
| **Malicious peer** (the other endpoint of the transfer) | Learn your IP; on receive, feed you a substituted or tampered file | Your IP: defeated - each side sees only a `.onion` and an onion circuit. Substitution/tampering: defeated only WITH a passphrase (the verifier binds the code to the key; the stream is authenticated per-chunk; a plaintext header on an encrypted-advertised share is refused as a downgrade) | On a plaintext transfer: everything but your IP. The peer necessarily receives the bytes, and a plaintext sender is NOT authenticated - an intercepted code can be answered by an impostor |
| **Malicious relay or exit** (hostile Tor nodes) | Log, tamper, or inject at the exit; correlate at a relay | Exit attacks are structurally irrelevant: onion-to-onion traffic **never uses an exit node** and never leaves Tor. A single relay sees only layer-encrypted cells and one hop's addresses | A relay observes timing and volume of its one hop (feeds the GPA tier below); a hostile guard knows you use Tor |
| **Third-party network participant** (DHT nodes, tracker operators, swarm peers) | Enumerate who shares what; join a swarm to read member IPs | Defeated for the anonymous payload: it never enters the BitTorrent session - no torrent, no info-hash, no DHT entry, no tracker announce, no swarm | The app still runs one DHT-enabled session, so the HOST is a visible DHT node; the hiding is scoped to the anonymous file bytes, not the machine's presence |
| **Global passive adversary** (sees traffic at both endpoints' guards at once) | Correlate a send with a receive by shape | **Out of scope - not defeated.** Tor onion services are not designed to resist a GPA and this design does not claim to | Start time, duration, total byte count, and the steady one-frame-per-tick cadence make a distinctive, matchable flow |

## Residual risks, spelled out

These are the plan's required caveats (sections 7.4-7.6), each carried
verbatim-or-equivalent; a shorter restatement that dropped one would be the
overclaim this page exists to prevent.

- **Traffic correlation.** Bounded script streaming produces a recognizable
  flow: a total close to the plaintext size plus a small constant, a start
  time, a duration, a steady cadence. An adversary watching both ends can
  match them on shape. Padding or jitter would raise the cost but would not
  defeat a GPA, and no such hardening is built or claimed.
- **The local Tor daemon is inside the trust boundary.** OnionXT talks to a
  daemon on 127.0.0.1. That process sees every `.onion` you dial, holds and
  serves your onion-service private keys, and if compromised can impersonate
  your service or de-anonymize you. It does NOT see file plaintext when a
  passphrase is layered on. Loopback only, always: pointing the control port
  at a remote host would hand that host full de-anonymization.
- **Timing and presence.** Publishing an onion service announces reachability:
  anyone holding the address can observe when it comes online. QuickShare
  deliberately mints a fresh random `.onion` per share so no persistent
  presence oracle accumulates; a stable address (the Channels design) trades
  that back for findability, and the plan says so where it makes the trade.
- **Tor use is visible.** Hiding the transfer's endpoints is not hiding the
  fact of Tor. Where using Tor is itself the risk, Model C does not help.
- **Plaintext does not authenticate.** Repeated because it is the one users
  assume wrong: an "anonymous" plaintext transfer hides the route and nothing
  else about the sender. The passphrase layer is what makes the bytes
  tamper-evident and the sender verified.

## The clearnet-mixing trap

The fastest way to lose everything above is to make the same payload available
both anonymously and on the public swarm: a third party correlates the onion
content with the swarm's info-hash and reads the real IP off the DHT. The
design therefore treats anon and clearnet as **mutually exclusive per payload**,
enforced at the code's branch points, not requested of the user (in the
QuickShare path, and - since 2026-08-15 - in the Channels layer too, whose
guards ship in `chPublishActiveFeed`, `chChannelTick` and `chHandleEvent`;
both await the two-machine Tor pass): the anonymous
branch returns before any torrent/DHT call can run, an anonymous transfer is
visibly tagged "via Tor" in the transfers list so a mixed state would be
seen, and no failure path falls back from Tor to the swarm - a refused or
broken anonymous transfer aborts, it does not downgrade. (Plan section 7.3
enumerates the guards; the two-machine pass is what observes them refusing.)

## Open owner decisions that gate wording

Stated as open because they are open (plan section 14); this page must not
quietly resolve them.

1. **The "derivable from the pubkey" claim (14.3) - OPEN.** The Channels
   design wants a channel's `.onion` address derivable from its public key
   alone, which is true only if libtorrent's and libsodium's ed25519
   seed-to-key expansions agree byte-for-byte - an equivalence that has not
   been verified. Until the plan's section 6.1 byte-compare passes on a real
   engine, **no suite document may publish the derivability claim**; the
   shipped fallback if it fails is the feed's `svc=` line. This page
   accordingly says nothing about deriving addresses.
2. **Positioning copy sign-off (14.4) - OPEN.** The in-app wording of what
   "anonymous" promises is user-protective copy carrying explicit owner
   approval before it ships. This page is an input to that sign-off, not the
   sign-off.

(The bundled-tor decision, 14.1, is also open; it shifts the daemon trust
story - a bundled tor is one you ship and update - and is covered in
`docs/anon-transport-onboarding.md`, where it bites.)
