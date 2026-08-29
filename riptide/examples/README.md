# Riptide examples

One stack so far: `riptide-social.livecodescript`, the phase-1-through-7
flagship on FOUR cards: Feed (identity via the RIPTKEY1-sealed seed, a
public feed of signed posts + a signed BEP44 head over the real DHT, the
verified follow walk, and the media strip), Messages (encrypted DMs + the
phase-5 Call button), Devices (the phase-6 LAN mesh), and Anon (the
phase-7 persona with its live guard panel). A phase-8 Nostr card was built
and REVERTED on 2026-08-29 - see the phase-8 entry below. It is built on the suite UI
kit (the block between the marker lines is carried verbatim from
`tools/ui-kit.livecodescript` at the suite root; do not edit it here).

Status, by phase (each a maintainer's dated account):
- Phases 1-2 (feed + follow): PASSED on two machines 2026-08-13, feeds
  both directions through the real DHT; the library underneath
  engine-passed 2026-08-12 (133/133).
- Phase 3 (media): PASSED on two machines 2026-08-15 - a follower fetched
  and played an attached video (mid-download start not yet distinguished
  from a fast complete transfer).
- Phase 4 (DMs): PASSED on two machines 2026-08-15, chat both ways, no
  server.
- Phase 5 (the call): BUILT, verified statically, never run. Phases 6
  (the mesh) and 7 (anon over Tor): BUILT, their COMPUTE halves
  engine-green 2026-08-20 (Windows, in the suite paste); the live legs
  have never run - `../docs/two-machine-runbook.md` is the script.
  Phase 5 now includes the spec-6.2 typing lane (2026-08-15): a second,
  deliberately lossy dc channel showing "the far side is typing..."
  during a call. Phase 6 now includes the SYNC PAYLOAD (2026-08-15):
  the Devices card's draft field broadcasts signed channel-0 records to
  every admitted device (debounced, absolute state), incoming drafts
  render with their origin device and seq, channel-1 presence shows
  [typing]/[quiet] per peer, and a stranger's record is refused and
  logged - the phase-6 done-criterion (a draft typed on one device
  appears on another with a stranger refused) is now reachable. And
  since 2026-08-16 the MEDIA HANDOFF (the channel-2 decision): Send
  media... seeds the picked file in place and offers it to every
  admitted device as a signed channel-0 pointer (info-hash + name +
  size); the receiving device's Fetch + play pulls the bytes over the
  phase-3 torrent rail, playable mid-download. Channel 2 itself stays
  reserved, dark - media never fits enet's 60000-byte budget, and bulk
  over that seam is a torrent in this suite.
  Phase 7 now includes the 8.2/8.3 onion SERVING (2026-08-15): Publish +
  serve registers onion-httpd routes for the feed page at `/`, the signed
  prekey at `/prekey`, and a POST `/dm` sealed-intro drop; it needs a tor
  daemon with the control port enabled.
- Phase 8 (the Nostr bridge, 2026-08-29): the LIBRARY rail is built and
  its compute half is EXECUTED headlessly against the real committed
  coinxt (`../tools/check-script-vectors.py`) - more than "verified
  statically", less than an engine pass, since it settles logic and not
  parser behaviour. **The CARD is NOT landed.** It was written the same
  day, and on a real engine it failed at `openStack` with
  `Chunk: no target found` - the whole app, not just the new card. It was
  REVERTED rather than left in place or patched on a guess, so this stack
  is byte-for-byte the phase-1-through-7 app that works. Two defects were
  found and fixed on the way (a non-literal `constant`, which does not
  compile and therefore took the entire stack script down; and the gate
  gap that let it ship - now check 22 in the family checker), but the
  third failure is UNDIAGNOSED: it needs an engine and a failing line
  number, and this repo has no way to execute a stack script headlessly.
  Nostr DMs are separately and deliberately NOT built (spec 8A.6): NIP-04
  needs AES, which this suite does not have, and NIP-17 gift wrap needs
  work this pass did not do - riptide's own DM rail already answers to
  nobody.

## Setup

1. Install the packaged extensions: sodiumxt (required everywhere), torrentxt
   (required for publish/fetch and for the phase-3 media rail),
   datachannelxt (required for the phase-5 call) and enetxt (required for the
   phase-6 LAN mesh). The body of this stack calls `dcCreatePeer` and
   `enHostCreate` directly, so phases 5 and 6 are dark without those two.
2. Nothing to wire: this stack CARRIES `riptide`, `onionxt` and `onion-httpd`
   embedded between the sentinels that `tools/sync-demo-embeds.py` (at the
   suite root) owns, so there is no `start using` step and no second stack to
   open beside it. Putting `riptide` in the message path as well - which this
   step used to ask for - only loads a second copy of every rs* handler, which
   is the stale-in-memory-library hazard the embed exists to remove. Edit the
   sources under `../src/` and `onionxt/src/`, never inside the sentinels.

   NostrXT is deliberately NOT carried here while the phase-8 card is
   reverted. Re-adding it means re-adding TWO socket libraries at once,
   which needs this stack's own `socketError`/`socketClosed`/`socketTimeout`
   handlers back with it plus the `DROP_HANDLERS` pair rows in the embed
   tool. If you re-land it, keep the final `pass` in each: a stack that
   swallows a socket message another library was waiting for produces a
   HANG rather than an error, and no gate here can see it.
3. Paste the stack script into a new one-card stack, apply, close, reopen.
4. One TorrentXT session per process: close every other torrent-flavoured
   stack first, and restart OXT before any re-paste of this script.

## The single-machine run (half of phase 2, honestly labeled)

Create an identity, post twice, then paste your own handle into the follow
field and Fetch: the head and both posts come back through the real DHT and
every signature verdict shows. That proves the event loop and the walk; it
does NOT prove propagation between machines.

## The two-machine run (the phase-2 done-criterion - MET 2026-08-13)

- Machine A: create an identity, post two or three times, stay online (the
  session keeps the records seeded while it runs).
- Machine B: open the same stack, skip identity (follow needs none), paste
  A's 64-hex handle, Fetch.
- Done when B's feed shows the head VERIFIED, every post walked in order to
  the zero target, and every line reads authorSig VERIFIED - with no record
  bytes copied between the machines by hand.

Record the result in the suite's `../../docs/OXT-PASS-RUNBOOK.md` (the
repository-root docs/, not riptide's; the demo row and item 6).
The phase 3-7 flows (media, DMs, the call, the LAN mesh, the anon persona)
are all IN this stack now; `../docs/two-machine-runbook.md` scripts their
per-phase tests and expected log lines, and the suite's
`../../docs/RIPTIDE-SOCIAL-SPEC.md` is the design they implement.
