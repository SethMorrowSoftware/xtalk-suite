# Riptide examples

One stack so far: `riptide-social.livecodescript`, the phase-1-through-7
flagship on FOUR cards: Feed (identity via the RIPTKEY1-sealed seed, a
public feed of signed posts + a signed BEP44 head over the real DHT, the
verified follow walk, and the media strip), Messages (encrypted DMs + the
phase-5 Call button), Devices (the phase-6 LAN mesh), and Anon (the
phase-7 persona with its live guard panel). It is built on the suite UI
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
- Phases 5 (the call), 6 (the mesh), 7 (anon over Tor): BUILT, statically
  verified, never run - `../docs/two-machine-runbook.md` is the script.
  Phase 7 now includes the 8.2/8.3 onion SERVING (2026-08-15): Publish +
  serve registers onion-httpd routes for the feed page at `/`, the signed
  prekey at `/prekey`, and a POST `/dm` sealed-intro drop; it needs BOTH
  `onionxt/src/onionxt.livecodescript` and
  `onionxt/src/onion-httpd.livecodescript` in use, plus a tor daemon with
  the control port enabled.

## Setup

1. Install the packaged sodiumxt (required) and torrentxt (required for
   publish/fetch) extensions.
2. Put the riptide library in the message path: `start using stack "riptide"`.
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
