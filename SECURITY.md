# Security policy

Several members of the suite handle secrets: SodiumXT (encryption,
signatures, key derivation), CoinXT (Bitcoin and Ethereum keys and
transactions), NostrXT (signed events and NIP-44 encryption), OnionXT
(Tor onion services) and the apps built on them (Riptide Social, No
Cloud Quick Share, Hold'em). Please treat a problem in any of them with
care.

## Reporting a vulnerability

Please report security problems **privately**, not in a public issue.

Use GitHub's private reporting form:
<https://github.com/SethMorrowSoftware/xtalk-suite/security/advisories/new>
(you need to be signed in to GitHub). Only the maintainers can see the
report.

If the form says private reporting is not available, open an ordinary
[issue](https://github.com/SethMorrowSoftware/xtalk-suite/issues) that
says only that you have a security report and would like a private way
to send it, with no details of the problem. A maintainer will then open
a draft security advisory and add you to it.

A problem in a member's own repository (for example
`SethMorrowSoftware/SodiumXT`) can be reported there or here; members
are developed here, so the fix will be made here.

Please include:

- the member and its version (the load checks under "Install" in the
  README, such as `sxVersion()`, print it where a member has one),
  or the commit of this repository you built from;
- the IDE and engine (OXT-Beyond, OpenXTalk, LiveCode) with its version,
  and your operating system, 32- or 64-bit;
- what an attacker can do, and what they need first;
- the smallest script that shows the problem.

This is a small volunteer project. There is no bug bounty and no
guaranteed response time, but every report is read, and a confirmed
problem is fixed before it is disclosed.

## Supported versions

Only the `main` branch and the newest
[release](https://github.com/SethMorrowSoftware/xtalk-suite/releases)
get fixes. OXT-Beyond carries its own copy of every extension, pinned
per OXT-Beyond release; a fix reaches it in the next OXT-Beyond release
after it lands here.

## What the suite does and does not promise

- Each native member is a thin binding over a widely used library
  (libsodium, libtorrent, ENet, libdatachannel, trezor-crypto and
  bitcoin-core/secp256k1, Box2D). The suite adds no cryptography of its
  own beyond what those libraries provide; OnionXT and NostrXT compose
  their siblings' primitives in script.
- Nonces are never caller-supplied for anything that seals bytes; the
  one documented exception is in `sodiumxt/docs/security.md`, which also
  describes SodiumXT's threat model.
- CoinXT signs only a digest the app hands it: the app owns custody of
  keys and money. Test with testnet first.
- OnionXT talks only to a Tor daemon on loopback that you install and
  run; its anonymity is Tor's.
- The macOS libraries are unsigned and not notarized, and the Windows
  DLLs are not code-signed.
- Testing status differs by member and platform. The README's "Where it
  stands" table and each member's `CLAUDE.md` say what has run on a
  real engine and what is "verified statically; needs an OXT pass".
  Please read them before you rely on a member for something that
  matters.
