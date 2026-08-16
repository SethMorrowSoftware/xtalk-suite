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
wired and statically verified but have never run; phase 7 needs a tor
daemon.

## Setup, once per machine

1. Install the extensions: sodiumxt (required), torrentxt (feed, media,
   DMs), enetxt (LAN mesh), datachannelxt (calls), onionxt + a tor daemon
   (anon persona only).
2. Open `riptide/src/riptide.livecodescript` as a stack and
   `start using` it, then open `examples/riptide-social.livecodescript`
   (or launch both from `start-here.livecodescript`).
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

## Phase 6 - the LAN mesh (never run; welcome + sync payload + media handoff)

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
8. The stranger test (the security half): on B, Lock, unlock a DIFFERENT
   identity, Join again. A must log `a peer FAILED admission (not your
   device)` and drop it. Nothing should appear in either device list,
   and NO draft may cross. If any record does arrive from an unadmitted
   or foreign peer, the log line to expect (and report) is
   `stranger record refused` - the record-level refusal the library
   enforces on top of admission.
9. Timing note: the admission is a first-message handshake, so a
   same-second join is normal; a hang at `connecting to <ip>` is almost
   always the firewall or the wrong IP.
10. Honest limits, said in the UI too: sync records are authenticated,
    not encrypted - the LAN carries draft plaintext - and offered media
    BYTES ride the ordinary torrent rail (swarm peers see your IP).

## Phase 7 - the anon persona (needs tor; single machine is enough)

The serving is BUILT as of 2026-08-15 (the 8.2 feed page, the 8.3
/prekey and POST /dm routes - library seams plus the demo's onion-httpd
wiring), verified statically; this pass is what flips its label.

1. Run a tor daemon with the control port enabled (see
   `onionxt/docs/03-control-port.md` for the torrc lines). Put BOTH
   onionxt libraries in use: `onionxt/src/onionxt.livecodescript` AND
   `onionxt/src/onion-httpd.livecodescript` (the demo refuses with a
   clear message if the second is missing).
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

## Re-verifications worth repeating on any pass

- The pump-survives-navigation check: start a Fetch or media download on
  the Feed card, visit every other card, come back; the pump must still
  be live.
- Phase 3's mid-download nuance is still unmeasured: attach a LARGE video
  on A, fetch on B, and confirm playback starts while the progress line
  is visibly below 100%. The 2026-08-15 pass proved the path; this proves
  the "mid-download" word.
- The suite selftest paste (`tests/suite-selftest.livecodescript`) on any
  machine whose extensions changed.

## What to report back

The pass/fail lines verbatim where there are checks; for the app flows,
the log lines named above plus anything that surprised you. A wrong or
missing log line is a finding even when the feature "worked".
