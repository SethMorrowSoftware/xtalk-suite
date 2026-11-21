# pdfxt

**PDFium - open, draw and read PDF files - for OpenXTalk / the xTalk family.**

[PDFium](https://pdfium.googlesource.com/pdfium/) is the PDF engine of Chromium: the code that
shows a PDF in Chrome, released under the BSD 3-clause and Apache 2.0 licenses. pdfxt binds it
behind the family's flat C shim and a thin LCB layer:

```
PDFium (prebuilt, pinned by SHA-256)      pdfium.{so,dll,dylib}     a second file, beside the shim
   |- C shim   src/pdfium_shim.c  ->  pdfxt.{so,dll,dylib}          (ABI: pdx_*, v1)
        |- LCB binding  src/pdfxt.lcb     (org.openxtalk.library.pdfxt; public pdf*)
```

It reads PDFs: it draws pages, hands back their text, and follows their outline and links. It
does not write, edit, print or fill in a PDF.

## What it can do

- **Open** a file by path or from bytes in memory, with a password if it has one; any number of
  documents at once (4095). A file is read as pages are asked for, so a large one opens at once.
- **Draw** a page at any size as the `imageData` of an image, as a ready BMP picture an image
  takes as its `text`, or one window of a zoomed page (what a viewer scrolls).
- **Read** a page's text, a range of it, the text inside a rectangle, the character under a
  point, and where each character sits, for selection and highlighting.
- **Search** a page, with or without case and whole words, and get the rectangles to highlight.
- **Navigate**: the outline (bookmarks) with levels and pages, the links on a page with their
  rectangles and targets, page labels, page sizes and rotation, the document's information.
- **The family's rules.** No callback runs script, and nothing runs on another thread (rule 1);
  every export validates before it calls PDFium and none can throw across the boundary (rule
  2: the shim is C); a drawing or a text crosses as one block the binding copies at once (rule
  3); a document is a generation-tagged integer, and a closed one is a harmless no-op (rule 4).

## Quick taste

```livecodescript
local sDoc

on showFirstPage pPath
   put pdfOpen(pPath, empty) into sDoc                        -- the path, a password or empty
   if sDoc is 0 then
      answer pdfLastError()
      exit showFirstPage
   end if
   put pdfPageCount(sDoc) && "pages" into field "status"
   set the text of image "page" to pdfRenderPageBMP(sDoc, 1, pdfPageWidth(sDoc, 1), pdfPageHeight(sDoc, 1), 0)
   put pdfPageText(sDoc, 1) into field "text"
end showFirstPage

on closeStack
   pdfClose sDoc
end closeStack
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## Two files, and what they need

pdfxt does not contain PDFium. Each platform's folder holds two libraries, `pdfxt` and `pdfium`,
and the shim loads the second from the folder it is itself in. The standalone builder copies
both. If `pdfium` is missing nothing fails to load: calls return 0 or empty, and
`pdfLastError()` says where it was looked for.

PDFium is taken prebuilt from [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries)
release `chromium/8165` (PDFium 160.0.8165.0, without V8 and without XFA: no JavaScript runs
and no XFA form is drawn). `src/pdfium.pin` pins every archive and every library by SHA-256. Its
builders set its floors, and they are higher than the rest of the suite's:

| Platform | PDFium needs | The suite's other members |
|---|---|---|
| macOS | 13.0 | 10.15 (Intel), 11.0 (Apple silicon) |
| Android | 6.0 (API 23) | 5.0 (API 21) |
| Linux | glibc 2.16 | glibc 2.28 |
| Windows | 64-bit and 32-bit | the same |
| Web | not available | - |

On an older system the extension still loads and every call is refused with a reason.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim against two
  PDFs it carries (three pages with text, shapes, links, an outline and labels; one protected
  by a password) and checks what comes back, down to the colour of single pixels. Clean under
  ASan/UBSan.
- **Natively on every platform it ships for**, by its own lane (`native-pdfxt.yml`, run
  44840908920, 2026-11-21): the same smoke test passed on Windows (x86_64 and x86), macOS
  (arm64, and x86_64 under Rosetta), Linux (x86_64, x86 and arm64) and an Android 6.0 emulator
  (x86_64 and x86, 183 checks each). On an Android 5.0 emulator only its 12 refusal checks
  could run, and it said so. The ARM Android libraries were built and checked, not run.
- **On an engine**, on 2026-11-20: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, opened both PDFs, drew pages into real images both ways, read text and
  searched it, walked the outline and links, and called every public handler once.
- **The demo stack**, `examples/pdfxt-demo.livecodescript` (paste it into a stack's script and
  reopen the stack): a PDF viewer in OXT-Beyond's dark showcase look, with a five-page sample
  built in and a locked one. It opens playing a tour of five self-running scenes (a deep zoom
  where only the window in view is drawn, a word found with every match marked, a page read by
  character, by box and by click, the outline and the links followed, a locked PDF unlocked),
  and any click hands the window over: zoom and scroll, the outline, links, search, a page's
  text, the word you click and the text in a box you drag, the document's information and
  permissions, the drawing flags, a page saved as a BMP, and one button that checks all of it.
  Without pdfxt it still opens, and says in red what is missing. `tests/demo-drive.livecodescript`
  drives it on OXT-Beyond's Linux desktop engine with no display (2026-11-21, a locally built
  library): the window built with every colour its own, the tour started by the engine's timer,
  each scene played to its end, the window used the way a person would, the locked sample
  unlocked, its own checks green, and the same window without pdfxt. The native lane repeats
  that on every change. The window's earlier look (the suite UI kit) was opened in the
  maintainer's Windows IDE on 2026-11-21: it built and opened the sample, and under Windows'
  dark appearance its page number and outline drew white on white, which this look was made to
  end. This look met the same PC that day (OXT-Beyond 0.2.8-dp.1, 64-bit, its IDE driven
  remotely, over the `x86_64-win32` library installed there): "Ready (pdfxt ABI 1; PDFium
  chromium/8165)", and the tour started by itself and ran to its end. It also showed three
  faults, fixed the same day: the window opened where it was last saved, partly off a smaller
  screen (it now moves onto the screen when it would not fit); every label's words sat 5
  pixels above it, so the tops of some letters were cut off (a field's first line starts 6
  pixels above its top margin, the suite's engine note 5.18; every margin now allows for it);
  and the toolbar's words sat above the buttons' line, for the same reason. The drive holds
  all three. The fixed window has met Linux only: on Windows it is verified statically; needs
  an OXT pass. Nobody has used the window by hand yet.
- **In the Windows IDE**, on 2026-11-21: the maintainer's 64-bit OXT-Beyond (engine 9.7.1)
  loaded the module, compiled there from this source, over CI's `x86_64-win32` library (run
  44840908920), and `tests/engine-selftest.lc`, run inside the IDE as a script-only stack,
  passed 64 checks and failed 2. The two are the first-load checks (a folder with no PDFium is
  refused, and the reason names it), which cannot hold in a process that has loaded PDFium
  before, and pdfxt had been used in that IDE session before the run. Loading and shutting
  down PDFium first reproduces exactly those two on Linux, so that is the likely cause; a run
  in a fresh IDE session is still owed. The test now reports those two as not checked when it
  runs a second time in one session. Every drawing, text, search, outline and link check
  passed there.
- **Not yet:** no IDE on Linux or a Mac has loaded it, and no engine on macOS or Android has
  run it: on those it is verified statically; needs an OXT pass. No library is committed under
  `src/code/` yet; the suite's release-binaries dispatch lands them.

## Building and testing

```sh
cmake -S . -B build -DPDFXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DPDFXT_BUILD_TESTS=ON -DPDFXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C11 compiler and CMake 3.22 are all it needs; the pinned PDFium archive is fetched at
configure time. [docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - how pages, characters and coordinates
  are counted, a small viewer, the limits, what a refusal looks like.
- [docs/api-reference.md](docs/api-reference.md) - every `pdf*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates, the pin.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). PDFium and the libraries inside it keep their own permissive
licenses: [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) reproduces each.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

pdfxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`pdfxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/pdfxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `pdfxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port pdfxt --ref pull/<n>/head`, keeping its
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

- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
