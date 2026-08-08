# CLAUDE.md - CoinXT

This file guides Claude Code (claude.ai/code) when working in the CoinXT sub-project.

> **Read the docs first.** [SPEC.md](SPEC.md) is the source of truth for WHAT CoinXT is (the C/script
> split, the ABI contract, the formats, the security model). [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)
> is the phased HOW. This file is the operational as-built record and the hard-won-lesson list, in the
> same spirit as the sibling `CLAUDE.md` files (SodiumXT, OnionXT, TorrentXT). The portable
> [templates/CLAUDE.md](templates/CLAUDE.md) (carried into this project so it survives the split into
> its own repository) carries the generic xTalk/LCB engine lessons; this file adds what is specific
> to CoinXT: a native crypto shim that handles money.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`, even in comments and strings. Comment the *why*, densely; match the surrounding style.

## What this is

**CoinXT** is a Bitcoin and Ethereum cryptography layer for OpenXTalk (OXT). It wraps **trezor-crypto**
(MIT, plain C, no external deps, the crypto core of a hardware wallet) behind a thin C ABI and a
livecodescript API, so an xTalk app can make keys, derive HD wallets from a mnemonic, build addresses,
and sign and verify for both chains. It adds no cryptography of its own; every curve op and hash is
trezor-crypto's.

```
app (livecodescript)
   |
CoinXT public API (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT: hex, Base58Check, Bech32/Bech32m, RLP, xprv/xpub, WIF, EIP-55, addresses
   |- FFI seam: one .lcb module, unsafe ... end unsafe around every foreign call
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto subset
   |- curve + hashes in C: secp256k1 (ECDSA/recoverable/recover/ECDH/Schnorr),
      SHA2/SHA3/Keccak-256/RIPEMD-160, HMAC, PBKDF2, BIP-32 node math, BIP-39 seed
```

## How CoinXT differs from its siblings (read before you assume)

1. **Unlike OnionXT, CoinXT HAS a C shim, and it is central.** OnionXT is pure script over engine
   sockets; its FFI section is carried "just in case." CoinXT's whole point is the shim, so the
   **FFI/C-ABI conventions below are law from day one**, and every shim change builds under ASan + UBSan
   and bumps the ABI + `cxCheckABI()` on any ABI change (the SodiumXT / TorrentXT discipline).
2. **Unlike OnionXT, CoinXT does no I/O and holds no long-lived state.** No sockets, no daemon, no accept
   loop, no lifecycle. Every call is a pure, synchronous, deterministic function: bytes in, bytes out.
   The async/state-machine discipline OnionXT needed does NOT apply. There is nothing to close.
3. **Like SodiumXT, CoinXT is bytes-in / bytes-out crypto, and composes it.** It is closest to SodiumXT
   in shape (a stateless crypto wrap), but it wraps a different C library and covers a different domain
   (coin curves, hashes, HD wallets, address formats).
4. **CoinXT handles money.** A wrong byte is not a bug report, it is lost funds. Every rule below that
   says "fail closed" or "verify the checksum" or "compose audited code, never hand-roll" counts double.

## The rules that make this safe and correct

1. **Add no cryptography. Wrap trezor-crypto.** Every scalar multiply, signature, and hash is upstream,
   audited code. A missing primitive is a new vendored file or an upstream request, never a hand-rolled
   curve op or hash here. There is no CoinXT cipher.
2. **The app owns key custody; CoinXT is a calculator.** CoinXT holds a key only for the microseconds of
   one operation. Storage, backup, and confirm-before-sign are the app's. Document the boundary loudly.
3. **Sign only the exact digest the app hands you.** `cxSign` takes a 32-byte hash. CoinXT does not build
   your sighash / transaction preimage in the primitive layer, and even in the tx-building phase the app
   confirms the decoded human intent. A blind signer is a footgun.
4. **Fail closed on every malformed input.** A bad Base58Check / Bech32 / EIP-55 checksum, an
   out-of-range scalar, a wrong-length buffer, a non-canonical signature: return a clean `"CoinXT: ..."`
   error, never a wrong-but-plausible key or address. Verify every checksum on decode.
5. **Secret hygiene across the FFI (see below).** Private keys, seeds, chaincodes cross as `Data` /
   `Pointer`, are `memzero`ed in the shim after use, and are NEVER returned as a bridged C string. The
   script layer clears its own key variables the moment it is done, and the docs state the honest limit
   (OXT script variables are not locked memory).
6. **Deterministic by design.** RFC 6979 signing needs no randomness; fresh key material comes from the
   caller (compose SodiumXT `sxRandomBytes`). No ambient RNG in the shim. Every operation is a pure
   function of its inputs, so every operation is KAT-testable.

## Commands

**Static gate for the script layer** (carried verbatim from OnionXT / SodiumXT; the checkers ship in
THIS project's `tools/` so CoinXT is self-contained when it moves to its own repository):
```sh
python3 tools/check-livecodescript.py
python3 tools/check-docs-style.py
```
It checks smart/curly quotes, em/en dashes, block balance, constants-before-use, the prefixed-token
shadow trap, the `put ... into ... after` malformation, and (for `.lcb`) a missing
`use com.livecode.foreign` and `textEncode`/`textDecode` used inside a module.

**The OXT self-test's vectors must not drift** (no compiler needed, so it runs on every push):
```sh
python3 tools/check-selftest-vectors.py
```
`tests/coin-selftest.livecodescript` carries its expected digests as hand-copied literals. This
re-derives all 21 of them - against `hashlib` / `hmac` where Python has an independent implementation,
against the published table in `coin-kat.py` for Keccak-256 (Python has no Keccak) and for RIPEMD-160
when OpenSSL 3 has moved it out of reach, saying so rather than skipping quietly. It also re-checks the
two structural claims the harness makes beyond its fixed digests: that PBKDF2's short output prefixes
its long one, and that the SHA3-256 and Keccak-256 constants genuinely differ. It is mutation-tested:
a flipped hex digit, an aliased Keccak constant, a changed BIP-39 salt, a truncated digest, a swapped
HMAC tag, and an altered input string with its digest left alone are each caught. A drifted expectation
turns a real regression into a green run, which in a money library is the worst failure mode there is.

**The C shim builds under sanitizers** (from phase 1):
```sh
cc -Wall -Wextra -fsanitize=address,undefined -isystem <trezor-crypto-dir> \
   native/coinxt.c <vendored .c files> -shared -o coinxt.<ext>
```
Treat trezor-crypto headers as system headers (`-isystem`) so their warnings do not pollute `-Wall
-Wextra`. Bump `cnx_abi_version()` + the `.lcb` `cxCheckABI()` on every ABI change.

**The SHIPPED library** (what the packaged extension carries, and what a native change must refresh in
the same commit - suite rule 5):
```sh
sh native/build.sh pack                 # -> src/code/<arch>-<platform>/coinxt.<ext>
sh native/build.sh pack x86-linux       # ... for an explicit platform id
python3 tools/check-binary-freshness.py # does the committed one still match the shim?
```
Pass the platform id explicitly for **any** cross build. Without it the path comes from `uname`, which
describes the machine and not the output: a 32-bit build driven by a `cc` that wraps `gcc -m32` still
reports `x86_64`, so a derived path would file an x86 library into `x86_64-linux/` on top of a good one.
(The build stages to a temp file and moves it in only on success, so a FAILED build can never truncate a
committed binary either way.)
Three things `pack` does that a plain `-shared` does not, all of them load-bearing:

- **the name.** `src/coinxt.lcb` binds `c:coinxt>cnx_*`, and the engine resolves that leading token to a
  file named `coinxt.<ext>` - NOT `libcoinxt.<ext>`. The Unix `lib` prefix is exactly wrong here. Every
  sibling ships the same way (`sodiumxt.so`, `enetxt.so`, `datachannelxt.so`).
- **the surface.** We compile the vendored trezor-crypto units straight in, so an unfiltered build
  exports 77 symbols, only 16 of them ours - the other 61 are upstream's `sha256_Init`, `hmac_sha512`,
  `keccak_256`, `ripemd160`, and (worst) plain `memzero`. Those are generic names another extension in
  the same engine process could also export, and the dynamic loader would pick one for both. Silently
  running a stranger's `sha256_Final` inside a money library is not a risk worth carrying for zero
  benefit, so `src/coinxt.map` narrows the exports to `cnx_*`. `pack` prints the symbol list it actually
  shipped; if it is longer than 16 names your linker refused the version script (it says so) - the
  library still works, but do not commit that one.
- **stripping**, so the committed artifact is small and reproducible. It is: rebuilding on the same
  toolchain reproduces the committed file byte for byte, so `pack` never dirties the manifest gate the
  way sodiumxt's CMake re-bundling does.

Refresh `src/code/MANIFEST.sha256` (`cd src/code && sha256sum <arch>-<platform>/coinxt.<ext> >
MANIFEST.sha256`) in the same change. The committed Linux build needs only `libc.so.6` and floors at
glibc 2.25.

`tools/check-binary-freshness.py` is the automated half of that rule, and it checks something the
manifest cannot: the manifest proves the committed file is unchanged, not that it still matches the
source. The freshness gate compares the committed library's exported symbols against the `cnx_*`
functions the shim actually defines, and calls `cnx_abi_version()` in the committed binary against
`CNX_ABI_VERSION` in the source. So an added export, a rename, a build without `src/coinxt.map`, or an
ABI bump the binary never got is a gate failure here instead of a bind failure on a user's machine. It
deliberately does NOT rebuild-and-diff: a different compiler emits different bytes from identical
source, so that check would fail for reasons that are not defects. It reads ELF, so it SKIPS (loudly)
on anything else.

**Known-answer vectors** (the correctness net for a money library):
```sh
python3 tools/coin-kat.py --check
```
Every deterministic path is pinned to a PUBLIC vector (RFC 6979, BIP-32/39, BIP-173/350, EIP-55,
Keccak), cross-checked against an independent implementation before pinning. A signature CoinXT makes
must also verify in a mainstream library, not just in CoinXT.

**There is no headless way to compile or run `.livecodescript` on OXT.** So a script change is "designed
and statically reasoned; needs an on-engine pass" until it has loaded the real `.lcb` in an engine and
round-tripped the `cx*` calls. The shim, by contrast, IS testable headless (the KAT harness can call it).

## The C-vs-script split (hold this line)

Anything that touches a private key or a curve point is **C** (audited trezor-crypto). Anything that is
checksummed byte-shuffling with no secret-dependent branch is **livecodescript**, pinned by a KAT. This
keeps the trusted native surface tiny (about 25 buffer-in / buffer-out functions, SPEC section 5.1) and
puts hex / Base58Check / Bech32 / RLP / address composition where they are easy to read, diff, and test,
exactly as OnionXT does base32 in script. Do NOT push encodings into the shim to "keep it together", and
do NOT re-implement a curve op in script to "avoid the FFI".

## FFI / C-ABI conventions (LAW here, not carried-for-later)

The single most expensive thing the family has learned. Change nothing here without a very good reason.

- **Byte buffers cross as `Pointer` + a length. An LCB `Data` does NOT auto-bridge to `void*`** (it
  marshals as an opaque `MCDataRef`). An **out** buffer is a raw block from the engine `<builtin>`
  `MCMemoryAllocate`, passed as a real `Pointer`; the LCB layer copies the written bytes back with
  `MCDataCreateWithBytes`. An **in** buffer passes `MCDataGetBytePtr(theData)` plus its length.
  **The length type follows the C declaration, always:** CoinXT's own `cnx_` ABI declares every buffer
  length as `size_t`, so in `src/coinxt.lcb` every one of them is `UIntSize`, never `CInt` (see the very
  next bullet: that mismatch is the heap bug, and it is not special to `MCMemoryAllocate`). The one
  `cnx_` argument that is genuinely 32-bit is the PBKDF2 iteration count (`uint32_t`, hence `CUInt`).
  SodiumXT's `-needed` re-alloc retry (its shim returns bytes-written-or-negative-required-size) is
  **not** the CoinXT protocol and must not be copied in: `cnx_` entry points return a status and write a
  FIXED size the shim itself reports (`cnx_*_len`), or exactly the output length the caller asked for,
  so the binding allocates exactly that and copies exactly that back. Keep it that way; there is then no
  retry path to get wrong and no size hardcoded in LCB.
- **`MCMemoryAllocate`'s size is C `size_t`, so it marshals as `UIntSize`, NOT `CUInt`.** A 4-byte int
  into an 8-byte size slot on a 64-bit build corrupts the heap.
- **There is no 64-bit foreign int.** A value that can exceed 2^31 (a PBKDF2 iteration count is fine at
  32-bit; a satoshi amount is not) crosses as a decimal `ZStringUTF8` string, parsed in the shim.
- **Reals cross as `double`, booleans as `int` (0/1).** Exported symbols keep the stable `cnx_` prefix
  and are NEVER renamed once shipped (the `.lcb` `binds to` strings reference them by name; a rename is a
  silent bind failure at load). `<builtin>` handlers resolve by name, so no leading underscore.
- **Never RETURN a bridged C string** (`ZStringUTF8` / `NativeCString`) from a foreign handler: the
  engine adopts the returned pointer and later `free()`s it, so a static or library-owned return is
  free()-on-static, heap corruption on the first call. This is doubly dangerous with key material. Fill a
  caller buffer and return length / `-needed`.
- **Pass a null pointer only through an `optional Pointer`** parameter (e.g. an absent BIP-340 aux_rand);
  a plain `Pointer` rejects `nothing`.
- **Bump the ABI version on any ABI change**, and have `cxCheckABI()` throw a clear "reinstall CoinXT"
  error on skew instead of corrupting memory on first use. Expose every length constant from the shim as
  a function (`cnx_seckey_len` = 32, ...); never hardcode a size in LCB.
- **`textEncode` / `textDecode` are NOT available to an LCB module** (livecodescript only), so bytes
  cross as `Data` and text<->Data conversion stays in the livecodescript layer.
- **`unsafe ... end unsafe` brackets every foreign call**, and keep all `local` declarations at the TOP
  of the handler (a nested `local` has broken whole-script compilation). **`use com.livecode.foreign`**
  whenever a foreign type is named.

## Determinism and entropy

- **No RNG in the shim.** trezor-crypto requires an integrator `random_buffer` / `random32`; wire it to
  ABORT (nothing should call it once signing is RFC 6979 and keys come from the caller). A called RNG is
  then a loud bug, not a silent weak key.
- **Fresh key material is the caller's.** `cxNewSeckey(pEntropy32)` validates 32 caller-supplied bytes
  (from SodiumXT `sxRandomBytes`, or OS entropy). Seeds and mnemonics are deterministic from there.
- Because everything is a pure function of its inputs, the whole surface is pinned by `tools/coin-kat.py`.
  If a result is not reproducible, something is wrong.

## Secret hygiene

- Private keys / seeds / chaincodes: `Data` in, `Data`/`Pointer` across the FFI, `memzero`ed in the shim
  after the operation, never a returned bridged string. The `cx*` layer does `put empty into tSeckey` as
  soon as it is done with one.
- **Honest limit, documented:** OXT script variables are not locked (mlock) memory, so a seed held in
  script can be paged to disk. CoinXT on a general-purpose desktop is not hardware-wallet isolation; do
  not market it as such. The trust boundary is the machine.
- Do not log key material. Do not put a seckey or a seed in an error string, a status message, or a
  committed test fixture (KATs use PUBLIC test-vector keys only, which are burned and safe to publish).

## Encodings in script (the OnionXT base32 discipline)

- **Byte discipline:** build with `numToByte` / `binaryEncode`, parse with `byteToNum` / `binaryDecode`
  (a FUNCTION that fills an out var: `get binaryDecode(...)`), index with `byte x to y of`. Never `char`
  / `line` / `word` on binary. Keep a base32/base58/bech32 bit-buffer small and masked each step so a
  long payload never builds a > 2^53 integer (precision loss). Route integer div/mod through helpers and
  avoid `^` in a compound expression (some OXT parsers reject it).
- **Verify every checksum on decode and fail closed:** Base58Check's 4-byte double-SHA-256 tail,
  Bech32/Bech32m's polymod (constant 1 vs 0x2bc830a3, SegWit v0 vs v1+), EIP-55's mixed case. A corrupt
  address must be rejected, never coerced.
- **Keccak-256 is NOT SHA3-256.** Ethereum uses the original `0x01` padding; FIPS-202 uses `0x06`. Two
  different shim functions (`cnx_keccak256` vs `cnx_sha3_256`); never alias them. This is the classic
  Ethereum footgun.
- Pin every encoding to its public vector (BIP-173/350 including INVALID cases, EIP-55 examples, the RLP
  yellow-paper examples).

## LiveCodeScript / LCB / OXT gotchas (carried; see [templates/CLAUDE.md](templates/CLAUDE.md) for the full list)

The generic list applies verbatim. The ones most likely to bite CoinXT:
- No smart/curly quotes anywhere (fails OXT compilation).
- The prefixed-token-shadow trap (`t/p/s/k` name whose full spelling is a reserved token); the checker's
  `RESERVED` set is only as complete as we keep it - add any new one found on-engine.
- Operators that look like functions: `bitAnd`/`bitOr` are operators; `binaryDecode`/`binaryEncode` are
  functions that fill an out var; `^` may be rejected in a compound expression.
- `is a <type>` has no `is a string`; commands report via `the result`, functions return a value.
- A whole `.livecodescript` compiles as a unit; a syntax error in one handler breaks the file.

## Handles and long-lived state

CoinXT is stateless: there is nothing to open, close, or free. The BIP-32 HD node crosses the ABI as a
**fixed-size opaque byte blob** (version || depth || fingerprint || child || chaincode || key), NOT as a
handle into a C-side table, so no generation-tagged handle machinery is needed. Keep it that way; if a
future feature ever needs C-side state, use SodiumXT's generation-tagged handle-table pattern (positive
32-bit ints, 0 invalid, a stale handle a clean error), never a raw pointer through script.

## Testing and conformance

- Pin every deterministic path with a PUBLIC known-answer vector in `tools/coin-kat.py`, cross-checked
  against an independent implementation (Python `ecdsa` / `eth-utils` / `pycryptodome`) BEFORE pinning.
- The gold standard for a signing test: a signature CoinXT produces VERIFIES in a mainstream external
  library, and an HD wallet from a standard mnemonic reproduces a reference address byte for byte.
- Ship a demo and a pure offline self-test harness formatted like OnionXT's (sPass/sFail, KAT sections,
  a section that SKIPS rather than fails when an optional dependency is absent).

## Git / workflow

- Develop on a per-task branch; commit there, open a **draft PR** if none exists. Do not push to `main`
  without explicit permission.
- A script change is "done" once the static gates pass and it has had (or is clearly flagged as needing)
  an on-engine pass. A shim change is "done" once it builds clean under ASan + UBSan, the KATs pass, and
  the ABI + `cxCheckABI()` are bumped in the SAME change.
- A change that ships a native binary refreshes the committed per-platform binary AND a
  `MANIFEST.sha256` in the same change (the SodiumXT model). Vendored trezor-crypto files are third-party
  code: record the upstream commit and any local patch in `VENDOR.md`; hash the sources and the wordlist
  in the manifest; never edit a vendored file in place silently.
- A change that needs a new SodiumXT primitive (e.g. a specific KDF) splits: the upstream feature lands
  first, then CoinXT composes it.
- **No em-dashes** in committed prose or docs. Comment the *why*, densely.

## As-built notes

Record on-engine and cross-library results here as they are learned: the exact trezor-crypto commit
vendored, any upstream quirk, the confirmed accepted-key formats, and each `VERIFY:` promoted to fact
once a CoinXT signature verifies externally.

**Phase 1, hash slice - DONE and verified (2026-07-02).** The FFI/build pipeline is proven end to end:

- Vendored the trezor-crypto SHA-3 unit (`sha3.c/h`, `memzero.c/h`, `byte_order.h`, `options.h`) at
  commit `230cfe37e4c5fefb6ca117725d261a7b3646a995` (see `native/vendor/VENDOR.md`; MIT `LICENSE`
  shipped). Note `byte_order.h` is header-only (there is no `byte_order.c` upstream; a fetch of it 404s).
- `native/coinxt.c` exposes `cnx_abi_version`, `cnx_keccak256`, `cnx_sha3_256`, and the length functions.
  It builds via `native/build.sh` (a plain shared lib for ctypes/LCB, and an ASan+UBSan self-test).
- Verified: the ASan/UBSan self-test runs clean; `cnx_keccak256` matches the published Ethereum vectors
  (`keccak256("")` = `c5d2...a470`), `cnx_sha3_256` matches Python `hashlib` (NIST FIPS-202), and the two
  are provably distinct (the Keccak-vs-SHA3 footgun guarded in `tools/coin-kat.py`).
- `tools/coin-kat.py --check` builds from source and runs the vectors headless (`self-check OK`). This is
  the CoinXT analogue of OnionXT's KAT harness; it grows with each phase.

**Phase 1, the rest of the hash surface - DONE and verified.** `cnx_sha256`, `cnx_sha512`,
`cnx_ripemd160`, `cnx_hmac_sha256`, `cnx_hmac_sha512`, and `cnx_pbkdf2_hmac_sha512` are built, with
their length functions, and the ABI moved 1 -> 2 (additive, but the rule is to bump on any ABI change
so `cxCheckABI()` can refuse a stale binary instead of failing at the first missing bind):

- Vendored `sha2.c/h`, `ripemd160.c/h`, `hmac.c/h`, `pbkdf2.c/h` at the SAME pinned commit as the
  existing files, each verified byte-identical to upstream by re-fetching the blob and comparing
  SHA-256, then pinned in `native/MANIFEST.sha256` (15 files now).
- **The boundary that mattered.** Our ABI carries lengths as `size_t`, but the vendored primitives do
  not: `hmac_*` take `uint32_t` and `pbkdf2_hmac_sha512` takes `int`. An oversized `size_t` would be
  silently TRUNCATED by the implicit conversion and the primitive would hash a shorter message than the
  caller asked about - a wrong answer, not a crash. `cnx_fits_u32` / `cnx_fits_int` refuse instead
  (`CNX_ERR_RANGE`, the one new status code). The u32 test compiles out where `size_t` is already
  32-bit, so `-Wextra` cannot complain about a tautological comparison; both preprocessor branches were
  compiled clean under `-Werror`.
- **Two more fail-closed refusals**, both cases where upstream would otherwise be quietly wrong rather
  than loud: `iterations == 0` (upstream's loop is seeded at 1, so a zero count yields the
  ONE-iteration key - far weaker than requested, with no error) and `outlen == 0` (the block loop never
  runs and the call "succeeds" having written nothing).
- KATs: every digest is pinned to a PUBLIC vector and, where Python has an independent implementation,
  cross-checked against it live - FIPS 180-4 for SHA-2, the RIPEMD-160 spec vectors, RFC 4231 for HMAC,
  and the all-"abandon" BIP-39 mnemonic + "TREZOR" seed for PBKDF2 (the exact shape CoinXT will use the
  KDF for, not just the primitive), plus a non-block-multiple output length to exercise the partial
  final block. The harness was mutation-tested: dropping the HMAC key, removing the zero-iteration
  guard, and aliasing a digest each make it fail with a non-zero exit.

**Phase 1, the `.lcb` foreign module - DONE; engine pass recorded 2026-08-08.**
`tests/suite-selftest.livecodescript` ran green on a real OXT engine: the module loaded, its binds
resolved, and keccak256(`""`/`"abc"`), sha256(`"abc"`), ripemd160(`"abc"`) came back byte-exact with
`cxSha3_256` distinct from `cxKeccak256`. That closes phase 1 (see IMPLEMENTATION-PLAN.md). Twelve of
the sixteen public handlers were not called by name in that run - `cxCheckABI` (proven transitively:
`sPrepare()` is its entire body and every wrapper calls it), the seven `*Len` accessors, `cxSha512`,
`cxHmacSha256`, `cxHmacSha512`, `cxPbkdf2HmacSha512` - so those stay "verified statically" as
individual handlers even though the seam beneath them is now observed. **The reason that gap existed is
closed:** CoinXT was the only member with no self-building harness, which is why the suite pass could
reach just 4 handlers. `tests/coin-selftest.livecodescript` now drives all 16 in one paste, so the next
engine session retires the remaining 12 in a single run.
`src/coinxt.lcb` is the whole FFI seam: `library org.openxtalk.library.coin`, one
`private foreign handler` per `cnx_` export (all 16, checked name-for-name against the built
library's exported symbols), and a `public cx*` wrapper for each: `cxKeccak256`, `cxSha3_256`,
`cxSha256`, `cxSha512`, `cxRipemd160`, `cxHmacSha256`, `cxHmacSha512`, `cxPbkdf2HmacSha512`, the
seven `cx*Len` accessors, and `cxCheckABI()`. The decisions worth knowing before editing it:

- **Sizes are `UIntSize`, everywhere, including as a RETURN type.** Our ABI carries every length as
  C `size_t`, so every length parameter marshals as `UIntSize` (the family rule: a 4-byte int into
  an 8-byte size slot corrupts the heap), and so do the `cnx_*_len()` returns. The one exception is
  the PBKDF2 iteration count, which is a C `uint32_t` and therefore `CUInt`. `UIntSize` was proven
  in this family as a parameter (`MCMemoryAllocate`, in the on-engine-verified `sodium.lcb`); as a
  *return* type it was reasoned rather than observed until the 2026-08-08 engine pass, which
  **settled it: it works.** Every digest that run checked was byte-exact, and each one's buffer was
  sized from a `cnx_*_len()` declared `returns UIntSize` - a mismarshalled length would have
  allocated wrong and broken the digest. The `CUInt` fallback is not needed; do not "simplify" these
  declarations to it.
- **No `-needed` retry path.** SodiumXT's shim returns bytes-written-or-`-needed`, so its LCB layer
  guesses a capacity and retries. Ours returns a status and writes a FIXED size the shim itself
  reports (or exactly the PBKDF2 output length asked for), so this layer asks for the size,
  allocates exactly that, and copies exactly that back. No size is hardcoded in the `.lcb`.
- **The ABI check runs on every call and is deliberately not memoized.** A module-scope variable
  would save an FFI call, but the default value of an unassigned module variable is not something
  we can verify headlessly, and being wrong about which binary is loaded is unacceptable in a
  library that handles money. `cnx_abi_version()` returns a compile-time constant; the call is
  cheap.
- **Errors are thrown, prefixed, and name the handler** (`"CoinXT: cxSha256: ..."`), so a caller can
  `try`/`catch`. The status code is NOT interpolated into the message: the set is closed (-1/-2/-3),
  and an unrecognised status can only mean a library newer than this binding, which the ABI guard
  already refuses. That also avoids relying on LCB number-to-String coercion inside a concatenation,
  which we cannot verify headlessly.
- **A secret-hygiene limit is documented, not papered over.** `cxPbkdf2HmacSha512` returns a seed;
  the raw block is freed WITHOUT being wiped, because there is no engine `<builtin>` we can name
  that zeroes one, and the returned `Data` is not locked memory. The file says so, and notes that a
  future `cnx_memzero(ptr, len)` export would fix it (a shim change, hence an ABI bump: not
  smuggled in).
- Verified: `tools/check-livecodescript.py` passes (it now actually has a file to check, where it
  previously reported "no .lcb or .livecodescript files found"); every `binds to "c:coinxt>..."`
  string, argument count, per-argument type mapping, and return type was diffed mechanically
  against `native/coinxt.c`; the bind set equals the exported-symbol set of a freshly built
  library (16/16, `nm -D`); and `kABIVersion` (2) equals `CNX_ABI_VERSION`. Nothing here has been
  RUN: OXT cannot compile or load a `.lcb` headlessly. Per IMPLEMENTATION-PLAN.md, phase 1 is done
  when `cxKeccak256` and friends return the pinned vectors from a real engine; the file header
  lists, in order, exactly what that pass must confirm.

After that (phase 2): the secp256k1 curve surface (keypair, ECDSA, recoverable, recover, ECDH),
with a signature that must verify in an independent library.

**Repo-prep - self-contained for the split (2026-07-07).** CoinXT no longer reaches outside its own
directory for anything; it is ready to become the root of its own repository (the procedure and the
post-split checklist are in [MIGRATION.md](MIGRATION.md)):

- The static gates (`tools/check-livecodescript.py`, `tools/check-docs-style.py`) are carried verbatim
  into `tools/`, alongside `tools/coin-kat.py`. Every `../` reference in the docs was retargeted.
- The portable xTalk/LCB lesson book is carried at `templates/CLAUDE.md`, synced byte-identical with
  OnionXT's copy at fork time (including the newest on-engine lessons: the `the detailedFiles` "bad
  factor", the unchecked `accept connections` bind failure, the CRLF returned by `read ... until crlf`,
  and the streaming no-quantifier read). After the split each repo maintains its own copy, the family
  pattern; keep appending to the living-gotcha log.
- CI ships at `.github/workflows/ci.yml`: both static gates, the vendored-source `MANIFEST.sha256`
  check, `coin-kat.py --check` (builds the shim from source, drives it via ctypes), and the ASan/UBSan
  self-test. It is dormant while CoinXT is nested (GitHub reads only the repo root's `.github/`) and
  goes live on the split.
- `native/MANIFEST.sha256` pins every vendored trezor-crypto file. Refresh it in the same change as any
  vendor re-pin. The shipped per-platform binaries are pinned separately in `src/code/MANIFEST.sha256`,
  which is where every other suite member pins them, so one gate shape covers all six.
