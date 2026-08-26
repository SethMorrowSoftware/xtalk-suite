# DataChannelXT examples

| File | What it is |
|---|---|
| `datachannel-helpers.livecodescript` | The poll dispatcher (`dcStartPolling` / `dcStopPolling`) that turns the native event queue into plain xTalk messages (`dcMessage`, `dcChannelOpen`, ...), plus display sugar (`dcStateName`, `dcFormatBytes`) and the poll pump's diagnostic pair (`dcPollLastError` / `dcPollClearError`). **The two demos below already carry it embedded** - there is nothing to load first for them. This copy is the one to put where your OWN app can reach it: `start using stack "dataChannelHelpers"`. |
| `datachannel-loopback.livecodescript` | The zero-infrastructure first-run demo: TWO real WebRTC peers in ONE stack, signaling shuttled in four lines of script, a chat pane per peer. Proves offer/answer, ICE, DTLS, SCTP, and both message kinds with no second machine. Its `dcLocalDescriptionReady` / `dcLocalCandidate` handlers are the template to replace with real signaling. |
| `datachannel-dht-chat.livecodescript` | **The flagship**: serverless P2P chat between two machines anywhere on the internet. TorrentXT's DHT (BEP44 mutable items) carries the WebRTC handshake — the room code IS a signing-key seed both sides derive the same DHT mailbox from — then the chat rides the direct DTLS data channel. Shows non-trickle one-blob signaling, the 1000-byte BEP44 budget (compress + chunk), nonce-paired offer/answer, reconnection, and the direct-vs-TURN path readout. **Requires TorrentXT installed too** (probed at startup; fails closed with an install message). |

The runtime self-test lives in `../tests/datachannel-selftest.livecodescript` —
paste it into a stack script to verify an installed extension end to end
(synchronous surface, a live loopback, message round-trips, teardown).

> **Honesty note (the suite convention):** `datachannel-dht-chat.livecodescript`
> HAS been run on a real OXT engine - **2026-08-18**, on Linux and again on
> Windows, one machine hosting a chat - and three things surfaced there that no
> gate had caught: the duplicate `local sPolling` the embed introduced, which
> stopped the compile outright (engine notes 1.6); a poll pump that died on a
> bad event instead of naming it, which is why the next failure cost two passes
> (6.6); and the cause that was hiding behind it - an event name and a public
> handler name sharing one xTalk namespace, so the `dcLocalDescription` event
> dispatched into the LIBRARY getter of the same name and had never fired once
> (6.7). All three are fixed and gated. What is still unwitnessed is the part
> that needs a second machine: this demo's two-machine walkthrough has no
> recorded run, and `datachannel-loopback.livecodescript` has no recorded engine
> run of its own at all - both remain **verified statically; needs an OXT pass**,
> as their own file headers say. The layer beneath them was already witnessed:
> on **2026-08-08** the suite selftest ran green on a real OXT engine, including
> a live datachannelxt loopback that negotiated, opened, and round-tripped a
> payload byte-for-byte. The verbatim engine output is in the suite's
> [`docs/OXT-ENGINE-NOTES.md`](../../docs/OXT-ENGINE-NOTES.md), sections 1.6,
> 6.6 and 6.7.

Every demo follows the family rules: self-building idempotent UI, a poll
interval treated as a latency knob, `dcCleanup` (bare - see above) on `closeStack`.
