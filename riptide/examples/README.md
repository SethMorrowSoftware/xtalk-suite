# Riptide examples

One stack: `riptide-social.livecodescript`, the phase-1-through-8 app as a social
network you can use. A welcome card (create or unlock your `RIPTKEY1`-sealed
identity), then a sidebar to nine places: Home (write a post, your timeline of
everyone you follow, follow someone by handle, media), Profile (anyone's posts and
name, your own display name), Following, Messages (one encrypted conversation per
person, and the phase-5 Call), and, under MORE, My devices (the phase-6 LAN mesh),
Anonymous persona (phase 7), Nostr bridge (phase 8) and Activity (the log and the
boot self-check). It is built on the suite UI kit; the block between the kit's
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
  (Windows) and 2026-09-25 (Linux and Windows) with phase 6's admission and
  welcome bytes as re-pinned 2026-09-09; the live legs are owed.
- Phase 8 (the Nostr bridge): the library is executed headlessly against the
  real committed CoinXT (`../tools/check-script-vectors.py`), and its offline
  compute ran green in the suite paste on an engine 2026-09-24 (Windows) and
  2026-09-25 (Linux and Windows). The card's label:
  verified statically + headless boot; needs an OXT re-pass. (Its re-landed boot
  ran on an engine 2026-08-29, and the v11 boot read 9 passed / 1 failed on a
  since-fixed self-check defect; the re-paste should read 10 passed / 0 failed.)
  Nostr DMs are deliberately NOT built (spec 8A.6): NIP-04 needs AES, which the
  suite does not have, and NIP-17 gift wrap needs work not yet done.

`../docs/two-machine-runbook.md` scripts every phase with its expected log
lines.

## The social layer (ra-ui-social-12, 2026-10-21)

Built on the protocol as it was: no wire format, library or kit change.

- **Following** is a list of handles, saved with your key. The app asks the DHT for
  each author's head in turn (at most six lookups at once, each with its own
  deadline), and walks back from their newest post until it meets one it already
  holds. Every head and post is verified on arrival, and only then kept.
- **The post cache** is sealed per identity in `riptide-social-<handle>.dat` beside
  the app state (`RIPTSOCIAL1`, subkey 5, so it opens only while unlocked). It is a
  file no older build reads or writes, so trying an older build cannot drop your
  follow list. It holds at most 2000 posts; your own are never dropped.
- **Replies** are a convention inside an ordinary post: the first line reads
  `re: riptide:<handle>/<target>`. An older reader shows that line on top of the
  post, still verified; this one draws "Replying to ..." with the quoted post.
- **The keep-alive.** BEP44 items fade in about two hours unless someone puts them
  again, so every 30 minutes while unlocked the app republishes your head (same
  seq, same bytes), your newest posts (a long post with its chunks), your prekey
  and your name.
- **Profiles**: a display name rides your head (as before), and saving a new one
  republishes the head without a new post.
- **Messages**: one conversation per person, kept in memory only and gone at Lock.
  Connect dials them; they need Riptide open too.
- **What is not possible here, said in the app**: there is no search, and you see a
  reply only from someone you follow (nothing indexes who replied to whom).

## The look

- The slate and indigo of the IDE's own stacks (Home, Academy, E2NB): a dark
  sidebar, white cards on a light page, flat buttons, avatars coloured by handle.
- Feeds, profiles, the follow list and chats are each one field drawn as htmlText,
  one bordered paragraph per post, and every action inside them is a link.
- Buttons that need an unlocked identity start disabled and enable on unlock -
  affordance only, every handler keeps its refusal guard.
- Return acts in one-line entry fields; multi-line compose fields keep Return as
  a newline. Empty surfaces say what they are for.
- Pasting a newer script over a stack an older version built rebuilds cleanly:
  the version bump deletes every `ra*` and `ui*` control on the app's cards first
  (a control you added under another name stays).

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
