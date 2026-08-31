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
upstream's - trezor-crypto's, and since ABI 6 (2026-08-16) upstream bitcoin-core/secp256k1's for BIP-340
Schnorr, x-only keys and the BIP-341 tweak (trezor-crypto's plain-C tree has no BIP-340; the rule change
that admitted a SECOND vendored library is SPEC.md section 2.1).

```
app (livecodescript)
   |
CoinXT public API (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT: hex, Base58Check, Bech32/Bech32m, RLP, xprv/xpub, WIF, EIP-55, addresses
   |- FFI seam: one .lcb module, unsafe ... end unsafe around every foreign call
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto subset
                                        +  vendored libsecp256k1 subset (ABI 6)
   |- curve + hashes in C: secp256k1 (ECDSA/recoverable/recover/ECDH) trezor-crypto;
      BIP-340 Schnorr, x-only keys and the BIP-341 tweak libsecp256k1;
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

1. **Add no cryptography. Wrap an audited upstream.** Every scalar multiply, signature, and hash is
   upstream, audited code. A missing primitive is a new vendored file or an upstream request, never a
   hand-rolled curve op or hash here. There is no CoinXT cipher.
   > **This rule used to say "Wrap trezor-crypto", singular, and it CHANGED on 2026-08-16.** There
   > are two vendored libraries now: trezor-crypto and upstream bitcoin-core/secp256k1. The full
   > text of the change, the reasoning, and the new audit surface are in the ABI 6 as-built entry at
   > the end of this file and in SPEC.md section 2.1. The part of the rule that matters is unchanged:
   > CoinXT still implements no cryptography of its own.
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
re-derives every one it can and reports the honest split rather than a count of what it parsed (`85 of
130 harness constant(s) re-derived, 45 are inputs` as it stands, each of those 45 listed with a written
reason, so a constant that is neither re-derived nor excused fails the build) - against `hashlib` /
`hmac` where Python has an independent implementation, against the published table in `coin-kat.py`
for Keccak-256 (Python has no Keccak) and for RIPEMD-160 when OpenSSL 3 has moved it out of reach,
saying so rather than skipping quietly. It also re-checks the
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
  exports 238 symbols today, only 35 of them ours (77 and 16 when this was first measured, in phase
  1) - the rest are upstream's `sha256_Init`, `hmac_sha512`, `keccak_256`, `ripemd160`, and (worst)
  plain `memzero`. Those are generic names another extension in
  the same engine process could also export, and the dynamic loader would pick one for both. Silently
  running a stranger's `sha256_Final` inside a money library is not a risk worth carrying for zero
  benefit, so `src/coinxt.map` narrows the exports to `cnx_*`. `pack` prints the symbol list it actually
  shipped; if it is longer than 35 names your linker refused the version script (it says so) - the
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
keeps the trusted native surface tiny (43 buffer-in / buffer-out functions at ABI 6, SPEC section 5.1) and
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

- **No KEY MATERIAL from an ambient RNG** (this rule used to read "no RNG in the shim"; phase 2 proved
  that version wrong, and the correction matters more than the original). trezor-crypto requires an
  integrator `random_buffer` / `random32`, and the old instruction was to wire it to ABORT because
  "nothing should call it once signing is RFC 6979 and keys come from the caller." **Nothing about
  that is true.** `vendor/ecdsa.c` calls it on EVERY curve operation: `curve_to_jacobian()` randomizes
  the projective Z coordinate on every scalar multiply, and `ecdsa_sign_digest()` draws a second value
  to blind the modular inversion. Both are side-channel countermeasures, not nonce generation. So
  abort-on-call kills the host process at the first `cxPublicKey`, and returning a constant either
  hangs (`generate_k_random` loops while the value is zero or out of range) or silently deletes
  upstream's countermeasure.
  What survives of the rule is the part that protects the user: fresh private keys are still the
  caller's (`cxNewSeckey` validates 32 caller-supplied bytes, composed from SodiumXT `sxRandomBytes`)
  and nonces are still RFC 6979, so no key can be weak because of an RNG here. The blinding entropy
  comes from the OS (`getrandom` / `BCryptGenRandom` / `arc4random_buf`), fails closed
  (`CNX_ERR_ENTROPY` from a pre-flight, `abort()` only where the void upstream signature leaves no
  other option), and an unknown platform is a COMPILE error rather than a weak fallback. The blinding
  cancels out of the result algebraically, which is why signatures stay KAT-pinnable; `coin-kat.py`
  proves that empirically by signing the same input 32 times and requiring one distinct answer.
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
- **`the itemDelimiter` is a REAL dependency of the script layer, and this repo already answered what
  the property is.** Comma-separated lists are how that layer moves 5-bit groups, converter output,
  mnemonic words and path levels, and every `item` expression reads the engine's CURRENT delimiter, so
  a caller who changed it and did not restore gets a silently wrong address rather than an error.
  This entry previously called the property's scope an open question for the engine pass. **It is not
  open.** [templates/CLAUDE.md](templates/CLAUDE.md) rule 5 - carried into this member verbatim - says
  `itemDelimiter` and `lineDelimiter` are GLOBAL MUTABLE STATE, to be set immediately before the parse
  that needs them and RESTORED afterward, because other code assumes the defaults. OnionXT, the member
  with the most on-engine hours, does exactly that at six sites (see `oxFieldAfter`). So the remedy is
  save/set/use/restore - NOT `set the itemDelimiter to comma` at the top of a handler, which would
  leave the caller's delimiter changed and is the very thing the rule forbids. Applying it here is a
  change of its own, because this layer throws by design and a handler that throws must restore on the
  way out too. **FIXED 2026-08-08**, and measured rather than assumed: modelling the property in
  `tools/lcs-interp.py` showed a hostile delimiter made `cxBtcAddressP2WPKH` fail outright and
  `cxMnemonicValidate` answer FALSE to a perfectly good twelve-word backup - a wrong answer, not an
  error. Nine of the thirty public handlers were affected. Each now has a save/set/use/restore WRAPPER
  around an untouched `Inner` body: restructuring nine vector-verified handlers to thread a restore
  through every return and every throw is exactly the edit that introduces the bug it was meant to
  prevent. The gate now requires every guarded handler to be indifferent to the delimiter AND to hand
  the caller's setting back, including on the throw path. **The transferable lesson: read the carried
  lesson book before filing an engine question. This one had been answered for years.**
- **Verify every checksum on decode and fail closed:** Base58Check's 4-byte double-SHA-256 tail,
  Bech32/Bech32m's polymod (constant 1 vs 0x2bc830a3, SegWit v0 vs v1+), EIP-55's mixed case. A corrupt
  address must be rejected, never coerced.
- **Keccak-256 is NOT SHA3-256.** Ethereum uses the original `0x01` padding; FIPS-202 uses `0x06`. Two
  different shim functions (`cnx_keccak256` vs `cnx_sha3_256`); never alias them. This is the classic
  Ethereum footgun.
- Pin every encoding to its public vector (BIP-173/350 including INVALID cases, EIP-55 examples, the RLP
  yellow-paper examples).

## LiveCodeScript / LCB / OXT gotchas (carried; see [templates/CLAUDE.md](templates/CLAUDE.md) for the full list)

> **Engine BEHAVIOUR - as opposed to the conventions here - is collected in
> [`docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md)**, with the verbatim
> symptom, what each one broke, and the gate (if any) that now holds it. Keep
> member-specific gotchas in this file; put anything the ENGINE does there, so
> there is one authoritative list instead of ten that drift.

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

**THE INTERPRETER GREW A SECOND MEMBER, IN THIS COPY (2026-08-23).** nostrxt's execution gate
(its docs/08 question 9) extended `tools/lcs-interp.py` HERE - the interpreter's home - and
carries a byte-identical copy under `nostrxt/tools/`, drift-gated by the suite's
`check-checker-drift.py` exactly like the checker copies, so an interpreter lesson can never
again apply to one member and not the other. The additions are the constructs nostrxt's core
uses beyond this member's subset (command/on handlers and statement calls, chained subscripts,
the keys-of family, the lineDelimiter as modelled state, script-level locals, UTF-8
textEncode/textDecode, base64, a handful of operators), each a named divergence or a documented
model in the header; everything else still refuses loudly. This member's own gate is the
REGRESSION PROOF for every such extension: `check-script-vectors.py` ran green at 300 checks
over the extended interpreter before and after each addition, which is the bar any future
extension pays too. One model correction worth knowing when reading `_eq`: an array operand of
`is` compares AS AN ARRAY (a populated array is not empty), modelled from riptide's
engine-proven refusal idiom - the classic folds-to-empty rule was tried first and was refuted
by the corpus.

## Git / workflow

- Develop on a per-task branch; commit there, open a **draft PR** if none exists. Do not push to `main`
  without explicit permission.
- A script change is "done" once the static gates pass and it has had (or is clearly flagged as needing)
  an on-engine pass. A shim change is "done" once it builds clean under ASan + UBSan, the KATs pass, and
  the ABI + `cxCheckABI()` are bumped in the SAME change.
- In the suite monorepo, `src/coinxt.livecodescript` is also EMBEDDED verbatim in the generated
  `tests/suite-selftest.livecodescript` (one paste carries the library its tests call, so a stale
  in-memory copy cannot masquerade as a failing fix - that happened, 2026-08-10). A script-layer edit
  therefore additionally requires `python3 tools/build-suite-selftest.py` at the suite root; the gate
  set's `--check` fails the build otherwise. It is ALSO carried verbatim into
  `examples/coinxt-demo.livecodescript` (2026-08-17) and `tests/coin-selftest.livecodescript`
  (2026-08-18), between the sentinels
  `tools/sync-demo-embeds.py` (at the suite root) owns, so each is paste-and-run without a
  `start using stack "coinxt"` step. Nobody edits inside the sentinels. So a `src/coinxt.livecodescript`
  edit is not done until that tool has been re-run too - CoinXT's own `tools/` does not carry it, and the
  member gates cannot see the drift; the suite gate set's `--check` is what fails. The suite paste already
  embeds this layer once as a script layer, so `build-suite-selftest.py` cuts the coin-selftest copy back
  out (`strip_spans` on the coin row); the demo is not folded at all.
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
`cxHmacSha256`, `cxHmacSha512`, `cxPbkdf2HmacSha512` - and that residual was RETIRED on 2026-08-10:
`tests/coin-selftest.livecodescript`, folded into the suite harness, called every public handler by
name (including `cxCheckABI` at last) and ran green on a real engine, 207/207 on the same-day re-run.
Nothing in phase 1 is "verified statically" any more.
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

**Phase 2, the secp256k1 curve - BUILT, CROSS-VERIFIED, and engine-passed 2026-08-10.**
ABI 2 -> 3. The shim exports `cnx_seckey_verify`, `cnx_pubkey_from_seckey`, `cnx_pubkey_decompress`,
`cnx_ecdsa_sign`, `cnx_ecdsa_verify`, `cnx_ecdsa_sign_recoverable`, `cnx_ecdsa_recover`, `cnx_ecdh`
and six length accessors (30 `cnx_*` exports now, up from 16), and `src/coinxt.lcb` wraps each one.

- **The phase-2 bar is met at the C level.** IMPLEMENTATION-PLAN says phase 2 is done when "a signature
  CoinXT makes verifies in an independent library, and `cxRecover` returns the signing pubkey." Both
  hold: `tools/coin-kat.py` reproduces four published RFC 6979 secp256k1 signatures byte for byte, a
  CoinXT signature verifies in Python `ecdsa`, a signature `ecdsa` made verifies in CoinXT, and
  recovery round-trips to the signer. The fifteen public `cx*` handlers ran on-engine on 2026-08-10
  (the folded harness), green: the CInt flag marshalled (33 vs 65 bytes, distinct), the Boolean
  returns answered both ways, and `cxRecover` returned the signing key. The phase is closed.
- **The phase-0 entropy decision was wrong and is corrected above.** That is the single most important
  thing learned in this phase; read "Determinism and entropy" before touching the shim.
- **The vendored set is a CLOSURE, found empirically** (compile, read the undefined symbols, add the
  file that defines them, repeat) and it is larger than it looks like it should be: `hasher.c` plus
  blake256/blake2b/groestl come in because `ecdsa.h` types its message-signing entry points against
  `HasherType`, and `base58.c`/`address.c` because `ecdsa.c` carries address helpers we never call.
  `secp256k1.table` (126 KB) is NOT needed, because `options.h` sets `USE_PRECOMPUTED_CP=0`. See
  `native/vendor/VENDOR.md`; every file's git blob id was checked against the pinned commit's tree.
- **The guard upstream cannot write for us.** `ecdsa_read_pubkey()` dispatches on the leading byte and
  reads 65 bytes whenever it sees `0x04`, and is never told the buffer length - so a 33-byte key whose
  first byte is `0x04` is read 32 bytes past its end. Every public key crosses the `cnx_` ABI as
  pointer PLUS length and the shim refuses a pair that disagrees. There is a KAT for it and an
  ASan case for it; do not "simplify" the length argument away.
- **Two upstream return conventions are inverted from each other**, in the same header:
  `ecdsa_sign_digest` and `ecdsa_recover_pub_from_sig` return 0 for success, while `ecdsa_read_pubkey`
  and `ecdsa_uncompress_pubkey` return 1 for success and 0 for failure. Each call site in the shim says
  which it is.
- **Low-s is upstream's, not ours.** `ecdsa_sign_digest` unconditionally replaces s with `order - s`
  when s is above the halfway point and flips the recovery bit with it, so signatures are canonical for
  both Bitcoin relay policy and Ethereum consensus without CoinXT normalising anything.
- **ECDH returns the RAW 65-byte point** (`0x04 || X || Y`), not the 32 bytes SPEC.md 5.1 sketched.
  Truncating to X or hashing it would be CoinXT inventing a convention; the caller composes the KDF its
  protocol specifies.
- **The `x86-linux` binary is cross-compiled with Zig, and that is deliberate.** The
  environment that rebuilt the other three has no 32-bit libc and cannot install
  `gcc-multilib`, so `src/code/x86-linux/coinxt.so` was built with
  `zig cc -target x86-linux-gnu.2.25` (a `cc` wrapper on PATH, which is the same
  mechanism `build.sh` already documents for a cross build). The result is a 32-bit
  i386 ELF exporting exactly the 30 `cnx_*` names and nothing else, needing only
  `libc.so.6` at the GLIBC 2.25 floor this member documents. Two things make that
  safe rather than hopeful: the same source built with the same Zig for x86_64
  passes the entire KAT suite including the cross-library leg, and CI now
  **executes** the committed library against the published vectors on every push
  (`native-coinxt.yml`, "Execute the COMMITTED library's vectors"), which no
  committed library had before. `release-binaries.yml` will overwrite it with a
  gcc-multilib build whenever it next runs, and that step re-verifies it the same
  way; nothing here depends on Zig staying in the picture. (It happened: release
  run 31551536144, 2026-08-12, replaced the Zig build and re-verified it.)
- Verified: ASan + UBSan clean over the whole curve surface (`sh native/build.sh asan`),
  `tools/coin-kat.py` green (four RFC 6979 vectors, G and 2G, decompression round-trip, 8 verification
  rejections including the overread guard, ecrecover, ECDH both directions, 10 fail-closed guards,
  32-way determinism, and the cross-library leg), every `.lcb` foreign declaration diffed mechanically
  against the C (arity, per-argument type, return type: 30/30), and the bind set equal to the built
  library's exported symbols (30/30).

**Phase 3, encodings and addresses - BUILT, EXECUTED headlessly (new for a pure-script
layer), and engine-passed 2026-08-10.** `src/coinxt.livecodescript` ships 19 public handlers
from this phase: hex, Base58Check, bech32/bech32m, SegWit addresses, `cxHash160`/`cxHash256`,
the four address builders and RLP. No shim change; the ABI is untouched at 3.

- **The script is not part of the .lcb and does not load with it.** It goes in the message
  path (`start using stack "coinxt"`), the way OnionXT ships its `ox*` surface, and
  `tools/package-extension.py` now stages it beside the binaries. A user whose hashes work
  and whose `cxBtcAddressP2PKH` says "handler not found" has loaded the extension and not the
  script; say so in that order when triaging.
- **A pure-script layer used to be unverifiable headlessly. It is not any more.**
  `tools/lcs-interp.py` interprets the LiveCodeScript subset the encoders are written in, and
  `tools/check-script-vectors.py` runs THE REAL FILE against the published BIP-173, BIP-350,
  EIP-55, RLP and Base58Check vectors, with the hashes supplied by the real shim through
  ctypes. 87 checks, in the gate set, on every push. This is an approximation of the engine
  and settles LOGIC only; parser behaviour got its OXT pass on 2026-08-10, when the whole
  layer ran green folded into the suite harness (and the day's one parser difference - the
  trailing-delimiter counting rule, below - was in phase 4's path walker, not the encoders).
  It found a real ambiguity while being built (a
  `the number of items of X < 1` that let the count swallow the comparison), which is
  precisely the kind of thing that would otherwise have burned an engine session.
- **The three portability disciplines are in the file header and are not optional.** No `^`,
  `div`, `mod`, `bitAnd`, `bitOr` or `bitXor` anywhere (all replaced by arithmetic helpers,
  including a 31-bit `cxBitXor` the bech32 checksum needs); every accumulator masked each step
  so nothing approaches 2^53; and alphabet lookup by BYTE VALUE rather than `offset()`.
- **That last one is the most dangerous line in the file.** `offset()` and `is` honour `the
  caseSensitive`, which defaults to FALSE, and in Base58 `a` and `A` are DIFFERENT DIGITS. A
  case-insensitive lookup decodes a different number and hands back a valid-looking wrong
  key. `cxCharIndex` compares `byteToNum` values instead, which is exact whatever the caller
  has set. Do not "simplify" it.
- **Base58 is a base conversion, not a bit repack**, so there is no bit-buffer trick: a 25-byte
  payload is a 200-bit number no xTalk number holds exactly. `cxBase58Encode` does long
  division over the byte array, and nothing in it exceeds 58 * 255.
- **`cxBtcAddressP2TR` encodes an output key it is GIVEN.** It does not tweak. BIP-341's
  `Q = P + int(tagged_hash(P || merkle_root))G` needs the BIP-340 surface deferred with
  Taproot, and feeding it a raw internal key yields a valid-looking unspendable address. The
  handler's comment says so; keep it saying so.
- Verified: `tools/check-script-vectors.py` green (87 checks), the constants tier compared
  against `tools/coin_reference.py` (which reproduces the published vectors independently),
  the gate mutation-tested, `tools/check-selftest-vectors.py` re-deriving the harness's new
  phase-3 constants AND asserting the two NEGATIVE vectors are genuinely negative, and
  `tools/check-livecodescript.py` clean.

**Schnorr / BIP-340 was DEFERRED here, and SHIPPED at ABI 6 on 2026-08-16 - see the entry at the
end of this file. The reasoning below is what decided the eventual answer, so it stays.** The plan left "which
upstream path provides it" open. The answer: not this one. trezor-crypto's plain-C tree has no BIP-340
implementation - it reaches Schnorr only through `zkp_bip340.c`, which requires the bundled
`secp256k1-zkp` library and its own build system, a vendoring an order of magnitude larger than
everything above. Phase 2 therefore ships ECDSA, recoverable ECDSA, recovery and ECDH, and Schnorr
moves to the Taproot phase where the `secp256k1-zkp` cost can be weighed against P2TR as a whole. That
is a scope decision, recorded here rather than left as a silent omission.

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

**Phase 4, HD wallets and mnemonics - BUILT, executed headlessly end to end, and
engine-passed 2026-08-10.** ABI 3 -> 4.
The shim gains four exports (34 now), `src/coinxt.lcb` wraps three of them, and
`src/coinxt.livecodescript` gains eleven public handlers: `cxMnemonicNormalize`,
`cxMnemonicFromEntropy`, `cxMnemonicToEntropy`, `cxMnemonicValidate`, `cxMnemonicToSeed`,
`cxHdFromSeed`, `cxHdNeuter`, `cxHdDeriveChild`, `cxHdDerivePath`, `cxXprv` and `cxXpub`.

- **The phase-4 bar is met headlessly.** IMPLEMENTATION-PLAN says phase 4 is done when "the official
  BIP-39 mnemonic + a BIP-44 path reproduce the reference address, byte for byte." They do:
  `tools/check-script-vectors.py` runs the REAL script against 14 official BIP-39 entropy vectors,
  BIP-32 test vectors 1-3, and the "abandon ... about" mnemonic down `m/44'/0'/0'/0/0`,
  `m/84'/0'/0'/0/0` and `m/44'/60'/0'/0/0` to the published Bitcoin and Ethereum addresses. 170
  checks, up from 87 (219 after the trailing-separator negatives; 251 now that phase 5 executes too).
  The ENGINE pass followed on
  2026-08-10: the folded harness walked the same paths to the same published addresses on a real
  engine, and the phase closed at 207/207 on the re-run - after the engine surfaced the one real
  defect, the `"m/"` fail-open recorded at the end of this file.
- **The vendoring decision that mattered: `bip32.c` was NOT taken.** It would have given BIP-32 for
  free, but it is written against every curve trezor supports, so it drags in `curves.c`,
  `nist256p1`, `ed25519-donna` and the Cardano variants - a large closure, nearly all of it code
  CoinXT would ship, license and never call. BIP-32 needs exactly TWO things from the curve, and the
  already-vendored `ecdsa.c`/`bignum.c` have both: `cnx_seckey_tweak_add` (the `bn_add` / `bn_mod` /
  `bn_is_zero` sequence lifted from upstream's own `hdnode_private_ckd_bip32` - `bn_add` leaves a
  PARTLY reduced value, so dropping the `bn_mod` gives a silently wrong key) and
  `cnx_pubkey_tweak_add` (upstream's `ecdsa_tweak_pubkey`, used as is). Everything else about HD
  derivation is byte shuffling and lives in script, which is what the C-vs-script rule asks for.
- **Both tweak entry points refuse a ZERO tweak, where upstream's public one accepts it.** BIP-32
  only calls a child invalid when `parse256(IL) >= n` or the result is zero/infinity, so `IL == 0` is
  technically legal and yields a child EQUAL TO ITS PARENT. Accepting it on one path and refusing it
  on the other would make private and public derivation of the same child disagree about validity,
  which is an interoperability bug of exactly the kind this member exists to prevent. It cannot arise
  in practice (one HMAC-SHA512 output in 2^256) and BIP-32's own remedy - move to the next index - is
  unchanged.
- **The wordlist is vendored, not transcribed, and the claim is CHECKED.** `bip39_english.c` +
  `bip39.h` come from the pinned commit (blob ids verified), and cross as one 16384-byte blob of 2048
  fixed-width 8-byte slots (`cnx_bip39_wordlist`). Fixed width is what makes index -> word one chunk
  expression and word -> index a binary search instead of a 2048-step scan. `tools/coin-kat.py` reads
  the list back through the shim, joins it canonically and requires SHA-256
  `2f5eed53...b24dbda` - the hash BIP-39 itself publishes - plus sorted and duplicate-free, because
  the script binary-searches it. Hand-copying 2048 words would have been 16 KB of unreviewable diff
  and one typo away from a wallet that cannot restore its own seed.
- **`cxMnemonicNormalize` is not cosmetic.** BIP-39 derives the seed from the mnemonic STRING, so a
  trailing newline from a paste would produce a different seed from every other wallet holding the
  same words, silently. Normalizing to single spaces is what every interoperable implementation does,
  so validate / to-entropy / to-seed all run it first. It does NOT do Unicode NFKD: for the English
  list that is a no-op (all ASCII), and a non-ASCII PASSPHRASE is the caller's to normalize. Said so
  in the file and in the docs.
- **`cxMnemonicToSeed` deliberately does not verify the checksum**, because BIP-39 defines the seed
  for any string. That is the spec's design, but it means a typo yields a perfectly good seed for the
  wrong wallet, so the docs and the handler comment both say to call `cxMnemonicValidate` first on
  anything a human typed.
- **The interpreter grew value semantics for arrays, and it had to.** xTalk arrays are VALUES:
  `put tA into tB` copies. Python dicts are references, so `tools/lcs-interp.py` now deep-copies at
  every binding (assignment, argument, return). Without it `cxHdNeuter` would have appeared to blank
  the CALLER's private key - the interpreter would have modelled a bug the engine does not have. It
  also grew `try`/`catch`, `replace ... in`, and the `comma`/`space`/`tab`/`quote` literals, and
  `_disp` now REFUSES to stringify an array rather than rendering a Python dict into a chunk
  expression.
- **A lesson about mutation testing itself.** A focused mutation probe reported "reversing BIP-39's
  11-bit unpacking order is NOT CAUGHT". It was wrong: the probe only exercised the ENCODE direction,
  while the mutation was in the decoder. The real gate catches it (the round trip throws on the
  checksum and `cxMnemonicValidate` goes false, both asserted). When a mutation survives, suspect the
  probe before the gate - but check, do not assume.
- Verified: `tools/coin-kat.py` green including the wordlist hash, BIP-32 vector 1 walked with both
  tweak exports, CKDpub agreeing with CKDpriv at every non-hardened level, and nine new fail-closed
  guards; `sh native/build.sh asan` clean over the new entry points (the 16 KB wordlist write is
  exactly the shape ASan is best at); `tools/check-script-vectors.py` green at 170 checks and
  mutation-tested (nine phase-4 mutations, all caught); `tools/check-selftest-vectors.py` re-deriving
  all 60 harness constants and mutation-tested (six, all caught); all four committed binaries rebuilt
  at ABI 4 with 34 exports each and `tools/check-binary-freshness.py` clean.

**The adversarial review of phase 3, and what it found (2026-08-08).** An independent review of the
shipped script layer raised 19 claims; 13 survived verification, deduplicating to **five real
defects**, and every one of them **FAILED OPEN** - a wrong answer that looked like a right one. All
five are fixed, and each now has a vector that would have caught it. This is the most useful thing
that has happened to this member, so the pattern matters more than the list:

- **`cxEthAddressIsChecksummed` compared a value with itself.** It read
  `cxEthAddressChecksum(pAddress) is cxEthAddressChecksum(cxToLower(tPlain))`, but
  `cxEthAddressChecksum` lowercases its argument before it hashes or emits anything, so both sides
  were the same string for every input. It answered **true to every mixed-case address**, including a
  corrupted one - the exact failure EIP-55 exists to prevent. The fix compares the computed form
  against the caller's UNTOUCHED text, by byte value (`is` could not have decided it either, since
  the whole question is case).
- **`cxConvert5To8` signalled failure in-band, as the string `"ERROR: ..."`**, and the decoder tested
  `char 1 to 5 of tProgram is "ERROR"`. A bech32m v1 witness program may be any 2 to 40 bytes, so a
  program beginning `45 52 52 4F 52` was read as a failure: **the library rejected an address its own
  encoder had just produced.** An in-band sentinel over arbitrary bytes is always wrong - there is no
  byte string that cannot occur. The status is now a separate key in an array.
- **`cxBtcAddressP2PKH` validated nothing.** `hash160` hashes anything, so an empty string, a 20-byte
  hash or a truncated key each produced a well-formed, checksummed, **permanently unspendable**
  mainnet address. Nothing downstream can catch that: the address is valid, it is simply not yours.
  P2WPKH and P2TR both checked; P2PKH was the one that did not. There is now a shared
  `cxCheckPubkey` that checks length AND prefix, the same rule the shim's `cnx_pubkey_ok` applies.
- **`cxBech32EncodeValues` accepted data values outside 0..31.** `char (n) of` a 32-character charset
  returns EMPTY past the end, so an out-of-range value emitted **nothing** - a bech32 string one
  character short, carrying a checksum over data it does not contain.
- **`cxSegwitAddressEncode` failed open on a non-lowercase HRP**, emitting `BC1qqq...` - a MIXED-case
  string BIP-173 forbids and this file's own decoder rejects. The 90-character cap is now enforced on
  the encoder too, for the same reason: an encoder that can emit a string its own decoder refuses
  will eventually be used to make one.

Also changed, on the same principle though not observed to collide: the Base58Check checksum
comparison used `is` on two hex strings, and `is` compares operands that both LOOK numeric as
NUMBERS. Whether `00001e00` equals `00000001` then stops being a question about bytes and becomes one
about how the engine parses exponents. It goes through `cxCompareBytes` now. **Discipline 3 already
covered this** - a comparison whose answer depends on engine coercion does not belong on a checksum
path - it just had not been applied here.

**The lesson, and it is the reusable part: every one of these was invisible to a vector set that only
ever fed the handlers WELL-FORMED INPUT.** 87 passing checks against BIP-173, BIP-350, EIP-55 and RLP
did not touch a single one, because a positive vector cannot catch a check that is not being made.
The five published EIP-55 vectors could not even detect a tautology, since a tautology returns true
for a true positive too. When adding a handler here, add the vector for what it must REFUSE in the
same change as the vector for what it must produce.

**Five public handlers were never called by any harness, and two gates were overstating
their own coverage (2026-08-09).** Prompted by nothing more than the question "does the
suite selftest include all the tests?", the answer was measured instead of asserted, and
it was no. `tools/check-suite-coverage.py` (suite root) found **five `cx*` handlers that
no harness had ever invoked**: `cxHash256`, `cxMnemonicNormalize`, `cxHdDeriveChild`, and
both ABI-4 tweak exports `cxSeckeyTweakAdd` / `cxPubkeyTweakAdd`. All five are pure,
deterministic and trivially vector-pinnable, so this was not a hard gap - it was an
unasked question. Each was reachable only INDIRECTLY, and that is what made it dangerous:

- `cxMnemonicNormalize` runs first inside validate / to-entropy / to-seed, so a defect in
  it would have made all three wrong TOGETHER and consistent with each other. Every round
  trip in the vector set would still have closed.
- `cxHdDeriveChild` is the single CKD step `cxHdDerivePath` loops over. Testing only the
  path walker cannot separate "the step is right" from "the loop and the step are wrong in
  the same direction", so the new check pins the single step to BIP-32's own published
  m/0' xprv first, and only then asserts the two agree.
- The tweak pair is the homomorphism BIP-32 non-hardened derivation rests on. If private
  and public tweaking ever disagreed, an xpub watch-only wallet would generate addresses
  its own xprv cannot spend. `1 + 1 = 2` pins both to the curve's second point (2G) rather
  than to each other, and the zero-tweak refusal is now asserted on BOTH paths, because
  refusing on one and accepting on the other is exactly the interop bug this member exists
  to prevent.

All five are now driven headlessly too (`check-script-vectors.py`, 198 -> 211 checks; the
tweaks were already in `coin-kat.py`), so the assertions added to
`tests/coin-selftest.livecodescript` are executed before an engine ever sees them.

**The gate hole is the more transferable part.** `check-selftest-vectors.py` re-derives an
explicit `want(...)` list and then printed `"66 harness constant(s) re-derived"` - a count
of the constants it had PARSED, not the ones it had CHECKED. The two constants added in
this very change (`kHash256Abc`, `kPubTwoCompressed`) sailed straight through it and the
gate still said 66. A gate that overstates its coverage is worse than no gate, because it
answers a question nobody asks twice. It now fails on any `k*` that is neither re-derived
nor listed in `inputs` with a reason, fails on a stale `inputs` entry, and reports the
honest split (`49 of 66 re-derived, 17 are inputs`). Fixing it immediately surfaced two
more: `kSegwitErrorProgram` was never checked to still SPELL "ERROR" (edit those five
bytes and the fail-open regression quietly stops reproducing the bug while still passing),
and the two EIP-55 negatives were never checked to be case-variants of the positive.

**THE FIRST ENGINE PASS OF THE SCRIPT LAYER (2026-08-09), and the fail-open it found.**
Two defects, both in constructs that existed at exactly ONE place in the entire
six-member suite, which is precisely why neither had ever met an engine.

**1. `repeat with tI = 1 to tCount step 2` did not honour its increment.** In
`cxHexDecode`, `tI` walked one at a time, so the last pass read `char (tCount + 1)`,
got EMPTY, and the handler's own fail-closed check threw
`"the input contains a character that is not a hex digit"` over VALID lowercase hex.
Six harness sections died. The shape is what makes it expensive: the library accused
the CALLER'S DATA of being corrupt, in the exact words it reserves for real
corruption, so the symptom pointed at the vector set rather than at the loop. Now
`repeat while` plus an explicit `add 2`, the form `cxBase58Encode` and
`cxConvert8To5` already used.

**2. `throw` from INSIDE a `catch` block does not reach the caller, and this one was
a FAIL-OPEN in the handler whose whole job is catching typos.** The nine
itemDelimiter guards - added in this same session to fix a real exposure - each did
`catch tError / set the itemDelimiter / throw tError`. The engine discards that
throw; the handler falls through to `return tResult` with `tResult` never assigned
and returns EMPTY where it owed an error. Nine "is refused" assertions came back
false. Far worse, and invisible in that run because the section died earlier:
`cxMnemonicValidateInner` reaches `return false` ONLY through its own catch, so with
the error swallowed **`cxMnemonicValidate` answered TRUE for a mistyped twelve-word
backup**. Fixed by capturing the error, closing the `try`, and throwing after
`end try`.

**The control that narrows it, and it matters:** `return` inside a catch is FINE and
engine-proven. onionxt's `oxSodiumHasSha3` reaches `false` only that way (sxSha3_256
does not exist, docs/08 gap #2), it feeds `oxTransportInfo`'s `offlineAddress`, and
the suite harness asserts that IS false - which PASSED in the same run. Had `return`
been discarded the handler would have returned empty, and `empty is false` is false,
so the line would have gone red. Only `throw` is affected. Do not over-generalise
this into "avoid catch".

**Three method lessons, each of which cost a wrong answer before it was learned:**

- **Two confident root causes were WRONG before the right one.** First `byteToNum(char
  ...)` - refuted, because `cxEthAddressChecksum` uses exactly that and EIP-55 passed
  5/5 in the same run. Then `stThrows`'s `do` - refuted, because
  `stThrows("cxEthAddressChecksum", ...)` goes through the identical `do` path against
  a script-layer handler and passed. The partition that actually held was 9/9 guarded
  FAILED, every unguarded handler PASSED. **A hypothesis that does not predict exactly
  the observed set, and nothing else, is not the cause.**
- **Fixing one thing made the next run WORSE, and that was predictable.** Unblocking
  `cxHexDecode` makes 132 previously-dead assertions execute for the first time, eight
  of them negatives against guarded handlers. Shipping the hex fix alone would have
  taken the engine from 9 red lines to 17. When a blocker is removed, count what it
  was hiding before promising an improvement.
- **The gates now refuse both constructs**, in all six copies of
  `check-livecodescript.py`, `.livecodescript` only, mutation-tested 6/6 including
  that `return`-in-catch is NOT flagged.

[Annotated 2026-08-19: the sentence above keeps its original figure, as a dated
record. There are TEN copies of `check-livecodescript.py` today, held
byte-identical by `tools/check-checker-drift.py` and fixture-tested by
`tools/test-checker.py` (75 fixtures x 10 copies = 750 runs). The count in the
prose is the count on the day it was written, not a live number.]

**A note on method, learned twice in one session.** Two mutations were first reported as NOT CAUGHT
and both times the PROBE was wrong, not the gate: one exercised only the encode direction while the
mutation was in the decoder, and one reverted only half of a two-part defect so the bug never
actually came back. When a mutation survives, reconstruct the original defect faithfully and check
that it reproduces before concluding the gate has a hole.

**THE SECOND FULL ENGINE PASS (2026-08-10): 205 of 206, and the one red line was a fail-open the
gate was already testing for.** The whole deep harness ran on a real engine inside the folded suite
selftest - every phase, every handler, the only red line in the entire suite - and the failure was
`cxHdDerivePath(tNode, "m/")` returning the node UNCHANGED where it owed a throw.

- **The mechanism: the engine ignores ONE trailing delimiter when it counts chunks.** After
  `replace "/" with comma`, the path "m/" is the string "m,", which is ONE item to the engine (as
  "a,," is two). So `the number of items` came back 1, the level loop ran zero times, and the
  empty-level check - which lives INSIDE the loop - was unreachable for exactly the input it named.
  The fix refuses a trailing "/" before the replace, while the separator is still visible; "m/0'/"
  is pinned too, so the refusal holds at depth and not just at the root.
- **Why the headless gate missed it, and this is the transferable part: the gate HAD the vector.**
  `check-script-vectors.py` has tested `throws("cxHdDerivePath", master, "m/")` since phase 4
  landed, and it passed - because `lcs-interp.py` counted items with a bare Python `split()`, which
  sees TWO items in "m,". The model disagreed with the engine about a counting rule, so the
  negative vector tested the model, not the script: the check it proved fires is a check the engine
  never runs. A negative vector is only as good as the semantics under it. The interpreter now
  strips one trailing delimiter before counting AND before item retrieval (`_split_chunks`), the
  same rule for lines.
- **The discipline that made the fix trustworthy: reproduce, then fix.** The interpreter was
  corrected FIRST, and the unmodified parser was run through the gate: it failed on exactly
  `rejects the path 'm/'` and nothing else - the engine's finding, reproduced headlessly. Only then
  was the parser touched, and the gate went green at 213 checks (two new negatives: "m/0'/", "/").
  A fix landed together with the model correction would have proven only that the two changes agree
  with each other.
- The lesson is appended to both copies of `templates/CLAUDE.md` (coinxt's and onionxt's, kept
  byte-identical), the harness gained "a trailing separator is refused", and the audit of every
  other `the number of items` site in the script layer found no second exposure: all the other
  counted strings are internally built lists that never end with the delimiter, which both the
  engine run and the gates confirm.

The fix is now CONFIRMED ON-ENGINE: the same-day re-run (2026-08-10, the suite harness with the
script layer embedded) reported both named checks green - "an empty level is refused" and "a
trailing separator is refused" - and the whole coinxt harness at 207/207. Everything else the
first 2026-08-10 pass touched came back on the side the code assumed, including both phase-2
marshalling bets: the C `int` flag marshals (33 vs 65 came back distinct) and `Boolean` returns
work (`cxVerify` answered both true and false).

**Phase 5, transaction building and signing - BUILT 2026-08-11, EXECUTED headlessly, and
ENGINE-PASSED 2026-08-12; independent-decoder / testnet acceptance is the one bar left.** ABI
untouched (no shim change: this is pure script over the existing primitives).
`src/coinxt.livecodescript` gains 13 public handlers, so the surface is 78 (35 `.lcb` + 43 script):
`cxVarInt`, `cxDerEncode`, `cxBtcOutpoint`, `cxBtcOutput`, `cxBtcSighashLegacy`,
`cxBtcSighashSegwit`, `cxBtcWitness`, `cxBtcTxEncode`, `cxBtcTxid`, `cxEthLegacySighash`,
`cxEthLegacyEncode`, `cxEth1559Sighash`, `cxEth1559Encode`.

- **The KAT is the strongest one this member has.** The Bitcoin case IS the BIP-143 native-P2WPKH
  worked example: a two-input transaction where input 0 is a legacy P2PK spend (SIGHASH_ALL preimage)
  and input 1 is P2WPKH (BIP-143 preimage), so ONE fixture exercises both sighash algorithms, DER
  encoding, witness serialization and the txid. `tools/coin_reference.py` rebuilds the whole signed
  transaction - witness and all - byte for byte from just the two private keys, and asserts it equals
  the BIP's published hex at import. Ethereum adds the EIP-155 specification's own example (its
  published signing hash and r/s) and a self-consistent EIP-1559 typed transaction.
- **The signer moved into the oracle, and it is anchored, not invented.** `coin_reference.py` had
  point math but no ECDSA signing; phase 5 adds RFC 6979 deterministic-k signing, checked at import
  against the SAME pinned vector `coin-kat.py` carries (sk=1, "Satoshi Nakamoto"), so the two files
  cannot disagree about what a signature is. It also adds DER encoding, the sighash builders, varint,
  little-endian writers and the RLP-uint-from-hex path the wei-scale fields need.
- **The integer-width split is the load-bearing design decision.** Bitcoin counters and satoshi
  amounts stay inside exact-integer range (21e6 BTC is 2.1e15 sat, well under 2^53) and cross as
  integers; Ethereum wei-scale fields (value, gasPrice, the 1559 fee caps) routinely exceed 2^53 and
  cross as minimal big-endian HEX, RLP-encoded as byte strings. Passing an ETH value as an integer
  would silently lose precision above 2^53 - a wrong amount that looks right, the exact failure this
  member exists to prevent. The docs and the file header both say which fields are which.
- **The structured-input convention is the RLP layer's, extended.** A transaction's repeated fields
  (inputs, outputs, witness items) cross as comma-separated lists of hex, one item per input/output,
  and every handler that reads one uses the save/set/use/restore itemDelimiter wrapper - including on
  the throw path, the discipline the nine phase-3/4 guards already follow. `scriptCode` is passed
  BARE and this layer adds its length prefix (the double-prefix bug the oracle self-check caught while
  it was being written: BIP-143's `1976a914...88ac` already carries its `0x19`).
- **This layer produces the digest; the app signs it.** `cxSign` (Bitcoin) / `cxSignRecoverable`
  (Ethereum, for the recovery id) are the app's calls on a digest THIS layer built, and CLAUDE.md
  rule 3 stands: confirm the decoded human intent before signing. A blind signer is a footgun.
- **The transaction layer is now EXECUTED headlessly, and it caught a would-be-red engine line the
  day it was wired up (2026-08-11).** Phase 5 shipped oracle-verified: `coin_reference.py` rebuilds the
  BIP-143 worked example byte for byte, but nothing ran it THROUGH THE SCRIPT - the exact gap phase 3
  and phase 4 had closed with `tools/check-script-vectors.py` and phase 5 had not. Closing it (32 new
  executing vectors, 219 -> 251 checks, every one of the 13 handlers driven against the real shim; the
  signatures fed to the encoders are the oracle's own RFC 6979 deterministic (r, s), so no signer is
  needed in the interpreter) failed on the FIRST run, on the flagship transaction. **`cxBtcTxEncode`
  refused to assemble the BIP-143 reference tx at all.** The cause is the trailing-delimiter chunk rule
  this member already learned once (the "m/" fail-open, 2026-08-10): the tx has a trailing EMPTY
  scriptSig (input 1 is segwit, its sig lives in the witness), so the scriptSig list is "<sig0>," -
  which the engine counts as ONE item, not two, because it ignores one trailing delimiter. The strict
  `the number of items of pScriptSigs is not tCount` guard therefore read the list as short and threw
  "the input lists must be parallel" over a perfectly good transaction. This slipped every offline gate
  before because the oracle re-derives the tx from the CORRECT model and the harness assertion had
  never run on an engine - "shipped is not run", again. The fix reads every list BY INDEX (a missing
  entry is an empty scriptSig / empty witness, its correct meaning) and bounds the count guard to "too
  long only", because a short list is INDISTINGUISHABLE from a legit trailing-empty one under the chunk
  rule; sequences stay strict (never empty). It reproduced-then-fixed and is mutation-tested: restoring
  the strict guard makes the whole-transaction vector throw again, exactly as the engine would have.
  The harness's witness-length negative was inverted to match (a too-LONG list is the detectable error;
  a too-short one cannot be rejected).
- Verified: `tools/check-selftest-vectors.py` re-derives all 22 phase-5 harness constants from the
  oracle (65 of 98 re-derived, 33 inputs) and is mutation-tested (a corrupted derived tx, a corrupted
  input, and a wrong pubkey each caught); `tools/check-script-vectors.py` green at 251 checks with the
  phase-5 handlers now EXECUTED (was 219, and the phase-3/4 vectors are unaffected); the suite coverage
  gate holds at 331/349 with every phase-5 handler exercised; the suite selftest is regenerated (coinxt
  fold 43 handlers).
- **THE ENGINE PASS LANDED 2026-08-12 (Windows x64): 230/230, phase 5 included.** The folded harness
  ran the whole coinxt section green on a real engine - "the whole signed transaction matches BIP-143
  byte for byte" on the very path the trailing-empty-scriptSig fix repaired, both new negatives
  ("cxBtcSighashSegwit refuses an empty outputs list", "cxBtcTxEncode refuses a witness list longer
  than the input count") firing as designed, and the EIP-155 / EIP-1559 transactions and hashes exact.
  So the headless-gate finding is now engine-confirmed from both sides: the defect it caught would have
  been red here, and the fix it shipped is green here.

- **THE INDEPENDENT-DECODER BAR IS MET (2026-08-12), and it is the strongest correctness statement
  this member can make short of a testnet broadcast.** `tools/verify-independent-decoder.py` builds a
  FRESH native-P2WPKH transaction - a key, amount, prevout and destination the repo has never pinned,
  so reproducing the BIP-143 example is not enough to pass - end to end through the SHIPPED
  `src/coinxt.livecodescript` (sighash, DER, varint, witness, serialization, via `lcs-interp.py`), and
  hands the resulting bytes to **python-bitcointx** (the maintained python-bitcoinlib fork, a full
  consensus-shaped script interpreter over libsecp256k1). It deserializes them, runs `VerifyScript`
  under `SCRIPT_VERIFY_WITNESS`, and checks the signature against its OWN BIP-143 sighash; a flipped
  signature byte and a +1-satoshi wrong amount are both rejected, so the verdict is not vacuous. This
  is the first time code we did not write has accepted a transaction CoinXT built. It is an ACCEPTANCE
  run, NOT a CI gate: python-bitcointx + coincurve are pip packages the suite does not vendor, so the
  tool SKIPS loudly without them (`--require` turns the skip into a failure on a machine that has
  them). The rationale for keeping it out of `build-all.sh` is the same one the runbook applies to a
  testnet node: an external dependency the gate set cannot assume. **The one bar left is a live
  testnet broadcast**; "broadcastable" stays unclaimed until then, but "an independent decoder accepts
  our bytes" is now true.

- **EXTENDED TO ALL FOUR FAMILIES (2026-08-13).** The 2026-08-12 run proved the claim for one family;
  the shipped surface has four (legacy P2PKH, native P2WPKH, EIP-155, EIP-1559), and an acceptance
  that samples one is exactly the shape of overstatement the gate lessons above exist to prevent.
  `tools/verify-independent-decoder.py` now builds a FRESH transaction in every family. The legacy
  spend signs the pre-BIP-143 preimage (DER by the SCRIPT this time, so both DER producers get an
  external verdict between the two Bitcoin legs) and passes python-bitcointx's `VerifyScript`, with
  a tampered-OUTPUT negative control because the legacy sighash commits to the outputs, not the spent
  amount. The Ethereum pair (chain id 137, wei values above 2^53 so the big-int hex path is genuinely
  exercised, a non-empty 1559 data payload) is accepted by **eth-account** - the recovery library
  web3.py itself uses - which must recover the exact sender address from the script-built bytes, an
  independent RLP decode confirming every field (the empty access list included) and a
  flipped-signature control in each. 31 checks, green on python-bitcointx 1.1.5 + eth-account 0.13.7.
  The Ethereum half SKIPS loudly without eth-account, the same contract as the Bitcoin half, and
  `--require` fails on any skip. A live testnet broadcast remains the one bar left.

**WIF - BUILT 2026-08-15; ENGINE-PROVEN 2026-08-17.** All fourteen WIF checks ran green in the 2026-08-17 engine pass (Windows x86_64, OXT 9.6.3; coinxt 278/278 green),
including the refusal that matters: an xprv is rejected on its payload LENGTH, not its version byte.
The last
designed encoding: `cxWifEncode` / `cxWifDecode` in `src/coinxt.livecodescript`, no shim change, the
surface now 80 public handlers (35 `.lcb` + 45 script). Base58Check over `version || key || optional
0x01 compressed marker`, 0x80 mainnet / 0xEF testnet. The decisions worth knowing before editing it:

- **The key crosses as 64 HEX CHARACTERS, both directions**, unlike the Data keys elsewhere in the
  script layer: WIF is the paste-in / paste-out format, so the key arrives as pasted text and leaves
  as pasteable text (the phase-5 reasoning for txids and scripts). Decode returns an array
  (`seckey` / `network` / `compressed`), the cxSegwitAddressDecode convention. SPEC.md only ever
  NAMED WIF, so both files carry AS BUILT marks for these decisions.
- **Both directions range-check the scalar through `cxSeckeyIsValid`** - the handler whose own .lcb
  comment names "a WIF" as its use case - because the framing alone would happily wrap zero or a
  value at or above the group order into a checksummed, valid-looking WIF of a key no wallet can
  spend from (rule 4's wrong-but-plausible answer). The compressed marker is validated too: a
  34-byte payload whose trailing byte is not 0x01 is refused rather than read as uncompressed,
  since guessing a flag guesses an ADDRESS - compressed and uncompressed keys pay different ones.
- **The vectors are derived, not recalled.** `tools/coin_reference.py` gained `wif_encode` /
  `wif_decode`, and its import self-check anchors the mainnet/uncompressed form of the wiki's
  worked-example key to the wiki's published string, asserts all four network/flag forms are
  distinct and round-trip, and asserts six malformed shapes raise. `check-script-vectors.py` drives
  the SHIPPED script both directions plus eleven refusals (272 checks, floor raised 240 -> 260,
  `cnx_seckey_verify` newly wired into the interpreter's environment mirroring the .lcb split:
  false for -1/-2/-4, throw otherwise); `check-selftest-vectors.py` re-derives the three harness
  strings and holds `kWifBadChecksum` genuinely corrupt. Both gates were mutation-tested in the
  same change: five constant/registration mutations and four script defects (marker check deleted,
  testnet aliased to mainnet, marker dropped on encode, range check deleted), all nine caught.
- **No engine has run these two handlers** - they postdate the 2026-08-10/12 passes, and the README,
  api-reference and the script's section header all say so. The OXT pass owes: the three-argument
  call shape, the boolean flag both ways, the array return, and both refusal paths.

**ABI 5, cnx_memzero - the recorded secret-hygiene fix, SHIPPED 2026-08-16.** ABI 4 -> 5, shim and
`kABIVersion` bumped in the same change, per the rule. `src/coinxt.lcb`'s header had carried the gap
honestly since phase 1: the raw out-buffer this layer allocates was freed WITHOUT being wiped,
because no engine `<builtin>` zeroes a block, with the fix recorded as "a future
`cnx_memzero(ptr, len)` export ... a shim change and therefore an ABI bump, so it is noted here, not
smuggled in." This is that change, made with the bump. The decisions worth knowing:

- **The wipe is vendored, not invented (rule 1).** `cnx_memzero` is a thin status-returning wrap of
  `vendor/memzero.c` - the trezor-crypto routine every in-shim secret already goes through
  (SecureZeroMemory / memset_s / explicit_bzero / a volatile-pointer byte loop, chosen per platform
  at compile time, none of which the compiler may elide the way it can a plain memset before free).
  The firewall contract mirrors the in-buffer convention: NULL+0 is a tolerated no-op, NULL with a
  nonzero length is `CNX_ERR_NULL`, len 0 with a valid pointer succeeds having done nothing.
- **The `.lcb` wipes EVERY out-buffer, not a classified subset.** `sFree` became
  `sWipeFree(ptr, len)` (wipe, free, THEN judge the status, so even the impossible refusal path
  leaks nothing), and `sFinish` routes all three of its paths through it. The audit of the
  `MCMemoryDeallocate` sites found the secret material beyond the known seed path:
  `cxPbkdf2HmacSha512` (the BIP-39 seed), `cxHmacSha512` (the BIP-32 I that splits into a child-key
  tweak and a chaincode), `cxSeckeyTweakAdd` (a child PRIVATE key), `cxEcdh` (a shared secret
  point). Rather than wiping those four and judging the rest harmless, the wipe is UNCONDITIONAL:
  per-site classification fails open when it is wrong and saves one cheap call when it is right.
- **Fixing the free path surfaced a latent leak on it.** Old `sFinish` called a throwing `sToData`
  BETWEEN allocate and free, so an engine refusal to build the result `Data` (unreachable OOM, but
  still a path) would have leaked the block unwiped - for a seed, the exact hole the wipe closes.
  The copy is now inline in `sFinish` and the block is wiped and freed before any throw it raises.
- **cnx_memzero is deliberately NOT public script surface.** No `cx*` wrapper: a script `Data`
  cannot be wiped in place (the honest-limit paragraph stands unchanged in the header, the README
  and the api-reference), so exposing the export would only invite the false belief that it can.
  The suite coverage gate is untouched: no new public handler exists to cover.
- **Verified where this environment can verify.** The wipe contract executes for real on Linux:
  `sh native/build.sh asan` clean with new cases (wipes exactly len - a 0xAA sentinel one past the
  wipe must survive - len 0 a no-op, NULL+0 tolerated, NULL+len refused), and `coin-kat.py` carries
  the same six-check contract, which its `--lib` mode also ran against the committed x86_64-linux
  binary. The `.lcb` call sites are verified statically (the bind diffed against the C signature,
  the gate set green); needs an OXT pass - specifically the first `cx*` call proving `_cnx_memzero`
  binds and `sWipeFree` does not disturb a result. `package-extension.py`'s stale 16-name
  EXPECTED_EXPORTS list was brought up to the full 35 in the same change, because for a cross-built
  DLL that install check is the only missing-export gate in the tree (the freshness gate reads ELF
  only). **That last sentence was true about the list and FALSE about the gate**: the reader under
  it had no opinion about any PE, so the gate it describes did not run. See the correction at the
  end of this section.

**THE WINDOWS DLLs IN THIS CHANGE ARE BELOW THIS MEMBER'S OWN BAR, AND THAT IS RECORDED, NOT
BLURRED (2026-08-16).** coinxt's bar for a bundled Windows binary is EXECUTION: since the
2026-08-12 release run, `release-binaries.yml`'s `kat-windows` job drives the cross-built DLL
through the published vectors on a real Windows runner before it is bundled. This environment has
no Windows runner, so the committed `x86_64-win32` and `x86-win32` DLLs at ABI 5 are MinGW
cross-builds (the exact toolchain-and-recipe rows from `release-binaries.yml`: `CC/NM/STRIP` set to
the `x86_64-w64-mingw32-*` / `i686-w64-mingw32-*` tools, `pack` with the explicit platform id, the
generated `.def` narrowing the PE surface) carrying the THREE STATIC CHECKS of the sodiumxt
precedent instead - the state sodiumxt's 2026-08-11 mingw64 DLL was in before its 2026-08-12
Windows engine proof, and the same checks its 2026-08-15 DLLs carry while awaiting theirs:

1. export-table parity with the Linux build: 35/35 `cnx_*` names byte-identical to the x86_64-linux
   `nm -D` set, zero leaked upstream symbols, in BOTH DLLs;
2. the ABI constant in the disassembly: `cnx_abi_version` at its export RVA disassembles to
   `mov $0x5,%eax; ret` in both;
3. the import table clean: `KERNEL32.dll`, `msvcrt.dll`, `bcrypt.dll` (BCryptGenRandom, the blinding
   entropy source) and nothing else, in both.

Static checks prove well-formed, not working - "shipped is not run" is this repo's most expensive
lesson - so both DLLs are honestly labeled: needs the Windows execution proof. The next
`release-binaries.yml` dispatch supersedes them with `kat-windows`-proven builds, exactly as run
31551536144 (2026-08-12) superseded the earlier cross-builds. The Linux pair is not in that state:
the committed x86_64-linux library passed the full KAT suite including the new memzero contract in
this environment, and the x86-linux build is the same source through the same gcc at `-m32`,
export-parity-checked, with CI executing the committed x86_64 library's vectors on every push.

**THE 2026-08-16 EXPORT CHECK WAS FAIL-OPEN FOR EVERY WINDOWS DLL, WHICH IS THE OPPOSITE OF WHAT ITS
OWN COMMIT MESSAGE CLAIMED (found and fixed 2026-08-16, same day).** Pushed commit `55f9130` states
that `tools/package-extension.py`'s export check "is the only missing-export check an installed DLL
gets", and the comment it added above `EXPECTED_EXPORTS` said the same. The claim about the tree was
right and the claim about the check was **false as shipped**: between that commit and this fix, the
check had no opinion about any PE at all, so on the artifact class it was written to protect it did
not run.

- **The mechanism.** `read_exports` shelled out to `nm`. The same commit added a type-letter filter
  (`len(parts) == 3 and parts[1] != "I"`) because a plain Linux binutils `nm` opens a mingw DLL far
  enough to list its IMPORT thunks (`__imp_BCryptGenRandom` and friends) and nothing else, and the
  old any-line parse had counted those thunks as "the exports" and refused a good DLL for missing
  every `cnx_*` name. The filter fixed that false refusal and created a worse failure: with every
  line filtered out the name set was empty, and the function treated an empty set as the documented
  `None`, "no opinion". `--lib` then printed `exports: not checked` and proceeded.
- **The consequence.** For `src/code/x86_64-win32/coinxt.dll` and `src/code/x86-win32/coinxt.dll`
  there is no second gate: `check-binary-freshness.py` reads ELF and SKIPS both.
(**SUPERSEDED 2026-08-17**: the suite-level `tools/check-binary-freshness.py`
reads PE as well - 43/43 binds resolved, 43/43 shim definitions exported, and
ABI 6 decoded from the export table on both DLLs. The member copy still skips
them; the clause that broke is "there is no second gate". The incident record
above stands as written.) So a MinGW build
  that had genuinely lost `cnx_memzero` (or any of the other 34) would have installed silently and
  failed at bind time on a user's machine, which is the exact outcome the check exists to stop.
- **What made it easy to miss**, and it is worth carrying: the DLL has 35 import thunks AND 35 real
  exports, so no count ever looked wrong, and the identical command on the two Linux `.so` files
  printed a correct "all 35 present" in the same session. A gate that is green on the artifacts you
  happen to look at is not evidence about the artifacts it was written for.
- **What holds now.** `read_exports` dispatches on the container's MAGIC, not on the platform id and
  not on what a tool happens to support. A PE is parsed against the file format with `struct` (DOS
  stub, optional header PE32/PE32+, data directory 0, the section table for RVA to file offset, then
  IMAGE_EXPORT_DIRECTORY's [Ordinal/Name Pointer] table), so no external tool is in the path and a
  host whose binutils lacks the PE targets can no longer make the check evaporate. `objdump -p`
  would have read this tree fine, but it would have rebuilt the same "works until the host's
  binutils is plain" hole one layer down. A PE now yields a real answer or raises `ExportReadError`,
  which `--lib` turns into a refusal; a container that is not ELF, PE or Mach-O is refused outright;
  the one surviving no-opinion path is a Mach-O with no usable `nm`, and it prints a three-line
  WARNING that names the file being installed unchecked instead of a single quiet line.
- **The gate is proven to FAIL, not just to pass** (the standing lesson, applied to the fix itself):
  a copy of the committed x64 DLL with `cnx_memzero` surgically deleted from its export name table
  (name pointer and ordinal entry removed, `NumberOfNames` decremented; `objdump -p` confirms 34
  names and no `cnx_memzero`) is refused with "missing 1 of the 35 cnx_* exports (cnx_memzero)"; a
  copy whose export-directory RVA points into no section is refused as unreadable rather than
  waved through; a copy with the export data directory zeroed is refused as missing all 35; and all
  four committed libraries still pass, the two DLLs now reading "35 present (PE export name table)".

**`sWipeFree` no longer throws, because a belt-and-braces guard must not be able to cost the caller
the real error (2026-08-16, same pass).** ABI 5's `sFinish` wiped and freed the out-buffer BEFORE
throwing the `cnx_*` status, so a wipe refusal on that path would have replaced a diagnostic the
caller can act on ("cxSign: a buffer had the wrong length.") with a reinstall-the-library sentence
naming no handler. Checking that status was the right call - an unchecked status would be the one
silent path in the file - but checking it where it can displace the primary error gives the benefit
straight back. `sWipeFree` now RETURNS the status; `sFinish` appends it in parentheses where there
is already a real error to report (`sWipeNote`, empty on success, so every existing message is
unchanged byte for byte), and throws it alone on the success path where there is nothing to
displace. Discarding a correct result there is deliberate: a library whose wipe refuses is a library
whose output this file has no reason to trust. The "could not build the result data" throw gained
the handler name it was missing, and `docs/api-reference.md`'s error table carries both new forms.
Verified statically (the gate set is green and only `sFinish` calls `sWipeFree`); needs an OXT pass,
which still owes the ABI-5 item above - the first `cx*` call proving `_cnx_memzero` binds - plus the
`String` return of `sWipeNote` concatenating into a throw.

**ABI 6: BIP-340 SCHNORR AND THE BIP-341 TAPROOT TWEAK, over a SECOND vendored library
(2026-08-16).** ABI 5 -> 6, `CNX_ABI_VERSION` and `kABIVersion` bumped in the same change per the
rule. Eight new exports (43 now), five new `.lcb` public handlers plus three length accessors, and
two new script handlers, so the public surface became 90 (43 `.lcb` + 47 script; 94 since the
2026-08-23 BIP-341 script-layer entry below). This is the largest
decision recorded in this file since the entropy correction, because it is not a feature - it is a
change to the rule the project opened with.

**THE RULE CHANGE, IN FULL, BECAUSE IT MUST NOT BE A QUIET EDIT.**

- **What the rule WAS.** Rule 1 of this file: *"Add no cryptography. Wrap trezor-crypto. Every
  scalar multiply, signature, and hash is upstream, audited code. A missing primitive is a new
  vendored file or an upstream request, never a hand-rolled curve op or hash here. There is no
  CoinXT cipher."* SPEC.md section 1 said the same in one line: *"Every curve op and hash is
  trezor-crypto's; CoinXT adds no cipher of its own."* SPEC.md section 2 justified the single
  library on the grounds that trezor-crypto is one MIT, dependency-free, plain-C tree the family's
  FFI pattern can vendor whole: one library, one audit surface, one pin.
- **What the rule IS now.** *Add no cryptography. Wrap an audited upstream.* CoinXT implements no
  cryptography of its own and composes **two** vendored libraries, which do not overlap:
  trezor-crypto keeps every hash, ECDSA, recoverable ECDSA, recovery, ECDH and the two BIP-32 curve
  steps; **upstream bitcoin-core/secp256k1** owns BIP-340 Schnorr, x-only public keys and the
  BIP-341 tweak, and is reached only through the five `cnx_` entry points that need it.
- **Why.** trezor-crypto's plain-C tree has **no BIP-340 implementation at all**. It reaches
  Schnorr only through `zkp_bip340.c`, which requires the bundled `secp256k1-zkp` and that
  library's own build system. So the real choice was: a second audited library, or write BIP-340
  in this repository. **Hand-rolling a signature scheme is precisely what rule 1 exists to
  prevent**, so the second library is the rule being OBEYED rather than waived - which is the whole
  argument, and the reason this is a rule change and not a rule break. Upstream (not the zkp fork)
  because its in-tree `schnorrsig` and `extrakeys` modules are everything BIP-340 and single-key
  BIP-341 need, the fork's extra value is irrelevant here, and upstream is what Bitcoin Core itself
  ships and audits: the least surprising possible answer to "whose Schnorr is this".
- **What the new audit surface is.** 58 vendored files, 3.13 MB of source, of which one generated
  table is 2.30 MB; three translation units compile. Only two upstream modules are enabled
  (`ecdh`, `recovery`, `musig`, `ellswift`, `silentpayments` are neither vendored nor compiled).
  One long-lived object appears in a shim whose architecture note says it holds none: a file-static
  `secp256k1_context`. One entry point stops being a pure function of its inputs
  (`cnx_schnorr_sign` with an absent aux). Licensing gets SIMPLER: libsecp256k1 is MIT throughout
  with no third-party sub-licenses, so it is one row in the suite `LICENSE` against
  trezor-crypto's six exceptions. All of it is written up in `native/vendor/VENDOR.md`, SPEC.md
  section 2.1 and `THIRD-PARTY-LICENSES.md`.

The rest is the engineering, and the decisions worth knowing before editing any of it:

- **The pin is a COMMIT, `439278a649d3099d62dde966a76dc04aaca7ccb3`, and that was weighed.** It is
  release `v0.8.0` plus twelve commits: eleven touch only tests, and the twelfth (`3d4340d`)
  hardens `src/scratch_impl.h`, which IS compiled here. So for the vendored subset the pin is "the
  last release plus one hardening fix, minus nothing" - a better place to stand than the tag, and
  small enough to state in a sentence rather than hand-wave. A bare commit hash is also this
  member's precedent; the trezor-crypto pin is one. Verified the strong way, not the plausible way:
  every file was extracted with `git cat-file blob <pin>:<path>` from a real clone (so it arrived
  in an object git had already content-hash-verified), and each installed file's blob id was then
  re-derived with `git hash-object` and compared against the id the commit's tree lists. 58 of 58.
- **THE 2.4 MB TABLE IS VENDORED VERBATIM, AND THE BINARY IS SHRUNK BY A DEFINE INSTEAD.** These
  are two separate decisions and conflating them is the mistake to avoid.
  `src/precomputed_ecmult.c` is an `#if` ladder over `ECMULT_WINDOW_SIZE`, so a smaller window does
  NOT shrink the source - the same 2.4 MB file compiles for any window in [2..15].
  - *Source:* vendored verbatim (option (a)). Generating it at build time (option (b)) would keep
    the repository smaller and would add a **code-generation step to a build that has none**:
    `native/build.sh` is POSIX sh and one compiler invocation, and its whole virtue is that a cross
    build is `CC=x86_64-w64-mingw32-gcc sh native/build.sh pack x86_64-win32`. A generator must be
    built for the HOST and run before the library is built for the TARGET, which puts a second
    toolchain concept in that script, breaks on any host that cannot execute its own output, and -
    the part that settles it - produces a table **nothing in this tree can hash-pin**.
    `MANIFEST.sha256` proves every vendored byte is upstream's; a generated table is proven by
    nothing but the fact that a generator ran. For a money library, "it came from the pinned commit
    and here is its SHA-256" is worth 2.4 MB of history.
  - *Binary:* `ECMULT_WINDOW_SIZE=12` rather than upstream's 15, which is a documented,
    range-checked compile-time knob and not a patch. The table is `2^(w-2) * 64 * 2` bytes, so 15
    costs **1,048,576 bytes of read-only data in every shipped binary** and this member commits
    four of them. Measured here (gcc 13.3 -O2, x86_64, min of 7 runs of 20,000 BIP-340
    verifications): w=15 33.26 us / 1,048,576 B; **w=12 33.40 us / 131,072 B**; w=10 35.02 us /
    32,768 B; w=8 35.33 us / 8,192 B; w=6 37.64 us / 2,048 B. 12 removes 87.5% of the table for
    0.4%, which is inside the run-to-run spread - no measurable verification cost at all. Going
    further DOES cost measurable time (5% at w=10) to save a further 96 kB, so 12 is where the free
    part ends. The absolute numbers are one machine's; the ranking transfers.
  - *What it actually cost, per platform, in committed bytes:* x86_64-linux 170,216 -> 481,536
    (+311,320, +183%); x86-linux 144,780 -> 398,744 (+253,964, +175%); x86_64-win32 122,114 ->
    453,273 (+331,159, +271%); x86-win32 125,920 -> 399,332 (+273,412, +217%). Most of that is
    libsecp256k1's CODE (~180 kB), not its tables: the ecmult table is 128 kB and the comb table
    22 kB. At upstream's default window each of those four would have been about 1 MB larger.
- **`precomputed_ecmult_gen.c` is left at upstream's default (11, 6) comb, deliberately.** Unlike
  the file above it is generated FOR one configuration and carries no `#if` ladder, so changing
  `COMB_BLOCKS`/`COMB_TEETH` would require regenerating it - i.e. a locally generated vendored
  file, which the vendor rules forbid. It is 22 kB and signing is unaffected by the ecmult window
  anyway.
- **A REAL BASENAME COLLISION, found while wiring the build.** `vendor/secp256k1.c` is
  trezor-crypto's curve-parameter file and `vendor/libsecp256k1/src/secp256k1.c` is upstream's
  entire library. `build.sh pack` derived each object path from `basename "$src" .c`, so the second
  would have silently overwritten the first and linked a library missing trezor's curve constants.
  Upstream's objects carry a `secp_` prefix now. The same shape would bite anything else that maps
  sources to objects by basename; two vendored trees can collide where one never could.
- **Warnings are scoped, which is why the build compiles two groups.** Upstream's units get
  `-Wall -Wextra -Wno-unused-function`, which is upstream's OWN flag set (it compiles as one unit
  and leaves the disabled modules' helpers unused, so the warning fires about fifteen times on a
  perfectly good build). The `-Wno-` must not reach `native/coinxt.c`, and no single `cc` line can
  scope a flag per file. `secp_cppflags` (the module defines, the window size and
  `SECP256K1_NO_API_VISIBILITY_ATTRIBUTES`) DOES reach every unit, because our shim includes the
  same headers and both sides must agree about them.
- **`SECP256K1_NO_API_VISIBILITY_ATTRIBUTES` is the flag that makes MinGW behave.** Without it
  upstream's `secp256k1.c` gets `__declspec(dllexport)` on every entry point and our shim sees
  `__declspec(dllimport)` on the same declarations - a DLL advertising, and trying to import, a
  libsecp256k1 surface that is nobody's business but ours. Upstream documents this exact define for
  "a static library which is linked into a shared library, and the latter should not re-export the
  libsecp256k1 API". `src/coinxt.map` and the generated `.def` still narrow the surface; this just
  settles it a layer earlier. Measured: zero `secp256k1_*` symbols in any of the four committed
  libraries, and the `cnx_*` export set is 43/43 identical across all four.
- **One `secp256k1_context`, static, created on first use, never freed - and that is correct.** It
  is one small allocation reachable from a global for the life of the process, so ASan's leak
  checker does not report it (verified, not assumed: LSan is active in the asan lane and reports an
  UNREACHABLE malloc in the same run). CoinXT has no shutdown call and by design never will, and
  freeing it would open a use-after-free window for nothing. Threading is sound for the same reason
  the rest of this member is: only the engine's script thread calls in. Upstream states the rule
  precisely - a constructed context is safe to share, but `secp256k1_context_randomize` needs
  exclusive access - so a multi-threaded host would need a lock around `cnx_secp_ready()` and
  nothing else.
- **The context is RE-RANDOMIZED before every secret-key operation, and fails closed.** Upstream:
  "The primary purpose of context objects is to store randomization data ... This protection is
  only effective if the context is randomized after its creation", and re-randomizing "before every
  few computations involving secret keys is recommended as a defense-in-depth measure" - taken at
  its strongest reading here. It costs one OS entropy draw plus a blinding update per secret
  operation, which is the same order as what trezor-crypto already spends on this member's ECDSA
  path. Public-only calls (`cnx_schnorr_verify`, `cnx_taproot_tweak_pubkey`) deliberately do NOT
  re-randomize: there is no secret scalar to blind, so spending the draw would buy nothing. If
  entropy is unavailable the call returns `CNX_ERR_ENTROPY` and a context that could not be
  randomized is destroyed rather than kept. **The easy misreading, stated in the shim too:**
  skipping the re-randomization is not the same as needing no entropy - CREATING the context
  randomizes it once, so the first call of any kind needs the OS source. That is not new here;
  `cnx_ecdsa_verify` has needed entropy on every call since phase 2, because trezor-crypto
  randomizes the projective Z coordinate on every scalar multiply.
- **UPSTREAM'S DEFAULT ILLEGAL-ARGUMENT CALLBACK IS LEFT IN PLACE, and that is the safer
  direction.** It aborts the process on an API misuse. Installing a returning callback looks safer
  and is not: upstream's own header says that if the callback returns, "the return value and output
  arguments of the API function call are undefined", and an undefined return in a money library is
  strictly worse than a loud stop. So the firewall guarantees the callback is unreachable instead -
  every pointer upstream is handed is non-NULL and every length is checked first, the same contract
  `cnx_pubkey_ok` already enforces for trezor-crypto's unlengthed pubkey parser. Same shape as the
  `abort()` in `random_buffer`, same pre-flight in front of it.
- **AUX_RAND: absent means FRESH, never all-zero. This is the one non-deterministic entry point in
  the shim and SPEC.md section 4 now says so.** Upstream accepts NULL and treats it as an all-zero
  aux while warning that real randomness is recommended. CoinXT does not take that default, because
  a library that silently picks the least-protected option when the caller says nothing is the
  fail-open shape this member exists to refuse. `auxlen == 32` uses those bytes and the signature is
  a pure function of (key, message, aux) - which is what the BIP-340 vectors pin; `auxlen == 0`
  draws 32 fresh OS bytes and fails closed if it cannot; anything else is `CNX_ERR_BADLEN`. It
  cannot weaken anything: BIP-340's nonce is `hash(aux XOR key, P, msg)`, deterministic in
  (key, message) even at aux = 0, so a bad aux draw can never repeat a nonce across messages -
  randomness there only ADDS protection. **The KAT asserts BOTH directions**, because "it was
  quietly passed through as NULL" and "it drew randomness" otherwise produce identical green runs:
  two absent-aux signatures must DIFFER, both must verify, and neither may equal the zero-aux one.
- **SIGNING TAKES A 32-BYTE MESSAGE; VERIFICATION TAKES ANY LENGTH.** That asymmetry is deliberate
  and each half has its own reason. Signing is narrow because rule 3 says sign only the exact digest
  the app hands you (`cnx_ecdsa_sign` obeys the same rule, and BIP-341 signs a 32-byte sighash).
  Verification is wide because BIP-340 has admitted arbitrary-length messages since 2022 and its own
  vector file carries 0-, 1-, 17- and 100-byte cases: a verifier that demanded 32 would REJECT VALID
  SIGNATURES, which is not caution, it is a wrong answer. The four variable-length vectors are
  therefore verified and not re-signed, which is a scope decision and is recorded as one.
- **AN X-ONLY KEY THAT IS NOT ON THE CURVE IS "false" WHEN VERIFYING AND AN ERROR WHEN TWEAKING**,
  and BIP-340's own vector file decides the first half: cases 5 ("public key not on the curve") and
  14 ("not a valid X coordinate ... exceeds the field size") both list their expected verification
  result as FALSE, so a shim returning `CNX_ERR_BADKEY` there would make `cxSchnorrVerify` throw
  where the specification says answer no. Tweaking is the other way round: the caller is ASSERTING
  "this is my internal key", not asking a yes/no question, so an unparseable key is
  `CNX_ERR_BADKEY`. Note this differs from `cnx_ecdsa_verify`'s treatment of a bad pubkey, and the
  difference is real rather than sloppy: there the rejected shapes are wrong LENGTHS and wrong
  PREFIX bytes, which are structural and must be refused before the overread; here every 32-byte
  string is structurally a candidate and only the curve can say otherwise.
- **THE MERKLE ROOT IS CARRIED BY LENGTH, AND ABSENT IS NOT ZERO. THIS IS A CONSENSUS RULE.**
  BIP-341 tweaks with `hash_TapTweak(bytes(P) || merkle_root)` where `merkle_root` is the EMPTY BYTE
  STRING for a key-path-only output - the common case. Hashing 32 zero bytes instead hashes 64 bytes
  where the spec hashes 32: a different tweak, a different output key, a different address, and
  coins nobody can spend. So `rootlen == 0` means key-path-only and `rootlen == 32` means a real
  root, with no sentinel VALUE anywhere in the stack to get wrong, and an all-zero 32-byte root is
  treated as the legal (if useless) script commitment it actually is. Asserted at three layers -
  the ASan self-test, `coin-kat.py` and `check-script-vectors.py` all require the two to produce
  DIFFERENT output keys - because if they ever agreed, every key-path-only address this library
  produced would be wrong and would still look like an address.
- **The parity travels IN THE OUTPUT BUFFER, not in an `int *` out-parameter.**
  `cnx_taproot_tweak_pubkey` writes 33 bytes: the x-only output key then one parity byte. That is
  this member's existing convention (`cnx_ecdsa_sign_recoverable` writes 64 bytes of signature plus
  a recovery id), and it keeps the binding on shapes an engine has already marshalled: **no `.lcb`
  in this entire suite has ever declared a scalar `out` parameter against our own C** (measured: the
  only `out` parameters anywhere are `Data`, `String` and `Pointer`, all against engine
  `<builtin>`s), and a money library is the wrong place to discover headlessly whether one works.
  The script layer's `cxTaprootTweak` splits the record into a named array, which is where the
  ergonomics belong.
- **The optional arguments cross as an EMPTY `Data`, not an `optional Pointer`.** CLAUDE.md's FFI
  law names `optional Pointer` for exactly this case ("an absent BIP-340 aux_rand"), and it is
  legal LCB - but it has never been exercised on an engine in this suite, whereas an empty `Data`
  through a plain `Pointer` slot was settled on 2026-08-08 by `cxKeccak256("")`, and every shim
  entry already accepts NULL when its length is 0. So "absent" is spelled the way this family has
  already proven, and the shim reads the LENGTH.
- **`cxBtcAddressP2TR` IS UNCHANGED AND STAYS UNCHANGED. The tweak is a NEW handler.** REMAINING-WORK
  A.10 and the old handler comment recorded that it encodes a pre-tweaked key and cannot compute
  the BIP-341 tweak. The tweak exists now, and the handler still does not apply it, because making
  it apply one would silently turn every existing CORRECT call - an app that pre-tweaked elsewhere -
  into a DOUBLE tweak: a different, valid-looking, permanently unspendable address, undetectable by
  the handler (both arguments are 32 bytes) and unnoticeable by the caller. `cxBtcAddressP2TR`
  therefore keeps its meaning forever, and `cxBtcAddressP2TRFromInternal(pInternalKey, pMerkleRoot)`
  is the new handler that does the whole BIP-341 path. It is a separate NAME rather than an optional
  second argument for a reason worth carrying: **an absent xTalk parameter is indistinguishable from
  an empty one**, so an optional `pMerkleRoot` could not tell "encode this output key" from "tweak
  this internal key with no script tree" - and empty is the COMMON case, so the ambiguity would land
  on the majority of calls. `check-script-vectors.py` asserts the two handlers DISAGREE on the same
  32 bytes, so a future edit cannot quietly make the old one tweak.
- **THE VECTORS ARE THE PUBLISHED FILES, IN FULL, AND TEN OF THEM ARE NEGATIVE.** BIP-340's official
  `test-vectors.csv` (all 19 cases, transcribed in `tools/coin-kat.py` with its source URL) and
  BIP-341's `wallet-test-vectors.json` (all 7 `scriptPubKey` cases and all 7 `keyPathSpending`
  inputs). Nothing is generated by the library under test - the standing lesson. The negatives are
  the point: a public key off the curve, `has_even_y(R)` false, a negated message, a negated s, two
  infinity cases, an x that is not on the curve, r equal to the field size, s equal to the group
  order, and a public key past the field size. The BIP-341 half walks private key -> internal x-only
  key -> tweaked private key -> **the 64-byte witness signature the specification publishes**, which
  is the strongest single vector this member has: a defect anywhere in that chain is a byte
  difference against bytes Bitcoin's own specification prints. (The witness signatures reproduce
  with `aux_rand` = 32 zero bytes, which is what the vector generator used; that is asserted rather
  than assumed, since a wrong aux gives a different but still-valid signature and a harness that
  only checked "it verifies" would not notice.)
- **The two vendored libraries are made to answer the same question once, on purpose.** BIP-341's
  published `tweak` column would otherwise be transcribed and never read - the exact overstatement
  shape this file has been bitten by. So for each `scriptPubKey` vector, trezor-crypto's
  `cnx_pubkey_tweak_add` is handed `0x02 || internal` and the published tweak, and must land on the
  point upstream's `cnx_taproot_tweak_pubkey` landed on: X byte for byte, with a compressed prefix
  that agrees with our parity byte. If the two ever disagreed, one of them would be computing a
  different curve.
- **The oracle got a BIP-340/341 model too** (`tools/coin_reference.py`), because
  `check-selftest-vectors.py` must re-derive the harness's constants from something that is not the
  library under test. It is the BIPs' own reference pseudocode written longhand over the affine
  curve model already in that file, and its import self-check anchors it to the published vectors -
  including two of the NEGATIVE ones, so the oracle is known to say no as well as yes.
- **A MUTATION SURVIVED, AND THE HONEST ANSWER WAS THAT THE GATE WAS RIGHT AND THE CHECK WAS
  WRONG.** Four defects were reconstructed in the shipped script and run through
  `check-script-vectors.py`: hashing 32 zero bytes for an absent merkle root, dropping the tweak in
  `cxBtcAddressP2TRFromInternal`, and slicing the 33-byte record off by one were all CAUGHT.
  Deleting `cxTaprootTweak`'s merkle-root length guard was NOT - and reconstructing it faithfully
  (the standing rule: suspect the probe first, but CHECK) showed why. The shim refuses a 31-byte
  root too, with `CNX_ERR_BADLEN`, so the handler throws either way and a `throws(...) is true`
  assertion cannot tell the two apart. **The guard is not a safety boundary; the shim is.** What
  the guard actually buys is a message that names the handler and the argument instead of a generic
  "a buffer had the wrong length", so that is now what is asserted (`throw_text`, and the mutation
  is caught). The transferable part: when a defence-in-depth check sits above an independent one
  that already refuses the same input, "it threw" tests the layer below it. Assert the thing the
  upper layer is actually for.
- Verified: `sh native/build.sh asan` clean over the whole new surface (the new code is where the
  fixed-size stack buffers are - a 64-byte tagged-hash message that is 32 or 64 bytes long, a
  32-byte aux staging buffer, and a 33-byte record whose last byte is written separately from the 32
  the library serializes); `tools/coin-kat.py` green with 19 BIP-340 vectors, 14 BIP-341 vectors and
  18 new fail-closed guards, and mutation-tested (a flipped signature byte, a flipped tweaked
  seckey, a flipped published tweak, and an inverted expected verdict, all caught);
  `tools/check-script-vectors.py` green at 290 checks (was 272) with the Taproot script handlers
  EXECUTED against the published wallet vectors; `tools/check-selftest-vectors.py` green at 78 of
  120 constants re-derived and mutation-tested (five, all caught); the suite coverage gate at 90/90
  for coinxt; all four committed binaries rebuilt at ABI 6 with 43 exports each and both manifests
  refreshed. **ENGINE-PROVEN 2026-08-17** - the 2026-08-17 engine pass (Windows x86_64, OXT 9.6.3; coinxt 278/278 green). Every question this
  entry listed as owed came back answered: `cxSchnorrSign`'s three-argument shape marshals; an EMPTY
  `Data` reaches the shim as length 0 in the aux slot (`an absent aux gives two DIFFERENT signatures`,
  and both verify) and in the merkle-root slot (`an EMPTY merkle root is not a 32-zero root`) - so the
  OPTIONAL-argument case, never before proven, now is; `cxSchnorrVerify` answered Boolean both ways,
  including the distinction the design turns on (a key that is not on the curve answers FALSE, while a
  33-byte key is refused as a LENGTH error - a caller bug, not a verdict); and `cxTaprootTweak`'s array
  return read back by name. `cxBtcAddressP2TR` confirmed still NOT tweaking, which is the deliberate
  non-change that keeps every existing correct call spendable.

**THE WINDOWS DLLs IN THIS CHANGE ARE AGAIN BELOW THIS MEMBER'S OWN BAR, RECORDED THE SAME WAY
(2026-08-16).** The precedent set by the ABI-5 change applies verbatim: this environment has no
Windows runner, so the committed `x86_64-win32` and `x86-win32` DLLs at ABI 6 are MinGW cross-builds
(the exact toolchain-and-recipe rows from `release-binaries.yml`) carrying the three static checks
instead of the execution proof:

1. export-table parity with the Linux build: 43/43 `cnx_*` names byte-identical to the x86_64-linux
   `nm -D` set, zero leaked symbols (in particular zero `secp256k1_*`), in BOTH DLLs;
2. the ABI constant in the disassembly: `cnx_abi_version` at its export RVA disassembles to
   `mov $0x6,%eax; ret` (`b8 06 00 00 00 c3`) in both;
3. the import table clean: `KERNEL32.dll`, `msvcrt.dll`, `bcrypt.dll` and nothing else, in both -
   libsecp256k1 adds no new import.

Static checks prove well-formed, not working - "shipped is not run" is this repo's most expensive
lesson - so both DLLs are honestly labeled: **needs the Windows execution proof.** The next
`release-binaries.yml` dispatch supersedes them with `kat-windows`-proven builds, exactly as run
31551536144 (2026-08-12) superseded the earlier cross-builds. The Linux pair is not in that state:
the committed x86_64-linux library passed the full KAT suite including all 33 new published vectors
in this environment (`coin-kat.py --check --lib src/code/x86_64-linux/coinxt.so`), and the x86-linux
build is the same source through the same gcc at `-m32`, export-parity-checked.

**BIP-341 SIGHASH + SCRIPT-PATH SPENDING, PURE SCRIPT OVER THE ABI 6 SURFACE (2026-08-23).** The
two gaps ABI 6's entry recorded ("no SigMsg builder, no script-path machinery") closed as four
public script handlers - `cxBtcSighashTaproot`, `cxTapLeafHash`, `cxTapBranchHash`,
`cxTapControlBlock` - plus three private helpers (`cxTapTagged` and the two Inner bodies behind
the house itemDelimiter-pinning wrapper pattern). No shim change, no ABI bump, no binary touched;
the public surface is 94 (43 `.lcb` + 51 script). Three recorded constraints are honored, not
revisited: `cxBtcAddressP2TR` is byte-for-byte unchanged and still does not tweak; the builder is
a BUILDER and never signs (it returns the 32-byte digest for `cxSchnorrSign` + the tweaked key,
the same split every sighash handler here keeps); and the segwit builder's SIGHASH_ALL-only
refusal said the variants would need their own published vectors before they could exist - the
taproot builder ships the FULL type set (0, 1, 2, 3, 0x81, 0x82, 0x83; 0x80 alone refused;
SINGLE past the last output refused, invalid under BIP-341) with every one pinned to a
bitcoin/bips keyPathSpending vector. Bounds, stated where a planner will meet them: no
OP_CODESEPARATOR (the tapleaf extension always writes position 0xffffffff and the doc says a
script that uses it needs a builder this layer does not have), no annex, leaf scripts stay under
253 bytes, and tree ASSEMBLY above one fold is the app's loop over `cxTapBranchHash`.

The verification stack is the phase-5 pattern one more time. `tools/coin_reference.py` gained
`tap_leaf_hash` / `tap_branch_hash` / `btc_sighash_taproot` and an import-time
`_bip341_sighash_self_check` anchored to the published wallet vectors - which fired on its first
run, because the first HAND transcription of the raw tx was corrupt: the never-from-memory rule
caught again, so the fixture was regenerated mechanically from the fetched JSON.
`tools/check-script-vectors.py` drives the real `.livecodescript` through the interpreter against
a mechanically transcribed `TAPROOT_FIXTURE`: all seven keyPathSpending sighashes, all six trees
(leaf lists and roots via the script's own fold), twelve control blocks, a script-path
oracle cross-check and eight refusals - 340 checks, floor raised 260 -> 300.

**The harness pins were WRONG on first write, and the gate caught them before any engine could.**
`stRunTaproot341`'s two synthetic sighash constants were first derived with the txid UN-reversed
(the outpoint convention `cxBtcOutpoint` exists to get right), and
`check-selftest-vectors.py`'s re-derivation refused them - the exact drift it was built to
notice, doing its job on the day the constants landed. The corrected pins agree with the model
AND with the shipped script driven through the interpreter on the harness's exact call, checked
both ways before the fix was accepted. Everything in this entry ran green on-engine on
**2026-08-24** (Windows x86_64, OXT 9.6.3): coinxt folded at **290/290** in the suite paste's
2373/0/3, the 12-check stRunTaproot341 section included - both sighash paths, the 0xfa leaf,
the sorted fold, the control block, and every refusal. The rest of the entry stands as the
pre-engine record.

**The same-day adversarial review found no real defect and two genuine spec edges, both now
refused.** The reviewer independently re-fetched the BIP text and the published vector file,
re-diffed the whole TAPROOT_FIXTURE against it (all match), and drove the shipped script through
the interpreter on the harness's exact single-input calls - which also closed the one shape the
9-input fixture never exercises, a single-item comma list. What it caught: leaf version 0x50 is
EVEN but reserved (BIP-341 excludes it because a witness element starting 0x50 is read as the
annex), and a control block caps at 128 path nodes - both were accepted, both now throw, with
driver refusal checks pinning each (the 0x50 refusal in the model too; the model builds no
control blocks, so the path cap is the script's alone). It also caught the gate
comments calling the published two-leaf tree "scriptPubKey vector 6" when the file's own 0-based
convention makes it vector 3 - a comment-only error, but the same one-number-two-conventions
shape as the 245-vs-244 lesson above, so it is recorded rather than just fixed.

### 2026-08-31 - the WALLET, and the third file this member can execute headlessly

`examples/coin-wallet.livecodescript` is a full Electrum-class Bitcoin wallet in one
paste-and-run stack, and `examples/wallet-core.livecodescript` is the pure calculator layer it
is built out of. `docs/wallet.md` is the reader's document; this entry records the decisions a
maintainer needs and would otherwise have to re-derive.

**THE SPLIT IS WHAT MAKES IT CHECKABLE, and it is the same split this member already lives by.**
CoinXT is a calculator and the app owns custody (rule 2); `wallet-core` is a calculator and
`coin-wallet` owns custody, the window, the file and the network. The engine has NO
script-level `local`, reads no `item` or `line` chunk, touches no control and opens nothing -
so `tools/check-wallet-vectors.py` can drive the SHIPPED bytes of it through `lcs-interp.py`
against `tools/wallet_reference.py` with the real shim signing - complete signed transactions on
all five spend paths, compared byte for byte. (Run it for the count. A number written here would
be true the day it was typed and quietly wrong afterwards, which is this tree's own recorded
failure mode for hand-copied figures.) That is the third
file in this member the shipped-is-not-run rule no longer applies to, after `src/coinxt.livecodescript`
and `tests/coin-selftest.livecodescript`.

**NOT READING `item`/`line` AT ALL IS STRONGER THAN GUARDING THEM.** This file records nine
handlers that a hostile `itemDelimiter` turned into wrong ANSWERS - a valid seed phrase
reported invalid, an address built from the wrong bytes - and the answer there was a
save/set/use/restore wrapper around each. The wrapper is correct and was the only option for
code that already existed. `wallet-core` was written afterwards, so it takes the other option:
lists are ARRAYS keyed 1..n, and the two places that must read a delimited string
(`cwSplitAt`, and the app's `waField`/`waField2`) scan for the separator by hand. There is no
delimiter dependency to guard.

**THE VECTOR GATE FOUND A REAL BUG ON ITS FIRST RUN, and it was this tree's own recorded trap.**
`cwParsePath` ACCEPTED `"m/84'/"`. The engine ignores one trailing delimiter when it counts
chunks, so a split-then-check loop never sees the empty last level: the path parsed as a
perfectly good one-level path. `cxHdDerivePath` carries an explicit refusal for exactly this and
the note explaining why; the wallet layer had to learn it again. It refuses before splitting now.

**IT ALSO FOUND A BUG IN ITSELF, which is the more useful half.** `"Xpub".replace("Pub", "Prv")`
is `"Xpub"` - the lowercase `p` - so three private-key version rows were compared against the
public constants and reported a defect in the script that was a defect in the gate. Suspect the
probe first; the names are spelled out now.

**TWO IMPLEMENTATIONS DISAGREEING IS NOT THE SAME AS ONE BEING WRONG.** The dust thresholds
differed between the script and the oracle, and BOTH were wrong: each had a hand-written
per-type spend size. Core's `GetDustThreshold` branches on ONE question - is the scriptPubKey a
witness program? - and the distinction it does NOT draw is the tempting one, because a
P2SH-wrapped SegWit output has a P2SH scriptPubKey and therefore costs the legacy 148 even
though spending it really does use a witness. Both now derive 546/540/330/294 from Core's own
branch instead of listing them.

**THE QR ENCODER IS THE ONE PIECE WITH NO PUBLISHED VECTOR TO PIN IT TO**, so it was checked
module-for-module against an independent encoder over 261 payloads spanning versions 1 to 15.
Three real defects came out of that, and all three produce a symbol whose DATA is perfect and
which no scanner can read: the format bits placed LSB-first (the natural spelling of the same
integer), one format module never written at all (an `i < 8` that should be `i < 7`), and the
masks scored with the format area already filled in. The last one is a genuine ambiguity in the
standard rather than a mistake - it says to evaluate the symbol and does not say whether the
format information is in it yet - and the two readings pick different masks on small versions,
so the choice is now written down in the code beside the reason.

**THE NETWORK'S SHAPE IS FORCED, NOT CHOSEN.** HTTPS over Tor is impossible in this engine: an
open socket cannot be upgraded to TLS, and `open secure socket` connects TLS directly to a host
so it cannot do a SOCKS handshake first. So the private transports are a `.onion` Esplora mirror
over plain HTTP and a `.onion` Electrum server over plain TCP, both through OnionXT's SOCKS
client, where the circuit IS the encryption. The clearnet transport uses the engine's own
`load URL` and says on screen what that costs, because this suite has never measured what the
engine does about TLS certificates. The stack defines the three engine socket messages itself
and dispatches to OnionXT's named functions, with `sync-demo-embeds.py`'s `DROP_HANDLERS` keyed
by (app, provider) pair so both halves are asserted.

**THE GATE WAS GREEN AND THE CODE WAS WRONG, IN A WAY THE GATE COULD NOT SEE.** An adversarial
read-through, run against the shipped files rather than against the design, found two defects of
one shape and they are the most important thing in this entry. `the caseSensitive` defaults to
FALSE on OXT, so `is` and `offset()` are case-INSENSITIVE; `tools/lcs-interp.py` models both
case-SENSITIVELY and names the first as its one declared divergence. Every one of the 414 checks
was therefore running under a comparison rule the engine does not have. Under the engine's rule:
`cwDescCharPos` looked a character up in Core's descriptor alphabet with `offset()`, and that
alphabet carries `abcdefgh` at 0-based 18 and `ABCDEFGH` at 82, so the lookup returned the wrong
twin and **every descriptor this wallet exported carried a bad checksum**; and `cwXKeyVersion`
told the stems `"z"` (BIP-84 single-sig) and `"Z"` (BIP-48 multisig) apart with `is`, so **a
multisig account key was serialized with the single-signature version** and a genuine `Zpub`
pasted back could never be decoded. This member's own header calls the first of those "the single
most dangerous line of this whole file" and ships `cxCharIndex` for it; the wallet layer had to
learn it again, which is why `cwCharIndex` and `cwSameBytes` now exist here.

**The fix that matters is not either patch - it is the tier.** `check-wallet-vectors.py` now runs
the WHOLE vector set a second time with `is` and `offset()` folded to the engine's default and
requires the same answers, and a mutation check proves the folded model still changes what it is
supposed to change. That turns "did anybody remember to think about case?" into a question the
build asks on every push. What it does NOT fold is `contains`, `begins with`, `ends with` and
`sort`, which the engine also folds; those live inside the interpreter's expression parser rather
than behind a module-level name, and this layer uses none of them on case-significant data. When
one lands on an address, that is a fourth tier and not a quiet widening of this one.

**THE SAME READ-THROUGH FOUND FOUR MORE THINGS, AND THEY GROUP.** None was
visible to any gate, and each is a class worth carrying rather than a line worth
patching.

*Custody promised more than it delivered, in four places at once.* `cwAddressAt`
puts the derived private key into every address record, so `sWaAddresses` is
2 x kWaPrefill spendable keys - more key material than the three variables
`closeStack` was carefully clearing, and its comment said the seed did not
outlive the window. A wallet file never carries `sWaAccountXprv`, so loading
somebody's watch-only file left the PREVIOUS wallet's private half in place and
`waAccountNode` prefers the private half: the result showed their xpub, derived
our addresses, and would sign. Choosing watch-only or an imported key never
cleared the mnemonic, so the file a person made for a wallet the status line had
just called unable to sign carried their real seed phrase. And the file password
stayed rendered on the Settings screen beside the path it unlocks. The through
line is that each was a place where the code's own comment or its own status
line was a claim about state that nothing enforced; the fixes make the state
match the claim, and `waSerializeWallet` now writes a secret only for the kind
that owns one, so even a future leak cannot reach the file.

*Two of the three transports agreed and the third quietly did nothing.* Esplora
takes a transaction by POSTing it; `load URL` does a GET and carries no body.
The clearnet branch built the URL, assigned the raw transaction to a local, and
never read it again - and the reply, Esplora's own 405 page, came back through
`waNetApply` as "Broadcast." That transport now refuses the operation by name.
Beside it: `load URL` cannot be cancelled, so after a deadline or a Stop the
abandoned request is still in flight, and `waUrlDone` correlated replies by
"is anything in flight?" alone - so one address's coins were recorded against
another's. The Tor transports got correlation free from the stream handle; this
one now carries the URL it issued and checks it.

*A checkbox nothing drives can never be ticked.* The kit builds `uiCheckbox`
with `autoHilite` false on purpose - the comment says the adopter's state
machine sets it - and `waSequenceNumber` read the control's hilite. So the RBF
option the Send screen offered was unreachable and every transaction this wallet
built was non-replaceable, while `waBumpAdvice` told the user to bump it. RBF is
app state now, defaulting on, painted onto the box. In the same class: `uiTable`
takes ABSOLUTE tab stops and all three tables passed column WIDTHS, so every
data column after the first overprinted the ones before it.

*And the boot self-check wrote its report into a field the app replaces
wholesale.* `scBegin` was given `lg_text`, which `waLog` and `waPaintLog` both
overwrite - and the report is written while the Log screen is hidden, so the only
way to read it, clicking the rail button, ran the painter and wiped it first. It
has its own field now. That one is worth carrying beyond this member: the carried
block APPENDS and an app's own log usually REPLACES, so any adopter that points
both at one field has the same defect.

**AND THE STACK IS RUN NOW, TOO.** `tools/check-wallet-boot.py` boots the shipped
`coin-wallet.livecodescript` headlessly and drives it. It is built by IMPORTING riptide's
`tools/check-demo-boot.py` rather than copying it - this tree already knows what happens to
copies of an engine model - and adds only the delta: `the number of controls of this card` and
`control N of this card` (the show/hide sweep works by index, because a screen here is a name
prefix and the engine has no reparenting), and the IMAGE control the Receive screen paints its QR
into. The image is a widening of riptide's shared object regex, applied by rebinding its module
global with the old text ASSERTED first; there are no source rewrites at all, because unlike
riptide this stack was written inside the modelled subset and an unused rewrite list is one that
goes stale unnoticed. Two things it establishes that no static gate could: the sweep really does
show exactly one screen and never touches the rail, checked control by control across all ten;
and the wallet file really does seal, re-open to the same account key, and refuse after one
flipped bit. One trap it had to name out loud: riptide's runner loads nostrxt's copy of
`lcs-interp.py` and this member loads its own, and two byte-identical files are still two module
objects with two `HASHES` tables - so the gate asserts they are identical and then rebinds, which
is the same trap riptide's own header records finding the hard way.

**AND THE PSBT LAYER GOT ITS OWN PASS, which found the sharpest set of all.**
Twelve findings, and the shape they share is that the PSBT code was written for
the documents this wallet PRODUCES and met a conformant one from elsewhere with
no defences. `cwPsbtFinalize` derived m from the first byte of a witness script
it never checked was present: absent, that byte is nothing, `cwBeRead` of
nothing is 0, and m came out as **-80** - so `tHave < tM` was `0 < -80`, false,
and an input with no witness script and no signatures at all was reported
COMPLETE. Below it, the type dispatch had no default: everything that was not
p2tr, p2wsh or p2pkh fell through to a P2WPKH-shaped witness, and a LEGACY input
from a conformant PSBT types as `unknown` (it carries NON_WITNESS_UTXO, from
which `cwPsbtInputType` cannot read a script) - so it got a witness it must not
have. `cwMultisigKeys` `exit repeat`-ed on anything that was not a direct push
and returned the keys it had so far, and that list decides signature ORDER in
`cwSignMultisig` and both the order and the count in `cwPsbtFinalize`: a
truncated parse is a wallet quietly agreeing to a different multisig than the one
on the chain. It parses strictly and throws now, with both call sites turning the
throw into a why-line rather than letting one bad input take a whole operation.
`cwPsbtSign` matched a taproot input's internal key and signed with a hard-coded
empty merkle root, never checking that the output actually pays to the key-path
tweak - the one branch missing the `is not tSpk` guard every other branch has,
and exactly the branch where the guard needs a tweak first. It also ignored
`PSBT_IN_SIGHASH_TYPE` entirely, which BIP-174 requires a Signer to honour or
fail on. And `cwPsbtParseMap` accepted duplicate keys, which the BIP forbids -
not merely lax, because `cwPsbtFind` answers with the first and `cwPsbtEmitMap`
writes them all, so a duplicate survived a parse/sign/emit round trip.

Two of the twelve are worth separating because they were **absences rather than
errors**. `cwPsbtFinalize` returned only the raw transaction, never a finalized
PSBT - so `PSBT_IN_FINAL_SCRIPTSIG` and `PSBT_IN_FINAL_SCRIPTWITNESS` were
emitted by a function nothing called with that metadata, and the wallet skipped
BIP-174's actual Finalizer output, which is the thing a coordinator collecting
from several signers is handed. And `waSigningKeys` walked the address records
looking for a `seckey` that a MULTISIG record never carries (it has
`witnessscript`, `script` and `pubkeys`), so it answered with an empty list and
`waPsbtSign` refused - **the one wallet kind PSBT exists for could not sign a
PSBT at all.** Both closed. Beside them, `waSignSpend` presented a one-of-two
witness as a signed transaction; `cwSignMultisig` reports its count now and the
app refuses, naming the PSBT button as the remedy.

**THE GATE ITSELF WAS THEN REVIEWED, and it was overstating its coverage in five
places.** Worth recording because the shape is this member's own: a gate that
answers the question nobody asks twice. The mutation check that proves the
case-folding tier can still fail compared a Python bool against a description
string, so it could not pass for any input. The compiler-free floor was 60 for a
constants tier that had shrunk to 35, so that path could not pass either. The
`boolean()` helper wiring `cxVerify` and `cxSchnorrVerify` had the .lcb's status
map INVERTED - false where the engine throws, throw where it answers false - so
the script's refusal paths were being driven by the wrong inputs. Twenty-one PSBT
key types carried ONE blanket excuse, "checked by the PSBT round-trip vectors",
when exactly three were ever byte-compared and four were read by no code path at
all. And `kCwQrVersionGen`'s reason named "the version-7-and-up QR vectors" when
the gate built nothing above version 3. All five are closed: the four dead
constants are deleted, every survivor names the vector that puts it on the wire,
three new byte-exact PSBT comparisons cover the output metadata, the legacy
non-witness shape and the signed and finalized documents, and version-7 and
version-8 symbols are built so the version-information block and the second
codeword group are reached. The honest split now also has to ADD UP - two names
sat in both the re-derived set and the excused set, so it printed 35 + 45 for 78.

**WHAT IS STILL OPEN.** Neither gate is an OXT pass: they settle that the code RUNS and what it
computes, not parser behaviour and not that a window appeared. Everything in
`docs/OXT-ENGINE-NOTES.md` the interpreter models differently is invisible to both, the case rule
above excepted. The three transports have never spoken to a real backend from here, and the two
Tor ones additionally need a live-Tor pass. No transaction this wallet built has been broadcast to
any network. The honesty labels in the file, in `docs/wallet.md` and on its own Settings screen all
say so.
