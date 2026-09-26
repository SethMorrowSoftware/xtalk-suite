# enetxt

**ENet - reliable-UDP real-time networking - for OpenXTalk / the xTalk family.**
Game-grade many-peer messaging from plain xTalk script: reliable, unreliable-sequenced and
unsequenced delivery on independent channels, sub-frame latency on a LAN, one broadcast to
fan out to every peer. It binds [ENet](https://github.com/lsalzman/enet) (v1.3.18, MIT)
behind a flat `extern "C"` shim with a thin LCB layer on top, the shape of its siblings:

```
ENet v1.3.18 (static)                          sockets + the reliability protocol
   |- C++ shim   src/enet_shim.cpp  ->  enetxt.{so,dll,dylib}   (ABI: enx_*, v2)
        |- LCB binding  src/enet.lcb      (org.openxtalk.library.enet; public en*)
             |- examples/enet-helpers.livecodescript   (the pump)
```

It completes the family's real-time story: **enetxt** for many peers at game cadence where
someone is reachable (LAN, port forward, rented box); **dataChannelXT** for NAT-traversed
pairs and browsers; **TorrentXT** for bulk. The 60000-byte packet budget is the seam: when a
payload stops being a message, move it to torrents.

## What it can do

- **Hosts and peers, not sockets**, with generation-tagged integer handles: a stale handle
  is always a harmless no-op.
- **Three delivery modes per send** - reliable (acked, ordered), unreliable (sequenced,
  droppable), unsequenced (fire-and-forget) - on up to 255 independent channels.
- **One-call fanout**: `enBroadcast` queues one packet to every connected peer.
- **Live stats** in one FFI round trip (`enPeerStatus`: state, RTT, loss, byte counters),
  plus timeouts, ping interval and bandwidth throttles.
- **Pump-driven.** ENet has no threads; the helpers' poll loop IS the transport, so the
  family's rule "never call script from a foreign thread" holds by construction.

## Quick taste

```livecodescript
start using stack "enetHelpers"
put enHostCreateServer("", 27099, 32, 2, 0, 0) into sServer
enStartPolling sServer, the long id of this card, 33   -- the heartbeat

on enetConnect pEvent
   enSendText pEvent["peer"], 0, "welcome!", 0          -- 0 = reliable
end enetConnect

on enetReceive pEvent
   enBroadcast sServer, 0, pEvent["payload"], 0         -- relay to everyone
end enetReceive
```

[docs/getting-started.md](docs/getting-started.md) walks the client side and delivery modes.

## Examples and the self-test

Each is ONE paste-and-run file: paste it into a stack's script and reopen the stack
(opening the file itself builds no window - the suite's engine note 5.5). They carry
`enet-helpers` between sentinels owned by the suite's `tools/sync-demo-embeds.py`, so do not
also `start using` the helpers (a second copy of the pump would sit behind the demo's); edit
the helpers file and re-run that tool, never inside the sentinels.

- **`examples/enet-helpers.livecodescript`** - the pump: `enStartPolling` / `enStopPolling`
  turn `enPoll` into `enetConnect` / `enetDisconnect` / `enetReceive` / `enetError`
  messages. Register EVERY host (polling is per host). A throwing handler costs one event,
  not the timer chain; read the first failure from `enPollLastError()`, clear it with
  `enPollClearError`. This is the file a real project starts using.
- **`examples/enet-lan-chat.livecodescript`** - Host on one machine, Join from others; lines
  relay through ONE `enBroadcast`, presence rides connect/disconnect, the connect data
  carries a protocol check, and `closeStack` calls the mandatory `enDeinitialize`.
- **`examples/enet-internet-chat.livecodescript`** - the same chat across DIFFERENT
  networks. The host opens its router's UDP port with TorrentXT's `btMapPort` (FALSE, for
  UDP) and learns its public IP; the chat bytes are pure ENet (host needs enetxt +
  torrentxt, a joiner only enetxt; it carries both helper layers). The pill reads INTERNET
  LIVE only for a public remote, LAN ONLY otherwise. On one network it cannot connect
  (routers will not hairpin the public-IP invite): use the LAN chat there. Verified
  statically; needs a two-machine, two-network OXT pass.
- **`tests/enet-selftest.livecodescript`** - the whole `en*` surface on an installed
  extension, including a live 127.0.0.1 loopback, byte-exact binary round trips and
  host/peer statistics.

## Install

enetxt ships as a standard OXT extension: the LCB module plus the native library under
`src/code/<platform-id>/`. All five platform ids are committed and pinned in
`src/code/MANIFEST.sha256` - `x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32` and
`universal-mac` (x86_64 + arm64, first landed 2026-08-27; all five rebuilt 2026-09-12).
Install through the Extension Manager and the engine resolves the `c:enetxt>` binding. A
hand-built mac library must carry both slices, because the suite's installer refuses a thin
Mach-O under `universal-mac` ([docs/building.md](docs/building.md)).

One rule the app must follow: **call `enDeinitialize` before quitting** (e.g. on
`closeStack`), written bare in statement position. There is no automatic unload hook.

## Documentation

| Document | What it is |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | Install to two machines chatting: the three habits, server and client, delivery modes, the demos. Read first. |
| [docs/api-reference.md](docs/api-reference.md) | All 23 public `en*` handlers, events, error codes, constants and the app rules. |
| [docs/architecture.md](docs/architecture.md) | The threadless pump, the lossless stash drain, handles, the codec, the firewall. |
| [docs/building.md](docs/building.md) | Building on all five targets, the sanitizer lane, packaging and CI. |
| [CLAUDE.md](CLAUDE.md) | Maintainer memory: rules, gotchas, the engine evidence ledger. |
| [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) | The ENet license. |

Suite-wide documents: https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md

## Development and status

`tests/enet_smoke_test.cpp` drives the ENTIRE exported ABI over a live one-process loopback
(connect data, echo, broadcast, byte-exact payloads, the keyhole partial drain, handle
retirement, a disconnect while still connecting, teardown) under **ASan+UBSan with ENet itself instrumented**; the record golden
and `record_handle_test` pin the wire format. `bash tools/run-gates.sh` runs the static
gates: the family's unified, byte-identical `check-livecodescript.py`,
`check-record-registry.py` (registries, ABI and budget in sync), the golden, the manifest.

**Status.** Engine-proven: the self-test ran green standalone on 2026-08-07 and, async
loopback and statistics included, on 2026-08-13, and folded in the suite paste from
2026-08-10 through 2026-09-25, when the paste's own live loopback also completed on Linux
(connect, a sealed payload, 60000 bytes as one message, a graceful disconnect); the LAN
chat ran on one Linux machine on 2026-08-18. The LAN
chat between two machines and the internet chat across two networks are verified
statically; they need an OXT pass. `CLAUDE.md` carries the dated ledger.

## License

enetxt is MIT (matching the family). It statically links
[ENet](https://github.com/lsalzman/enet) (MIT).

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

enetxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`enetxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/enetxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `enetxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port enetxt --ref pull/<n>/head`, keeping its
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

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/enet-internet-chat.livecodescript`, `examples/enet-lan-chat.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/enet-internet-chat.livecodescript`, `examples/enet-lan-chat.livecodescript`.
- The self-test harness scaffold (`tools/harness-scaffold.livecodescript`; gate `tools/check-harness-scaffold-drift.py`) in `tests/enet-selftest.livecodescript`.
- Sibling libraries embedded by the suite's `tools/sync-demo-embeds.py` (the copy is the shipped file; the master is the sibling's `src/`):
  - `examples/enet-internet-chat.livecodescript` carries `torrentxt/examples/torrent-helpers.livecodescript` from https://github.com/SethMorrowSoftware/TorrentXT.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/enet-internet-chat.livecodescript` carries `examples/enet-helpers.livecodescript`; `examples/enet-lan-chat.livecodescript` carries `examples/enet-helpers.livecodescript`; `tests/enet-selftest.livecodescript` carries `examples/enet-helpers.livecodescript`.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
