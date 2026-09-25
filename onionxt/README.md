# OnionXT

**Tor transport and self-authenticating rendezvous for OpenXTalk (OXT) / the xTalk family.**

OnionXT gives xTalk apps three things by talking to a **locally running Tor daemon**:

1. **IP anonymity for any TCP stream.** Dial out through Tor's SOCKS5 proxy: the far end never learns
   your IP address, and you never learn theirs ([docs/02](docs/02-socks5-client.md)).
2. **Self-authenticating rendezvous.** Create and reach **v3 onion services**, whose address *is* an
   ed25519 public key: reaching `<56-char-base32>.onion` proves you reached the holder of that key, with
   no certificate authority, no DNS and no hijackable key exchange ([docs/03](docs/03-control-port.md),
   [docs/04](docs/04-onion-rendezvous.md)).
3. **Hosting.** The companion `onion-httpd` layer (`oxh*`) serves static sites, a browsable file share
   or dynamic routes over an onion, with no web server and no port forwarding
   ([examples/onion-httpd/](examples/onion-httpd/)).

```
   tor daemon (Tor Browser, a system tor, or a launched binary)
      |  127.0.0.1:9050  SOCKS5 proxy   (outbound: dial a .onion or clearnet host)
      |  127.0.0.1:9051  control port   (inbound: ADD_ONION, events, bootstrap)
      v
   OnionXT (ox*)   src/onionxt.livecodescript
      |- oxDial           -> SOCKS5 state machine (RFC 1928) over an engine socket
      |- oxCreateService  -> control-protocol state machine over an engine socket
      |- accept loop on 127.0.0.1:<local>, where Tor forwards inbound onion traffic -> onPeer
            +--> composes SodiumXT (sx*) for payload sealing and deterministic onion keys
            +--> exposes a pluggable transport seam, oxTransport* (docs/06)
            +--> onion-httpd (oxh*) serves HTTP on that loop: sites, file shares, routes
```

The tor daemon is a separate process: OnionXT never routes, never processes onion layers, and touches
the network only through the daemon's loopback ports. It is **script, not a native binding**: the
engine already has `open socket`, `read from socket ... with message`, `write to socket` and `accept
connections`, SOCKS5 is a few fixed byte sequences and the control protocol is line text, so a C binding
would add a build matrix, an ABI surface and a bundling problem for no gain.

## What OnionXT is NOT

- **It is not Tor, and it does not bundle Tor.** Launching a tor binary (Mode B,
  [docs/07](docs/07-tor-lifecycle.md)) is an optional convenience, never a requirement.
- **It adds no cryptography.** Identity, the onion-key expansion, SAFECOOKIE HMAC and payload sealing
  are SodiumXT calls: **SodiumXT ABI >= 6** for deterministic onions and SAFECOOKIE (ABI 7 for offline
  address checksums). Dialing and Tor-generated onions need no SodiumXT.
- **It is not an anonymity guarantee by itself.** Tor does not defend against a global passive
  adversary doing traffic correlation, a compromised local daemon, or you dialing the wrong onion
  address ([docs/01](docs/01-threat-model.md)).

## Documentation

If you just want to use OnionXT, start with [docs/10-usage-guide.md](docs/10-usage-guide.md).
[CLAUDE.md](CLAUDE.md) holds the rules, gotchas, as-built decisions and the engine evidence ledger;
suite-wide documents are at https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md.

| Document | What it is |
|---|---|
| [01-threat-model.md](docs/01-threat-model.md) | What Tor plus onion rendezvous buys and does not, the trust boundaries, the deliberate v1 defaults |
| [02-socks5-client.md](docs/02-socks5-client.md) | The outbound path byte for byte: SOCKS5, RFC 1928 plus Tor's extensions |
| [03-control-port.md](docs/03-control-port.md) | The control protocol: auth (incl. SAFECOOKIE), `ADD_ONION` / `DEL_ONION`, events, bootstrap |
| [04-onion-rendezvous.md](docs/04-onion-rendezvous.md) | A v3 address IS an ed25519 key; deterministic onions from a seed; the expanded-key gotcha |
| [05-api-reference.md](docs/05-api-reference.md) | The public `ox*` surface, the handlers the engine calls, the error model |
| [06-transport-integration.md](docs/06-transport-integration.md) | OnionXT as a pluggable transport under a higher-layer protocol |
| [07-tor-lifecycle.md](docs/07-tor-lifecycle.md) | Where the daemon comes from: assume-running (the default) or the optional Mode B launch |
| [08-capabilities-required.md](docs/08-capabilities-required.md) | The SodiumXT primitives OnionXT composes and the ABI each needs |
| [10-usage-guide.md](docs/10-usage-guide.md) | From zero: start tor, load the library, dial, publish, shut down |

## Layout and examples

`src/onionxt.livecodescript` is the transport library (`ox*`) and `src/onion-httpd.livecodescript` the
hosting layer (`oxh*`). `tools/run-gates.sh` runs the static gate, the docs-style gate,
`tools/onion-kat.py --check` (base32, v3 address and seed KATs) and `tools/check-selftest-vectors.py
--check`. `templates/CLAUDE.md` is a carried copy of the family's portable engineering template.

| Example | What it shows |
|---|---|
| `examples/onionxt-demo.livecodescript` | A tabbed, paste-and-run showcase of every public `ox*` feature: connect and bootstrap, dial, HOST (serve an editable page, or share a folder through `onion-httpd`), address and base32 tools, capability flags, and a "Run self-test" button. It carries `onionxt`, `onion-httpd` and `onionxt-tests` between the sentinels `tools/sync-demo-embeds.py` owns: edit `src/`, never inside the sentinels. |
| `examples/onionxt-tests.livecodescript` | The pure, offline `oxSelfTest()` harness: KATs cross-checked against `tools/onion-kat.py`, fail-closed contracts, idempotent teardown. It never attempts a daemon handshake. |
| `examples/onion-httpd/` | The `spike.livecodescript` file-sharing app (paste-and-run, both libraries embedded) and the `oxh*` API reference. |
| `examples/socks-dial/` | The thinnest slice: dial a host through Tor and read the reply. No control port needed. |
| `examples/onion-roundtrip/` | Two instances talk over Tor with no server, sealed by SodiumXT. Not yet run on an engine. |

## Status

**Implemented; the live-Tor core is engine-proven.** Bring-up on a real OXT engine against a system tor
and Tor Browser exercised the SOCKS dial, SAFECOOKIE auth, publishing a v3 onion, inbound accept,
streams both ways and bootstrap, and `oxh*` sites, file shares and routes rendered in Tor Browser. The
offline `oxSelfTest()` ran green folded into every dated suite pass from 2026-08-10 (61 checks on
2026-08-17 and 2026-08-20; 74 and one counted skip on 2026-09-24, Windows, including the three
live-daemon names on their refusal paths and the two SOCKS timeout reasons), and coinxt's wallet,
which carries OnionXT, synced real testnet wallets over Tor through a v3 onion (Esplora on port 80,
Electrum on port 143) on 2026-09-02/03. Still "verified statically; needs an OXT pass + a live-Tor
pass": the optional Mode B launch, four inline `VERIFY` hypotheses, an OnionXT-to-OnionXT dial and the
two-instance round trip, the live negative paths (all but one: a retired v2 onion's mapped REP `0x01`
failed closed in the 2026-09-02 wallet log), the 2026-08-23/24 socket-message changes on a live socket
(the harness's offline half, each named function disowning a foreign socket, ran green on 2026-09-24),
and the 2026-09-09 `oxWrite` error return and callback pins. `bash tools/run-gates.sh` runs on every
push (the generated `.github/workflows/gates.yml` here, and the suite's `build-all.sh --gates`).

## Troubleshooting

The failure modes a first setup hits (codes are the Windows Winsock names).

### The control port refuses the connection (`Error 10061` / `WSAECONNREFUSED` / "connection refused")

Nothing is listening: tor opens SOCKS by default but **not a control port**, and **Tor Browser exposes
none**. Add `ControlPort 9051` and `CookieAuthentication 1` to your `torrc` (or pass
`tor --ControlPort 9051 --CookieAuthentication 1`) and restart; the log gains `Opening Control listener
on 127.0.0.1:9051`. Prefer cookie auth (OnionXT reads the cookie itself). System tor is SOCKS `9050` /
control `9051`; Tor Browser is SOCKS `9150`. Walkthrough:
[docs/10-usage-guide.md](docs/10-usage-guide.md#1-start-a-tor-daemon).

### Publishing fails to listen (`cannot listen on 127.0.0.1:<port>` / `Error 10013` or `10048`)

The loopback port Tor forwards to could not be bound. `10013` (`WSAEACCES`): the port is **reserved or
blocked** (Hyper-V / WSL2 / Docker Desktop reserve TCP ranges and `8080` is a frequent casualty; list
them with admin `netsh int ipv4 show excludedportrange protocol=tcp`). `10048` (`WSAEADDRINUSE`):
another process, often a leftover instance, holds it. Choose a **different local port** (`8090`,
`9099`) and keep the **virtual port at 80**. OnionXT fails closed rather than publish an onion that
forwards to a dead port.

### The onion publishes but Tor Browser shows `ERR_EMPTY_RESPONSE`

Check: **is the address fresh?** (a descriptor lingers ~3 hours after its service is gone; publish
again); **did the listen succeed?** (see above); **is the app still running?** (it holds the loopback
listener, even with `Flags=Detach`). A service-side tor logging `Unable to find any hidden service
associated identity key ... on rendezvous circuit` means "descriptor cached, service gone": republish.

### The onion is "not found" or will not connect at all

The descriptor has not published yet: a cold tor takes tens of seconds to bootstrap, a service seconds
more after `ADD_ONION`. Wait for the demo's green **"reachable"** status (`HS_DESC UPLOADED`).

### A dial fails with a SOCKS error

Tor's extended errors (`0xF0`-`0xF7`) map to clear messages (descriptor not found, rendezvous failed,
missing client auth, bad address...); the usual cause is an offline or mistyped `.onion`. A refused
SOCKS port means tor is not running there (`9050`, or `9150` for Tor Browser).

### Deterministic onions or SAFECOOKIE auth report "needs SodiumXT ..."

Load **SodiumXT ABI >= 6** (`sxSignSeedToExpandedKey`, `sxHmacSha256`) alongside OnionXT. Dialing,
Tor-generated onions and COOKIE / NULL / password auth need none. The offline address checksum needs
ABI 7's `sxSha3_256` and otherwise degrades to a clear capability error; tor still authenticates the
onion at connect time ([docs/08](docs/08-capabilities-required.md)).

## House style

ASCII only in `.livecodescript` / `.lcb`; no em-dashes or curly quotes anywhere (curly quotes fail OXT
compilation). Comment the *why*, densely. Enforced by `tools/run-gates.sh`.

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
