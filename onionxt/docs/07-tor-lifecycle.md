# 07 - Tor Lifecycle: Assume-Running vs Launch-a-Binary

OnionXT talks to a tor daemon; it does not embed one. "Where does the daemon come from" has two
answers, and OnionXT supports both without letting the convenient one become a hidden dependency. The
suite decided document-install as the delivery model (decision D-07, 2026-08-27, in the suite's
`docs/OPEN-DECISIONS.md`): Mode A is the product path, Mode B stays optional, and the decision is
revisitable if a consumer app ever targets non-technical users first.

## Mode A: assume a running daemon (the default, the engine-proven path)

The app assumes tor is already reachable on the loopback ports: **Tor Browser** (SOCKS `9150`, and no
control port until you enable one on `9151`), a **system tor** (a Linux/macOS package, a Windows
service, or the Tor Expert Bundle `tor.exe`), or an ops-managed tor. It is the default because it is
the simplest and most testable and keeps OnionXT free of process management. Bring-up `torrc`:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

**tor opens the SOCKS port by default but NOT a control port**, so dialing out works against a stock
daemon while the onion-service features need the control port enabled first. Set it in a `torrc`
(above) or as flags (`tor --ControlPort 9051 --CookieAuthentication 1`), restart tor, and confirm the
log gains `Opening Control listener on 127.0.0.1:9051` next to the SOCKS line. A refused control
connection (on Windows, `Error 10061`) means nothing is listening there. The full step-by-step is in
[10-usage-guide.md](10-usage-guide.md#1-start-a-tor-daemon).

The app should detect the daemon (`oxConnectControl` + `GETINFO version`) and, if it is absent, show a
clear "start Tor / install Tor" message rather than failing obscurely.

## Mode B: launch a tor binary (optional; the launch not yet run on an engine)

`oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort` does exactly this, and no more:

1. Refuses an empty tor path or data directory before touching anything.
2. Writes `<pDataDir>/onionxt-torrc` with `SocksPort`, `ControlPort` (default 9050 / 9051; pass other
   ports, for example 9250 / 9251, beside a running system tor), `CookieAuthentication 1`,
   `DataDirectory <pDataDir>`, `__OwningControllerProcess <pid>` so tor exits with the app (suite
   engine note 6.3), and `Log notice file <pDataDir>/onionxt-tor.log`. If the write reports a failure
   (a missing or read-only directory), it returns an `"OnionXT: ..."` reason and stops.
3. Runs `open process` on `"<tor>" -f "<torrc>"` for read, both paths quoted because spaces in
   "Program Files" or "Application Support" are normal. If `open process` reports a failure, it
   returns an `"OnionXT: ..."` reason and stops.
4. Only then points OnionXT's SOCKS and control ports at the launched tor, and returns empty without
   waiting for bootstrap; the caller polls `oxConnectControl` / `oxBootstrapProgress`. An empty result
   means the engine started the process, not that tor is up: tor can still exit on a port already in
   use.

`oxStopTor` sends `SIGNAL SHUTDOWN` over the control port only if control is authenticated, then
disconnects.

What changed on 2026-09-24, and what did not. Until then the results of the torrc write and of
`open process` were not checked (a torrc that could not be written came back as a clean launch), and
the ports were set before the launch. Whether a wrong tor path is reported at launch at all is the
engine's call: one that forks and then execs may learn of it only when the child exits, after
`oxLaunchTor` has returned. Leg F records what OXT does.

Tor logs to stdout by default, and the process pipe is opened for read and never read, so a
long-running tor could in principle fill the pipe and block (inferred, not observed); the `Log` line
moves tor's notices to the file once tor has read its torrc, so only its first few startup lines
still reach the pipe. That file is also where tor's own `Bootstrapped 100%` line can be read;
OnionXT itself still reads neither the pipe nor the log. Still absent: `close process`, any cleanup of
the torrc, the log or the `DataDirectory`, and a way for `oxStopTor` to stop a child whose control
connection never authenticated. All of Mode B, the 2026-09-24 result checks included, is labelled
"verified statically; needs an OXT pass + a live-Tor pass", except two legs that touch nothing: step
1's refusal (called with both arguments empty) and `oxStopTor` while unauthenticated, which only
disconnects, ran green on an engine on 2026-09-24 (the member harness's sections 3 and 5, in the suite
paste). Nothing was launched or shut down.

Bundling a tor binary is a licensing and size decision (BSD-3, large, per platform, with an update
duty), carries the Tor Project's naming and packaging expectations (never imply endorsement), and does
not move the trusted base (doc 01): a launched tor must be genuine, unmodified and user-replaceable.

## Bootstrap UX (both modes)

- A cold tor takes tens of seconds to bootstrap; an onion service takes seconds more to publish its
  descriptor. Never freeze the UI: read `STATUS_CLIENT BOOTSTRAP PROGRESS=NN` (seeded once with
  `GETINFO status/bootstrap-phase`) and `HS_DESC`, and show progress at <= ~4 Hz.
- Distinguish the states a user cares about: "connecting to Tor," "bootstrapping NN%," "publishing your
  address," "reachable." A stalled bootstrap (blocked network, censored Tor) should time out into a
  clear, actionable message, not an indefinite spinner.
