# Riptide examples

One stack so far: `riptide-social.livecodescript`, the phase-1/2 flagship.
Identity (create or unlock the RIPTKEY1-sealed seed), a public feed (signed
posts + a signed BEP44 head over the real DHT), and follow (fetch another
author's head, walk the post chain to the zero target, show every authorSig
verdict). It is built on the suite UI kit (the block between the marker
lines is carried verbatim from `tools/ui-kit.livecodescript` at the suite
root; do not edit it here).

Status: PASSED, on two machines (2026-08-13). Identities were created on
both sides and feeds published and received in both directions through the
real DHT - which is phase 2's done-criterion, since a post renders only
after the ingest verifiers accept its signature. That run also closed the
event loop (real btPoll DHT items into the verifiers, previously
synthetic-only). The library underneath was engine-passed 2026-08-12
(133/133). Environments of the closing run were not captured; the record
is the maintainer's dated account.

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

Record the result in `docs/OXT-PASS-RUNBOOK.md` (the demo row and item 6).
Phases 3-7 (media, DMs, live sessions, LAN sync, anonymous personas) are
deliberately absent here; see `docs/RIPTIDE-SOCIAL-SPEC.md`.
