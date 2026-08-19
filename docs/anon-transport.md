# The anonymous transport (Model C)

**Scope: torrentxt + onionxt + sodiumxt. Audience: a suite user deciding whether
(and when) to trust the "Send privately over Tor" toggle.**

> **Status, first.** The QuickShare anonymous path described here is BUILT
> (`torrentxt/examples/torrent-quickshare.livecodescript`) and passes every
> static gate, and the `ox*` surface it drives is the in-repo `onionxt/` member,
> which has its own on-engine pass against a live tor daemon. But the
> COMPOSITION - torrentxt's Tor path end to end, two machines, a real daemon on
> each - has never run. Everything behavioural below is therefore *verified
> statically; needs an OXT + live-Tor pass* (the suite convention), tracked as
> `docs/OXT-PASS-RUNBOOK.md` inventory item 5. This doc says what the code does
> by design; the runbook pass is what will let it say what the code was seen to do.

This page explains the design for a user. The full engineering design - framing,
state machines, edit points, review findings - is
`docs/ONIONXT-INTEGRATION-PLAN.md`; the adversary-by-adversary analysis is
`docs/anon-transport-threat-model.md`; getting from zero to a transfer is
`docs/anon-transport-onboarding.md`.

## What Model C is

QuickShare's normal path is public BitTorrent: the file is seeded as a torrent,
the DHT introduces the two machines, and both IPs are visible to the swarm -
that is how BitTorrent works, and it stays the suite's default. Model C adds a
second, **optional** transport beside it: when the Tor toggle is on, the file's
bytes travel over a Tor **onion-to-onion** stream (OnionXT) and **no torrent is
ever created** for that file - no `btCreateTorrent`, no DHT announce, no
tracker, nothing for the swarm to see. The two paths are mutually exclusive for
a given payload; that exclusivity is the invariant that keeps the word
"anonymous" honest, and it is enforced in code, not advised in a comment.

Onion-to-onion matters: both endpoints are Tor onion services, so the traffic
never touches a Tor exit node and never leaves the Tor network. There is no
exit to trust and no clearnet destination to observe. (The rejected
alternative - torrenting through a SOCKS proxy - fails on both counts and
cannot carry the DHT's UDP at all; the plan's section 7.2 has the full
argument.)

## What it hides

- **Both endpoints' IPs, from each other.** The receiver sees only a `.onion`
  address; the sender sees only an inbound onion circuit. Neither learns the
  other's IP.
- **Both endpoints' IPs, from the network.** No swarm, no tracker, no DHT entry
  carries the file or either address; on-path observers see Tor traffic, not
  endpoints.
- **The file's bytes and name in transit.** The onion circuit is layer-encrypted
  end to end; the filename rides inside the stream, not in any public record.
- **The DHT sees only the public default.** An anonymous transfer adds nothing
  to the DHT. (The app itself still runs one BitTorrent session with DHT
  enabled, so the *host* remains a visible DHT node - the hiding claim is
  scoped to the anonymous file bytes, not to the machine's overall network
  presence.)

## What it does NOT hide

These are the plan's residual risks, stated here so the toggle never
over-promises; the threat-model page carries the per-adversary detail.

- **That you use Tor.** Your ISP or network operator sees a Tor connection.
- **Traffic timing and volume.** A watcher who can see both endpoints' Tor
  traffic at once can correlate a send with a receive by start time, duration,
  total bytes, and cadence. Tor does not resist a global passive adversary,
  and neither does this.
- **The local Tor daemon is trusted.** It sees every `.onion` you dial and
  holds your service keys. A compromised local Tor de-anonymizes you.
- **The sender, on a plaintext transfer.** Tor alone hides the route; it does
  not authenticate who is at the other end. Add a passphrase for that (below).

## How the QuickShare path works today

What follows is the behaviour of the built code, per the status note above.

**Capability probe, fail closed.** At startup the demo probes once for OnionXT
(which itself requires SodiumXT, even for a plaintext transfer) and
connects to the local Tor daemon's control port - stock tor's 9051 first, Tor
Browser's 9151 as a one-shot retry. A live pill reports the state (`Tor: no
extension` / `no daemon` / `connecting NN%` / `ready`), and every anonymous
action re-checks live readiness at the moment of use. Anything missing
disables the toggle with the reason; the public path is never affected, and a
failure never silently falls back to the swarm.

**Sending.** Tick "Send privately over Tor" and drop a file. With a passphrase
set, the file is first encrypted exactly as the public encrypted path does it
(Argon2id key from passphrase + fresh random salt, `crypto_secretstream`
ciphertext), and the *ciphertext* is what streams. The demo then publishes a
**fresh, ephemeral onion service** for this one share - a random key each time,
so shares are unlinkable to each other - and only once Tor confirms the service
descriptor uploaded (up to a minute) does the share code appear:

```
BTXTOR1:<onion-address>:<base64 name>:<base64 salt>:<base64 verifier>
```

The last two fields are empty on a plaintext share. One anonymous share is
active at a time; a new drop replaces the old service.

**Receiving.** Paste a `BTXTOR1:` code. For an encrypted share, the passphrase
is checked **locally, before dialing**, against a small sealed verifier carried
in the code - a wrong passphrase is caught with zero network activity. For a
plaintext code the demo makes you confirm past an explicit warning: your IP is
hidden but the sender is NOT verified, and anyone who intercepts the code could
substitute a file. Only then does it dial the onion and pull the file over a
small framed protocol (a header with the sanitized filename and total size,
64 KiB length-prefixed frames, a zero-length terminator; oversized headers and
frames are rejected before any allocation, and the wire format is pinned by
`torrentxt/tests/onion_frame_golden.py`).

**Downgrade refusal.** If the code advertised encryption (it carried a
verifier) but the stream's header claims plaintext, the transfer is **aborted**:
"This share was supposed to be encrypted but arrived unencrypted - do not trust
it." An attacker who can tamper with the stream cannot quietly strip the
encryption.

**Folders, and the web option.** A dropped *folder* is not framed as a file
stream; it is served as a browsable web page over the onion - the "code" is an
`http://<onion>/` link opened in Tor Browser. Both IPs stay hidden, but a
browser cannot decrypt, so folder serving is always plaintext and the demo says
so. A plaintext single file can likewise opt in to a Tor Browser download link
("Serve as web download"). Do not confuse either with the demo's separate
"Share via web link" mode, which is a *direct clearnet* link and anonymizes
nothing.

**The honest limits.** Throughput is modest by design (bounded 64 KiB frames on
the single script thread, over Tor circuits) and **unmeasured** - no number is
quoted until the two-machine pass measures one. Above 256 MiB the demo warns
that anonymous transfer will be slow and offers the public swarm *with the
explicit caveat that it reveals your IP* - it never downgrades silently. An
interrupted anonymous transfer does not resume; it restarts from byte 0. And
the sender's window must stay open: the service, and the transfer, live in it.

## The Channels layer

The same substrate gives the DHT-Channels demo per-channel anonymous feeds and
file delivery. That layer is **BUILT** (2026-08-15): per-channel onion
services, the signed anon feed, the BTXC/BTXF request layer and onion file
delivery all ship, and like everything in this tree that no engine has run it
is **verified statically; needs an OXT + live-Tor pass**. Its two-machine done
gates are the plan's #32 and #33.

For what the layer IS, see the plan's section 6; for what is built versus
pending at any moment, see the plan's **section 10**, whose Phase 2 and Phase 3
entries carry dated as-built blockquotes.

> **Why this paragraph is dated rather than evergreen.** It used to say the
> layer was "being built in a parallel workstream", and justified carrying no
> status with "a pointer cannot go stale the way a restatement can" - in the
> sentence immediately after a restatement, which then went stale for two days.
> The principle is right and the execution was not: the pointer to section 10 is
> what this page relies on, and any status sentence beside it carries a date so
> a reader can see how old it is.

## What would change this page

The runbook item 5 pass (two machines, live daemons, byte-identical delivery,
packet capture showing onion-only traffic, the passphrase and downgrade
refusals observed). When it lands, the status note at the top flips from
"verified statically" to a dated on-engine record, and a measured throughput
figure can replace "unmeasured". Until then, treat every behavioural sentence
here as design intent that the gates check statically - nothing more.
