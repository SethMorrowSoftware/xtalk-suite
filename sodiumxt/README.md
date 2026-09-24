# SodiumXT

**Modern, authenticated cryptography for OpenXTalk and the xTalk family, made easy.**

SodiumXT is a [libsodium](https://libsodium.org) binding for OpenXTalk (OXT) / LiveCode. It
gives xTalk apps the cryptography people actually need today, behind a small, friendly set of
`sx*` handlers:

- **Authenticated encryption** with a passphrase or a key (secretbox, AEAD) - tampering and
  wrong keys are *rejected*, never silently mis-decrypted.
- **Password hashing** with Argon2id (memory-hard), for login checks and key derivation.
- **Large files**: encrypt, decrypt, and hash files of any size, streamed so they never have
  to fit in memory.
- **Public-key** encryption and **sealed boxes** (X25519), and **digital signatures**
  (ed25519).
- **Hashing** (BLAKE2b), **hex/base64**, **key exchange**, and a real **cryptographic random**
  generator.

It wraps the audited libsodium library, so you can delete hand-rolled crypto and just call
`sx*` instead.

## Why

The stock `encrypt ... using "aes-256-cbc" with password ...` path in xTalk has a weak key
derivation and no integrity checking: a corrupted or tampered ciphertext decrypts to garbage
instead of failing. SodiumXT fixes both. Argon2id makes passphrases expensive to guess, and
every SEALING cipher carries an authentication tag, so a wrong key or a single flipped byte
is detected and rejected. (The one deliberately unauthenticated handler on the surface,
`sxChaCha20IetfXor`, is a building block for published constructions that carry their own
MAC, never a way to encrypt bytes - the argued exception in `docs/security.md`.)

## Requirements

- OpenXTalk, or LiveCode 9.6.3+ (anything that loads LiveCode Builder extensions).
- **Linux** (x86_64, x86), **Windows** (64- and 32-bit) and **macOS** (universal, x86_64 +
  arm64), all five at ABI 10. The native library ships inside the extension: nothing to
  install separately, no `LD_LIBRARY_PATH` or `sudo`. A `"SodiumXT ABI mismatch ...
  Reinstall the packaged extension."` error means the package was built from a stale tree;
  repackage from the current one.

## Install

1. Get SodiumXT (download a release, or clone the xtalk-suite repository; SodiumXT lives
   in its `sodiumxt/` directory).
2. In the OpenXTalk / LiveCode IDE, install it through the **Extension Manager**, the same way
   you install any LCB extension. The per-platform native library under `src/code/` is
   resolved automatically by the engine.
3. Verify it loaded from the message box:

   ```
   put sxVersion()
   -- e.g. SodiumXT 0.1.0 (libsodium 1.0.20)
   -- (Linux and macOS report the pinned 1.0.20; the committed Windows DLLs are
   --  MSVC + vcpkg builds and report 1.0.22)
   ```

Once installed, the `sx*` handlers are in scope in your stacks; read
[docs/getting-started.md](docs/getting-started.md) before your first call.

## Quick start: encrypt a message with a passphrase

```livecode
local tSalt, tKey, tSealed, tPlain

-- Encrypt. Keep tSalt next to the ciphertext so you can re-derive the key later.
put sxRandomBytes(16) into tSalt
put sxPwHash(textEncode("my passphrase", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
put sxSecretBox(textEncode("Attack at dawn.", "utf-8"), tKey) into tSealed

-- Decrypt. Re-derive the same key from the stored salt, then open.
put sxPwHash(textEncode("my passphrase", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
put textDecode(sxSecretBoxOpen(tSealed, tKey), "utf-8") into tPlain   -- "Attack at dawn."
```

If the passphrase is wrong or the ciphertext was tampered with, `sxSecretBoxOpen` throws
instead of returning garbage - wrap it in `try ... catch`.

## Documentation

- **[Getting started](docs/getting-started.md)** - install and the few conventions worth
  knowing before your first call. Read first.
- **[API reference](docs/api-reference.md)** - every `sx*` signature and error convention.
- **[Recipes](docs/recipes.md)** - copy-paste solutions: file encryption, password storage,
  signing, public-key messaging, key exchange.
- **[Security model](docs/security.md)** - what libsodium guarantees, what this binding adds
  (nothing cryptographic, by design), and what an app is still responsible for. Read it
  before shipping anything that protects a user.
- **[Building](docs/building.md)** - for contributors: layout, libsodium, sanitizers, the
  static gate, packaging. `CLAUDE.md` is maintainer memory: rules, traps, the committed
  binaries and the engine evidence ledger.

Suite-wide documents: https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md

## Examples

Two ready-to-run stacks are in [`examples/`](examples):

- **`sodium-demo.livecodescript`** - an interactive, tabbed showcase with step-by-step
  guidance: passphrase encryption (with live tamper rejection), public-key messaging,
  signatures, hashing and file encryption, passphrase-derived identities, stream rekeying.
- **`sodium-tests.livecodescript`** - a self-test: `put sxSelfTest()` runs every capability
  through round-trips, known-answer vectors, and tamper / wrong-key checks and returns a
  pass/fail report.

## Security at a glance

SodiumXT is designed so the easy way is the safe way:

- Nonces are handled for you (random and prepended, or derived per chunk). The one
  caller-supplied-nonce handler, `sxChaCha20IetfXor` (ABI 10), is a building block for
  published constructions that derive their own nonces; read the argued exception in
  `docs/security.md` before touching it.
- Compare secrets with `sxMemEqual` (constant time), never with `is` or `=`.
- Use `sxRandomBytes` / `sxRandomUniform` for anything that must be unguessable, never the
  engine `random()`.
- Store the salt (and the cost settings) alongside a passphrase-derived ciphertext so you can
  re-derive and raise the cost later.

## Contributing / building from source

Most users never build anything: the extension ships prebuilt native libraries for every
platform. To build from source, change the C shim, or contribute, start with
[docs/building.md](docs/building.md).

## License

SodiumXT is released under the [MIT License](LICENSE). It statically links libsodium, which is
distributed under the ISC license. See `LICENSE` for details.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

SodiumXT is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`sodiumxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/SodiumXT: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `sodiumxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port sodiumxt --ref pull/<n>/head`, keeping its
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

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/sodium-demo.livecodescript`.
- `tools/check-docs-style.py`, `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
