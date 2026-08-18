# Anonymous transfer onboarding

**Scope: torrentxt + onionxt + sodiumxt. Audience: a fresh user, on any desktop
OS, going from nothing to a two-machine anonymous file transfer.**

> **Honesty label, before you invest an evening.** This walkthrough is
> *verified statically; needs the two-machine pass*. The plan's own exit
> criterion for this document (`docs/ONIONXT-INTEGRATION-PLAN.md` section 10,
> Phase 4) is a fresh user on each of macOS, Windows, and Linux completing this
> walkthrough end to end - and that has not happened yet. The steps below are
> what the built code is designed to do; where a step misbehaves, you have
> found exactly the evidence the suite is waiting for - record it
> (`docs/OXT-PASS-RUNBOOK.md`, item 5, says what to capture).

You need **two machines** (not two windows - torrentxt allows one session per
process, and a two-party test on one machine proves much less). Each machine
needs: OpenXTalk, a local Tor daemon, and three suite members. Mobile is
explicitly unsupported - a user-controllable local Tor daemon is not realistic
there, so on iOS/Android the toggle stays disabled with the reason and every
public feature still works.

## Step 1 - a Tor daemon, per platform

The demo needs a local Tor listening on a SOCKS port AND a control port. The
second is the one that trips people: **tor opens SOCKS by default but does NOT
open a control port unless you ask.** The suite ships no Tor daemon - whether
it ever bundles one is an OPEN owner decision (plan section 14, item 1:
document-install versus bundled-tor); until that is decided, installing Tor is
your step, documented here.

Whichever platform, the goal is the same three lines of `torrc` (quoted from
`onionxt/docs/07-tor-lifecycle.md`, the member's engine-passed reference):

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

or, as flags with no file edit: `tor --ControlPort 9051 --CookieAuthentication 1`.
After restarting tor, confirm the proof line in its log before going further:
`[notice] Opening Control listener on 127.0.0.1:9051`.

- **Linux.** `sudo apt install tor` (or your distro's package). SOCKS 9050 is
  on by default; add the `ControlPort` + `CookieAuthentication` lines to
  `/etc/tor/torrc` and `sudo systemctl restart tor`. Cookie auth means the app
  must be able to read tor's cookie file - on Debian/Ubuntu add your user to
  the `debian-tor` group and re-login.
- **macOS.** `brew install tor`, then `brew services start tor`. The torrc is
  `/opt/homebrew/etc/tor/torrc` (Intel Macs: `/usr/local/etc/tor/torrc`); add
  the same lines and restart the service.
- **Windows.** The **Tor Expert Bundle** (a bare `tor.exe` from torproject.org)
  with a `torrc` at `%APPDATA%\tor\torrc` carrying the same lines. Run
  `tor.exe` and leave it running.
- **Tor Browser (any OS) - read this caveat.** Tor Browser is often suggested
  as the zero-config path, and the demo does auto-probe its port pair (SOCKS
  9150, control 9151). But **Tor Browser exposes no control port by default**
  (`docs/OXT-PASS-RUNBOOK.md`, trap 5.3) - you must enable 9151 yourself, at
  which point a standalone tor is usually simpler. Prefer the daemon.

## Step 2 - the extensions

Install order matters only in that sodiumxt underlies the others; the runbook's
section 2.2 is the authoritative dependency graph. On each machine:

1. **sodiumxt** (`org.openxtalk.library.sodium`) - via OXT's
   `Tools > Extension Manager`. Required even for a plaintext anonymous
   transfer: OnionXT builds its onion identities on it.
2. **torrentxt** (`org.openxtalk.library.torrent`) - same way. The QuickShare
   demo is this member's example.
3. **onionxt** - NOT a packaged extension: it is pure LiveCodeScript. Copy
   `onionxt/src/onionxt.livecodescript` into your app (or open it as a stack)
   and `start using` it, per `onionxt/docs/10-usage-guide.md`.

Verify from the message box before continuing: `put sxVersion()`,
`put oxVersion()`, and `put btStartSession()` (a handle greater than 0 - then
`btStopSession` it; a leftover session is the classic trap, runbook 5.1).

## Step 3 - the transfer, machine A to machine B

On BOTH machines: make a new one-card stack, paste
`torrentxt/examples/torrent-quickshare.livecodescript` into the **stack**
script, close and reopen the stack (it will not re-initialize otherwise -
runbook trap 5.2). Watch the pill at the top right:

| Pill | Meaning |
|---|---|
| `Tor: no extension` / `Tor: needs SodiumXT` | Step 2 incomplete on this machine |
| `Tor: no daemon` | Step 1 incomplete - no control port answered on 9051 or 9151 |
| `Tor: connecting NN%` | Daemon reached; Tor is bootstrapping (tens of seconds) |
| `Tor: ready` | Anonymous sends and receives will work |

Wait for `Tor: ready` on both machines. Then:

1. **A:** type a passphrase into the send field. (Optional, but recommended:
   without it your IP is hidden but the sender is not verified and the bytes
   are plaintext at the far end - the demo will say exactly this.)
2. **A:** tick **"Send privately over Tor"** and drop a file on the window.
   The demo encrypts (briefly pausing on a large file), publishes a fresh
   onion service, and - after up to a minute of "Publishing a private Tor
   address..." - shows a share code beginning `BTXTOR1:`.
3. **A:** click Copy; send the code to B over any channel. Tell B the
   passphrase over a DIFFERENT channel. **Keep A's window open** - the service
   and the transfer live in it (and an onion service does not outlive its
   control connection - runbook trap 5.4).
4. **B:** paste the code into "Receive a file", type the passphrase, click
   Download. A wrong passphrase is refused immediately, before any network
   traffic - that is the built-in verifier working, not a failure. A plaintext
   code instead shows a "sender is NOT verified" confirmation you must
   explicitly accept.
5. Both transfer lists show a "via Tor" row with a byte progress bar. When B's
   side completes, the file is decrypted (or moved) into the save folder under
   its real name. Compare checksums across the machines - byte-identical
   delivery is the pass criterion, so actually run `sha256sum` on both.

If a transfer breaks mid-flight it does not resume: fix the cause and start
again from the code (from byte 0). A dropped *folder* on the anonymous path
becomes a browsable `http://<onion>/` page for Tor Browser instead of a code -
that mode is always plaintext, and the demo says so when you drop one.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pill stuck at `Tor: no daemon`; log says no control port answered on 9051 or 9151 | No tor running, or tor running with the control port disabled (the stock default), or you counted on Tor Browser (no control port by default) | Step 1: add `ControlPort 9051` + `CookieAuthentication 1`, restart tor, look for the "Opening Control listener" log line, then close and reopen the stack |
| "Reached Tor but it refused the control connection" (auth failure) | Control port enabled but authentication failing - commonly the app cannot read tor's cookie file | Linux: add your user to the `debian-tor` group and re-login. Or check the torrc really says `CookieAuthentication 1` |
| Pill stuck at `Tor: connecting NN%` and never reaches ready | Bootstrap incomplete: no route to the Tor network - an outbound firewall, captive portal, or a network that blocks Tor | Fix the network first; watch tor's own log for bootstrap progress. Anonymous actions are refused (never queued, never sent clearnet) until the pill says ready |
| Wrong ControlPort configured (e.g. a custom port in torrc) | The demo probes exactly 9051 then 9151 | Move tor to the standard pair - the demo does not take a custom port |
| A's code never appears; "Publishing ... is taking too long" after ~90 s | The onion service descriptor did not upload (weak Tor connectivity; clock skew is a classic Tor culprit) | Check the system clock, let Tor settle, drop the file again - the half-built service was already cleaned up |
| B: "Could not open a Tor connection to that address" | A's window closed (the service died with it), A re-dropped a file (a new share replaces the old service and its code), or B's Tor cannot build the circuit yet | A: re-share, keep the window open, send the NEW code. B: retry after a moment |
| Transfer starts then aborts with a watchdog/idle message | A stalled circuit, or one side went offline mid-transfer | Retry from the code; anonymous transfers restart from byte 0 by design |
| "This share was supposed to be encrypted but arrived unencrypted - do not trust it" | The downgrade refusal firing: the code promised encryption, the stream claimed plaintext | Do exactly what it says - do not trust the file. Re-share; if it recurs, treat the path between you as hostile |
| Firewall software on the machine itself | Loopback (127.0.0.1) filtering breaks the app-to-tor link even when the network is fine | Allow the OXT engine and tor to talk on localhost 9050/9051 (9150/9151) |

Everything in the table fails closed: whatever the anonymous path's state, the
public QuickShare features keep working, and nothing you marked anonymous is
ever quietly sent over the public swarm.

## When you finish

A completed walkthrough on real hardware is precisely runbook item 5. Record
what you ran and saw (the runbook's section 4.7 lists which honesty labels your
evidence flips - including the one at the top of this page), or, if a step
fought you, record that instead: a fresh user failing this document is a
Phase 4 finding, not a user error.
