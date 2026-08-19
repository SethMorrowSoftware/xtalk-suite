# Getting started with DataChannelXT

This walks from install to a working two-machine connection. If you want the
zero-setup proof first, skip to **The loopback demo** — it needs no second
machine and no signaling infrastructure. If you want the headline act — two
machines chatting across the internet with no server — that is section 6.

> **Honesty note (the suite convention):** the native pipeline is proven by the
> C++ smoke test under sanitizers, and on **2026-08-08** the `.lcb` binding was
> observed loading and working on a real OXT engine — the suite selftest ran
> green, negotiating a live loopback and round-tripping a payload byte-for-byte.
> Every public `dc*` handler has now been called on one — the
> **2026-08-10** suite pass folded the member harness's synchronous half in,
> and the **2026-08-15** standalone run closed the async loopback too. That run
> is what it covered, not the file as it stands: the assertions added to
> `tests/datachannel-selftest.livecodescript` since it - the exact-code
> stale-handle checks, the embedded-NUL refusal and its last-error clearing,
> and the skip-on-failed-setup teardown branch - are **verified statically;
> needs an OXT pass** on a build carrying `kErrInvalidArg`.
>
> The demos this guide walks through are now SPLIT evidence, and the split is
> exactly where a second machine begins. Section 6's
> `datachannel-dht-chat.livecodescript` HAS been run on a real engine -
> **2026-08-18**, on Linux and again on Windows, one machine hosting a chat -
> and three things surfaced there that no gate had caught: the duplicate
> `local sPolling` the embed introduced, which stopped the compile outright
> (engine notes 1.6); a poll pump that died on a bad event instead of naming
> it, which is why the next failure cost two passes (6.6); and the cause that
> was hiding behind it - an event name and a public handler name sharing one
> xTalk namespace, so the `dcLocalDescription` event dispatched into the
> LIBRARY getter of the same name and had never fired once (6.7). All three
> are fixed and gated; the verbatim engine output is in
> [`docs/OXT-ENGINE-NOTES.md`](../../docs/OXT-ENGINE-NOTES.md), sections 1.6,
> 6.6 and 6.7. What has NO recorded run: the loopback demo of section 5, and
> section 6's own two-machine flow. Treat those steps as designed behaviour.

## 1. Install the extension

DataChannelXT is a standard OXT extension package: the LCB module
(`datachannel.lcb`, library `org.openxtalk.library.datachannel`) with the
native library bundled per platform under `code/<arch>-<platform>/
datachannelxt.{so,dll,dylib}`. Install it through the OXT Extension Manager
like any other extension; the engine then resolves the `c:datachannelxt>`
binding automatically via `the revLibraryMapping` — no loose files, no `sudo`,
no `LD_LIBRARY_PATH`.

Also put `examples/datachannel-helpers.livecodescript` where your app can
`start using` it — it is the poll dispatcher every app wants.

## 2. The three habits every app needs

```livecodescript
on openStack
   dcInit                                      -- optional, but moves the one-time
                                               -- DTLS certificate cost off your
                                               -- first connection
   start using stack "dataChannelHelpers"
   dcStartPolling the long id of this card, 33 -- ~30 Hz; the latency knob
end openStack

on closeStack
   dcStopPolling
   -- BARE, not dcCleanup(): a zero-argument call in STATEMENT position parses
   -- as a command whose argument is `()`, and `()` is not an expression, so
   -- the parenthesised spelling does not compile - and a .livecodescript
   -- compiles as ONE unit, so it takes the whole stack script with it.
   -- dcStopPolling on the line above is the same idiom. The parens are
   -- required only in EXPRESSION position, as in `dcCleanup() is 0`.
   dcCleanup     -- MANDATORY: there is no automatic unload hook; skipping this
                 -- leaks the native worker threads at quit
end closeStack
```

Everything the engine wants to tell you arrives as messages dispatched by the
helpers (`dcMessage`, `dcChannelOpen`, ... — full list in the api-reference).

## 3. The WebRTC shape: signaling is yours

Two peers cannot meet out of thin air. WebRTC's contract: each side produces a
**description** (an SDP blob) and **candidates** (ways to reach it), and YOU
carry those between the peers over any channel that already exists — a
TorrentXT DHT rendezvous (serverless!), a chat, a copy/paste, a web service.
After that, the peers talk directly.

With DataChannelXT the artifacts arrive as events, so a complete signaling
implementation is just four handlers:

```livecodescript
-- OFFERER (machine A)
put dcCreatePeer("stun:stun.l.google.com:19302") into sPeer
put dcCreateChannel(sPeer, "chat") into sChan   -- triggers the offer

on dcLocalDescriptionReady pEvent
   -- send pEvent["sdp"] and pEvent["sdpType"] to machine B somehow
end dcLocalDescriptionReady

on dcLocalCandidate pEvent
   -- send pEvent["candidate"] and pEvent["mid"] to machine B somehow
end dcLocalCandidate

-- when B's answer + candidates come back:
--   dcSetRemoteDescription sPeer, tSdp, tType
--   dcAddRemoteCandidate sPeer, tCandidate, tMid
```

```livecodescript
-- ANSWERER (machine B)
put dcCreatePeer("stun:stun.l.google.com:19302") into sPeer
-- apply A's offer; DataChannelXT auto-creates the answer, which arrives as
-- B's own dcLocalDescriptionReady event -> ship it back to A
dcSetRemoteDescription sPeer, tOfferSdp, "offer"

on dcChannelIncoming pEvent
   put pEvent["channel"] into sChan   -- A's channel, arriving on B
end dcChannelIncoming
```

Both sides then get:

```livecodescript
on dcChannelOpen pEvent
   dcSendText(pEvent["channel"], "hello!")
end dcChannelOpen

on dcMessage pEvent
   if pEvent["text"] is not empty then
      -- a text message
   else
      -- pEvent["payload"] is a binary Data
   end if
end dcMessage
```

### Copy/paste (non-trickle) signaling — great for a first two-machine test

Shipping every candidate separately ("trickle") connects fastest, but you can
also wait for gathering to finish and ship ONE blob each way:

```livecodescript
on dcGatheringStateChange pEvent
   if pEvent["state"] is 2 then   -- kGatheringComplete
      -- this SDP now CONTAINS the candidates; paste it to the other machine
      put dcLocalDescription(pEvent["peer"]) into field "myBlob"
   end if
end dcGatheringStateChange
```

On the far side, `dcSetRemoteDescription` with that blob is the ONLY call
needed — no candidate shipping at all. Two humans with a chat window can
bootstrap a connection this way.

## 4. STUN and TURN

- `dcCreatePeer("")` — no servers: works on one machine or a LAN.
- A **STUN** line (`stun:stun.l.google.com:19302`) lets peers behind ordinary
  home NATs discover their public addresses; most pairs connect directly.
- A **TURN** line (`turn:user:pass@turn.example.com:3478?transport=udp`) adds a
  relay for the hostile-NAT minority. TURN relays your traffic, so it needs
  credentials — which ride inside the URI and live in ordinary memory (the
  usual scripting-secret caveat).

One server per line in the `dcCreatePeer` argument.

## 5. The loopback demo

`examples/datachannel-loopback.livecodescript` runs both peers in one stack and
does its "signaling" in four script lines. It is ONE paste-and-run file - the
poll dispatcher is carried inside it, so there is no helpers stack to put in
use first. Open it, click **Connect**, watch the states go
`connecting -> connected`, then chat between the two panes. Its
`dcLocalDescriptionReady`/`dcLocalCandidate` handlers are the template for real
signaling: replace "hand it to the other local peer" with "transmit it".

## 6. The flagship demo: DHT-signalled chat (two machines, no server)

`examples/datachannel-dht-chat.livecodescript` is the copy/paste flow of
section 3 with the human removed: **TorrentXT's DHT carries the blobs.** One
side clicks **Host a room** and sends the room code to the other, who pastes
it and clicks **Join**; the offer and answer travel as signed BEP44 mutable
items, ICE punches the NATs, and the chat itself is a direct DTLS data
channel — no server of yours anywhere, ever.

Worth stealing from it even if you never run it:

- **The room code is a keypair.** `btDhtKeypair` is deterministic on a 64-hex
  seed, so handing someone the seed hands them the same signing keypair — a
  shared write-capability for one DHT mailbox, minted fresh per room.
- **Non-trickle over a slow channel.** A DHT round-trip is seconds, so the
  demo ships ONE blob per side (wait for `dcGatheringStateChange` == 2), never
  a candidate trickle.
- **The 1000-byte BEP44 budget.** Blobs are compressed and, when still too
  big, split across content-addressed immutable items listed in the mutable
  head — see the wire-format comment at the top of the script.
- **Nonce-paired offer/answer.** DHT items linger for hours; a nonce echoed
  from offer to answer is what lets "Reconnect" reuse a room code safely.

It needs BOTH extensions installed (TorrentXT is probed at startup and the
demo fails closed with an install message when absent).

## 7. Where to go next

- `docs/api-reference.md` — every handler, event, key, and constant.
- The runtime self-test (`tests/datachannel-selftest.livecodescript`) — paste
  into a stack script to verify the installed binding end to end.
- Talking to a **browser**: the far side is standard WebRTC —
  `new RTCPeerConnection()`, `pc.ondatachannel`, the same SDP/candidate dance
  over your signaling; text arrives as strings, `dcSendData` as `ArrayBuffer`.
- **Bulk transfer**: the per-message budget is 60 000 bytes by design. Chunk
  small files over the channel if you must, but the family's answer to bulk is
  TorrentXT — use the data channel for control and presence.
