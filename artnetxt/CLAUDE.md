# CLAUDE.md

Guidance for Claude Code in the artnetxt member of the xtalk-suite monorepo (`artnetxt/`).
Where anything disagrees, the code and this file win.

## What this is

**artnetxt** is Art-Net (DMX512 lighting levels over UDP) for OXT, in pure LiveCode Builder:
`src/artnet.lcb` (`org.openxtalk.library.artnet`, public `artnet*`) packs and reads bytes.
There is no C shim, no native library and no `src/code/`, so nothing is built and nothing is
committed per platform. It is a codec only: transport is the script's own UDP sockets, so
nothing here opens a socket, starts a thread or calls back.
`examples/artnet-helpers.livecodescript` holds the level, send, poll and routing helpers;
`examples/artnet-selftest.livecodescript` the in-OXT self-test.

`examples/artnet-light-board.livecodescript` is the showcase (2026-11-21, by Seth Morrow): OXT-Beyond's dark look
(EXEMPT from the suite's UI kit by the owner's request), a board and a virtual node over real UDP on 127.0.0.1, port 6454 (6464 at most), never a broadcast. It CARRIES
`examples/artnet-helpers.livecodescript` between the embed markers: edit the helper, then run the suite's
`tools/sync-demo-embeds.py`, never the copy. Its tests: `tests/lcs/demo_test.livecodescript` (the rig's ArtPollReply checked byte by byte against an oracle written from the Art-Net 4 field table). It builds its window with messages locked, then centres it: built unlocked it held
OXT-Beyond 0.2.8-dp.1's IDE on Windows for 112 s as it opened (each scripted create and rename
ran the IDE's script, the suite's engine note 5.15), and a size set keeps a new stack's centre (5.17), so it
opened 390 px past the screen's left edge (2026-11-21). `TestTheWindowIsBuiltQuietly` and
`TestTheWindowOpensCentredOnTheScreen` failed against that build. Built so, it opened there in
5.0 s, running, wholly on the screen (the same day). Its loop stops itself at its next frame
once its stack is closed, so a close made with messages locked, which sends no closeStack,
cannot leave it running unseen in the IDE's memory with its sockets open (after each close there
a frame was still queued; `TestAClosedWindowStopsItsShow`).

It is the Art-Net third of ShowControl (Seth Morrow Software's OSC, MIDI and Art-Net
extensions), which joined the suite on 2026-11-21 as oscxt, midixt and artnetxt. The library
id, every public handler, the refusal texts and the helpers' ShowControl names are
unchanged, so an installed ShowControl `artnet` extension upgrades in place and its stacks
keep working.

## The rules

1. **Never call script from a foreign thread.** There is none: packets arrive through the
   engine's own `accept datagram connections ... with message`.
2. **Nothing throws for bad input.** A refusal returns empty (for a parser, an array whose
   one key, "opcode", is empty) and `artnetLastError()` says why; every public handler
   clears it on entry. LCB THROWS reading past the end of data, so every read is bounded:
   `byteAt` answers 0 past the end and `fieldText` stops where the data does. An LCB caller
   tests "opcode" before reading another key, which would throw on a refusal's array (in
   Script a missing key is empty). An EMPTY argument into the Integer parameter is still a
   throw, at the engine's boundary (the suite's engine note 6.4).
3. **Bytes from the network are untrusted.** The parsers read only what arrived: a Length
   larger than the data, or than 512, is read as far as the bytes go. Mutation fuzzing of
   both parsers in `tests/lcb/artnet_test.lcb` holds the invariants.
4. **Mixed byte order is THE bug.** The OpCode is little-endian, ProtVer and Length are
   big-endian, ArtPollReply's Port is little-endian, and the universe goes out SubUni then
   Net. Reverse one and a real node ignores the packet, silently. The vectors pin each.
5. **Done means:** a binding change passes `tools/run-lcb-tests.py` (lc-compile `-Werror`,
   as the Extension Builder compiles); a Script change passes `tools/run-lcs-tests.py`; all
   pass `bash tools/run-gates.sh`. A wire-format change starts in
   `tests/vectors/artnet.json`, which the Python codec, the LCB vectors module
   (`tools/gen_vectors.py`) and the virtual node all read. New behaviour gets a test, a fix
   the test that would have caught it.

## As built

- **ArtDmx:** 18-byte header, then the levels. The Length is even, 2 to 512, as the
  specification asks: fewer than 2 or an odd number are padded with 0, past 512 cut.
- **The universe** is the 15-bit Port-Address (Net 7 bits, Sub-Net 4, Universe 4), 0 to
  32767; outside that `artnetBuildDmx` builds nothing ("universe out of range 0..32767"). A
  fraction is cut toward zero: LCB's `Integer` is `Number` (engine note 6.17), and
  `the byte with code` truncates. `artnetParseDmx` answers `net * 256 + subuni`, unmasked,
  as ShowControl's did.
- **ArtPollReply** is read at the Art-Net 4 offsets (239 bytes; anything from 26 is read as
  far as it goes): IP, Port, VersInfo, the switches, the three names, Style, MAC (from 207
  bytes), BindIndex (from 212), and each port's universe, from 194 bytes, through
  PortTypes bit 7 (output) and bit 6 (input), masked as the specification says:
  `(Net & 0x7F) << 8 | (Sub & 0x0F) << 4 | (Sw & 0x0F)`. Those lists are LCB Lists, which
  arrive in Script as arrays numbered from 1.
- **What changed from ShowControl:** the binding compiles under `-Werror` (ShowControl's
  `variable i` did not, so the Extension Builder refused it), and `artnetParseReply` answers
  eight more keys: port, version, nodeReport, outputUniverses, inputUniverses, style, mac
  and bindIndex. Every key ShowControl answered means what it meant.

## The helpers (examples/artnet-helpers.livecodescript)

ShowControl's `scArtnetSend`, `artnetSendDmx` and `scArtnetOneChannel`, under their names,
plus `scArtnetEnsureSocket`, `scArtnetSetChannel`, `scArtnetChannel`, `scArtnetPoll`,
`scArtnetReceived` and `scLooksLikeArtnet`. The file's header lists what changed on purpose.

- **Levels are rounded and clamped** before `numToByte`, which WRAPS (256 is byte 0) and
  rounds or truncates a fraction by where the value came from (engine note 2.13, pinned by
  `tests/lcs/engine_notes_test.livecodescript`).
- **A channel outside 1..512 throws**; an unbuildable send sends nothing and returns why.
- **The engine calls a datagram message with (sender, data, socket)**, in that order
  (engine `opensslsocket.cpp`); `write ... to socket "h:p"` sends NOTHING unless `h:p` was
  opened, so every send opens first. An accepted socket is named by its port alone.
- **Nodes answer an ArtPoll to port 6454 of the computer that asked**, so discovery listens
  there; a broadcast needs `the allowDatagramBroadcasts` (`scArtnetPoll` sets it for a
  `.255` host). A failed `accept` shows only in `the result` (engine note 6.12): the socket
  suites skip a test whose port is taken rather than fail it.

## Gotchas

1. **LCB has no `numToByte` or `byteToNum`**: `the byte with code N` and
   `the code of byte N of X`. `the byte with code` THROWS for 256 or -1, so every computed
   byte is reduced with `mod` first, after the range check.
2. **An all-lowercase LCB name warns, and the Extension Builder compiles with `-Werror`.**
3. **Reading a missing array key THROWS in LCB** (Script answers empty).
4. **The library needs nothing from `com.livecode.foreign`**: keep it that way, or it stops
   being the member with nothing to build.

## Status

Verified on OXT-Beyond's headless engine (9.7.1-OXT, Linux x86_64, 2026-11-21): the LCB
suite under lc-compile `-Werror` and lc-run, and the Script suite in the standalone engine
with `-ui`, real UDP and the virtual node included. In a desktop IDE on 2026-11-21:
OXT-Beyond 0.2.8-dp.1 on Windows (64-bit) compiled the binding with its own lc-compile,
loaded it and ran the showcase, ArtDmx out to 127.0.0.1:6454 and the rig lit from what
arrived (that run found the two faults above; the suite's runbook, section 8). The self-test
has not run in an IDE, and no macOS or Android engine and no hardware node has met it:
verified statically; needs an OXT pass. Open work is in the suite's `docs/WORK-PLAN.md`.
