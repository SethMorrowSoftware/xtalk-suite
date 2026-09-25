# Riptide examples

One stack: `riptide-social.livecodescript`, the phase-1-through-8 app on FIVE
cards - Feed (identity via the `RIPTKEY1`-sealed seed, signed posts and a signed
BEP44 head over the real DHT, the verified follow walk, the media strip),
Messages (encrypted DMs and the phase-5 Call button), Devices (the phase-6 LAN
mesh), Anon (the phase-7 persona with its live guard panel), and Nostr (the
phase-8 bridge). It is built on the suite UI kit; the block between the kit's
marker lines is carried verbatim from the suite's `tools/ui-kit.livecodescript`,
so do not edit it here.

## Status, by phase

`../CLAUDE.md` holds the dated evidence ledger.

- Phases 1-2 (feed + follow): PASSED on two machines 2026-08-13, feeds both
  directions through the real DHT; the library engine-passed 2026-08-12
  (133/133).
- Phase 3 (media): PASSED on two machines 2026-08-15. Mid-download playback was
  measured negative 2026-08-27 and fixed the same day; the faststart re-run is
  owed.
- Phase 4 (DMs): PASSED on two machines 2026-08-15, chat both ways, no server.
- Phase 5 (the call and its typing lane): built, never run.
- Phases 6 (the mesh) and 7 (anon over Tor, with the 8.2/8.3 onion serving):
  compute engine-green 2026-08-20 in the suite paste, and again 2026-09-24
  (Windows) and 2026-09-25 (Linux) with phase 6's admission and welcome bytes
  as re-pinned 2026-09-09; the live legs are owed.
- Phase 8 (the Nostr bridge): the library is executed headlessly against the
  real committed CoinXT (`../tools/check-script-vectors.py`), and its offline
  compute ran green in the suite paste on an engine 2026-09-24 (Windows) and
  2026-09-25 (Linux). The card's label:
  verified statically + headless boot; needs an OXT re-pass. (Its re-landed boot
  ran on an engine 2026-08-29, and the v11 boot read 9 passed / 1 failed on a
  since-fixed self-check defect; the re-paste should read 10 passed / 0 failed.)
  Nostr DMs are deliberately NOT built (spec 8A.6): NIP-04 needs AES, which the
  suite does not have, and NIP-17 gift wrap needs work not yet done.

`../docs/two-machine-runbook.md` scripts every phase with its expected log
lines.

## The v11 look

- Five tabs in the title band of every card, the current one held down; any card
  is one click from any other.
- Two white column panels per card behind the controls (the kit's family card
  look).
- Buttons that need an unlocked identity start disabled and enable on
  unlock - affordance only, every handler keeps its refusal guard. The status
  line names who is unlocked, from any card.
- Return acts in one-line entry fields; multi-line compose fields keep Return as
  a newline. Empty surfaces say what they are for.
- Pasting a newer script over a stack an older version built rebuilds cleanly:
  the version bump sheds the old furniture first.

## Setup

1. Install the packaged extensions: sodiumxt (required everywhere), torrentxt
   (publish, fetch and the phase-3 media rail), datachannelxt (the phase-5 call)
   and enetxt (the phase-6 LAN mesh). The stack calls `dcCreatePeer` and
   `enHostCreate` directly, so phases 5 and 6 are dark without those two. CoinXT
   powers the Nostr card; without it only that card refuses.
2. Nothing to wire: this stack CARRIES `nostrxt` (core + relay layer),
   `riptide`, `onionxt` and `onion-httpd` between the sentinels the suite's
   `tools/sync-demo-embeds.py` owns, so there is no `start using` step. Putting
   `riptide` in use as well loads a second copy of every rs* handler. Edit the
   sources (`../src/`, and the nostrxt and onionxt members' `src/`), never
   inside the sentinels.
3. Paste the stack script into a new one-card stack, apply, close, reopen.
4. One TorrentXT session per process: close every other torrent stack first, and
   restart OXT before any re-paste of this script.

This is the first stack carrying TWO socket libraries. The embed tool DROPS both
libraries' thin `socketError`/`socketClosed`/`socketTimeout` wrappers (its
`DROP_HANDLERS` pair rows), and this stack's own three handlers call
`oxSocketError`/`nxrSocketError` (and kin) in turn, then `pass`. Keep that final
`pass`: a stack that swallows a socket message another library was waiting for
produces a HANG rather than an error, and no gate can see it.

Record results in the suite's `docs/OXT-PASS-RUNBOOK.md` (the suite's docs, not
riptide's).
