# curlxt

**libcurl - HTTP(S), FTP(S), SFTP, SCP, SMTP(S) and WebSockets - for OpenXTalk / the xTalk
family, with the tsNet calls for stacks written for LiveCode's tsNet external.**

LiveCode Indy and Business shipped tsNet, a closed-source libcurl external, from 8.1 onward.
Community never had it, so OpenXTalk never had it either: a stack that calls `tsNetGet` or
`tsNetSmtpSync` stops at the first call, and the only built-in transport is libURL, a script
library over the engine's sockets (HTTP/1.1 and FTP, no SFTP, no SMTP). curlxt binds
[libcurl](https://curl.se/) 8.22.0 (with libssh2 1.11.1 for SFTP) behind the family's flat
`extern "C"` shim and thin LCB layer, and adds two script libraries on top:

```
libcurl 8.22.0 + libssh2 1.11.1 (static)       the transfers
   |- C++ shim   src/curl_shim.cpp  ->  curlxt.{so,dll,dylib}     (ABI: cux_*, v2)
        |- LCB binding  src/curl.lcb        (org.openxtalk.library.curl; public cu*)
             |- src/curl-helpers.livecodescript   (the pump and everyday calls; cu*)
                  |- src/tsnet.livecodescript     (the tsNet calls, by name; tsNet*)
```

It is ORIGINAL code. The tsNet layer was written from the public tsNet dictionary entries
only (its names, parameters, callbacks and `tsneterr:` errors); no tsNet code was seen or
used. [docs/tsnet-compat.md](docs/tsnet-compat.md) lists every tsNet call it answers and
every place it may differ. tsNet itself is Charles Warwick's (Techstrategies Solutions),
whose design and documentation these calls follow; curlxt is not affiliated with him or
with LiveCode Ltd.

**Nothing changes for a stack that does not use it.** libURL stays the engine's URL
handler: `get url`, `put ... into url` and `load url` behave exactly as they did.

## What it can do

- **Requests as handles.** `cuRequestNew`, set headers, options and a body, `cuStart`;
  read the outcome with `cuInfo` / `cuText` / `cuBody`; `cuFree`. A stale handle is always
  a harmless no-op.
- **Wait or run in the background.** `cuWait` drives one request to its end; `cuPoll`
  moves every running request a step and lists the ones that ended. The helpers run
  `cuPoll` on a timer only while something is waiting, and send your message when a
  request ends (`cuRequestAsync`).
- **Large transfers stay native.** `outputFile` downloads straight to a file and
  `inputFile` uploads straight from one, so the bytes never cross into script.
- **WebSockets (`ws://` and `wss://`), since 2026-11-20.** A socket is a request handle too:
  `cuWsNew`, the same headers and options (a subprotocol, a token, `caFile`, a proxy),
  `cuStart`. Then `cuWsSendText` / `cuWsSendData` and `cuWsReadText` / `cuWsRead`, whole
  messages both ways (fragments are put back together, pings are answered), and `cuWsClose`
  for the polite ending. The helpers' `cuWsOpen` runs it on the timer and sends your handler
  "open", "text", "binary" and "closed". It uses libcurl's own WebSocket support: no new
  library.
- **Protocols:** http, https, ftp, ftps, sftp, scp, smtp, smtps, ws, wss. Every other
  libcurl protocol is compiled out and refused at run time, so a redirect cannot reach
  `file://`.
- **The family's rules.** No thread of its own and no callback into script (rule 1), an
  exception firewall on every export (rule 2), large payloads kept native (rule 3),
  generation-tagged handles (rule 4).

## Quick taste

```livecodescript
start using stack "curlHelpers"
put cuRequestSync("GET", "https://example.com/", empty, empty, empty, 10000) into tReq
put cuResponse(tReq) into tAnswer           -- ok, responseCode, headers, body, error ...
get cuFree(tReq)

-- in the background
put cuRequestAsync("GET", tURL, empty, empty, empty, the long id of me, "pageArrived") into tReq
on pageArrived pRequest
   put cuResponse(pRequest)["body"] into field "page"
   get cuFree(pRequest)
end pageArrived
```

A WebSocket, with the helpers running the timer:

```livecodescript
put cuWsOpen("wss://example.com/chat", empty, empty, the long id of me, "chatEvent") into sSocket

on chatEvent pSocket, pWhat, pValue
   switch pWhat
      case "open"
         get cuWsSendText(pSocket, "hello")
         break
      case "text"
         put pValue & return after field "Log"
         break
      case "closed"                          -- always arrives, once; pValue is the close code
         get cuFree(pSocket)
         break
   end switch
end chatEvent
```

And a tsNet-era script runs as written once the tsNet library is in use:

```livecodescript
start using stack "curlHelpers"
start using stack "tsNetCompat"
put tsNetGetSync("https://example.com/", tHeaders, tRespHeaders, tResult, tBytes) into tData
if tData begins with "tsneterr:" then answer tData
```

## The demo

`examples/curlxt-live.livecodescript`, **curlxt Live**, shows the extension at work in
OXT-Beyond's look: five scenes that run themselves, against a server the stack runs itself on
the engine's own sockets, so it needs no network and nothing set up.

1. **Round trips**: a message every 120 ms over a WebSocket, each round trip drawn as it lands;
   the stack opens into this scene, and it keeps one round trip a second going afterwards.
2. **Text and bytes**: plain, accented, Greek and Japanese text, every byte value, random bytes
   and two big messages, each checked identical when it comes back.
3. **Full speed**: for eight seconds, 64 messages of 1 KB always in flight, the rate drawn every
   quarter second and every echo checked to come back in the order it was sent.
4. **Many requests at once**: sixteen requests started together with `cuRequestAsync` (GET,
   POST, HEAD), one through `tsNetGet`, and one out to the internet, which says plainly when
   there is no network.
5. **Close and reconnect**: a clean close (1000), the server going away (1001), retries while
   nothing listens, and the reconnect once it is back on the same port.

Open it from the suite's `start-here.livecodescript`, or paste it into a stack script and
close and reopen the stack. It carries curlxt's two script libraries, so there is nothing to
put in use, and its boot self-check says in its log what it checked before the first scene.

## Status

The shim and its smoke test are verified natively (the whole exported surface against loopback HTTP
and WebSocket servers, clean under ASan/UBSan). The helpers and the tsNet layer RUN headlessly over
the built library against loopback HTTP, SMTP and WebSocket servers
(`tools/check-script-vectors.py`, on the family's interpreter). The binding and both layers also RUN
on a real engine, OXT-Beyond's headless Linux server engine: `tests/engine-selftest.lc`, driven by
`tools/run-engine-selftest.py` against the same servers, in the native lane on every change
(2026-11-21 below). The binaries come from the suite's release-binaries dispatch (2026-11-14,
rebuilt 2026-11-15 with the file-download fixes); since 2026-11-21 every committed library, the
six desktop rows and the four Android ABIs, is the ABI 2 build of run 44825160471 (from ac22df8,
commit 02b4238).

**WebSockets (2026-11-20, ABI 2).** Added on libcurl's own WebSocket support, as new handlers only:
every handler, option, number and result that existed before is as it was, `cuPoll` never lists a
socket, and a stack that opens none sees no difference. The smoke test drives the six new exports
against a WebSocket server it runs itself (clean under ASan/UBSan), and the helpers' calls run
headlessly over the built library against `ws://` and, with a certificate made for the run, `wss://`
servers. On 2026-11-21 OXT-Beyond's headless Linux server engine opened `ws://` and `wss://` sockets
through the binding and the helpers, and the same day OXT-Beyond's IDE on Windows opened them too:
`ws://` in the demo's scenes, and `wss://` over Schannel to a public echo service through the binding
and the helpers (the records below). No mac or Android engine and no Linux or mac IDE has opened one
yet: needs an OXT pass there. The ABI number moved from 1 to 2, so the `.lcb` and the
native library must come from the same build, as always. There is no web (Emscripten) build of
curlxt, so none of this reaches an HTML5 standalone; a browser has its own WebSocket.

**Control frames (2026-11-21).** A review found that pings and pongs had no bound: a peer that
pinged and never read made the shim queue one pong per ping without limit, and a flood of control
frames could hold one pump for as long as it lasted. Now at most one answer waits behind the frame
being sent (a later ping replaces it, as RFC 6455 allows, so the last pong out answers the last
ping), and one pass over a socket handles at most 1024 pings and pongs. The smoke test floods
200,000 pings at a client whose answers cannot leave, and 5,000 pongs in one write; its three new
checks failed on the earlier shim and pass now, clean under ASan/UBSan. A script sees the
difference only under such a flood: `wsQueuedBytes` stays small, and a burst of pongs is counted
in `wsPongs` over several pumps instead of one.

**`cuWsWait` with a message waiting (2026-11-21, the owner's choice).** `cuWsWait` answers 1 at
once while a message is waiting to be read. It used to answer without moving anything, so a loop
that waited for something later, such as the close, with a message unread spun in place: the
engine test's first run lost eight checks to it. Now it moves every socket and request once, without
waiting, before it answers, so such a loop ends. Its answers are the same for every call; only the
socket moves on meanwhile. The loop still never pauses, so reading the messages first, or looping
on `cuWsPoll` with a short `wait`, stays the better way. The smoke test and the engine test each
pin it with a server that sends a message and closes only when the client then says so: on the
earlier shim two of the smoke test's three new checks failed, and one of the engine test's three
(the loop ran out its five seconds with the socket still open), and all six pass now.

**Android (2026-11-18).** `src/code/` also carries this library for `arm64-android`,
`armv7-android`, `x86_64-android` and `x86-android` (Android 5.0, API 21, and up), built by the
suite's `tools/build-android.sh` and landed by its `release-binaries.yml` dispatch. Its smoke test
ran on an Android 5.0 emulator for the two x86 ids, and the ABI 2 build's tests ran there again
in run 44825160471 (2026-11-21), whose Android rows fail unless every member's tests ran; the two
ARM libraries are built and statically checked, not run. An OXT engine on Android first loaded
this library on 2026-11-19, as the ABI 1 build committed before that run: an app OXT-Beyond's CI
built with the suite's extensions ran on x86_64 emulators (Android 13, and Android 16 with 16 KB
pages), where `cuLibraryVersion()` answered, its certificate count 149 on Android 16. That is one
call on the ABI 1 `x86_64-android` library. No Android engine has loaded the ABI 2 files
committed here now, this member's selftest has not run on an Android engine, and no engine has
loaded an `x86-android` or an ARM library: needs an OXT pass on Android. The `.lcb` declares
Android's INTERNET permission, which OXT-Beyond's standalone builder adds to an app that
includes this extension.

**First engine records, Windows x86-64, on the 2026-11-14 `x86_64-win32` DLL, the one before
the 2026-11-15 rebuild:**
- 2026-11-14: OXT-Beyond's own Windows CI loaded the three extensions as built in. It ran
  `cuLibraryVersion()` (`curlxt ABI 1; libcurl/8.22.0 Schannel libssh2/1.11.1`),
  `cuWaitingCount()` and `tsNetVersion()` (1.4.5), and found only system DLL imports.
- 2026-11-15, the same build on the maintainer's Windows PC through the MCP bridge:
  - `tsNetGetSync` fetched a page (200);
  - an async `tsNetGet` called back;
  - expired.badssl.com failed with 35.
  - `cuRequestAsync`, five at once with the expired one among them: the expired one failed in
    116-314 ms each of four runs, with no pump call over 108 ms.

**Engine record, Linux x86-64 (2026-11-21).** OXT-Beyond 0.2.7-rc.6's `lc-compile -Werror` compiled
`src/curl.lcb`, and that release's headless server engine (9.7.1-OXT) loaded it over a library built
from this tree (`curlxt ABI 2; libcurl/8.22.0 OpenSSL/3.5.9 libssh2/1.11.1`) and ran
`tests/engine-selftest.lc`: 138 checks, none failed. It called every public handler of the binding;
made GET and POST requests and waited for and polled them; ran `cuRequestSync`, `cuRequestAsync`
with its callback, `tsNetVersion`, `tsNetGetSync` and `tsNetClose`; and opened `ws://` and `wss://`
sockets through the binding and through the helpers' timer: text, UTF-8, binary, fragmented and
burst messages, ping and pong, the peer's close, a dropped connection, the close timeout, the
message cap (1009), a refused upgrade, a dead port and a refused certificate. The same day it ran
again over the COMMITTED `x86_64-linux` library, the ABI 2 release build of run 44825160471 (the
same version line): 138 checks, none failed.

**The demo on an engine, Linux x86-64 (2026-11-21).** `examples/curlxt-live.livecodescript` ran
start to finish on OXT-Beyond 0.2.7-rc.6's desktop engine (9.7.1-OXT) with no screen, over a library
built from this tree: `tests/engine-demo.livecodescript`, driven by `tools/run-engine-demo.py` in the
native lane on every change, made 26 checks, none failed. The boot self-check was green; scene 1
started by itself and kept going; every scene reached its own verdict (all 8 messages back
identical, over 11,000 echoes in 8.1 s every one in order, 15 of 15 local requests answered, the server's
1001 heard and the reconnect made); closing left no request, socket or listener behind; and the
demo opened and ran again. It ran again the same day over the committed `x86_64-linux` library:
26 checks, none failed (12,453 echoes in 8.1 s at full speed). Neither run sees anything drawn.

**The demo on Windows (2026-11-21).** OXT-Beyond 0.2.8-dp.1's IDE on Windows x86-64 opened it over
its built-in curlxt 0.1.0 (ABI 1, so scene 4 was the one that could run): the boot self-check was
green and scene 4 ran, but the window opened 430 px off the screen, every one-line label had its
top cut off, building the window held the IDE for 22.7 s, and the HEAD tile failed. That tile was
the demo's own server closing a new connection under an id Windows had just given it (the suite's
engine note 6.20), which cost one request in four on that machine the same day, GETs too. With the
fixes (the server lets the client close and closes a straggler only by its serial, the window is
centred, messages are locked while the window is built, a running tile says so and a failed one's
reason goes to the log) the demo ran there again the same day, from commit f5309f5 in a new stack:
the boot self-check green (26 passed, the WebSocket scenes skipped), the window centred and open in
1.6 s, and scene 4 run seven times, 105 of 105 local requests answered, HEAD included. The labels
were still cut: a field lays its first line out 6 px above its top margin (the suite's engine note
5.19), and the demo's margins were 2. Every field's top margin is 6 since, and the demo ran there
once more from commit 104f95a, rebuilding its window on reopen in 0.34 s: every label whole, the
boot self-check green (27 passed, among them its new measure of each field's first line, all 47
inside; on Linux that measure fails all 46 quiet fields with the old margins), and scene 4 seven
times more, 105 of 105 answered.

**WebSockets on Windows (2026-11-21).** The same IDE then ran the WebSocket scenes over ABI 2: the
binding compiled there by the IDE's own `lc-compile -Werror` from commit 104f95a and loaded in place
of the built-in 0.1.0, over the committed `x86_64-win32` library of run 44825160471
(`curlxt ABI 2; libcurl/8.22.0 Schannel libssh2/1.11.1`), the demo's script also from 104f95a. The
boot self-check was green (28 passed, none failed). Scene 1 started by itself and made 84 round
trips, 18.3 ms on average and 16 ms at the fastest (Linux's desktop engine: 98, 6.3 ms and under 1
ms), and kept going; scene 2 had all 8 back identical; scene 3 echoed 1,199 messages in 8.5 s, every
one back in order (141 a second, where Linux has about 1,450); scene 4 answered 15 of 15 local
requests and reached the internet over https; and scene 5 closed cleanly (1000), heard the server
go (1001), found nothing there twice and reconnected 3.1 s after it went. No scene stopped on an
error, closing the demo left no request or socket behind, and it opened again in 0.29 s with a
green boot self-check and scene 1 running. The window was looked at during scene 1: every label
whole. The slower round trips match the 16 ms tick of Windows' timers (inferred, not measured). In
the same session `wss://echo.websocket.org/` answered over Schannel through the binding (opened in
0.35 s; a UTF-8 text message and a 7-byte binary one back identical; a ping's pong; a close with
1000) and through the helpers: `cuWsOpen` with a handler that sent on "open", the socket then left
idle for 85 s and still open (each message once and in order, then "closed" once with 1000), and
`cuWsOpenSync` with `cuWsWait` and `cuWsReadText`. The IDE answered throughout. The demo's look on
Linux, mac and Android, and the demo in those IDEs, are verified statically; needs an OXT pass.

The rest (SFTP, SCP, SMTP, FTP, uploads, the Linux IDE and mac) is verified statically; needs an
OXT pass.

## Building and testing

```sh
cmake -S . -B build -DCURLXT_BUILD_TESTS=ON && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DCURLXT_BUILD_TESTS=ON -DCURLXT_SANITIZE=address && cmake --build build-asan -j && (cd build-asan && ctest)
CURLXT_LIB=build/curlxt.so bash tools/run-gates.sh
```

Linux and macOS need OpenSSL 3 development files; Windows uses Schannel and needs nothing
extra. [docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/api-reference.md](docs/api-reference.md) - every `cu*` handler, option and field.
- [docs/tsnet-compat.md](docs/tsnet-compat.md) - the tsNet calls, and where they may differ.
- [docs/building.md](docs/building.md) - dependencies, sanitizers, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

curlxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`curlxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/curlxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `curlxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port curlxt --ref pull/<n>/head`, keeping its
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

**Sibling members this member's gates need beside it.** `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
reaches into these siblings, found as `../<name>` beside this checkout:

- `../riptide` from https://github.com/SethMorrowSoftware/RipTide - `tools/check-demo-boot.py`, the runner `tools/check-script-vectors.py` runs the helpers and the tsNet layer on.
- `../nostrxt` from https://github.com/SethMorrowSoftware/NostrXT - what riptide's runner loads at import time.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `curlxt`), or point `XTALK_SIBLINGS` at a
directory holding them (`XTALK_SIBLING_<NAME>` for one). The generated
`.github/workflows/gates.yml` takes them from the suite itself, at the
commit named by this repository's newest `Suite-Commit:` trailer - the
versions the suite's gates ran with this tree - and sets
`XTALK_REQUIRE_SIBLINGS=1` so a missing sibling fails the job rather
than skipping its tier. Nothing the SHIPPED code needs is beside it: a
demo that uses a sibling's library carries its own copy (below).

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/curlxt-live.livecodescript`.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/curlxt-live.livecodescript` carries `src/curl-helpers.livecodescript`; `examples/curlxt-live.livecodescript` carries `src/tsnet.livecodescript`.
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

## License

MIT (see [LICENSE](LICENSE)); libcurl, libssh2 and OpenSSL under their own licenses
([THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)).
