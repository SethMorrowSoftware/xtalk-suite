# barcodext

**Barcodes and QR codes - read from a picture, and made - for OpenXTalk / the xTalk family.**

barcodext binds [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) (Apache-2.0), the C++
"zebra crossing" barcode library that phone scanner apps and browsers are built on, behind the
family's flat C shim and a thin LCB layer:

```
zxing-cpp 3.1.1 (pinned to a commit, static)      the reader and the writer
   |- C++ shim   src/barcode_shim.cpp  ->  barcodext.{so,dll,dylib}     (ABI: bcx_*, v1)
        |- LCB binding  src/barcodext.lcb     (org.openxtalk.library.barcodext; public bc*)
```

A picture crosses in the engine's own layout: the `imageData` of an image object, with a
width and a height. A photo from a camera goes in as it is; a created barcode comes back
ready to set on an image.

## What it can do

- **Read** every barcode in a picture: QR Code, Micro QR, rMQR, Data Matrix, Aztec, PDF417,
  MaxiCode, EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, ITF, Codabar, DataBar,
  Telepen and more. The barcode may be turned, mirrored, light on dark, small in a large
  photo, or one of several. Each comes back with its text, its bytes, its kind and its four
  corners in the picture.
- **Make** the same kinds, as a picture, as SVG text, or as rows of 1 and 0 for a stack that
  draws its own. Text or binary content; error-correction level and size where a kind has
  them.
- **The family's rules.** Nothing runs off the caller's thread (rule 1). zxing-cpp throws, and
  every export runs inside a firewall that turns a throw into a refused call (rule 2). No
  call throws on a bad picture or a bad argument: a refused call returns empty and
  `bcLastError()` says why.

## Quick taste

```livecodescript
on scanPhoto
   local tFound, tBarcode
   put bcRead(the imageData of image "photo", the width of image "photo", the height of image "photo") into tFound
   repeat for each element tBarcode in tFound
      put tBarcode["format"] & ": " & tBarcode["text"] & return after field "log"
   end repeat
end scanPhoto

on makeCode pText
   local tPicture
   put bcCreate(pText, "QR Code", 6) into tPicture             -- 6 pixels a square
   set the width of image "code" to tPicture["width"]
   set the height of image "code" to tPicture["height"]
   set the imageData of image "code" to tPicture["imageData"]
end makeCode
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test creates a barcode of EVERY kind the library can
  write, draws it and reads it back, then reads barcodes turned, mirrored, inverted and side
  by side, and makes every refusal; clean under ASan/UBSan. A second test
  (`tests/fuzz_test.cpp`) damages the pictures and makes random calls. Both also pass as a
  32-bit build and as WebAssembly under node.
- **On an engine**, the same day: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, made and read barcodes of fourteen kinds, carried text beyond ASCII
  and binary data through a QR code, set a created barcode on an image object and read the
  image back, and called every public handler once.
- **The committed libraries** under `src/code/` (2026-11-21: six desktop platforms, four
  Android ABIs, a web archive) were tested where they were built. The same day the engine
  self-test ran again on that server engine over the committed `x86_64-linux` library (80
  checks, none failed), and two more engines loaded committed ones:
  - **In the IDE on Windows**: OXT-Beyond 0.2.8-dp.1 (64-bit) on the maintainer's PC loaded
    the `x86_64-win32` library as an installed extension, and `bcLibraryVersion()` answered
    `barcodext ABI 1; zxing-cpp 3.1.1`. Barcode Studio, the community gallery's demo, then
    played its first scene there: a QR Code typed a letter at a time, each made in under a
    millisecond (`bcCreateMatrix`, `bcCreateAdvanced`) and read back.
  - **On Android**: OXT-Beyond's Android check built the extension into an app (its pull
    request 614), and on an Android 16 x86_64 emulator `bcLibraryVersion()` answered the same.
- **Not yet:** no IDE on Linux or a Mac has loaded it; no engine on macOS or the web, and no
  ARM or 32-bit library on any engine, has run it; and on Windows and Android only what is
  listed above ran. Beyond these records it is verified statically; needs an OXT pass. No
  photograph from a real camera has been read by it here: every picture the tests and the
  demo read was drawn by the library's own writer.

## Building and testing

```sh
cmake -S . -B build -DBARCODEXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DBARCODEXT_BUILD_TESTS=ON -DBARCODEXT_SANITIZE=address && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C++20 compiler and CMake 3.22 are all it needs; zxing-cpp is fetched at configure time.
[docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - reading, making, the kinds, the options,
  the limits.
- [docs/api-reference.md](docs/api-reference.md) - every `bc*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

barcodext is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`barcodext/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/barcodext: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `barcodext/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port barcodext --ref pull/<n>/head`, keeping its
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

- `tools/check-livecodescript.py`, `tools/check-shim-coverage.py`, `tools/test-shim-coverage.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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

## License

MIT (see [LICENSE](LICENSE)). zxing-cpp is under the Apache License 2.0; the Zint backend and
libzueci it carries are BSD 3-Clause. Every text is in the same file.
