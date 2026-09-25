# CLAUDE.md - CoinXT

Guidance for Claude Code (claude.ai/code) in the CoinXT member. [SPEC.md](SPEC.md) is the source of truth for WHAT
CoinXT is (the C/script split, the ABI contract, the formats, the security model); this file is the operational record:
rules, traps with their reasons, and dated evidence. The portable xTalk/LCB lesson book is
[templates/CLAUDE.md](templates/CLAUDE.md) (byte-identical with onionxt's, by the suite's `check-checker-drift.py`).
Engine behaviour is in the suite's
[docs/OXT-ENGINE-NOTES.md](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/OXT-ENGINE-NOTES.md),
cited as "engine note N.N". Open work is tracked in the suite's docs/WORK-PLAN.md, not here.

House style: no em/en dashes and no curly quotes in any `.md` (`tools/check-docs-style.py`); ASCII only in `.lcb` /
`.livecodescript`, comments and strings included. Comment the *why*, densely; match the surrounding style.

## What this is

**CoinXT** is a Bitcoin and Ethereum cryptography layer for OpenXTalk (OXT): keys, BIP-39/32/44 HD wallets,
addresses, WIF, sighashes and transactions, and signing and verification for both chains, behind a thin C ABI and a
LiveCodeScript API. It implements no cryptography of its own and composes two vendored upstreams that do not overlap:

- **trezor-crypto** (MIT, plain C): every hash (SHA-2, SHA3-256, Keccak-256, RIPEMD-160, HMAC, PBKDF2), ECDSA,
  recoverable ECDSA, recovery, ECDH, and the two BIP-32 tweak steps.
- **upstream bitcoin-core/secp256k1** (MIT; added at ABI 6, 2026-08-16): BIP-340 Schnorr, x-only keys, the BIP-341
  tweak, and since ABI 7 (2026-09-10) the key sum behind `cnx_pubkey_combine`. Six `cnx_` entry points reach it.

Encodings, addresses, HD derivation and transaction byte work live in script. Today: **ABI 7, 44 `cnx_` exports,
95 public handlers** (44 in the `.lcb`, 51 in `src/coinxt.livecodescript`).

Layout:
- `src/coinxt.lcb` - the FFI seam: one private foreign handler per `cnx_` export, a public `cx*` wrapper for each.
- `src/coinxt.livecodescript` - the script layer; NOT part of the `.lcb`, it loads with `start using stack "coinxt"`.
- `src/code/<platform-id>/coinxt.<ext>` - the five committed libraries, pinned by `src/code/MANIFEST.sha256`.
- `native/` - `coinxt.c` (the shim), `build.sh`, `vendor/` (provenance: `native/vendor/VENDOR.md`), `MANIFEST.sha256`.
- `tests/` - `coin-selftest.livecodescript` (the pasteable OXT harness) and trimmed BIP-352 / BOLT11 vector files.
- `examples/` - `coinxt-demo`, `wallet-core` (the wallet's pure calculator layer), `coin-wallet` (the 13-screen
  wallet; its reader's document is [docs/wallet.md](docs/wallet.md)).
- `tools/` - the gates (`run-gates.sh` lists them), the oracles `coin_reference.py` / `wallet_reference.py`, and the
  interpreter `lcs-interp.py`. `docs/` - [api-reference.md](docs/api-reference.md) (every public handler),
  getting-started, wallet.md, bitcoin-core-plan.md.

**How CoinXT differs from its siblings (read before you assume).**
1. Unlike OnionXT it HAS a C shim, and the shim is central: the FFI law below applies from day one, every shim change
   builds under ASan + UBSan, and any ABI change bumps `CNX_ABI_VERSION` and `kABIVersion` together.
2. Like SodiumXT it is a stateless crypto wrap with no I/O and no lifecycle: every call is a pure, synchronous
   function, bytes in and bytes out. Its one long-lived object is the file-static `secp256k1_context` (process
   lifetime, never freed; LSan does not report it because it stays reachable).
3. It handles money. A wrong byte is lost funds, so every "fail closed" and "verify the checksum" counts double.

## The rules that make this safe and correct

Code cites these by number; keep the numbers.

1. **Add no cryptography. Wrap an audited upstream.** Every scalar multiply, signature and hash is upstream, audited
   code. A missing primitive is a new vendored file or an upstream request, never a hand-rolled curve op or hash.
   (Until 2026-08-16 this read "Wrap trezor-crypto". trezor-crypto's plain-C tree has no BIP-340, so the second
   library is the rule obeyed, not waived; SPEC.md section 2.1 has the reasoning.)
2. **The app owns key custody; CoinXT is a calculator.** It holds a key for one operation. Storage, backup and
   confirm-before-sign are the app's; say so wherever the boundary shows.
3. **Sign only the exact 32-byte digest the app hands you.** The transaction layer BUILDS digests; the app signs them
   (`cxSign`, `cxSignRecoverable`, `cxSchnorrSign`) after confirming the decoded human intent. No blind signing.
4. **Fail closed on every malformed input, and verify every checksum on decode.** A bad checksum, an out-of-range
   scalar, a wrong-length buffer or a non-canonical signature gets a clean `"CoinXT: <handler>: ..."` error, never a
   wrong-but-plausible key or address.
5. **Secret hygiene across the FFI** (the section below). Keys, seeds and chaincodes cross as `Data` / `Pointer`, are
   wiped after use, and are never returned as a bridged C string.
6. **Deterministic by design.** RFC 6979 nonces; fresh key material is the caller's (SodiumXT `sxRandomBytes`). Every
   operation is a pure, KAT-pinnable function of its inputs, except `cnx_schnorr_sign` with an absent aux (below).

### The C-vs-script split (hold this line)

Anything that touches a private key or a curve point is C, audited upstream code. Checksummed byte-shuffling with no
secret-dependent branch is script, pinned by a KAT. That keeps the trusted native surface to 44 buffer-in /
buffer-out functions (SPEC.md section 5.1) and the encodings where they are easy to read, diff and test. Never push an
encoding into the shim; never reimplement a curve op in script (point addition in script was costed for BIP-352 and
refused - minutes per input under the interpreter - and became `cnx_pubkey_combine`).

### FFI / C-ABI conventions

LAW here, not carried-for-later. Change nothing without a very good reason.

- **Buffers cross as `Pointer` + length; an LCB `Data` never auto-bridges to `void*`** (it marshals as an opaque
  `MCDataRef`). An in buffer is `MCDataGetBytePtr` + length; an out buffer is an `MCMemoryAllocate` block passed as a
  real `Pointer` and copied back with `MCDataCreateWithBytes`.
- **Every `cnx_` length is `size_t`, so it is `UIntSize` in the `.lcb`, never `CInt`**: a 4-byte int in an 8-byte
  slot corrupts the heap. The one genuinely 32-bit argument is the PBKDF2 iteration count (`uint32_t`, `CUInt`).
  `UIntSize` as a RETURN type was engine-proven 2026-08-08; do not "simplify" it to `CUInt`.
- **No SodiumXT-style `-needed` retry.** A `cnx_` entry returns a status and writes either the fixed size its
  `cnx_*_len` reports or exactly the requested length. Every length is a function; no size is hardcoded in LCB.
- There is no 64-bit foreign int. Reals cross as `double`, booleans as `int`. Never rename a shipped `cnx_` name (a
  silent bind failure at load). `<builtin>` handlers resolve by name, so no leading underscore.
- **Never RETURN a bridged C string** (`ZStringUTF8` / `NativeCString`): the engine frees the returned pointer.
- **Absent optional inputs cross as an EMPTY `Data`, read by LENGTH** (engine-proven in an optional slot 2026-08-17;
  as an empty input 2026-08-08). `optional Pointer` is legal LCB but unexercised on any engine here; do not use it.
- **No scalar `out` parameters**: parity and recovery id travel inside the output buffer (`cnx_taproot_tweak_pubkey`
  writes key plus parity byte, `cnx_ecdsa_sign_recoverable` signature plus recovery id).
- **`cxCheckABI` runs on EVERY call and is deliberately not memoized** (an unassigned module variable's default cannot
  be verified headlessly, and being wrong about the loaded binary is not acceptable). On skew it says reinstall CoinXT.
- No `textEncode` / `textDecode` in LCB (text <-> Data stays in script). Every foreign call inside `unsafe ... end
  unsafe`; locals at the top of the handler (a nested `local` has broken whole-script compilation);
  `use com.livecode.foreign` whenever a foreign type is named.
- **Errors throw as `"CoinXT: <handler>: ..."` without the status code** (an unknown status can only mean a newer
  library, which the ABI guard refuses). Status codes: `CNX_OK` 0, `ERR_NULL` -1, `ERR_BADLEN` -2, `ERR_RANGE` -3,
  `ERR_BADKEY` -4, `ERR_BADSIG` -5, `ERR_ENTROPY` -6, `ERR_BADDIGEST` -7 (an all-zero digest: forgeable),
  `ERR_INTERNAL` -8.

### Determinism and entropy

- **No KEY MATERIAL from an ambient RNG** - the phase-2 correction of a phase-0 rule that said "wire trezor's
  `random_buffer` to abort". `vendor/ecdsa.c` calls it on EVERY curve op (Z randomization, inversion blinding):
  side-channel countermeasures, not nonces. Abort kills the host at the first `cxPublicKey`; a constant hangs
  `generate_k_random` or deletes the countermeasure. The entropy comes from `getrandom` / `BCryptGenRandom` /
  `arc4random_buf` and fails closed (`CNX_ERR_ENTROPY`; `abort()` only where upstream's void signature leaves no
  choice; an unknown platform is a compile error). It cancels algebraically: `coin-kat.py` signs one input 32 times
  and requires one answer. Fresh keys are the caller's (`cxNewSeckey` validates 32 caller-supplied bytes).
- **The libsecp256k1 context is re-randomized before every secret-key operation**; one that cannot be randomized is
  destroyed. Public-only calls skip it, but CREATING the context needs entropy once. Only the script thread calls in;
  a multi-threaded host would need a lock around `cnx_secp_ready()` and nothing else.
- **Schnorr aux: absent means FRESH, never all-zero.** `auxlen == 32` is deterministic (what the BIP-340 vectors pin);
  `auxlen == 0` draws 32 OS bytes and fails closed; anything else is `CNX_ERR_BADLEN`. The KAT asserts both ways: two
  absent-aux signatures differ, both verify, and neither equals the zero-aux one.

### Secret hygiene

- **The `.lcb` wipes EVERY out-buffer through `cnx_memzero`** (ABI 5, 2026-08-16; a wrap of `vendor/memzero.c`) before
  `MCMemoryDeallocate`, unconditionally: per-site classification fails open when it is wrong.
- **`sWipeFree` RETURNS its status; `sFinish` appends it in parentheses to a real error (`sWipeNote`) and throws it
  alone only on the success path**, so a wipe failure never displaces the primary error. The copy into the result is
  inline in `sFinish`, so a failed `Data` build still wipes and frees first.
- `cnx_memzero` has no `cx*` wrapper, on purpose: a script `Data` cannot be wiped in place.
- Honest limit, stated wherever it matters: OXT script variables are not locked memory, so a seed held in script can
  be paged to disk. This is not hardware-wallet isolation; the trust boundary is the machine. The script layer
  empties its key variables as soon as it is done. Never log a seckey or seed, or put one in an error string or a
  committed fixture (KATs use public vector keys).

### Encodings in script (the OnionXT base32 discipline)

- Build bytes with `numToByte` / `binaryEncode`, parse with `byteToNum` / `binaryDecode` (a function filling an out
  var), index with `byte x to y of`. Never `char` / `line` / `word` on binary.
- **No `^`, `div`, `mod`, `bitAnd`, `bitOr` or `bitXor`**: arithmetic helpers, including the 31-bit `cxBitXor` the
  bech32 checksum needs. Mask every accumulator well below 2^53 (engine note 2.4).
- **Decide a wide integer's bound on small exact integers, never against a quotient** (2026-09-24; the numeric model
  is engine note 2.4): OXT (Win32, the suite paste) ACCEPTED 2^53 + 1 through riptide's
  `tHi > (9007199254740992 - tLo) / 4294967296`, adjacent doubles that IEEE and `lcs-interp.py` both order
  (OBSERVED). The rule behind it, named by the same day's third run and the engine source: two unequal numbers
  within 10 DBL_EPSILON of the SMALLER are EQUAL (so integers one apart blur from 4.5e14; engine note 2.10).
  `cwLeRead` / `cwBeRead` had the form, safe only under an absolute tolerance, and now decide 2^53 as 32 times
  2^48 on the bytes; `check-wallet-vectors.py` tier 4 runs the bound under the engine's rule and two margin
  models. Verified statically; needs an OXT pass.
- Base58 is long division over the byte array (nothing exceeds 58 * 255), not a bit repack.
- **Look up alphabet characters by BYTE VALUE with `cxCharIndex`, never `offset()` or `is`**: `the caseSensitive`
  defaults to false, and in Base58 `a` and `A` are different digits - the file's "most dangerous line".
- **Compare checksums with `cxCompareBytes`, never `is`**, which compares numeric-looking hex as NUMBERS.
- Keccak-256 (Ethereum, `0x01` padding) is NOT SHA3-256 (FIPS-202, `0x06`): two shim functions, never aliased. The
  bech32 constant is 1, bech32m's `0x2bc830a3`. An encoder must never emit what its own decoder refuses.
- **`the itemDelimiter` is global mutable state** (templates/CLAUDE.md rule 5; engine note 2.3). Nine public handlers
  wear a save/set/use/restore wrapper around an untouched `Inner` body (fixed 2026-08-08: a hostile delimiter made
  `cxMnemonicValidate` answer FALSE to a valid phrase). The gate requires each to be indifferent to the delimiter and
  to restore it, throw path included. The carried book had answered this; read it before filing an engine question.

### Testing and conformance

- Pin every deterministic path to a PUBLIC vector, cross-checked against an independent implementation first. Never a
  vector generated by the library under test, never one from memory (two BIP-322 signatures and a hand-transcribed
  BIP-341 transaction were both wrong that way): transcribe mechanically.
- Add the vector for what a handler must REFUSE in the same change as the one for what it must produce (trap 16).
- The gold standard for signing: a CoinXT signature verifies in a mainstream external library, and a standard
  mnemonic reproduces a reference address byte for byte.
- **Handles:** none (the BIP-32 node crosses as bytes / an array). If C-side state is ever needed, use SodiumXT's
  generation-tagged handle table, never a raw pointer through script.

## Handler contracts

- `cxMnemonicNormalize` is not cosmetic: the seed is derived from the STRING. It does not apply NFKD (a non-ASCII
  passphrase is the caller's to normalize). `cxMnemonicToSeed` does not validate (BIP-39 seeds any string).
- A zero tweak is refused on BOTH tweak paths (upstream's public one accepts it), so private and public derivation
  agree about validity. `cnx_seckey_tweak_add` keeps the `bn_mod` after `bn_add`, which leaves a partly reduced value.
- `cxEcdh` returns the raw 65-byte point `0x04 || X || Y`; the caller composes its protocol's KDF.
- Every public key crosses as pointer + length (`cnx_pubkey_ok`): `ecdsa_read_pubkey` reads 65 bytes on a `0x04`
  prefix without being told the length, so a 33-byte key starting `0x04` would be overread. KAT and ASan both hold it.
- Upstream return conventions are inverted: `ecdsa_sign_digest` / `ecdsa_recover_pub_from_sig` return 0 for success,
  `ecdsa_read_pubkey` / `ecdsa_uncompress_pubkey` return 1; each call site says which. Low-s is upstream's.
- `size_t` lengths into upstream `uint32_t` / `int` parameters are range-checked (`CNX_ERR_RANGE`) rather than
  silently truncated; PBKDF2 refuses `iterations == 0` (upstream would return the one-iteration key) and `outlen == 0`.
- WIF: the key crosses as 64 hex both ways, range-checked through `cxSeckeyIsValid`; a trailing byte that is not
  `0x01` is refused (guessing the flag guesses an address); an xprv is refused on its payload LENGTH.
- Transactions: satoshi amounts and counters are integers (2.1e15 sat is under 2^53); Ethereum wei-scale fields are
  minimal big-endian HEX, RLP-encoded as bytes. Repeated fields cross as comma lists of hex behind the itemDelimiter
  wrapper. `scriptCode` is passed bare and the layer adds its length prefix.
- **Taproot.** `cxBtcAddressP2TR` encodes an output key it is GIVEN and never tweaks (tweaking would double-tweak every
  existing correct call). `cxBtcAddressP2TRFromInternal` is a separate NAME because an absent xTalk parameter is
  indistinguishable from an empty one; the gate asserts the two disagree on the same 32 bytes. **An empty merkle root
  means BIP-341's empty string, NOT 32 zero bytes** - a consensus rule, asserted in the ASan self-test, `coin-kat.py`
  and the script vectors. The tweak record is 33 bytes (key || parity).
- Schnorr signing takes a 32-byte message; verification takes any length. An off-curve x-only key answers FALSE on
  verify (BIP-340 vectors 5 and 14) and `BADKEY` on tweak. `cxTaprootTweak`'s length guard is asserted by its MESSAGE,
  because the shim refuses the same input and "it threw" would test the layer below.
- `cxBtcSighashTaproot` takes types 0-3 and `0x81`-`0x83`, refuses `0x80` and SINGLE past the last output, supports no
  OP_CODESEPARATOR and no annex, and builds, never signs. Leaf version `0x50` is refused (it reads as the annex); a
  control block holds at most 128 nodes; `cxTapLeafHash` refuses scripts of 253 bytes or more (wallet-core carries a
  real-varint leaf hash for inscriptions). Tree assembly above one fold is the app's loop over `cxTapBranchHash`.
- trezor's `tweak_add` must land on upstream's taproot tweak point: `coin-kat.py` checks the two libraries agree once
  per published vector, so BIP-341's `tweak` column is read, not just transcribed.

## Traps

Symptom -> cause -> fix. Engine behaviour gets one line and its engine note.

### Shim, vendoring, toolchain

1. **A vendored closure larger than it looks** (found by compile, read undefined symbols, add, repeat): `hasher.c`
   and blake/groestl come in through `HasherType`, `base58.c`/`address.c` through `ecdsa.c`. `bip32.c` and `bip39.c`
   are NOT vendored (bip32 drags in every curve trezor supports; BIP-32 needs only the two tweak steps). The wordlist
   IS vendored, crosses as one 16384-byte blob of 8-byte slots, and `coin-kat.py` requires BIP-39's published SHA-256
   `2f5eed53...b24dbda`, sorted and duplicate-free (the script binary-searches it).
2. **Basename collision.** `vendor/secp256k1.c` (trezor's curve parameters) and `vendor/libsecp256k1/src/secp256k1.c`
   (upstream's library) mapped to one object by basename; upstream's objects carry a `secp_` prefix.
3. **Scoped warnings.** Upstream's units get upstream's own `-Wall -Wextra -Wno-unused-function`; the `-Wno-` must
   not reach `native/coinxt.c`. `secp_cppflags` (module defines, window size, `SECP256K1_NO_API_VISIBILITY_ATTRIBUTES`)
   reach every unit; that define also stops MinGW dllexporting the whole libsecp256k1 API.
4. **`ECMULT_WINDOW_SIZE=12`**, a documented knob, not a patch: 128 KB of table per binary instead of 1 MB at no
   measurable verify cost. `precomputed_ecmult.c` is vendored verbatim (a generated table cannot be hash-pinned);
   `precomputed_ecmult_gen.c` stays at upstream's default comb (changing it means regenerating a vendored file).
5. **Upstream's default illegal-argument callback (abort) is kept**: a returning callback leaves outputs undefined.
   The firewall (non-NULL pointers, checked lengths) makes it unreachable.
6. **Pins**: trezor-crypto `230cfe37e4c5fefb6ca117725d261a7b3646a995`; libsecp256k1
   `439278a649d3099d62dde966a76dc04aaca7ccb3` (v0.8.0 plus 12 commits, one of them hardening fix `3d4340d` in a
   compiled file), every file verified by git blob id. `native/vendor/VENDOR.md` is the provenance; do not repeat it.
7. **Zig's Mach-O linker silently ignores `-exported_symbols_list`** (2026-09-10: 257 vendored names shipped; the
   suite freshness gate refused it). `tools/mac-cross-cc.sh` compiles with Zig and links with `ld64.lld`, and vendored
   units are compiled `-fvisibility=hidden` on every platform (trezor's `random_buffer` hook carries the attribute).
8. **The DLL export check was fail-open (2026-08-16, commit `55f9130`).** `package-extension.py` used `nm`, which on
   plain binutils lists only a DLL's import thunks; a filter emptied the set and an empty set meant "no opinion".
   `read_exports` now dispatches on the container MAGIC and parses PE with `struct` (an answer or `ExportReadError`);
   an unknown container is refused; only a Mach-O with no usable `nm` passes, with a loud WARNING. Proven to FAIL on a
   DLL with `cnx_memzero` surgically removed. **A gate green on the artifacts you look at is not evidence about the
   ones it protects.**
9. **The member's `check-binary-freshness.py` reads ELF only** and SKIPS PE and Mach-O loudly (the suite copy has read
   both since 2026-08-17). It compares exports and `cnx_abi_version()` with the source and never rebuilds-and-diffs.
10. **Cross builds must name the platform** (`pack x86-linux`): `uname` describes the host, and a `cc` wrapping
    `gcc -m32` still reports x86_64, which would file a 32-bit library over the 64-bit one.

### Script layer, and the engine under it

11. **"Hashes work but `cxBtcAddressP2PKH` is handler not found"**: the extension is installed and the script layer is
    not (`start using stack "coinxt"`, or a file that embeds it). Triage in that order.
12. **`repeat with ... step 2` walks by 1** (engine note 3.1; met 2026-08-09): `cxHexDecode` accused valid hex of a
    bad digit. Use `repeat while` plus an explicit `add`.
13. **A `throw` inside a `catch` is discarded** (engine note 3.2; met 2026-08-09): the nine itemDelimiter guards
    returned empty and `cxMnemonicValidate` answered TRUE for a mistyped backup. Capture, close the `try`, throw after
    `end try`. `return` inside a catch is fine and engine-proven; do not generalise to "avoid catch".
14. **The trailing-separator fail-open** (engine note 2.2; met 2026-08-10): the engine ignores ONE trailing delimiter
    when counting (`m,` is one item), so `cxHdDerivePath(node, "m/")` returned the node unchanged; refuse a trailing
    separator before splitting. The same rule made `cxBtcTxEncode` refuse the BIP-143 tx (a trailing EMPTY scriptSig):
    read lists BY INDEX and bound count guards to "too long" only; sequences stay strict.
15. **Case folds by default** (`the caseSensitive` is false for `is`, `offset()`, and array KEYS - engine note 2.7):
    never use an array as an exact-string index; compare through byte-value helpers.
16. **Every defect in the 2026-08-08 adversarial review FAILED OPEN**, and 87 green positive vectors saw none:
    `cxEthAddressIsChecksummed` compared a value with itself; `cxConvert5To8` signalled failure in-band as the bytes
    "ERROR" (now a separate status key); `cxBtcAddressP2PKH` validated nothing (the shared `cxCheckPubkey` checks length
    AND prefix now); bech32 values outside 0..31 emitted nothing; the encoder accepted a non-lowercase HRP.
17. **A handler reachable only indirectly is untested** (2026-08-09: `cxHash256`, `cxMnemonicNormalize`,
    `cxHdDeriveChild` and both tweaks had never been called by name). Pin a loop's single step before the loop, and
    both tweak paths to 2G rather than to each other. The suite's `check-suite-coverage.py` holds it now.
18. **Carried copies.** `src/coinxt.livecodescript` is embedded verbatim in the suite paste (`build-suite-selftest.py`,
    which `strip_spans` the coin-selftest copy) and between `sync-demo-embeds.py` sentinels in `coinxt-demo`,
    `coin-wallet` (with `wallet-core` and onionxt's layer) and `coin-selftest`. Never edit inside the sentinels; a
    script-layer edit is not done until both suite generators have re-run (this member's gates cannot see the drift).

### Interpreter and gate method

19. **`tools/lcs-interp.py` contract: stricter than the engine is acceptable, looser is a bug.** A byte-identical copy
    lives in nostrxt (drift-gated); `check-script-vectors.py` is the regression proof for every extension to it.
20. **2^53** (2026-09-08; engine note 2.4): Python ints made the model MORE capable than the engine, which fails
    silently. `_exact()` refuses any value past 2^53; `Imprecise` is not a `Thrown`, so a script `try` cannot eat it.
21. **What the model does.** Arrays are values (deep copy at every binding). The trailing-delimiter rule is modelled (a
    bare `split()` once made the "m/" negative vector test the model, not the script). `the number of chunks of X & Y`
    counts X alone (engine note 2.6, corrected 2026-09-11: the "binds into the target" reading was the runner's; the
    wallet's local-variable rewrites stay). `and` / `or` evaluate BOTH operands (engine note 2.5; a comparison against
    a non-number compares as text, `+ 0` on one is a hard error): use `waWholeAtLeast` / `waWholeInRange` /
    `waNumAtLeast` / `waIsDigits` / `waIsInt` - a lesson repeated after being written down three times is a missing
    function. `the name` of a control is type-prefixed. `is` against an array compares as an array. Array KEYS fold
    case (engine note 2.7; modelled since 2026-09-24, the first spelling written is kept, tier 0 of
    `check-script-vectors.py` pins it). NOT modelled: `round()`, `repeat for each line`. `ip.call` reaches natives
    only through script. Hot paths use `_rx` / `_rxi`.
22. **`is` is modelled case-SENSITIVELY whatever `the caseSensitive` says** (the property reaches array keys only,
    as a per-handler local), so `check-wallet-vectors.py` runs every vector twice, the second time with `is` and
    `offset()` folded. `contains`, `begins with`, `ends with` and `sort` are NOT folded; putting one on
    case-significant data needs a new tier, not a quiet widening.
23. **When a mutation survives, suspect the probe first, but check**: twice the probe was wrong (wrong direction; half
    a defect reverted), once the check was (an "it threw" assertion over a shim that refuses the same input).
24. **Reproduce, then fix: correct the model first**, see the engine's failure headlessly on the unmodified code, then
    change the code. A fix landed with the model correction proves only that the two agree.
25. **Drive the handler a person reaches; never set the state the handler under test was supposed to set.**
26. **Two Checker APIs.** riptide's `Checker.ck` is `(label, ok, detail)`; the vector gate's is `(label, got, want)`;
    eleven boot checks in the wrong shape passed for any value. The boot gate has `ck()` for booleans and `eq()` for
    values, and a scan refuses a value-shaped `ck()`.
27. **An oracle-based gate cannot see a rule both sides share** (2026-08-31 manual coin selection and change pricing;
    2026-09-10 the seven wallet-core findings). Move `wallet_reference.py` first; delete any oracle line that exists
    to make two implementations agree.
28. **A check that reads a running total must count from a mark** (a correct new block failed an old phrase count).
29. **When CI and a local run disagree, run `test-wallet-boot.py`'s prefill-2 clean copy first**, the way CI does.
30. **A model that answers "nothing happened" is worse than one that throws**: a pump that must dial writes nothing
    until `waSockOpened`, so the Core block's `core_pump()` delivers it, or checks read the previous request.
31. **A gate that overstates its coverage is worse than none.** `check-selftest-vectors.py` once printed "66
    re-derived" for constants it had PARSED; it now fails any `k*` constant neither re-derived nor listed as an input
    with a reason, its split must add up, and it checks PBKDF2's short output prefixes its long one and that the
    SHA3-256 and Keccak-256 constants differ.
32. **An offline gate is blind beyond the network boundary** (the 2026-08-31 Esplora root). A gate's cost is part of
    its value: a run indistinguishable from a hang gets killed.

### Wallet: architecture

33. **wallet-core is a calculator**: no script-level `local`, no `item` / `line` chunks, no UI, no I/O; lists are arrays
    keyed 1..n; `cwCharIndex` / `cwSameBytes` for case-significant data (2026-08-31: every exported descriptor
    checksum and the `Zpub` / `zpub` version were wrong under the engine's case rule).
34. **`kWaUiVersion` is a fingerprint** (`ui-` plus 12 hex of SHA-256 over every `command waBuild*` handler): a stored
    stack rebuilds only when it changes, so run `check-wallet-ui-version.py --fix` after any `waBuild*` edit. New
    features must be named in the About and Tools text.
35. **Dust thresholds 546/540/330/294 come from Core's witness-program branch alone** (P2SH-wrapped SegWit prices as
    legacy). Data outputs are kind `nulldata:N`, threshold 0, one per transaction.
36. **QR** has no published vector: checked module-for-module against an independent encoder over 261 payloads.
    Format bits are MSB-first, the format loop is `i < 7`, and masks are scored with the format area as the code says.
37. **Validation shared across transports lives in ONE handler** (`waCheckedHeight`, `waCheckedTxid`, `waCheckList`,
    `waSetSuggestedRate`): a check written inside one transport's branch is one the next transport does not inherit.
38. **Commit state only after the last check that can refuse** (`waOpenWallet`, `waDeriveAccount`, `waSetNetwork`,
    `waSetType`): a failed Open must change nothing.
39. **Price each coin by its own type** (`waRecordType`; `waSizingType` gives `p2pkh-uncompressed`; coins carry
    `inputtype` into `cwSelectCoins`). The wallet's type is not the coin's.
40. **Anything written into the Send box goes through `waAmountBare`**: the box is read back in the SELECTED unit
    (`cwParseAmount(text, sWaUnit)`), so a BIP-21 request for 1.5 BTC written as `1.5` came back as 1.5 mBTC, a
    thousandfold underpayment, silent (2026-09-01 audit). A fee RATE from a backend is the opposite case: it is cut to
    eight decimals BY CHARACTERS before `cwBtcToSat`, which rightly refuses a ninth decimal on an AMOUNT (electrs sent
    `0.0026374400000000004`, 2026-09-02); `cwExpandExponent` handles the other float artefact, `1e-05`.
41. **Never drive a loop from a count the input supplies**: `cwTxDecode` looped 268 million times on eighteen pasted
    characters (`01000000feffffff0f`), and an `0xff` count never ended, a frozen engine on the UI thread (2026-09-01).
    `cwNeedBytes` refuses a count the remaining bytes cannot satisfy, sized by the SMALLEST item so only the impossible
    is refused; a non-minimal varint is refused as Core's `ReadCompactSize` does, and the eight-byte form is read as two
    halves so a count past 2^32 is a refusal, not a value past 2^53 (2026-09-10). A chunk that runs past the end of a
    string ANSWERS with what is there rather than refusing, so framing is checked explicitly (`cwScriptCheck`, a second
    walk beside `cwScriptAsm`). Same frozen-window class: `lock screen` with an unguarded body (a throw skips the
    unlock; `waBuild` unlocks in its catch) and `shell()` (trap 66).
42. **One accessor for the derivation path** (`waAccountPath`): descriptors and `BIP32_DERIVATION` must follow an
    override. `waSelfTestAddress` deliberately stays on BIP-84's standard path; it is the boot check's anchor.
43. **Leaf records (inscription commits, timelocks, found silent-payment outputs) are unpaid address records on chain
    0**: `waNextUnused` skips them, and recipes are re-attached after every derivation. The address windows extend
    themselves (`waNextUnusedOrMore`, `waNextChangeOrMore`).
44. **A throw crosses every frame to its catcher**, and in a queue that is a whole sync: a refusal belongs to the
    request it is about (`waNetFail`, `waCliDrain`).
45. **Kit and object traps met here**: `uiCheckbox` has `autoHilite` false (app state drives it); `uiTable` takes
    ABSOLUTE tab stops; the boot self-check has its OWN field (the block appends, an app log replaces; `waScFresh`
    clears it before `scBegin`); a list field selects on button 1 only, so `mouseDown` sets the hilitedLine first.
46. **A menu item means what the button means**: items resolve through the click router (`waRouteKnows` /
    `waRouteClick` / `waMenuRoute`). "Names a real control" is not "does what the label says"; drive the row.
47. **Update from main**: the carry (`waSerializeWallet` text plus `update:*` rows) sits in a stack custom property,
    restored LAST by `waBoot` and cleared by `closeStack`. `waUpdateCheck` matches whole lines, because its own source
    carries the strings it looks for.

### Wallet: custody

48. **`waSerializeWallet` writes a secret only for the kind that owns one**, so a future leak cannot reach the file.
49. **`waSafeText` strips tab and newline at every label door**, and `waSerializeWallet` refuses them: a BIP-21 label
    carrying `%0A` / `%09` could replace the account key with a payer's (demonstrated end to end 2026-09-01).
50. **The watch-only box refuses private keys** through `cwXKeyIsPrivate` (an xprv there was stored as public).
51. **`waDropSeed` drops the account xprv and the derived address list** (every record carries its private key).
52. **`waSaveWallet` checks the write result on both branches, and both guards are held** (2026-09-24). Until then the
    boot model's `url_write` raised instead of setting `the result`, so a test could not fail. riptide's runner now
    answers a write through `the result` (empty when it landed; the planted text, nothing written, for a path in
    `world.url_write_refuse`), `check-wallet-boot.py` drives Save into a planted refusal on the sealed and the
    unencrypted branch, and `test-wallet-boot.py` removes each guard in turn and requires the gate to fail.
53. **Mainnet with the published test seed is allowed BY DECISION**; `waPublicSeedWarning` is recomputed every repaint.
54. **Every PSBT signing branch checks the script it is about to unlock** (the p2wsh branch did not, 2026-09-01: anyone
    could get a signature over a preimage of their choosing). Multisig keys parse strictly; SIGHASH 0 and 1 are honoured
    and others refused; duplicate keys are refused; signatures are capped at m; a final input is taken as it stands.
55. **A guard written correctly is dead if something above it throws for the case it allows** (an imported key).

### Wallet: transports and backends

56. **HTTPS over Tor is impossible in this engine** (no TLS upgrade on an open socket; `open secure socket` cannot do
    SOCKS): the Tor transports are plain HTTP / TCP to `.onion` hosts through OnionXT's SOCKS client, and the stack
    defines the three engine socket messages itself, dispatching to OnionXT's named functions (`DROP_HANDLERS`).
57. **esplora-clear uses `load URL`, a GET**: it cannot broadcast (refused by name), gets no status code (a refusal
    arrives as an empty body), and cannot be cancelled, so replies are correlated by the URL issued.
58. **`waBackendChainWhy` runs before any request**, recomputed when the backend or the network changes: an Electrum
    server answers a foreign-chain script hash with an EMPTY list, which reads as an empty wallet.
59. **Esplora roots differ per chain**: `/api`, `/testnet/api`, `/signet/api`, and `/testnet4` on mempool.space.
    **The Electrum port selects the chain**: the v3 onion uses 110 mainnet / 143 testnet (`waRetunePort`). A v2 onion
    is refused by name (`waOnionWhy`).
60. **Replies are correlated by JSON-RPC id**; a `headers.subscribe` push is dropped (`waIsNotification`), not failed.
61. **A failed request is requeued once, at the FRONT** (an unparseable reply is not); the deadline follows progress.
62. **`kWaBatchSize` is 22** (tip, fees and one chain's twenty addresses); a refused batch is halved (`sWaBatchCap`)
    down to singles, and the cap is forgotten on a backend change.
63. **Tor streams are kept open for a sync**; Esplora-Tor speaks HTTP/1.1 keep-alive through `waHttpFeed` (with a
    close-delimited fallback). Buffers grow with `put pData after`, never by concatenation.
64. **`waEnsurePolling` re-arms the pump** before anything is queued (a re-pasted script leaves it stopped and every
    transport silent). A non-empty queue is a running sync: Refresh reports it, Sync refuses a second.
65. **Coins are marked spent when a broadcast is QUEUED** (`waNoteBroadcast`) and released on its final failure; the
    backend outranks that memory (`waMergeUtxos` un-marks a coin it still lists). A Core scan is NOT mempool evidence.
66. **Bitcoin Core**: one parameter builder (`waCoreParams`) for RPC and cli; the allowlist is `kWaCoreMethods`; POSIX
    single-quoting (`waCliQuoteFor`), a structured argument REFUSED on Windows. `shell()` blocks, so cli requests run
    from the press, never the poll tick. The node's `getblockchaininfo` outranks the port table. One `addr()` per
    address; the birth date is never guessed.
67. **core-tor never inherits a public onion as the node host** (`sWaCoreOnion`): it once pointed node RPC credentials
    at a public explorer.
68. **`waSockOpened` captures `the result` before any other command runs** (`set` clears it).

## As-built notes

The dated evidence, newest last; the narrative is in git history. Interpreter-versus-engine disagreements are traps.

### ABI history

| ABI | Date | Change | `cnx_` exports |
|---|---|---|---|
| 1 | 2026-07-02 | phase 1 hash slice: Keccak-256, SHA3-256 (trezor-crypto pin vendored) | - |
| 2 | phase 1 | SHA-256/512, RIPEMD-160, HMAC-SHA256/512, PBKDF2-HMAC-SHA512; `CNX_ERR_RANGE` | 16 |
| 3 | phase 2 | secp256k1: seckey verify, pubkey from seckey / decompress, ECDSA sign / verify / recoverable / recover, ECDH | 30 |
| 4 | phase 4 | the two BIP-32 tweak steps, the BIP-39 wordlist blob and its length | 34 |
| 5 | 2026-08-16 | `cnx_memzero` | 35 |
| 6 | 2026-08-16 | libsecp256k1: BIP-340 sign / verify, x-only key, BIP-341 tweak (seckey and pubkey) + lengths | 43 |
| 7 | 2026-09-10 | `cnx_pubkey_combine` (BIP-352 receiving) | 44 |

The script layer's 51: phase 3 encodings (19), phase 4 HD (11), phase 5 transactions (13, 2026-08-11), WIF (2,
2026-08-15), two taproot handlers alongside ABI 6, and the BIP-341 sighash and script-path handlers (4, 2026-08-23).

### The library on an engine

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| 2026-08-08 | OXT (platform not recorded) | suite paste: the `.lcb`'s five questions | green. Module loads, binds resolve, ABI guard holds (via `sPrepare`), `UIntSize` return works, empty `Data` marshals; keccak256 / sha256 / ripemd160 byte-exact, SHA3 != Keccak. Phase 1 closed |
| 2026-08-09 | OXT | first run of the script layer (coin-selftest, folded) | red: the step-2 defect and throw-in-catch (traps 12, 13). Both fixed; the checker refuses both forms |
| 2026-08-10 | OXT | folded suite harness | 205/206: the one red line was `"m/"`, the trailing-separator fail-open (trap 14). The C `int` flag (33 vs 65) and `Boolean` returns proven |
| 2026-08-10 | OXT | same-day re-run, script layer embedded | 207/207; every public handler of the time (65) executed. Phases 2-4 closed |
| 2026-08-12 | Windows x64 | suite paste, phase 5 | THE ENGINE PASS LANDED 2026-08-12: 230/230; the BIP-143 signed tx byte for byte on the path the trailing-empty-scriptSig fix repaired, both new refusals, EIP-155 / EIP-1559 exact. Phase 5 closed |
| 2026-08-17 | Windows x86_64, NT 10.0, OXT 9.6.3 | suite paste (1,836 folded checks, 0 failed, 7 skips) | coinxt 278/278 at ABI 6: WIF (14 checks; an xprv refused on payload length), the `cnx_memzero` bind, BIP-340 vector 1 byte for byte, cases 5 (an off-curve key answers false) and 6 (odd R), three tamper negatives, fresh-aux signatures that differ and both verify (the full 19, 10 negative, run headless in `coin-kat.py`), the BIP-341 wallet vectors, `cxBtcAddressP2TR` still not tweaking, an empty `Data` in an OPTIONAL slot, a three-argument foreign call, an array return by name |
| 2026-08-20 | Windows | suite paste, whole run | 1981 passed / 0 failed / 1 skipped overall; coinxt's own count not recorded |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | suite paste (2373/0/3) | coinxt 290/290, including the 12-check BIP-341 section: both sighash paths, the `0xfa` leaf, the sorted fold, the control block, every refusal |
| 2026-09-24 | Windows (the engine reports Win32; the bitness not recorded), the 2026-09-12 release DLL at ABI 7 (its first engine load, the maintainer's account) | the D-23 suite paste (2620/5/3; none of the five failures was coinxt's) | coinxt 296/296 and the core's two samplers 11/11. ABI 7's first engine run: the "secp256k1 keys" section's six `cxPubkeyCombine` checks (G + G is 2G, one key is itself, the intermediate-infinity sum G + (-G) + 2G, and three refusals: the point at infinity, a length not a multiple of 33, an empty set), the first `Data`-of-many-keys shape this binding marshalled. `cxCheckABI` passed against the shipped binary; every section through phase 5 green |

### Independent acceptance (manual-only by D-17)

| Date | Verifier | What ran | Result |
|---|---|---|---|
| 2026-08-12 | python-bitcointx 1.1.5 (`VerifyScript`, witness flags) | a FRESH native-P2WPKH tx built end to end through the shipped script | accepted; a flipped signature byte and a +1 sat amount rejected |
| 2026-08-13 | python-bitcointx 1.1.5 + eth-account 0.13.7 | all four families: legacy P2PKH, P2WPKH, EIP-155 and EIP-1559 on chain id 137 (wei above 2^53, non-empty data) | 31 checks green, a negative control in each |

`tools/verify-independent-decoder.py` is an ACCEPTANCE run, not a CI gate: its pip dependencies are ones the gate set
cannot assume, it SKIPS loudly without them, and `--require` fails on a skip. No workflow invokes it today (D-17's
brief says the release lane does; the work plan carries that).

### Committed binaries

| Date | Build | Result |
|---|---|---|
| 2026-08-12 | release run 31551536144 | replaced the Zig-built `x86-linux` (`zig cc -target x86-linux-gnu.2.25`) and earlier cross-builds; `kat-windows` executed the x64 DLL against the published vectors before bundling |
| 2026-08-16 | local MinGW cross-builds at ABI 5, then ABI 6 | static checks only: `cnx_*` names identical to Linux (35, then 43), no leaked symbols, `cnx_abi_version` disassembling to the right constant, imports `KERNEL32` / `msvcrt` / `bcrypt` only. Superseded |
| 2026-08-17 | suite `check-binary-freshness.py` gains PE | 43/43 binds resolved and ABI 6 decoded from both DLLs |
| 2026-08-27 | release run 12 | the first `universal-mac` dylib, both slices KAT-driven on the mac runner; all five platforms ship |
| 2026-09-10 | local, ABI 7 (commit `dca02b0`) | all five rebuilt here; the mac one cross-built (Zig + `ld64.lld`, trap 7) with exactly 44 `_cnx_*` names, verified by export trie, ABI constant and slices, not executed |
| 2026-09-12 | release run 34657390798 (commit `421bab3`) | replaced all five at ABI 7 |

CI executes the committed x86_64-linux library's vectors on every push (`native-coinxt.yml`). One 2026-09-12 Windows
DLL loaded on an engine 2026-09-24 (the ledger above), its bitness not recorded, so the `x86-win32` DLL may still
never have executed anywhere (CI's Windows KAT step is x86_64 only); no engine has loaded the Linux or mac builds.

### The wallet on an engine

Logs pasted (or runs reported) by the person running the wallet; platform not recorded; testnet unless stated.

| Date | Log | What ran | Result |
|---|---|---|---|
| 2026-08-31 | first real-network run | a wallet generated, its testnet address funded, esplora-clear | no coins shown: `waEsploraPath` sent the mainnet root `/api` for every network, and through `load URL` Esplora's 400 arrived as an empty result. Fixed with per-chain roots and `waBackendChainWhy` |
| 2026-09-01 | first log | electrum-clear, MAINNET, `electrum.blockstream.info:50001`, the demonstration wallet | a full sync on one persistent socket, ids 2-145, a 16 KB history. Also 27 identical "does not pass its BIP-39 checksum" lines (a failed Open committed the bad phrase, trap 38), Test with no backend reported as a failure, and a second Sync appending a second 82-request batch (all fixed) |
| 2026-09-02 | REPORTED, no log | a testnet receive over both clearnet transports | the first coin held; recorded as reported, no more |
| 2026-09-02 | second log | electrum-clear reshaped sync (42 requests for a fresh mainnet wallet); the specific-word BIP-39 diagnostic; esplora-tor (147 circuits, one SOCKS timeout retried once) | **FIRST BROADCAST**, esplora-tor: txid `7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, 226 vB, one legacy input, RBF, 10000 sat plus 181973 sat change (a self-payment); the reference decoder's txid equals the logged one; seen spent by the next sync. Refresh during a slow sync logged errors (fixed) |
| 2026-09-02 | REPORTED, no log | "neither clearnet nor tor ever fire" | diagnosed as a stopped pump; `waEnsurePolling` added |
| 2026-09-02 | fourth log | fresh open: boot self-check 27 green | esplora-clear, esplora-tor and electrum-clear all fire on both chains. Three defects fixed: a float fee rate refused, a dropped Tor request, Inspect with no raw-tx request |
| 2026-09-02 | fifth log | electrum-tor against the retired v2 onion; the right-click menu | "general SOCKS server failure" (the retry-once seen working on an engine); three boot blocks in one field (fixed); the menu opened on an engine for the first time, acting on the previously selected row (fixed); electrum-clear on testnet synced |
| 2026-09-03 | sixth log | **electrum-tor**, Blockstream's v3 onion, port 143 | full sync, a second wallet, and a broadcast, txid `9bab6640f2bbe01f96a95ffdeca3e96881f1819e677348562ef8bf87da6b719a`, seen spent; 173 requests on 173 streams (streams kept since) |
| 2026-09-03 | seventh log | electrum-tor with kept streams | one stream per sync; an abort mid-sync; a pushed header on the idle stream logged and ignored. Esplora-Tor still used a stream per request (HTTP/1.0, by design then) |
| 2026-09-03 | eighth log | esplora-tor on HTTP/1.1; Electrum batches | 51 requests down one Tor stream; both Blockstream Electrum servers take JSON-RPC batches (a 51-request sync in five round trips) |
| 2026-09-03 | autotest runs before the tenth log | chain phase, electrum-tor | a second spend reused the first one's coin ("insufficient fee, rejecting replacement"), fixed by `waNoteBroadcast`; a vault payment refused "insufficient funds" over 451087 sat (not reproduced headlessly); the onion server refused a batch of 22, fixed by halving. The evening run: two children refused `400 Bad Request` (fixed by marking at queue time), the halving proven (six lines of 11 answered), and the vault payment went through |
| 2026-09-03 19:42 EDT | tenth log, autotest, p2pkh wallet, electrum-tor | 41 passed / 0 failed / 4 skipped in 248 s | a 41-request sync in eight round trips; the note's RBF bump accepted, voiding the note's coins; the silent-payment send and the commit funding built on the replacement's change and accepted; the commit coin seen at 0 conf and the reveal accepted - inscription `f002bfb2bde8ff4354c89ca590291bea96416ed6e2e5797c0e863b9be79bc0eei0`; the vault paid and its coin withheld; every acceptance "reserved when it was queued". Skips: BIP-322 on p2pkh, vault spend after its height, CPFP on a foreign tx, the update swap |
| 2026-09-03 20:13, 20:30 EDT | eleventh log, second autotest, electrum-tor | two runs | a reply-refused broadcast released its coin (balance back to the sat, the node's reason `mempool-script-verify-flag-failed` logged); a bump refused naming the queued child; a change-less sweep bumped by a CPFP child priced from the spend record, accepted. Found and fixed: leaf addresses never marked used and `waNextUnused` handing out a leaf record, the release passing a log label to the decoder, the CPFP rate rounding up. This testnet server accepts a 0.1 sat/vB transaction |
| 2026-09-03 21:54 EDT | twelfth log, second autotest, electrum-tor | 14/14 | the refused broadcast released; the bump refused naming the child; the sweep's CPFP "about 3 sat/vB" (1152 sat over 384 vB); BOTH address windows extending themselves (change chain; receive chain at index 40 on the 27th timelock); every queued transaction accepted after the script finished, so the CPFP pair is real on testnet |

### CI clock (2026-09-11)

The suite's static-gates job had reached 5 h 30 m, and a pull-request run was cancelled at GitHub's 6 h ceiling. Three
changes, none to what is checked: `test-wallet-boot.py` runs its eight boots concurrently (2 h 59 m serial to 89 min
at four workers); the three wallet gates start together and print fixtures-first (the job went to 4 h 06 m); and every
hot `re.match` in the interpreter, riptide's runner and `check-wallet-boot.py` compiles its pattern once (`_rx` /
`_rxi`, 105 sites; A/B 11 m 43 s to 7 m 02 s). CI then ran 2 h 15 m for a pull request and 2 h 32 m for a push.

## Status

Engine-proven: the whole library surface through ABI 7 (all 95 handlers; 296/296 on 2026-09-24 in the suite paste, on the
2026-09-12 Windows DLL, whose first engine load that was; 290/290 at ABI 6 on 2026-08-24, Windows x86_64) and, in the
wallet, all four public transports, broadcast, RBF, CPFP, an OP_RETURN note, a silent-payment send, an inscription and
a timelock payment (2026-09-01 to 09-03, testnet). Bitcoin spends over the `cx*` sighash and encoder were accepted on
testnet; a native-P2WPKH broadcast is not recorded, and no EIP-155 / EIP-1559 transaction has been broadcast. Verified
statically; needs an OXT pass: every ABI 7 binary but the one Windows DLL that loaded on 2026-09-24 (its bitness was not
recorded, so the `x86-win32` DLL may still never have executed); the wallet surface
added from 2026-09-04 (the Ordinals and Vault screens, testnet4, BIP-329, BIP-322, silent-payment receiving, Runes,
BOLT11, the Core backends, the 2026-09-10 fixes, the 2026-09-24 byte-level 2^53 bound in `cwLeRead` / `cwBeRead`);
and what the logs did not reach (the update swap, mainnet Electrum on port 110, the stale-answer skip, paint/pump
timing, the mixed tip+fees batch, the three corrected menu items, the backend un-marking a coin, Esplora's 400 body in
the log, CPFP on a foreign transaction, an Electrum-format seed opening real coins, a vault release after its height).
Open work is in the suite's docs/WORK-PLAN.md.

## Commands

```sh
bash tools/run-gates.sh               # every gate, in order (needs bash); build-all.sh and gates.yml run it (hours)
python3 tools/check-livecodescript.py; python3 tools/check-docs-style.py; python3 tools/check-doc-handlers.py --check
python3 tools/coin-kat.py --check     # KATs: builds the shim in a temp dir, drives it via ctypes (needs cc)
python3 tools/check-selftest-vectors.py --check && python3 tools/check-script-vectors.py --check
python3 tools/check-wallet-ui-version.py [--fix]   # after any waBuild* change
python3 tools/test-wallet-boot.py     # the boot gate's seeded-defect fixtures, BEFORE the gate they prove
python3 tools/check-wallet-vectors.py --check && python3 tools/check-wallet-boot.py --terse
sh native/build.sh asan               # ASan + UBSan self-test of the shim
sh native/build.sh pack [platform-id] # the SHIPPED library -> src/code/<platform-id>/coinxt.<ext>
python3 tools/check-binary-freshness.py
python3 tools/package-extension.py --assemble | --refresh-manifest | --lib <path> --platform-id <id>
python3 tools/verify-independent-decoder.py [--require]   # manual acceptance (pip: python-bitcointx, eth-account)
```

- **Environment.** `COINXT_REQUIRE_CROSSCHECK=1` with `pip install ecdsa` turns the cross-library SKIP in `coin-kat.py`
  and `check-selftest-vectors.py` into a failure (suite-gates.yml sets it). `check-wallet-boot.py` imports
  `../riptide/tools/check-demo-boot.py` (which loads `../nostrxt/tools/nostr_reference.py`), located by
  `XTALK_SIBLINGS=<dir>` or `XTALK_SIBLING_<NAME>=<path>`; an absent riptide exits 2 (setup, not a boot failure).
  `WALLET_BOOT_JOBS=1` serializes the fixture boots.
- **`build.sh` has three outputs**: `libcoinxt.<ext>` in `native/` for the ctypes tooling, the `cnx_selftest`
  sanitizer binary, and the shipped library. `pack` gets *the name* right (`coinxt.<ext>`, NOT `libcoinxt`: the engine
  resolves `c:coinxt>` to the bare name), narrows *the surface* to the 44 `cnx_*` names (`src/coinxt.map`, a `.def` on
  Windows, `-exported_symbols_list` on mac; upstream's `sha256_Init` or `memzero` could collide with another extension
  in the process - a longer printed list means the linker refused it, so do not commit that one), and *strips*
  (byte-reproducible on the same toolchain, so the manifest stays clean).
- Always pass the platform id on a cross build (trap 10); the build stages to a temp file and moves it in only on
  success. The Linux library needs only `libc.so.6` (glibc floor 2.25). Upstream headers go in with `-isystem`.

## Git / workflow

- Develop on a per-task branch; open a draft PR. Do not push to `main` without explicit permission.
- A script change is done when the static gates pass AND it has had, or is flagged as needing, an engine pass. A shim
  change is done when ASan + UBSan are clean, the KATs pass, and `CNX_ABI_VERSION` / `kABIVersion` are bumped together.
- A native change refreshes all five committed binaries (locally, or by the suite's `release-binaries.yml`) and
  `src/code/MANIFEST.sha256` in the same change (suite rule 5); a vendor re-pin refreshes `native/MANIFEST.sha256` and
  `native/vendor/VENDOR.md`. Vendored files are never edited in place.
- No signing claim is done until a CoinXT signature verifies in an independent library. A change needing a new
  SodiumXT primitive splits: the upstream feature lands first, then CoinXT composes it.
- CoinXT is developed here and published into its own repository by the suite (the suite's docs/MEMBER-REPO-SPLIT.md);
  the old export procedure is at `git show cf0484d:coinxt/MIGRATION.md`.
