# enetxt examples

| File | What it is |
|---|---|
| `enet-helpers.livecodescript` | The poll dispatcher (`enStartPolling` / `enStopPolling`) that turns `enPoll` into plain xTalk messages (`enetConnect`, `enetDisconnect`, `enetReceive`, `enetError`), plus `enPollLastError()` / `enPollClearError` and display sugar (`enStateName`, `enFormatBytes`). Register EVERY host you create - polling is per host here, and PUMP OR NOTHING: this loop is the transport's heartbeat, not a convenience. The pump guards BOTH the `enPoll` drain and each dispatch and isolates every event, so app code that throws costs one skipped event instead of the timer chain: the first failure since the last `enPollClearError` is readable from `enPollLastError()` rather than printed, which is what turns "the demo went quiet" back into a line a maintainer can act on. **This is the dependency a REAL project starts using** - `start using stack "enetHelpers"` (see `../docs/getting-started.md`). The demo in this directory needs no such step; see below. |
| `enet-lan-chat.livecodescript` | The milestone-3 demo: a LAN chat. One machine Hosts (server + chatter), others Join its ip; lines relay through the host with ONE `enBroadcast`; presence rides the connect/disconnect events; the status line shows peer count / RTT. The template for the server-relay shape, the connect-data protocol check, and the mandatory `enDeinitialize` at `closeStack`. **Paste-and-run**: it carries this directory's helpers verbatim between the sentinels the suite-root `tools/sync-demo-embeds.py` owns, so there is nothing to load first and `start using stack "enetHelpers"` would only place a second copy of the pump's handlers and script locals behind the demo's own. Edit `enet-helpers.livecodescript` and re-run that tool; never edit inside the sentinels. |

The runtime self-test lives in `../tests/enet-selftest.livecodescript` — paste
it into a stack script to verify an installed extension end to end (sync
surface, a live 127.0.0.1 loopback, byte-exact binary round-trip, teardown).

Every demo follows the family rules: self-building idempotent UI, the poll
interval treated as a latency knob (here it is also the latency FLOOR — ENet
only progresses when pumped), `enDeinitialize` on `closeStack`.
