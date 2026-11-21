# Android

What the suite has for Android, how it is built and checked, what has run and what has not.
Started 2026-11-18. Every claim here is one of three kinds, and says which: **run** (a test
executed on an Android system), **checked** (read from the built file by a tool), or **read**
(taken from source and not observed). Open work is in [WORK-PLAN.md](WORK-PLAN.md), sections 1.2
and 1.3; this page keeps status and method.

## Status in one paragraph

All seven native members (sodiumxt, enetxt, box2dxt, coinxt, curlxt, datachannelxt, torrentxt)
build for the four Android ABIs with one script, `tools/build-android.sh`, and the release
workflow has an `android` job that calls it. Each built library is checked as an Android library
(ABI, API level, what it needs at load time, 16 KB alignment, no text relocations). **The job has
run twice**, both on 2026-11-18 with `lanes: android`, all four rows green both times: run
44379162842 from 7364c0f (`commit_mode: none`), and run 44391791349 from 17b1f93
(`commit_mode: branch`), which **committed the twenty-eight libraries** (commit 5aa3ad4) after
the installer's checks and the whole gate set passed over them. In each run's two x86 rows
**every member's own tests ran on an Android 5.0 x86_64 emulator and passed**, for
`x86_64-android` and `x86-android` (the record is below); a row builds, tests and uploads in one
job, so the fourteen committed x86 libraries are the files the second run tested.
The fourteen ARM libraries were built and checked in both runs and **not run**. **An OXT engine
on Android first loaded them on 2026-11-19**: OXT-Beyond pinned the twenty-eight, and its CI
built an app with all seven extensions and ran it on x86_64 emulators, where every extension's
library loaded and answered one call (the record is below). That is the seven `x86_64-android`
libraries, one call each; no engine has loaded an `x86-android` or an ARM one. curlxt's four
were rebuilt at ABI 2 on 2026-11-21 (release run 44825160471, commit 02b4238, its tests run on
the emulator again for the two x86 ABIs); the engine load was of the ABI 1 files, and no
Android engine has loaded the ABI 2 ones committed now.
**box3dxt joined on 2026-11-20**, after both runs: `tools/build-android.sh` names it as an eighth
member, its own lane (`native-box3dxt.yml`) builds it for the four ABIs with that script and runs
its tests on the emulator for the two x86 ones on every change. Its four libraries were
committed on 2026-11-20 by its own release run (run 44806507517, commit 6d132d3; the x86 ones
tested on the emulator, the ARM ones built and checked, not run). The counts in this page's dated records are of the seven members of those runs.
**audioxt joined the same day**, the same way: a member of `tools/build-android.sh`, built
for the four ABIs and tested on the emulator for the two x86 ones by `native-audioxt.yml`. Its
four libraries were committed on 2026-11-21 from release run 44847619287 (commit 78223d8; the x86
ones tested on the emulator, the ARM ones built and checked, not run).
**render3dxt joined the same day** as a tenth, built and tested the same way by its own lane
(`native-render3dxt.yml`), with no Android library committed yet; its tests carry their model
and picture files inside them, so they run from the folder the emulator is handed.
**pdfxt joined the same day**, as an eleventh member, with one difference from every other: beside its
own library it places `pdfium.so`, a PREBUILT PDFium its shim loads at run time, pinned by SHA-256
in `pdfxt/src/pdfium.pin` and never built or stripped here. That file is its builders' and says
API 23 (Android 6.0), above the suite's floor, so `--android-check` is not asked of it; the pin is.
pdfxt's own lane (`native-pdfxt.yml`) runs its tests on an Android 6.0 emulator for the two x86
ABIs (`tools/android-emulator.sh start 23`, the level `tools/build-android.sh --pins` names as
`companion-api-pdfxt`), and once on the Android 5.0 one, where a test that can run only its
refusals must say so (`XTALK_TEST_PARTIAL`, which `tools/build-android.sh` carries into its last
line as "passed IN PART"); the release job tests pdfxt on the floor, so there it passes IN PART. The lane's run of 2026-11-21 (run 44840908920, from `3f3a348`) RAN it: the smoke
test's 183 checks passed on the Android 6.0 emulator for both x86 ABIs, the Android 5.0 one ran
its 12 refusal checks and said "passed IN PART", and the ARM libraries were built and checked,
not run. None of its Android libraries is committed yet, and no OXT engine on Android has
loaded one.
**xlsxt joined the same day**, the same way: named in `tools/build-android.sh`, built for the four
ABIs and tested on the emulator for the two x86 ones by its own lane (`native-xlsxt.yml`) on every
change. Its four libraries were committed on 2026-11-21 by its own release run (run 44838679488,
commit 0be6db1; the x86 ones tested on the emulator, the ARM ones built and checked, not run).
**gamepadxt (joined the same day too) is not built for Android**, and `tools/build-android.sh` does not
name it: SDL reaches controllers on Android through its own Java activity, which an OXT app does
not have. Its packager names no Android id, so the all-four-or-none rule has nothing to hold.
**torrentxt alone is built for API 24 (Android 7.0) since 2026-11-21.** Its API 21 libraries did
not work inside an app on Android 11 or later (found that day; the record is below, "The torrent
stall"): built for API 21, libtorrent reads the network over a socket those Androids refuse an
app, so a session starts paused and "listen on every address" opens no socket. Built for API 24
libtorrent does not use that socket. Release run 44914897842 rebuilt the four that day (commit
d47060f) and ran the member's tests on an Android 7.0 emulator for the two x86 ABIs, the first
libraries built for API 24 to run on an Android. Those tests run as the shell user, whom Android
does not refuse the socket, so they show the library working on its floor and NOT the fix: no
engine has loaded the rebuilt four, and no app on Android 11 or later has started a session of
them (work plan 1.2 #33).
So five of the seven members' `x86_64-android` libraries are: native tests run on an Android
emulator, and loaded by an engine in an app for one call each (curlxt's and torrentxt's were
rebuilt after that load, above, and the files committed now have not been loaded); a member's own
selftest on an Android engine is still owed. Every other `x86_64-android` and every `x86-android`
library: native tests run on an Android emulator; needs an OXT pass on Android. The ARM libraries
are: built and verified statically; needs an OXT pass on Android.

## The four platform ids

OXT-Beyond's Android standalone builder takes an extension's native code from
`code/<arch>-android/` and packs it into the app as `lib<name>.so` (read in OXT-Beyond's
`ide-support/revsaveasandroidstandalone.livecodescript` and `revsblibrary.livecodescript`,
2026-11-18; not observed). The four folder names are its `kAndroidArchitectures`:

| Platform id | Android ABI | Devices | Tests in CI |
|---|---|---|---|
| `arm64-android` | arm64-v8a | nearly every phone and tablet since about 2017 | built, not run |
| `armv7-android` | armeabi-v7a | older and low-end 32-bit devices | built, not run |
| `x86_64-android` | x86_64 | emulators, some Chromebooks | run on an Android 5.0 emulator (torrentxt's: Android 7.0, from its next build) |
| `x86-android` | x86 | older emulators | run on the same emulator |

The two ARM rows are the ones real devices use and the ones CI cannot run: a hosted runner runs an
x86 Android under KVM at speed and an ARM one not at all. They are built by the same recipe from
the same source and pass the same static checks. That is evidence about the recipe, not a run, and
the job's summary says "built, NOT RUN" for them, per member. The first execution of an ARM
library will be on a device or an ARM emulator, through an app built with OXT-Beyond.

## How a library is built

```sh
export ANDROID_NDK_HOME=/path/to/android-ndk      # the pinned revision
bash tools/build-android.sh enetxt arm64-android  # writes enetxt/src/code/arm64-android/enetxt.so
bash tools/build-android.sh --list                # the members and platform ids
bash tools/build-android.sh --pins                # the NDK, API level, OpenSSL and Boost pins
bash tools/build-android.sh --api torrentxt       # the Android API level one member is built for
bash tools/build-android.sh --companion pdfxt     # the file one member ships beside its own (pdfium.so)
```

- **One NDK, pinned** (`--pins` prints it): the revision OXT-Beyond's `config/android-ndk-version`
  names, so the libraries and the engine that loads them come from one compiler. Another revision
  is refused; `XTALK_ANDROID_ANY_NDK=1` is for a trial, and says its output must not be committed.
- **API 21 (Android 5.0)** is the floor, as for OXT-Beyond's own Android engine.
- **torrentxt alone is built for API 24 (Android 7.0)**, since 2026-11-21 (the owner's choice that
  day, over keeping API 21 with a patch to libtorrent). libtorrent decides at COMPILE time how it
  learns the device's addresses: below API 24 over a NETLINK_ROUTE socket, as on Linux; from API 24
  with `getifaddrs()`, which bionic has from that level. Android 11 and later refuse an app the
  netlink socket, so only the second works there ("The torrent stall" below). The cost is that an
  app using torrentxt needs Android 7.0; every other member keeps Android 5.0. The OpenSSL torrentxt
  links stays built for API 21, because curlxt and datachannelxt share that build.
- **libc++ is linked into each library** (`ANDROID_STL=c++_static`). Each exports a C ABI only, so
  no C++ object crosses a library boundary; the alternative, `libc++_shared.so`, is a file every
  app would have to carry.
- **16 KB segment alignment on the 64-bit ABIs** (the pinned NDK's default), which Android 15's
  16 KB devices need.
- **Dependencies are the desktop pins**: curlxt, datachannelxt and torrentxt link a static OpenSSL
  built for the ABI from the same hash-checked tarball the desktop lanes use, and torrentxt takes
  the same Boost headers. `tools/test-build-android.py` fails when the script's pins and the
  workflow's disagree.
- **coinxt builds through its own `native/build.sh`**, as on every platform (`pack <platform-id>`,
  with the NDK's compiler as `CC`); its self-test builds for Android with the new `selftest` mode.

The script is the whole recipe. The workflow's `android` job is four rows (one per ABI) that call
it once per member, so what a person builds with the NDK is what CI builds.

## What is checked on every built library

`python3 tools/install-release-binaries.py --android-check <library>` runs where the library is
born (the build script's last step), and the installer runs the same checks again on the bundle
before anything is committed:

| Check | Why |
|---|---|
| ELF class and machine match the platform id | a build for another ABI filed under this one |
| the NDK's Android note is present | a Linux library loads nowhere on a device |
| the note's API level is 21 or lower | a higher one may import what an older Android lacks |
| torrentxt: the note's API level is exactly 24 | a higher one as above; a LOWER one is the build that loads and then does not work in an app on Android 11 or later |
| everything in `DT_NEEDED` is one of Android's own libraries | notably never `libc++_shared.so` |
| no text relocations | Android 6.0 and later refuse such a library |
| 64-bit: every loadable segment aligned to 16 KB | Android 15's 16 KB devices |

The reverse is checked too: a library carrying the Android note is refused under a `-linux` id.
`--selftest` holds each refusal with a synthesised library that differs from an accepted one in
that one property.

`tools/check-binary-freshness.py` reads the Android libraries like the other ELF platforms: every
symbol the `.lcb` binds is exported, every non-static shim definition is exported, and the ABI
number is decoded from the function's machine code. Two instruction-set shapes are new for that
(32-bit ARM, Thumb or ARM as the symbol says, and the frame the NDK's toolchain gives 32-bit x86),
each an exact sequence with recorded vectors and near misses in `tools/test-binary-freshness.py`.

## What is run, and where

Each member's own native tests (the ones `ctest` runs on a desktop) are built for Android in every
row. With a device (`XTALK_ANDROID_SERIAL`), `tools/build-android.sh` runs each of them there
through `tools/android-run.sh`, which pushes the test and the library to the device, runs it, and
reports the test's own exit status (read from a marker line: adb before Android 7.0 does not carry
exit statuses; `tools/test-android-run.py` holds that against a fake adb).

In CI the device is an Android 5.0 x86_64 emulator, `tools/android-emulator.sh`: the floor the
libraries are built for, on a real Android libc, loader and certificate store. Its 64-bit system
runs 32-bit x86 programs too, so it serves both x86 rows. The job fails an emulator row in which
any member's tests did not run.

torrentxt's tests need its own floor, Android 7.0: built for API 24, the library does not load on
the Android 5.0 image. `tools/android-emulator.sh start 24` boots the same kind of image for that
level, the job stops the first emulator and boots that one where torrentxt comes up in the list
(asking `tools/build-android.sh --api <member>`, never a copied number), and the build script
refuses, before it builds, a member whose level is above the device's. The script boots one more
level, 23 (Android 6.0), for pdfxt's own lane: pdfxt is built for API 21, but the prebuilt PDFium
it loads was built for API 23, and only there do its tests open a PDF (above, and
`companion-api-pdfxt` in `--pins`). None of that has run in CI
yet: it is held by `tools/test-build-android.py` against a fake adb, and the next release dispatch
with the Android lane is its first run.

What the emulator cannot show is the failure this floor exists for. A test runs there as the shell
user (`tools/android-run.sh`), and the refusal is Android's rule for an APP, so torrentxt's API 21
library passed every test on it. The run that has an app is OXT-Beyond's (its Android workflow
drives each pinned library from inside one, on Android 13 and 16). What the suite holds itself is
the consequence: `torrent_smoke_test`'s last row asks that a new session is not paused, listens,
and checks a local file to seeding, and on Linux the ctest `torrent_smoke_netlink_refused` runs
that row under a preloaded library that refuses the two netlink calls and requires it to fail on
exactly those checks (`torrentxt/tests/netlink_refused_preload.c`).

**The record, 2026-11-18** (run 44379162842 from 7364c0f, read from the two emulator rows'
logs). The boot step passed, and `tools/android-emulator.sh` fails it unless the device reports
API 21 (its own line was not read back for this record). On the emulator, for each of
`x86_64-android` and `x86-android`: box2dxt's smoke test (304 checks); coinxt's self-test (hashes,
secp256k1, BIP-32/39, BIP-340/341); curlxt's smoke test (98 checks), whose shim read 157
certificates from the emulator's system store; datachannelxt's three tests, the smoke test over a
live libdatachannel loopback; torrentxt's four tests, `rp1_integration_test` delivering a message
between two sessions on loopback. sodiumxt's and enetxt's tests ran too: the job counts the
members whose line says `tests RUN on` and fails a row that is short of all seven, and both rows
passed that count (their own output was not read back for this record). What the run does NOT
show: a FAILING test on a real device. Every status the runner read from its marker line was 0,
so the path a failure takes is still held only by `tools/test-android-run.py`'s fake adb.

**The landing, 2026-11-18** (run 44391791349 from 17b1f93, `commit_mode: branch`; commit
5aa3ad4). All four rows green again, the two emulator rows past the job's count of seven members
whose tests ran (the tests' own output was not read back a second time). The commit job installed
twenty-eight new libraries, four per member, each through
`tools/install-release-binaries.py`'s Android checks, added four lines to each member's
`src/code/MANIFEST.sha256`, and ran the whole gate set with `--installing` before it pushed. The
change after it added the four ids to every member's `ships` row, so the freshness gate now
demands all of them.

**The first engine load, 2026-11-19** (OXT-Beyond pull request 572, head 7f66366, merged as
6bab006; its `Android builder on linux-x86_64` job, run 44456373273). OXT-Beyond pinned the seven
members at the commits the publisher carried the Android libraries to, and all twenty-eight
pinned SHA-256s equal the ones 5aa3ad4 committed (compared 2026-11-21). Its CI built one app with
OXT-Beyond's Android builder (the 0.2.8-dp.1 package with that pull request's builder), the seven
`.lcb` extensions chosen in its standalone settings, for all four ABIs, and checked that the
package held `lib/<abi>/lib<name>.so` for every extension and ABI. On an Android 16 x86_64
emulator with 16 KB pages (API 36) the app's `openStack` called one handler of each extension
inside a `try`, and each answered (read back from the job's log): sodiumxt's `sxVersion()`
`SodiumXT 0.1.0 (libsodium 1.0.22)`; enetxt's `enLibraryVersion()` `enet 1.3.18`; datachannelxt's
`dcLibraryVersion()` `libdatachannel v0.24.5`; box2dxt's `b2Version()` `4`; coinxt's
`cxKeccak256Len()` `32`; torrentxt's `btLastError()` empty; curlxt's `cuLibraryVersion()`
`curlxt ABI 1; libcurl/8.22.0 OpenSSL/3.5.9 libssh2/1.11.1; Android CA store: 149 certificates`,
so its certificate reader ran inside an app, on the conscrypt path the Android 5.0 emulator does
not have. `dumpsys package` showed the app holding INTERNET, which nothing but the four bindings'
`metadata android.permissions` line asked for (the probe's settings name no permission: read in
OXT-Beyond's `tools/ci/android-check.livecodescript`). The same step ran first on an Android 13
emulator (API 33) and fails the job unless every extension answers; the job passed, and that
step's lines were not read back for this record (INFERRED from the workflow and its result).
What this is NOT: a member's selftest. One call per extension shows that the library loads from
the package, the binding resolves and that call returns; no socket was opened, no torrent session
started, no world stepped. And the device was x86_64: the
`x86-android` and the ARM libraries rode in the package and were not loaded.

**The torrent stall, 2026-11-21** (OXT-Beyond pull request 609, its `Android builder on
linux-x86_64` job, run 44878092625). That pull request gives the app a functional test per member
in place of one call. On the Android 13 x86_64 emulator seven of its eight tests passed, and
torrentxt's did not: a torrent made of a file the app had just written, added to a session
listening on the loopback, stayed in "checking files" at progress 0 for the test's 20 s, with no
error, while the system log showed the app refused a netlink socket (`avc: denied { bind }` on
`netlink_route_socket`). The step stops the job, so nothing ran on the Android 16 emulator.
As read in libtorrent 2.0.11 (the pinned source): a library built for an Android below API 24
takes the Linux path (`TORRENT_USE_NETLINK`); a session's start-up binds a NETLINK_ROUTE socket to
watch for address changes; Android 11 and later refuse that bind, and the `RTM_GETLINK` request
that lists the interfaces, to an app that targets API 30 or later; and a session answers an
exception in its own start-up by pausing itself (`session_impl::wrap`). A paused session starts no
torrent. The same day the consequence was reproduced on x86_64 Linux, on this suite's torrentxt
build with libtorrent 2.0.11, under a preloaded library refusing those two calls: with the bind
refused a new session answered paused and a torrent of a local file sat at state 1 (checking
files), progress 0, no error, which is what the app showed; with `RTM_GETLINK` refused as well, a
session told to listen on `0.0.0.0` reported no listen port. What is OBSERVED: the stall and the
refused bind on the emulator, and both consequences on Linux under the preload. That the session
in the app was paused was an inference until the pull request's next run asked (run 44887565428,
head 5ce49b7, the same job): on the Android 13 emulator and on the Android 16 one with 16 KB pages
the test read `btSessionIsPaused` true on a new session, resumed it, and the torrent was then
checked and seeding, its answer ending `KNOWN LIMIT: the session started paused and the test had
to resume it`; the Android 13 system log of that run shows the app refused both `bind` and
`nlmsg_readpriv` on `netlink_route_socket`. So OBSERVED on both emulators: a session of the API 21
library is born paused inside an app, and resuming it is enough for a torrent on a named address.
Not exercised there: listening on the unspecified address (the test names the loopback). The fix
chosen is the build level (above); a torrentxt built for API 24 was built locally for
`x86_64-android` that day and imports `getifaddrs` where the API 21 one does not (read from both
files).

**The rebuild at API 24, 2026-11-21** (release run 44914897842 from 3d4db47, `lanes: android`,
`members: torrentxt`, `commit_mode: branch`; commit d47060f, on pull request 201's branch). All
four rows green. It was the first run of the per-member level: each x86 row booted the Android
5.0 emulator, built and tested every other member on it, then stopped it, booted an Android 7.0
one (API 24) and built and tested torrentxt there. Read back from the `x86_64-android` row's log: `booted API 24`,
`torrentxt for x86_64-android (x86_64, API 24, NDK 30.0.16248370)`, the member's four tests
passing on the device (the smoke test with its new last row, `test_local_torrent_seeds`: a new
session not paused, listening, a local file checked to seeding; the record-handle test; the rp1
loopback between two sessions; the rp1 queue test), and the installer's line for the library,
`API 24, needs libdl.so, libm.so, libc.so, aligned to 16384`. From the `x86-android` row's log:
the same four tests passing on the device and `API 24, ... aligned to 4096`; its boot line was not
read back, and the script refuses a device older than the member is built for. The two ARM rows
built and checked the library, not run. The commit job took torrentxt's four files alone
(`members`); the other members' rebuilt libraries were tested and left out.
What this is NOT: the fix seen at work. A test started over adb runs as the shell user, and the
refusal that paused a session is Android's rule for apps; and the emulator is Android 7.0, older
than the Androids that refuse. It shows that a torrentxt built for API 24 loads and runs on the
oldest Android it now supports, and that a session there starts unpaused, listens and seeds. The
proof is an app on Android 11 or later, which OXT-Beyond's Android workflow runs once it pins
these four (work plan 1.2 #33).

Not run anywhere yet: any ARM library; any `x86-android` library on an engine; any member's
selftest or demo on an Android engine; box3dxt's, render3dxt's, pdfxt's and xlsxt's libraries
in an app; a torrentxt built for API 24 on an engine, or in an app at all.

## What differs on Android, per member

| Member | Difference | State |
|---|---|---|
| curlxt | Android has no CA bundle file. The shim reads the system's trusted certificates from `/apex/com.android.conscrypt/cacerts` (Android 14 and later) or `/system/etc/security/cacerts` and gives them to curl in memory. Certificates a user added by hand are not included; `caFile` still overrides, and an empty `caFile` returns to the system store. `cuVersion()` ends with the number of certificates found. | tests run on the emulator 2026-11-18 (both x86 ABIs): 157 certificates read from its store. Loaded by an engine in an app 2026-11-19 (x86_64, one call, the ABI 1 build): 149 certificates on Android 16. Rebuilt at ABI 2 on 2026-11-21 and tested on the emulator again; no Android engine has loaded that build. ARM: built, not run |
| coinxt | Entropy comes from `arc4random_buf` (bionic's, kernel-seeded): `getrandom()` only arrived in API 28 and the library targets API 21. | self-test run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| torrentxt | Built for API 24 (Android 7.0), not 21: libtorrent then learns the device's addresses with `getifaddrs()` and uses no netlink socket, which Android 11 and later refuse an app. On that path libtorrent watches for no address changes (a session does not notice the device moving between networks) and, with no route table to read, listens on the unspecified address itself, which its own source calls a best effort that does not follow BEP 32 and BEP 45 for the IPv6 DHT (read in libtorrent 2.0.11, not exercised). An app must give save paths it may write to (the engine's documents or cache folder, not `/tmp`), and Android stops background network use it has not been told about. | rebuilt at API 24 on 2026-11-21 (run 44914897842, commit d47060f): tests run on an Android 7.0 emulator (both x86 ABIs), as the shell user. No engine has loaded these four, and no app on Android 11 or later has started a session of them: needs an OXT pass on Android. The API 21 builds they replace (tests run on the emulator 2026-11-18, loaded by an engine in an app 2026-11-19 for one call) started a session paused in an app on Android 13 and 16 ("The torrent stall"); an app still carrying those must `btSessionResume` it and name the address to listen on. ARM: built, not run |
| datachannelxt, enetxt | None in the library. | tests run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| box3dxt | None. Box3D picks its AVX2 solver at run time, so the x86_64 library needs no flag; the 32-bit x86 one is built with SSE2 arithmetic; the ARM ones use NEON. | built by the 2026-11-20 release run and committed (6d132d3); tested on the emulator for the two x86 ABIs, the ARM ones not run |
| audioxt | None in the library: miniaudio finds AAudio (API 26 and later) or OpenSL ES at run time and links neither. An app that records must hold the `RECORD_AUDIO` permission, which the binding does NOT declare for it (most stacks only play), and must ask the person at run time. | built by the 2026-11-21 release run and committed (78223d8); tested on the emulator for the two x86 ABIs (through miniaudio's silent device), the ARM ones not run; no sound has been played on an Android device |
| render3dxt | None. Plain C with no SIMD of its own; the 32-bit x86 library is built with SSE2 arithmetic. Its drawing threads are bionic's pthreads, joined before every call returns. A model or picture is read from the path an app gives it, so an app passes paths it may read (its own files, not another app's). | built and tested by its own lane, not yet by a release run; no library committed |
| pdfxt | Two files: `pdfxt.so` (built here, API 21) and `pdfium.so` (prebuilt, pinned, API 23). On Android 5.0 and 5.1 the extension loads and every call is refused with a reason (`pdfLastError()`); PDFs open from Android 6.0. An app reads a PDF from a path it may read, or passes bytes to `pdfOpenData`. | built and tested by its own lane, not yet by a release run; no library committed |
| gamepadxt | Not built: SDL's Android joystick code is driven from SDL's own Java activity (`SDLActivity`, `SDLControllerManager`), and an OXT app has the engine's activity instead. Reading controllers on Android would need that Java side written for the engine. | not built for Android |
| xlsxt | None in the library: three C libraries built from source, with no per-processor path. An app must say where a workbook's temporary files go (`xlSetTempFolder` with the engine's cache or documents folder): Android has no `/tmp` an app may write to. | built by release run 44838679488 and committed 2026-11-21 (0be6db1); tested on the emulator for the two x86 ABIs, the ARM ones not run |
| sodiumxt, box2dxt | None. box2dxt's x86 libraries are built without AVX2 (x86_64) or SIMD (x86), as on the desktop; the ARM ones use NEON. | tests run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| onionxt (script) | It drives a Tor daemon it can reach. Android apps cannot start one of their own this way; a Tor app that offers a SOCKS port (Orbot) could serve the client paths, and the control-port paths (onion services) need a control port such an app may not offer. | not examined on Android |
| nostrxt (script) | Pure script over coinxt and sodiumxt (both built for Android) and the engine's sockets. Its relay layer opens secure sockets, so an app needs the engine's SSL library in the package (the builder's `android,include revsecurity` setting) and the Internet permission ticked. Neither library file calls anything a desktop alone has (read 2026-11-18: no `shell`, no `open process`, no fixed path). | read, not run: verified statically; needs an OXT pass on Android |
| riptide, nocloud, holde-em | Their windows are laid out for a 1200 x 640 desktop card. | no phone layout |

Every native extension that opens a socket needs the app to hold Android's INTERNET permission.
The four that do (enetxt, curlxt, datachannelxt, torrentxt) declare it in their binding,
`metadata android.permissions is "INTERNET"`, the key OXT-Beyond's standalone builder reads from
each extension an app includes and writes into the app's manifest (read in its
`ide-support/revsblibrary.livecodescript`, 2026-11-18; OBSERVED 2026-11-19: the app of the first
engine load, whose own settings name no permission, held INTERNET by `dumpsys package`; no socket
was opened with it). The comment above the line in each `.lcb` still carries its 2026-11-18
label and is corrected with the binding's next change (a `.lcb` edit starts the member's native
lanes). `tools/test-build-android.py` holds the four to that line and the other three to none. The script members ride the engine's own sockets, so an app that uses onionxt or
nostrxt alone still ticks Internet in the IDE's standalone settings.

## Landing the libraries

Steps 1 to 3 were done on 2026-11-18; they stay here as the procedure for a rebuild (a moved pin,
a shim change), which repeats 1 and 2.

A rebuild of one member names it: run 44914897842 (2026-11-21, `lanes: android`,
`members: torrentxt`, commit d47060f) replaced torrentxt's four API 21 libraries, which the
installer had refused since the recipe moved it to API 24. In that run the Android rows built and
tested every member and the commit job took only the named one's files; a dispatch with
`build: named`, added later that day, builds only the named members' lanes.

1. Dispatch `release-binaries.yml` with `lanes: android` on the branch that holds this page's
   tooling. Every row must be green: the two emulator rows with every member's tests run. (Done
   first with `commit_mode: none`, run 44379162842; the dispatch that commits runs the rows again.)
2. With `commit_mode` other than `none`, the commit job installs the twenty-eight libraries,
   refreshes each `MANIFEST.sha256`, and runs the gates with `--installing`. (Done: run
   44391791349, commit 5aa3ad4.)
3. In the next change, add the four ids to each member's `ships` row in
   `tools/check-binary-freshness.py` (the gate names the edit), and replace this page's status
   paragraph with the run's record. (Done in the change that follows 5aa3ad4. A first landing
   only: once the ids are in `ships`, a rebuild needs no `--installing` allowance.)
4. Publishing carries each member's `src/code/<abi>-android/` to its repository when this
   reaches `main`. OXT-Beyond then pins them in its `tools/oxt/xtalk-extensions.json`, and its
   Android builder packs them into an app, where an engine loads them. (Done 2026-11-19 for the
   seven: OXT-Beyond pull request 572, the first engine load above. Its Android workflow runs the
   same probe again whenever its pins move, so a rebuilt library meets an engine there.)
