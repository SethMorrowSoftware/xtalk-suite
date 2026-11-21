# artnetxt

**Art-Net compatible DMX lighting for OpenXTalk / the xTalk family (and LiveCode 9.6.3+).**

artnetxt builds and reads Art-Net packets: DMX512 lighting levels carried over a network, the
way lighting desks, media servers and Art-Net nodes (the boxes that turn a network into DMX
cables for dimmers, LED fixtures and moving lights) talk to each other. It is pure LiveCode
Builder: plain byte packing, with no C shim and no native library, so there is nothing to
build for any platform. It is a codec: the network is the engine's own UDP sockets.

```
(no native code)
   |- LCB binding  src/artnet.lcb     (org.openxtalk.library.artnet; public artnet*)
        |- examples/artnet-helpers.livecodescript   (levels, send, poll and route over UDP)
```

It is the Art-Net third of ShowControl, which joined the suite on 2026-11-21 as **oscxt**
(Open Sound Control), **midixt** (realtime MIDI) and **artnetxt**. The library id, every
handler and the helpers' names are ShowControl's, so a stack written for ShowControl's
`artnet` extension keeps working.

## What it can do

- **Send levels**: `artnetBuildDmx` packs up to 512 channel levels (one universe) into an
  ArtDmx packet, with the protocol's mixed byte order handled for you; the helpers set a
  channel by number (`scArtnetSetChannel`) and send to a node (`scArtnetSend`).
- **Receive levels**: `artnetParseDmx` reads an ArtDmx from another controller, refusing
  anything that is not one, with a reason.
- **Discover nodes**: `artnetBuildPoll` asks every node to answer; `artnetParseReply` reads
  each answer (name, address, firmware version, status report, and the universes of each
  output and input port, Art-Net 4's fields included).
- **The family's rules.** No thread and no callback (rule 1): packets arrive through the
  engine's own `accept datagram connections ... with message`. Nothing throws for bad input:
  a refusal returns empty and `artnetLastError()` says why.

What it does not do: open sockets (the engine does), RDM, sACN (E1.31), timecode, ArtSync,
or pace frames for you (send on your own timer: DMX refreshes at most about 44 times a
second, so a show sends each universe at a steady 30 to 40 frames a second).

## Quick taste

```livecodescript
-- with examples/artnet-helpers.livecodescript pasted into the stack script
local sLevels   -- the universe's levels, kept between sends

on scrollbarDrag pNewPosition
   scArtnetSetChannel sLevels, 1, pNewPosition * 2.55   -- a 0-100 fader drives channel 1
   scArtnetSend "192.168.1.50", 0, sLevels              -- universe 0 of that node
end scrollbarDrag
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## The showcase: Art-Net Light Board

`examples/artnet-light-board.livecodescript` (by Seth Morrow) is a lighting board and a
virtual rig in one window, talking real Art-Net over UDP on this computer only (it never
broadcasts). It opens straight into motion and plays five scenes by itself: a colour
wash, a chase, two moving heads, all 512 channels of a universe, and node discovery, where
the board finds the rig with ArtPoll and the rig answers with a byte-exact ArtPollReply.
Every lamp and every square of the universe is drawn from the packets the rig READ.
Paused, a lighting desk sending universe 0 to this computer drives the rig instead. It carries its helper script, so it is one file: open it from the suite's `start-here.livecodescript`, or paste the whole file into a new stack's script, apply, then close the stack and open it again. It needs the artnetxt extension installed; without it the window still opens and says what is missing.

Its engine tests, `tests/lcs/demo_test.livecodescript`, passed on 2026-11-21 in
OXT-Beyond's headless engine (Linux x86_64). The window, its look, its feel and a real
node or desk are verified statically; need an OXT pass.

## Status

Joined the suite on 2026-11-21. What has run, and where:

- **With no engine:** a clean-room Python codec (`tools/sim/refcodec.py`) agrees with every
  wire-format vector, a third encoder written from the specification asserts hand-checked
  golden packets, and the virtual node `tools/sim/artnet_node.py` is proven over real UDP.
- **On an engine**, the same day, OXT-Beyond's headless engine (9.7.1-OXT, Linux x86_64): the
  LCB suite under lc-compile with `-Werror` and lc-run (the binding against the same vectors,
  every refusal, and mutation fuzzing of both parsers), and the Script suite in the
  standalone engine with `-ui` (the Script-to-LCB boundary, the helpers, the shipped
  self-test, real UDP through the engine's sockets, and discovery plus DMX against the
  virtual node). Every fix artnetxt made to ShowControl's code has a test that failed
  against it.
- **Not yet:** no desktop IDE has loaded it, no engine on Windows, macOS or Android has run
  it, and no hardware node has received its packets: there it is verified statically; needs
  an OXT pass.

## Building and testing

There is nothing to build. To test:

```sh
python3 tools/run-lcb-tests.py --oxt-bin <OXT bin folder>
python3 tools/run-lcs-tests.py --oxt-bin <OXT bin folder>
bash tools/run-gates.sh
```

[docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - install, send levels, receive them,
  discover nodes, the self-test, troubleshooting.
- [docs/api-reference.md](docs/api-reference.md) - every `artnet*` handler, generated from
  the binding's doc blocks.
- [docs/building.md](docs/building.md) - the test layers and the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). Art-Net(TM) Designed by and Copyright Artistic Licence Holdings
Ltd.; artnetxt is Art-Net compatible and contains no code of theirs.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

artnetxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`artnetxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/artnetxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `artnetxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port artnetxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/artnet-light-board.livecodescript` carries `examples/artnet-helpers.livecodescript`.
- `tools/build-api-reference.py`, `tools/check-livecodescript.py`, `tools/run-lcb-tests.py`, `tools/run-lcs-tests.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
