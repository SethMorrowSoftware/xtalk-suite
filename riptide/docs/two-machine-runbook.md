# The two-machine runbook

How to drive `examples/riptide-social.livecodescript` on two OXT machines,
phase by phase, and what each result proves. Written after the first passes
(2026-08-15) so the next tester does not need the chat scrollback that
produced them. Paste results back into the tracker; the honesty labels in
the spec and CLAUDE.md move only on a dated report.

Status going in: phases 1-4 are DONE on two machines (feed + follow
2026-08-13; media, and DMs chatting both ways, 2026-08-15). Phase 5 (the
call, now with the spec-6.2 typing lane) and phase 6 (the LAN mesh:
welcome round AND the sync payload - drafts, feed seq, presence) are
wired, with phase 6's sync-payload compute half engine-green 2026-08-20
in the suite paste, but neither has ever run on two machines; phase 7
needs a tor daemon.

## Setup, once per machine

1. Install the extensions: sodiumxt (required), torrentxt (feed, media,
   DMs), enetxt (LAN mesh), datachannelxt (calls). OnionXT is not in that
   list because it is not a packaged extension at all - it is pure script,
   and this demo already carries it (see step 2); the anon persona needs
   only a tor daemon.
2. Open `examples/riptide-social.livecodescript`, paste it into a new
   one-card mainstack's stack script, apply, close and reopen (or launch
   it from `start-here.livecodescript`, which performs that ritual for
   you). Nothing else to wire: since the demo-embed pass the stack
   CARRIES the riptide, onionxt and onion-httpd script libraries between
   its sentinel lines, so opening `riptide/src/riptide.livecodescript`
   and `start using` it as well - which this step used to ask for -
   only loads a second copy of every rs* handler.
3. Firewalls: torrent/DHT traffic for phases 2-4; UDP 27099 for the LAN
   mesh; the dc call uses ephemeral UDP via STUN.

Identity setup differs per phase, and getting it wrong is the easiest way
to chase a non-bug:

| Test | Machine A | Machine B |
|---|---|---|
| Feed / media / DMs / call | identity 1 | a DIFFERENT identity 2 |
| LAN mesh | identity 1 | the SAME identity 1 (copy the key file, same passphrase) |

## Phase 5 - the call (NEVER RUN; the next pass's main event)

Needs: an open DM conversation (phase 4 flow), datachannelxt on both.

1. A and B: open a DM conversation until the `channel open` line shows.
2. Either side: Messages card, click `Call`.
3. Watch the chat area. Expected sequence, caller side:
   `calling: gathering ICE candidates...` then `offer sent over the
   encrypted DM channel`. Callee side: `incoming call: answering...` then
   `answer sent; connecting...`.
4. Success on BOTH sides is `CALL CONNECTED: direct peer-to-peer channel
   open`, a `via <candidate>` line, and a `call: live from <handle>`
   greeting from the far side. The `via` line is evidence: `typ host` =
   same network, `typ srflx` = across NATs via STUN. The done-criterion
   (a call connects across two networks) wants the srflx case, so run it
   once on different networks (for example one machine on a phone
   hotspot).
5. The typing lane (spec 6.2, built 2026-08-15): during the call, start
   typing in the compose field WITHOUT sending. Within a second the far
   side's Messages card should show `the far side is typing...` below
   the compose row; stop typing and it must clear within a few seconds.
   The lane is a second dc channel (unordered, maxRetransmits 0), so an
   occasional missed flicker is by design - a stuck indicator is the
   bug. If one side logged `no typing lane (dcCreateChannelEx
   refused...)` at call start, the call itself still counts; report the
   refusal line.
6. Click `Call` again to hang up; the far side should see `call ended`.
   The DM conversation must survive the call ending, and the typing line
   must clear.
7. Known limits, not bugs: one call at a time; symmetric-NAT pairs will
   fail visibly (STUN only, no TURN relay, by design - spec section 6);
   the call dies on Lock or close.

## Phase 6 - the LAN mesh (never run; welcome + sync payload + media handoff + the three-device relay)

Needs: BOTH machines unlocked with the SAME master (see the table), same
LAN, UDP 27099 allowed.

1. A: Devices card, set a device name, `Host`. Note A's LAN IP.
2. B: Devices card, set a different device name, type A's IP, `Join`.
3. Expected, host side: `admitted "<B's name>" (it proved it shares your
   master)` and B's name in the device list. Joiner side (the W welcome
   round): `ADMITTED - the host "<A's name>" proved it shares your
   master. Mesh is mutual.` and A's name in B's device list. Both sides
   now get a positive, authenticated verdict; if the joiner instead
   logs `the host FAILED to prove itself`, the "host" is not your device
   and the demo leaves the mesh.
4. THE DONE-CRITERION (new, the sync payload): on A, type into the
   "My draft" field on the Devices card. Within about a second B must
   log `draft from <A's name> seq N applied` and render the draft text
   under "Drafts from your other devices", labeled with A's name and
   the seq. Keep typing: the draft on B must CONVERGE to what A's field
   says (edits are debounced on the poll timer, roughly one record per
   second, never per keystroke - intermediate states may be skipped,
   the final state must not be). Then type on B and confirm the same in
   the other direction. Clearing the field must propagate too (an empty
   draft is "cleared", absolute state).
5. Presence/typing (channel 1): while A types, B's device list must show
   `<A's name>  [typing]`, clearing a few seconds after A stops. Kill
   riptide on A without Leave: within ~5 s B's list must show
   `<A's name>  [quiet]` (presence is re-asserted every second and
   expires, so a dead device cannot paint as live).
6. Feed seq over the mesh: with a published feed (seq N > 0) on A, both
   admitted, B must log `feed seq N adopted from <A's name>` if B's own
   seq is behind - the two-devices-never-conflict half of channel 0.
7. The media handoff (the channel-2 decision, added 2026-08-16: a
   signed channel-0 POINTER; the bytes ride the phase-3 torrent rail,
   and channel 2 stays dark). Both machines unlocked so their torrent
   sessions are up. On A, section 5 of the Devices card: `Send
   media...`, pick a small photo or video. Expected on A:
   `offered "<file>" (<size> bytes) to 1 admitted device(s)`; on B:
   `media offer from "<A's name>": <file> (<size> bytes)` and the offer
   line fills in with the file, size, sender, and hash. On B click
   `Fetch + play`: the handoff progress line must climb (on one LAN,
   near instantly - the phase-3 pass's own shape) and the button must
   flip to `Play now` the moment the on-disk file exists; click it and
   the file must open in the system player. Report whether playback
   was mid-download or after completion, same nuance as phase 3. If
   the swarm never connects, note it with the network's shape: peer
   discovery is the DHT, so a LAN with no internet route may not find
   its swarm even though both devices sit on it - report that as the
   recorded honest limit, not a defect.
8. THE THIRD-DEVICE STEP (added 2026-08-17; this runbook structurally
   could not reach the relay before it, and a real defect was hiding
   there). Everything above uses ONE non-host device, so every record B
   applies arrives from A over B's only link. The mesh is hub-and-spoke:
   the host RELAYS each verified record to its other admitted peers, so
   a joiner's view of a THIRD device arrives over the SAME peer id as
   the host's own records. Bring up C on the same master and the same
   LAN, give it a THIRD distinct device name, and `Join` A's IP (C joins
   the HOST, never B - joiners have no link to each other).
   - On A: the device list must show BOTH B and C, and `Send media...`
     must report `to 2 admitted device(s)`.
   - On B: the device list must show A AND C, two rows, each with its
     own `[typing]` / `[quiet]` marker. One row, or C's presence
     replacing A's row, is the failure this step exists to catch.
   - Type on C. B must log `draft from <C's name> seq N applied` and
     render that draft labeled with C's NAME - not with A's, and not
     replacing A's draft block. Then type on A and C at the same time:
     both drafts must converge independently on B. The per-device seq
     counters seed from the clock on each device separately, so
     interleaved records under one counter would silently drop most of
     them (the drop path is a deliberate silent exit and logs nothing,
     which is exactly why this must be watched in the UI and not in the
     log).
   - Media: offer a file from C. B must show the offer attributed to
     C's name, and A must relay it rather than swallow it.
   - Then close C (no `Leave`): within about 5 s B must mark C
     `[quiet]` while A's row stays live. Now `Leave` on A: B loses ALL
     rows, C's included, which is correct - B had no link but the host.
   If a third machine is not available, a second OXT instance on B's
   machine should serve (the same key file and passphrase, a DIFFERENT
   device name; only the HOST binds UDP 27099, so a second joiner needs
   no port). That substitution is untried - report it if it does not
   work rather than assuming the mesh is at fault.
9. The stranger test (the security half): on B, Lock, unlock a DIFFERENT
   identity, Join again. A must log `a peer FAILED admission (not your
   device)` and drop it. Nothing should appear in either device list,
   and NO draft may cross. If any record does arrive from an unadmitted
   or foreign peer, the log line to expect (and report) is
   `stranger record refused` - the record-level refusal the library
   enforces on top of admission.
10. Timing note: the admission is a first-message handshake, so a
    same-second join is normal; a hang at `connecting to <ip>` is almost
    always the firewall or the wrong IP.
11. Honest limits, said in the UI too: sync records are authenticated,
    not encrypted - the LAN carries draft plaintext - and offered media
    BYTES ride the ordinary torrent rail (swarm peers see your IP). A
    joiner keeps a row for a device that leaves the mesh until its
    presence goes `[quiet]`: there is no leave record, and a joiner
    hears nothing when a device drops off the HOST's link.

## Phase 7 - the anon persona (needs tor; single machine is enough)

The serving is BUILT as of 2026-08-15 (the 8.2 feed page, the 8.3
/prekey and POST /dm routes - library seams plus the demo's onion-httpd
wiring). Its COMPUTE half ran engine-green 2026-08-20 in the suite
paste; this pass flips the remaining LIVE half of the label.

1. Run a tor daemon with the control port enabled (see
   `onionxt/docs/03-control-port.md` for the torrc lines). Both onionxt
   libraries are already embedded in the demo, so there is nothing to
   put in use; the demo's "onion-httpd is not loaded" refusal now means
   the embedded copy is damaged - re-paste the file, or re-run
   `tools/sync-demo-embeds.py`.
2. Anon card: type a line or two into "anon feed entries", `Reveal
   persona 0`, then `Publish + serve`. A cold tor means the first click
   only connects the control port (watch the `tor:` lines in the log);
   publishing continues automatically once authenticated.
3. From Tor Browser on the SAME machine, visit the shown .onion.
   Expected: the anon feed page renders, title and your typed entries
   (reaching it at all proves the deterministic service key - the
   address IS the persona's public key; the page proves the serving).
4. Visit `<onion>/prekey`. Expected: 264 hex chars, and on a second
   machine (or a scratch stack) `rsVerifyPrekey(sxHex2Bin(body),
   anonHandle)` returns non-empty - the served prekey proves itself.
5. The /dm drop: build a sealed intro with the PUBLIC identity
   (`rsBuildIntro` to the anon handle, `rsDmSealIntro` to the served
   prekey), spell it as hex, and POST it to `<onion>/dm` (curl through
   the tor SOCKS proxy works: `curl --socks5-hostname 127.0.0.1:9050
   --data "<hex>" http://<onion>/dm`). Expected: `accepted`, and the
   Anon card logs the PROVEN sender handle (the Messages card gets a
   pointer line). A mangled body or a replay outside the 600 s window
   must answer `refused` with nothing logged but the stale note.
6. The done-criterion also wants a trace showing zero `bt*` calls for the
   persona; the guard panel on that card shows the policy that enforces
   it.
7. Known limits, not bugs: the persona does not REPLY over the onion
   (answering an accepted intro means a public-side DM to the proven
   sender - the reply rail is recorded as deliberately unbuilt), and
   curl's `--data` must carry the hex EXACTLY (a trailing newline is a
   refusal - the strict 632-char gate).

## Phase 8 - the Nostr rail (never run; ONE machine is enough, plus a real relay)

Unlike every other section here this one needs no second machine: the
"other side" is the public Nostr network, and a second client can be a
web one. It DOES need CoinXT installed and outbound TLS to a relay.

The rail is optional by construction, so **step 0 is to prove that**:
open the app with CoinXT NOT installed and confirm the boot self-check
SKIPs the Nostr rail with an install line while every other card still
works. A failure here is worse than a broken feature - it means phase 8
became a dependency, which is the one thing the design forbids.

1. **Identity.** Unlock on the Feed card, then go to `Nostr >`. An
   `npub1...` must appear. Copy it and paste it into any Nostr web
   client's search: it must resolve to a valid (empty) profile rather
   than being rejected as malformed. That is the NIP-19 encoding
   verified by somebody else's implementation.
2. **Lock and unlock again.** The SAME npub must come back. It derives
   from the master seed, so this is the identity-first property one rail
   further out; a different npub means the ladder or the subkey is not
   deterministic and everything below is void.
3. **Relays.** The field is pre-filled and nothing has been dialled -
   confirm the relay log is empty before you click. Click `Connect`.
   Each relay must log `connecting...` then `OPEN`. A relay that stalls
   must say so within ~20 s rather than sitting silent (the UI
   watchdog); report a silent stall as a finding.
4. **Post.** Type a note, click `Post note`. The log must show one
   `publish <id> -> true` per relay. Then find that note in a web client
   by its npub. **Report the id and the relay's reason text verbatim** -
   a `true` with an unexpected reason is still worth seeing.
5. **Follow and read.** Paste a well-known npub (any active account)
   into the follow field, click `Follow`. The timeline must fill with
   VERIFIED events - and the relay log must show any refusals separately
   as `refused an event`. Report the ratio if refusals are non-zero:
   the relay layer verifies id and signature before delivery, so a
   refusal is either a relay misbehaving or a bug worth chasing.
   Confirm an event from an author you do NOT follow is dropped and
   logged (relays send what they like; the subscription is a request).
6. **The bridge, both directions.** Click `Publish identity bridge`.
   The log must report the DHT half and the relay half separately.
   Then, on the SECOND machine if you have one:
   - **npub to handle**: fetch the kind-30078 event from a relay (any
     client can) and confirm its content decodes to a 276-byte record
     naming your riptide handle.
   - **handle to npub**: this direction needs a riptide build, so it is
     the one part of this step that wants machine B - fetch the bridge
     off the DHT at salt `riptide-nostr` under the handle.
   Report BOTH, and report if either half fails while the other works.
7. **The republish refusal.** The one adversarial check, and it needs no
   network: it is asserted in the suite paste. Confirm the two harness
   lines pass - a stranger CAN sign an event carrying your bridge, and
   reading it back REFUSES. If those two ever disagree, the linkage is
   forgeable and the rail must not ship.
8. **Persistence.** Quit the app entirely and reopen it. Unlock. Your
   follows and relay list must come back, and the timeline must be
   empty (it is a live view, not a store). Then unlock with a DIFFERENT
   key file and confirm the state does NOT open, silently and without
   overwriting anything - the log says so and the app starts empty.
9. **The guard.** On the Anon card, confirm the live guard panel shows
   `nostr` REFUSED for the anon persona. This is a read of the same
   function the relay dial asserts through, so a disagreement between
   the panel and the dial is a deanonymization finding, not a UI bug.

## Re-verifications worth repeating on any pass

- The pump-survives-navigation check: start a Fetch or media download on
  the Feed card, visit every other card, come back; the pump must still
  be live.
- Phase 3's mid-download nuance was MEASURED 2026-08-27 (two machines) and
  it did NOT start mid-download as then wired: the Play mood unlocked on
  file-EXISTENCE, which libtorrent satisfies at metadata time with a
  hollow allocated file, so the system player got ~0% real data - "the
  feed and media work fully, streaming does not" was the exact report.
  Fixed the same day (raMediaFrontReady: Play unlocks once the first 5%
  of the file's CONTIGUOUS front is on disk; both the feed and the LAN
  handoff paths). Re-run the leg on the fixed stack: attach a LARGE video
  on A, fetch on B, wait for the "Play now" mood, and confirm playback
  starts while the progress line is visibly below 100%. USE A FASTSTART
  VIDEO (ffmpeg -movflags +faststart, or any web-optimized mp4): a
  non-faststart file keeps its index at the TAIL, and no player can start
  it early whatever the fetch order - that case playing only at 100% is
  the recorded limit, not a defect.
- The DM clean close (new 2026-08-17, never run): with a conversation
  open both ways, `Lock` on A. B must print
  `-- <A's short handle> closed the conversation --` and stop showing the
  channel as open. Before this the far side simply went quiet and kept
  its `channel open with ...` line forever, which reads as a hang rather
  than a hang-up. The signal is the secretstream FINAL tag, so it is
  one-shot: A cannot send again on that stream, which is correct - a
  re-dial mints fresh streams. Report it if B shows nothing, and report
  separately if B shows a stray chat line (the close rides a filler body
  that must never be rendered).
- The tick tiers (new 2026-08-17, never run): the pump now runs at ~33 ms
  while a dc call or an enet mesh is live and ~250 ms otherwise, which is
  the cadence the spec's section 10.1 always specified and NOT what
  phases 5 and 6 were ever driven at. Judge the call and the typing
  indicators for feel at that cadence, and watch CPU on the slower of the
  two machines while a call and a mesh are up together - the UI painters
  are deliberately still gated to 4 Hz, so a busy CPU with a smooth
  window means the transport tier, not the painters.
- The suite selftest paste (`tests/suite-selftest.livecodescript`) on any
  machine whose extensions changed.

## What to report back

The pass/fail lines verbatim where there are checks; for the app flows,
the log lines named above plus anything that surprised you. A wrong or
missing log line is a finding even when the feature "worked".
