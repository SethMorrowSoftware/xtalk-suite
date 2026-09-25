# CLAUDE.md

Guidance for Claude Code in the SodiumXT member of the xtalk-suite monorepo (`sodiumxt/`).
Where anything else disagrees, the code, `docs/api-reference.md` and this file win; the
original design plan is in git history, and what still matters from it is below.

## What this is

**SodiumXT** brings modern cryptography to OpenXTalk (OXT) and LiveCode 9.6.3+:
authenticated encryption, Argon2id, streaming AEAD for big files, X25519 boxes, ed25519
signatures, BLAKE2b, ristretto255 group arithmetic and a real CSPRNG. Layers: libsodium
(ISC, static-linked; pinned 1.0.20, vcpkg's on Windows) -> the C shim `src/sodium_shim.c` (exports `sxt_*`,
marshals bytes, adds no cryptography) -> ONE library `sodiumxt.{so,dll,dylib}` -> the LCB
binding `src/sodium.lcb` (library `org.openxtalk.library.sodium`, public `sx*`) -> the
examples. 73 public `sx*` handlers over 124 `sxt_*` exports, at **ABI 10**
(`SXT_ABI_VERSION` in `src/sodium_shim.h` equals `kSXTABIVersion` in `src/sodium.lcb`).

- `src/` - shim, binding, `code/` (bundled libraries + `MANIFEST.sha256`), `vendor/` (SHA3).
- `tests/sodium_smoke_test.c` - KATs, round trips, tamper, wrong-key and firewall checks.
- `examples/` - the kit-look demo and the `sxSelfTest()` harness.
- `tools/` - `run-gates.sh` (the gate list), `check-livecodescript.py`,
  `check-docs-style.py`, `package-extension.py`.
- `docs/` - getting-started, api-reference, recipes, security, building.

The library ships under `src/code/<arch>-<platform>/sodiumxt.*` (bare token, no `lib`
prefix; ids architecture first, `-win32` for both Windows bitnesses); the engine resolves
`c:sodiumxt>` through `the revLibraryMapping`, with no loose library, `sudo`, `/usr/lib`,
`LD_LIBRARY_PATH` or rename.

**Unlike TorrentXT (do not cargo-cult):** no threads, alert queue, polling or session
(every `sxt_*` call is synchronous bytes-in/bytes-out); payload DOES cross the FFI, so big
files go through secretstream and the C-side file helpers; and there is no C++ exception
firewall (libsodium is C), only the length-and-pointer firewall of rule 1.

## The rules that make this safe

The shim cites these by number; keep the numbering.

1. **Validate every length and pointer at the boundary.** A too-small out buffer returns
   `-needed`, never a partial write; a null pointer or bad handle is a defined no-op or
   error, never a crash. The smoke test feeds short buffers and bad handles to every entry.
2. **`sodium_init()` exactly once, first**, behind a static guard (`ensure_init()`); until
   it runs the CSPRNG and CPU feature detection are not ready. Safe to repeat, not to skip.
3. **Never reuse a nonce with a key.** One-shot calls draw a fresh random nonce and prepend
   it; secretstream derives per-chunk nonces from a random header. No bring-your-own-nonce
   entry without a very loud reason, given ONCE (2026-08-23): `sxChaCha20IetfXor` (ABI 10),
   the NIP-44 building block whose nonce is an HKDF slice derived inside the construction.
   The argument is in `docs/security.md` and at its declaration in `src/sodium_shim.h`.
4. **Authenticate everything; compare in constant time.** AEAD, `_easy`, secretbox and
   secretstream, never a raw stream cipher, with the same single exception
   (`sxChaCha20IetfXor`: NIP-44 v2 authenticates one layer up with HMAC-SHA256, and an AEAD
   would break interop; a construction over it verifies its MAC BEFORE the cipher runs).
   Compare tags with `sodium_memcmp` or libsodium's verify calls, never `is` (timing leak).
5. **Zero secrets C-side, and be honest about the rest.** `sodium_memzero` transient key
   and scratch buffers. A key in a LiveCode `Data` cannot be `mlock`ed or reliably zeroed:
   secure-memory guarantees stop at the FFI line.

## Working rules

6. **Script is done when `python3 tools/check-livecodescript.py` passes** (the family's
   unified checker; fix it in every copy at once), and stays "verified statically; needs an
   OXT pass" until an engine runs it.
7. **A shim change is done when `sodium_smoke_test.c` passes under ASan/UBSan**; an ABI
   change bumps `SXT_ABI_VERSION` and `kSXTABIVersion` together.
8. **A native-library change is done when the binary AND its `MANIFEST.sha256` entry are
   refreshed in one change**, by `tools/package-extension.py` or the suite's hand-dispatched
   `release-binaries.yml`. `native-sodiumxt.yml` never commits (it fires on every push).
9. **Naming:** `t`/`p`/`s`/`k` prefixes; public `sxPascalCase`; C ABI `sxt_snake_case`. A
   prefix rename is one pass that keeps the `binds to "c:sodiumxt>sxt_..."` strings in step.
10. **No em dashes, en dashes or curly quotes** in any `.md` here (`tools/check-docs-style.py`).
11. **Engine behaviour goes to the suite's `docs/OXT-ENGINE-NOTES.md`**
    (https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/OXT-ENGINE-NOTES.md).
12. Comment the why, densely. Per-task branch and a draft PR; never push to `main` unasked.

## FFI / C-ABI conventions

The most expensive lessons in the family. Change nothing here without a very good reason.

- **An LCB `Data` does NOT auto-bridge to `void*`** ("No automatic bridging from Data or
  String to Pointer exists"; it cost TorrentXT an `expected type pointer`). OUT buffer: a
  `<builtin>` `MCMemoryAllocate` block passed as `Pointer`; the shim returns bytes written
  or `-needed`; the LCB reallocates, retries once, copies back with
  `MCDataCreateWithBytes`. IN buffer: `MCDataGetBytePtr(theData)` plus its length.
  `<builtin>` handlers resolve by NAME (no leading `_`); our foreign handlers keep `_sxt_*`.
- **Error returns** (also in `sodium_shim.h`): `>= 0` bytes written; between `SXT_ERR_BASE`
  and 0, too small, need `-ret`, nothing written; `<= SXT_ERR_BASE` a hard error with text
  in the thread-local `sxt_last_error()` (`sxLastError()`). `SXT_MAX_BUFFER` (2000000000)
  caps an in-memory buffer; never widen it without moving `SXT_ERR_BASE` in lockstep.
- **There is no 64-bit foreign int**: `opslimit`, `memlimit` and file sizes cross as
  decimal `ZStringUTF8`. Reals are `double`, booleans `int` 0/1, short strings `ZStringUTF8`.
- **Never return a library-owned `const char*`** of unknown lifetime: fill a caller buffer.
  Return `""`, never `NULL`, on error. Never rename a shipped `sxt_` symbol.
- **Bump `SXT_ABI_VERSION` on any ABI change**, with `kSXTABIVersion`, so the private
  `sPrepare()` guard throws a clear error on skew instead of corrupting memory.
- **Expose every length constant from the shim** (`sxt_secretbox_keybytes()` ...); the LCB
  never hardcodes 24/32/16.

## Handles for the stateful primitives

secretstream, multipart generichash and multipart sign keep their state C-side, in a
generation-tagged handle table (positive 32-bit ints, `0` invalid), so a stale handle is a
harmless no-op or error. The free (`sxFreeStream`, `sxFreeHash`) is explicit, idempotent
and zeroes the state. There is no LCB unload hook: apps free what they open (`closeStack`).

## Gotchas and traps

1. **The ABI-mismatch footgun.** Symptom: `"SodiumXT ABI mismatch: the native sodiumxt
   library does not match this extension. Reinstall the packaged extension."` from the
   FIRST `sx*` call. Cause: `sPrepare()` compares `_sxt_abi_version()` with `kSXTABIVersion`
   on every call, and the package's `.lcb` and binary disagree (built from a tree whose
   binary for that platform was stale). It takes out the SodiumXT section and every
   composer: riptide entirely; onionxt's SAFECOOKIE, deterministic-onion and offline-address
   paths. Fix: repackage from the current tree.
2. **Smart quotes fail compilation, comments included** (suite engine note 1.4).
3. **A prefixed name spelled like a token IS the token** (`tExt` is `text`; engine note 1.5).
4. **Constants are literal and declared before first use** (engine note 1.3).
5. **LCB: `unsafe` around each foreign call; declarations at a handler's TOP**
   (suite engine notes section 4).
6. **`itemDelimiter` / `lineDelimiter` are global state** (engine note 2.3): set before use.
7. **Commands report via `the result`, functions return**; `is a <type>` accepts only
   number, integer, boolean, point, rect, date and color (no `is a string`).
8. **Crypto in script:** `sxRandomBytes`, never `random()`; `sxMemEqual`, never `is`/`=`;
   `textEncode(...,"UTF-8")` a passphrase so it derives the same key everywhere.
9. **A plain CMake build re-bundles `x86_64-linux/sodiumxt.so`** with different bytes, so the
   MANIFEST gate fails until you `git checkout` it or refresh binary and manifest together.

## Performance and crypto correctness

- One FFI round trip per logical operation (the `-needed` retry adds at most one); reuse a
  persistent out-buffer in hot paths. Anything that does not fit in memory twice uses
  `sxEncryptFile` / `sxDecryptFile` / `sxHashFile`, so the bytes never enter a `Data`.
- The crypto blocks the one interpreted thread: the INTERACTIVE/MODERATE/SENSITIVE preset
  is the latency knob; keep status updates at or below about 4 Hz.
- Passwords: Argon2id, never a fast hash; store opslimit, memlimit and salt with the
  ciphertext (or use `pwhash_str`) so the cost can rise later. Reject a tag failure as
  "wrong key or tampered", never garbage; secretstream's FINAL tag makes truncation
  detectable, which hand-rolled chunk framing does not.

## Design decisions (from the original plan)

- **libsodium**: hard-to-misuse primitives, C ABI, audited NaCl lineage, ISC. Rejected
  OpenSSL EVP (heavy, easy to misuse), Tink/BoringSSL (too heavy) and monocypher (no
  Argon2id `pwhash_str`, hex/base64 or secretstream). The C ABI is engine-agnostic:
  monocypher or raw OpenSSL could replace libsodium behind `sxt_*` without touching the LCB.
- **KATs are mandatory**: round trips hide byte mangling (mangled-then-unmangled still
  matches). Negative tests: tamper fails, short buffer returns `-needed`, stale handle is a
  clean no-op, wrong-length key is a clean error.
- Settled: prefix `sx*`, library id `org.openxtalk.library.sodium`, URL-safe base64 without
  padding, `sxSeal` exposed, multi-value returns through out parameters. SHA3-256 (ABI 7)
  is vendored from trezor-crypto (`src/vendor/VENDOR.md`) because libsodium has none.

## Committed binaries

| platform id | ABI | built from | engine record |
|---|---|---|---|
| `x86_64-linux` | **10** | release run 12 (2026-08-27), pinned 1.0.20 source | none recorded for this build; Linux last recorded at ABI 9 (2026-08-18) |
| `x86-linux` | **10** | release run 12, pinned 1.0.20 source (`-m32`) | none recorded |
| `x86_64-win32` | **10** | MSVC + vcpkg libsodium 1.0.22 (D-08); last re-committed 2026-09-12 | needs its Windows engine pass (runbook row 23); the 2026-08-24 106/106 ran on a mingw DLL that no longer ships, and the 2026-09-24 106/106 on Windows recorded neither `sxVersion()` nor bitness, so it names no DLL |
| `x86-win32` | **10** | as the x64 row | needs its Windows engine pass (runbook row 23; a 32-bit OXT) |
| `universal-mac` | **10** | release run 12, pinned 1.0.20 source; both slices in one pass, `lipo -archs` asserted, arm64 tested natively, x86_64 under Rosetta 2 | no OXT load recorded |

The suite's `tools/build-preflight.py` parses the `universal-mac` row and needs exactly one;
`tools/check-binary-freshness.py` decodes ABI 10 from every row, both mac slices included.
`sxVersion()` reports libsodium 1.0.22 on the Windows DLLs and 1.0.20 elsewhere.

**CI executes the committed library (since 2026-08-16).** The build-matrix step "Execute
the COMMITTED library's ristretto and ChaCha20 vectors" in `native-sodiumxt.yml` dlopen()s
the committed Linux `.so` BEFORE the build overwrites it: RFC 9496 A.1 [1]B/[2]B/[3]B, the
group law, scalarmult against scalarmult_base, batch against single, a refused bad point,
and (since 2026-09-24) the RFC 8439 A.2 #1 ChaCha20 keystream and its inverse. It reads the
expected ABI from `src/sodium_shim.h`, never a literal (coinxt's literal turned its lane red
at a 4 -> 5 bump). Linux only; the mac dylib is driven in `release-binaries.yml`'s mac lane.

**The proven mingw fallback when no MSVC is available** (71/71 on 2026-08-12 with an ABI-7
DLL; 106/106 on 2026-08-24 with an ABI-10 DLL): member CMake with
`-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc
"-DSODIUMXT_LIBSODIUM_CONFIGURE_EXTRA=--host=x86_64-w64-mingw32"
-DCMAKE_SHARED_LINKER_FLAGS=-static-libgcc` (`i686-w64-mingw32` twins for x86), tests OFF;
without `-static-libgcc` the DLL imports `libgcc_s_seh-1.dll` / `libgcc_s_dw2-1.dll`. By
hand: libsodium `--host=... --enable-static --disable-shared`, shim with `-DSODIUM_STATIC`.
A DLL nobody can run here passes three checks: (1) exports match the Linux build exactly
(124/124 `sxt_*`); (2) `sxt_abi_version` disassembles to `mov $imm,%eax ; ret` (32-bit:
`_sxt_abi_version`); (3) imports are only KERNEL32, ADVAPI32 and msvcrt (it caught libgcc).
`--exclude-libs,ALL` plus `__declspec(dllexport)` on `SXT_API` keep libsodium from leaking.

## Engine evidence ledger

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| pre-suite (undated; `src/sodium.lcb` header) | OXT, Windows x64 | `sxSelfTest()`, core surface | 35/35 |
| 2026-08-08 | OXT, suite paste, all members | the suite sampler: headline paths and cross-member seams | green; `sxSignSeedToExpandedKey`'s expanded key equals libtorrent's DHT secret key from the same seed |
| 2026-08-10 | OXT, suite paste (folded) | the complete `sxSelfTest()` | 68/68, twice |
| 2026-08-12 | OXT, Windows x64, mingw64 ABI-7 DLL | `sxSelfTest()` incl. FIPS 202 SHA3-256 and the Argon2id KAT | 71/71; riptide 89/89 over it |
| 2026-08-15 | C, ASan/UBSan | ristretto255 ABI 8/9 KATs vs an independent RFC 9496 reference (`holde-em/tools/protocol-kat.py`) | green |
| 2026-08-16 | CI, no engine | committed Linux `.so` first executed (the step above) | in every Linux lane since |
| 2026-08-17 | OXT 9.6.3, Windows x86_64, NT 10.0, ABI 9 | suite paste (preflight: SodiumXT LOADED at 9) | sodiumxt 99 green incl. ristretto ABI 8+9 and the batch naming index 2 of 3; paste 1,836 folded, 0 failed, 7 skipped |
| 2026-08-18 | OXT, Linux, ABI 9 | suite paste | sodiumxt green, ristretto included (the one failure was box2dxt's) |
| 2026-08-20 | OXT, Windows | suite paste, sodiumxt inside it | 1981 passed / 0 failed / 1 skipped |
| 2026-08-23 | C, ASan/UBSan | ABI 10 ChaCha20 KATs | green; three implementations agree on RFC 8439 vectors |
| 2026-08-24 | OXT 9.6.3, Windows x86_64, mingw64 ABI-10 DLL (since replaced) | suite paste (preflight accepted ABI 10) | `sxSelfTest()` 106/106 incl. 7-check ChaCha20; paste 2,373 / 0 / 3 skipped |
| 2026-08-27 | CI, no engine | `release-binaries.yml` run 12 (GitHub run 33025459610, cec1e85) | all five rows at ABI 10; mac universal, both slices tested |
| 2026-08-27 | OXT, two-machine session (platform and package not recorded) | suite paste | 2440 passed / 2 failed / 3 skipped; every folded member green, sodiumxt included (both failures were the live loopbacks, UDP to 127.0.0.1 blocked on that machine) |
| 2026-08-27, 2026-09-12 | CI, no engine | runs 33100007529 (b9e1c1b) and 34657390798 (421bab3) | Windows DLLs re-committed (MSVC + vcpkg, 1.0.22); the 09-12 pair ships |
| 2026-09-24 | OXT, Windows (the engine reports Win32; OXT version, OS build, bitness and `sxVersion()` not recorded, so no DLL is named) | the D-23 suite paste (built from 9aa62c8; this member as at 6401e43) | `sxSelfTest()` 106/106, every group incl. ristretto ABI 8+9 and the 7-check ChaCha20; sampler 17/17; the CROSS seams green (one identity with libtorrent, the BEP44 item TorrentXT accepts, one sealed payload, OnionXT's SodiumXT-backed capabilities); board row 125/0/0, no skips; paste 2620 passed / 5 failed / 3 skipped, the failures riptide's three and the two live loopbacks |

## Status

The whole `sx*` surface is engine-proven through ABI 10 (every section, ChaCha20 included,
green on Windows x64 2026-08-24 and again on Windows 2026-09-24, 106/106 both times;
ristretto also on Linux 2026-08-18). The current BINARIES are not: no record names any of
the five committed builds (the 2026-09-24 paste is the one engine record after the shipped
Windows DLLs of 2026-09-12, and it recorded neither `sxVersion()` nor bitness, so it cannot
say which DLL it loaded; the 2026-08-27 paste did not record its platform or package). The
demo's UI (unified onto the suite kit 2026-08-14) is "verified statically; needs an OXT
re-pass". Open work is tracked in the suite's docs/WORK-PLAN.md.

## Build and gates

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSODIUMXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --output-on-failure     # sodium_smoke_test.c, KATs included
bash tools/run-gates.sh                        # this member's gate list (what CI runs)
# iterate the shim under sanitizers with gcc (clang's ASan runtime is not installed);
# -isystem keeps libsodium's warnings out of our -Wall -Wextra (/W3 on MSVC):
gcc -std=c11 -Wall -Wextra -fsanitize=address,undefined -fno-sanitize-recover=all \
  -Isrc -isystem <libsodium-include> \
  src/sodium_shim.c tests/sodium_smoke_test.c <path-to>/libsodium.a -o /tmp/sx && /tmp/sx
```
Windows/MSVC commands, the pin and packaging: `docs/building.md`.
