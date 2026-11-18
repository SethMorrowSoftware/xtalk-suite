# Android

What the suite has for Android, how it is built and checked, and what nobody has run yet.
Started 2026-11-18. Every claim here is one of three kinds, and says which: **run** (a test
executed on an Android system), **checked** (read from the built file by a tool), or **read**
(taken from source and not observed). Open work is in [WORK-PLAN.md](WORK-PLAN.md), sections 1.2
and 1.3; this page keeps status and method.

## Status in one paragraph

All seven native members (sodiumxt, enetxt, box2dxt, coinxt, curlxt, datachannelxt, torrentxt)
build for the four Android ABIs with one script, `tools/build-android.sh`, and the release
workflow has an `android` job that calls it. Each built library is checked as an Android library
(ABI, API level, what it needs at load time, 16 KB alignment, no text relocations). On 2026-11-18
all twenty-eight libraries were built with the pinned NDK on a development machine and passed
those checks and the binary-freshness gate's export and ABI-pin legs. **No Android library is
committed yet**: they arrive by a `release-binaries.yml` dispatch, like every other platform's
(suite rule 5). **No test of any member has run on an Android system yet**: the workflow's x86
rows run them on an emulator, and that job's first run is still owed. **No OXT engine on Android
has loaded any of them.** Until those happen the whole of this page is: built and verified
statically; needs a release dispatch, then an OXT pass on Android.

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

Not run anywhere yet: any ARM library; any library inside an app; any `.lcb` binding on an Android
engine.

## What differs on Android, per member

| Member | Difference | State |
|---|---|---|
| curlxt | Android has no CA bundle file. The shim reads the system's trusted certificates from `/apex/com.android.conscrypt/cacerts` (Android 14 and later) or `/system/etc/security/cacerts` and gives them to curl in memory. Certificates a user added by hand are not included; `caFile` still overrides, and an empty `caFile` returns to the system store. `cuVersion()` ends with the number of certificates found. | built; the smoke test asserts a non-empty store, first run owed |
| coinxt | Entropy comes from `arc4random_buf` (bionic's, kernel-seeded): `getrandom()` only arrived in API 28 and the library targets API 21. | built; self-test first run owed |
| torrentxt | None in the library. An app must give save paths it may write to (the engine's documents or cache folder, not `/tmp`), and Android stops background network use it has not been told about. | built; tests first run owed |
| datachannelxt, enetxt | None in the library. | built; tests first run owed |
| sodiumxt, box2dxt | None. box2dxt's x86 libraries are built without AVX2 (x86_64) or SIMD (x86), as on the desktop; the ARM ones use NEON. | built; tests first run owed |
| onionxt (script) | It drives a Tor daemon it can reach. Android apps cannot start one of their own this way; a Tor app that offers a SOCKS port (Orbot) could serve the client paths, and the control-port paths (onion services) need a control port such an app may not offer. | not examined on Android |
| nostrxt (script) | Pure script over coinxt, sodiumxt and the engine's sockets. | not examined on Android |
| riptide, nocloud, holde-em | Their windows are laid out for a 1200 x 640 desktop card. | no phone layout |

Every native extension that opens a socket needs the app to hold Android's INTERNET permission (a
standalone setting in the IDE).

## Landing the libraries

1. Dispatch `release-binaries.yml` with `lanes: android` on the branch that holds this page's
   tooling. Every row must be green: the two emulator rows with every member's tests run.
2. With `commit_mode` other than `none`, the commit job installs the twenty-eight libraries,
   refreshes each `MANIFEST.sha256`, and runs the gates with `--installing`.
3. In the next change, add the four ids to each member's `ships` row in
   `tools/check-binary-freshness.py` (the gate names the edit), and replace this page's status
   paragraph with the run's record.
4. Publishing carries each member's `src/code/<abi>-android/` to its repository. OXT-Beyond then
   pins them in its `tools/oxt/xtalk-extensions.json`, and its Android builder packs them into an
   app, where the first engine load can be observed.
