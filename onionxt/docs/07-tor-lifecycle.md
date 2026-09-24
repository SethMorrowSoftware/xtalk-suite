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

## Mode B: launch a tor binary (optional; not yet run on an engine)

`oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort` does exactly this, and no more:

1. Writes `<pDataDir>/onionxt-torrc` with `SocksPort`, `ControlPort` (default 9050 / 9051; pass other
   ports, for example 9250 / 9251, beside a running system tor), `CookieAuthentication 1`,
   `DataDirectory <pDataDir>` and `__OwningControllerProcess <pid>` so tor exits with the app (suite
   engine note 6.3).
2. Runs `open process` on `"<tor>" -f "<torrc>"` for read, both paths quoted because spaces in
   "Program Files" or "Application Support" are normal.
3. Returns without waiting for bootstrap; the caller polls `oxConnectControl` / `oxBootstrapProgress`.

`oxStopTor` sends `SIGNAL SHUTDOWN` over the control port only if control is authenticated, then
disconnects. As written, the results of the torrc write and of `open process` are not checked, the
process pipe is never read (tor's own stdout, including its `Bootstrapped 100%` line, is not visible
through OnionXT), and the torrc and `DataDirectory` are not cleaned up. All of Mode B is labelled
"verified statically; needs an OXT pass + a live-Tor pass".

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
