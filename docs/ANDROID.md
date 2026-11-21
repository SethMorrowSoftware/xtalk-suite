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
**render3dxt joined the same day** as a ninth, built and tested the same way by its own lane
(`native-render3dxt.yml`), with no Android library committed yet; its tests carry their model
and picture files inside them, so they run from the folder the emulator is handed.
**xlsxt joined the same day**, the same way: named in `tools/build-android.sh`, built for the four
ABIs and tested on the emulator for the two x86 ones by its own lane (`native-xlsxt.yml`), with no
Android library committed yet.
So the seven members' `x86_64-android` libraries are: native tests run on an Android emulator,
and loaded by an engine in an app for one call each; a member's own selftest on an Android engine
is still owed. Every other `x86_64-android` and every `x86-android` library: native tests run on
an Android emulator; needs an OXT pass on Android. The ARM libraries are: built and verified
statically; needs an OXT pass on Android.

## The four platform ids

OXT-Beyond's Android standalone builder takes an extension's native code from
`code/<arch>-android/` and packs it into the app as `lib<name>.so` (read in OXT-Beyond's
`ide-support/revsaveasandroidstandalone.livecodescript` and `revsblibrary.livecodescript`,
2026-11-18; not observed). The four folder names are its `kAndroidArchitectures`:

| Platform id | Android ABI | Devices | Tests in CI |
|---|---|---|---|
| `arm64-android` | arm64-v8a | nearly every phone and tablet since about 2017 | built, not run |
| `armv7-android` | armeabi-v7a | older and low-end 32-bit devices | built, not run |
| `x86_64-android` | x86_64 | emulators, some Chromebooks | run on an Android 5.0 emulator |
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
```

- **One NDK, pinned** (`--pins` prints it): the revision OXT-Beyond's `config/android-ndk-version`
  names, so the libraries and the engine that loads them come from one compiler. Another revision
  is refused; `XTALK_ANDROID_ANY_NDK=1` is for a trial, and says its output must not be committed.
- **API 21 (Android 5.0)** is the floor, as for OXT-Beyond's own Android engine.
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

Not run anywhere yet: any ARM library; any `x86-android` library on an engine; any member's
selftest or demo on an Android engine; box3dxt's, render3dxt's and xlsxt's libraries in an app.

## What differs on Android, per member

| Member | Difference | State |
|---|---|---|
| curlxt | Android has no CA bundle file. The shim reads the system's trusted certificates from `/apex/com.android.conscrypt/cacerts` (Android 14 and later) or `/system/etc/security/cacerts` and gives them to curl in memory. Certificates a user added by hand are not included; `caFile` still overrides, and an empty `caFile` returns to the system store. `cuVersion()` ends with the number of certificates found. | tests run on the emulator 2026-11-18 (both x86 ABIs): 157 certificates read from its store. Loaded by an engine in an app 2026-11-19 (x86_64, one call, the ABI 1 build): 149 certificates on Android 16. Rebuilt at ABI 2 on 2026-11-21 and tested on the emulator again; no Android engine has loaded that build. ARM: built, not run |
| coinxt | Entropy comes from `arc4random_buf` (bionic's, kernel-seeded): `getrandom()` only arrived in API 28 and the library targets API 21. | self-test run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| torrentxt | None in the library. An app must give save paths it may write to (the engine's documents or cache folder, not `/tmp`), and Android stops background network use it has not been told about. | tests run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| datachannelxt, enetxt | None in the library. | tests run on the emulator 2026-11-18 (both x86 ABIs). Loaded by an engine in an app 2026-11-19 (x86_64, one call). ARM: built, not run |
| box3dxt | None. Box3D picks its AVX2 solver at run time, so the x86_64 library needs no flag; the 32-bit x86 one is built with SSE2 arithmetic; the ARM ones use NEON. | built by the 2026-11-20 release run and committed (6d132d3); tested on the emulator for the two x86 ABIs, the ARM ones not run |
| render3dxt | None. Plain C with no SIMD of its own; the 32-bit x86 library is built with SSE2 arithmetic. Its drawing threads are bionic's pthreads, joined before every call returns. A model or picture is read from the path an app gives it, so an app passes paths it may read (its own files, not another app's). | built and tested by its own lane, not yet by a release run; no library committed |
| xlsxt | None in the library: three C libraries built from source, with no per-processor path. An app must say where a workbook's temporary files go (`xlSetTempFolder` with the engine's cache or documents folder): Android has no `/tmp` an app may write to. | built and tested by its own lane, not yet by a release run; no library committed |
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
