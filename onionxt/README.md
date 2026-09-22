# OnionXT

**Tor transport and self-authenticating rendezvous for OpenXTalk (OXT) / the xTalk family.**

OnionXT gives xTalk apps two things by talking to a **locally-running Tor daemon** (it does not
embed or ship Tor):

1. **IP anonymity for any TCP stream** - dial out through Tor's SOCKS5 proxy, so a peer, a tracker,
   a broker, or a server never learns your IP address, and you never learn theirs.
2. **Self-authenticating rendezvous** - create and reach **v3 onion services**, whose address *is*
   an ed25519 public key. Connecting to `<56-char-base32>.onion` cryptographically proves you
   reached the holder of that key, with no certificate authority, no DNS, and no key-distribution
   step that a man-in-the-middle can hijack.
3. **Hosting** - the companion `onion-httpd` layer serves HTTP over an onion (static sites, a
   browsable file share, or dynamic routes) from an OXT app, with no web server, no hosting, and no
   port forwarding. See [src/onion-httpd.livecodescript](src/onion-httpd.livecodescript) and
   [examples/onion-httpd/](examples/onion-httpd/).

```
   tor daemon (already running: Tor Browser, system tor, or a bundled binary)
      |  127.0.0.1:9050  SOCKS5 proxy        (outbound: dial a .onion or clearnet host)
      |  127.0.0.1:9051  control port         (inbound: ADD_ONION, events, bootstrap)
      v
   OnionXT (ox*)   src/onionxt.livecodescript
      |- speaks SOCKS5 (RFC 1928) over an engine socket        -> dial
      |- speaks the Tor control protocol over an engine socket -> publish an onion service
      |- runs a local accept loop that Tor forwards inbound onion traffic to
            |
            +--> composes SodiumXT (sx*) for the payload and for deterministic onion keys
            +--> exposes a pluggable transport seam any app can use (doc 06)
            +--> onion-httpd (oxh*) serves HTTP on that loop: sites, file shares, routes
```

> **Documentation:** [`docs/README.md`](docs/README.md) indexes the numbered 00-10 series. If you just want to use OnionXT, jump straight to [`docs/10-usage-guide.md`](docs/10-usage-guide.md).

## Why this matters

Most peer-to-peer and messaging transports leak IP-layer metadata by default: who talks to whom, from
which address, and the fact and timing of contact. Even when the payload is encrypted, the network still
sees the endpoints. OnionXT closes that gap: route the transport through Tor and swap DHT or direct-peer
rendezvous for onion-service rendezvous, and the IP-layer metadata simply stops being emitted. It is
useful on its own (any xTalk app that wants an anonymous socket or a serverless, self-authenticating
inbound address), and it drops in as a metadata-privacy transport under any higher-layer secure-comms
protocol (doc 06).

## What OnionXT is NOT

- **It is not Tor, and it does not bundle Tor.** It assumes a tor daemon is reachable on the loopback
  SOCKS and control ports. Launching or bundling a tor binary is an optional convenience layer
  (doc 07), never a requirement, and never a reimplementation of onion routing.
- **It adds no cryptography.** ed25519 identity, the deterministic onion-key expansion, SAFECOOKIE
  HMAC, and the payload sealing are all SodiumXT calls. OnionXT is a transport and a naming layer, not
  a cipher. It requires **SodiumXT ABI >= 6** for the deterministic-onion and SAFECOOKIE paths (dialing
  and Tor-generated onions need no SodiumXT at all).
- **It is not an anonymity guarantee by itself.** Tor defends the network path; it does not defend
  against a global passive adversary doing traffic correlation, against a compromised local daemon,
  or against you connecting to the wrong onion address. See [docs/01-threat-model.md](docs/01-threat-model.md).

## Layout

```
onionxt/                    (the OnionXT member of the xtalk-suite monorepo)
  README.md                 you are here
  CLAUDE.md                 the operational guide + all carried OXT/LCB/FFI lessons (read first)
  IMPLEMENTATION-PLAN.md    the phased build order
  docs/
    00-overview.md          architecture and the composition story
    01-threat-model.md      what Tor buys, what it does not, and the honesty rules
    02-socks5-client.md     the SOCKS5 dial path (RFC 1928 + Tor's extensions), byte for byte
    03-control-port.md      the Tor control protocol: auth, ADD_ONION, events, bootstrap
    04-onion-rendezvous.md  v3 onion == ed25519 pubkey; deterministic onions from a seed
    05-api-reference.md     the public ox* surface
    06-transport-integration.md OnionXT as a pluggable transport for a higher-layer protocol
    07-tor-lifecycle.md     assume-running vs launch-a-bundled-binary; bootstrap UX
    08-capabilities-required.md upstream gaps (ed25519 expansion + HMAC shipped in SodiumXT ABI 6; SHA3-256 shipped in ABI 7)
    09-open-questions.md    the honest to-do list
    10-usage-guide.md       from-zero guide for any OXT app that uses OnionXT
  tools/
    check-livecodescript.py the static gate (carried verbatim from the family)
    check-docs-style.py     the prose house-style gate (no dashes / curly quotes)
    onion-kat.py            known-answer vectors: base32, v3 address, ed25519 seed
                            (the demo and the spike carry their libraries; the
                            suite-wide tools/sync-demo-embeds.py does that now)
    check-selftest-vectors.py
                            re-derives every pinned vector in examples/onionxt-tests
                            against onion-kat.py and the standard library, so a
                            hand-copied literal cannot drift into a test that
                            passes for the wrong value (suite gate; not in ci.yml)
  templates/
    CLAUDE.md               the portable xTalk/LCB engineering template, held
                            byte-identical with coinxt's copy by the suite's
                            tools/check-checker-drift.py
  .github/workflows/ci.yml  the first three gates above, on every push / PR
  src/
    onionxt.livecodescript      the transport library (public ox* handlers)
    onion-httpd.livecodescript  the HTTP hosting layer over the accept loop (oxh*)
  examples/
    socks-dial/             dial a host through Tor and read the reply
    onion-roundtrip/        two instances talk over Tor with no server, sealed by SodiumXT
    onion-httpd/            host a site / a browsable file share over an onion (oxh*):
                            spike.livecodescript, paste-and-run, libraries embedded
    onionxt-demo.livecodescript   interactive tabbed showcase: dial through Tor, HOST over an onion
                                  (serve a page or share a folder, viewable in Tor Browser), address tools.
                                  Paste-and-run: it embeds onionxt + onion-httpd + its own tests
    onionxt-tests.livecodescript  a pure, offline self-test harness (sPass/sFail, KATs)
```

## Status

The library is **implemented and has been brought up on a live tor daemon.**
`src/onionxt.livecodescript` has the full public `ox*` surface (SOCKS5 dial, control-port connect + all
four auth methods, onion services with a loopback accept loop, deterministic-from-seed addresses, base32
and the address<->key mapping, events and bootstrap, idempotent teardown, and the pluggable transport
seam), and adds no cryptography of its own: it composes SodiumXT for every hash / HMAC / signature.

On-engine bring-up against a real tor daemon (and Tor Browser) has exercised the core paths end to end:
dialing through the SOCKS proxy, connecting and authenticating on the control port (SAFECOOKIE),
publishing a v3 onion service, and answering an inbound HTTP request so a published onion renders as a
web page in Tor Browser (once the loopback forward port is one the OS allows binding, see
[Troubleshooting](#troubleshooting)). The pure-compute paths (base32, the v3 address, the ed25519 seed
derivation) are pinned by known-answer vectors in `tools/onion-kat.py`; exactly one behaviour stays
flagged `VERIFY:` in the source: the optional Mode B tor launch (`oxLaunchTor` / `oxStopTor`),
unexercised until a run against a real tor binary. In the xtalk-suite monorepo the suite gate walk
runs every gate this member ships, on every push: the static gate, the house-style docs gate, the KAT
self-check and the harness-vector re-derivation all sit in `tools/build-all.sh --gates`, which is what
`.github/workflows/suite-gates.yml` runs. The member's own workflow runs the first three of those and
is inert here; it fires when OnionXT is worked on in isolation.

New here? Start with [CLAUDE.md](CLAUDE.md), the [usage guide](docs/10-usage-guide.md), the
[Troubleshooting](#troubleshooting) section below, and [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md).

## Troubleshooting

These are the failure modes a first-time setup actually hits (several were found during on-engine
bring-up). The demo surfaces most of them with an actionable message. The raw socket error codes shown
are the Windows Winsock names; other platforms print the text equivalent ("connection refused", etc.).

### The control port refuses the connection (`Error 10061` / `WSAECONNREFUSED` / "connection refused")

Nothing is listening on the control port. tor opens the SOCKS port by default but **not a control port**
unless you ask for one, and **Tor Browser does not expose one at all**. Enable it, then restart tor:

```
ControlPort 9051
CookieAuthentication 1
```

(in your `torrc`, or as flags: `tor --ControlPort 9051 --CookieAuthentication 1`). After restarting,
tor's log should gain `Opening Control listener on 127.0.0.1:9051` beside the SOCKS line. Prefer cookie
auth: OnionXT reads the cookie file automatically, so you never hand it a password. Match the ports:
system tor is SOCKS `9050` / control `9051`; Tor Browser is SOCKS `9150` (no control). Full walkthrough:
[docs/10-usage-guide.md](docs/10-usage-guide.md#1-start-a-tor-daemon).

### Publishing fails to listen (`cannot listen on 127.0.0.1:<port>` / `Error 10013` or `10048`)

The local forward port (the loopback port Tor forwards inbound onion traffic to) could not be bound:

- `Error 10013` (`WSAEACCES`, permission denied): the port is **reserved or blocked by the OS**, not in
  use. On Windows, Hyper-V / WSL2 / Docker Desktop reserve whole TCP port ranges and `8080` is a frequent
  casualty. List the reserved ranges with (admin) `netsh int ipv4 show excludedportrange protocol=tcp`.
- `Error 10048` (`WSAEADDRINUSE`): another process (often a leftover instance) already holds the port.

Fix either by choosing a **different local port** (for example `8090` or `9099`); leave the **virtual
port at 80** so the browser reaches `http://<address>.onion/` with no port. OnionXT fails closed on a
bind error rather than publishing an onion whose traffic Tor would forward to a dead port.

### The onion publishes but Tor Browser shows `ERR_EMPTY_RESPONSE`

The rendezvous reached tor but no data came back. Check, in order:

- **Are you visiting a fresh address?** An onion descriptor lingers in the DHT for ~3 hours after its
  service is gone, so an address from an earlier run still resolves but has no live service. Publish
  again and use the new address.
- **Did the listen actually succeed?** A `cannot listen ...` error at publish (above) means Tor is
  forwarding to a dead local port. Pick a free local port.
- **Is the app still running with the control connection up?** OnionXT publishes with `Flags=Detach` so a
  brief control-connection drop no longer un-publishes the service, but the app process (which holds the
  loopback listener) must stay running while you visit.

The service-side tor logging `Unable to find any hidden service associated identity key ... on
rendezvous circuit` is the exact signature of "descriptor still cached, service gone": republish.

### The onion is "not found" or will not connect at all

The descriptor has not published yet. A cold tor takes tens of seconds to bootstrap (watch the bootstrap
percent), and an onion service takes a few seconds more to upload its descriptor after `ADD_ONION`. Wait
for the demo's green **"reachable"** status (the `HS_DESC UPLOADED` event) before visiting.

### A dial fails with a SOCKS error

Tor's SOCKS extended errors (`0xF0`-`0xF6`) map to clear messages (onion descriptor invalid, rendezvous
failed, missing client auth, bad address, and so on); the usual cause is a `.onion` that is offline or a
mistyped address. A plain "connection refused" on the SOCKS port itself means tor is not running there
(SOCKS is `9050`, Tor Browser `9150`).

### Deterministic onions or SAFECOOKIE auth report "needs SodiumXT ..."

Those paths compose **SodiumXT ABI >= 6** (`sxSignSeedToExpandedKey`, `sxHmacSha256`): load SodiumXT into
the message path alongside OnionXT. Plain dialing, Tor-generated onions, and COOKIE / NULL / password
auth need no SodiumXT. (The offline address checksum composes SodiumXT ABI 7's `sxSha3_256`; against
an older SodiumXT it degrades to a clear capability error, and tor authenticates the onion at connect
time regardless, see [docs/08](docs/08-capabilities-required.md).)

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. These are enforced by `tools/check-livecodescript.py` and
the docs-style CI job, and they are not optional: curly quotes fail OXT compilation outright.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

OnionXT is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`onionxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/OnionXT: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `onionxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port onionxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/onionxt-demo.livecodescript`, `examples/onion-httpd/spike.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/onion-httpd/spike.livecodescript`, `examples/onionxt-demo.livecodescript`.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/onion-httpd/spike.livecodescript` carries `src/onionxt.livecodescript`; `examples/onion-httpd/spike.livecodescript` carries `src/onion-httpd.livecodescript`; `examples/onionxt-demo.livecodescript` carries `src/onionxt.livecodescript`; `examples/onionxt-demo.livecodescript` carries `src/onion-httpd.livecodescript`; `examples/onionxt-demo.livecodescript` carries `examples/onionxt-tests.livecodescript`.
- `tools/check-docs-style.py`, `tools/check-livecodescript.py`, `templates/CLAUDE.md`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What other members carry from this one.** The suite embeds this
member's script into the stacks below, verbatim; a change to it
reaches them when the suite re-runs `tools/sync-demo-embeds.py`, and
is not done until every carrier has been re-run on an engine:

- `coinxt/examples/coin-wallet.livecodescript` in coinxt carries `src/onionxt.livecodescript`.
- `holde-em/src/holdem.livecodescript` in holde-em carries `src/onionxt.livecodescript`.
- `nocloud/src/nocloudquickshare.livecodescript` in nocloud carries `src/onionxt.livecodescript`.
- `riptide/examples/riptide-social.livecodescript` in riptide carries `src/onionxt.livecodescript`.
- `riptide/examples/riptide-social.livecodescript` in riptide carries `src/onion-httpd.livecodescript`.
- the suite's `tests/suite-closing-pass.livecodescript` carries `src/onionxt.livecodescript`.
- `torrentxt/examples/torrent-dht-channels.livecodescript` in torrentxt carries `src/onionxt.livecodescript`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
