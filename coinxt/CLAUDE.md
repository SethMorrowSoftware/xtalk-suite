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

**AND ON ITS FIRST FULL RUN THE BOOT GATE FOUND TWO THINGS NEITHER FILE OWNS.**
Both are worth carrying because both were latent in code the whole family shares.

The carried self-check block's `scMissing` asked about fields, buttons and
graphics - the three types the KIT builds - and this wallet paints its QR into
an IMAGE, which is the only way a BMP this layer builds becomes something a
phone can read. Registered and built, `rc_qr` reported as missing. The block had
already been widened once for exactly this reason (graphics, after every `uiPill`
reported missing), and the lesson it did not draw the first time is the general
one: **the list of types a demo can build is not the list of types the kit
builds.** Fixed in `tools/demo-selfcheck.livecodescript` and re-carried into all
fifteen adopters; riptide's boot runner learned the type in the same change,
because the block it executes now asks about it.

And `tools/lcs-interp.py` split `put X into Y` with a NON-GREEDY REGEX, so a
statement whose value is a string containing the word `into` -
`put "... A seed typed into this" & return after tOut`, in this wallet's own
custody note - split inside its own message and handed the parser an
unterminated string literal. It surfaced as a `ValueError` out of the string
scanner, about as far from the cause as an error can land. The engine has a real
tokenizer and never had this; the model has a string-aware `split_outside_strings`
now, in both copies and in riptide's runner. **This is the second time a member's
executable gate has found a latent defect in that shared interpreter** (riptide's
negative chunk range was the first), and both were found the same way: by
executing a form no other member happened to write. Note WHERE it was: a paint
handler for a screen that is not the one the boot opens, so every gate in the
tree had been green over code that had never run.

**THE CLICK DRIVE FOUND TWO MORE, in the same shared runner, and the second is
the one worth remembering.** riptide's `DemoExpr.p_atom` matched every branch
against an anchored regex without skipping leading whitespace, so
`word 1 of the name of the target` died on the space its own `of` left behind -
reported as an unsupported expression about a form that class models perfectly
well. And `obj_prop_get` answered `the name` of a control with its BARE name
whatever the adjective, where the engine gives the bare name only for
`the SHORT name` and prefixes the TYPE otherwise: `button "nv_wl"`. That is
exactly what this wallet's click router reads to tell a button click from a
field click - so under the model it answered "not a button" for every click and
passed the message on, and **a gate driving clicks would have gone green over a
stack where nothing routed at all.** A model that is wrong in the direction of
"nothing happened" is worse than one that throws, because throwing is visible.
Both fixed in riptide's runner, whose own fixture suite still catches its four
seeded defects; this wallet is simply the first body in the tree to write
either form.

**AND THE SAME DEFECT CLASS LANDED ONE FILE LATER, WHICH IS THE ONLY REASON TO
WRITE IT DOWN AGAIN.** The gate review above found a mutation check that
compared a Python bool against a description string, so it could never pass.
Hours later, `check-wallet-boot.py` was found with ELEVEN checks written the
other way round: riptide's `Checker.ck` is `(label, ok, detail)` - a boolean and
a message - and the vector gate's `Checker` sitting beside it is
`(label, got, want)`. Eleven comparisons written in the second shape against the
first passed for any value at all. The two APIs are one import apart and the
mistake is invisible at the call site, which is the whole point: **a checker
whose second argument means different things in two files will be got wrong, and
neither shape errors.** The boot gate has `ck()` for booleans and `eq()` for
values now, and a scan asserts no value-shaped `ck()` remains. If a third
Checker ever appears in this member, give it the same two names.

**AND THE LAST TWO DEFECTS THE FULL PASS CONFIRMED WERE BOTH INVISIBLE FOR ONE
REASON: the script and its ORACLE had the same rule.** 66 agents, 58 findings
judged, 2 survived - and neither could ever have failed a vector, because the
two implementations the gate compares agreed with each other and were both
wrong. `cwSelectCoins`'s `manual` strategy narrowed the pool to the ticked coins
and then used the same incremental loop as the automatic strategies, returning
on the first PREFIX that paid: ticking 100000/40000/30000 to send 10000 spent
the 100000 and left the rest, against a contract in this file's own header and a
promise on the Coins screen, and with consolidation - the reason anybody ticks a
set - impossible to express. And `cwBranchAndBound` priced the change output's
FUTURE spend at today's fee rate, where the oracle used a long-term estimate:
two acceptance windows 345 satoshi apart at 5 sat/vB, with no vector in the
band. **An oracle-based gate cannot see a rule both sides get wrong**, which is
the one structural hole in this whole approach and is worth knowing before
trusting a green run. What closes it is not another gate but the thing that
found these: reading the shipped code against the specification rather than
against the other implementation.

**THE FIRST REAL-ENGINE, REAL-NETWORK RUN FOUND THE ONE CLASS NEITHER GATE
COULD, AND IT IS WHERE THE WALLET ASKED (2026-08-31).** A person generated a
wallet, funded the testnet address it gave them, and saw no coins. Everything
this member checks was correct: the seed, the account key, the derivation path,
the address. `waEsploraPath` emitted the MAINNET root `/api` for every network,
and Esplora serves each chain under its own (`/testnet/api`, `/signet/api`) - so
the wallet derived a correct testnet address and asked the mainnet index about
it.

**Why no gate saw it.** `check-wallet-vectors.py` drives the calculator and
`check-wallet-boot.py` boots the stack; between them they settle what the wallet
COMPUTES. Neither had an opinion about the URL it computes, because no backend
has ever been reachable from here - the honesty label two paragraphs down said
exactly that and it was read as a limitation on confidence rather than as the
place a defect would hide. It is worth stating the general form: **the thing an
offline gate is structurally blind to is not a hard case, it is everything on
the far side of the boundary it cannot cross.** The oracle hole recorded above
(two implementations agreeing and both wrong) is the same shape one layer in.

**What made it silent rather than loud is the sharper half.** Esplora refuses a
foreign address with a 400, and `waHttpCheckStatus` reads it - on the two Tor
transports. The clearnet transport goes through the engine's `load URL`, which
hands `waUrlDone` a body and no status code, so the refusal arrived as an empty
result and the wallet reported a green, synced, empty wallet over a funded
address. A wallet that says "you have nothing" is not a visibly broken wallet.

**The guard is wider than the fix, because Electrum fails worse than Esplora.**
An Electrum server asked for a script hash from another chain answers with an
EMPTY LIST - a perfectly well-formed "this address has never been used" - so
there is no status to read and no error to surface at any layer. The built-in
Electrum onion was mainnet-only (the v2 address that stood there until
2026-09-02; the v3 one carries testnet on its own port, see that day's entry),
and the wallet defaults to testnet, so that
combination was one click away and would have reported the same empty wallet
with nothing anywhere to contradict it. `waBackendChainWhy` now refuses any
backend that does not carry the selected chain BEFORE a request is built, and
`waRefreshNetState` recomputes it whenever either half moves - the backend or
the network - so the answer cannot go stale in the direction of "fine". Regtest
is refused against all three built-in hosts, because no public backend carries a
chain you run yourself.

**The regression checks assert both directions**, per this file's own standing
rule that a positive vector cannot catch a check that is not being made: every
request kind carries the network root (not just the two the defect was noticed
on, so a seventh kind cannot forget it), the guard refuses the Electrum and
regtest cases, AND it permits Esplora on testnet and signet and Electrum on
mainnet - an over-refusing guard is the same defect with the sign flipped.
`waSync` is driven to prove the guard is actually reached rather than merely
present.

**THE SCRIPT-TYPE AUDIT (2026-08-31), AND WHY ITS THREE DEFECTS WERE ALL IN THE
APP.** Asked to audit P2SH-P2WPKH and the other types, the engine layer came
back clean and the app layer did not, which is itself the finding. Every
per-type rule in `wallet-core` is right and pinned: BIP-49 purpose 49, the
SLIP-132 ypub/yprv pair, redeem = the P2WPKH scriptPubKey, scriptPubKey =
P2SH(hash160(redeem)), the BIP-143 sighash over the P2PKH scriptCode, a
`[sig, pubkey]` witness with `push(redeem)` as the scriptSig, a 23-byte
scriptSig in the size estimate, message header 35, `sh(wpkh(...))` as the
descriptor. The vector gate drives all of that against the oracle. **What it
cannot drive is the app deciding WHICH type to hand it**, and all three defects
lived exactly there.

*An address record that lied about its own type.* `cwWifInfo` leaves both
SegWit slots empty for an UNCOMPRESSED key, because BIP-143 forbids a SegWit
address for one, so `waImportedRecords` falls back to the legacy address. The
fallback is right; recording it with the type the SCREEN was set to was not.
The record said `p2wpkh` over a `76a914...88ac` scriptPubKey, and the signer
signs by type - so the coins at that address got the BIP-143 sighash and a
witness with an empty scriptSig, which no node accepts. Reproduced headlessly
before it was fixed, and the fixed path now produces a real legacy spend (no
segwit marker, a 138-byte scriptSig for the uncompressed pubkey).

*A wallet kind that could not sign at all.* `waSignSpend` called
`waAccountNode()` and only then asked whether the wallet was an imported key -
and an imported key HAS no account node, so the call threw first. The refusal
read "this wallet has no account key yet. Open one on the Wallet screen", about
a wallet that was open and holding the only key it needs. The guard's own
condition already named the case (`and sWaKind is not "key"`); the call
ordering defeated it. **The shape to remember: a guard written correctly is
still dead if something above it throws for the case it was written to
allow.**

*And the structural half, which is what keeps the first one from recurring.*
`waSignSpend`, the PSBT builder and the size estimate all asked
`waInputType()` - the WALLET's type - where the question is the type of the
COIN. That is true for every seed wallet, which is why it survived, and false
the moment any record differs. `waRecordType` answers per record (falling back
to the wallet's type, which is exactly right for a record saved before the
field existed), and `waSelectedInputSpecs` prices a selection from the coins
actually in it. `waSignMessage` had been reading `tRec["scripttype"]` correctly
all along, so the right pattern was already in the file, in one place out of
five.

**MAINNET IS ALLOWED WITH THE PUBLISHED TEST SEED, BY DECISION, AND THE WARNING
IS THE PRICE.** The earlier entry refused that combination outright. The
refusal was reversed on request, which is a product call and not a technical
one, so it is recorded as a call: the seed this stack pre-fills is printed in
BIP-39, anyone can derive its keys, and mainnet no longer stops you. What
replaced the refusal is a warning that cannot be missed or dismissed -
`waPublicSeedWarning` is ONE computed sentence (so the wording cannot drift and
no screen can quietly stop showing it) rendered on the Wallet screen, at the
top of Receive above the address somebody is about to be paid at, and on Send
ahead of every other warning. It is recomputed on each repaint rather than
acknowledged once, because an acknowledgement is a thing that gets clicked
through and then never seen again by the person who inherits the wallet.

**WHAT THE AUDIT DID NOT COVER, stated because a partial audit read as a whole
one is worse than none.** It walked the five script types through derivation,
scriptPubKey, sighash, signing, witness assembly, sizing, message signing,
descriptors and PSBT metadata. It did not re-audit coin selection, the QR
encoder, the file format or the network layer, all of which have their own
records above. And it settles none of the open items below.

### 2026-09-01 - the audit of the wallet, and why eight of its eleven defects were in code written that week

An audit was asked for and run against `f1408c5`, which is a different tree from the one
the entries above describe: the eight commits of 2026-08-31 landed a whole new transport
(`electrum-clear`, Electrum JSON-RPC over a plain TCP socket), the `lock screen` freeze fix,
the script-type pass and `cwExpandExponent`. **Eight of the eleven defects confirmed are in
that week's code, and six of those eight are in the new transport.** That distribution is
the finding, not a coincidence: the two gates were extended along with the transport and
they check what the transport IS - the host, the port, the chain guard, the wire shapes -
and not what it DOES over time. Nothing in either gate had an opinion about a second request
on a connection that was already open.

**THE SHAPE THE TRANSPORT CLUSTER SHARES: one socket, many requests, and nothing tying an
answer to its question.** Before `f021c57` this transport opened a socket per request, and
the socket handle WAS the correlation, exactly as the comment beside it still says. Making
the connection persistent - correctly, because eighty connections in a few seconds is abuse -
removed that correlation and replaced it with nothing, while the comment claiming it went on
standing. Four defects fall out of that one change and each is silent:

- `waNetFail` closed the Tor stream and never touched `sWaSock`. `waSockClose` had exactly one
  caller, `waNetAbort`. So a 45-second deadline left the connection open with the server still
  owing an answer, `waTick` kept pumping the rest of the queue down it, and the next request's
  armed read collected the PREVIOUS request's reply. `waMergeUtxos` REPLACES every coin at the
  address it was asked about, so one address's coins were written under another's and the second
  address's real coins went with them.
- Nothing ever read the JSON-RPC `id` off a reply. Six writes of `pRec["id"]`, zero reads.
- The `tip` request is `blockchain.headers.subscribe`, which SUBSCRIBES, so a real server pushes
  a header object down that same socket at every block. Between requests no read is armed, so
  the push sits in the buffer and is collected as the next answer: no `result`, `cwJsonCount` 0,
  and `waMergeUtxos` empties a funded address.
- A write that failed forgot `sWaSock` without CLOSING it and dropped `sWaInFlight` on the floor.
  The request was never sent and never requeued, so that address was simply never asked about.

The fixes are `waNetFail waSockClose`, an id check in `waNetApply` that refuses both a mismatched
id and an id-less notification by name, and a requeue-once on a failed write. **The id check is
written to refuse in both directions and the gate asserts both**, because an over-refusing
correlation check breaks every working server, which is the same defect with the sign flipped.

**AND THE PORT IS THE CHAIN, WHICH ONLY ONE HANDLER KNEW.** `waSetBackend` picked the Electrum
port from the network because on this transport the port selects the chain. `waSetNetwork` -
the handler a person actually uses, on a different screen - changed the network and left the
port alone, and `waBackendChainWhy` allows the built-in host on both mainnet and testnet because
it does carry both. So a testnet wallet dialled the mainnet server, which answers a foreign
script hash with an EMPTY LIST, and reported itself synced, green and empty over funded
addresses. **This is the same failure this member learned from a real machine on 2026-08-31 by
way of the Esplora API root, arriving through the port instead**, and the table now lives in
`waRetunePort` alone. A host somebody typed is deliberately left alone: this wallet has no port
table for a server it does not ship.

**WHY THE GATE COULD NOT SEE IT, AND THIS IS THE TRANSFERABLE PART.** `check-wallet-boot.py`
already proved the port was right, in a block that reads `ip.globals["swanetwork"] = "testnet"`
and then calls `waSetBackend`. **It set the state the handler under test was supposed to set.**
A check written that way can only ever confirm the path it already assumes, and it is invisible
at the call site because the assertion that follows it is correct. Every check added here drives
the handler a person reaches - `waSetNetwork`, `waPaintNetwork`, `waNetFail`, `waNetDeliver` -
and reads the result off the same state the app reads.

**THE THREE THAT ARE NOT THE TRANSPORT.**

*An amount can be written in three units and only one of them was written down.* `waReadUri`
put `cwSatToBtc(amountsat)` into field `sd_to`; `waParsePayments` reads that same field with
`cwParseAmount(text, sWaUnit)`. With mBTC selected, a BIP-21 request for 1.5 BTC was written as
`1.5` and read back as 1.5 mBTC - **a thousandfold underpayment, silent, because both numbers
read "1.5"**. Driven through the shipped `wallet-core`: 150000000 sat in, 150000 sat out. On
satoshi it threw instead, which is the dangerous arrangement rather than a lucky one - two of
three units looked fine. `waAmountBare` exists now and is the only thing that writes into that
box; `waAddSelfPayment`'s hard-coded `0.0001` went the same way.

*A fee rate that arrived over a socket became the default the Send screen proposes.* The Esplora
branch wrote `cwJsonGet(tNode, "1")` straight into `sWaFeeRates` with no check at all, while the
Electrum branch three hundred lines above already tested `is a number` and `> 0`: two transports
disagreeing about validating the same quantity. Both go through `waSetSuggestedRate` now, with a
ceiling, and a rate the PERSON types is still their own business.

*And a backend that could never be shown as selected.* `waPaintChoice` only touches the names it
is handed, and `electrum-clear` was added to `waBackendChoice`, to the screen and to
`kWaScControls` but not to that literal - so selecting it darkened the previously lit button and
lit nothing, and the Network screen reported no backend while one was running. The check reads
the hilite off all five real controls, because the defect was a name missing from a literal and
nothing had ever looked at the buttons.

**THREE FAIL-OPEN PATHS IN THE ENGINE, and the first is the one that matters.** `cwPsbtSign`'s
p2wsh branch asked only whether one of our public keys appears inside the witness script THE
SENDER SUPPLIED, and never compared `cwScriptP2wsh(tWitScript)` against the input's own
scriptPubKey. Our cosigner keys are not secret - they are in any descriptor or account xpub this
wallet has ever exported - so anyone could build a 1-of-1 witness script around one, pair it with
a witness UTXO naming any 32-byte P2WSH program and any amount, and get back a real signature
over a BIP-143 preimage of their choosing, reported as `SIGNED 1 input(s)` with no why-line.
**The taproot branch's own comment, eighty lines above, says "every other branch here checks the
script it is about to unlock".** It was the one branch that did not, and the comment is what
should have found it: a claim in a comment that nothing enforces is this member's own recorded
failure shape, and here it sat directly above the code that broke it. Beside it, `cwTxDecode`
drove `repeat with tI = 1 to tCount` from a varint the input supplied, so eighteen pasted
characters (`01000000feffffff0f`) meant 268 million iterations over a string that had already
ended, and an `0xff` count meant no end at all - a frozen ENGINE, on the UI thread, which is the
same class as the `lock screen` freeze recorded above arriving through a different door.
`cwNeedBytes` refuses a count the remaining bytes cannot satisfy, using the SMALLEST an item can
be so it refuses only the impossible. And `cwSignInput` had no default: everything that was not
p2tr, p2pkh or p2sh-p2wpkh fell through to a `[signature, pubkey]` witness with an empty
scriptSig, which is P2WPKH's shape - and `p2wsh` reaches it through the file's own documented
pairing with `cwSighash`, so the pairing produced a signed-looking transaction no node accepts.

**THE ASYMMETRY WAS THE PATTERN, NOT AN INSTANCE.** The unchecked fee rate above turned out
to be one of four places where the Esplora branch validated something and the Electrum branch
beside it did not, in the same handler, on the same quantity. The Esplora tip refused anything
that was not a non-negative integer; the Electrum tip wrote `result/height` straight into
`sWaTipHeight`. The Esplora broadcast required 32 bytes of hex and says in its own comment that
reporting a success the backend did not give is "the failure this whole block exists to stop";
the Electrum broadcast reported a green `Broadcast.` for whatever scalar the server put in
`result`, an error string included - **and a wallet that says a transaction was sent when it was
not is worse than one that says nothing, because the person stops watching.** Neither branch
asked whether the answer was a LIST: `waMergeUtxos` and `waMergeHistory` delete every record for
the address before re-filling, and `cwJsonCount` answers 0 for a null, a string, a number or a
boolean, so any well-formed non-list reply read as "this address has never been used" and
DELETED what it holds. And `kWaMaxBody` was enforced in exactly one place, the OnionXT data
event, so two transports of three accepted a reply of unbounded size.

Each is now ONE handler that both transports call - `waCheckedHeight`, `waCheckedTxid`,
`waCheckList`, `waSetSuggestedRate` - which is the only fix that stops the fifth instance. The
general form is worth stating once, because it is what made all four invisible: **a validation
written inside a per-transport branch is a validation the next transport does not inherit**, and
this file gained a whole new transport that week.

**AND THE FIRST VERSION OF THE PARTIAL-SYNC FIX WAS ITSELF INCOMPLETE**, which is the reason to
write it down. `waNetDeliver` preserved `sWaNetWhy` when a request had failed but still wrote
`"ok"` into `sWaNetState` - so the sentence survived on the Network screen and the PILL, which
is the thing visible on every screen while somebody reads a balance, went green anyway. The
state has its own value now (`partial`), painted `warn` in both places that render it. Fixing
the explanation and leaving the indicator is the same defect one layer out.

**AND A FOURTH CALL SITE OF THE CLASS THE 2026-08-31 SCRIPT-TYPE AUDIT CLOSED, which is worth
its own sentence because the entry above says that audit found the structural half.** That pass
replaced `waInputType()` - the WALLET's type - with a per-record answer at `waSignSpend`, the
PSBT builder and the size estimate, and added `waSelectedInputSpecs` for exactly this. But
`waBuildSpend`'s non-MAX branch still hands `cwSelectCoins` a single `waInputType()`, so the
fee, the vsize, the change-or-changeless decision and the branch-and-bound acceptance window
are all priced for a type the selected coins may not have - while `waMaxSpend`, forty lines
below it, does it correctly through `waSelectedInputSpecs`. **A fix applied at one call site and
not its sibling is this tree's own recorded shape, and here the sibling is in the same handler.**
It is NOT fixed here: closing it means `cwSelectCoins` taking per-coin specs rather than one
type, which is a change to the selector that `tools/wallet_reference.py` mirrors, and the entry
above already records that an oracle-based gate cannot see a rule both sides share. That is a
change to make deliberately, with the oracle moved first, not on the end of an audit commit.

**AND CUSTODY PROMISED MORE THAN IT DELIVERED FOR A FIFTH AND SIXTH TIME, in the two places
where being wrong costs the most.** `waSaveWallet` writes the wallet file with
`put tSealed into URL ("binfile:" & tPath)` on both branches and checked `the result` on
neither, so a full disk, a path inside a directory that does not exist, or a read-only volume
was reported as `Saved, sealed, to <path>`. **The whole value of that sentence is that somebody
then stops worrying about their seed**, which makes an unchecked write here worse than an
unchecked write anywhere else in the file. Both paths throw now, naming the path and saying
NOTHING has been saved. And `waDropSeed`, whose own comment says "the status line is now true
about the state", cleared the mnemonic and the passphrase and left `sWaAccountXprv` and the
`seckey` inside every derived address record exactly where the previous seed wallet put them -
while `waAccountNode` PREFERS the private half and `waSeckeyFor` reads the record's key. A
wallet the screen had just called watch-only still held, and would still have used, full
spending keys. Both `waOpenWallet` branches that reach `waDropSeed` call `waDeriveAddresses`
immediately afterwards, so dropping the derived list there costs nothing and is the only way to
be rid of the keys inside it.

**ONE OF THOSE TWO HAS NO REGRESSION CHECK, AND SAYING SO IS THE POINT.** `waDropSeed` is
pinned in both directions. The write-result guard is NOT, because `check-wallet-boot.py`'s
sandboxed `url_write` RAISES on a bad path rather than setting `the result`, so the model cannot
produce the failure the guard reads. A check written against it anyway would be a check that
cannot fail, which is this member's own recorded worst outcome for a gate - it answers the
question nobody asks twice. The gap is recorded here instead.

**AND THE GATE FOUND THREE MORE BY RUNNING THE FIX, which is the argument for the runners in
one line.** `check-wallet-boot.py` drove `waNetDeliver` for the first time and died in code no
audit had read: `put char -6000 to -1 of (field "nw_out" & tKind && ...)` binds the
concatenation INTO THE CHUNK TARGET, so the engine is asked for a field whose NAME is the whole
log line. `waStreamOpened` already carries that note beside a Content-Length and settles it with
a local; these three sites were written before the note existed. The other two are
`waSignMessage`'s report, which asks for a field named `tl_msg` followed by the signature and
the paragraph after it, and the Log screen's Copy, which asks for one named `lg_boot` followed
by the entire log. Each is silent in its own way - a raw-reply pane that never grows, a signed
message missing the message, a clipboard holding a field name - and none of them is reachable
from any check that existed before this commit.

**Two of my own edits went the same way and are worth the same sentence.** `cwNeedBytes`
computed `the number of chars of pHex - pPos`, which is the identical trap one file over, and
used `div` in an expression where this layer routes integer division through `cwIntDiv`.
`waSetSuggestedRate` and `waCheckedHeight` were written as
`if X is not a number or X <= 0`, and LiveCodeScript evaluates BOTH operands of `or` - so the
comparison still runs on a value that is not a number, which the interpreter refuses and the
engine answers by comparing as text. Nested now. **All four were caught by running the gate,
not by reading the diff**, on code written by somebody who had just finished writing the
paragraph above about the first one.

**AND THE FLEET'S OWN PASS FOUND THREE MORE, TWO OF THEM THE WORST IN THIS ENTRY.** They are
here because a second, independent read of the same files was run against the same brief, and
the two it found that nothing above had are both places where the wallet believed a stranger.

*A PAYMENT REQUEST COULD REPLACE THE WALLET'S ACCOUNT KEY.* The wallet file is one record per
LINE with the name and value split by a TAB, parsed last-wins - and a label is the one field a
person does not type. BIP-21 carries one, and `cwPercentDecode` turns `%0A` into a real newline
and `%09` into a real tab. So a payer could put
`Refund%0Akind%09watch%0Amnemonic%09%0Axpub%09<their key>` in the label of an invoice, and the
next Save-then-Open replaced this wallet's own account key with theirs, after which every
address the Receive screen offered was an address THEY could spend from. It was demonstrated
end to end through the boot harness before it was fixed, driving only real controls. The fix is
`waSafeText` at every door a label enters by, plus a refusal in `waSerializeWallet` so a door
somebody adds later is loud rather than silent. Stripped rather than escaped, deliberately: an
escape needs an unescape and the two drift, and a label has no legitimate use for a tab.

*AND THE WATCH-ONLY BOX ACCEPTED A PRIVATE KEY.* That branch checked the extended key's NETWORK
and nothing else, so an account `xprv` - one character from its `xpub`, and the line directly
above it in whatever a signing wallet exported - was stored in `sWaAccountXpub` and thereafter
treated as public by everything downstream: printed on the Wallet screen under "account extended
PUBLIC key (safe to hand out)", put on the clipboard by Copy, exported by Tools, and written to
the wallet file on the line labelled `xpub`. It was not watch-only either, because
`waDeriveAddresses` re-fills every record through `waAccountNode`, which prefers the private
half - so the records carried spending keys while the status line said "This wallet cannot sign
anything." **`wallet-core` has shipped `cwXKeyIsPrivate` for exactly this question since the day
it was written, and nothing in the stack called it.** A handler that exists for a question
nobody asks is the same defect as a comment that claims a check nobody makes; this entry now
carries one of each.

*And the third is the sibling of the port defect above, one layer down.* `waNetStart` reused
`sWaSock` on the test "is one open?" alone, never comparing it to the `host:port` it had just
computed - so a host or a port edited on the Network screen reached the state and the fields and
NOT the connection. Every script hash of the sync still went to the server the person had just
acted to leave, which is a privacy loss they explicitly moved to avoid; and where the edit was
the chain-selecting port, the old server answered every request for the other chain with a
well-formed empty list. The socket id IS its `host:port` in this engine, so the comparison is
exact and costs nothing.

### 2026-09-01 - non-standard derivation paths, and two single-key tools

The audit above found what was wrong. This is the first thing added because it was MISSING, and
the shape of it is worth recording: **almost none of it was new code.**

**A WALLET THAT CAN ONLY FIND THE ADDRESSES IT WOULD ITSELF HAVE MADE CANNOT RECOVER.**
`cwParsePath` has accepted an arbitrary path since the day it was written - any depth, `'` or `h`
or `H` for hardened, a refusal for a trailing separator and for a level at or above 2^31, all of
it vector-tested. What the app could ask for was `cwAccountPath`, which answers the STANDARD path
for a script type and nothing else. So a person recovering an Electrum legacy wallet (`m/0'`) or
an early Bitcoin Core one (`m/0'/0'`) had correct words, a working parser sitting in the file
they had pasted, and nowhere to type the path. The engine layer was never the limit; the app was.

**THE OVERRIDE GOES THROUGH ONE ACCESSOR, AND THAT IS THE WHOLE DESIGN.** Eight readers each had
their own `cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount)`. Two of them are not display:
`waDescriptorFor`, which is what somebody imports into Bitcoin Core, and `waBip32Record`, which
is the `BIP32_DERIVATION` a cosigner uses to find its own key in a PSBT. A ninth reader that
missed the override would hand a person a descriptor for a wallet that is not theirs, so
`waAccountPath()` is the only caller of `cwAccountPath` in the app now, and the gate checks the
override reaches both of the two that matter rather than only the label.

A NINTH SITE IS DELIBERATELY LEFT ALONE and this is the one to be careful about on any future
edit: `waSelfTestAddress` derives BIP-84's published vector from the published test seed, takes
its type and network as PARAMETERS, and must stay on the standard path whatever the open wallet
is doing. It is the boot self-check's own anchor; routing it through the override would make it
agree with the wallet instead of with BIP-84.

**Validated where it is SET, not where it is read**, so eight readers never see a path that has
not parsed - and validated on the way out of a wallet FILE too, because a file is not a person
and `waLoadInto` already turns a throw there into "nothing was loaded". The depth cap is this
layer's own: BIP-32 has ONE BYTE for depth and this path gets two more levels below it, so a
refusal at 32 is a sentence rather than a truncated byte.

**AND TWO SINGLE-KEY TOOLS, because everything else here derives from a seed.** `waNewKey` mints
one key from SodiumXT entropy with no fallback (waGenerateSeed's reasoning, unchanged) and says
plainly that the wallet will not remember it; `cxWifEncode` refuses a value at or above the group
order, so the 1-in-2^128 case fails closed rather than printing something no node accepts.
`waDeriveAtPath` answers "what is at m/44'/0'/0'/0/7?" without moving anything, which is how a
person finds which path an old wallet used: try one, compare the address. **It is pinned to
BIP-84's published address AND its published private key**, so that check is a real answer and
not this wallet agreeing with itself.

**One test bug worth the line.** The single-key check scraped the WIF out of the panel by taking
the last line containing "WIF" - and that panel's closing sentence ends "...with that WIF.", so
it scraped the word and the base58 decoder refused it. The check failed loudly, which is the
right outcome, but it is the same shape as every other defect in this member's record: a thing
that reads like what it means and is not. It matches the labelled line now.

**WHAT THIS AUDIT DID NOT SETTLE.** It read the app layer, the transport, the amount and fee
paths, and the PSBT signer, and it ran both gates. It did not re-audit the QR encoder, the
wallet file format or the address encodings, all of which have their own records above.
Findings CONFIRMED by reading and deliberately NOT fixed here are listed so this entry cannot be
read as a clean bill: the selection-input-type site above; `cwInputBaseBytes` pricing every
P2PKH input with a 33-byte pubkey when an imported UNCOMPRESSED key's scriptSig carries 65, so
such an input is estimated 32 bytes short in a function whose whole contract is the worst case;
`waBumpAdvice` computing a BIP-125 floor from `pRec["fee"]` and `pRec["vsize"]` that
`waMergeHistory` never writes, so it is always `cwRbfMinFee(0, 0)`; a taproot input signed
SIGHASH_DEFAULT where the PSBT asked for ALL; `cwPsbtFinalize` not reading the `PSBT_IN_FINAL_*`
fields it writes; `cwSignMultisig` not capping its signature count at m; and `cwReadVarInt`
accepting a non-minimal varint, after which the txid it feeds is not the txid of those bytes.

Also confirmed and open, all in the transport and the file the fixes above touched, and left
because each is a change of its own rather than a line: `waNetStart` reuses `sWaSock` whenever
it is non-empty without comparing it to the `host:port` it has just computed, so a host or port
edited on the Network screen is applied to the state and NOT to the connection already open -
the sibling of the port defect fixed above, one layer down; `waSockOpened` reads `the result`
to test whether the connect succeeded, after an intervening `set the defaultStack`, and `set`
is a command that clears `the result`, so that branch cannot be reading the outcome of the
`open socket` at all (failures do arrive, through `socketError`, which is why nothing looked
broken); `waMergeUtxos` stores the backend's txid with no shape check while `waPaintCoins`
renders one line per coin and `waSelectedCoinKey` maps a clicked row back by arithmetic, so a
txid containing a return shifts every row after it; the PLAIN wallet-file branch writes and
reads its payload with no `textEncode`/`textDecode` where the sealed branch of the same two
handlers wraps the identical bytes in UTF-8, so a non-ASCII label round-trips differently
depending on whether the file is encrypted; and the boot self-check's three base58 address
assertions use `is`, which is case-INSENSITIVE by default - so the checks the file calls "the
cheapest possible place" to catch a wrong address cannot catch a case-only one.

**Naming them here rather than fixing them quietly is the point**: a partial audit read as a
whole one is worse than none.

**WHAT IS STILL OPEN.** Neither gate is an OXT pass: they settle that the code RUNS and what it
computes, not parser behaviour and not that a window appeared. Everything in
`docs/OXT-ENGINE-NOTES.md` the interpreter models differently is invisible to both, the case rule
above excepted. The three transports have never spoken to a real backend from here, and the two
Tor ones additionally need a live-Tor pass. No transaction this wallet built has been broadcast to
any network. The honesty labels in the file, in `docs/wallet.md` and on its own Settings screen all
say so.

### 2026-09-01 - a right-click menu, a full toolset, and the fee bump that used to be a paragraph

Five things landed together. Four are tools the wallet advertised and did not have; the fifth is
the one that had been talked out of existing.

**THE CONTEXT MENU IS IN THE KIT, AND IT IS OPT-IN.** `tools/ui-kit.livecodescript` gained
`uiContextMenu`, `uiPopupMenu` and `uiMenuSource` - a hidden `style "menu"` / `menuMode "popup"`
button, `popup button ... at the clickLoc`, and the menu's own name read back so a `menuPick`
label can be resolved against the screen it came from. Nothing about the other seventeen adopters
changed: a stack that never calls `uiContextMenu` never builds a button, so the block is carried
by all eighteen and used by one. That mattered more than it sounds. The kit is held BYTE-IDENTICAL
across every carrier, so a look change is a fleet change; adding behaviour that fires only when
asked for is how a shared block grows without eighteen re-passes.

**A MENU ITEM MEANS WHAT THE BUTTON MEANS, BY CONSTRUCTION.** The obvious implementation gives
each item its own call, which is a second copy of the click router that drifts from the first the
week somebody renames a role. Instead `mouseUp`'s dispatch was extracted into `waRouteKnows` and
`waRouteClick`, and `waMenuRoute` resolves an item to the same `"<prefix> <role>"` pair a button
name produces. An item that routes to nothing answers EMPTY and `waMenuPick` throws, so an
unwired item is a failed check rather than a click that quietly does nothing -
`tools/check-wallet-boot.py` walks every item of every screen's menu through the router and
requires each non-self route to name a control the app's own registry already carries.

**NONE OF THE MENU HAS RUN ON AN ENGINE.** `popup`, `menuMode` and `menuPick` are documented
LiveCode and OpenXTalk is a fork of it, but no stack in this suite has ever opened a menu and the
headless runner models no mouse button. What the gates settle is the menu's CONTENT and its
ROUTING. That it APPEARS needs an OXT pass, and `mouseDown` is written so that the answer does not
matter: button 3 only, `uiPopupMenu` ANSWERS false rather than throwing, and every failure path
is `pass mouseDown`.

**THE FOUR TOOLS.** A script decoder for bare hex, first-class validation, the BIP-39 round trip,
and the fee bump. Two of them are worth more than their code.

`cwScriptCheck` is a SECOND WALK over the same bytes `cwScriptAsm` renders, and the duplication is
the point. A LiveCodeScript chunk expression that runs past the end of a string ANSWERS with what
is there rather than refusing - so a push claiming forty bytes with ten left renders as a ten-byte
push and reads exactly like a correct decode of a different script. `cwScriptAsm` never had to ask,
because everything it had ever been given came out of a transaction, where the varint that
introduced the script had already framed it. A script pasted into a box has no such frame. The
renderer's output is pinned by the vector gate and by every transaction the inspector has ever
printed, so folding the check into it would have been a change to both; it is a separate function
with the reason in its docstring, and eight truncation shapes plus nine well-framed ones are
vector-tested in both directions.

`waValidateAnything` asks a different question from `waInspectAnything`, and the difference is the
whole reason it exists: the inspector says what something IS, the validator says whether it is safe
to pay and ON WHICH CHAIN. **It checks every network, not this wallet's.** The mistake that costs
money is not a mistyped address - a checksum catches that - it is a well-formed address for the
wrong chain, which a validator that only asks about the current network reports as simply invalid.
"Invalid" reads as "I mistyped it". The extended-key branch adds the structural check no checksum
makes: BIP-32 fixes a depth-0 key's parent fingerprint and child index at zero, so a key claiming
depth 0 with either set was assembled by hand, and one claiming depth 3 with a zero parent had its
header edited. Neither is caught by Base58Check, and both derive perfectly valid addresses nobody
else will ever see. It derives through `cwAddressAt` - the wallet's own builder - rather than a
private reimplementation, because a validator that agrees with itself and disagrees with the wallet
is worse than no validator.

`waWordsToEntropy` closes a one-way street: entropy-to-words shipped alone, so you could check what
a dice roll would become but not what a phrase you already hold came from. **It runs the trip both
ways and refuses to report a number the return journey does not reproduce.** Recovering entropy
means stripping checksum bits, and an off-by-one there yields a plausible hex string that
regenerates DIFFERENT words - a number that looks right and is wrong, which is this member's
recorded failure shape. It prints the master fingerprint with and without the passphrase side by
side, because the passphrase is a thirteenth word rather than a password on the phrase: every
passphrase opens a real, empty, different wallet, and nothing anywhere will tell you that you typed
it wrong.

**AND THE BUMP.** What stood there was advice, and the advice was defended in a comment: "this
wallet does not do it for you, deliberately - building it where you can see every line is safer
than a button that rebuilds it out of sight." The safety argument is real and it is kept -
`waBumpFee` prints every input, every payment and both change amounts, and signs nothing until it
has checked its own arithmetic against the transaction it actually produced. What was not
defensible was the reason underneath it, which is that **the wallet could not do it**. Signing an
input under BIP-143 commits to that input's VALUE, and the raw transaction does not carry it; the
moment a spend is signed those coins leave `sWaUtxos`, so the wallet was looking at a transaction
it could price a replacement for and could not build one. Reconstructing a spend by hand under time
pressure, from a fee estimate that has already proved wrong once, is the moment a person pays the
wrong address.

`waRecordSpend` keeps what each signed spend was made of, keyed by txid. The replacement is the
same transaction with a smaller change output: same inputs, same BIP-125 opt-in, same payments to
the same people, and the extra fee out of the coins that were coming back to you anyway. Nothing is
re-selected, so no path here spends a coin the original did not - which the gate checks by decoding
both transactions independently and comparing outpoint sets. **The floor is computed over the
REPLACEMENT'S OWN size**, not the original's, because a signature is a byte or two shorter about
half the time and a bump that misses the floor by a byte is refused by every node, silently, and
looks exactly like a bump that was never sent. The replacement is itself recorded, so it can be
bumped again.

**THE RECORD IS MEMORY ONLY, and that is a decision rather than an omission.** The wallet file is
one field per line with a tab between name and value; a per-transaction coin list is a nested
structure that format has no spelling for. Inventing one would be a change to the format every
existing wallet file is written in, for the case of bumping a transaction made in an earlier
session - which the advice text still covers. So the button is one button either way: it builds
when the window holds the makeup, and prints the advice plus a plain sentence about why it cannot
when it does not. A person with a stuck transaction should not have to know which case they are in
before pressing something.

**ONE LAYOUT DEFECT FOUND ON THE WAY, and it was mine from earlier the same day.** `waPaintTools`
re-lays `tl_note` on every refresh, at a rect that the two buttons added that morning had been put
underneath. The builder and the painter each named the rect, and only the builder was updated. Both
name the same rect now, and the Tools panel was re-laid to fit thirteen buttons and the passphrase
input. It is worth noting how it surfaced: not from a gate and not from reading the new code, but
from reading the PAINTER while looking for somewhere to put a button. A control created in two
places with two rects is invisible to a boot check that only asks whether it exists.

**WHAT IS PROVEN AND WHAT IS NOT.** Everything above is settled headlessly, against the real
committed shim, by `tools/check-wallet-boot.py` and `tools/check-wallet-vectors.py` - the framing
checks in both directions, the validator on four address cases and two key cases, the round trip
against `cxMnemonicFromEntropy`, and the replacement decoded by the independent oracle and checked
against BIP-125 rules 1, 2, 3 and 4. None of the five additions above has run on an engine, no
menu has been opened by a person, and no transaction this wallet built has been broadcast to any
network.

### 2026-09-01 - the first engine run of the wallet, and the twenty-seven lines it sent back

The wallet's first contact with a real engine did not arrive as a harness report. It arrived as a
pasted log: twenty-seven consecutive, byte-identical copies of `error: that seed phrase does not pass
its BIP-39 checksum`, then `FAILED: this wallet is offline.`, then a complete, successful sync of the
demonstration wallet over Electrum-clearnet against `electrum.blockstream.info:50001` on mainnet -
one persistent socket, every reply correlated by id, ids 2 through 145, a 16 KB history included.
Three things in that log are defects, one is a label that had to flip, and one is a guess about
what the person was holding that turned into a feature.

**THE TWENTY-SEVEN LINES WERE ONE DEFECT, and it was a wall.** `waOpenWallet` committed the seed box
into `sWaMnemonic` and THEN asked `waDeriveAccount` whether it was any good - and `waDeriveAccount`
emptied the account key, the private key and the fingerprint BEFORE it validated. So one bad phrase
plus one press of Open left a wallet whose state WAS the bad phrase and whose account was gone, and
every later click that re-derives - the four network buttons, the five script-type buttons, the
account box - re-validated the same phrase and threw the same sentence. The person clicked around
trying to find what was wrong, which is exactly what a person does, and each click was another line.
Twenty-seven is not a count of attempts at the phrase; it is a count of clicks on a screen that had
stopped working. `waSetNetwork` had the same shape one layer down: network committed, coins dropped,
THEN the derive that can refuse - so a watch-only key on the wrong chain produced a wallet on mainnet
showing testnet addresses under an error about the switch.

And the watch-only kind had it worse, which the gate found on its first run by asking for a refusal
that never came: `waSetNetwork` re-derived only when the wallet HAD A MNEMONIC, which a watch-only
wallet never has - so a network switch on one ran no derive at all, the chain check that
`waDeriveAccount`'s watch branch exists for never ran, and the addresses stayed the old chain's under
a network label that said otherwise. It re-derives whenever there is an account key to re-derive from,
and the watch branch re-encodes the addresses for the chain that passed.

All three read-then-write orders are reversed now. `waOpenWallet` reads every box into a local,
validates all of it, and commits only after the last check that can refuse; `waDeriveAccount` builds
the new key material in locals and writes the three fields together at the end; `waSetNetwork` and
`waSetType` keep the old state in locals and put it back on a throw, re-thrown after the try because a
throw inside a catch does not reach the caller here. **The property the gate holds is not "the error
is better"; it is that a failed Open changes nothing** - the phrase that was open is still the phrase
that is open, the account key is byte-identical, the addresses are byte-identical, and four more
clicks on that screen add zero copies of the error to the log.

**THE SENTENCE ITSELF WAS THE SECOND DEFECT.** "Does not pass its checksum" is the least useful true
thing to say about a phrase: it does not say whether a word is misspelt, which word, whether there
are eleven words rather than twelve, or whether the phrase is a perfectly good seed from another
wallet. `cxMnemonicToEntropy` throws every one of those distinctions by name and this app was
catching them and discarding them. `waMnemonicProblem` now asks it and passes the answer through,
with the word count: "word 1 is not in the BIP-39 English wordlist (12 word(s) given.)". A person
who had typed their phrase twenty-seven times never once saw which word was wrong.

**A MULTISIG WALLET IGNORED ITS OWN PHRASE.** Found while reversing the order above: the multisig
branch of `waOpenWallet` exited before the line that read the seed box, so choosing Multisig, typing
a phrase and pressing Open derived the cosigner key from whatever `sWaMnemonic` held before - at boot,
the PUBLISHED test seed. The phrase box is now read and validated before the kind dispatch for both
kinds that have one; an empty box on a multisig wallet keeps the seed already open, because a
cosigner may have opened it first.

**THE OFFLINE FAILURE AND THE DOUBLED SYNC were two small ones on the Network screen.** Test queued a
request with no backend chosen, so the pump dialled nothing and reported it through `waNetFail` as a
failure - a count, a red pill and a torn-down connection, for a wallet that had simply not been told
where to look; it refuses at the door now, the way Sync already did. And `waSync` appended a whole
second batch behind whatever was still queued, so the log shows eighty-two requests and then the same
eighty-two again from id 85 - twice the round trips, twice what a public server learns, and a failure
count reset under a batch still adding to it. A non-empty queue is a running sync and a second press
is refused; a single request in flight (Test's tip) is not a sync and does not block one, because
Test-then-Sync is the flow the log actually shows.

**THE SUBSCRIPTION.** `blockchain.headers.subscribe` is the only way Electrum's protocol answers "what
is the tip", and it is a subscription: after the answer the server pushes a new header on every
block, with a method and no id, for the life of the socket. `waNetApply`'s id check - added in the
audit above - correctly refused to treat that as an answer, but the refusal was a throw, and a throw
there is `waNetFail`: socket down, failure counted, the request that was in flight retried. A pushed
header during a sync would have failed a request the block had nothing to do with. `waNetDeliver` now
asks `waIsNotification` before it touches the in-flight record, logs the push, and drops it; the real
answer lands on the next line into a wallet still waiting for it. Two Test-then-Sync subscriptions on
one socket, as the log shows, are harmless for the same reason.

**THE LABEL THAT FLIPPED.** Until this log, every document in this member said the transports had
never spoken to a real backend. Electrum over clearnet now has, on a real engine, against a real
server, for a full sync. `docs/wallet.md` says so with the date; the other three transports keep their
labels, and the doc-status gate is what makes the difference between "flipped" and "forgotten" a
build failure rather than a reading.

**AND THE GUESS THAT BECAME A FEATURE.** A phrase that fails BIP-39's checksum twenty-seven times is
very rarely a phrase with a typo in it. It is far more often a phrase that was never BIP-39: Electrum's
seeds are twelve words from the SAME English list and fail BIP-39 by design - Electrum's generator
rejects any phrase that would also validate as BIP-39, so the two formats never collide. Their own
check is the hex prefix of HMAC-SHA512 keyed "Seed version" over the phrase ("01" original, "100"
segwit, "101"/"102" two-factor), their seed is the same PBKDF2 with salt "electrum" instead of
"mnemonic", and below the master key they are ordinary BIP-32 at paths this app already let a person
type: `m/0'` for segwit (p2wpkh), the master itself for the original kind (p2pkh, receive `m/0/i`,
change `m/1/i`). `waSeedFormatOf` asks the phrase what it is; an Electrum seed opens at its own path
and script type whatever the buttons said, because the alternative is a valid seed opening the wrong
wallet - a zero balance that reads like an empty wallet rather than a mistake. The two-factor kinds
are named and refused: those need TrustedCoin's third key. Nothing about the wallet file changed,
because the phrase carries its own format and the path and type were already saved.

Both Electrum vectors in the gate were MANUFACTURED the way Electrum manufactures seeds - draw twelve
words until the HMAC prefix matches and BIP-39 does not - and their addresses come from the
independent reference with salt "electrum", so the check is not the wallet agreeing with itself. The
first attempt at that search walked the wordlist with a fixed stride and could never have found a
"100" prefix: 2048 distinct phrases against a 1-in-4096 event. It ran for twenty minutes before the
arithmetic was done. A search that cannot succeed looks exactly like a search that has not succeeded
yet, which is this member's failure shape one more time, in the tooling.

**THE COST OF THE FIX, AND THE COST OF THE CHECK, both had to be paid down before either could
land.** The first version of `waDeriveAccount` asked `waMnemonicProblem` and then `waSeedFormatOf`,
and each of those runs `cxMnemonicValidate` - a twelve-word walk of the 2048-word list, which under
the interpreter is seconds - so the path that SUCCEEDS paid twice for an answer the first call had
already given, on every derive in the gate. The format is asked once now and the problem only when
the format says there is one. And the first version of the gate's check clicked four network and
script-type buttons in a row to prove that a click after a failed Open no longer throws; each of
those re-derives forty addresses through the shim, and the property is proven by the first click
exactly as well as by the fourth. Together they had pushed `check-wallet-boot.py` past a hundred
minutes - a gate `build-all.sh` runs on every push - and the run looked, from outside, exactly like
a hang: one line, no output, for twenty minutes. It was not; CPU time equalled wall time throughout.
But a gate whose honest run is indistinguishable from a stuck one is a gate somebody will kill, and
the number that matters for a gate is not only what it proves but what it costs to be believed.

**What this settles and what it does not.** Every defect above has a check in
`tools/check-wallet-boot.py` driven through the real click router, and the boot self-check asks the
phrase-format question on open. The Electrum-clearnet transport is engine-proven for a read-only sync;
no transaction built here had been broadcast and Esplora-clearnet and both Tor transports had still not
met a backend - three claims that were true on this date and closed by the two entries below it on
2026-09-02 - and the Electrum seed support has run only under the interpreter against the reference;
it has not opened a real Electrum wallet's coins on an engine.

### 2026-09-02 - the first coin, and half the requests

**A TESTNET RECEIVE, reported by the person running the wallet on an engine**: a wallet created
here, an address handed out, coins arriving at it, seen over both clearnet transports. That is the
first coin this wallet has ever held on any chain, and it flips the Esplora-over-clearnet label
that the 2026-09-01 entry left standing - a receive is a sync that found the coin. Recorded as
REPORTED rather than observed: no log was pasted this time, so the record says what was said and no
more. The two Tor transports still had not met a backend from here at that point, and nothing built
here had been broadcast - both closed later the same day, in the entry below.

**And the request count, which the same person asked about.** A sync queued unspent outputs AND
history for every address - eighty-two round trips to learn that a fresh wallet is empty - and
each of those is a thing a public server learns and, over Tor, a trip through three hops. History
is the question that has to be asked of every address (it is the History screen's only source, and
a spent-out address still counts as used or the Receive screen re-offers it); unspent outputs are
not, because an address with no history has none by definition. `waSync` queues history alone and
`waFollowHistory` queues the unspent-output request the moment an address's history comes back
non-empty - forty-two requests for a fresh wallet, one more per address that has ever been used.
An EMPTY history replaces that address's coin rows with none, through the same call the utxos
reply would have made, because a re-sync keeps the last sync's coins until each address answers
and an address whose history has gone empty (a re-org that took the funding transaction) would
otherwise keep a coin the chain no longer has. Both directions are gated against a real server's
bytes: a one-row history queues exactly one utxos request for that address, an empty one queues
nothing and clears it.

### 2026-09-02, later - Tor, and the first broadcast

A second pasted log from the same engine, and it is the one this member's honesty labels were
written to wait for. Read in order it shows: the reshaped sync on Electrum-clearnet on both chains
(forty histories, then unspent outputs only where a history was non-empty - a fresh mainnet wallet at
exactly forty-two requests, ids 147 to 188); the specific-word diagnostic firing on a real engine
(`word 12 is not in the BIP-39 English wordlist. (12 word(s) given.)`) with the open wallet left open
behind it, which is the 2026-09-01 fix doing on an engine what the gate said it would; then
`backend: esplora-tor`, and everything after that is new.

**ESPLORA OVER TOR WORKS.** `dial <onion>:80 stream 1`, a tip, fees, forty histories and the unspent
outputs of the three used addresses, every one through OnionXT's SOCKS client to the Esplora onion
mirror, 147 circuits in all. One circuit failed (`SOCKS handshake timed out`), the request was retried
once as designed, and the sync went on. That flips the label on the third of the four transports;
Electrum over Tor is the one left.

**AND THE FIRST BROADCAST.** `recorded the makeup of 7978bdd2...` - `waRecordSpend` running on an
engine - then `POST /testnet/api/tx` and a sixty-four-character answer, which is Esplora echoing the
txid. Decoded from the raw bytes the log carries, by the independent reference: txid
`7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, 226 vB, one legacy input, sequence
`fdffffff` (replaceable), 10000 sat to `n476wEbNGa4jdzHJHb5hBS7b3swdHD9W2N` and 181973 sat change to
`muzfHmKN4YHZQc1hvccyk6MR5VnhmNYQqM` - both this wallet's own addresses, so a self-payment, which is the
right first transaction to make. **The reference's txid is the txid the wallet logged**, so the
wallet's own transaction hashing agrees with an independent implementation on a transaction the
network accepted. And the sync that followed shows it: the input address `n2EhgCTvLg8zyTchgXCURSkoYZT8e7Q1BN` answering `[]` to
unspent outputs where it had answered one coin before, and both outputs appearing as coins. Every
honesty label in this member that said "no transaction this wallet built has been broadcast" is
closed as of this log; each carries the date and the txid where it stood.

**THE ONE DEFECT IN THE LOG IS THE GUARD FROM THE MORNING, seen from the other side.** `a sync is
already running, with N request(s) still queued` appears seven times, at 38, 36, 40, 25 and 4
queued. Not one is a press of Sync. They are the nav rail's Refresh, pressed while a slow Tor sync
walked its queue - and `waNavClick` had always started a sync on every refresh, which before the
guard meant a whole second batch appended each time (the four back-to-back syncs of one empty
mainnet wallet in the same log, ids 147 to 314, are that), and after the guard meant an ERROR line
about the very thing the person was waiting for. Refresh is a repaint that would also like fresh data;
it now syncs only when nothing is running and otherwise says where the running sync is, on the status
line, as information. The History screen's refresh and the Addresses screen's scan go the same way.
The Sync button keeps the refusal: pressing SYNC during a sync is the one case where somebody meant
to start another. The gate drives all three during a queued sync and asks for no throw, no growth,
no error line, and the status.

**Two things worth carrying that are not defects.** On Tor every request is its own circuit - 147
dials for one sync-and-broadcast - because the Esplora transport speaks HTTP/1.0 over a fresh stream
per request. Reusing one stream with keep-alive would take the per-request cost to nearly nothing
and is the next reduction worth making; it is a transport change with no engine pass, so it is named
here and not done here. And the demonstration wallet on testnet has history on all forty of its
addresses (the published seed has been used by everybody who ever read the specification, and its
first address carries 38 KB of it), which means a wallet whose whole derived window is used cannot
offer a fresh address without "Derive twenty more" being pressed; a real gap-limit scan extends the
window itself until twenty unused addresses stand at the end. This wallet's does not. It is named as
open rather than fixed because extending the window during a sync is a change to what a sync IS, and
the log that would prove it right has not been produced.

**How this entry was gated, honestly.** `tools/check-wallet-boot.py` was run three times on this tree
and reached line 249 of its output each time - "the boot marked itself booted", with zero failures and
every check that touches the changed code behind it, the ten refresh-during-sync checks included - and
was cut off each time at the slow re-boot step when the session's runner was reclaimed. The tail after
that point (the tools, engine-log, Electrum and menu blocks) touches none of the three handlers this
change edits and passed at 323 on the commit before it. The complete run on this tree is the one
`build-all.sh --gates` makes on the push. That is stated here rather than rounded up to "green" because
a partial run reported as a pass is the kind of sentence this file exists to refuse.

### 2026-09-02, later still - "neither clearnet nor tor ever fire"

Reported against the commit above, with no log: after updating, no transport made a request - not
clearnet, not Tor, "the tor daemon never even gets the request", ports checked. The commit's diff is
three Refresh call sites and one new handler, none of them near the pump, the sockets or Tor, so the
cause is not a code path but a STATE - and the one state that silences every transport at once is the
request pump not running. `waTick` exits for good the moment `sWaPolling` is not "true"; `closeStack`
sets it, and a re-pasted script reinitialises every script local so the pending tick fires into an
empty flag and never re-arms. From then on every request sits in the queue with nothing behind it: no
`open`, no `dial`, no FAILED line, a Tor daemon that never hears a handshake, and Refresh reporting a
sync "already running" that will never move. Nothing that queued a request had ever asked whether the
pump was alive. It is a shape this member has met before - a queue is not a transport - and it was
invisible to the boot gate because the gate drives `waSync` and reads the queue; it never pumps.

`waEnsurePolling` arms the pump before Sync, Test and the broadcast queue anything, and writes one
line to the log when it had to. Sync and Test also log what they queued and to where, because the
last three logs went from `backend: ...` straight to the next thing and could not say whether a sync
had been asked for at all. Whether this was the cause of the report is NOT settled here - no log was
pasted - and the record says so: the fix makes the pump-stopped state impossible to stay in and makes
the next log name it if it was. Gated for both directions under the interpreter (a stopped pump is
re-armed and logged; a running one is left alone), fast gates green; the full boot gate is CI's on
the push, for the reason the entry above gives.

### 2026-09-02, the fourth log - every transport fires, and three things the fleet had not met

A pasted log from a fresh open of the stack, and it answers the report above first: Esplora over
clearnet, Esplora over Tor and Electrum over clearnet all fire, on both chains, with the halved sync
and the Refresh that no longer errors. The log begins with the boot self-check (27 green, the
Electrum-format assertions among them), which is `openStack` running `waBoot` and arming the pump -
so the reopen is what cleared the "nothing fires" state, exactly as the pump-not-running diagnosis
predicted, and `waEnsurePolling` is what keeps a re-paste from putting it back. Three defects
followed, each one a real backend doing something the interpreter's fixtures had never done.

**A FEE ESTIMATE IS A FLOAT ON THE WIRE.** `{"result":0.0026374400000000004}` - electrs computing
263744/1e8 in IEEE doubles and serialising every digit - and `cwBtcToSat` refused it, correctly for
an AMOUNT (a ninth decimal is money that does not exist) and wrongly for a RATE (noise a thousandth
of a satoshi wide). Every Electrum sync failed its fees request, reported itself partial, and left
the Send screen on its default rate. `cwExpandExponent` had already met the other float artefact
(`1e-05`, the 2026-09-01 log); this is the second, and the fix is the same shape: the string is cut to
eight decimals BY CHARACTERS before it goes near the converter, because arithmetic is where the
extra digits came from. The gate wires the log's own bytes and asks for 264 sat/vB.

**A FAILED TOR REQUEST WAS DROPPED, NOT RETRIED.** Two circuits died mid-sync (`no header/body
boundary in 0 bytes`), and both times the wallet moved on to the NEXT address: a history never
merged, so - under the halved sync - its unspent outputs never asked for, so a funded address
missing from a sync that called itself merely partial. The requeue-once that existed covered one
failure shape only, a refused socket write. `waNetFail` now puts any request that was still in
flight back at the FRONT of the queue and tries it once more before anything is counted; a reply
that arrived and did not parse is not retried, because `waNetDeliver` clears the in-flight record
before applying and a deterministic failure has nothing to gain from a second attempt. The empty
close is also named for what it is - a circuit that failed - rather than as a malformed reply. And
the deadline now moves with progress: it was set once per request and measured a whole reply against
forty-five seconds, and the same log has a 2155402-character history arriving over Tor, which is a
body that can still be arriving when a fixed deadline expires.

**INSPECT TOLD THE PERSON TO ASK THE BACKEND, AND HAD NO BUTTON THAT DID.** `error: this wallet does
not hold the raw bytes of that transaction. Ask the backend for it` - about a wallet whose two
transports had each carried a raw-transaction request since they were written, which nothing ever
queued, and whose Electrum branch had no case for the reply at all (it fell off the end of the
dispatch). Inspect now asks, the answer lands on every history row carrying that txid, the panel
paints when it arrives, and the bytes are checked against the txid they were asked for so a stale or
mistaken reply cannot be inspected as the transaction somebody clicked.

Also in the log and not a defect: the legacy demonstration wallet on testnet has addresses with
2 MB histories (the published seed, used by everyone), and the sync of it over Tor was restarted
three times before it got through - the fixed deadline above, seen from the outside.

Gated under the interpreter with the log's own bytes for the fee reply, both directions of the
retry, the empty close, and the Inspect round trip on both transports; fast gates green; the full
boot gate is CI's on the push, for the reason the entries above give.

**And the wallet's own honesty panel was two days stale**, which the person running it noticed
before this file did. The Settings screen's "What is proven, and what is not" still said "this
STACK has not run on an OXT engine" and "the three network transports have never spoken to a real
backend" under a wallet that had synced on three transports and broadcast. The doc-status gate
deliberately does not read `.livecodescript` prose (its docstring says so), so nothing could have
caught it; the panel is rewritten with every claim dated and the log that made it named, and this
sentence is the reminder that the gate's blind spot is exactly where the most-read label lives.

### 2026-09-02, the fifth engine log: a dead onion, a boot record that grew, and a menu that acted on the wrong row

**THE ELECTRUM ONION WAS A VERSION-2 ADDRESS, and Tor stopped resolving those in 2021.**
`kWaElectrumOnion` read `explorernuoc63nb.onion` - sixteen characters, the retired shape - so the
first engine attempt at Electrum over Tor dialled it, was answered by the daemon with "general SOCKS
server failure", retried once (the requeue of the previous entry, seen working on an engine for the
first time), and failed on the retry. The daemon uses the same words for a circuit that failed, which
is why the retry was reasonable and why the log could not say what was wrong. The constant is
Blockstream's v3 onion now (the address the Esplora mirror already used; the two constants stay
separate so they can move apart), with the chain selected by PORT the way the clearnet server does it
- 110 mainnet, 143 testnet, the operator's published table and NOT yet observed from this stack.
`waRetunePort` now holds that table for the onion as well as for the clearnet host; it held only the
clearnet one, so the Tor transport would have dialled 110 for every chain, and the chain guard that
refused testnet on the onion for exactly that reason now refuses only signet and regtest. Lifting the
guard without the port branch would have swapped a refusal for a well-formed empty wallet. And
`waOnionWhy` refuses the retired shape BY NAME - on the Network screen's state line, in `waSync`
before a request is built, and in the dial itself for a host edited after the state was computed -
because "general SOCKS server failure" is not a sentence anybody can act on. Electrum over Tor is
still the one transport with no engine pass; what changed is that the next attempt can reach a
server.

**THE BOOT RECORD GREW BY ONE BLOCK PER OPEN.** The log opened with three boot self-check blocks.
The field is saved with the stack and the carried block appends, so every open added a block and
nothing in the text said which one was about the build being read. `waScFresh` empties the field
before `scBegin`, as its own handler so the gate can drive it without paying for a second boot, and
the gate reads the ORDER from the source, because a clear after `scBegin` would erase the block it had
just started. This is the adopter's line, not the master block's: the block's log field is whatever
the adopter passes it, and a demo passing its general log would lose what it wrote before boot.

**THE RIGHT-CLICK MENU ACTED ON THE PREVIOUSLY SELECTED ROW.** First seen open on an engine in this
log ("menu works, but maybe needs a second look for usability"). A list field moves its selection on
button 1 only, so a right-click on a table popped a menu whose Inspect, Copy and Freeze acted on
whatever had been clicked before. `mouseDown` now sets the hilitedLine from the clickLine before the
popup, contained so an engine that answers the clickLine oddly still gets its menu; the gate models
the clickLine the way it already modelled the target, and asserts the selection moves on button 3
and on nothing else. That the selection is seen to move on an engine needs the next pass.

Also in the log: clearnet Electrum on testnet synced clean under the new log lines ("test: asking",
"sync: queued 42 request(s)"), which is the first log in which every queue names its transport.

Fast gates green; the boot gate's new blocks were driven in isolation against the booted stack
(the full gate is CI's on the push, for the reason the entries above give).

### 2026-09-03, the sixth engine log: Electrum over Tor runs, and dials 173 streams to do it

**THE TRANSPORT WORKS.** First log in which Electrum over Tor spoke to a server: Blockstream's v3
onion on port 143 (testnet), the tip, fees, forty histories and every unspent-output request of the
public test seed, a second wallet synced, a broadcast (txid
`9bab6640f2bbe01f96a95ffdeca3e96881f1819e677348562ef8bf87da6b719a`) seen spent by the sync that
followed. All four transports have now synced real wallets on an engine; the labels in the Settings
panel and docs/wallet.md moved with it. Also seen: one boot self-check block on open (the previous
entry's fix), and the retry-once of two entries ago never needed. Mainnet on port 110 is still the
operator's table and nothing more.

**AND EVERY REQUEST WAS A NEW RENDEZVOUS.** 173 `dial ... stream N` lines for 173 requests. This is
the per-request-connection shape the clearnet Electrum transport was cured of on 2026-09-01,
arriving on the Tor transport by the other door: `waNetDeliver` closed the stream the moment its one
line landed. The stream is kept now, exactly as `sWaSock` is - reused while it is the stream the
settings name and OnionXT still reports it connected, dialled afresh otherwise - and three things had
to move with it, each of which was harmless while a stream carried one reply. The line splitter took
the FIRST line and emptied the buffer, which on a kept stream would have dropped a reply arriving in
the same chunk as a pushed `headers.subscribe` notification (a block landing mid-sync); it delivers
every line and keeps the remainder. The pump cleared the buffer before each request, which would
have handed the tail of a straddling notification to the next reply as a line that parses as
nothing; on a kept stream a partial line belongs to the stream. And a stream the server drops while
nothing is waiting on it - a thing that could not happen before - is now forgotten and logged, not
counted as a failure of the sync. The gate drives the whole life of a stream through a MODELLED Tor
(OnionXT's five stream commands intercepted at statement level, `oxStreamState` answered from the
model, `the result` the way the real ones set it), because OnionXT's own dial goes to `open socket`
and nothing headless can run that. The reuse has not run on an engine.

**Three log lines, from reading this one.** `waNetAbort` now says what it threw away (the log's
request ids jumped 73 to 84 across a wallet switch, with nothing saying why); the broadcast reply's
`<-` line no longer echoes the whole raw transaction that the `->` line above it already carries;
and the accepted txid goes into the log on both transports, because the status line is not what
gets pasted back and this log's only record of its txid was the fee-bump bookkeeping line. Also
the one `error:` in the log - "this wallet has no address to pay", from Add self on the public test
seed mid-sync - now says why (everybody has used every address that seed derives) and what to press.

### 2026-09-03, the seventh engine log: one stream per sync, seen

The reuse of the entry above ran on the engine the same day: one `dial` line, then the test's tip
and every one of the sync's requests down stream 1; a wallet action mid-sync (the new abort line
names what it dropped: one in flight, one queued) closed it and the next sync dialled stream 2 and
ran to the end on it; and a `headers.subscribe` push arrived on the idle stream afterwards and was
logged and ignored - the notification guard's first engine sighting on the Tor transport. Nothing
failed. The label moved; the only thing left unproven on this transport is mainnet on port 110.
Esplora over Tor in the same log dialled a stream per request, as it is designed to (HTTP/1.0 with
Connection: close), which now makes Electrum the cheaper Tor transport, and the Network screen's
privacy text says so - the difference is one a person choosing a backend should be told.

### 2026-09-03, after the seventh log: fewer requests, faster replies, and a menu that copies

Asked for in three words - "as efficient as we can" - and one defect: the context menu did not copy
the selected address.

**THE MENU ROUTED THREE ITEMS TO THE WRONG BUTTON, and the gate could not tell.** "Copy selected
address" routed to `ad receive`, which is the receive-chain TOGGLE; "Prove this address" to `ad scan`,
a sync; "Copy selected outpoint" to `cn detail`, the coins detail FIELD, which no click handler
answers. The menu gate proves every route names a control the registry carries, and every one of
those does - so a right-click copy switched the chain view and reported nothing. The three are the
router's own now (copy the selected address; "Sign a message with it", which fills the Tools address
box and shows Tools; copy the selected txid:vout), and the gate drives each against the row the
right-click selected rather than checking that the route resolves. The lesson is the gate's: "names a
real control" is not "does what the label says", and the second question needs the selected row and
the clipboard, not the registry.

**ESPLORA OVER TOR KEEPS ITS STREAM TOO.** HTTP/1.0 with Connection: close was chosen so a reply
ended when the peer closed and there was no framing to get wrong; the price, visible in the seventh
log beside an Electrum sync running down one stream, was a rendezvous per request. It is HTTP/1.1
keep-alive now, and `waHttpFeed` is the framing: a phase machine over the receive buffer that
consumes what it has understood (Content-Length; chunked with extensions and trailers; a reply that
says close forgets the stream after delivering; a reply with no framing at all falls back to the old
close-delimited read and is not kept), checks the status at the head so a 404 is refused before its
body is read, and reports a framed reply the peer cut short as a failure rather than a short answer.
The gate drives every shape through the modelled Tor, split at the worst byte boundaries. The
keep-alive path has not run on an engine; the fallback exists because which framing the mirror sends
is not known from here.

**A SYNC ASKS ONLY FOR WHAT IS STALE.** Every engine log shows the Test button fetching the tip
seconds before the sync fetched it again, and the fee estimate asked for on every sync. A tip under
thirty seconds old and a fee estimate under ten minutes old are kept (`kWaTipFresh`, `kWaFeesFresh`;
cleared on a backend or network change), and the sync's log line counts what it queued instead of
adding two to a formula.

**AND THE REPLY PATH DOES LESS PER REPLY.** Every reply repainted the whole screen - a rebuild of the
visible table and a walk of every coin and history row for the balances, fifty times a sync; it is
once a second and when the queue drains now, with the rail's balance painted every time. The next
request left on the next 250 ms tick; it leaves on the next event-loop turn (`waPumpNow`, deferred
rather than called from inside the transport's read callback). And the Network screen's raw-reply
window concatenated a two-megabyte history onto the field before keeping its last 6000 characters.
None of this has an engine pass; the gate holds the queue counts, the immediate pump and the menu.

**AND AN ELECTRUM SYNC SENDS ITS REQUESTS IN BATCHES.** JSON-RPC allows an array of requests
answered by an array of replies, each carrying its id, and the reference Electrum clients batch by
default. The pump gathers a contiguous run of same-kind requests - the histories a sync queues, then
the unspent-output requests that follow them - into one line of up to twenty (`kWaBatchSize`), so
forty addresses are two round trips instead of forty and a Tor sync is mostly no longer waiting.
`waBatchApply` hands each element to its member by id through `waElectrumApply`, the per-kind half
of the old apply handler, which the single-reply path now reaches after its id and error checks.
Three ways a batch goes wrong, each pinned in the gate through the modelled Tor: a server that
answers something other than an array (an error object, typically "Invalid Request") has the batch
split into its members at the front of the queue and is asked singly from then on (`sWaBatch`,
forgotten on a backend change); a member's own error element counts as that member's failure and
nobody else's; a member the server leaves unanswered is asked again alone. A batch that fails in
transit is split rather than retried whole, because whatever refused it is likelier to refuse it
again, and the members then get the ordinary once-more each. The log carries a batch as its shape and
id range rather than twenty script hashes. Whether the mirror takes a batch is not known from here -
the fallback is what makes that safe to find out on an engine.

### 2026-09-03, the eighth engine log: one stream, five round trips

The transport changes of the entry above ran the same day. Esplora over Tor: one `dial`, then
fifty-one requests down stream 1 on HTTP/1.1 - so whichever framing the mirror sends, `waHttpFeed`
read it, and the fallback never fired. Electrum over Tor and over clearnet: the tip, the fees, two
batches of twenty histories and one of nine unspent-output requests, every batch answered - so both
of Blockstream's servers take a JSON-RPC batch, and a sync of fifty-one requests was five round
trips. Nothing failed, and nothing in the log needed the split path.

Two things in that log were worth a change. The tip and the fee estimate went alone and cost two of
the five round trips, because the pump batched only a run of the SAME kind; a batch is now any run of
requests but a broadcast (a broadcast stays its own line so its acknowledgement is its own line), and
`kWaBatchSize` is twenty-two - the tip, the fees and one chain's twenty addresses, so a fresh sync is
three round trips: receive chain, change chain, unspent outputs. Not larger, because a reply is one
line and some servers cap what they will send on one (ElectrumX's default is a megabyte), and the
split-on-failure makes that a slow sync rather than a lost one. And the receive buffer was rebuilt
on every chunk - `put sWaBuffer & pData into sWaBuffer` copies the whole buffer, so a two-megabyte
history arriving in Tor-cell-sized pieces was a gigabyte of copying; it is `put pData after`, which
the engine extends in place. The mixed batch is gated (five kinds in one line, answered out of order,
with the tip and the fees landing from inside it) and has not run on an engine.

Not visible in that log, and so still unseen: the stale-answer skip (every sync followed a backend
change, which forgets the tip and fees on purpose), the paint and pump timing, and the three menu
items.

### 2026-09-04, Update from main

Asked for as a button, a menu item, or both, "to make updating seamless": fetch the latest script
from `main`, set it as the stack script, fire `preOpenStack`. Both, and the fetch is `get URL` as
asked. What the design had to settle first is what makes a self-replacing wallet honest.

**THE WALLET MUST SURVIVE THE SWAP.** Setting a stack's script reinitialises every script local, so
the seed, the coins and the settings in memory would simply vanish - the pump re-arm entry above is
the same fact from the other side. The carry is the wallet-file text (`waSerializeWallet`, the one
serialisation the wallet already trusts) plus `update:*` rows for the Network settings and the
screen, parked in a stack custom property for the milliseconds between the old script's last
statement and the new script's boot. A property rather than a global, because the family's
interpreter models script-level `local`/`constant` and stack properties and not `global`, and a carry
the gate cannot drive is a carry nobody has run. `waBoot` reads it back LAST, so it lands on a booted
wallet, clears it, and logs the version it came from; `closeStack` clears it too, so a swap that never
came back cannot leave a seed in a property of a saved stack. The log survives on its own: it is a
field, and `waBuild` is guarded by `uUiVersion`, so nothing is rebuilt.

**WHAT PROVES THE FETCHED TEXT IS THIS WALLET.** `waUpdateCheck` takes the fetched text AND the
running script, so it can be driven with any two texts: the first line must match; the size must be
within a half and three times the running script's (a truncated download is the likely failure); it
must declare `kWaVersion`, carry `waUpdateRestore` (or the wallet would not come back) and an
`openStack` (or it could not boot); and a copy identical to the running script is refused as already
current. What it accepts is offered with its version, size and SHA-256 beside the running version,
and nothing happens until Update is pressed. That is the whole of the trust model and it is stated on
the Settings panel and in docs/wallet.md: whoever writes to `main` writes in front of your keys, and
so does anyone who can answer for the host if TLS is not doing its job.

**THE SWAP IS THE ONE UNGATED PIECE.** `set the script of this stack` from inside one of that
script's own handlers, then `preOpenStack` and `openStack` sent to the new script on a timer - engine
work nothing headless can model, so `preOpenStack`/`openStack` now pin the defaultStack (they are
timer-reached for the first time) and the label says the swap has not run on an engine. A script
that does not compile leaves the old one running, restores the pump and says so; the throw for that
sits AFTER the try, per the checker's rule, which flagged the first draft. Everything else is gated:
seven refusals by name, the accepted copy's version and hash, the carry's rows, the restore on a
one-key wallet with the stack property cleared and the log line written, a carry that will not load
reported rather than half-applied, and the route from the button and the menu item.

kWaVersion moved to 1.1.0 with this, so the first update anyone runs has a version to name.


### 2026-09-04, a note to the chain: OP_RETURN outputs, and reading data back

The first of the "modern Bitcoin" additions, and the shape was the decision: a note is a LINE in the
Pay-to box (`note: text`, `data: hex`), not a screen, and it becomes a payment record whose script is
`OP_RETURN <push>`, whose value is 0 and whose KIND carries its byte count - `nulldata:N` - because
every caller of wallet-core sizes outputs by type and a data output's size is not a property of its
type. That one choice is why nothing downstream changed: `cwOutputBytes` and `cwDustThreshold` learned
the parametrised kind (0 is the threshold: there is no spend to price), and selection, the review,
signing, the PSBT and the fee bump all saw a payment. One per transaction, because a second OP_RETURN
output is what most nodes refuse to relay; over eighty bytes is warned about, not refused, because
Bitcoin Core 30 relays far more and whether a longer note reaches a miner depends on whose node it
meets; the hard cap is the encoder's (PUSHDATA2). wallet-core gained `cwOpReturnScript`,
`cwOpReturnData`, `cwPushLen` and `cwScriptItems` - the one script reader the decoders now share,
one item per line - each vector-gated against the reference across every push form (direct,
PUSHDATA1, PUSHDATA2), with a push that runs past the end refused. Inspect reads an OP_RETURN
output back as text when every byte is printable UTF-8 and as hex otherwise, and reads an Ordinals
inscription out of a witness: the OP_FALSE OP_IF "ord" envelope, the content type after a push of
0x01, the body after OP_0 across as many pushes as it takes - which is the read half of ordinals and
costs a parser, not a protocol. Two things the interpreters taught while it was written: the base
interpreter models `repeat for each item` and not `for each line` (core code loops by index), and
`pI` is the engine token `pi` (the checker's rule). Gated end to end: the review names the output,
the signed spend decodes to exactly one OP_RETURN of value 0 carrying the bytes, the wallet's vsize
agrees with the oracle's for a spend with a data output, the four refusals by name, the long-note
warning, and the inscription reader on an envelope the oracle builds. The note output and the
inscription reader have not run on an engine.

### 2026-09-04, testnet4 and BIP-329 labels

**TESTNET4** is a fifth column in wallet-core's network tables with testnet3's value in every row -
prefixes, WIF, extended-key versions, coin type - because that is what testnet4 is: a new chain
(Bitcoin Core 28) with the old bytes. The vector gate re-derives every row against the reference,
which gained the same entry with the same comment. The app is where the chains differ: the Esplora
root is `/testnet4`, Blockstream's mirrors (which index testnet3) are refused for it by name with
mempool.space - already the built-in second Esplora host - named as the remedy, and both built-in
Electrum servers are refused. The Wallet screen's network row is five buttons now. Testnet3 is being
retired, which is the reason this landed ahead of the bigger items.

**BIP-329 LABELS.** One JSON object per line; address labels go out as `addr` records, frozen coins as
`output` records with `spendable: false` (the one BIP-329 field this wallet's freeze maps onto exactly),
both come back, and the types it keeps no home for are counted and skipped rather than refused - a
label file from another wallet should always import. The file sits beside the wallet file, named for
it, so there is no dialog to model. Gated: the round trip with an escaped label, the BIP's own six
example lines (one kept, one frozen and labelled, four skipped), a non-JSON line refused by its
number, and Export without a wallet path refused. Neither has run on an engine.

### 2026-09-04, child pays for parent

The bump a replacement cannot make. `waBumpFee` used to explain, at length, why a transaction this
wallet did not build could not be bumped here; the honest half of that explanation was that a
replacement needs the inputs, and the missing half was that a CHILD needs only an output. If the
wallet holds an unconfirmed coin of the parent - which it does for every incoming payment, the case
RBF can never touch - `waCpfpBuild` spends it back to the next change address at a fee that carries
both, so the pair clears together. Three things had to be decided rather than coded. The parent's size:
from its bytes (the same fetch Inspect makes, and the wallet asks for them and says "press Bump again"
rather than guessing) or from the weight Esplora reports, which `waMergeHistory` now keeps. The
parent's fee: Esplora says it, Electrum's history does not, and when it is unknown the child pays for
both sizes in full as if the parent had paid nothing - an overpayment, stated in the detail, rather
than a guess. And the child's own floor: never below one sat/vB of its own bytes. It signals RBF and
is recorded with no payees and its whole value as change, so the existing replacement path can raise
it. Gated against a parent the oracle builds, so its txid and size are real: the child spends exactly
that output to an address of this wallet, its fee is the pair's shortfall at the asked rate within a
few sat, the fee-unknown case pays in full, the size-unknown case asks for the bytes and queues the
request, and a rate that would leave dust is refused. Not run on an engine.

### 2026-09-04, BIP-322 signed messages

The wallet's own refusal named the gap: "Bitcoin Core signs those with BIP-322, which this wallet does
not implement." It does now, for the two single-key shapes the 2011 format cannot or should not
carry - taproot always, native SegWit by choice - and the design point is that BIP-322 is a SPEND: a
virtual `to_spend` pays `tagged_hash("BIP0322-signed-message", message)` to the address, a virtual
`to_sign` spends it to OP_RETURN, and the signature is `to_sign`'s witness stack, base64. That is why
it cost so little: `cwBip322Digest` is `cwSighash` over two transactions the wallet already knows how
to build, the P2WPKH witness is `cwSignInput`'s and the taproot witness is `cwSignTaproot`'s, and the
verifier checks the witness the way a node would (key matches the program, then `cxVerify` on the
BIP-143 digest; or `cxSchnorrVerify` on the BIP-341 digest against the output key). Three small
pieces were new: a witness-stack encoder and decoder, a DER-to-compact converter for `cxVerify`, and
the reader's rule that a 65-byte signature is the 2011 format and anything else is BIP-322. The
reference gained the same four functions; both sides sign deterministically, so the vector gate
compares signatures byte for byte, and it also holds the BIP's published message hashes, `to_spend`
txids and signatures for its test key. Legacy and nested addresses stay 2011, which is what the world
expects of them, and a taproot signature offered against a P2WPKH address is refused with the
reason. Not run on an engine.

### 2026-09-04, silent payments (BIP-352), sending

The address is the whole design problem: `sp1...` is two public keys, and the output that pays it does
not exist until the funding coins are chosen, because it is derived from THEIR private keys and the
smallest outpoint. So the Send screen's record for such a line carries the keys and no script, sizing
and selection run on its taproot kind, and `waSpResolve` fills the script in between selection and
the outputs loop - the one place in `waBuildSpend` where the inputs are known and nothing has been
built from the outputs yet. That is also why it is refused as a PSBT, on a watch-only wallet and on
a multisig wallet: the first two have no key to derive with, the third has inputs the BIP excludes.
Three things in wallet-core were decided rather than coded. The address needs bech32m under the
BIP's own 1023-character waiver, and coinxt's decoder enforces BIP-173's 90 as it should, so
wallet-core carries its own polymod over a list rather than loosening the library. The key sum is
done in hex mod n by two nibble loops, because `cxSeckeyTweakAdd` refuses a zero result by design and
the BIP's vector "intermediate sum is zero but final sum is non-zero" is precisely the chain of
tweak-adds that would refuse half way. And the K_max refusal counts the groups BEFORE deriving,
so the vector that asks for 2324 outputs costs nothing. The gate holds every stage to the BIP's
published sending vectors, trimmed into `tests/bip352-sending-vectors.json` with the receiving half
dropped and the trimming recorded in the file; which inputs take part is the receiver's rule, so the
oracle carries the receiver-side extraction (the malleated-P2PKH window scan, the NUMS-point skip,
the annex) and the vectors' own input lists hold IT. The same day the BIP-322 gate learned its lesson
one entry up: the two published signatures it held were written from memory and were wrong, and
the BIP's text carries none - they live in `bip-0322/basic-test-vectors.json`, four per key, and
those are what it holds now. Not run on an engine.

### 2026-09-04, Runes, read only

The reader Inspect gained is small and the reason it is small is worth keeping: a runestone is a
handful of LEB128 varints in an OP_RETURN, but they are 128-bit, and a double-based reader would
render a rune name or an amount wrongly without ever erroring. So wallet-core carries decimal-string
arithmetic (multiply-add, divmod by a small number, add, subtract-one, compare) and every rune number
stays text from the varint to the screen. The cenotaph rules are the specification's, applied in its
order - a non-push opcode, a bad varint, a truncated field, the edict rules, the flags, the pointer,
the even tags that need a flag they do not have - and a malformed runestone is still returned with
its fields, as the specification requires, with the flaws named so Inspect can say what burns. The
gate uses the reference's own test cases, mined out of ord's `rune.rs` and `runestone.rs` rather than
invented, and a Python oracle that reads the same bytes. Nothing here writes a runestone. Not run on
an engine.

### 2026-09-04, inscriptions by commit and reveal

The one-leaf script path was the last taproot capability the wallet lacked, and inscriptions are its
most legible use: the commit hides the envelope behind a key, the reveal spends through the leaf and
puts it on the chain. Every primitive was already in coinxt - the tweak with a merkle root, the control
block, the script-path sighash with a leaf hash - except one, and it is the instructive gap: coinxt's
`cxTapLeafHash` refuses scripts of 253 bytes or more because it models a one-byte compact size, and an
inscription body is precisely the script that is longer, so wallet-core carries a leaf hash with a real
varint and the gate checks a 600-byte leaf against the oracle's. The wallet side is ONE button with two
phases, and the state that makes the second phase possible is an ADDRESS RECORD: the commit is appended
to the wallet's own address list carrying its leaf script, leaf hash and control block, so sync watches
it like any address, the coin arrives like any coin, and `waSignSpend` gained one branch that signs a
coin through its leaf. Two consequences were designed rather than discovered. The recipe (receive index,
type, body) is saved with the wallet and re-attached after EVERY derivation, because `waDeriveAddresses`
rebuilds the list from scratch and a commit that vanished on a gap change would be a funded output the
wallet had forgotten how to spend. And a commit coin funding a silent payment tweaks by the leaf hash,
not the empty root, because BIP-352 wants the key that spends the output. The boot gate drives both
presses on the fixture wallet, plants a coin on the commit, and rebuilds the reveal signature from the
same key byte for byte; Inspect reads the envelope back. Not run on an engine.

### 2026-09-04, coins locked until a block

Once the inscription commit existed as an ADDRESS RECORD carrying a leaf, a timelock vault was a second
recipe kind and one new leaf, and the record store was generalised rather than duplicated (`sWaLeaves`,
kinds "inscribe" and "lock", saved as `leaf` lines). The design points are the two the record makes
easy to get wrong. The internal key is the NUMS point, not the receive key: with the receive key there
the lock would be a suggestion, because the key path would still spend. And a locked coin is WITHHELD
from selection while the tip is below its height, not merely warned about, because the alternative is
a signed transaction every node rejects - and offered from the height on, with `waBuildSpend` raising
the locktime to the coin's height and the review saying it did; the sequence numbers the wallet already
uses are both below 0xffffffff, which is what lets a locktime bind at all. `cwScriptNum` is the small
piece that had to be right (minimal little-endian with a sign bit; 900000 is `a0bb0d`), and the gate
pins its edge values against the oracle. Not run on an engine.

### 2026-09-04, Lightning invoices read out

Reading a BOLT11 invoice cost almost nothing because the silent-payment work had already paid for
the expensive part: a bech32 decoder with the length cap a parameter. What was new is small and
worth naming. The amount is in BITCOIN with a multiplier letter, and pico-bitcoin is a tenth of a
millisatoshi, so the amount is decimal-string arithmetic with the divide-by-ten check the
specification's "sub-millisatoshi precision" example exists for. The fields are 5-bit values whose
byte conversions differ by ONE rule - a field drops its incomplete tail, the signed message zero-pads
its own - and the two converters are written twice rather than parameterised so a reader sees which
is which. The signature is coinxt's recoverable form byte for byte (64 + recovery id), so the payee
is `cxRecover` and a compress; and when the invoice names its node key the specification wants the
signature checked against it AND canonical, which is the only place this wallet looks at high-S. The
vectors are the specification's examples with expected values taken from its own breakdowns, held in
`tests/bolt11-vectors.json`; the high-S recovery example recovers to a different key than the one
every other example signs with, which is that example's point, and the file records the key it
recovers to rather than the one a reader might expect. Not run on an engine.

The same day's offline finding, recorded here because it is the kind that hides: the vector gate's
wiring declared `cxEcdh`'s output as 32 bytes where the native returns the 65-byte point, so every
offline ECDH had been a BADLEN refusal since the wiring was written - unnoticed because nothing in
the gates had called it until BIP-352 did.

### 2026-09-04, what stopped silent-payment receiving, for whoever picks it up

The sending side is done and gated; the receiving side was designed the same evening and stopped at
one line. A receiver computes A_sum, the sum of the eligible inputs' PUBLIC keys, and that is point
addition - `secp256k1_ec_pubkey_combine` - which coinxt does not expose. Everything else it needs is
here: the input-key extraction (`sp_input_pubkey` in the oracle, mirrored by the vectors' own
input lists), the scan and spend keys at `m/352'/coin'/0'/1'/0` and `.../0'/0`, the shared secret by
`cxEcdh`, the candidate outputs by `cxPubkeyTweakAdd`, and a found output's spending key by
`cwScalarAdd` (which then signs UNTWEAKED - a silent payment output is the raw key, not a BIP-341
tweak - so the record needs a flag `waSignSpend` does not yet read). Doing point addition in script
was costed and rejected: a field inversion is ~400 big multiplies, minutes in the offline
interpreter per input, which would make the gate unrunnable. The honest next step is the native
handler, with `check-binary-freshness.py` holding rule 5, and then the receiving vectors already in
the fetched file (`receiving[*].given.key_material` and `expected.outputs`, dropped from
`tests/bip352-sending-vectors.json` deliberately) become the gate.

### 2026-09-04, the checksum got five times faster, and why that mattered to the gate

The long bech32 decoder did its 30-bit xor one bit at a time (thirty tests, each two divisions),
which was fine for a 116-character address and was not fine for a 765-character invoice, where the
offline vector run spent twelve minutes per block on checksums. It is now six lookups in a 1024-entry
table of 5-bit xors (`kCwXor5`, two decimal digits per entry), and the generator bits are tested by
halving the top five bits rather than by a power-of-two per bit. Same answers on the same vectors
(the sp address round-trips, the invoice recovers the same payee), a 585-character invoice in 14 s
where it took the best part of a minute. The lesson is the family's usual one about the offline
interpreter: it is where the cost of an arithmetic idiom shows up first, and a block that takes
twelve minutes there is a gate people stop running.

### 2026-09-04, "I do not see any UI for the new features", and why the UI version is a fingerprint now

Every control added between 2026-09-02 and 2026-09-04 was built, placed and gated, and none of it
appeared in the maintainer's stack. `waBuild` rebuilds the window only when the stack's stored
`uUiVersion` differs from `kWaUiVersion`, which is what makes a reopened stack open instantly, and
that constant had read `coinwallet-1` since the day the wallet was written. A fresh paste built
everything; a stack that was reopened, or replaced its script with Update from main (which fires
`preOpenStack` and so `waBuild`), kept the window it had. The boot gate could not see it because it
boots fresh every time. The fix is not a bump - a bumped number is a hand-copied number, the failure
this file records more than any other - but a DERIVATION: `kWaUiVersion` is `ui-` plus twelve hex
digits of the SHA-256 over every `command waBuild*` handler, `tools/check-wallet-ui-version.py`
refuses a stale value and writes the right one with `--fix`, `build-all.sh` runs it, and the boot gate
pins the mechanism the only way that matters (a control removed comes back when the stored version is
stale, and stays away when it is current). The same day the About text gained a "where the new things
are" section and the Tools note the `inscribe:` and `lock:` recipes, because a feature reached only
by a line format nobody is told about is a feature that does not exist. Not run on an engine.

### 2026-09-04, two screens, a rail of twelve, and tooltips: "this needs to be an impressive display"

The maintainer's second reading, after the rebuild fix, was that the new features were not
self-explanatory, and that was right: inscriptions and timelocks lived behind `inscribe:` and `lock:`
lines in a paste box, silent payments and notes behind line forms in the Pay-to box, and nothing
on any screen said so. The wallet now has an ORDINALS screen (content type with quick picks, body,
a size line that prices the reveal as you type, two NUMBERED buttons, a table of every inscription
with its state read from the coins and spends, a reader for any transaction's inscription or
runestone) and a VAULT screen (a height or +1 day/week/month/year from the tip, a line saying how far
away that is, Prepare, a table of every vault with locked-with-N-blocks-to-go or UNLOCKED read from
the tip). The rail grew to twelve at a 26-pixel pitch; the router, the sweep, the menus and every
`1 to 10` loop follow `kWaScreenCount`. Every button on both screens and the rail carries a tooltip
(`waTips`, the wallet's own pass after the build, since the kit sets none), the Pay-to box explains its
line forms on hover and has an Add-a-note button, and the old line forms pasted on Tools are CARRIED
to their screens filled in rather than refused. The commit, reveal and lock bodies became functions
that return their report, so a screen and a line form share one core. The boot gate drives the
numbered buttons, the quick picks, the tables' states, the tooltips, the rail geometry and the
carrying. Not run on an engine.

### 2026-09-04, the update check was fooled by its own source, and the gate that found it had never run

The Update-from-main boot block was committed on the maintainer's "commit what you have" and never
driven to the end, so its first complete run was in CI, two days later, and it found three things.
Two are the wallet's. `waUpdateCheck` looked for `constant kWaVersion = "` anywhere in the fetched
copy and for `command waUpdateRestore` and `on openStack` as substrings; the handler's OWN SOURCE
carries all three as literals, and `command waUpdateRestoreX` contains `command waUpdateRestore`,
so a copy with no version declaration read as "unreadable" instead of "missing" and a copy that had
lost its restore handler or its openStack was OFFERED. The version is searched at a line start now
and the handlers as whole lines. The third is the gate's: it asked `ip.call` for `cxSha256`, which
the driver cannot reach (natives resolve from script, not from Python), so the block crashed on its
last check. The same run showed the 9c header-notification check reading an empty tip, because its
two Electrum deliveries had no trailing newline and the line-framed receiver rightly held both in
its buffer; the fixture now sends lines, as every server does. Not run on an engine.

**The second spend reused the first one's coin (engine log, 2026-09-03).** The
autotest script built a silent payment and, sixty seconds later with no sync
between, the funding of an inscription commit - and the second transaction spent
the same input as the first. The server took the first and refused the second
with `insufficient fee, rejecting replacement`, which is exactly right: the
wallet had chosen from a coin list that was true when the last sync answered and
not since, and nothing in it remembered what the wallet itself had just done.
`waNoteBroadcast` runs on every accepted broadcast now, from both transports: it
decodes the raw it sent, marks each input as spent by that txid (`sWaSpentBy`,
memory only), and lists each output that pays an address of ours as a coin at 0
confirmations - so a second spend has the change to draw on. The selector, the
CPFP coin finder and the balance skip a marked coin and the Coins screen shows
it as SPT. The backend outranks the memory in both directions: `waMergeUtxos`
un-marks a coin the backend still lists and says so in the log, and a
replacement re-marks the inputs and voids the coins added from what it replaced.
The same log's Bump on the wallet's own note transaction went the
child-pays-for-parent way (no change to shrink) and asked the server for the
parent's bytes, which the spend record already held; `waBumpFee` fills the size
and the fee from the record first. The boot gate drives all of it through
`waNetApply` with modelled acceptances. Not run on an engine.

**A third failure in that log is still open: paying the vault address.** The
autotest asked to pay 30000 sat to a freshly prepared timelock address and the
selector answered `insufficient funds` over 451087 sat confirmed. The report was
cut at 120 characters by the autotest itself, so what the advice said after
"confirmed" is not in the record. It does not reproduce headlessly: the selector
clears a five-coin p2pkh pool of that total for that target at rates 2 and 5,
and the booted fixture wallet, asked to pay 30000 sat into a timelock address it
had just prepared, builds and signs the spend at both rates (the review labels
it a self-send, locked until its block). The autotest now reports 400 characters
of a refusal instead of 120, so the next engine run carries the rest of that
advice line - frozen, unconfirmed, or something else - and this entry is here so
the failure is not mistaken for the two above.

**A refused batch is halved, not abandoned (2026-09-03).** The same engine log
had the onion Electrum server close the connection on the sync's first batch of
22, after which `waBatchSplit` switched batching off and the sync asked its 41
requests one at a time - 41 Tor round trips where two or three lines would have
done. ElectrumX caps the SIZE of a line, and 22 histories of a busy wallet can be
over it where 11 are not, so a refusal now puts the members back and tries half
as many on the next line (`sWaBatchCap`, read by `waBatchCap` in the pump),
halving again on each refusal; when the half would be one, batching is off for
that server as before, and `waSetBackend` forgets the cap with the refusal. The
boot gate's Tor section drives four requests refused to two, two refused to
singles, and the forgetting; the section passed in isolation, 114 checks with
the boot. Not run on an engine.

**The marks moved from acceptance to queueing (the 2026-09-03 evening run).** With
the broadcast memory in place, the autotest queued the note's fee bump, then built
the silent payment and the commit funding one second apart - on the ORIGINAL
note's change, because the bump was still behind Tor and its acceptance is what
voided that change. Both children were refused by every node (`400 Bad Request`),
and the log showed the status line and two headers, not the reason. Three
changes: `waBroadcast` calls `waNoteBroadcast` when it QUEUES (the acceptance
call stays, idempotent, and logs "reserved when it was queued"); `waNetFail`
calls `waUnnoteBroadcast` on a broadcast's final failure, which hands the
reserved coins back and drops the outputs it had added; and `waBumpFee` refuses
to replace a transaction whose output a queued spend of ours already uses
(`waPendingSpenderOf`), naming the child. The Tor Esplora reader now HOLDS a
non-2xx status (`sWaHttpBad`) until the body is in and refuses with the body's
first 240 bytes, so the reason reaches the log. The same run proved the batch
halving (22 refused, then six lines of 11 answered) and the vault payment that
had failed the day before went through. Both windows extend themselves now too:
`waNextChangeOrMore` for change, after the harness's two-address prefill showed
the change chain running out the way the receive chain had. Not run on an
engine since.

**A failure only CI sees is the harness's own copy (2026-09-03).** Four boot-gate
checks failed in every CI run from 595 on and passed in every local run, under
Python 3.11 and 3.13 alike, with no relevant diff between the green and red
commits. The difference was `tools/test-wallet-boot.py`: its clean pass runs the
gate on a COPY with `kWaPrefill` cut from 20 to 2, so the wallet has four
addresses, the inscription commit takes the last unused receive address, the
vault lock has none and throws, and everything downstream of that state (the
vault table, a version-2 transaction that made the "different bytes" fixture a
no-op, the update restore) reads differently. The rule for next time: when CI
and a local run disagree, run the gate the way CI does - `test-wallet-boot.py`'s
clean copy, not the shipped file - before looking anywhere else; the scratchpad
drivers now take that copy as their path. What it found was real either way: a
wallet that had prepared a few leaves ran out of receive addresses and sent the
person to another screen, and the change chain ran out the same way, so both
windows extend themselves now (`waNextUnusedOrMore`, `waNextChangeOrMore`); the
update restore lost the carried server twice over (loading reset it, then the
Network fields overwrote it) and keeps it now; and the fixture flips the version
away from whatever the transaction has. The whole Send-to-audit region and the
update block pass on the prefill-2 copy: 561 and 43 checks. Not run on an engine.

**The tenth engine log (2026-09-03, 19:42 EDT): the whole chain phase green.**
The autotest script, on a p2pkh testnet wallet over Electrum on Tor, reported 41
passed, 0 failed, 4 skipped in 248 seconds - the first run in which every chain
step went through without waiting on the network. What it proves, by the log:
the batch halving (a batch of 22 refused by the onion server, then every line of
11 answered; a sync of 41 requests in eight round trips instead of 41); the
queue-time reservation (every acceptance says "its coin(s) were reserved when it
was queued"); a replacement voiding the replaced transaction's coins and the
next spends drawing on the replacement's change; the commit coin seen at 0
confirmations from the wallet's own memory and the reveal signed and accepted on
it - a real inscription on testnet, f002bfb2...i0; and the vault paid and its
coin withheld from the selector. Labels flipped in docs/wallet.md accordingly.
NOT exercised by that run, and still unproven on an engine: the release of a
refused broadcast, the refusal to bump a parent whose change a queued spend
uses, a refusal's body reaching the log, the child-pays-for-parent pricing from
the spend record (the note had change, so the bump went the replacement way),
and the windows extending themselves (receive index 14 was still inside the
derived window). The four skips are the autotest's own: BIP-322 on a p2pkh
wallet, spending the vault after its height, CPFP on a foreign transaction, and
the update swap.

**The eleventh engine log (2026-09-03, 20:13 and 20:30 EDT): the second autotest.**
Two runs of a second button script, each forcing a path the first autotest never
reached. Proven on Electrum over Tor: a broadcast the server refuses in its reply
hands its coin back (the balance returned to the sat) with the node's reason in
the log; a parent whose output a queued child spends is refused a bump, naming
the child; a change-less sweep is bumped by a child priced from the spend record
without a round trip, and the child was accepted. Found by the same runs, and
fixed: (1) every timelock said "key at receive index 14", thirty times - a leaf
never marked its key's address as used (`waUsedAddresses` counts leaf bases now),
and once the base addresses DID run out, `waNextUnused` handed back the first
LEAF RECORD as the next unused receive address (leaves sit on chain 0 with an
unpaid address; they are skipped now); (2) the release of a reply-refused
broadcast passed the log's label to the decoder instead of the bytes, so it never
ran - the gate leg written for it caught that before the engine did; (3) the pair
rate in the CPFP report rounded up ("about 4" for 3.0), and its first fix used
`round()`, which the engine has and the gate's interpreter does not; (4) this
testnet Electrum server ACCEPTS a 0.1 sat/vB transaction, so the script's
refusal is a signed transaction whose locktime is changed afterwards, which no
node accepts. The script's own case-insensitive `contains` matched the release
line ("...failed;") for "FAILED" once; it matches "FAILED: " now. Still unproven:
the window extending itself (the fix above lands after these runs), the backend
un-marking a coin, and Esplora's 400 body in the log.

**The twelfth engine log (2026-09-03, 21:54 EDT): the second autotest, fourteen
of fourteen.** The same script on the wallet as fixed by its second run, on
Electrum over Tor: the refused broadcast released with the node's reason, the
bump refused naming the child, the change-less sweep bumped by a child priced
from the record ("about 3 sat/vB" for 1152 sat over 384 vB, the integer-tenths
fix), and - new - BOTH windows extending themselves: the change chain while
child B was built ("derived a further window: every change address was used"),
and the receive chain on the twenty-seventh timelock, at index 40, after locks
took indices 14 to 39 one each (the leaf-skip fix of the entry above, seen
working). Every queued transaction was accepted by the network after the
script finished - the parent, the child, the sweep and the CPFP child - so the
pair is real on testnet. The one wording fix from reading the log: the release
line was followed by "FAILED: could not read the answer to broadcast: the
Electrum server refused: ...", and the answer had been read perfectly well;
a refusal is logged as "broadcast: the Electrum server refused: ..." now, with
the old prefix kept for a reply that does not parse. Still unproven: the
backend un-marking a coin it still lists, and Esplora's 400 body in the log.

### 2026-09-04, Bitcoin Core as a backend: the plan's phase 1, and the scan

`docs/bitcoin-core-plan.md` was written the day before as a plan and this is
its first code: a `core-rpc` transport beside the four public ones, on the
Network screen as "Bitcoin Core: your own node, over RPC", with the cookie
and rpcauth boxes, the remote-host tick, and a scan of the node's UTXO set in
place of the per-address requests. Four decisions are worth the record.

**IT RIDES THE CLEARNET SOCKET PATH, AND ONLY THE BYTES DIFFER.** Core's RPC
is HTTP on a plain socket, kept alive between requests, which is exactly what
the clearnet Electrum transport already owns (one socket, the id as the
correlation, the write-failure requeue, the deadline, the close on failure);
`waNetStart` dials the same way and `waSockSend` dispatches to `waCoreSend`.
The reply framing is two engine reads rather than a phase machine, because
Core never chunks: the head until the blank line, then the body for exactly
its Content-Length. The write-failure branch was extracted (`waSockWriteFailed`)
so the two protocols on one socket cannot drift about it, which is the
per-transport-validation lesson of 2026-09-01 applied before the fifth
instance rather than after.

**THE CHAIN IS ASKED FIRST, EVERY TIME IT IS NOT KNOWN.** The port table is
Core's own and is still only a guess about what a person runs where, so the
sync puts `getblockchaininfo` ahead of the scan whenever the node's chain is
not known, and a mismatch empties the queue, is remembered (`sWaCoreChain`),
and is refused by `waBackendChainWhy` until the network or the host moves.
The chain is NOT forgotten on a network change: what the node said is what
the guard compares, and comparing it to the new network is the question.

**ONE addr() PER ADDRESS RATHER THAN THE ACCOUNT'S DESCRIPTORS**, because
every wallet kind has addresses and only some have a descriptor Core can
range, and an address list needs no fingerprint, path override or range
bookkeeping to be right. The watch tier (phase 3) is where the descriptors
earn their place. **AND THE SCAN IS NOT BELIEVED ABOUT THE MEMPOOL**, in
either direction: a scanned coin this wallet has marked spent stays marked
(the spend is in the mempool the scan cannot see), where `waMergeUtxos` would
drop the mark; and the wallet's own unconfirmed coins survive the replace.
Getting either wrong is a coin offered twice or a balance that falls on every
sync until a confirmation.

**THE GATE MODELS THE SOCKET, which nothing had needed before.** The
clearnet Electrum checks drive the handlers around the socket and never the
socket; the Core block switches on a modelled one (`world.sock`, the four
statements recorded and `the result` answered the way the engine's are, the
same shape as the modelled Tor) and drives the whole life of a request: the
dial, the write asserted byte for byte with the auth header base64 of a
cookie file written in the sandbox, the two armed reads, the head and body
delivered as the engine would, the socket kept. Nothing here has met a node;
the labels say so in three places.

### 2026-09-04, the rest of Bitcoin Core: three ways in, a watch wallet, a screen and a sandbox

The entry above landed the plan's phase 1 and the scan tier. This is phases 2
to 4 in one pass, built while an engine was unavailable, so every word of it
is headless: `core-tor` and `core-cli` beside `core-rpc`, the watch tier (a
descriptor wallet inside the node), a thirteenth screen, and a regtest
sandbox. Six decisions are worth the record and two of them are lessons this
member had already written down and I made anyway.

**ONE PARAMETER BUILDER, TWO CHANNELS.** `waCoreParams` answers the JSON
array for a request and nothing else; the RPC wraps it in an envelope and
`waCliArgsFrom` splits it back into command-line arguments. The alternative -
a second builder for the command line - is the shape this file has scars
from, and the split is a scanner (`waJsonSplitTop`) rather than a chunk
expression because a bracket inside a string is not a bracket. Nothing is
re-serialised, so a structured argument reaches `bitcoin-cli` as the same
bytes the socket would have sent.

**THE SHELL IS QUOTED BY ITS OWN RULE, AND REFUSED WHERE IT HAS NONE.** Inside
POSIX single quotes every byte is literal but a single quote, so a JSON
payload full of double quotes and parentheses - which is exactly what
`scantxoutset` and `importdescriptors` take - passes through untouched, and
one refusal covers the whole shell. Windows has no such rule, so a structured
argument there is REFUSED with the RPC channel named as the remedy. The first
version of the quoter refused parentheses and double quotes on every
platform, which would have made the two requests that matter impossible on
the channel built to carry them. The quoting takes the style as a PARAMETER
(`waCliQuoteFor`) so both can be driven offline: a rule that can only be
exercised on the machine it is written for is a rule nothing checks, and the
model answers `the platform` as Win32.

**shell() BLOCKS, SO THE POLL TICK NEVER RUNS ONE.** `waNetPump` exits
immediately for the cli backend and `waCliDrain` runs the queue from the
press that filled it. This is the frozen-window shape this file has already
met twice by other doors (`lock screen` with an unguarded body; `cwTxDecode`
looping on a count the input supplied), and it would have arrived a third
time as a wallet that hangs whenever a node is slow, with nothing on screen
to say why.

**A NODE IS ASKED WHAT CHAIN IT IS ON, and the answer outranks the port
table.** Core's default ports are only a guess about what a person runs
where. The sync puts `getblockchaininfo` ahead of everything whenever the
node's chain is not known, a mismatch empties the queue and is remembered,
and `waBackendChainWhy` keeps refusing until the network or the host moves.
The chain is deliberately NOT forgotten on a network change: what the node
said is what the guard compares.

**THE WATCH TIER IMPORTS addr() PER ADDRESS, not the account's ranged
descriptors** - every wallet kind has addresses and only some have a
descriptor Core can range, and a leaf (an inscription commit, a timelock) is
an address and not a range at all. The cost is a re-import when the window
grows, which `waSync` queues by comparing counts rather than trusting anyone
to remember. And the birth date is never guessed: an earlier one is safe and
slow, a later one silently loses history, so an empty box means the genesis
block and a seed generated here records its own birth.

**A SCAN IS NOT EVIDENCE ABOUT THE MEMPOOL, IN EITHER DIRECTION.**
`waMergeUtxos` drops a mark from a coin the backend still lists, because the
backends that see the mempool are believed over this wallet's memory.
`waMergeScan` must NOT: a scan reads the chain, so a coin it lists may be
spent by a transaction in a mempool it cannot see, and dropping the mark
would offer that coin twice. The wallet's own unconfirmed coins survive a
scan for the same reason, or the balance would fall on every sync until a
confirmation. `waMergeCoreUnspent`, on the watch tier, goes back to the
`waMergeUtxos` rule, because that answer DOES include the mempool.

**AND THE GATE CAUGHT THE ONE REAL DEFECT IN ALL OF IT, which was mine and
was already in this file twice.** `waNodeApplyBirth` was written
`if tText is not an integer or tText < 1`, and LiveCodeScript evaluates BOTH
operands of `or` - the exact mistake recorded here for `waSetSuggestedRate`
and `waCheckedHeight` on 2026-09-01, in the same words, by the same author.
The boot gate died on "last tuesday" rather than reporting it, which is the
interpreter refusing what the engine would have answered as text. Nested now.
Two more of the same class went the same way in one sitting: the sandbox
helpers were declared `command` and called as functions (the checker caught
that), and `waCliDeliver` concatenated `the number of chars of` into a log
line, which binds into the chunk target - three sites over in the same file
carry the note explaining it.

**AND ONE MORE THE GATE FOUND, which is the worst thing in this entry.**
`waSetBackend "core-tor"` kept whatever host was already in the box if it
ended in ".onion", on the reasoning that a person's own node address should
survive a switch. Every onion this wallet ships ends in ".onion": switching
from Esplora over Tor to Core over Tor therefore pointed a NODE'S RPC
CREDENTIALS at a public block explorer, which would have sent them in a
Basic auth header to somebody else's server on the first request. The
person's own onion is remembered under its own name (`sWaCoreOnion`) and
restored; anything else is cleared, and the gate drives the switch away and
back. The general form is one this file already knows in another dress: a
condition that tests the SHAPE of a value where the question is which
BACKEND it belongs to.

**One thing the gate itself taught.** Four checks in the first Core block
were about the wrong request, because a pump that had to DIAL writes nothing
until the engine's `waSockOpened` callback arrives and the model only sends
one when the test remembers to. They were green while asserting on the
previous request's bytes. The fix is a `core_pump()` helper that delivers the
callback whenever the last thing the model recorded was an open - and the
general form is the one this member keeps meeting: a check that passes
because it is looking at the wrong thing is worse than one that fails.
Beside it, the shared `Checker.ck` in riptide's runner crashed while PRINTING
a failure whose detail was a tuple, so the one thing that had gone wrong was
replaced by a traceback about printing it; it coerces now.

**AND THE LAST THING THE GATE FOUND was the shape of a failure rather than
one.** A command line that cannot be built - which on Windows is any request
carrying a structured argument - threw out of `waCliRun`, through
`waCliDrain` and `waSync`, to the press that started the sync: so a Windows
person choosing this channel lost the tip and the fee estimate as well as
the scan, from one refusal that was only ever about the scan. A refusal
belongs to the request it is about, which is what every other transport
already does through `waNetFail`, and the drain goes on to the next one. The
general form is worth the sentence: **a throw crosses every frame between
where it happens and where somebody catches it, and a queue is exactly the
place where that difference is a whole sync.**

**AND THE RUN AFTER THAT FOUND THE SAME CLASS TWICE MORE, so it stopped
being a list of sites and became a named question.** LiveCodeScript
evaluates BOTH operands of `and` and `or`, so `X is an integer and X >= 1`
still runs the comparison on a value that is not a number - the engine
answers by comparing as TEXT (so "six" is greater than 1) and the family's
interpreter refuses outright. This file had recorded that three times, each
fix nesting one site, and I wrote two more anyway (a block count off a
node, a fee target off a request). `waWholeAtLeast`, `waWholeInRange` and
`waNumAtLeast` ask it as one question now, and every Core guard goes through
them: a rule with a name cannot be got in the wrong order. **A lesson
written down three times and repeated twice is not a lesson, it is a
missing function.**

Beside them, the fifth instance in this file of the chunk-binding trap:
`the number of chars of tMethod + 1` binds the arithmetic into the CHUNK
TARGET, so the engine is asked for the length of (tMethod plus one). Four
sites carry the note explaining it; this was the fifth, and it was found by
running the code rather than by reading it - which is what the runner is
for.

**AND THE ONE FAILURE CI FOUND THAT THE THREE BLOCKS COULD NOT** is the
mirror of the pump-callback lesson above, and worth its own line because it
is the cost of adding a block to a long gate. `check-wallet-boot`'s update
section asserted that the WHOLE RUN'S log held exactly one "updated to
version" - true only while nothing else in the gate ever restored a carry.
The Bitcoin Core block does, because the node's credentials cross the swap
and that has to be checked. So a correct new block failed a correct old
check, 972 checks in, on a phrase count neither of them is about. It counts
from a mark now, which is what "a second restore does nothing" always
meant. **A check that reads a running total is a check about everything
that happened before it**, and in a gate this long that is a coupling
nobody can see at the call site.

Not run against a node, a program, or an engine.
