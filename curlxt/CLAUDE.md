# CLAUDE.md

Guidance for Claude Code in the curlxt member of the xtalk-suite monorepo (`curlxt/`). Where
anything disagrees, the code and this file win.

## What this is

**curlxt** binds libcurl 8.22.0 (with libssh2 1.11.1 for SFTP/SCP) for OXT: libcurl and
libssh2 (static, PIC, FetchContent from pinned release tarballs with SHA256) -> the C++ shim
`src/curl_shim.cpp` (exports `cux_*`, **ABI 2**: `CUX_ABI_VERSION` in `src/cux_abi.h` equals
`kABIVersion` in `src/curl.lcb`) -> ONE library `curlxt.{so,dll,dylib}` (bare token) -> the
LCB binding `src/curl.lcb` (`org.openxtalk.library.curl`, public `cu*`) -> the helpers
`src/curl-helpers.livecodescript` (stack `curlHelpers`, public `cu*`) -> the tsNet calls
`src/tsnet.livecodescript` (stack `tsNetCompat`, public `tsNet*`, private `tsnx*`).
TLS: Schannel on Windows; OpenSSL elsewhere (static 3.5.9 in the 64-bit Linux and mac release
builds, the system's in the 32-bit Linux one: "Release builds" below).

## The rules

1. **Never call script from a foreign thread - PUMP OR NOTHING** (enetxt's model). The shim
   starts no thread; libcurl's write/read/seek/header callbacks run inside
   `curl_multi_perform`, inside `cux_poll` or `cux_wait`, on the script thread, and only
   copy bytes. A started request moves only while one of those two runs.
2. **The exception firewall.** Every `cux_*` body runs inside `CUX_GUARD_*`: one declaration
   per line inside a guard body, and no preprocessor directive inside one (hoist it into a
   helper, as `open_utf8` does; MSVC C2121). The libcurl callbacks catch everything too.
3. **Payload stays native where it can**: `outputFile` / `inputFile`. An in-memory body
   crosses once, on `cux_body`, into a block allocated for it and freed at once (never the
   shared scratch buffer, which would hold a large body for the life of the process).
4. **A shim change is done when `curl_smoke_test` is green under ASan/UBSan**
   (`-DCURLXT_SANITIZE=address`; gcc). Native-library changes refresh the committed binaries
   through the suite's `release-binaries.yml`; `native-curlxt.yml` never commits.
5. **Every enum in `cux_abi.h` is APPEND-ONLY; an ABI change bumps `CUX_ABI_VERSION` and
   `kABIVersion` together.** `tools/check-abi-registry.py` proves every constant, every
   foreign bind and every name table (fixture: `tools/test-abi-registry.py`).
6. **Script is done when `tools/check-livecodescript.py` AND `tools/check-script-vectors.py`
   pass.** The second RUNS the helpers and tsNet layers on the family's interpreter with every
   `cu*` bound to the built library through ctypes, against loopback HTTP and SMTP servers;
   it SKIPs without a library (`$CURLXT_LIB`, or a committed x86_64-linux build) unless
   `CURLXT_REQUIRE_LIB=1`, which the native lane sets. Labels stay "verified statically;
   needs an OXT pass" until an engine runs it.
7. **Compatibility is the point of the tsNet layer.** Its names, parameter orders and
   callback parameters follow the public tsNet dictionary only (docs/tsnet-compat.md marks
   the two entries that could not be read). Never change one to taste; never take tsNet code.
   It must never touch libURL: a stack that does not use it must behave exactly as before.
8. **The engine run is `tests/engine-selftest.lc`** (since 2026-11-21): the root
   `native-curlxt.yml` `engine` job compiles the binding with OXT-Beyond's `lc-compile
   -Werror` and runs the test on that release's headless Linux server engine through
   `tools/run-engine-selftest.py`, against the same loopback servers as rule 6's gate. A new
   public handler goes into the test's SWEEP in the same change (`--check-sweep` is a gate);
   new behaviour gets a check there too. It runs the server engine only: the IDE, Windows,
   mac and Android still need an OXT pass, and a label says which.
9. **The demo runs on an engine too** (since 2026-11-21): the same job runs
   `examples/curlxt-live.livecodescript` start to finish on that release's DESKTOP engine with
   `-ui` and no screen (`tools/run-engine-demo.py`, driver `tests/engine-demo.livecodescript`),
   because the demo serves its own scenes and the server engine delivers no `accept` (the
   suite's engine notes 6.15 and 6.16). The driver waits for each scene's verdict line in the
   demo's log and checks its words: a change to a verdict changes the driver in the same
   change. A change to the demo is done when the native lane's run is green; it sees nothing
   drawn, so the look keeps its "needs an OXT pass" label until a screen shows it.

## As built

- **Out-buffer contract**: text calls return bytes written or `-(bytes needed + 1)`. The LCB
  scratch buffer is never below `kScratchCap` (4096), so a "needed" answer is always below
  `-kScratchCap` and cannot be mistaken for an error code (-1..-7). `cux_body` returns
  `-needed` instead (no NUL): the .lcb asks `bodySize` first and allocates exactly.
- **`cux_poll`** returns finished handles as a comma list and is lossless: a too-small buffer
  leaves the queue intact. `cux_wait` collects ITS request without queueing it (the `quiet`
  flag), and takes a request that had already ended back off the queue.
- **`cux_cancel`** reports the request through `cux_poll` like any ending, result
  `CUX_RESULT_CANCELLED` (1000, outside CURLcode), so a callback always arrives. `cux_free`
  of a running request detaches it silently.
- **Init is refcounted and process-wide** (enetxt's lesson, its gotcha 7): the release that
  reaches zero frees every request. The helpers take ONE hold (`cuHelpersInit`) and give it
  back only in `cuHelpersRelease`.
- **Protocols** are limited at build time (CMake `CURL_DISABLE_*`) and at run time
  (`CURLOPT_PROTOCOLS_STR`, `CURLOPT_REDIR_PROTOCOLS_STR`): no `file://`, ever.
- **CA certificates**: Linux probes the common bundle paths once (`linux_ca_bundle`);
  Windows and macOS ask for the native store (macOS through curl's `USE_APPLE_SECTRUST`:
  OpenSSL alone cannot see the Keychain). `caFile` overrides. No CA path from the build
  machine is compiled in (`CURL_CA_BUNDLE`/`CURL_CA_PATH` are `none`). Android has no bundle
  file: `android_ca_store` reads the system store's folder once
  (`/apex/com.android.conscrypt/cacerts`, else `/system/etc/security/cacerts`) and every
  request gets it as a `CURLOPT_CAINFO_BLOB`; a `caFile` clears the blob for that request
  (`set_ca_file`: curl would otherwise load both), and `cux_version_string` ends with the
  count. User-added certificates are not read. Built for Android 2026-11-18, and the smoke
  test ran that day on an Android 5.0 emulator for both x86 ABIs (157 certificates read from its
  store); the ARM libraries are built, not run, and no engine on Android has loaded any: needs
  an OXT pass on Android.
- **Release builds** (the suite's `release-binaries.yml`): 64-bit Linux and the mac slices
  link a pinned static OpenSSL 3.5.9 (no `libssl.so.3` needed); 32-bit Linux links the
  system's, as datachannelxt does; Windows uses Schannel and the static CRT (`/MT`), so
  `curlxt.dll` needs no Visual C++ Redistributable.
- **WebSockets (ABI 2, 2026-11-20)** use libcurl's own support, no new library. A socket is a
  Request made by `cux_ws_new` (`CURLOPT_CONNECT_ONLY` 2): the multi handle drives the upgrade,
  and the handle then STAYS in the multi handle (libcurl's rule for a connect-only handle in
  use) while `ws_service`, called by `pump()` for every live socket, writes the send queue with
  `curl_ws_send` and reads whole messages with `curl_ws_recv`. What holds it together:
  - **A socket is never listed by `cux_poll`** (`quiet` from birth): that list is consumed by
    its reader, so a handle the helpers' timer does not know would be lost. State is read
    (`wsState`), and `cux_ws_poll` pumps without consuming the list. `cux_wait` refuses a socket.
  - **Whole messages only.** Fragments are reassembled; a message crosses into script once
    (`cux_ws_read`, into a block of its exact size, like `cux_body`).
  - **Both queues are bounded.** Reading stops at 4 MiB (or 4096 messages) unread, so TCP slows
    the peer; `cux_ws_send` refuses past 16 MiB unsent. `maxBodyBytes` caps one message (close
    1009, result 23).
  - **Three things libcurl 8.22 does not do, done in the shim, each measured:** it holds its
    automatic pong until the next frame (so `CURLWS_NOAUTOPONG`, and `ws_service` answers pings,
    after the frame at the head of the queue, never inside it); it does not answer a close
    (`ws_got_close` echoes it); and it applies no timeout to the wait for the upgrade's answer
    (`timeout` and `connectTimeout` are kept on the shim's own clock, and `timeout` is never
    given to libcurl for a socket: it bounds the opening, not the socket's life).
  - **`closed` is one state for every ending**, told apart by `result` (0 a close, a CURLcode a
    failure, 1000 cancelled) and `wsCloseCode` (the peer's, 1005 none, 1006 no close frame,
    0 never opened). The helpers send "open" only to a socket whose upgrade answered 101.
- **Only `cux_*` is exported**: `src/curlxt.map` for GNU ld and a derived
  `-exported_symbols_list` for ld64.
- **The demo** (`examples/curlxt-live.livecodescript`) is one paste-and-run file: the helpers
  and the tsNet layer are EMBEDDED by the suite's `tools/sync-demo-embeds.py`, the boot
  self-check is carried from its master, and its control list is derived
  (`check-demo-control-lists.py --write`). It wears OXT-Beyond's dark look at the owner's
  request (2026-11-21), so the suite's UI-kit gate lists it in `EXEMPT`. Its server answers
  127.0.0.1 only and every write is the background kind; every scene uses curlxt's background
  calls, never `cuRequestSync`, whose wait would hold the very stack that serves it.

## Gotchas

1. **`tO` is the token `to`**: the static gate refused it in the tsNet layer (renamed
   `tOpts`). Use distinctive stems.
2. **The family interpreter has no `filter` and no `@` parameters.** The scripts loop instead
   of `filter`, and avoid by-reference calls between their own handlers;
   `check-script-vectors.py` models `@` only for the calls it makes itself.
3. **`return X for error` does not put a reason in `the result` as text**; the helpers keep the
   last reason in `cuHelpersError()` instead.
4. **No handler-shaped line inside a `/** */` block** (a precaution, not a measured failure):
   an example line starting `on name ...` at column 0 could be read as a handler by a tool
   that splits a script by handlers. Describe the handler in a sentence, as `cuRequestAsync`'s
   block does; the README can show it in full.
5. **The WebSocket test servers answer ANY request with an upgrade.** Point an ordinary request
   at the HTTP server (`base`), never at the WebSocket one.
6. **`cuWsWait` answers 1 at once while a message waits, and moves nothing then** (by contract:
   `cux_ws_wait` looks before it pumps). A loop that waits for a LATER state (closed, a count of
   messages) with messages unread spins in place: the engine test's first run lost eight checks
   to it (2026-11-21). Read the messages first, or loop on `cuWsPoll` with a short `wait`.
7. **The engine's parser is the judge of a `.lc` test**, which `tools/check-livecodescript.py`
   does not read (it reads `.lcb` and `.livecodescript`): `does not contain` is not xTalk (the
   checker's check 7 refuses it in a script; the engine stops the whole file at it), and
   `unicodeText` is a reserved word, so a handler of that name cannot be called.
8. **A chunk inside a chunk needs parentheses when a bound is a sum**: the demo's
   `word 1 to -1 of char tColon + 1 to -1 of tLine` stopped its whole 4,400-line script from
   compiling (the suite's engine note 1.10). The checker cannot see it; the engine run can.
