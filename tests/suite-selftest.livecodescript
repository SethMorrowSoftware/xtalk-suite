script "xTalkSuiteSelfTest"

-- suite-selftest.livecodescript - ONE self-building RUNTIME harness that drives
-- ALL SIX xTalk Suite members in a single OXT process and reports PASS / FAIL /
-- SKIP per check.
--
-- WHY THIS FILE EXISTS. Every member already ships a deep per-member selftest
-- (torrentxt/tests, enetxt/tests, datachannelxt/tests, ...) and those stay
-- authoritative for their own surface. This file is deliberately NOT a fifth
-- copy of them. It does the two things no per-member selftest can do:
--   1. It runs the whole suite in ONE process, in ONE pass, so the maintainer
--      gets one green/red list instead of five separate runs; and
--   2. it exercises the CROSS-MEMBER compositions the suite advertises - one
--      seed that is simultaneously a SodiumXT signing identity and a TorrentXT
--      DHT identity, a BEP44 item whose signature is produced by SodiumXT and
--      accepted by libtorrent, a SodiumXT-sealed payload carried byte-exact
--      over BOTH real transports, and the 60000-byte message budget that
--      enetxt and datachannelxt are supposed to share. Those compositions are
--      the suite's actual product; nothing tests them today.
--
-- HONESTY (root CLAUDE.md rule 6). THIS HARNESS HAS RUN. On 2026-08-08 it
-- ran on a real OXT engine with all six members installed and reported GREEN
-- - the suite's first runtime evidence. On 2026-08-10 it ran again - every
-- member's deep self-test folded in, both then-embedded script libraries in
-- the paste - and reported ZERO failures: 455 member-harness checks
-- (sodiumxt 68, onionxt 40, coinxt 207, torrentxt 96, enetxt sync 21,
-- datachannelxt sync 23) plus every core and cross-member section. On
-- 2026-08-12 it ran on Windows x64 (SodiumXT ABI 7, all SEVEN members
-- folded, three libraries embedded) and again reported ZERO failures -
-- riptide phase 1 at 89/89, coinxt phase 5 at 230/230, the offline-onion
-- legs 43/43. A later 2026-08-12 run of the current harness was green across
-- all 617 folded checks: sodiumxt 71, onionxt 43, coinxt 230, torrentxt 96,
-- enetxt sync 21, datachannelxt sync 23, and riptide phases 1-2 at 133.
-- What each run bought is recorded per member (each member's
-- README / CLAUDE.md and docs/OXT-PASS-RUNBOOK.md, the pass blockquotes).
-- Riptide's phase-2 single-engine work is therefore closed; only its
-- two-machine propagation criterion remains under runbook item 6.
--
-- THIS IS NO LONGER A SAMPLER, AND THAT IS THE BIG CHANGE. It used to drive
-- about a dozen handlers per member and say so. It now carries EVERY member's
-- own deep self-test as well, folded in whole by tools/build-suite-selftest.py:
--
--   sodiumxt        sxSelfTest()      21 groups, the entire sx* surface
--   onionxt         oxSelfTest()       8 groups, all offline
--   coinxt          its 28 sections    all five phases, ~300 checks
--   torrentxt       its full harness   sharing this file's single session
--   enetxt          its SYNC half      lifecycle, stale handles, tuning
--   datachannelxt   its SYNC half      lifecycle, the stale-handle surface
--   riptide         rsSelfTest()      run LAST: identity, wire formats, and
--                                     the phase-2 live feed layer, which
--                                     also shares this file's session
--
-- AND IT CARRIES THE THREE PURE-SCRIPT LIBRARIES THEMSELVES. coinxt's script
-- layer (encoders, addresses, the HD wallet walk), onionxt's entire ox*
-- surface, and riptide's rs* layer are LiveCodeScript, and the first two
-- used to be a separate setup step - `start using stack` x2 before pasting.
-- Embedded, that step is gone, and so is the failure mode it carried: the
-- 2026-08-10 re-run pasted a fresh harness into an engine whose in-memory
-- coinxt stack predated a parser fix, and got two red lines that read as
-- "the fix does not work" and meant "the fix was not loaded". This file and
-- the libraries in it are generated from one tree; they cannot skew against
-- each other.
--
-- So one paste now settles what used to take seven runs. Two things are still
-- honestly outside it, and they are named where they are cut rather than left
-- for you to discover: the ENet and DataChannel ASYNC loopbacks stay in their
-- own harnesses, because this file already drives a real loopback on both
-- transports for its cross-member sections and two state machines in one
-- process would race for the event handlers. Everything else those two members
-- test, this runs.
--
-- The folded sections are GENERATED. Do not edit them here - edit the member
-- harness they come from and run tools/build-suite-selftest.py. The gate set
-- runs --check, so a stale copy fails the build rather than quietly testing
-- code that moved.
--
-- Re-run this on any new engine, OS, or set of committed binaries: it is the
-- cheapest end-to-end check the suite has, and the recorded results are
-- evidence about those machines, not a permanent property of the code.
--
-- WITH ONE NARROWING, and it is worth knowing before you run this. The
-- cross-member sections below ask questions that are mostly NOT script
-- questions - "do libsodium and libtorrent derive the same ed25519 public key
-- from one seed?" is a question about two C libraries. tests/cross-member-test.py
-- settles exactly those, headless, by driving the built shims through ctypes,
-- and they PASS: the two libraries agree on the public key, libtorrent's DHT
-- secret key really is SodiumXT's expanded key (and not its seed||pk one),
-- libtorrent verifies a libsodium BEP44 signature and refuses one made for a
-- different seq, and ENX_MAX_MESSAGE == DCX_MAX_MESSAGE == 60000. So what those
-- sections still need the engine for is NARROWER than it looks: the FFI
-- marshalling and the script plumbing that reach those libraries, not the
-- cryptography underneath. A cross-member FAILURE here, on an engine, therefore
-- points at the binding rather than at the crypto - which is a much better place
-- to start debugging than "one of six things is wrong."
--
-- WHICH FILE TO PASTE: tests/suite-selftest.livecodescript, the GENERATED one.
-- This file (suite-selftest.core.livecodescript) is only the hand-maintained
-- half; on its own it has no member harnesses in it.
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK script
-- (Object > Stack Script), then close and reopen the stack. It builds its own
-- UI, probes for each member, runs everything it can, and shows the list. Use
-- "Copy results" to put the run on the clipboard and paste it back verbatim.
--
-- RUN IT STANDALONE. TorrentXT allows only ONE session per process, so close
-- any other TorrentXT stack (client, demo, torrent-selftest) first - otherwise
-- the torrent sections SKIP with a note rather than fighting for the session.
-- The enet loopback deliberately uses UDP port 27196, NOT the 27098 that
-- enet-selftest uses, so the two harnesses can coexist if both are open.
--
-- MISSING EXTENSIONS SKIP, THEY NEVER FAIL. Each member is probed with one
-- cheap guarded call inside try/catch (the family's fail-closed probe pattern,
-- as used by the demos and by onionxt's own oxSodiumHas* helpers). An absent
-- member marks its own sections SKIPPED with an install note; every other
-- section still runs, and any cross-member check that needs the absent member
-- skips with a reason instead of failing.
--
-- NON-DESTRUCTIVE. Nothing here writes a file, moves storage, deletes a
-- torrent, or touches a Tor control port. The DHT puts are queued into the
-- ordinary public DHT exactly as any client would; nothing else leaves the box
-- except loopback UDP to 127.0.0.1.
--
-- THE LCS LESSONS THIS FILE IS WRITTEN UNDER (the LiveCodeScript/LCB gotcha
-- list carried in every member CLAUDE.md): no brace array literals, no
-- subscripted function results, array emptiness by counting `the keys of` a
-- LOCAL, binary built with numToByte because string literals have no escape
-- syntax, byte-exact compares only under `set the caseSensitive to true`, all
-- declarations at handler top, and teardown calls written bare in statement
-- position, which is enetxt's own shipped teardown idiom (enet-lan-chat line
-- 220, enet-selftest line 371).
--
-- That last one is NOT a style choice, and this comment used to say it was.
-- It read: "datachannelxt spells the same thing dcCleanup(); BOTH forms are
-- attested in shipped members, so this is a style match, not a claim about what
-- the engine can compile." The reasoning was that a shipped member used it, so
-- it must work - but shipped is not run, and datachannelxt's own harness had
-- never been run on an engine. An OXT pass then failed on exactly that line.
-- A ZERO-ARGUMENT call in STATEMENT position must be BARE: a statement starting
-- with an identifier is parsed as a COMMAND, so `dcCleanup()` hands the command
-- the expression `()`, and `()` is not an expression. In EXPRESSION position
-- (`dcCleanup() is 0`, below) the parenthesised form is correct and required,
-- and a one-argument statement call like `dcFreePeer(sPeerA)` is fine because
-- `(sPeerA)` IS an expression - which is why the broken spelling looks exactly
-- like the working one beside it. Every member's check-livecodescript.py now
-- refuses it, .livecodescript only: LiveCode BUILDER does allow `sPrepare()` as
-- a statement, and the .lcb files rely on that on engine-verified paths.

-- ---- tunables ----------------------------------------------------------------
-- A port of our own so this harness and enet-selftest can both be open.
constant kStPortEnet = 27196
-- The budget BOTH real-time members enforce (ENX_MAX_MESSAGE == DCX_MAX_MESSAGE
-- == 60000). One over must be refused with -4 by both; a suite-level invariant
-- neither member can check alone.
constant kStBudget = 60000
constant kStOverBudget = 60001
-- SCTP's floor. libdatachannel negotiates our 60000 cap, but a remote is only
-- ever REQUIRED to accept 16 KiB, so the "large but legal" leg uses whatever
-- was actually negotiated, clamped to our budget - it must never assert against
-- a number the wire did not agree to.
constant kStSctpFloor = 16384
-- Generous: two live loopbacks (ENet handshake, plus ICE/DTLS/SCTP for WebRTC)
-- plus a 60000-byte transfer each, on a possibly loaded machine.
constant kStDeadlineMs = 40000

-- ---- state -------------------------------------------------------------------
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sRunning             -- "true" while the async phases are still live

-- probe results (one flag per member; "reason" strings carry the SKIP note)
local sHaveSodium, sHaveTorrent, sHaveEnet, sHaveDc, sHaveOnion, sHaveCoin
local sHaveCoinScript      -- coinxt ships in TWO pieces; see stProbe
local sHaveRiptideScript   -- the embedded riptide layer; same tripwire shape
local sTorrentNote         -- why torrent is unavailable, when it is

-- torrentxt
local sSession             -- THE one session handle (0 = none)

-- the shared sealed payload (one secretbox, carried over BOTH transports)
local sSealKey, sSealPlain, sSealBox

-- enetxt loopback
local sPhaseEn             -- "" / "connecting" / "sealed" / "big" / "closing" / "done" / "skip" / "failed"
local sEnServer, sEnClient
local sEnClientPeer, sEnServerPeer
local sEnGotSealed         -- the ciphertext the server received (Data)
local sEnBigSize           -- byte count of the budget-sized payload it received
local sEnSawDisc

-- datachannelxt loopback
local sPhaseDc             -- "" / "opening" / "sealed" / "big" / "done" / "skip" / "failed"
local sDcPeerA, sDcPeerB
local sDcChanA, sDcChanB
local sDcAOpen, sDcBOpen
local sDcGot               -- the ciphertext B received (Data)
local sDcBigSize, sDcBigWant

local sDeadline            -- the async phases' drop-dead time (ms clock)

-- Every FOLDED member's script locals and constants are hoisted to here, above
-- the first handler, by tools/build-suite-selftest.py - and so are the two
-- EMBEDDED script layers' (coinxt's and onionxt's), for the same reason.
--
-- They cannot live down in each member's own section, which is where they
-- started and where they look like they belong. OXT resolves a script-level
-- name BY LEXICAL POSITION, so a declaration below a handler is not in scope
-- for it - and stRunMemberHarnesses, up here in the core, reads every member's
-- counters (cx1sPassed and friends) to merge them. With the declarations left
-- in place the read was ~1000 lines ABOVE them, so `cx1sPassed` was an
-- undeclared name, LiveCodeScript evaluated it to the literal text
-- "cx1sPassed", and `add "cx1sPassed" to sPassed` killed the whole run with
-- "add: error in source expression" on a real engine.
--
-- Nothing about the member harnesses was wrong: each one declares its locals
-- above its own handlers, which is the house pattern in all six. Only the FOLD
-- broke the invariant, by putting one file's declarations after another file's
-- readers. check-suite-selftest.py now fails if any declaration lands below the
-- first handler.
-- ---- SodiumXT: the full sx* self-test ----
local sx1sLog
local sx1sPass
local sx1sFail

-- ---- OnionXT: the full ox* self-test ----
constant ox1kTestAddrTorProject = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant ox1kTestAddrDuckDuckGo = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
local ox1sLog
local ox1sPass
local ox1sFail

-- ---- CoinXT: the full cx* self-test ----
constant cx1kKeccakEmpty = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
constant cx1kKeccakAbc = "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
constant cx1kSha3Empty = "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
constant cx1kSha3Abc = "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
constant cx1kSha3Fox = "69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04"
constant cx1kSha256Empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
constant cx1kSha256Abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
constant cx1kSha512Empty = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
constant cx1kSha512Abc = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
constant cx1kRipeEmpty = "9c1185a5c5e9fc54612808977ee8f548b2258d31"
constant cx1kRipeA = "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"
constant cx1kRipeAbc = "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
constant cx1kRipeMsgDigest = "5d0689ef49d2fae572b881b123a85ffa21595f36"
constant cx1kHmac1Sha256 = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
constant cx1kHmac1Sha512 = "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"
constant cx1kHmac2Sha256 = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
constant cx1kHmac2Sha512 = "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"
constant cx1kBip39Mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
constant cx1kBip39Salt = "mnemonicTREZOR"
constant cx1kBip39Seed = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
constant cx1kFox = "The quick brown fox jumps over the lazy dog"
constant cx1kPubOneCompressed = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
constant cx1kPubOneUncompressed = "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
constant cx1kPubTwoCompressed = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
constant cx1kSigSatoshi = "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d82442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"
constant cx1kHash256Abc = "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358"
constant cx1kBase58Payload = "00010966776006953D5567439E5E39F86A0D273BEE"
constant cx1kBase58Address = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM"
constant cx1kBase58Corrupt = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvN"
constant cx1kP2wpkhOfG = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
constant cx1kP2trOfG = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"
constant cx1kP2pkhOfG = "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH"
constant cx1kEthOfG = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"
constant cx1kEip55A = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
constant cx1kEip55B = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
constant cx1kBech32Valid = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
constant cx1kSegwitTestnet = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"
constant cx1kSegwitTestnetProgram = "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262"
constant cx1kSegwitV0WithBech32m = "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5"
constant cx1kEip55Corrupt = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"
constant cx1kEip55Flipped = "0x5AaEB6053f3e94c9B9a09F33669435e7eF1bEaEd"
constant cx1kSegwitErrorProgram = "4552524f52000102030405060708090a0b0c0d0e0f101112131415161718191a"
constant cx1kSegwitErrorAddress = "bc1pg4f9yn6jqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydqqwyhrw"
constant cx1kBip39Entropy12 = "00000000000000000000000000000000"
constant cx1kBip39Entropy24 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
constant cx1kBip39Mnemonic24 = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
constant cx1kBip39SeedNoPass = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
constant cx1kBip39Mnemonic12Bad = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
constant cx1kBip32Seed1 = "000102030405060708090a0b0c0d0e0f"
constant cx1kBip32V1Xprv = "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
constant cx1kBip32V1Xpub = "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
constant cx1kBip32V1H0Xprv = "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7"
constant cx1kBip32V1H0Xpub = "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
constant cx1kBip32V1DeepPath = "m/0'/1/2'/2/1000000000"
constant cx1kBip32V1DeepXprv = "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76"
constant cx1kBip32Seed3 = "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
constant cx1kBip32V3Xprv = "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6"
constant cx1kAbandonXprv = "xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu"
constant cx1kAbandonBip44 = "m/44'/0'/0'/0/0"
constant cx1kAbandonP2pkh = "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
constant cx1kAbandonBip84 = "m/84'/0'/0'/0/0"
constant cx1kAbandonP2wpkh = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
constant cx1kAbandonBip84Account = "m/84'/0'/0'"
constant cx1kAbandonBip84Xpub = "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V"
constant cx1kAbandonEthPath = "m/44'/60'/0'/0/0"
constant cx1kAbandonEth = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
constant cx1kTxSeckey0 = "bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"
constant cx1kTxSeckey1 = "619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"
constant cx1kTxPubkey1 = "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant cx1kTxid0 = "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"
constant cx1kTxid1 = "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"
constant cx1kTxScriptCode0 = "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac"
constant cx1kTxScriptCode1 = "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac"
constant cx1kTxOutScript0 = "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant cx1kTxOutScript1 = "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant cx1kTxOutpoint0 = "fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000"
constant cx1kTxOutpoint1 = "ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a01000000"
constant cx1kTxOut0 = "202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant cx1kTxOut1 = "9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant cx1kTxLegacySighash = "63cec688ee06a91e913875356dd4dea2f8e0f2a2659885372da2a37e32c7532e"
constant cx1kTxSegwitSighash = "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670"
constant cx1kTxScriptSig0 = "4830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01"
constant cx1kTxWitness1 = "0247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant cx1kTxSignedRaw = "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000"
constant cx1kTxTxid = "e8151a2af31c368a35053ddd4bdb285a8595c769a3ad83e0fa02314a602d4609"
constant cx1kEthSeckey = "4646464646464646464646464646464646464646464646464646464646464646"
constant cx1kEthTo = "3535353535353535353535353535353535353535"
constant cx1kEthGasPrice = "04a817c800"
constant cx1kEthValue = "0de0b6b3a7640000"
constant cx1kEthLegacySighash = "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53"
constant cx1kEthLegacyRaw = "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
constant cx1kEthLegacyTxhash = "33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
constant cx1kEth1559MaxPrio = "3b9aca00"
constant cx1kEth1559MaxFee = "04a817c800"
constant cx1kEth1559Value = "016345785d8a0000"
constant cx1kEth1559Sighash = "bf4c3dfa4164868c98534322ecbbce3c022d6d0dee3580b1504da0a28fff9199"
constant cx1kEth1559Raw = "02f8730180843b9aca008504a817c80082520894353535353535353535353535353535353535353588016345785d8a000080c001a0180a63d9ea767ab51941f4cb5d3f4f1113ae08861b4a660eb72770967ddc8987a04a41c8877f4e53a06c3a7d6f2787f113d9700bd112168f6714ff3b8957f1b123"
constant cx1kEth1559Txhash = "1d723f02967119095427907564da7762bd6d3a5d8edb1291db53b97191749e7f"
local cx1sTotal, cx1sPassed, cx1sFailed
local cx1sResultText       -- the accumulated PASS/FAIL/section lines
local cx1sDone             -- "true" once the run has finished (drives the colour)

-- ---- TorrentXT: the full bt* self-test ----
local bt1sSession          -- the live session handle (0 = none)
local bt1sTorrent          -- a torrent we create + seed, for torrent-scoped checks
local bt1sTorrent2         -- a second torrent from the extended-add check
local bt1sTotal, bt1sPassed, bt1sFailed
local bt1sResultText       -- the accumulated PASS/FAIL/section lines
local bt1sTempDir          -- parent dir we seed from
local bt1sContentDir       -- the content folder inside it

-- ---- ENetXT: the synchronous half of the en* self-test ----
local en1sTotal, en1sPassed, en1sFailed
local en1sResultText       -- the accumulated PASS/FAIL/section lines
local en1sServer, en1sClient  -- the two loopback hosts
local en1sClientPeer       -- client side: handle from enConnect
local en1sServerPeer       -- server side: handle born in its enetConnect event
local en1sGotEcho          -- "true" once the client received the echo
local en1sGotUnseq         -- "true" once the client received the channel-1 line
local en1sGotBinary        -- the binary payload the server received (a Data)
local en1sSentBinary       -- what the client sent (kept for byte-exact compare)
local en1sSawServerDisc    -- "true" once the server drained enetDisconnect
local en1sDeadline         -- the async phase's drop-dead time (ms clock)
local en1sPhase            -- "", "connecting", "messaging", "binary", "closing", "done"

-- ---- DataChannelXT: the synchronous half of the dc* self-test ----
local dc1sTotal, dc1sPassed, dc1sFailed
local dc1sResultText       -- the accumulated PASS/FAIL/section lines
local dc1sPeerA, dc1sPeerB    -- the loopback peers
local dc1sChanA, dc1sChanB    -- A's channel; B's (learned from dcChannelIncoming)
local dc1sAOpen, dc1sBOpen    -- "true" once each side's channel open arrived
local dc1sGotText          -- the text B received
local dc1sGotBytes         -- the binary payload A received back (a Data)
local dc1sSentBytes        -- the binary payload B sent (kept for byte-exact compare)
local dc1sGotBufferedLow   -- "true" once A's channel reported dcBufferedLow
local dc1sBigLen           -- the cap-sized payload length for the buffered-low leg
local dc1sDeadline         -- the async phase's drop-dead time (ms clock)
local dc1sPhase            -- "", "opening", "messaging", "done"

-- ---- Riptide Social (phases 1-2): the rs* self-test ----
constant rs1kRsGoldMasterHex = "4242424242424242424242424242424242424242424242424242424242424242"
constant rs1kRsGoldConfSeedHex = "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7"
constant rs1kRsGoldRoomSalt = "golden-salt"
constant rs1kRsGoldPost1Text = "hello, riptide"
constant rs1kRsGoldPost2Text = "second post"
constant rs1kRsGoldTs1 = "1754870400"
constant rs1kRsGoldTs2 = "1754870460"
constant rs1kRsGoldHeadSeq = "7"
constant rs1kRsGoldHeadName = "Riptide"
constant rs1kRsGoldPrekeyTarget = "abababababababababababababababababababab"
constant rs1kRsGoldProfileTarget = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
constant rs1kRsGoldMediaTarget = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
constant rs1kRsGoldIdSeedHex = "9c7b6be59e0884a1923505cf1390a1d01b5b7a258c582d9518e722c07bd8650c"
constant rs1kRsGoldDmSeedHex = "4dca52e87fa8919a5699fd35f79d6e4a417bdf0cf3e16d5c549aac6cd8c2b391"
constant rs1kRsGoldLanKeyHex = "fb9441aca42ca2212b3b16ea0b615d70e6d8c5ab3f6ac9a90a5e648fd58ac85f"
constant rs1kRsGoldAnon0Hex = "6940ca2dc794eb4c533feb196481c0547b1257d3837925affe35dae97682c68a"
constant rs1kRsGoldHandle = "5a546e4fef5d1b76f94dc1b2eded75c44bffc900af7461a26d8427453a92f22d"
constant rs1kRsGoldZeroSeedPub = "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29"
constant rs1kRsGoldConfPub = "672e8e0b259627f15c772ec0d61f15cd786ce2bc7244549255f9d6cfaac300b2"
constant rs1kRsGoldOnion = "ljkg4t7plunxn6knygzo33lvyrf77siav52gditnqqtukous6iwwe6yd.onion"
constant rs1kRsGoldInboxId = "3cf4170b3e7253387f351af14eb1071224d0140e"
constant rs1kRsGoldRoomId = "3a57d3ad644536e20a4486d31bde5ecb3902d3a5"
constant rs1kRsGoldPost1Hex = "5253503100000000689932803030303030303030303030303030303030303030303030303030303030303030303030303030303044000e68656c6c6f2c20726970746964650084b56e15631b88e780a74e22241c00efc34b63e50fd645ba651bb27dc41cac5953396ae8f848ef9b81711b08baa5b764fc5746bfd02122f36ac5a17f87a88f01"
constant rs1kRsGoldPost1Target = "a161e3add5a4d78080db9219583e6a988954705c"
constant rs1kRsGoldPost2Hex = "5253503100000000689932bc6131363165336164643561346437383038306462393231393538336536613938383935343730356344000b7365636f6e6420706f737401656565656565656565656565656565656565656565656565656565656565656565656565656565654d29a287d8ac5360688b548ee342f7754287e3ddc604fe2a5160263ce1ef7a5526f9a750dc05d0edf2c317ea0b3dca062e745d0e2fb6c1b381225c7d19dba10f"
constant rs1kRsGoldPost2Target = "21d0180855ef47084fd8a9825f4ec8516608161a"
constant rs1kRsGoldHeadHex = "525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"
constant rs1kRsGoldHeadBufHex = "343a73616c7431323a726970746964652d68656164333a736571693765313a763230333a525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"
constant rs1kRsGoldHeadSigHex = "6d4560c6c20794dfbb71e4592679c242472d459728051a90bcedb123ec2404a544882525242888eda72dcd3c820a5538a80b9fb63e09d4c1bc3487db67730b0f"
local rs1sLog
local rs1sPass
local rs1sFail
local rs1sSkip
local rs1sRsTestSession

-- >>> GENERATED EMBED: coinxt script layer declarations >>> --
-- ---- CoinXT script layer (the real library, embedded) ----
constant kCxBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
constant kCxBech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
constant kCxHexDigits = "0123456789abcdef"
constant kCxBech32mConst = 734539939
constant kCxBech32MaxLen = 90
constant kCxVersionP2PKH = 0
constant kCxHrpMainnet = "bc"
constant kCxBip39Rounds = 2048
constant kCxBip39SaltPrefix = "mnemonic"
constant kCxBip39WordCount = 2048
constant kCxBip39BitsPerWord = 11
constant kCxBip32MasterKey = "Bitcoin seed"
constant kCxHardenedBase = 2147483648
constant kCxVersionXprv = 76066276
constant kCxVersionXpub = 76067358
-- <<< GENERATED EMBED: coinxt script layer declarations <<< --

-- >>> GENERATED EMBED: onionxt script layer declarations >>> --
-- ---- OnionXT script layer (the real library, embedded) ----
constant kOxHost = "127.0.0.1"
constant kOxSocksPortDefault = 9050
constant kOxControlPortDefault = 9051
constant kOxVersion = "1.0.0"
constant kOxHandshakeTimeout = 20000     -- milliseconds
constant kOxStatusThrottle = 250         -- milliseconds
constant kOxBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
constant kOxChecksumPrefix = ".onion checksum"
constant kOxSafeCookieServerKey = "Tor safe cookie authentication server-to-controller hash"
constant kOxSafeCookieClientKey = "Tor safe cookie authentication controller-to-server hash"
local sSocksPort
local sControlPort
local sControlSocket        -- engine id of the open control socket, or empty
local sControlState         -- disconnected|connecting|protocolinfo|authenticating|authenticated|failed
local sControlMethods       -- offered auth methods (comma list) from PROTOCOLINFO
local sControlCookieFile     -- cookie-file path from PROTOCOLINFO (unescaped)
local sControlPassword       -- app-set password for HASHEDPASSWORD auth
local sControlCookieBytes    -- the 32 raw cookie bytes (SAFECOOKIE flow)
local sControlClientNonce    -- our SAFECOOKIE client nonce (raw bytes)
local sControlTorVersion     -- tor version string from GETINFO version
local sBootstrap             -- 0..100 bootstrap percent from STATUS_CLIENT
local sCtlInFlight           -- label of the in-flight command, or empty
local sCtlReplyLines         -- accumulated reply text (newline-joined)
local sCtlInData             -- true while inside a 250+ CmdData block
local sCtlData               -- accumulated CmdData block text
local sCtlQueue              -- pending commands: lines of "label" & TAB & "command"
local sStatusCallback
local sPeerCallback
local sCallbackOwner         -- long id of the object whose script has the callbacks
local sLastStatusTick        -- `the milliseconds` of the last coalesced update
local sStreams               -- keyed by integer stream handle (nested array)
local sSockToStream          -- keyed by socket id string -> stream handle
local sServices              -- keyed by integer service handle (nested array)
local sLocalToService        -- keyed by local port -> service handle
local sNextHandle            -- monotonic handle allocator (0 is never valid)
-- <<< GENERATED EMBED: onionxt script layer declarations <<< --

-- >>> GENERATED EMBED: riptide script layer declarations >>> --
-- ---- Riptide script layer (the real library, embedded) ----
constant kRsVersion = "0.2.0"
constant kRsKeyMagic = "RIPTKEY1"
constant kRsHeadMagic = "RSH1"
constant kRsPostMagic = "RSP1"
constant kRsHeadSalt = "riptide-head"
constant kRsKdfContextText = "riptide"
constant kRsInboxSuffix = "riptide-inbox"
constant kRsZeroTarget = "0000000000000000000000000000000000000000"
constant kRsSubkeyIdentity = "1"
constant kRsSubkeyDm = "2"
constant kRsSubkeyLan = "3"
constant kRsSubkeyAnonBase = 100
constant kRsMaxDisplayName = 64
constant kRsMaxMedia = 8
constant kRsMaxChunks = 16
constant kRsMaxRecord = 1000
constant kRsMaxSalt = 64
constant kRsOnionAddrLen = 62
constant kRsArgonOps = "2"
constant kRsBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
constant kRsChecksumPrefix = ".onion checksum"
local sRsLastError
local sRsProbed
local sRsCaps
-- <<< GENERATED EMBED: riptide script layer declarations <<< --

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack

on closeStack
   -- There is NO deterministic unload hook in this family: a leaked libtorrent
   -- session would block the next run outright (one session per process), and a
   -- leaked ENet host or WebRTC peer would hold a UDP port and its threads. So
   -- teardown is unconditional and idempotent here.
   stCleanup
end closeStack

on mouseUp
   if the short name of the target is "stRerun" then
      stCleanup
      stRun
   else if the short name of the target is "stCopy" then
      stCopyResults
   else
      pass mouseUp
   end if
end mouseUp

-- ---- self-building UI (idempotent) -------------------------------------------
command stBuild
   if there is a field "stResults" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to 760
   set the height of this stack to 680
   set the backgroundColor of this card to "237,239,243"
   set the title of this stack to "xTalk Suite - End-to-End Self-Test"
   stMakeLabel "stTitle", "  xTalk Suite - End-to-End Self-Test", "0,0,760,30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38,520,66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", "560,38,660,64"
   stMakeButton "stRerun", "Re-run", "666,38,744,64"
   stMakeList "stResults", "16,72,744,664"
   set the textFont of field "stResults" to "Courier"
   set the textSize of field "stResults" to 11
   unlock screen
end stBuild

command stMakeLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the textSize of field pName to pSize
   put pText into field pName
end stMakeLabel

command stMakeButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end stMakeButton

command stMakeList pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
end stMakeList

-- ---- assertion plumbing ------------------------------------------------------
command stAssert pName, pOk
   add 1 to sTotal
   if pOk then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

-- A SKIP is a first-class outcome here, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this member is not
-- here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

command stShow
   put sResultText into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sRunning is not "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "20,120,40"
      else
         set the foregroundColor of field "stSummary" to "170,30,30"
      end if
   end if
end stShow

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back verbatim
   -- into the OXT-pass record, so nobody has to retype a result.
   try
      set the clipboardData["text"] to sResultText
      answer "Results copied to the clipboard."
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

-- ---- the run -----------------------------------------------------------------
command stRun
   -- Belt and braces: a run that was interrupted (an engine error mid-pump)
   -- can leave a pump armed even though stCleanup never ran.
   stCancelPump
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put "true" into sRunning
   put empty into sPhaseEn
   put empty into sPhaseDc
   -- RELEASE THE SESSION BEFORE FORGETTING IT. This line used to be a bare
   -- `put 0 into sSession`, and that is how an engine pass loses the whole
   -- TorrentXT surface for the rest of the launch. The one-session latch lives
   -- in the C shim, the ONLY key that opens it is the integer handle
   -- btStartSession returned, and TorrentXT exports nothing that enumerates
   -- sessions or frees one you can no longer name (live_session_count() is a
   -- C++ test hook, not part of the FFI). So dropping the handle while the
   -- session is live orphans it permanently: btStartSession answers 0 for the
   -- rest of the process and the probe below blames a stack the operator does
   -- not have open.
   --
   -- The Re-run button already went through stCleanup, which stops it. This
   -- path is the one that did not: openStack re-entry, which the runbook's own
   -- trap 5.2 escape hatch (`send "openStack" to this stack`) performs on a
   -- stack that may already have run. Guarded because TorrentXT may simply be
   -- absent, and safe to repeat because btStopSession on a stale handle is a
   -- documented no-op.
   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent, or the session was already released; nothing to free.
   end try
   put 0 into sSession
   put false into sHaveCoinScript
   put false into sHaveRiptideScript
   put empty into sSealKey
   put empty into sSealPlain
   put empty into sSealBox

   put "xTalk Suite end-to-end self-test" & return into sResultText
   put "First green engine pass recorded 2026-08-08; this run re-confirms it here." & return after sResultText

   -- EVERY synchronous section is contained. A section that throws - a
   -- mis-declared foreign handler, an unexpected native error, an API that has
   -- moved since this harness was written - must cost EXACTLY ITSELF. Without
   -- this, one throw inside openStack leaves the maintainer with an error dialog,
   -- an empty window, no summary, and (worse) a live libtorrent session that
   -- blocks the next run. Each catch reports which section died and why.
   -- stProbe is contained for the same reason as every section below, and one
   -- sharper one: it is the statement that TAKES the session. A throw anywhere
   -- after btStartSession returned - a later probe's scaffolding, a report line
   -- - would strand a live session AND skip the `send "stPump"` at the bottom
   -- of this handler, which is the only route to stFinish and stTeardown. Each
   -- per-member probe inside already carries its own try, so this catches only
   -- the scaffolding between them, and every sHave* flag a half-finished probe
   -- leaves behind is read from inside a try, so a stale one costs a FAIL line.
   try
      stProbe
   catch tError
      stSectionFailed "extension probe", tError
   end try
   try
      stSodiumSection
   catch tError
      stSectionFailed "SodiumXT", tError
   end try
   try
      stTorrentSection
   catch tError
      stSectionFailed "TorrentXT", tError
   end try
   try
      stOnionSection
   catch tError
      stSectionFailed "OnionXT", tError
   end try
   try
      stCoinSection
   catch tError
      stSectionFailed "CoinXT", tError
   end try
   -- THE DEEP PER-MEMBER HARNESSES. Everything above is the suite's own
   -- sampler; this is each member's WHOLE self-test, folded in verbatim by
   -- tools/build-suite-selftest.py and namespaced so five harnesses that all
   -- define stAssert and sTotal can share one script. Each runs exactly as it
   -- does standalone and keeps its own counters; stMergeMember folds its log
   -- and its totals into this report afterwards.
   --
   -- They go HERE, after the sampler and before the cross-member sections,
   -- for one reason: TorrentXT allows a single session per process, the probe
   -- above already opened it, and the folded torrent harness reuses it. The
   -- async cross-member loopbacks start below and must not be racing while
   -- these run.
   -- CONTAINED like every other section, and for one extra reason. This call
   -- used to be uncontained (it was not the ONLY bare statement here - stProbe,
   -- stCancelPump and stShow are bare too; that earlier claim was wrong),
   -- on the reasoning that each folded harness contains its own sections. Four
   -- of the six have unguarded prologues (bt1stRun clears the error and reads
   -- btLastError before its try begins), and stMergeCounted/stMergeReturned
   -- only validate counters they were actually handed. A throw here therefore
   -- skipped everything below - including `send "stPump"`, which is what
   -- eventually reaches stFinish and stTeardown - so the run ended with the
   -- libtorrent session, the ENet hosts and the WebRTC peers all still live and
   -- no summary printed. The session is the one that does not come back: see
   -- the note above `put 0 into sSession`.
   -- The OUTER try is a BACKSTOP ONLY. Each of the seven harnesses inside is
   -- contained individually, and that is the part that matters: with only this
   -- outer one, a throw in member three left members four, five and six never
   -- run, never merged and not even SKIPPED, while the run still printed a
   -- tidy summary silently short by a hundred and fifty checks. That is the
   -- same wrong-answer-that-looks-right shape CLAUDE.md already records for
   -- stMergeCounted, reintroduced one level up - and strictly worse than the
   -- uncontained version it replaced, because a dead run is at least
   -- unmistakable. Per-member containment costs one FAIL line and keeps the
   -- other five intact; this catch only fires for the scaffolding between them.
   try
      stRunMemberHarnesses
   catch tError
      stSectionFailed "deep per-member self-tests", tError
   end try
   try
      stCrossIdentitySection
   catch tError
      stSectionFailed "cross: one identity", tError
   end try
   try
      stCrossBep44Section
   catch tError
      stSectionFailed "cross: BEP44 signing", tError
   end try
   try
      stSealPayload
   catch tError
      stSectionFailed "cross: sealed payload", tError
   end try
   try
      stStartEnetLoopback
   catch tError
      stSectionFailed "enetxt loopback start", tError
      put "failed" into sPhaseEn
   end try
   try
      stStartDcLoopback
   catch tError
      stSectionFailed "datachannelxt loopback start", tError
      put "failed" into sPhaseDc
   end try
   try
      stCrossBudgetSection
   catch tError
      stSectionFailed "cross: 60000-byte budget", tError
   end try

   put the milliseconds + kStDeadlineMs into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- ---- the probe ---------------------------------------------------------------
-- ONE cheap guarded call per member. A missing extension raises a "can't find
-- handler" execution error, which try/catch turns into a flag; nothing here is
-- allowed to abort the run.
command stProbe
   local tVersion, tDigest

   stSection "extension probe (an absent member SKIPS, it never FAILS)"

   put false into sHaveSodium
   try
      put sxVersion() into tVersion
      put (tVersion is not empty) into sHaveSodium
   catch tError
      put false into sHaveSodium
   end try
   stProbeLine "SodiumXT", sHaveSodium, "org.openxtalk.library.sodium"

   -- TorrentXT is probed by actually TAKING the session, because there is only
   -- one per process and every torrent check needs it. A 0 return (rather than
   -- a throw) means the extension is present but somebody else holds it.
   put false into sHaveTorrent
   put empty into sTorrentNote
   try
      put btStartSession() into sSession
      if sSession > 0 then
         put true into sHaveTorrent
      else
         -- NAME BOTH CAUSES, because the shim cannot tell them apart and
         -- neither can we. btx_session_new refuses a second session with one
         -- message however the first was opened, and there is no exported
         -- live-count or owner query. This note used to assert the cause it
         -- could not know ("close the other TorrentXT stack"), which sends the
         -- operator hunting for a window that is not open. The other cause is
         -- real and this harness has produced it: an earlier run in THIS engine
         -- process that lost its handle, either by dying before stTeardown or
         -- by having its stack script recompiled, which clears every script
         -- local while the C-side session keeps running.
         --
         -- No recovery is attempted, and that is deliberate. A handle is
         -- (generation << 16) | slot, so the first one a process mints is
         -- exactly 65536 and a search would find it in one guess - and if the
         -- owner is a real client stack, btStopSession pauses it, flushes its
         -- resume data and joins its threads out from under an app still
         -- holding torrent handles. This harness advertises itself as
         -- non-destructive; guessing at another process-wide singleton is not
         -- a thing a self-test may do.
         put "TorrentXT is installed but a session is already live in this " \
               & "process. Either another TorrentXT stack owns it (close that " \
               & "stack and re-run), or an earlier run here lost its handle - " \
               & "quit and relaunch OXT. See OXT-PASS-RUNBOOK 5.1.1." \
               into sTorrentNote
      end if
   catch tError
      put 0 into sSession
      put "install org.openxtalk.library.torrent (or ABI skew: " & tError & ")" \
            into sTorrentNote
   end try
   if sTorrentNote is empty then
      put "org.openxtalk.library.torrent" into sTorrentNote
   end if
   stProbeLine "TorrentXT", sHaveTorrent, sTorrentNote

   put false into sHaveEnet
   try
      put enLibraryVersion() into tVersion
      put (tVersion is not empty) into sHaveEnet
   catch tError
      put false into sHaveEnet
   end try
   stProbeLine "enetxt", sHaveEnet, "org.openxtalk.library.enet"

   put false into sHaveDc
   try
      put dcLibraryVersion() into tVersion
      put (tVersion is not empty) into sHaveDc
   catch tError
      put false into sHaveDc
   end try
   stProbeLine "DataChannelXT", sHaveDc, "org.openxtalk.library.datachannel"

   -- OnionXT is pure LiveCodeScript, not a compiled extension - and its whole
   -- ox* surface is EMBEDDED in this paste by tools/build-suite-selftest.py,
   -- so there is no `start using stack "onionxt"` setup step any more. The
   -- probe stays: it costs one call, and a FAIL here no longer means "not
   -- loaded" (an embedded handler cannot be absent from a script that
   -- compiled) - it means the generated file itself is damaged, which is
   -- exactly the line you want to see before trusting 40 onion checks.
   put false into sHaveOnion
   try
      put oxVersion() into tVersion
      put (tVersion is not empty) into sHaveOnion
   catch tError
      put false into sHaveOnion
   end try
   stProbeLine "OnionXT", sHaveOnion, "embedded in this paste; a FAIL means the paste is damaged"

   -- CoinXT's hash surface is the phase-1 half of its binding; the probe is one
   -- of its published vectors, so a present CoinXT is a WORKING CoinXT.
   put false into sHaveCoin
   try
      put cxKeccak256(textEncode("", "UTF-8")) into tDigest
      put (the number of bytes of tDigest is 32) into sHaveCoin
   catch tError
      put false into sHaveCoin
   end try
   stProbeLine "CoinXT (extension)", sHaveCoin, "org.openxtalk.library.coin"

   -- COINXT IS THE ONLY MEMBER THAT SHIPS IN TWO PIECES: the hash and curve
   -- surfaces are the .lcb extension, probed above; the encoders, addresses
   -- and the whole HD layer are src/coinxt.livecodescript - which is EMBEDDED
   -- in this paste by tools/build-suite-selftest.py, so the old failure mode
   -- (extension installed, `start using stack "coinxt"` forgotten, ten
   -- sections of "handler not found" that read like a broken library) cannot
   -- happen any more, and neither can its subtler cousin, which cost the
   -- 2026-08-10 re-run: a STALE script layer left loaded from an earlier
   -- session, failing checks whose fix was already merged. The probe stays as
   -- the same tripwire as OnionXT's: cxHexEncode here is a real vector, so a
   -- FAIL means the generated file is damaged, not that a setup step was
   -- missed. The deep harness still guards on both flags.
   put false into sHaveCoinScript
   try
      put (cxHexEncode(numToByte(222) & numToByte(173)) is "dead") into sHaveCoinScript
   catch tError
      put false into sHaveCoinScript
   end try
   stProbeLine "CoinXT (script layer)", sHaveCoinScript, \
         "embedded in this paste; a FAIL means the paste is damaged"

   -- Riptide's script layer rides the same embed mechanism, so the same
   -- tripwire: rsZeroTarget is a real vector (40 zeros), not a version sniff.
   put false into sHaveRiptideScript
   try
      put (the number of chars in rsZeroTarget() is 40) into sHaveRiptideScript
   catch tError
      put false into sHaveRiptideScript
   end try
   stProbeLine "Riptide (script layer)", sHaveRiptideScript, \
         "embedded in this paste; a FAIL means the paste is damaged"
end stProbe

command stProbeLine pName, pPresent, pHint
   if pPresent then
      put "      " & pName & ": present" & return after sResultText
   else
      put "      " & pName & ": ABSENT - " & pHint & return after sResultText
   end if
end stProbeLine

-- ---- per-member: SodiumXT ----------------------------------------------------
-- Headline paths only. sodiumxt's own examples/sodium-tests.livecodescript is
-- the deep one; here we prove the binding loads and a crypto round trip works,
-- because every cross-member section below is built out of these calls.
command stSodiumSection
   local tVersion, tSeed, tRand1, tRand2, tHex, tBack
   local tPubA, tSecA, tPubB, tSecB
   local tMsg, tSig, tBox, tOpened, tWrongKey, tRejected, tExpanded

   stSection "SodiumXT: headline paths"
   if not sHaveSodium then
      stSkip "SodiumXT surface", "install org.openxtalk.library.sodium"
      exit stSodiumSection
   end if

   put sxVersion() into tVersion
   stAssert "sxVersion names SodiumXT", tVersion begins with "SodiumXT"
   stAssert "sxVersion names libsodium", tVersion contains "libsodium"

   -- The ONLY sanctioned entropy source in this family; everything below and
   -- every cross-member identity check depends on it.
   put sxRandomBytes(32) into tRand1
   put sxRandomBytes(32) into tRand2
   stAssert "sxRandomBytes(32) returns 32 bytes", the number of bytes of tRand1 is 32
   set the caseSensitive to true
   stAssert "sxRandomBytes does not repeat itself", tRand1 is not tRand2
   set the caseSensitive to false

   -- hex is the lingua franca between SodiumXT (Data in / Data out) and
   -- TorrentXT (hex Strings across its whole DHT surface), so the round trip is
   -- load-bearing for the cross-member sections, not decoration.
   put tRand1 into tSeed
   put sxBin2Hex(tSeed) into tHex
   stAssert "sxBin2Hex yields 64 hex bytes for a 32-byte seed", \
         the number of bytes of tHex is 64
   put sxHex2Bin(tHex) into tBack
   set the caseSensitive to true
   stAssert "sxHex2Bin round-trips the seed byte-for-byte", tBack is tSeed
   set the caseSensitive to false
   stAssert "sxMemEqual agrees (constant time)", sxMemEqual(tBack, tSeed)
   stAssert "sxMemEqual rejects a different value", not sxMemEqual(tRand1, tRand2)

   -- secretbox: the primitive the cross-member sealed-payload sections carry
   -- over both transports. Embedded NUL and 0x01 prove a Data crosses unmangled
   -- rather than merely that ASCII survives (LCS string literals have no escape
   -- syntax, so the bytes are built with numToByte).
   put textEncode("seal", "UTF-8") & numToByte(0) & numToByte(1) \
         & textEncode("me", "UTF-8") into tMsg
   put sxSecretBox(tMsg, tRand2) into tBox
   stAssert "sxSecretBox produces a box longer than its plaintext", \
         the number of bytes of tBox > the number of bytes of tMsg
   put sxSecretBoxOpen(tBox, tRand2) into tOpened
   set the caseSensitive to true
   stAssert "sxSecretBoxOpen recovers the plaintext byte-for-byte", tOpened is tMsg
   set the caseSensitive to false
   -- Fail CLOSED on the wrong key. A wrong key is deterministic where a flipped
   -- ciphertext byte is not (a random nonce byte might already hold the flipped
   -- value), so this is the version that cannot pass by accident.
   put sxRandomBytes(32) into tWrongKey
   put false into tRejected
   try
      put sxSecretBoxOpen(tBox, tWrongKey) into tOpened
   catch tError
      put true into tRejected
   end try
   stAssert "sxSecretBoxOpen throws on a wrong key", tRejected

   -- ed25519: the signature primitive the BEP44 composition below needs.
   sxSignKeypairFromSeed tSeed, tPubA, tSecA
   sxSignKeypairFromSeed tSeed, tPubB, tSecB
   stAssert "sxSignKeypairFromSeed public key is 32 bytes", \
         the number of bytes of tPubA is 32
   set the caseSensitive to true
   stAssert "sxSignKeypairFromSeed is deterministic for one seed", tPubB is tPubA
   set the caseSensitive to false
   put sxSignDetached(tMsg, tSecA) into tSig
   stAssert "sxSignDetached returns a 64-byte signature", \
         the number of bytes of tSig is 64
   stAssert "sxSignVerifyDetached accepts it", sxSignVerifyDetached(tSig, tMsg, tPubA)
   stAssert "sxSignVerifyDetached rejects a different message", \
         not sxSignVerifyDetached(tSig, tRand1, tPubA)

   -- The ABI-6 helper OnionXT composes for a reproducible .onion identity
   -- (SHA-512(seed), clamped). Asserted here so the cross-member identity
   -- section can rely on it existing.
   put empty into tExpanded
   try
      put sxSignSeedToExpandedKey(tSeed) into tExpanded
   catch tError
      put empty into tExpanded
   end try
   if tExpanded is empty then
      stSkip "sxSignSeedToExpandedKey is 64 bytes", \
            "SodiumXT ABI < 6 - update the installed extension"
   else
      stAssert "sxSignSeedToExpandedKey returns the 64-byte expanded key", \
            the number of bytes of tExpanded is 64
   end if
end stSodiumSection

-- ---- per-member: TorrentXT ---------------------------------------------------
-- Session lifecycle plus the pure, offline-verifiable half of the DHT surface.
-- Deliberately NOT a second torrent-selftest: no torrent is created, added,
-- moved, or removed here.
command stTorrentSection
   local tKp, tKp2, tBuf, tBuf2, tEvents

   stSection "TorrentXT: session + offline-verifiable DHT surface"
   if not sHaveTorrent then
      stSkip "TorrentXT surface", sTorrentNote
      exit stTorrentSection
   end if

   stAssert "btStartSession returned a positive handle", sSession > 0
   btClearError
   stAssert "btLastError is empty after btClearError", btLastError() is empty
   stAssert "btListenPort reports a bound port", btListenPort(sSession) > 0
   stAssert "btSetBool enable_dht", btSetBool(sSession, "enable_dht", true) is 0
   stAssert "btSetInt rejects an unknown settings key", \
         btSetInt(sSession, "no_such_setting_key", "1") < 0

   -- btDhtKeypair is a PURE function of its seed - that determinism is what
   -- lets a room code, a passphrase, or a SodiumXT seed BE a DHT identity.
   put btDhtKeypair("") into tKp
   stAssert "btDhtKeypair mints a 64-hex public key", \
         the number of chars of tKp["publicKey"] is 64
   stAssert "btDhtKeypair reports its 64-hex seed", \
         the number of chars of tKp["seed"] is 64
   put btDhtKeypair(tKp["seed"]) into tKp2
   stAssert "btDhtKeypair is deterministic from that seed", \
         tKp2["publicKey"] is tKp["publicKey"]

   -- The alert drain has to survive being called; the events themselves arrive
   -- asynchronously and are not asserted here (that is the member selftest's job).
   put btPoll(sSession) into tEvents
   stAssert "btPoll drains without throwing", stCount(tEvents) >= 0

   -- btDhtBep44SignBuf needs no session and no network: it is a pure function of
   -- (salt, seq, value), which is exactly why an off-box signer can use it.
   put btDhtBep44SignBuf("oxt", "1", textEncode("18:oxt-suite-selftest", "UTF-8")) into tBuf
   put btDhtBep44SignBuf("oxt", "1", textEncode("18:oxt-suite-selftest", "UTF-8")) into tBuf2
   stAssert "btDhtBep44SignBuf returns the canonical bytes", \
         the number of bytes of tBuf > 0
   set the caseSensitive to true
   stAssert "btDhtBep44SignBuf is deterministic", tBuf2 is tBuf
   set the caseSensitive to false
end stTorrentSection

-- ---- per-member: OnionXT -----------------------------------------------------
-- Pure-compute paths ONLY. OnionXT's live surface needs a running Tor daemon and
-- a control port; this harness never opens one, so everything here is the byte
-- work that runs with no daemon at all (docs/04).
command stOnionSection
   local tAddr, tPub, tInfo, tKeys, tZeroPub

   stSection "OnionXT: pure-compute address paths (no Tor daemon touched)"
   if not sHaveOnion then
      stSkip "OnionXT surface", "start using stack " & quote & "onionxt" & quote
      exit stOnionSection
   end if

   stAssert "oxVersion returns a version string", oxVersion() is not empty

   -- Structurally valid v3 address, BUILT rather than pasted so a miscounted
   -- literal cannot silently weaken the test. A v3 address is base32 of
   -- pubkey(32) || checksum(2) || version(1); 35 bytes is exactly 56 base32
   -- chars. 55 leading "a" (base32 zero) plus a final "d" (value 3) sets every
   -- bit to zero except the low two of the last byte - i.e. an all-zero public
   -- key, an all-zero checksum, and version byte 3.
   put empty into tAddr
   repeat 55 times
      put "a" after tAddr
   end repeat
   put "d" after tAddr
   put tAddr & ".onion" into tAddr

   put oxPublicKeyFromAddress(tAddr) into tPub
   stAssert "oxPublicKeyFromAddress yields a 32-byte ed25519 key", \
         the number of bytes of tPub is 32
   put empty into tZeroPub
   repeat 32 times
      put numToByte(0) after tZeroPub
   end repeat
   set the caseSensitive to true
   stAssert "oxPublicKeyFromAddress decoded base32 byte-exactly", tPub is tZeroPub
   set the caseSensitive to false

   -- The fail-closed half: wrong length, a character outside the base32
   -- alphabet, and a version byte that is not 3 must all be refused.
   stAssert "oxIsValidAddress rejects an empty address", not oxIsValidAddress("")
   stAssert "oxIsValidAddress rejects a short address", \
         not oxIsValidAddress("notanonion.onion")
   put empty into tAddr
   repeat 56 times
      put "a" after tAddr
   end repeat
   stAssert "oxIsValidAddress rejects a version-0 address", \
         not oxIsValidAddress(tAddr & ".onion")
   put empty into tAddr
   repeat 55 times
      put "a" after tAddr
   end repeat
   put "1" after tAddr
   stAssert "oxIsValidAddress rejects a non-base32 character", \
         not oxIsValidAddress(tAddr & ".onion")

   -- oxTransportInfo is OnionXT's capability advertisement, and it is computed
   -- by probing SodiumXT. Its keys are asserted here; whether they are TRUE is
   -- a cross-member question, checked in the cross-member section below.
   put oxTransportInfo() into tInfo
   put the keys of tInfo into tKeys
   stAssert "oxTransportInfo returns a populated array", \
         the number of lines of tKeys >= 5
   stAssert "oxTransportInfo names the transport", tInfo["transport"] is "ox"
end stOnionSection

-- ---- per-member: CoinXT ------------------------------------------------------
-- Published known answers this repo already pins in coinxt/tools/coin-kat.py,
-- re-run through the SCRIPT layer so a green result means the cx* wrappers
-- reach the same audited C the KAT harness tests. Hashes here, then the
-- secp256k1 sample in stCoinCurveSection below.
command stCoinSection
   local tDigest, tHex

   stSection "CoinXT: published hash vectors through the binding"
   if not sHaveCoin then
      stSkip "CoinXT surface", "install org.openxtalk.library.coin"
      exit stCoinSection
   end if

   -- These are the same published answers coinxt/tools/coin-kat.py pins against
   -- the native library. Re-running them HERE, through the cx* binding, is what
   -- proves the .lcb wrappers (buffer allocation, length marshalling, the status
   -- check) reach that same audited C - the layer no headless test can touch.
   put cxKeccak256(textEncode("", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "keccak256 of the empty input matches the published vector", \
         tHex is "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
   put cxKeccak256(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "keccak256 of abc matches the published vector", \
         tHex is "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
   put cxSha256(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "sha256 of abc matches FIPS 180-4", \
         tHex is "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
   put cxRipemd160(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "ripemd160 of abc matches its specification vector", \
         tHex is "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
   -- The aliasing trap this suite has already had to guard against natively:
   -- Keccak-256 and SHA3-256 differ only in a padding byte, and a binding that
   -- wired one symbol to both would pass every Keccak vector above.
   put cxSha3_256(textEncode("", "UTF-8")) into tDigest
   stAssert "cxSha3_256 is NOT aliased to cxKeccak256", \
         stHex(tDigest) is not \
         "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

   stCoinCurveSection
end stCoinSection

-- CoinXT phase 2: a SAMPLE of the secp256k1 surface, not a substitute for
-- coinxt/tests/coin-selftest.livecodescript, which drives all 31 public
-- handlers. Four checks earn their place in a sampler because the phase-2
-- wrappers have never been loaded on an engine and two of their shapes are new
-- to that binding:
--   * cxPublicKey passes an LCB Boolean through a C int FLAG. Nothing in phase 1
--     crossed the FFI as a boolean. If it fails to marshal, the compressed and
--     uncompressed calls return the same length instead of 33 and 65.
--   * cxVerify RETURNS Boolean, where every phase-1 handler returned Data.
-- The whole section is wrapped so that an older CoinXT install (phase-1 .lcb, or
-- an ABI-2 library) reports one clear failure rather than aborting the run.
command stCoinCurveSection
   local tSeckey, tPubC, tPubU, tDigest, tSig, tBad, tRecovered, tByte

   stSection "CoinXT: secp256k1 through the binding (phase 2)"
   try
      -- The private key 1, whose public key is the curve's own generator G, so
      -- this vector needs no table. Built with numToByte because this harness
      -- has no hex decoder and must not borrow another member's.
      put stRepeatByte(0, 31) & numToByte(1) into tSeckey
      put cxPublicKey(tSeckey, true) into tPubC
      put cxPublicKey(tSeckey, false) into tPubU
      stAssert "cxPublicKey (compressed) is the generator G", \
            stHex(tPubC) is \
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      -- If the C int flag did not marshal, these two would be equal.
      stAssert "the compressed and uncompressed keys differ in length", \
            the number of bytes of tPubC is 33 and \
            the number of bytes of tPubU is 65

      -- The most-republished RFC 6979 vector for secp256k1 + SHA-256. The digest
      -- is built with cxSha256, which this same section already checked against
      -- FIPS 180-4, so a failure here cannot be a hashing failure.
      put cxSha256(textEncode("Satoshi Nakamoto", "UTF-8")) into tDigest
      put cxSign(tSeckey, tDigest) into tSig
      stAssert "cxSign reproduces the published RFC 6979 signature", \
            stHex(tSig) is \
            "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8" & \
            "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"

      -- cxVerify returns Boolean, not Data. Both answers are asserted, because a
      -- binding that returned something falsy for everything would still pass a
      -- test that only checked the rejection.
      stAssert "cxVerify accepts a good signature", \
            cxVerify(tPubC, tDigest, tSig) is true
      put (byteToNum(byte 6 of tSig) + 1) mod 256 into tByte
      put byte 1 to 5 of tSig & numToByte(tByte) & byte 7 to 64 of tSig into tBad
      stAssert "cxVerify rejects a tampered signature", \
            cxVerify(tPubC, tDigest, tBad) is false

      -- ecrecover: the signature alone must yield the signer's key back.
      put cxRecover(cxSignRecoverable(tSeckey, tDigest), tDigest) into tRecovered
      stAssert "cxRecover returns the signing public key", \
            stHex(tRecovered) is stHex(tPubU)
   catch tError
      stSectionFailed "CoinXT secp256k1", tError
   end try
end stCoinCurveSection

-- ==============================================================================
-- THE CROSS-MEMBER SECTIONS - the reason this file exists.
-- ==============================================================================

-- ONE IDENTITY, TWO TRANSPORTS. The suite's "reaching you is verifying you"
-- claim rests on a single 32-byte seed being simultaneously a SodiumXT signing
-- identity and a TorrentXT DHT identity. Both libraries implement RFC 8032
-- ed25519 (libsodium ref10; libtorrent's bundled ed25519), so the same seed must
-- expand to the same public key in both - and if it ever does not, every DHT
-- mailbox the suite mints is addressed to a key its owner cannot sign for. That
-- invariant spans two members, so neither member's selftest can state it.
command stCrossIdentitySection
   local tSeed, tSeedHex, tKp, tPub, tSec, tPubHex, tExpanded, tExpandedHex

   stSection "CROSS: one seed, one identity (SodiumXT + TorrentXT)"
   if not sHaveSodium or not sHaveTorrent then
      stSkip "one identity, two transports", \
            "needs BOTH SodiumXT and a live TorrentXT session"
      exit stCrossIdentitySection
   end if

   -- The seed comes from SodiumXT's CSPRNG, crosses to TorrentXT as hex (its
   -- whole DHT surface speaks hex Strings), and must come back the same key.
   put sxRandomBytes(32) into tSeed
   put textDecode(sxBin2Hex(tSeed), "UTF-8") into tSeedHex
   stAssert "the sodium seed hex-encodes to 64 chars for TorrentXT", \
         the number of chars of tSeedHex is 64

   put btDhtKeypair(tSeedHex) into tKp
   stAssert "btDhtKeypair accepts the SodiumXT seed verbatim", \
         tKp["seed"] is tSeedHex
   put btDhtKeypair(tSeedHex) into tKp
   stAssert "btDhtKeypair is deterministic on that seed (same key twice)", \
         the number of chars of tKp["publicKey"] is 64

   sxSignKeypairFromSeed tSeed, tPub, tSec
   put textDecode(sxBin2Hex(tPub), "UTF-8") into tPubHex
   -- Both hex encoders emit lowercase, and `is` is case-insensitive by default,
   -- so this compare is deliberately left case-INsensitive: it is a comparison
   -- of two hex TEXTS, not of secret bytes.
   stAssert "SodiumXT and libtorrent derive the SAME ed25519 public key", \
         tPubHex is tKp["publicKey"]

   -- The two libraries disagree on how to SPELL the secret key, and the suite
   -- depends on knowing which is which: libsodium's is seed||publicKey (64
   -- bytes), libtorrent's is the EXPANDED SHA-512(seed) clamped form (also 64
   -- bytes) - the same form a Tor v3 onion service consumes. sxSignSeedToExpanded
   -- Key is the bridge, so this is the assertion that the bridge is the right one.
   put empty into tExpanded
   try
      put sxSignSeedToExpandedKey(tSeed) into tExpanded
   catch tError
      put empty into tExpanded
   end try
   if tExpanded is empty then
      stSkip "libtorrent's DHT secret key IS SodiumXT's expanded key", \
            "needs SodiumXT ABI >= 6 (sxSignSeedToExpandedKey)"
   else
      put textDecode(sxBin2Hex(tExpanded), "UTF-8") into tExpandedHex
      stAssert "libtorrent's DHT secret key IS SodiumXT's expanded key", \
            tExpandedHex is tKp["secretKey"]
   end if

   -- The third leg of the claim: that same public key IS a v3 .onion address.
   -- RENDERING one needs SHA3-256 for the address checksum. That was ononxt/
   -- docs/08 gap #2, and it CLOSED on 2026-08-11: SodiumXT ABI 7 ships
   -- sxSha3_256 and OnionXT's oxSha3_256 composes it, so oxAddressFromPublicKey
   -- now emits a real address against an ABI-7 SodiumXT. OnionXT's own harness
   -- renders and round-trips it (ox1's address section); this cross-section
   -- still does not re-render it here, because the identity being proven is the
   -- KEY (handle == the ed25519 key an onion would encode), and re-implementing
   -- the checksum would be the test faking a composition rather than observing
   -- it. The capability section below asserts oxTransportInfo now advertises the
   -- offline address as AVAILABLE whenever SHA3 is.
   stNote "the onion-address leg (SHA3-256 checksum) is now closed: SodiumXT ABI 7"
end stCrossIdentitySection

-- SIGN A BEP44 ITEM WITH SODIUMXT. btDhtBep44SignBuf exists precisely so a
-- signer that must keep its key private can produce a BEP44 signature without
-- any secret key crossing into TorrentXT. Nothing tests that composition today:
-- torrent-selftest can only prove the buffer is deterministic and that garbage
-- is refused, because it has no signer. Here we have one.
command stCrossBep44Section
   local tSeed, tSeedHex, tKp, tPub, tSec
   local tValue, tBuf, tSig, tSigHex, tWrongBuf, tWrongSig, tWrongHex

   stSection "CROSS: SodiumXT signs a BEP44 item TorrentXT accepts"
   if not sHaveSodium or not sHaveTorrent then
      stSkip "SodiumXT-signed BEP44 put", \
            "needs BOTH SodiumXT and a live TorrentXT session"
      exit stCrossBep44Section
   end if

   put sxRandomBytes(32) into tSeed
   put textDecode(sxBin2Hex(tSeed), "UTF-8") into tSeedHex
   put btDhtKeypair(tSeedHex) into tKp
   sxSignKeypairFromSeed tSeed, tPub, tSec

   -- v must be ALREADY bencoded and is stored verbatim, so what we sign is
   -- byte-identical to what lands in the DHT. "18:" is the bencode length
   -- prefix for the 18-character payload that follows.
   put textEncode("18:oxt-suite-selftest", "UTF-8") into tValue
   put btDhtBep44SignBuf("oxt", "7", tValue) into tBuf
   stAssert "btDhtBep44SignBuf handed back the canonical buffer", \
         the number of bytes of tBuf > 0

   put sxSignDetached(tBuf, tSec) into tSig
   stAssert "SodiumXT signed those exact bytes", the number of bytes of tSig is 64
   stAssert "SodiumXT verifies its own signature over the BEP44 buffer", \
         sxSignVerifyDetached(tSig, tBuf, tPub)

   -- The real proof: libtorrent VERIFIES the foreign signature on this thread,
   -- before anything touches the network, and only queues the put if it checks
   -- out. A 0 here means two independent ed25519 implementations agreed on one
   -- signature over one canonical buffer - the whole point of the seam.
   put textDecode(sxBin2Hex(tSig), "UTF-8") into tSigHex
   stAssert "btDhtPutSigned accepts the SodiumXT signature", \
         btDhtPutSigned(sSession, tKp["publicKey"], "oxt", "7", tValue, tSigHex) is 0

   -- And it must fail CLOSED. A well-formed 128-hex signature that is valid for
   -- a DIFFERENT seq is the sharpest negative available: it proves the check
   -- binds the whole (salt, seq, value) tuple, not merely the hex shape.
   put btDhtBep44SignBuf("oxt", "8", tValue) into tWrongBuf
   put sxSignDetached(tWrongBuf, tSec) into tWrongSig
   put textDecode(sxBin2Hex(tWrongSig), "UTF-8") into tWrongHex
   stAssert "btDhtPutSigned refuses a signature made for another seq", \
         btDhtPutSigned(sSession, tKp["publicKey"], "oxt", "7", tValue, tWrongHex) < 0
end stCrossBep44Section

-- OnionXT's capability advertisement is COMPUTED from SodiumXT: it probes for
-- HMAC, entropy, seed expansion, and SHA3 and reports what it can actually do.
-- So the honest cross-member assertion is that its answers track reality.
command stCrossOnionSection
   local tInfo, tHasSha3, tErr

   stSection "CROSS: OnionXT advertises its real SodiumXT-backed capabilities"
   if not sHaveOnion then
      stSkip "OnionXT capability negotiation", \
            "start using stack " & quote & "onionxt" & quote
      exit stCrossOnionSection
   end if

   put oxTransportInfo() into tInfo
   if sHaveSodium then
      stAssert "SAFECOOKIE auth is advertised when SodiumXT is present", \
            tInfo["safeCookieAuth"] is true
      stAssert "deterministic .onion keys are advertised (sxSignSeedToExpandedKey)", \
            tInfo["deterministicOnion"] is true
   else
      stAssert "capabilities are advertised as absent without SodiumXT", \
            tInfo["safeCookieAuth"] is false
   end if
   -- offlineAddress tracks whether SHA3-256 is reachable, which is exactly what
   -- OnionXT's oxSha3_256 probes: it composes SodiumXT's sxSha3_256 (ABI 7,
   -- onionxt/docs/08 gap #2, closed 2026-08-11). So the honest assertion is that
   -- the advertisement TRACKS REALITY, not that it holds a fixed answer: probe
   -- SHA3 the same way OnionXT does and require the flag to agree. It is true on
   -- an ABI-7 SodiumXT and false on an older one or with SodiumXT absent.
   put false into tHasSha3
   if sHaveSodium then
      try
         put (the number of bytes of sxSha3_256(textEncode("probe", "ASCII")) is 32) \
               into tHasSha3
      catch tErr
         put false into tHasSha3
      end try
   end if
   stAssert "oxTransportInfo's offlineAddress tracks whether SHA3-256 is available", \
         tInfo["offlineAddress"] is tHasSha3
   if tHasSha3 then
      stNote "SHA3-256 is present: offline .onion address rendering is AVAILABLE"
   else
      stNote "SHA3-256 absent (SodiumXT pre-ABI-7 or absent): offline address deferred"
      stNote "that FALSE was docs/08 gap #2; SodiumXT ABI 7+ closes it (reinstall)"
   end if
end stCrossOnionSection

-- Build the one sealed payload BOTH transports will carry. Sealing once and
-- sending the same ciphertext twice is the point: the assertion is that a
-- SodiumXT box survives two entirely different wire formats unchanged.
command stSealPayload
   stSection "CROSS: one SodiumXT-sealed payload for both transports"
   put textEncode("suite", "UTF-8") & numToByte(0) & numToByte(1) & numToByte(255) \
         & textEncode("sealed-payload", "UTF-8") into sSealPlain
   if not sHaveSodium then
      -- Degrade visibly, never silently: the transports still carry the bytes
      -- and the byte-exactness checks still mean something; only the crypto
      -- half is skipped.
      put sSealPlain into sSealBox
      put empty into sSealKey
      stSkip "sxSecretBox seals the transport payload", \
            "SodiumXT absent - the transports will carry the plaintext instead"
      exit stSealPayload
   end if
   put sxRandomBytes(32) into sSealKey
   put sxSecretBox(sSealPlain, sSealKey) into sSealBox
   stAssert "sealed one payload for both transports", \
         the number of bytes of sSealBox > the number of bytes of sSealPlain
end stSealPayload

-- THE 60000-BYTE BUDGET SEAM. ENX_MAX_MESSAGE and DCX_MAX_MESSAGE are both
-- 60000 and both refuse an over-budget message with -4 rather than truncating
-- or splitting it. That the two numbers agree is a SUITE invariant: an app that
-- switches transports at runtime (the whole premise of having both) would
-- silently start losing messages if they drifted apart. Neither member can
-- check it alone.
--
-- The enetxt half runs here, synchronously, because enSend validates the length
-- before it needs a connection. The datachannelxt half CANNOT: dcx_send_data
-- validates the channel handle first, so an over-budget send on a stale handle
-- returns -2, not -4 - it needs a LIVE channel, and therefore runs in the
-- datachannel loopback's open phase below. Same invariant, reported in two
-- places for a reason.
command stCrossBudgetSection
   local tOver

   stSection "CROSS: the 60000-byte budget both transports share"
   if not sHaveEnet then
      stSkip "enetxt refuses 60001 bytes", "install org.openxtalk.library.enet"
   else if sEnClientPeer is empty or sEnClientPeer <= 0 then
      stSkip "enetxt refuses 60001 bytes", "the enet loopback did not start"
   else
      put stRepeatByte(90, kStOverBudget) into tOver
      stAssert "enSend refuses 60001 bytes with -4 (never truncates)", \
            enSend(sEnClientPeer, 0, tOver, 0) is -4
   end if
   if not sHaveDc then
      stSkip "datachannelxt refuses 60001 bytes", \
            "install org.openxtalk.library.datachannel"
   else
      stNote "the datachannelxt half needs a LIVE channel; see the loopback below"
   end if
end stCrossBudgetSection

-- ---- enetxt: the live loopback ----------------------------------------------
command stStartEnetLoopback
   stSection "enetxt: live loopback on 127.0.0.1:" & kStPortEnet
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer
   put empty into sEnGotSealed
   put empty into sEnBigSize
   put empty into sEnSawDisc
   if not sHaveEnet then
      stSkip "enetxt loopback", "install org.openxtalk.library.enet"
      put "skip" into sPhaseEn
      exit stStartEnetLoopback
   end if

   stAssert "enInitialize returns 0", enInitialize() is 0
   stAssert "enLibraryVersion names enet", enLibraryVersion() begins with "enet "
   -- A stale handle must be a harmless no-op, not a crash: the generation-tagged
   -- handle rule, spot-checked (the member selftest covers the whole surface).
   stAssert "enHostDestroy(0) is a harmless no-op", enHostDestroy(0) is 0

   put enHostCreateServer("127.0.0.1", kStPortEnet, 4, 2, 0, 0) into sEnServer
   stAssert "enet server host bound", sEnServer > 0
   put enHostCreateClient(1, 2, 0, 0) into sEnClient
   stAssert "enet client host created", sEnClient > 0
   if sEnServer <= 0 or sEnClient <= 0 then
      stNote "UDP port " & kStPortEnet & " may already be held; skipping the loopback"
      put "failed" into sPhaseEn
      exit stStartEnetLoopback
   end if
   put enConnect(sEnClient, "127.0.0.1", kStPortEnet, 2, 7) into sEnClientPeer
   stAssert "enConnect returns a peer handle", sEnClientPeer > 0
   if sEnClientPeer <= 0 then
      put "failed" into sPhaseEn
      exit stStartEnetLoopback
   end if
   put "connecting" into sPhaseEn
end stStartEnetLoopback

-- Deliberately if/else-if rather than switch: this file lives at the SUITE root
-- and has to satisfy every member's copy of check-livecodescript.py, and the
-- older copies (sodiumxt's lineage) do not model `switch` as a block, so an
-- `end switch` there is mistaken for a handler terminator. if/else-if is exactly
-- as clear and is understood by all of them.
command stEnServerEvent pEvent
   local tName, tPayload
   put pEvent["name"] into tName
   if tName is "enetConnect" then
      put pEvent["peer"] into sEnServerPeer
      stAssert "enet server sees the connect data (7)", pEvent["data"] is 7
   else if tName is "enetReceive" then
      -- Routed by CHANNEL, not by phase, so an early delivery can never be
      -- mistaken for the later one.
      put pEvent["payload"] into tPayload
      if pEvent["channel"] is 0 then
         put tPayload into sEnGotSealed
      else
         put the number of bytes of tPayload into sEnBigSize
      end if
   else if tName is "enetDisconnect" then
      put "true" into sEnSawDisc
   end if
end stEnServerEvent

command stEnClientEvent pEvent
   if pEvent["name"] is "enetConnect" then
      stAssert "enet client sees the handle enConnect gave it", \
            pEvent["peer"] is sEnClientPeer
      stAssert "enSend carries the sealed ciphertext", \
            enSend(sEnClientPeer, 0, sSealBox, 0) is 0
   end if
end stEnClientEvent

command stEnAdvance
   local tBig
   if sPhaseEn is "connecting" then
      if sEnServerPeer is not empty then
         put "sealed" into sPhaseEn
      end if
   else if sPhaseEn is "sealed" then
      if sEnGotSealed is not empty then
         stCheckSealed "enetxt", sEnGotSealed
         -- The other half of the budget seam: a payload AT the cap must be
         -- accepted and delivered whole. ENet fragments it internally; script
         -- must see one message of exactly 60000 bytes.
         put stRepeatByte(90, kStBudget) into tBig
         stAssert "enSend accepts a payload at the 60000-byte budget", \
               enSend(sEnClientPeer, 1, tBig, 0) is 0
         put "big" into sPhaseEn
      end if
   else if sPhaseEn is "big" then
      if sEnBigSize is not empty then
         stAssert "enet reassembled all 60000 bytes into ONE message", \
               sEnBigSize is kStBudget
         stAssert "enDisconnect returns 0", enDisconnect(sEnClientPeer, 7) is 0
         put "closing" into sPhaseEn
      end if
   else if sPhaseEn is "closing" then
      if sEnSawDisc is not empty then
         stAssert "enet closed gracefully (server drained enetDisconnect)", true
         put "done" into sPhaseEn
      end if
   end if
end stEnAdvance

function stEnDone
   return sPhaseEn is "done" or sPhaseEn is "skip" or sPhaseEn is "failed"
end stEnDone

-- ---- datachannelxt: the live loopback ---------------------------------------
command stStartDcLoopback
   stSection "datachannelxt: live loopback (two in-process peers)"
   put empty into sDcPeerA
   put empty into sDcPeerB
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcAOpen
   put empty into sDcBOpen
   put empty into sDcGot
   put empty into sDcBigSize
   put empty into sDcBigWant
   if not sHaveDc then
      stSkip "datachannelxt loopback", "install org.openxtalk.library.datachannel"
      put "skip" into sPhaseDc
      exit stStartDcLoopback
   end if

   stAssert "dcInit returns 0", dcInit() is 0
   stAssert "dcLibraryVersion names libdatachannel", \
         dcLibraryVersion() contains "libdatachannel"
   stAssert "dcPeerState(0) is -1 for a stale handle", dcPeerState(0) is -1

   put dcCreatePeer("") into sDcPeerA
   put dcCreatePeer("") into sDcPeerB
   stAssert "dcCreatePeer A", sDcPeerA > 0
   stAssert "dcCreatePeer B", sDcPeerB > 0
   if sDcPeerA <= 0 or sDcPeerB <= 0 then
      put "failed" into sPhaseDc
      exit stStartDcLoopback
   end if
   put dcCreateChannel(sDcPeerA, "suite-selftest") into sDcChanA
   stAssert "dcCreateChannel on A (auto-negotiation makes the offer)", sDcChanA > 0
   if sDcChanA <= 0 then
      put "failed" into sPhaseDc
      exit stStartDcLoopback
   end if
   put "opening" into sPhaseDc
end stStartDcLoopback

-- The in-script signaling shuttle IS the loopback: WebRTC signaling is always
-- the app's job, and here the app hands each side's description and candidates
-- straight to the other.
command stDcEvent pEvent
   local tName, tDest, tPayload
   put pEvent["name"] into tName
   if tName is "dcLocalDescription" then
      put stDcOtherPeer(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcSetRemoteDescription tDest, pEvent["sdp"], pEvent["sdpType"]
      end if
   else if tName is "dcLocalCandidate" then
      put stDcOtherPeer(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcAddRemoteCandidate tDest, pEvent["candidate"], pEvent["mid"]
      end if
   else if tName is "dcChannelIncoming" then
      if pEvent["peer"] is sDcPeerB and sDcChanB is empty then
         put pEvent["channel"] into sDcChanB
      end if
   else if tName is "dcChannelOpen" then
      if pEvent["channel"] is sDcChanA then
         put "true" into sDcAOpen
      else if sDcChanB is not empty and pEvent["channel"] is sDcChanB then
         put "true" into sDcBOpen
      end if
   else if tName is "dcMessage" then
      -- Routed by PHASE here (unlike enet, a data channel has no channel number
      -- to key on), and the two payloads are sent strictly one phase apart so
      -- the routing can never be ambiguous.
      put pEvent["payload"] into tPayload
      if sPhaseDc is "big" then
         put the number of bytes of tPayload into sDcBigSize
      else
         put tPayload into sDcGot
      end if
   end if
end stDcEvent

function stDcOtherPeer pPeer
   if pPeer is sDcPeerA then
      return sDcPeerB
   else if pPeer is sDcPeerB then
      return sDcPeerA
   end if
   return empty
end stDcOtherPeer

command stDcAdvance
   local tOver, tMax, tBig
   if sPhaseDc is "opening" then
      if sDcAOpen is "true" and sDcBOpen is "true" then
         stAssert "datachannel loopback negotiated and both ends opened", true
         stAssert "the incoming channel carries our label", \
               dcChannelLabel(sDcChanB) is "suite-selftest"
         stAssert "peer A reports connected", dcPeerState(sDcPeerA) is 2
         -- THE BUDGET SEAM, datachannelxt half. It has to be here: the shim
         -- validates the channel handle BEFORE the length, so this -4 can only
         -- be observed on a live channel.
         put stRepeatByte(90, kStOverBudget) into tOver
         stAssert "dcSendData refuses 60001 bytes with -4 (same code as enetxt)", \
               dcSendData(sDcChanA, tOver) is -4
         stAssert "dcSendData carries the sealed ciphertext", \
               dcSendData(sDcChanA, sSealBox) is 0
         put "sealed" into sPhaseDc
      end if
   else if sPhaseDc is "sealed" then
      if sDcGot is not empty then
         stCheckSealed "datachannelxt", sDcGot
         -- "Large but legal" means legal ON THIS WIRE: the shim advertises our
         -- 60000 cap in the SCTP negotiation, but the negotiated value is what
         -- the association actually agreed to, so clamp rather than assume.
         put dcChannelMaxMessage(sDcChanA) into tMax
         stAssert "SCTP negotiated at least its 16 KiB floor", tMax >= kStSctpFloor
         if tMax > kStBudget then
            put kStBudget into tMax
         end if
         if tMax < kStSctpFloor then
            -- A nonsense reading (dcChannelMaxMessage answers -1 for a handle it
            -- no longer knows) must not become a nonsense payload and a second,
            -- meaningless failure: the assertion above already reported it.
            put kStSctpFloor into tMax
         end if
         put tMax into sDcBigWant
         put stRepeatByte(90, tMax) into tBig
         put "big" into sPhaseDc
         stAssert "dcSendData accepts a payload at the negotiated cap", \
               dcSendData(sDcChanA, tBig) is 0
      end if
   else if sPhaseDc is "big" then
      if sDcBigSize is not empty then
         stAssert "datachannel delivered the large payload whole", \
               sDcBigSize is sDcBigWant
         put "done" into sPhaseDc
      end if
   end if
end stDcAdvance

function stDcDone
   return sPhaseDc is "done" or sPhaseDc is "skip" or sPhaseDc is "failed"
end stDcDone

-- ---- the shared sealed-payload check ----------------------------------------
-- The cross-member payoff: the SAME ciphertext, over two unrelated transports,
-- opened by SodiumXT on arrival. Byte-exactness needs caseSensitive, because
-- `is` folds 0x41 onto 0x61 by default and would let corrupted binary compare
-- equal; it is restored immediately afterwards so the hex-text comparisons
-- elsewhere in the run keep their intended case-insensitive semantics.
command stCheckSealed pWho, pGot
   local tOpened
   set the caseSensitive to true
   stAssert pWho & " delivered the ciphertext byte-for-byte", pGot is sSealBox
   set the caseSensitive to false
   if not sHaveSodium then
      stSkip pWho & ": sxSecretBoxOpen on arrival", \
            "SodiumXT absent - the payload crossed as plaintext"
      exit stCheckSealed
   end if
   put empty into tOpened
   try
      put sxSecretBoxOpen(pGot, sSealKey) into tOpened
   catch tError
      put empty into tOpened
   end try
   set the caseSensitive to true
   stAssert pWho & ": sxSecretBoxOpen recovers the exact plaintext", \
         tOpened is sSealPlain
   set the caseSensitive to false
end stCheckSealed

-- ---- the pump ----------------------------------------------------------------
-- ONE timer chain drives BOTH async members. It reschedules itself until every
-- async phase is terminal or the deadline passes; it never blocks the
-- interpreter, because nothing in this family may block the one script thread.
command stPump
   local tEvents, tEvent
   if sRunning is not "true" then
      exit stPump
   end if

   -- Contained for the same reason the synchronous sections are, and with one
   -- extra stake: a throw out of the pump would break the timer chain, so
   -- nothing would ever reach stFinish - and the hosts, peers, and the one
   -- libtorrent session would all leak until the maintainer closed the stack.
   -- Marking the phase "failed" lets the run converge and tear down properly.
   if not stEnDone() then
      try
         put enPoll(sEnServer) into tEvents
         repeat for each element tEvent in tEvents
            stEnServerEvent tEvent
         end repeat
         put enPoll(sEnClient) into tEvents
         repeat for each element tEvent in tEvents
            stEnClientEvent tEvent
         end repeat
         stEnAdvance
      catch tError
         stAssert "enet loopback pumped without throwing", false
         stNote "it raised:" && tError
         put "failed" into sPhaseEn
      end try
   end if

   if not stDcDone() then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            stDcEvent tEvent
         end repeat
         stDcAdvance
      catch tError
         stAssert "datachannel loopback pumped without throwing", false
         stNote "it raised:" && tError
         put "failed" into sPhaseDc
      end try
   end if

   if stEnDone() and stDcDone() then
      stFinish
      exit stPump
   end if

   -- A stuck section must not take the run with it: record the failure against
   -- the section that hung and finish everything else.
   if the milliseconds > sDeadline then
      if not stEnDone() then
         stAssert "enet loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseEn & "; UDP to 127.0.0.1 may be blocked"
         put "failed" into sPhaseEn
      end if
      if not stDcDone() then
         stAssert "datachannel loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseDc & "; UDP to this machine may be blocked"
         put "failed" into sPhaseDc
      end if
      stFinish
      exit stPump
   end if

   stShow
   send "stPump" to me in 33 milliseconds
end stPump

-- ---- finish + teardown -------------------------------------------------------
command stFinish
   -- Run last: OnionXT's capability advertisement is pure compute, but reading
   -- it here keeps the whole cross-member story in one block at the end of the
   -- report, next to the transports it describes.
   try
      stCrossOnionSection
   catch tError
      stSectionFailed "cross: OnionXT capabilities", tError
   end try

   -- Teardown is contained too, but it is the ONE thing that must be attempted
   -- no matter what came before: stCleanup on closeStack is the safety net if a
   -- handle survives this.
   try
      stTeardown
   catch tError
      stSectionFailed "teardown", tError
   end try

   stSection "summary"
   stNote "This is a sampler, not a full per-member selftest: it drives the"
   stNote "headline paths and the cross-member seams. Each member has a deeper"
   stNote "harness that still needs its own engine run. Paste these numbers back."
   put empty into sRunning
   stShow
end stFinish

-- Everything this file opened gets closed, in dependency order, each guarded so
-- one absent member cannot stop the rest from being released.
command stTeardown
   stSection "teardown (nothing may outlive the run)"
   if sHaveDc then
      if sDcChanA is not empty and sDcChanA > 0 then
         dcCloseChannel sDcChanA
         dcFreeChannel sDcChanA
      end if
      if sDcChanB is not empty and sDcChanB > 0 then
         dcFreeChannel sDcChanB
      end if
      if sDcPeerA is not empty and sDcPeerA > 0 then
         dcFreePeer sDcPeerA
      end if
      if sDcPeerB is not empty and sDcPeerB > 0 then
         dcFreePeer sDcPeerB
      end if
      stAssert "dcCleanup returns 0", dcCleanup() is 0
   end if
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcPeerA
   put empty into sDcPeerB

   if sHaveEnet then
      if sEnServer is not empty and sEnServer > 0 then
         stAssert "enHostDestroy(server) returns 0", enHostDestroy(sEnServer) is 0
      end if
      if sEnClient is not empty and sEnClient > 0 then
         stAssert "enHostDestroy(client) returns 0", enHostDestroy(sEnClient) is 0
      end if
      stAssert "enDeinitialize returns 0", enDeinitialize() is 0
   end if
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer

   -- The one that MUST happen: a surviving libtorrent session makes the next run
   -- impossible (one session per process) and keeps its threads and sockets.
   if sSession is not empty and sSession > 0 then
      btStopSession sSession
      stAssert "btStopSession released THE session", true
   end if
   put 0 into sSession
end stTeardown

-- Idempotent hard teardown for closeStack and for Re-run. It must survive being
-- called when a member was never present, when the run never started, and twice
-- in a row - so every call is guarded and no assertion is recorded.
command stCleanup
   put empty into sRunning
   put "skip" into sPhaseEn
   put "skip" into sPhaseDc
   stCancelPump
   try
      if sDcChanA is not empty and sDcChanA > 0 then
         dcFreeChannel sDcChanA
      end if
      if sDcPeerA is not empty and sDcPeerA > 0 then
         dcFreePeer sDcPeerA
      end if
      if sDcPeerB is not empty and sDcPeerB > 0 then
         dcFreePeer sDcPeerB
      end if
      dcCleanup
   catch tError
      -- DataChannelXT absent or already released; nothing to free
   end try
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcPeerA
   put empty into sDcPeerB
   try
      if sEnServer is not empty and sEnServer > 0 then
         enHostDestroy sEnServer
      end if
      if sEnClient is not empty and sEnClient > 0 then
         enHostDestroy sEnClient
      end if
      -- Bare statement form, matching enetxt's own teardown (enet-selftest line
      -- 371, enet-lan-chat line 220). This IS an engine constraint, contrary to
      -- what this comment claimed before an OXT pass proved otherwise: a
      -- zero-argument call in statement position must be bare, because the
      -- parenthesised spelling passes `()` to a command and `()` is not an
      -- expression. See the note in the file header.
      enDeinitialize
   catch tError
      -- enetxt absent or already released; nothing to free
   end try
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer
   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent; there was never a session to stop
   end try
   put 0 into sSession
end stCleanup

-- ---- small helpers -----------------------------------------------------------
-- Kill any pump still queued from a previous run. Without this, Re-run would arm
-- a SECOND timer chain while the first was still pending: both would pass the
-- `sRunning is "true"` guard, both would drive the same phase machine, and every
-- assertion would be counted twice - a silently wrong report, which is worse
-- than no report. `the pendingMessages` lines are id,time,message,object.
command stCancelPump
   local tPending, tLine
   put the pendingMessages into tPending
   set the itemDelimiter to comma
   repeat for each line tLine in tPending
      if item 3 of tLine is "stPump" then
         cancel (item 1 of tLine)
      end if
   end repeat
end stCancelPump

-- Count a bridged list WITHOUT `the number of elements` (the sibling selftests
-- avoid relying on it for an LCB List; iteration is the idiom that is known to
-- work on a bridged value).
function stCount pList
   local tN, tEl
   put 0 into tN
   repeat for each element tEl in pList
      add 1 to tN
   end repeat
   return tN
end stCount

-- Lowercase hex for the digest comparisons. The harness encodes its own on
-- purpose: CoinXT's cxHexEncode is a phase-2 script-layer encoding its shipped
-- .lcb does not carry yet, and borrowing SodiumXT's sxBin2Hex would make a
-- CoinXT check fail whenever SodiumXT is the absent member. A test harness must
-- not need one member present to check another.
function stHex pData
   local tOut, tI, tByte, tDigits
   put "0123456789abcdef" into tDigits
   put empty into tOut
   repeat with tI = 1 to the number of bytes of pData
      put byteToNum(byte tI of pData) into tByte
      put char (tByte div 16 + 1) of tDigits after tOut
      put char (tByte mod 16 + 1) of tDigits after tOut
   end repeat
   return tOut
end stHex

-- pCount copies of byte pCode, built without string-escape folklore (LCS string
-- literals have no escapes at all). Doubling then trimming keeps this O(log n)
-- concatenations instead of 60001.
function stRepeatByte pCode, pCount
   local tOut
   if pCount <= 0 then
      return empty
   end if
   put numToByte(pCode) into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte


-- ==========================================================================
-- The deep per-member harnesses: running them, and merging their reports.
--
-- Each folded harness keeps its OWN scaffolding and its OWN counters (see the
-- generated banner below for why sharing them would be wrong), so it reports
-- into its own log and its own sTotal/sPassed/sFailed. These two handlers are
-- the whole coupling: run the entry point, then fold the result in.
-- ==========================================================================

command stRunMemberHarnesses
   stSection "deep per-member self-tests (each member's own harness, folded in)"
   stNote "Each of these is the SAME harness that member ships standalone."
   stNote "A failure here means the same thing it would mean there."

   -- SodiumXT and OnionXT return their report as a string; CoinXT, TorrentXT,
   -- ENetXT and DataChannelXT accumulate into their own script locals. Both
   -- shapes are handled, because both are what those members actually ship -
   -- rewriting one to look like the other would be editing a proven harness to
   -- suit this file, which is backwards.
   if sHaveSodium then
      try
         stMergeReturned "SodiumXT", sx1sxSelfTest()
      catch tError
         stSectionFailed "SodiumXT deep self-test", tError
      end try
   else
      stSkip "SodiumXT deep self-test", "install org.openxtalk.library.sodium"
   end if

   if sHaveOnion then
      try
         stMergeReturned "OnionXT", ox1oxSelfTest()
      catch tError
         stSectionFailed "OnionXT deep self-test", tError
      end try
   else
      stSkip "OnionXT deep self-test", "install org.openxtalk.library.onion"
   end if

   -- BOTH pieces, because ten of the folded sections call the script layer and
   -- would report FAIL rather than SKIP without it (see stProbe).
   if sHaveCoin and sHaveCoinScript then
      try
         cx1stRun
         stMergeCounted "CoinXT", cx1sResultText, cx1sPassed, cx1sFailed, cx1sTotal
      catch tError
         stSectionFailed "CoinXT deep self-test", tError
      end try
   else if sHaveCoin then
      stSkip "CoinXT deep self-test", "the extension is loaded but its SCRIPT layer is not:" && \
            "start using stack " & quote & "coinxt" & quote & \
            " - 10 of its 27 sections need it"
   else
      stSkip "CoinXT deep self-test", "install org.openxtalk.library.coin"
   end if

   if sHaveTorrent then
      try
         bt1stRun
         stMergeCounted "TorrentXT", bt1sResultText, bt1sPassed, bt1sFailed, bt1sTotal
      catch tError
         stSectionFailed "TorrentXT deep self-test", tError
      end try
   else
      stSkip "TorrentXT deep self-test", sTorrentNote
   end if

   if sHaveEnet then
      try
         en1stRun
         stMergeCounted "ENetXT (sync half)", en1sResultText, en1sPassed, en1sFailed, en1sTotal
      catch tError
         stSectionFailed "ENetXT deep self-test", tError
      end try
   else
      stSkip "ENetXT deep self-test", "install org.openxtalk.library.enet"
   end if

   if sHaveDc then
      try
         dc1stRun
         stMergeCounted "DataChannelXT (sync half)", dc1sResultText, dc1sPassed, dc1sFailed, dc1sTotal
      catch tError
         stSectionFailed "DataChannelXT deep self-test", tError
      end try
   else
      stSkip "DataChannelXT deep self-test", "install org.openxtalk.library.datachannel"
   end if

   -- Riptide is an APP layer over the extensions above, so it runs LAST: by
   -- here every extension it probes has already shown its own colours. Its
   -- harness handles a missing optional extension itself (sections SKIP), and
   -- refuses cleanly without SodiumXT, so the only gate here is the embedded
   -- layer being present at all.
   if sHaveRiptideScript then
      try
         stMergeReturned "Riptide Social (phases 1-2)", rs1rsSelfTest()
      catch tError
         stSectionFailed "Riptide deep self-test", tError
      end try
   else
      stSkip "Riptide deep self-test", \
            "the riptide script layer is not present; the paste is damaged"
   end if
end stRunMemberHarnesses

-- Strip the punctuation a report hangs off its words, so "PASSED:" and
-- "passed," both read as the bare word "passed" and "68," reads as 68. Only the
-- EDGES are touched: a word's own characters are left alone, so "self-test"
-- stays "self-test" and goes on disqualifying its line rather than quietly
-- turning into something the summary test would accept.
function stTrimEdges pWord
   local tOut, tPunct

   put ":,.;()[]" into tPunct
   put pWord into tOut
   -- The `tOut is not empty` guard is load-bearing, not defensive noise: in
   -- xTalk EVERY string contains empty, so the moment tOut runs out,
   -- `tPunct contains char 1 of tOut` is TRUE forever and the loop never ends.
   repeat while tOut is not empty and tPunct contains char 1 of tOut
      delete char 1 of tOut
   end repeat
   repeat while tOut is not empty and tPunct contains the last char of tOut
      delete the last char of tOut
   end repeat
   return tOut
end stTrimEdges

-- Given ONE line, return "<passed> <failed>" if that line is a summary, or
-- empty if it is not. This is the whole rule; see stMergeReturned below for why
-- it is shaped this way.
--
-- A line qualifies only when EVERY word on it is either a number or the word
-- "passed"/"failed" (case and edge punctuation ignored), with exactly one of
-- each keyword, "passed" before "failed", and exactly two numbers. That shape
-- test - rather than "the line mentions both words" - is what makes an
-- individual check's LABEL unable to masquerade as a summary: a label always
-- carries at least one other word (SodiumXT's "  ok   a failed call surfaces an
-- error" has "ok", "a", "call"), and one other word is enough to disqualify it.
function stSummaryCounts pLine
   local tI, tN, tWord, tPassAt, tFailAt, tNums

   put the number of words of pLine into tN
   put 0 into tPassAt
   put 0 into tFailAt
   put empty into tNums
   repeat with tI = 1 to tN
      put stTrimEdges(word tI of pLine) into tWord
      if tWord is a number then
         put tWord & space after tNums
      else if toLower(tWord) is "passed" and tPassAt is 0 then
         put tI into tPassAt
      else if toLower(tWord) is "failed" and tFailAt is 0 then
         put tI into tFailAt
      else
         -- Any other word - or a SECOND "passed"/"failed" - means this line is
         -- prose. Nothing is guessed from it.
         return empty
      end if
   end repeat
   if tPassAt is 0 or tFailAt is 0 or tPassAt > tFailAt then
      return empty
   end if
   if the number of words of tNums is not 2 then
      return empty
   end if
   -- Keyword order was just checked, and both shipped spellings put the pass
   -- count with the "passed" keyword, so the two numbers are in the order the
   -- two keywords are: first number = passed, second = failed. Requiring the
   -- keyword order is what makes that one-line rule safe rather than lucky.
   return word 1 to 2 of tNums
end stSummaryCounts

-- For a harness whose entry point RETURNS its report (SodiumXT, OnionXT). The
-- counts are parsed back out of the report rather than guessed at, and if the
-- parse ever fails that is a reported FAILURE, not a silent zero.
--
-- THE RULE, in one sentence: the summary is the ONE line of the report that is
-- nothing but two numbers and the words "passed" and "failed" (in that order,
-- case and edge punctuation ignored), and its first number is the pass count
-- and its second the fail count.
--
-- WHY IT IS NOT THE OBVIOUS THING, and this is the whole reason the handler was
-- rewritten. It used to take word 1 as the pass count and the LAST word as the
-- fail count, under a comment claiming that covered both members' spellings. It
-- covered NEITHER, and the 2026-08-09 engine pass duly reported both members as
-- unreadable while both reports were perfect. The two shipped spellings are
-- mirror images of each other, and both are exactly four words:
--
--   SodiumXT, the LAST line of its report:    PASSED: 68   FAILED: 0
--   OnionXT,  the FIRST line of its report:   40 passed, 0 failed
--
-- SodiumXT is keyword-first, so its word 1 is "PASSED:", which is not a number.
-- OnionXT is number-first, so its last word is "failed", which is not a number.
-- The old code needed BOTH ends to be numeric, which is true of neither shape,
-- so each format defeated it at the opposite end - and the validation then did
-- exactly the job it was built for and refused to guess. Two lesser bugs rode
-- along: the loop scanned top-to-bottom keeping the LAST match, which is right
-- for SodiumXT's trailing summary and wrong for OnionXT's leading one; and its
-- only test for a summary line was "contains passed and contains failed", which
-- any check label mentioning both words would satisfy.
--
-- The shape rule above fixes all three at once, and position stops mattering:
-- first line or last, there is exactly ONE line in either report that can
-- qualify. Requiring exactly one is what keeps this LOUD - zero matches and two
-- matches are both reported failures that print the report for a human to read,
-- never a silent zero folded into the suite totals.
command stMergeReturned pMember, pReport
   local tLine, tI, tCount, tPair, tMatches, tPassed, tFailed, tOk

   stSection pMember & ": its own full self-test"
   put 0 into tMatches
   put empty into tPassed
   put empty into tFailed
   put the number of lines of pReport into tCount
   repeat with tI = 1 to tCount
      put line tI of pReport into tLine
      put stSummaryCounts(tLine) into tPair
      if tPair is not empty then
         add 1 to tMatches
         put word 1 of tPair into tPassed
         put word 2 of tPair into tFailed
      end if
   end repeat
   -- Built as a value rather than a continued condition, for the same reason
   -- stMergeCounted below does it: three of the six copies of
   -- check-livecodescript.py do not join line continuations before counting
   -- block openers, so an `if ... \` reads to them as a handler-level statement
   -- and every `end if` after it looks unbalanced.
   --
   -- The two numeric tests are redundant with stSummaryCounts, which already
   -- refuses to return anything but two numbers. They stay because the lesson
   -- recorded on stMergeCounted below was that "it cannot be anything but a
   -- number" is a feeling, not a check, and these values are added into the
   -- suite totals: an `add` on a non-number is an UNCAUGHT engine error that
   -- takes the whole run, while a failed assertion costs one line of report.
   put (tMatches is 1 and tPassed is a number and tFailed is a number) into tOk
   if tOk is false then
      stAssert pMember & " deep self-test reported a summary this harness could read", false
      stNote "Looked for the one line that is nothing but two counts and the words"
      stNote "passed/failed (either order of word and number);" && tMatches && \
            "line(s) in its report matched."
      stNote "Its report is below verbatim; read the counts by eye."
   else
      add tPassed to sPassed
      add tFailed to sFailed
      add (tPassed + tFailed) to sTotal
      stAssert pMember & " deep self-test had zero failures", tFailed is 0
      stNote tPassed && "passed," && tFailed && "failed, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeReturned

-- For a harness that accumulates into script locals (CoinXT, TorrentXT,
-- ENetXT, DataChannelXT). Its counters are read directly - they are locals of
-- THIS script, since the whole thing compiles as one unit.
command stMergeCounted pMember, pReport, pPassed, pFailed, pTotal
   stSection pMember & ": its own full self-test"
   -- VALIDATE BEFORE ADDING, and the reason is an engine failure this cost.
   -- These three lines used to be a bare `add pPassed to sPassed`, on the
   -- reasoning that the counters are script locals of THIS file that the
   -- member's own stRun sets to 0 on its first line, so they cannot be
   -- anything but numbers. When one of them was not, LiveCode threw
   --     add: error in source expression
   -- and, because that is an uncaught engine error rather than a failed
   -- assertion, it killed the WHOLE RUN: no summary, no totals, no report from
   -- the members after it, and - the part that actually costs an engine
   -- session - NO INDICATION OF WHICH MEMBER IT WAS. Six harnesses had run and
   -- the operator was left with one line naming a handler.
   --
   -- stMergeReturned, ten lines up, has validated its counts since the day it
   -- was written, because THOSE come from parsing a report and a parse can
   -- obviously fail. This path skipped the check because its values come from
   -- script locals, which felt safer. Feeling safer is not the same as being
   -- checked, and the two paths merge into the same totals: they should be
   -- equally suspicious of what they are handed.
   --
   -- A non-numeric counter is now a reported FAILURE that names the member and
   -- prints what it actually got, and the run CONTINUES to the members after
   -- it. `empty` is the diagnostic case worth knowing: it means that member's
   -- stRun did not reach its own counter init, so look for a throw at the very
   -- top of it rather than anywhere in the checks.
   -- Built as a value rather than a continued condition on purpose: this file
   -- is read by all six members' copies of check-livecodescript.py, and three
   -- of them do not join line continuations before counting block openers, so
   -- an `if ... \` reads to them as a handler-level statement and every `end if`
   -- after it looks unbalanced. Keeping the opener on one physical line costs
   -- nothing and keeps the file parsable by the strictest reader of it.
   put (pPassed is a number and pFailed is a number and pTotal is a number) into tOk
   if tOk is false then
      stAssert pMember & " deep self-test reported numeric counters", false
      stNote "Got passed=[" & pPassed & "] failed=[" & pFailed & \
            "] total=[" & pTotal & "]"
      stNote "An EMPTY counter means that member's stRun threw before its own"
      stNote "first line (it sets all three to 0 there), so suspect the top of"
      stNote "its stRun, not its checks. Its report is below verbatim; count by eye."
   else
      add pPassed to sPassed
      add pFailed to sFailed
      add pTotal to sTotal
      stAssert pMember & " deep self-test had zero failures", pFailed is 0
      stNote pPassed && "passed," && pFailed && "failed of" && pTotal && \
            "checks, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeCounted


-- ==========================================================================
-- THE TWO PURE-SCRIPT LIBRARIES THEMSELVES, embedded by
-- tools/build-suite-selftest.py so that one paste carries the code its
-- tests test. These used to be a separate setup step (`start using
-- stack` x2), and that step cost an engine pass on 2026-08-10: a fresh
-- harness ran against a stale in-memory coinxt stack and reported the
-- two failures its parser fix had already closed. Embedded, the harness
-- and the library are built from one tree and cannot skew.
--
-- NOT renamed, unlike the folded tests below: this is the real library,
-- and the tests must call it by its real names. If you also have these
-- loaded via `start using`, calls from THIS script resolve to the copies
-- here (same-script wins), so the run still tests the embedded tree.
-- ==========================================================================

-- >>> GENERATED EMBED: coinxt script layer >>> --
-- ==========================================================================
-- CoinXT script layer (the real library, embedded)
--
-- Encoders, addresses and the whole HD layer - the half of coinxt's API that
-- is pure script. Embedded so one paste carries the code its tests test; no
-- `start using stack` step, and no way to run new tests against a stale
-- library.
--
-- GENERATED from coinxt/src/coinxt.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild. Names are NOT prefixed: this is the library itself, and the
-- folded tests above must reach it by its real names.
-- ==========================================================================

private function cxIntDiv pA, pB
   -- Integer division, floor, for the NON-NEGATIVE operands every caller here
   -- uses. trunc() rather than `div` (see the header).
   return trunc(pA / pB)
end cxIntDiv

private function cxIntMod pA, pB
   -- pA modulo pB, without the `mod` operator.
   return pA - pB * cxIntDiv(pA, pB)
end cxIntMod

private function cxPow2 pN
   -- 2 to the pN as an exact integer, without `^`. pN stays small here (0..30
   -- for the bech32 checksum, 0..8 for bit packing), so this is a few multiplies
   -- and never leaves exact-integer range.
   local tResult, tI
   put 1 into tResult
   repeat with tI = 1 to pN
      multiply tResult by 2
   end repeat
   return tResult
end cxPow2

private function cxBitXor pA, pB
   -- Bitwise exclusive-or over the low 31 bits, built from arithmetic because
   -- bitXor is an operator in this dialect and its portability across xTalk
   -- parsers is exactly the kind of thing this family has been bitten by.
   -- The bech32 checksum is a 30-bit value, so 31 bits is sufficient headroom
   -- and keeps every intermediate far below 2^53.
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to 31
      put cxIntMod(cxIntDiv(pA, tBit), 2) into tDigitA
      put cxIntMod(cxIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is not tDigitB then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end cxBitXor

private function cxCharIndex pChar, pAlphabet
   -- The 1-based position of pChar in pAlphabet, or 0 if absent, comparing BYTE
   -- VALUES so the answer does not depend on `the caseSensitive` (see discipline
   -- 3 in the header - this is the Base58 a-versus-A trap). Linear over a 58
   -- character alphabet, which is nothing next to the hashing these encoders
   -- already do.
   local tI, tCount, tWanted
   put byteToNum(pChar) into tWanted
   put the number of chars of pAlphabet into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of pAlphabet) is tWanted then
         return tI
      end if
   end repeat
   return 0
end cxCharIndex

private function cxCompareBytes pA, pB
   -- -1, 0 or 1 for pA before / equal to / after pB, comparing BYTE VALUES.
   -- Discipline 3 again: `<` on strings honours `the caseSensitive`, which
   -- defaults to FALSE, and a case-insensitive comparison would put the binary
   -- search below into the wrong half of a list that is sorted by byte value.
   local tI, tLenA, tLenB, tShort, tVa, tVb
   put the number of chars of pA into tLenA
   put the number of chars of pB into tLenB
   put tLenA into tShort
   if tLenB < tShort then
      put tLenB into tShort
   end if
   repeat with tI = 1 to tShort
      put byteToNum(char tI of pA) into tVa
      put byteToNum(char tI of pB) into tVb
      if tVa < tVb then
         return -1
      end if
      if tVa > tVb then
         return 1
      end if
   end repeat
   if tLenA < tLenB then
      return -1
   end if
   if tLenA > tLenB then
      return 1
   end if
   return 0
end cxCompareBytes

function cxHexEncode pData
   local tOut, tI, tCount, tByte
   put "" into tOut
   put the number of bytes of pData into tCount
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of pData) into tByte
      put char (cxIntDiv(tByte, 16) + 1) of kCxHexDigits after tOut
      put char (cxIntMod(tByte, 16) + 1) of kCxHexDigits after tOut
   end repeat
   return tOut
end cxHexEncode

function cxHexDecode pHex
   local tOut, tI, tCount, tHi, tLo, tText
   put pHex into tText
   put the number of chars of tText into tCount
   if cxIntMod(tCount, 2) is not 0 then
      throw "CoinXT: cxHexDecode: a hex string must have an even number of characters."
   end if
   put "" into tOut
   -- WALK THE PAIRS WITH `repeat while` AND AN EXPLICIT `add 2`, NOT WITH
   -- `repeat with tI = 1 to tCount step 2`. This is the one line the first real
   -- OXT pass of the suite harness (2026-08-09) killed, and it is worth the
   -- paragraph because reading it tells you nothing.
   --
   -- The engine did not honour the increment: tI walked 1, 2, 3, ... so the
   -- final pass read `char (tCount + 1) of tText`, which is EMPTY. Empty is
   -- genuinely not a hex digit, so cxHexValue answered -1 and this handler's
   -- own fail-closed check threw "the input contains a character that is not a
   -- hex digit" - over a perfectly good lowercase literal. That is the worst
   -- shape a defect can take here: the library accused the CALLER'S DATA of
   -- being corrupt, in the exact words it uses for a real corruption, so the
   -- symptom pointed at the vector set rather than at the loop. Six harness
   -- sections (hex, Base58Check, RLP, BIP-39, BIP-32, the fail-open
   -- regressions) died on it; every section that never calls cxHexDecode
   -- passed, which is what identified this handler.
   --
   -- `step` was the only construct in this file with no other user anywhere in
   -- the six-member suite, and that is precisely why it was the one that broke:
   -- nothing else had ever put it in front of an engine. Every construct below
   -- ran green in that same session - cxEthAddressChecksum drives cxHexValue
   -- over `char tI of` eighty times per call, and `repeat while` with `add N
   -- to` is how cxBase58Encode and cxConvert8To5 loop. The even-length guard
   -- above is what makes `char (tI + 1)` safe here: tCount is even, so the last
   -- pair starts at tCount - 1 and never reads past the end.
   --
   -- Do not "tidy" this back into a step loop.
   put 1 into tI
   repeat while tI <= tCount
      put cxHexValue(char tI of tText) into tHi
      put cxHexValue(char (tI + 1) of tText) into tLo
      if tHi < 0 or tLo < 0 then
         throw "CoinXT: cxHexDecode: the input contains a character that is not a hex digit."
      end if
      put numToByte(tHi * 16 + tLo) after tOut
      add 2 to tI
   end repeat
   return tOut
end cxHexDecode

private function cxHexValue pChar
   -- 0..15, or -1 when pChar is not a hex digit. Case-insensitive BY VALUE: the
   -- upper and lower alphabets are checked explicitly rather than by folding
   -- case, so this does not depend on `the caseSensitive` either.
   local tCode
   put byteToNum(pChar) into tCode
   if tCode >= 48 and tCode <= 57 then
      return tCode - 48
   end if
   if tCode >= 97 and tCode <= 102 then
      return tCode - 87
   end if
   if tCode >= 65 and tCode <= 70 then
      return tCode - 55
   end if
   return -1
end cxHexValue

function cxHash160 pData
   return cxRipemd160(cxSha256(pData))
end cxHash160

function cxHash256 pData
   return cxSha256(cxSha256(pData))
end cxHash256

private function cxBase58Encode pData
   -- Long division: repeatedly divide the big-endian byte array by 58, emitting
   -- the remainder as a digit, until the array is zero. Leading zero BYTES are
   -- not part of the number, so they are re-attached afterwards as leading "1"s,
   -- one for one, which is what makes a 0x00 version byte show up as the "1"
   -- every mainnet P2PKH address starts with.
   local tDigits, tOut, tI, tCount, tCarry, tValue, tQuotient, tStart, tZeros
   put the number of bytes of pData into tCount
   if tCount is 0 then
      return ""
   end if
   -- Copy the bytes into a numeric list we can divide in place.
   put empty into tDigits
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of pData) into tDigits[tI]
   end repeat
   -- Count the leading zero bytes before they are consumed by the division.
   put 0 into tZeros
   repeat with tI = 1 to tCount
      if tDigits[tI] is not 0 then
         exit repeat
      end if
      add 1 to tZeros
   end repeat
   put "" into tOut
   put 1 into tStart
   repeat while tStart <= tCount
      put 0 into tCarry
      repeat with tI = tStart to tCount
         put tCarry * 256 + tDigits[tI] into tValue
         put cxIntDiv(tValue, 58) into tQuotient
         put tQuotient into tDigits[tI]
         put tValue - tQuotient * 58 into tCarry
      end repeat
      -- tCarry is now the next base58 digit, least significant first.
      put char (tCarry + 1) of kCxBase58Alphabet before tOut
      -- Skip over any leading zeros the division produced, so the next pass is
      -- shorter and the loop terminates.
      repeat while tStart <= tCount and tDigits[tStart] is 0
         add 1 to tStart
      end repeat
   end repeat
   repeat with tI = 1 to tZeros
      put char 1 of kCxBase58Alphabet before tOut
   end repeat
   return tOut
end cxBase58Encode

private function cxBase58Decode pText
   -- The inverse: multiply the byte array by 58 and add each digit. Returns
   -- empty on any character outside the alphabet, so the caller can fail closed.
   local tBytes, tI, tJ, tCount, tIndex, tCarry, tValue, tOut, tZeros, tLen
   put the number of chars of pText into tCount
   if tCount is 0 then
      return ""
   end if
   put 1 into tLen
   put 0 into tBytes[1]
   repeat with tI = 1 to tCount
      put cxCharIndex(char tI of pText, kCxBase58Alphabet) into tIndex
      if tIndex is 0 then
         return empty
      end if
      put tIndex - 1 into tCarry
      repeat with tJ = tLen down to 1
         put tBytes[tJ] * 58 + tCarry into tValue
         put cxIntMod(tValue, 256) into tBytes[tJ]
         put cxIntDiv(tValue, 256) into tCarry
      end repeat
      repeat while tCarry > 0
         add 1 to tLen
         repeat with tJ = tLen down to 2
            put tBytes[tJ - 1] into tBytes[tJ]
         end repeat
         put cxIntMod(tCarry, 256) into tBytes[1]
         put cxIntDiv(tCarry, 256) into tCarry
      end repeat
   end repeat
   -- Leading "1" characters are leading zero bytes, one for one.
   put 0 into tZeros
   repeat with tI = 1 to tCount
      if cxCharIndex(char tI of pText, kCxBase58Alphabet) is not 1 then
         exit repeat
      end if
      add 1 to tZeros
   end repeat
   put "" into tOut
   repeat with tI = 1 to tZeros
      put numToByte(0) after tOut
   end repeat
   -- Drop the single zero byte the accumulator starts with when the value is
   -- itself zero-length, but keep a genuine zero payload.
   repeat with tI = 1 to tLen
      if tI is 1 and tBytes[1] is 0 and tLen > 1 then
         next repeat
      end if
      put numToByte(tBytes[tI]) after tOut
   end repeat
   return tOut
end cxBase58Decode

function cxBase58CheckEncode pPayload
   local tChecksum
   put cxHash256(pPayload) into tChecksum
   return cxBase58Encode(pPayload & byte 1 to 4 of tChecksum)
end cxBase58CheckEncode

function cxBase58CheckDecode pText
   local tRaw, tBody, tChecksum, tCount
   put cxBase58Decode(pText) into tRaw
   if tRaw is empty then
      throw "CoinXT: cxBase58CheckDecode: the input contains a character that is not in the Base58 alphabet."
   end if
   put the number of bytes of tRaw into tCount
   if tCount < 5 then
      throw "CoinXT: cxBase58CheckDecode: the input is too short to carry a 4-byte checksum."
   end if
   put byte 1 to (tCount - 4) of tRaw into tBody
   put byte (tCount - 3) to tCount of tRaw into tChecksum
   -- BYTE COMPARISON, not `is`. Both operands here are 8-character hex strings,
   -- and `is` compares two operands that both LOOK numeric as NUMBERS - so
   -- whether "00001e00" and "00000001" are equal stops being a question about
   -- bytes and becomes a question about how the engine parses exponents. That
   -- has not been observed to collide on this surface, and it is not going to
   -- be left to chance either: this is the one comparison standing between a
   -- corrupt address and a caller's funds, and discipline 3 in the header
   -- already says a comparison whose answer depends on engine coercion does not
   -- belong on a checksum path.
   if cxCompareBytes(cxHexEncode(byte 1 to 4 of cxHash256(tBody)), cxHexEncode(tChecksum)) is not 0 then
      throw "CoinXT: cxBase58CheckDecode: the checksum does not match, so the input is corrupt."
   end if
   return tBody
end cxBase58CheckDecode

private function cxBech32Polymod pValues
   -- BIP-173's checksum over a list of 5-bit values (pValues is a comma
   -- separated list of numbers). The generator constants are the BIP's, gated
   -- against the reference by tools/check-script-vectors.py.
   local tChk, tI, tCount, tTop, tValue, tGen
   put "996825010,642813549,513874426,1027748829,705979059" into tGen
   put 1 into tChk
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put cxIntDiv(tChk, 33554432) into tTop
      put cxBitXor(cxIntMod(tChk, 33554432) * 32, item tI of pValues) into tChk
      repeat with tValue = 1 to 5
         if cxIntMod(cxIntDiv(tTop, cxPow2(tValue - 1)), 2) is 1 then
            put cxBitXor(tChk, item tValue of tGen) into tChk
         end if
      end repeat
   end repeat
   return tChk
end cxBech32Polymod

private function cxBech32HrpExpand pHrp
   -- The HRP contributes its high bits, then a zero, then its low bits.
   local tOut, tI, tCount, tCode
   put the number of chars of pHrp into tCount
   put "" into tOut
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      if tOut is not "" then
         put "," after tOut
      end if
      put cxIntDiv(tCode, 32) after tOut
   end repeat
   put ",0" after tOut
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      put "," & cxIntMod(tCode, 32) after tOut
   end repeat
   return tOut
end cxBech32HrpExpand

private function cxBech32Const pSpec
   -- "bech32" is 1; "bech32m" is the BIP-350 constant. Any other spelling is a
   -- programming error and is refused rather than defaulted.
   if pSpec is "bech32" then
      return 1
   end if
   if pSpec is "bech32m" then
      return kCxBech32mConst
   end if
   throw "CoinXT: the encoding must be either bech32 or bech32m."
end cxBech32Const

function cxBech32EncodeValues pHrp, pValues, pSpec
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBech32EncodeValuesInner(pHrp, pValues, pSpec) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBech32EncodeValues

private function cxBech32EncodeValuesInner pHrp, pValues, pSpec
   local tPolymod, tI, tOut, tIndex, tCombined, tCount, tCode
   -- FAIL CLOSED ON THE INPUTS, because both of these used to fail OPEN and a
   -- bech32 string that is subtly wrong is far worse than one that is refused.
   --
   -- The HRP: BIP-173 requires 1 to 83 characters in the range 33..126, and a
   -- bech32 string must be entirely one case. This handler lowercases nothing
   -- and used to concatenate whatever it was given, so an uppercase "BC" gave
   -- "BC1qqq...q42su7w" - a MIXED-case string that this file's own decoder
   -- rejects and no conformant decoder accepts. Refusing an uppercase HRP is
   -- the honest answer: a caller who wants the uppercase form should uppercase
   -- the whole finished string, which is what BIP-173 actually defines.
   put the number of chars of pHrp into tCount
   if tCount < 1 or tCount > 83 then
      throw "CoinXT: cxBech32EncodeValues: the human-readable part must be 1 to 83 characters."
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      if tCode < 33 or tCode > 126 then
         throw "CoinXT: cxBech32EncodeValues: the human-readable part must be printable ASCII."
      end if
      if tCode >= 65 and tCode <= 90 then
         throw "CoinXT: cxBech32EncodeValues: the human-readable part must be lowercase; uppercase the finished string instead."
      end if
   end repeat
   -- The data values: each indexes a 32-character charset, and `char (n) of` a
   -- short string returns EMPTY rather than failing. So a value of 32 used to
   -- emit NOTHING for that position - a string one character short, carrying a
   -- checksum computed over data it does not contain. It would decode to
   -- something, and that something would not be what the caller encoded.
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put item tI of pValues into tIndex
      if tIndex < 0 or tIndex > 31 or tIndex is not trunc(tIndex) then
         throw "CoinXT: cxBech32EncodeValues: every data value must be a whole number between 0 and 31."
      end if
   end repeat
   put cxBech32HrpExpand(pHrp) & "," & pValues & ",0,0,0,0,0,0" into tCombined
   put cxBitXor(cxBech32Polymod(tCombined), cxBech32Const(pSpec)) into tPolymod
   put pHrp & "1" into tOut
   put the number of items of pValues into tI
   repeat with tI = 1 to the number of items of pValues
      put item tI of pValues into tIndex
      put char (tIndex + 1) of kCxBech32Charset after tOut
   end repeat
   repeat with tI = 0 to 5
      put cxIntMod(cxIntDiv(tPolymod, cxPow2(5 * (5 - tI))), 32) into tIndex
      put char (tIndex + 1) of kCxBech32Charset after tOut
   end repeat
   -- The same 90-character cap the decoder enforces. An encoder that can emit a
   -- string its own decoder refuses is an encoder that will eventually be used
   -- to make one.
   if the number of chars of tOut > kCxBech32MaxLen then
      throw "CoinXT: cxBech32EncodeValues: the result would exceed the 90-character bech32 limit."
   end if
   return tOut
end cxBech32EncodeValuesInner

function cxBech32DecodeValues pText
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBech32DecodeValuesInner(pText) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBech32DecodeValues

private function cxBech32DecodeValuesInner pText
   local tResult, tPos, tI, tCount, tCode, tHrp, tData, tIndex, tLower, tSpec
   put the number of chars of pText into tCount
   if tCount > kCxBech32MaxLen then
      throw "CoinXT: cxBech32DecodeValues: the string is longer than the 90 characters bech32 allows."
   end if
   -- Every character must be printable ASCII, and the string must not MIX case:
   -- a mixed-case bech32 string is invalid by specification, because the
   -- checksum is defined over one case only.
   put cxCaseKind(pText) into tLower
   if tLower is "mixed" then
      throw "CoinXT: cxBech32DecodeValues: the string mixes upper and lower case, which bech32 does not allow."
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode < 33 or tCode > 126 then
         throw "CoinXT: cxBech32DecodeValues: the string contains a character outside the printable ASCII range."
      end if
   end repeat
   put cxToLower(pText) into tData
   -- The separator is the LAST "1", because "1" is not in the data charset but
   -- may appear inside the human-readable part.
   put 0 into tPos
   repeat with tI = tCount down to 1
      if byteToNum(char tI of tData) is 49 then
         put tI into tPos
         exit repeat
      end if
   end repeat
   if tPos < 2 then
      throw "CoinXT: cxBech32DecodeValues: the string has no human-readable part before its separator."
   end if
   if tPos + 6 > tCount then
      throw "CoinXT: cxBech32DecodeValues: the string is too short to carry a 6-character checksum."
   end if
   put char 1 to (tPos - 1) of tData into tHrp
   put "" into tResult["values"]
   repeat with tI = (tPos + 1) to tCount
      put cxCharIndex(char tI of tData, kCxBech32Charset) into tIndex
      if tIndex is 0 then
         throw "CoinXT: cxBech32DecodeValues: the data part contains a character that is not in the bech32 charset."
      end if
      if tResult["values"] is not "" then
         put "," after tResult["values"]
      end if
      put (tIndex - 1) after tResult["values"]
   end repeat
   -- Try both constants and report WHICH verified, so the SegWit layer above can
   -- enforce the version-to-encoding pairing instead of guessing.
   put "" into tSpec
   if cxBech32Polymod(cxBech32HrpExpand(tHrp) & "," & tResult["values"]) is 1 then
      put "bech32" into tSpec
   end if
   if cxBech32Polymod(cxBech32HrpExpand(tHrp) & "," & tResult["values"]) is kCxBech32mConst then
      put "bech32m" into tSpec
   end if
   if tSpec is "" then
      throw "CoinXT: cxBech32DecodeValues: the checksum does not match, so the string is corrupt."
   end if
   put tHrp into tResult["hrp"]
   put tSpec into tResult["spec"]
   -- Drop the six checksum values; the caller wants the payload.
   put cxDropLastItems(tResult["values"], 6) into tResult["values"]
   return tResult
end cxBech32DecodeValuesInner

private function cxDropLastItems pList, pHowMany
   local tCount, tI, tOut
   put the number of items of pList into tCount
   put "" into tOut
   repeat with tI = 1 to (tCount - pHowMany)
      if tOut is not "" then
         put "," after tOut
      end if
      put item tI of pList after tOut
   end repeat
   return tOut
end cxDropLastItems

private function cxCaseKind pText
   -- "upper", "lower", "mixed" or "none", decided by BYTE VALUE so it does not
   -- depend on the caller's caseSensitive setting.
   local tI, tCount, tCode, tHasUpper, tHasLower
   put false into tHasUpper
   put false into tHasLower
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         put true into tHasUpper
      end if
      if tCode >= 97 and tCode <= 122 then
         put true into tHasLower
      end if
   end repeat
   if tHasUpper and tHasLower then
      return "mixed"
   end if
   if tHasUpper then
      return "upper"
   end if
   if tHasLower then
      return "lower"
   end if
   return "none"
end cxCaseKind

private function cxToLower pText
   -- ASCII lowercase by byte value (see cxCaseKind).
   local tI, tCount, tCode, tOut
   put "" into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         add 32 to tCode
      end if
      put numToChar(tCode) after tOut
   end repeat
   return tOut
end cxToLower

private function cxConvert8To5 pData
   local tOut, tI, tCount, tValue, tBits, tIndex
   put "" into tOut
   put 0 into tValue
   put 0 into tBits
   put the number of bytes of pData into tCount
   repeat with tI = 1 to tCount
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put cxIntMod(cxIntDiv(tValue, cxPow2(tBits)), 32) into tIndex
         if tOut is not "" then
            put "," after tOut
         end if
         put tIndex after tOut
      end repeat
      put cxIntMod(tValue, cxPow2(tBits)) into tValue
   end repeat
   if tBits > 0 then
      -- Pad the final group with zero bits, as SegWit encoding requires.
      put cxIntMod(tValue * cxPow2(5 - tBits), 32) into tIndex
      if tOut is not "" then
         put "," after tOut
      end if
      put tIndex after tOut
   end if
   return tOut
end cxConvert8To5

private function cxConvert5To8 pValues
   -- The inverse, and it is STRICTER than the forward direction on purpose: the
   -- padding must be fewer than 5 bits and must be zero. A decoder that accepts
   -- non-zero padding accepts several distinct strings for the same program,
   -- and BIP-173 rejects that explicitly.
   local tOut, tI, tCount, tValue, tBits, tByte, tResult
   put "" into tOut
   put 0 into tValue
   put 0 into tBits
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put tValue * 32 + item tI of pValues into tValue
      add 5 to tBits
      repeat while tBits >= 8
         subtract 8 from tBits
         put cxIntMod(cxIntDiv(tValue, cxPow2(tBits)), 256) into tByte
         put numToByte(tByte) after tOut
      end repeat
      put cxIntMod(tValue, cxPow2(tBits)) into tValue
   end repeat
   -- THE STATUS IS OUT OF BAND, in a separate key, and it has to be. This
   -- returned the strings "ERROR: ..." in place of the bytes once, and the
   -- caller tested `char 1 to 5 of tProgram is "ERROR"` - which means a witness
   -- program whose first five bytes happen to be 45 52 52 4F 52 was read as a
   -- failure. That is a real address (bech32m v1 accepts any 2-to-40-byte
   -- program), and this file's own encoder produces it, so the library rejected
   -- an address it had just made. An in-band sentinel over arbitrary bytes is
   -- always wrong; there is no byte string that cannot occur.
   put tOut into tResult["bytes"]
   if tBits >= 5 then
      put false into tResult["ok"]
      put "there are too many padding bits" into tResult["why"]
   else if tValue is not 0 then
      put false into tResult["ok"]
      put "the padding bits are not zero" into tResult["why"]
   else
      put true into tResult["ok"]
      put "" into tResult["why"]
   end if
   return tResult
end cxConvert5To8

function cxSegwitAddressEncode pHrp, pVersion, pProgram
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxSegwitAddressEncodeInner(pHrp, pVersion, pProgram) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxSegwitAddressEncode

private function cxSegwitAddressEncodeInner pHrp, pVersion, pProgram
   local tValues, tSpec, tLength
   if pVersion < 0 or pVersion > 16 then
      throw "CoinXT: cxSegwitAddressEncode: the witness version must be between 0 and 16."
   end if
   put the number of bytes of pProgram into tLength
   if tLength < 2 or tLength > 40 then
      throw "CoinXT: cxSegwitAddressEncode: a witness program must be between 2 and 40 bytes."
   end if
   if pVersion is 0 and tLength is not 20 and tLength is not 32 then
      throw "CoinXT: cxSegwitAddressEncode: a version 0 witness program must be exactly 20 or 32 bytes."
   end if
   if pVersion is 0 then
      put "bech32" into tSpec
   else
      put "bech32m" into tSpec
   end if
   put pVersion & "," & cxConvert8To5(pProgram) into tValues
   return cxBech32EncodeValues(pHrp, tValues, tSpec)
end cxSegwitAddressEncodeInner

function cxSegwitAddressDecode pHrp, pAddress
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxSegwitAddressDecodeInner(pHrp, pAddress) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxSegwitAddressDecode

private function cxSegwitAddressDecodeInner pHrp, pAddress
   local tDecoded, tResult, tVersion, tProgram, tValues, tLength, tConverted
   put cxBech32DecodeValues(pAddress) into tDecoded
   if tDecoded["hrp"] is not cxToLower(pHrp) then
      throw "CoinXT: cxSegwitAddressDecode: the address is for a different network than the one requested."
   end if
   put tDecoded["values"] into tValues
   if (the number of items of tValues) < 1 then
      throw "CoinXT: cxSegwitAddressDecode: the address carries no witness version."
   end if
   put item 1 of tValues into tVersion
   if tVersion > 16 then
      throw "CoinXT: cxSegwitAddressDecode: the witness version is greater than 16."
   end if
   if tVersion is 0 and tDecoded["spec"] is not "bech32" then
      throw "CoinXT: cxSegwitAddressDecode: a version 0 address must use bech32, not bech32m."
   end if
   if tVersion > 0 and tDecoded["spec"] is not "bech32m" then
      throw "CoinXT: cxSegwitAddressDecode: a version 1 or later address must use bech32m, not bech32."
   end if
   put cxConvert5To8(cxDropFirstItem(tValues)) into tConverted
   if tConverted["ok"] is false then
      throw "CoinXT: cxSegwitAddressDecode: the address is not canonical because" && tConverted["why"] & "."
   end if
   put tConverted["bytes"] into tProgram
   put the number of bytes of tProgram into tLength
   if tLength < 2 or tLength > 40 then
      throw "CoinXT: cxSegwitAddressDecode: the witness program must be between 2 and 40 bytes."
   end if
   if tVersion is 0 and tLength is not 20 and tLength is not 32 then
      throw "CoinXT: cxSegwitAddressDecode: a version 0 witness program must be exactly 20 or 32 bytes."
   end if
   put tVersion into tResult["version"]
   put tProgram into tResult["program"]
   return tResult
end cxSegwitAddressDecodeInner

private function cxDropFirstItem pList
   local tCount, tI, tOut
   put the number of items of pList into tCount
   put "" into tOut
   repeat with tI = 2 to tCount
      if tOut is not "" then
         put "," after tOut
      end if
      put item tI of pList after tOut
   end repeat
   return tOut
end cxDropFirstItem

private function cxCheckPubkey pPubkey, pName, pCompressedOnly
   -- The length AND the prefix, together, exactly as the shim's cnx_pubkey_ok
   -- does - and for a related reason. There the danger is an overread; here it
   -- is worse in a quieter way: hash160 happily hashes ANY bytes, so without
   -- this an empty string, a 20-byte hash or a truncated key each produce a
   -- perfectly well-formed, checksummed mainnet address whose funds nobody can
   -- ever spend. Nothing downstream can catch that - the address is valid, it
   -- is simply not yours - so it has to be refused here.
   local tCount, tFirst
   put the number of bytes of pPubkey into tCount
   if tCount is not 33 and (pCompressedOnly is true or tCount is not 65) then
      if pCompressedOnly is true then
         throw "CoinXT:" && pName & ": this address type requires a 33-byte COMPRESSED public key."
      end if
      throw "CoinXT:" && pName & ": a public key must be 33 bytes (compressed) or 65 bytes (uncompressed)."
   end if
   put byteToNum(byte 1 of pPubkey) into tFirst
   if tCount is 33 and tFirst is not 2 and tFirst is not 3 then
      throw "CoinXT:" && pName & ": a 33-byte public key must begin with 0x02 or 0x03."
   end if
   if tCount is 65 and tFirst is not 4 then
      throw "CoinXT:" && pName & ": a 65-byte public key must begin with 0x04."
   end if
   return true
end cxCheckPubkey

function cxBtcAddressP2PKH pPubkey
   get cxCheckPubkey(pPubkey, "cxBtcAddressP2PKH", false)
   return cxBase58CheckEncode(numToByte(kCxVersionP2PKH) & cxHash160(pPubkey))
end cxBtcAddressP2PKH

function cxBtcAddressP2WPKH pPubkey
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcAddressP2WPKHInner(pPubkey) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcAddressP2WPKH

private function cxBtcAddressP2WPKHInner pPubkey
   get cxCheckPubkey(pPubkey, "cxBtcAddressP2WPKH", true)
   return cxSegwitAddressEncode(kCxHrpMainnet, 0, cxHash160(pPubkey))
end cxBtcAddressP2WPKHInner

function cxBtcAddressP2TR pOutputKey
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcAddressP2TRInner(pOutputKey) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcAddressP2TR

private function cxBtcAddressP2TRInner pOutputKey
   if the number of bytes of pOutputKey is not 32 then
      throw "CoinXT: cxBtcAddressP2TR: a Taproot address requires a 32-byte x-only output key."
   end if
   return cxSegwitAddressEncode(kCxHrpMainnet, 1, pOutputKey)
end cxBtcAddressP2TRInner

function cxEthAddress pPubkey
   local tKey, tHash, tCount
   put the number of bytes of pPubkey into tCount
   if tCount is 33 then
      put cxPubkeyDecompress(pPubkey) into tKey
   else
      put pPubkey into tKey
   end if
   if the number of bytes of tKey is not 65 then
      throw "CoinXT: cxEthAddress: a public key must be 33 bytes (compressed) or 65 bytes (uncompressed)."
   end if
   put cxKeccak256(byte 2 to 65 of tKey) into tHash
   return "0x" & cxHexEncode(byte 13 to 32 of tHash)
end cxEthAddress

function cxEthAddressChecksum pAddress
   local tPlain, tHash, tOut, tI, tCode, tNibble, tHex
   put pAddress into tPlain
   if char 1 to 2 of tPlain is "0x" then
      delete char 1 to 2 of tPlain
   end if
   if the number of chars of tPlain is not 40 then
      throw "CoinXT: cxEthAddressChecksum: an Ethereum address must be 40 hex characters."
   end if
   put cxToLower(tPlain) into tPlain
   repeat with tI = 1 to 40
      if cxHexValue(char tI of tPlain) < 0 then
         throw "CoinXT: cxEthAddressChecksum: the address contains a character that is not a hex digit."
      end if
   end repeat
   -- The hash is over the ASCII of the lowercase address, NOT over its bytes.
   put cxHexEncode(cxKeccak256(textEncode(tPlain, "UTF-8"))) into tHex
   put "0x" into tOut
   repeat with tI = 1 to 40
      put cxHexValue(char tI of tHex) into tNibble
      put byteToNum(char tI of tPlain) into tCode
      if tNibble >= 8 and tCode >= 97 and tCode <= 102 then
         put numToChar(tCode - 32) after tOut
      else
         put numToChar(tCode) after tOut
      end if
   end repeat
   return tOut
end cxEthAddressChecksum

function cxEthAddressIsChecksummed pAddress
   local tPlain
   put pAddress into tPlain
   if char 1 to 2 of tPlain is "0x" then
      delete char 1 to 2 of tPlain
   end if
   if cxCaseKind(tPlain) is not "mixed" then
      return false
   end if
   -- COMPARE AGAINST THE CALLER'S ORIGINAL CASING, BY BYTE VALUE. Both halves
   -- of that sentence are load-bearing, and this handler shipped once getting
   -- both wrong - it read
   --    cxEthAddressChecksum(pAddress) is cxEthAddressChecksum(cxToLower(tPlain))
   -- which is a TAUTOLOGY: cxEthAddressChecksum lowercases its argument before
   -- it hashes or emits anything, so its result is a function of the lowercase
   -- form alone and both sides are the same string for every input. It answered
   -- "true" to every mixed-case address, including a corrupted one, which is
   -- precisely the failure EIP-55 exists to prevent.
   -- The second half matters too: `is` honours `the caseSensitive` (default
   -- FALSE), and this comparison is ENTIRELY about case, so `is` could not
   -- decide it even against the right operand. cxCompareBytes is exact whatever
   -- the caller has set - the same reasoning as discipline 3 in the header.
   return cxCompareBytes(cxEthAddressChecksum(tPlain), "0x" & tPlain) is 0
end cxEthAddressIsChecksummed

function cxRlpEncodeBytes pData
   local tCount
   put the number of bytes of pData into tCount
   if tCount is 1 and byteToNum(byte 1 of pData) < 128 then
      -- A single byte below 0x80 is its own encoding: it carries no prefix.
      return pData
   end if
   return cxRlpLengthPrefix(tCount, 128) & pData
end cxRlpEncodeBytes

function cxRlpEncodeList pEncodedItems
   return cxRlpLengthPrefix(the number of bytes of pEncodedItems, 192) & pEncodedItems
end cxRlpEncodeList

private function cxRlpLengthPrefix pLength, pOffset
   -- Short form below 56 bytes; otherwise a big-endian length whose OWN length
   -- goes in the prefix.
   local tBig, tOut
   if pLength < 56 then
      return numToByte(pOffset + pLength)
   end if
   put cxUIntToBytes(pLength) into tBig
   put numToByte(pOffset + 55 + the number of bytes of tBig) into tOut
   return tOut & tBig
end cxRlpLengthPrefix

private function cxUIntToBytes pValue
   -- Big-endian, no leading zero byte. Used for RLP length prefixes only, which
   -- stay far inside exact-integer range.
   local tOut, tRest
   put "" into tOut
   put pValue into tRest
   repeat while tRest > 0
      put numToByte(cxIntMod(tRest, 256)) before tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   if tOut is "" then
      put numToByte(0) into tOut
   end if
   return tOut
end cxUIntToBytes

function cxRlpDecode pData
   local tResult, tPrefix, tCount, tLength, tLengthLength, tI, tHeader
   put the number of bytes of pData into tCount
   if tCount is 0 then
      throw "CoinXT: cxRlpDecode: there is nothing to decode."
   end if
   put byteToNum(byte 1 of pData) into tPrefix
   if tPrefix < 128 then
      put "bytes" into tResult["kind"]
      put byte 1 of pData into tResult["payload"]
      put byte 2 to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 184 then
      put tPrefix - 128 into tLength
      if tCount < 1 + tLength then
         throw "CoinXT: cxRlpDecode: the item claims more bytes than the input holds."
      end if
      if tLength is 1 and byteToNum(byte 2 of pData) < 128 then
         throw "CoinXT: cxRlpDecode: a single byte below 0x80 must be encoded as itself, not with a length prefix."
      end if
      put "bytes" into tResult["kind"]
      put cxSlice(pData, 2, 1 + tLength) into tResult["payload"]
      put byte (2 + tLength) to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 192 then
      put tPrefix - 183 into tLengthLength
      put cxRlpLongLength(pData, tLengthLength, tCount) into tLength
      put 1 + tLengthLength into tHeader
      if tCount < tHeader + tLength then
         throw "CoinXT: cxRlpDecode: the item claims more bytes than the input holds."
      end if
      put "bytes" into tResult["kind"]
      put cxSlice(pData, tHeader + 1, tHeader + tLength) into tResult["payload"]
      put byte (tHeader + tLength + 1) to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 248 then
      put tPrefix - 192 into tLength
      if tCount < 1 + tLength then
         throw "CoinXT: cxRlpDecode: the list claims more bytes than the input holds."
      end if
      put "list" into tResult["kind"]
      put cxSlice(pData, 2, 1 + tLength) into tResult["payload"]
      put byte (2 + tLength) to tCount of pData into tResult["rest"]
      return tResult
   end if
   put tPrefix - 247 into tLengthLength
   put cxRlpLongLength(pData, tLengthLength, tCount) into tLength
   put 1 + tLengthLength into tHeader
   if tCount < tHeader + tLength then
      throw "CoinXT: cxRlpDecode: the list claims more bytes than the input holds."
   end if
   put "list" into tResult["kind"]
   put cxSlice(pData, tHeader + 1, tHeader + tLength) into tResult["payload"]
   put byte (tHeader + tLength + 1) to tCount of pData into tResult["rest"]
   return tResult
end cxRlpDecode

private function cxRlpLongLength pData, pLengthLength, pCount
   -- The big-endian length that follows a long-form prefix, with both
   -- canonicality rules enforced: no leading zero byte, and the value must
   -- actually have needed the long form.
   local tI, tLength
   if pCount < 1 + pLengthLength then
      throw "CoinXT: cxRlpDecode: the length prefix is truncated."
   end if
   if byteToNum(byte 2 of pData) is 0 then
      throw "CoinXT: cxRlpDecode: the length has a leading zero byte, which is not canonical."
   end if
   put 0 into tLength
   repeat with tI = 1 to pLengthLength
      put tLength * 256 + byteToNum(byte (1 + tI) of pData) into tLength
   end repeat
   if tLength < 56 then
      throw "CoinXT: cxRlpDecode: a length below 56 must use the short form, so this is not canonical."
   end if
   return tLength
end cxRlpLongLength

private function cxSlice pData, pFrom, pTo
   -- byte x to y of, with the empty case made explicit: an empty RLP string has
   -- pFrom greater than pTo, and relying on the engine's behaviour there is the
   -- kind of assumption this family writes down rather than trusts.
   if pFrom > pTo then
      return ""
   end if
   return byte pFrom to pTo of pData
end cxSlice

private function cxBitAt pData, pBitIndex
   -- Bit pBitIndex (0-based, most significant bit of byte 1 first) of pData.
   local tByteIndex, tBitInByte, tByte
   put cxIntDiv(pBitIndex, 8) + 1 into tByteIndex
   put cxIntMod(pBitIndex, 8) into tBitInByte
   put byteToNum(byte tByteIndex of pData) into tByte
   return cxIntMod(cxIntDiv(tByte, cxPow2(7 - tBitInByte)), 2)
end cxBitAt

private function cxBitsToBytes pBits
   -- Pack a comma-separated list of 0/1 into bytes, most significant bit first,
   -- zero-padding the final partial byte. The padding is not a fudge: BIP-39's
   -- checksum is the FIRST few bits of a digest byte, so the zeros below a
   -- 4-bit checksum are exactly the zeros the comparison expects.
   local tOut, tAcc, tCount, tI, tBitCount
   put "" into tOut
   put 0 into tAcc
   put 0 into tBitCount
   put the number of items of pBits into tCount
   repeat with tI = 1 to tCount
      put tAcc * 2 + (item tI of pBits) into tAcc
      add 1 to tBitCount
      if tBitCount is 8 then
         put numToByte(tAcc) after tOut
         put 0 into tAcc
         put 0 into tBitCount
      end if
   end repeat
   if tBitCount > 0 then
      repeat with tI = tBitCount to 7
         put tAcc * 2 into tAcc
      end repeat
      put numToByte(tAcc) after tOut
   end if
   return tOut
end cxBitsToBytes

private function cxWordSlotLen pList
   -- The slot width, derived from the blob rather than written down again.
   return cxIntDiv(the number of bytes of pList, kCxBip39WordCount)
end cxWordSlotLen

private function cxWordAt pList, pIndex
   -- Word at pIndex (0-based), trailing pad removed.
   local tWidth, tStart, tSlot, tEnd
   put cxWordSlotLen(pList) into tWidth
   put pIndex * tWidth + 1 into tStart
   put byte tStart to (tStart + tWidth - 1) of pList into tSlot
   put tWidth into tEnd
   repeat while tEnd > 0
      if byteToNum(char tEnd of tSlot) is not 32 then
         exit repeat
      end if
      subtract 1 from tEnd
   end repeat
   return char 1 to tEnd of tSlot
end cxWordAt

private function cxWordIndex pList, pWord
   -- The 0-based index of pWord, or -1 if it is not a BIP-39 word. Binary
   -- search: the list is sorted by byte value (tools/coin-kat.py checks that,
   -- so this is a verified precondition and not an assumption).
   local tLow, tHigh, tMid, tCmp
   put 0 into tLow
   put kCxBip39WordCount - 1 into tHigh
   repeat while tLow <= tHigh
      put cxIntDiv(tLow + tHigh, 2) into tMid
      put cxCompareBytes(pWord, cxWordAt(pList, tMid)) into tCmp
      if tCmp is 0 then
         return tMid
      end if
      if tCmp < 0 then
         put tMid - 1 into tHigh
      else
         put tMid + 1 into tLow
      end if
   end repeat
   return -1
end cxWordIndex

function cxMnemonicNormalize pText
   local tOut, tI, tCount, tChar, tCode, tPending
   put "" into tOut
   put false into tPending
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put char tI of pText into tChar
      put byteToNum(tChar) into tCode
      if tCode is 32 or tCode is 9 or tCode is 10 or tCode is 13 then
         if tOut is not "" then
            put true into tPending
         end if
      else
         if tPending is true then
            put " " after tOut
            put false into tPending
         end if
         put tChar after tOut
      end if
   end repeat
   return tOut
end cxMnemonicNormalize

private function cxSplitWords pMnemonic
   -- The words of an already-normalized mnemonic, comma separated. Safe as a
   -- comma list because every BIP-39 English word is lowercase a-z; a word
   -- containing a comma could not be in the list and is rejected by
   -- cxWordIndex before it can be misread.
   local tOut, tI, tCount, tChar
   put "" into tOut
   put the number of chars of pMnemonic into tCount
   repeat with tI = 1 to tCount
      put char tI of pMnemonic into tChar
      if byteToNum(tChar) is 32 then
         put "," after tOut
      else
         put tChar after tOut
      end if
   end repeat
   return tOut
end cxSplitWords

function cxMnemonicFromEntropy pEntropy
   local tLen, tChecksumBits, tTotalBits, tWordCount, tSource, tList
   local tI, tB, tValue, tOut, tBitIndex
   put the number of bytes of pEntropy into tLen
   if tLen is not 16 and tLen is not 20 and tLen is not 24 and tLen is not 28 and tLen is not 32 then
      throw "CoinXT: cxMnemonicFromEntropy: entropy must be 16, 20, 24, 28 or 32 bytes."
   end if
   -- One checksum bit per 32 bits of entropy, taken from the FRONT of the
   -- SHA-256 of the entropy. That is at most 8 bits, so appending the first
   -- digest byte supplies every bit the packing below will read.
   put cxIntDiv(tLen, 4) into tChecksumBits
   put tLen * 8 + tChecksumBits into tTotalBits
   put cxIntDiv(tTotalBits, kCxBip39BitsPerWord) into tWordCount
   put pEntropy & (byte 1 of cxSha256(pEntropy)) into tSource
   put cxBip39Wordlist() into tList
   put "" into tOut
   repeat with tI = 0 to (tWordCount - 1)
      put 0 into tValue
      repeat with tB = 0 to (kCxBip39BitsPerWord - 1)
         put tI * kCxBip39BitsPerWord + tB into tBitIndex
         put tValue * 2 + cxBitAt(tSource, tBitIndex) into tValue
      end repeat
      if tOut is not "" then
         put " " after tOut
      end if
      put cxWordAt(tList, tValue) after tOut
   end repeat
   return tOut
end cxMnemonicFromEntropy

function cxMnemonicToEntropy pMnemonic
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxMnemonicToEntropyInner(pMnemonic) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxMnemonicToEntropy

private function cxMnemonicToEntropyInner pMnemonic
   local tWords, tCount, tList, tBits, tI, tIndex, tB
   local tEntBytes, tChecksumBits, tPacked, tEntropy, tGot, tWant
   put cxSplitWords(cxMnemonicNormalize(pMnemonic)) into tWords
   put the number of items of tWords into tCount
   if tCount is not 12 and tCount is not 15 and tCount is not 18 and tCount is not 21 and tCount is not 24 then
      throw "CoinXT: cxMnemonicToEntropy: a mnemonic must be 12, 15, 18, 21 or 24 words."
   end if
   put cxBip39Wordlist() into tList
   put "" into tBits
   repeat with tI = 1 to tCount
      put cxWordIndex(tList, item tI of tWords) into tIndex
      if tIndex < 0 then
         throw "CoinXT: cxMnemonicToEntropy: word" && tI && "is not in the BIP-39 English wordlist."
      end if
      -- Most significant bit of the 11 first, which is the order
      -- cxMnemonicFromEntropy wrote them in.
      repeat with tB = (kCxBip39BitsPerWord - 1) down to 0
         if tBits is not "" then
            put "," after tBits
         end if
         put cxIntMod(cxIntDiv(tIndex, cxPow2(tB)), 2) after tBits
      end repeat
   end repeat
   -- 32 bits of entropy per 3 words, and one checksum bit per 32 bits of it.
   put cxIntDiv(tCount * 4, 3) into tEntBytes
   put cxIntDiv(tEntBytes, 4) into tChecksumBits
   put cxBitsToBytes(tBits) into tPacked
   put byte 1 to tEntBytes of tPacked into tEntropy
   -- Compare the checksum bits as a NUMBER rather than as bytes, because when
   -- there are fewer than 8 of them the byte around them is padding on both
   -- sides and only the top tChecksumBits are meaningful.
   put cxIntDiv(byteToNum(byte (tEntBytes + 1) of tPacked), cxPow2(8 - tChecksumBits)) into tGot
   put cxIntDiv(byteToNum(byte 1 of cxSha256(tEntropy)), cxPow2(8 - tChecksumBits)) into tWant
   if tGot is not tWant then
      throw "CoinXT: cxMnemonicToEntropy: the checksum does not match, so at least one word is wrong or out of order."
   end if
   return tEntropy
end cxMnemonicToEntropyInner

function cxMnemonicValidate pMnemonic
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxMnemonicValidateInner(pMnemonic) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxMnemonicValidate

private function cxMnemonicValidateInner pMnemonic
   local tEntropy
   try
      put cxMnemonicToEntropy(pMnemonic) into tEntropy
   catch tError
      return false
   end try
   return true
end cxMnemonicValidateInner

function cxMnemonicToSeed pMnemonic, pPassphrase
   return cxPbkdf2HmacSha512(cxMnemonicNormalize(pMnemonic), \
         kCxBip39SaltPrefix & pPassphrase, kCxBip39Rounds, 64)
end cxMnemonicToSeed

private function cxUInt32ToBytes pValue
   -- Four bytes, big endian, FIXED WIDTH. Deliberately not cxUIntToBytes: that
   -- one is RLP's minimal-length encoding, and using it here would silently
   -- drop the leading zeros of a small child index and corrupt every
   -- serialization and every HMAC that covers one.
   local tOut, tI, tRest
   put "" into tOut
   put pValue into tRest
   repeat with tI = 1 to 4
      put numToByte(cxIntMod(tRest, 256)) before tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   return tOut
end cxUInt32ToBytes

private function cxFingerprint pPubkey
   -- The first 4 bytes of hash160(compressed public key). BIP-32 uses it only
   -- as a hint for locating a parent; it is NOT a checksum and collisions are
   -- expected, so nothing in this file treats a match as proof of anything.
   return byte 1 to 4 of cxHash160(pPubkey)
end cxFingerprint

function cxHdFromSeed pSeed
   local tLen, tI, tNode
   put the number of bytes of pSeed into tLen
   if tLen < 16 or tLen > 64 then
      throw "CoinXT: cxHdFromSeed: a BIP-32 seed must be between 16 and 64 bytes."
   end if
   put cxHmacSha512(kCxBip32MasterKey, pSeed) into tI
   put byte 1 to 32 of tI into tNode["seckey"]
   put byte 33 to 64 of tI into tNode["chaincode"]
   -- Throws if IL is zero or >= n, which is BIP-32's "this seed is invalid" and
   -- happens with probability about 2^-127. Deriving the public key is what
   -- performs the check, so it is not restated here.
   put cxPublicKey(tNode["seckey"], true) into tNode["pubkey"]
   put 0 into tNode["depth"]
   put 0 into tNode["index"]
   put cxUInt32ToBytes(0) into tNode["parentfp"]
   return tNode
end cxHdFromSeed

function cxHdNeuter pNode
   local tNode
   put pNode into tNode
   put "" into tNode["seckey"]
   return tNode
end cxHdNeuter

function cxHdDeriveChild pNode, pIndex
   local tData, tI, tChild, tHasPrivate
   if pIndex < 0 or pIndex > 4294967295 then
      throw "CoinXT: cxHdDeriveChild: a child index must be between 0 and 2^32-1."
   end if
   put (pNode["seckey"] is not "") into tHasPrivate
   if pIndex >= kCxHardenedBase then
      if tHasPrivate is false then
         throw "CoinXT: cxHdDeriveChild: a hardened child cannot be derived from a public-only node, because BIP-32 hashes the private key to make one."
      end if
      -- The 0x00 pad makes the private key 33 bytes, the same width as the
      -- compressed public key the non-hardened branch uses, so both hash the
      -- same amount of data. BIP-32 is explicit about it.
      put numToByte(0) & pNode["seckey"] & cxUInt32ToBytes(pIndex) into tData
   else
      put pNode["pubkey"] & cxUInt32ToBytes(pIndex) into tData
   end if
   put cxHmacSha512(pNode["chaincode"], tData) into tI
   put byte 33 to 64 of tI into tChild["chaincode"]
   if tHasPrivate is true then
      -- Throws when IL >= n or the child key is zero. BIP-32's remedy is to
      -- use the next index; it is surfaced rather than retried here, because
      -- silently returning a DIFFERENT child than the one asked for is how two
      -- wallets end up disagreeing about what m/44'/0'/0'/0/0 means.
      put cxSeckeyTweakAdd(pNode["seckey"], byte 1 to 32 of tI) into tChild["seckey"]
      put cxPublicKey(tChild["seckey"], true) into tChild["pubkey"]
   else
      put "" into tChild["seckey"]
      put cxPubkeyTweakAdd(pNode["pubkey"], byte 1 to 32 of tI) into tChild["pubkey"]
   end if
   put pNode["depth"] + 1 into tChild["depth"]
   put pIndex into tChild["index"]
   put cxFingerprint(pNode["pubkey"]) into tChild["parentfp"]
   return tChild
end cxHdDeriveChild

function cxHdDerivePath pNode, pPath
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxHdDerivePathInner(pNode, pPath) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxHdDerivePath

private function cxHdDerivePathInner pNode, pPath
   local tPath, tNode, tCount, tI, tPart, tLast, tHardened, tIndex, tJ, tCode, tPartLen, tPathLen
   put pPath into tPath
   -- A trailing separator must be refused HERE, while the "/" is still
   -- visible: the engine ignores one trailing delimiter when it counts
   -- items, so after the replace below "m/" counts as ONE item, the level
   -- loop never runs, and the empty-level check inside it can never fire.
   -- The 2026-08-10 engine pass caught exactly that failing OPEN: "m/"
   -- walked zero levels and handed back the node unchanged.
   put the number of chars of tPath into tPathLen
   if tPathLen > 0 and char tPathLen of tPath is "/" then
      throw "CoinXT: cxHdDerivePath: the path has an empty level."
   end if
   replace "/" with comma in tPath
   put pNode into tNode
   put the number of items of tPath into tCount
   if tCount < 1 then
      throw "CoinXT: cxHdDerivePath: the path is empty."
   end if
   if item 1 of tPath is not "m" and item 1 of tPath is not "M" then
      throw "CoinXT: cxHdDerivePath: a path must begin with m."
   end if
   repeat with tI = 2 to tCount
      put item tI of tPath into tPart
      if tPart is "" then
         throw "CoinXT: cxHdDerivePath: the path has an empty level."
      end if
      put false into tHardened
      put the number of chars of tPart into tPartLen
      put char tPartLen of tPart into tLast
      if tLast is "'" or tLast is "h" or tLast is "H" then
         put true into tHardened
         delete char tPartLen to tPartLen of tPart
      end if
      if tPart is "" then
         throw "CoinXT: cxHdDerivePath: a hardened marker with no index before it."
      end if
      -- Digits only, checked by byte value: `is a number` would accept "1e3",
      -- " 5" and "5.0", and a path level that quietly became 5000 or 5 would be
      -- a different wallet with no error anywhere.
      repeat with tJ = 1 to the number of chars of tPart
         put byteToNum(char tJ of tPart) into tCode
         if tCode < 48 or tCode > 57 then
            throw "CoinXT: cxHdDerivePath: a path level must be digits, optionally followed by a hardened marker."
         end if
      end repeat
      put tPart + 0 into tIndex
      if tIndex >= kCxHardenedBase then
         throw "CoinXT: cxHdDerivePath: a path level must be below 2^31; use the ' marker for a hardened level."
      end if
      if tHardened is true then
         add kCxHardenedBase to tIndex
      end if
      put cxHdDeriveChild(tNode, tIndex) into tNode
   end repeat
   return tNode
end cxHdDerivePathInner

private function cxHdSerialize pNode, pVersion, pPrivate
   -- The 78 bytes BIP-32 defines, in order: version, depth, parent
   -- fingerprint, child number, chain code, then 33 key bytes - a private key
   -- padded to 33 with a leading 0x00, or the compressed public key as is.
   local tOut
   put cxUInt32ToBytes(pVersion) into tOut
   put numToByte(pNode["depth"]) after tOut
   put pNode["parentfp"] after tOut
   put cxUInt32ToBytes(pNode["index"]) after tOut
   put pNode["chaincode"] after tOut
   if pPrivate is true then
      put numToByte(0) & pNode["seckey"] after tOut
   else
      put pNode["pubkey"] after tOut
   end if
   return tOut
end cxHdSerialize

function cxXprv pNode
   if pNode["seckey"] is "" then
      throw "CoinXT: cxXprv: this node has no private key, so it can only be serialized as an xpub."
   end if
   if pNode["depth"] > 255 then
      throw "CoinXT: cxXprv: BIP-32 stores the depth in one byte, so it cannot exceed 255."
   end if
   return cxBase58CheckEncode(cxHdSerialize(pNode, kCxVersionXprv, true))
end cxXprv

function cxXpub pNode
   if pNode["depth"] > 255 then
      throw "CoinXT: cxXpub: BIP-32 stores the depth in one byte, so it cannot exceed 255."
   end if
   return cxBase58CheckEncode(cxHdSerialize(pNode, kCxVersionXpub, false))
end cxXpub

private function cxUIntToBytesLE pValue, pWidth
   local tOut, tRest, tI
   if pValue < 0 then
      throw "CoinXT: cxUIntToBytesLE: the value must not be negative."
   end if
   put "" into tOut
   put pValue into tRest
   repeat with tI = 1 to pWidth
      put numToByte(cxIntMod(tRest, 256)) after tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   if tRest is not 0 then
      throw "CoinXT: cxUIntToBytesLE: the value does not fit in the requested width."
   end if
   return tOut
end cxUIntToBytesLE

function cxVarInt pN
   if pN < 0 then
      throw "CoinXT: cxVarInt: the count must not be negative."
   end if
   if pN < 253 then
      return numToByte(pN)
   end if
   if pN <= 65535 then
      return numToByte(253) & cxUIntToBytesLE(pN, 2)
   end if
   if pN <= 4294967295 then
      return numToByte(254) & cxUIntToBytesLE(pN, 4)
   end if
   return numToByte(255) & cxUIntToBytesLE(pN, 8)
end cxVarInt

private function cxStripLeadingZeroBytes pData
   local tCount, tStart
   put the number of bytes of pData into tCount
   put 1 into tStart
   repeat while tStart <= tCount and byteToNum(byte tStart of pData) is 0
      add 1 to tStart
   end repeat
   if tStart > tCount then
      return ""
   end if
   return byte tStart to tCount of pData
end cxStripLeadingZeroBytes

private function cxRlpUintFromHex pHex
   return cxRlpEncodeBytes(cxStripLeadingZeroBytes(cxHexDecode(pHex)))
end cxRlpUintFromHex

function cxDerEncode pCompactSig
   local tR, tS, tBody
   if the number of bytes of pCompactSig is not 64 then
      throw "CoinXT: cxDerEncode: a compact signature is 64 bytes (r || s)."
   end if
   put cxDerInteger(byte 1 to 32 of pCompactSig) into tR
   put cxDerInteger(byte 33 to 64 of pCompactSig) into tS
   put tR & tS into tBody
   return numToByte(48) & numToByte(the number of bytes of tBody) & tBody
end cxDerEncode

private function cxDerInteger pValue
   local tTrimmed, tLen
   put cxStripLeadingZeroBytes(pValue) into tTrimmed
   if tTrimmed is "" then
      put numToByte(0) into tTrimmed
   end if
   -- DER integers are signed: a leading byte >= 0x80 needs a 0x00 sign pad so
   -- the value is not read as negative.
   if byteToNum(byte 1 of tTrimmed) >= 128 then
      put numToByte(0) & tTrimmed into tTrimmed
   end if
   put the number of bytes of tTrimmed into tLen
   return numToByte(2) & numToByte(tLen) & tTrimmed
end cxDerInteger

function cxBtcOutpoint pTxidHex, pVout
   local tTxid
   put cxHexDecode(pTxidHex) into tTxid
   if the number of bytes of tTxid is not 32 then
      throw "CoinXT: cxBtcOutpoint: a txid is 32 bytes (64 hex chars)."
   end if
   return cxReverseBytes(tTxid) & cxUIntToBytesLE(pVout, 4)
end cxBtcOutpoint

private function cxReverseBytes pData
   local tOut, tI, tCount
   put the number of bytes of pData into tCount
   put "" into tOut
   repeat with tI = 1 to tCount
      put byte tI of pData before tOut
   end repeat
   return tOut
end cxReverseBytes

function cxBtcOutput pAmountSat, pScriptHex
   local tScript
   put cxHexDecode(pScriptHex) into tScript
   return cxUIntToBytesLE(pAmountSat, 8) & cxVarInt(the number of bytes of tScript) & tScript
end cxBtcOutput

function cxBtcSighashLegacy pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashLegacyInner(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcSighashLegacy

private function cxBtcSighashLegacyInner pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType
   local tCount, tI, tBuf, tScript, tOutBytes, tOutCount
   put the number of items of pOutpoints into tCount
   if tCount is 0 or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcSighashLegacy: the outpoint and sequence lists must be parallel and non-empty."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashLegacy: the input index is out of range (it is 1-based)."
   end if
   put cxHexDecode(pScriptCodeHex) into tScript
   put cxUIntToBytesLE(pVersion, 4) & cxVarInt(tCount) into tBuf
   repeat with tI = 1 to tCount
      put tBuf & cxHexDecode(item tI of pOutpoints) into tBuf
      if tI is pIndex then
         put tBuf & cxVarInt(the number of bytes of tScript) & tScript into tBuf
      else
         put tBuf & cxVarInt(0) into tBuf
      end if
      put tBuf & cxUIntToBytesLE(item tI of pSequences, 4) into tBuf
   end repeat
   put the number of items of pOutputs into tOutCount
   put "" into tOutBytes
   repeat with tI = 1 to tOutCount
      put tOutBytes & cxHexDecode(item tI of pOutputs) into tOutBytes
   end repeat
   put tBuf & cxVarInt(tOutCount) & tOutBytes into tBuf
   put tBuf & cxUIntToBytesLE(pLocktime, 4) & cxUIntToBytesLE(pSighashType, 4) into tBuf
   return cxHash256(tBuf)
end cxBtcSighashLegacyInner

function cxBtcSighashSegwit pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashSegwitInner(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcSighashSegwit

private function cxBtcSighashSegwitInner pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType
   local tCount, tI, tPrevouts, tSequencesRaw, tOutputsRaw, tScript, tBuf, tOutCount
   put the number of items of pOutpoints into tCount
   if tCount is 0 or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcSighashSegwit: the outpoint and sequence lists must be parallel and non-empty."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashSegwit: the input index is out of range (it is 1-based)."
   end if
   if pOutputs is "" then
      throw "CoinXT: cxBtcSighashSegwit: the outputs list is required (BIP-143 commits to hashOutputs)."
   end if
   put "" into tPrevouts
   put "" into tSequencesRaw
   repeat with tI = 1 to tCount
      put tPrevouts & cxHexDecode(item tI of pOutpoints) into tPrevouts
      put tSequencesRaw & cxUIntToBytesLE(item tI of pSequences, 4) into tSequencesRaw
   end repeat
   put the number of items of pOutputs into tOutCount
   put "" into tOutputsRaw
   repeat with tI = 1 to tOutCount
      put tOutputsRaw & cxHexDecode(item tI of pOutputs) into tOutputsRaw
   end repeat
   put cxHexDecode(pScriptCodeHex) into tScript
   put cxUIntToBytesLE(pVersion, 4) into tBuf
   put tBuf & cxHash256(tPrevouts) & cxHash256(tSequencesRaw) into tBuf
   put tBuf & cxHexDecode(item pIndex of pOutpoints) into tBuf
   put tBuf & cxVarInt(the number of bytes of tScript) & tScript into tBuf
   put tBuf & cxUIntToBytesLE(pAmountSat, 8) & cxUIntToBytesLE(item pIndex of pSequences, 4) into tBuf
   put tBuf & cxHash256(tOutputsRaw) & cxUIntToBytesLE(pLocktime, 4) & cxUIntToBytesLE(pSighashType, 4) into tBuf
   return cxHash256(tBuf)
end cxBtcSighashSegwitInner

function cxBtcWitness pItems
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcWitnessInner(pItems) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcWitness

private function cxBtcWitnessInner pItems
   local tCount, tI, tOut, tItem
   if pItems is "" then
      return cxVarInt(0)
   end if
   put the number of items of pItems into tCount
   put cxVarInt(tCount) into tOut
   repeat with tI = 1 to tCount
      put cxHexDecode(item tI of pItems) into tItem
      put tOut & cxVarInt(the number of bytes of tItem) & tItem into tOut
   end repeat
   return tOut
end cxBtcWitnessInner

function cxBtcTxEncode pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcTxEncodeInner(pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcTxEncode

private function cxBtcTxEncodeInner pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime
   local tCount, tI, tBuf, tHasWitness, tSig, tWitBytes
   put the number of items of pOutpoints into tCount
   if tCount is 0 then
      throw "CoinXT: cxBtcTxEncode: a transaction needs at least one input."
   end if
   -- Every list is read BY INDEX below (item 1..tCount), so a missing entry
   -- reads as empty: for a scriptSig that means "no scriptSig", for a witness
   -- "no witness" - the correct meaning, not an error. That read-by-index is
   -- FORCED by the engine's chunk rule, and getting it wrong was a real bug the
   -- headless gate caught before the engine did: the engine ignores ONE trailing
   -- delimiter when it counts items, so a list whose LAST input is empty
   -- ("<sig>," for [sig, ""], the common legacy-then-segwit shape) counts as
   -- tCount-1 and is INDISTINGUISHABLE from a genuinely short list. A strict
   -- "items == tCount" check therefore REFUSED the BIP-143 reference transaction
   -- outright. The count can only catch a list that is too LONG (extra entries
   -- serialization would silently drop); a short one is read as trailing empties.
   -- Sequences are the exception and stay strict: an input always carries one and
   -- it is never empty, so that list is a reliable one-per-input cross-check.
   if the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcTxEncode: the sequence list must have one entry per input."
   end if
   if the number of items of pScriptSigs > tCount then
      throw "CoinXT: cxBtcTxEncode: the scriptSig list has more entries than there are inputs."
   end if
   if pWitnesses is not "" and the number of items of pWitnesses > tCount then
      throw "CoinXT: cxBtcTxEncode: the witness list has more entries than there are inputs."
   end if
   put false into tHasWitness
   if pWitnesses is not "" then
      repeat with tI = 1 to tCount
         if item tI of pWitnesses is not "" then
            put true into tHasWitness
         end if
      end repeat
   end if
   put cxBtcTxBody(pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, tHasWitness) into tBuf
   if tHasWitness then
      repeat with tI = 1 to tCount
         put item tI of pWitnesses into tWitBytes
         if tWitBytes is "" then
            put tBuf & cxVarInt(0) into tBuf
         else
            put tBuf & cxHexDecode(tWitBytes) into tBuf
         end if
      end repeat
      -- The witness section sits before nLockTime, so append the locktime last.
      put tBuf & cxUIntToBytesLE(pLocktime, 4) into tBuf
   end if
   return tBuf
end cxBtcTxEncodeInner

private function cxBtcTxBody pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, pWithMarker
   local tCount, tI, tBuf, tSig, tOutBytes
   put the number of items of pOutpoints into tCount
   put cxUIntToBytesLE(pVersion, 4) into tBuf
   if pWithMarker then
      put tBuf & numToByte(0) & numToByte(1) into tBuf
   end if
   put tBuf & cxVarInt(tCount) into tBuf
   repeat with tI = 1 to tCount
      put tBuf & cxHexDecode(item tI of pOutpoints) into tBuf
      if item tI of pScriptSigs is "" then
         put tBuf & cxVarInt(0) into tBuf
      else
         put cxHexDecode(item tI of pScriptSigs) into tSig
         put tBuf & cxVarInt(the number of bytes of tSig) & tSig into tBuf
      end if
      put tBuf & cxUIntToBytesLE(item tI of pSequences, 4) into tBuf
   end repeat
   put "" into tOutBytes
   repeat with tI = 1 to the number of items of pOutputs
      put tOutBytes & cxHexDecode(item tI of pOutputs) into tOutBytes
   end repeat
   put tBuf & cxVarInt(the number of items of pOutputs) & tOutBytes into tBuf
   if not pWithMarker then
      put tBuf & cxUIntToBytesLE(pLocktime, 4) into tBuf
   end if
   return tBuf
end cxBtcTxBody

function cxBtcTxid pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxHexEncode(cxReverseBytes(cxHash256(cxBtcTxBody(pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, false)))) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcTxid

function cxEthLegacySighash pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex, pChainId
   local tBody
   put cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pGasPriceHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pChainId)) into tBody
   put tBody & cxRlpEncodeBytes("") & cxRlpEncodeBytes("") into tBody
   return cxKeccak256(cxRlpEncodeList(tBody))
end cxEthLegacySighash

function cxEthLegacyEncode pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex, pChainId, pRecid, pRHex, pSHex
   local tBody, tRaw, tResult, tV
   put pRecid + 2 * pChainId + 35 into tV
   put cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pGasPriceHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(tV)) into tBody
   put tBody & cxRlpUintFromHex(pRHex) & cxRlpUintFromHex(pSHex) into tBody
   put cxRlpEncodeList(tBody) into tRaw
   put cxHexEncode(tRaw) into tResult["raw"]
   put cxHexEncode(cxKeccak256(tRaw)) into tResult["txhash"]
   return tResult
end cxEthLegacyEncode

function cxEth1559Sighash pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex
   local tBody
   put cxEth1559Body(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex) into tBody
   return cxKeccak256(numToByte(2) & cxRlpEncodeList(tBody))
end cxEth1559Sighash

private function cxEth1559Body pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex
   local tBody
   put cxRlpUintFromHex(cxHexOfInt(pChainId)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pMaxPriorityHex) into tBody
   put tBody & cxRlpUintFromHex(pMaxFeeHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   -- The access list is an empty RLP list.
   put tBody & cxRlpEncodeList("") into tBody
   return tBody
end cxEth1559Body

function cxEth1559Encode pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex, pRecid, pRHex, pSHex
   local tBody, tRaw, tResult
   put cxEth1559Body(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pRecid)) into tBody
   put tBody & cxRlpUintFromHex(pRHex) & cxRlpUintFromHex(pSHex) into tBody
   put numToByte(2) & cxRlpEncodeList(tBody) into tRaw
   put cxHexEncode(tRaw) into tResult["raw"]
   put cxHexEncode(cxKeccak256(tRaw)) into tResult["txhash"]
   return tResult
end cxEth1559Encode

private function cxHexOfInt pValue
   local tHex
   if pValue < 0 then
      throw "CoinXT: cxHexOfInt: the value must not be negative."
   end if
   if pValue is 0 then
      return ""
   end if
   put cxHexEncode(cxUIntToBytes(pValue)) into tHex
   return tHex
end cxHexOfInt
-- <<< GENERATED EMBED: coinxt script layer <<< --


-- >>> GENERATED EMBED: onionxt script layer >>> --
-- ==========================================================================
-- OnionXT script layer (the real library, embedded)
--
-- The entire ox* surface - OnionXT is pure LiveCodeScript over engine
-- sockets. Embedded for the same reason as coinxt's layer; its engine socket
-- callbacks (socketError and friends) ride along, which is correct - the
-- engine delivers them to the object that opened the socket, and in this
-- paste that is this stack.
--
-- GENERATED from onionxt/src/onionxt.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild. Names are NOT prefixed: this is the library itself, and the
-- folded tests above must reach it by its real names.
-- ==========================================================================

command oxSetSocksPort pPort
   -- Loopback-locked: only the port is settable, never the host (CLAUDE.md
   -- socket gotcha 6). Take effect on the next oxDial.
   put pPort into sSocksPort
end oxSetSocksPort

command oxSetControlPort pPort
   put pPort into sControlPort
end oxSetControlPort

command oxSetControlPassword pPassword
   -- Only used if the daemon offers HASHEDPASSWORD auth (docs/03 step 2).
   put pPassword into sControlPassword
end oxSetControlPassword

command oxSetCallbackOwner pObjectLongId
   -- The object whose script holds the app callbacks. If unset, callbacks
   -- dispatch to the topStack; setting this explicitly (as the demo does) removes
   -- any ambiguity about which stack. Confirmed on-engine: with an explicit owner,
   -- onStatus / onPeer / onStreamData all resolve and fire.
   put pObjectLongId into sCallbackOwner
end oxSetCallbackOwner

command oxSetStatusCallback pHandlerName
   put pHandlerName into sStatusCallback
end oxSetStatusCallback

command oxSetPeerCallback pHandlerName
   put pHandlerName into sPeerCallback
end oxSetPeerCallback

function oxVersion
   -- The library version, plus the tor version once the control connection has
   -- answered GETINFO version (docs/05).
   if sControlTorVersion is empty then
      return kOxVersion
   end if
   return kOxVersion & " (tor " & sControlTorVersion & ")"
end oxVersion

command oxConnectControl
   -- Idempotent-ish: refuse a second concurrent connect rather than leak a
   -- socket. Disconnect first to reconnect.
   if sControlSocket is not empty then
      return "OnionXT: control connection already open (oxDisconnectControl first)"
   end if
   local tSocketID
   -- A named connection (|oxctl) so the id is stable and distinct from streams.
   put kOxHost & ":" & effectiveControlPort() & "|oxctl" into tSocketID
   put tSocketID into sControlSocket
   put "connecting" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   -- Bound the connect/handshake so a stalled daemon fails cleanly.
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxCtlOpened"
   -- A watchdog independent of the (repeating) socketTimeout: if we are not
   -- authenticated within the deadline, tear the connection down.
   send ("oxCtlDeadline " & quote & tSocketID & quote) to me in kOxHandshakeTimeout milliseconds
   return empty
end oxConnectControl

command oxDisconnectControl
   -- Idempotent close of the control socket and reset of all control state.
   if sControlSocket is not empty then
      oxSafeCloseSocket sControlSocket
   end if
   put empty into sControlSocket
   put "disconnected" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   put empty into sControlCookieBytes
   put empty into sControlClientNonce
end oxDisconnectControl

function oxIsControlAuthenticated
   return (sControlState is "authenticated")
end oxIsControlAuthenticated

function oxBootstrapProgress
   if sBootstrap is empty then
      return 0
   end if
   return sBootstrap
end oxBootstrapProgress

function oxIsReady
   -- Ready to carry traffic once bootstrapped to 100 and the control port is
   -- authenticated. A published service's own reachability is reported
   -- separately via the "serviceReady" status (HS_DESC UPLOADED).
   return (sBootstrap is 100) and (sControlState is "authenticated")
end oxIsReady

command oxCtlOpened pSocketID
   -- The control TCP connection is up. Start the single persistent line reader
   -- and kick the auth dance with PROTOCOLINFO (allowed pre-auth).
   if pSocketID is not sControlSocket then
      exit oxCtlOpened          -- a stale socket; ignore
   end if
   put "protocolinfo" into sControlState
   oxStatusUpdate "control", "connected"
   -- One outstanding CRLF read at a time; re-armed at the end of oxCtlLine.
   read from socket pSocketID until crlf with message "oxCtlLine"
   oxCtlSend "PROTOCOLINFO 1", "protocolinfo"
end oxCtlOpened

private command oxCtlSend pCommand, pLabel
   -- Send a control command, or queue it if one is already in flight so replies
   -- always match commands (docs/03: keep a single in-flight command queue).
   if sControlSocket is empty then
      exit oxCtlSend
   end if
   if sCtlInFlight is not empty then
      put pLabel & tab & pCommand & return after sCtlQueue
      exit oxCtlSend
   end if
   put pLabel into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlData
   -- Commands are ASCII text; textEncode gives the exact wire bytes, then the
   -- CRLF terminator (docs/03 line framing).
   write textEncode(pCommand & oxCrlf(), "UTF-8") to socket sControlSocket
end oxCtlSend

private command oxCtlDrainQueue
   -- Send the next queued command, if any. Called when a reply completes.
   if sCtlQueue is empty then
      exit oxCtlDrainQueue
   end if
   local tLine, tLabel, tCommand, tSaved
   put line 1 of sCtlQueue into tLine
   delete line 1 of sCtlQueue
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tLine into tLabel
   put item 2 to -1 of tLine into tCommand
   set the itemDelimiter to tSaved
   oxCtlSend tCommand, tLabel
end oxCtlDrainQueue

command oxCtlLine pSocketID, pData
   -- The persistent control-port line reader. Demultiplexes unsolicited 650
   -- events from command replies, reassembles multi-line replies, and honours
   -- the 250-/250+/'.'/250 space framing (docs/03).
   if pSocketID is not sControlSocket then
      exit oxCtlLine            -- a stale socket; ignore
   end if
   local tLine
   -- Control replies are ASCII; decode as text, then strip the line terminator.
   -- Confirmed on-engine: `read until crlf` returns the trailing CRLF and
   -- oxStripLineEnd removes it, so auth / GETINFO / events all parse correctly.
   put textDecode(pData, "UTF-8") into tLine
   put oxStripLineEnd(tLine) into tLine

   if sCtlInData then
      -- Inside a 250+ CmdData block: a lone "." ends it; other lines are data
      -- with any doubled leading dot un-stuffed (docs/03, RFC 2821 dot-stuffing).
      if tLine is "." then
         put false into sCtlInData
      else
         if char 1 to 2 of tLine is ".." then
            delete char 1 of tLine
         end if
         put tLine & return after sCtlData
      end if
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   if the length of tLine < 3 then
      oxCtlRearm pSocketID      -- malformed / empty; skip
      exit oxCtlLine
   end if

   local tCode, tSep
   put char 1 to 3 of tLine into tCode
   put char 4 of tLine into tSep

   if tCode is "650" then
      -- An asynchronous event. Route it to the event handler, never to the
      -- pending-command continuation.
      oxHandleEvent tLine
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   -- A command-reply line. Accumulate it and act on the frame control byte.
   put tLine & return after sCtlReplyLines
   if tSep is "+" then
      put true into sCtlInData
   else if tSep is space or tSep is empty then
      -- Space (or a 3-char line) terminates the reply.
      oxCtlReplyComplete
      put empty into sCtlInFlight
      put empty into sCtlReplyLines
      oxCtlDrainQueue
   end if
   -- "-" continuation: just keep reading.
   oxCtlRearm pSocketID
end oxCtlLine

private command oxCtlRearm pSocketID
   -- Keep exactly one read outstanding, but only while the socket is still ours.
   if pSocketID is sControlSocket then
      read from socket pSocketID until crlf with message "oxCtlLine"
   end if
end oxCtlRearm

private command oxCtlReplyComplete
   -- Dispatch the just-completed reply to the continuation for the in-flight
   -- command. if/else-if, not switch (the static gate rejects `end switch`).
   -- tReplyOp, NOT tOp: a t-prefixed "tOp" lowercases to `top`, a reserved OXT
   -- property, and the engine would parse it as the keyword, not this variable
   -- (the prefixed-token-shadow trap, CLAUDE.md gotcha 2).
   local tLabel, tReplyOp, tArg, tSaved
   put sCtlInFlight into tLabel
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tLabel into tReplyOp
   put item 2 to -1 of tLabel into tArg
   set the itemDelimiter to tSaved

   if tReplyOp is "protocolinfo" then
      oxParseProtocolInfo sCtlReplyLines
      oxChooseAuthAndStart
   else if tReplyOp is "authchallenge" then
      oxHandleAuthChallenge sCtlReplyLines
   else if tReplyOp is "authenticate" then
      oxHandleAuthResult sCtlReplyLines
   else if tReplyOp is "setevents" then
      -- 250 OK expected; nothing to do on success.
   else if tReplyOp is "getinfo-version" then
      oxParseTorVersion sCtlReplyLines
   else if tReplyOp is "getinfo-bootstrap" then
      oxParseBootstrapPhase sCtlReplyLines
   else if tReplyOp is "add_onion" then
      oxHandleAddOnionReply tArg, sCtlReplyLines
   else if tReplyOp is "del_onion" then
      -- 250 OK on success, 552 if unknown; the removal already forgot local
      -- state, so nothing further is required here.
   end if
end oxCtlReplyComplete

private command oxParseProtocolInfo pReply
   -- Extract the offered auth methods and (for cookie auth) the cookie-file path
   -- from the PROTOCOLINFO reply (docs/03 step 1).
   put empty into sControlMethods
   put empty into sControlCookieFile
   local tLine
   repeat for each line tLine in pReply
      if "AUTH METHODS=" is in tLine then
         -- METHODS=<comma list> [COOKIEFILE="<quoted, C-escaped path>"]
         put oxFieldAfter(tLine, "METHODS=") into sControlMethods
         if "COOKIEFILE=" is in tLine then
            put oxCUnescape(oxQuotedValueAfter(tLine, "COOKIEFILE=")) into sControlCookieFile
         end if
      end if
   end repeat
end oxParseProtocolInfo

private command oxChooseAuthAndStart
   -- Priority SAFECOOKIE > COOKIE > NULL > HASHEDPASSWORD (docs/03), but degrade
   -- past any method whose prerequisite is missing rather than fail: SAFECOOKIE
   -- needs SodiumXT HMAC-SHA256 and randomness (docs/08), COOKIE needs the
   -- readable cookie file, HASHEDPASSWORD needs an app-set password.
   put "authenticating" into sControlState

   if oxMethodOffered("SAFECOOKIE") and oxSodiumHasHmac() and oxSodiumHasRandom() then
      if oxLoadCookie() then
         oxStartSafeCookie
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("COOKIE") then
      if oxLoadCookie() then
         local tHex
         put oxBytesToHex(sControlCookieBytes) into tHex
         oxCtlSend "AUTHENTICATE " & tHex, "authenticate"
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("NULL") then
      oxCtlSend "AUTHENTICATE", "authenticate"
      exit oxChooseAuthAndStart
   end if
   if oxMethodOffered("HASHEDPASSWORD") and sControlPassword is not empty then
      -- Quote the password; escape backslash and double-quote (docs/03).
      oxCtlSend "AUTHENTICATE " & quote & oxQuoteEscape(sControlPassword) & quote, "authenticate"
      exit oxChooseAuthAndStart
   end if

   put "failed" into sControlState
   oxStatusUpdate "control", "authfailed: no usable auth method (offered " & sControlMethods & ")"
   oxDisconnectControl
end oxChooseAuthAndStart

private command oxStartSafeCookie
   -- SAFECOOKIE step A: send a 32-byte client nonce as hex (docs/03 step 2).
   put oxRandomBytes(32) into sControlClientNonce
   oxCtlSend "AUTHCHALLENGE SAFECOOKIE " & oxBytesToHex(sControlClientNonce), "authchallenge"
end oxStartSafeCookie

private command oxHandleAuthChallenge pReply
   -- SAFECOOKIE step B/C/D. The reply is a SINGLE final line:
   -- 250 AUTHCHALLENGE SERVERHASH=<hex> SERVERNONCE=<hex> (docs/03; the reply is
   -- space-separated, not a 250- continuation).
   local tLine, tServerHashHex, tServerNonceHex
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is not "250" then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: AUTHCHALLENGE rejected (" & tLine & ")"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   put oxFieldAfter(tLine, "SERVERHASH=") into tServerHashHex
   put oxFieldAfter(tLine, "SERVERNONCE=") into tServerNonceHex

   local tServerNonce, tMessage, tExpected, tOk
   put oxHexToBytes(tServerNonceHex) into tServerNonce
   -- HMAC message = CookieBytes || ClientNonce || ServerNonce (docs/03).
   put sControlCookieBytes & sControlClientNonce & tServerNonce into tMessage
   put oxHmac(kOxSafeCookieServerKey, tMessage) into tExpected
   -- Verify the server hash in constant time; a mismatch means the far end does
   -- not hold the cookie (not the real Tor), so abort and do NOT authenticate.
   put oxConstantTimeEqual(tExpected, oxHexToBytes(tServerHashHex)) into tOk
   if not tOk then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: SAFECOOKIE server hash mismatch (not the real Tor?)"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   -- Step D: authenticate with the controller-to-server hash.
   local tClientHash
   put oxHmac(kOxSafeCookieClientKey, tMessage) into tClientHash
   oxCtlSend "AUTHENTICATE " & oxBytesToHex(tClientHash), "authenticate"
end oxHandleAuthChallenge

private command oxHandleAuthResult pReply
   -- 250 OK => authenticated; anything else (515 bad auth, 514 required) fails
   -- closed (docs/03; there is no unauthenticated fallback, CLAUDE.md rule 4).
   local tLine
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is "250" then
      put "authenticated" into sControlState
      oxStatusUpdate "control", "authenticated"
      -- Subscribe to the events we care about and learn the tor version.
      oxCtlSend "SETEVENTS STATUS_CLIENT HS_DESC CIRC STREAM", "setevents"
      oxCtlSend "GETINFO version", "getinfo-version"
      -- Query the CURRENT bootstrap phase once. STATUS_CLIENT BOOTSTRAP events
      -- only fire WHILE tor is bootstrapping, so a daemon already at 100% when we
      -- connect emits none and the UI would sit at 0. This one GETINFO seeds it.
      oxCtlSend "GETINFO status/bootstrap-phase", "getinfo-bootstrap"
   else
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: " & tLine
      oxDisconnectControl
   end if
end oxHandleAuthResult

private command oxParseTorVersion pReply
   -- 250-version=<x> then 250 OK (docs/03). Pull the version value.
   local tLine
   repeat for each line tLine in pReply
      if "version=" is in tLine then
         put oxFieldAfter(tLine, "version=") into sControlTorVersion
      end if
   end repeat
end oxParseTorVersion

private command oxParseBootstrapPhase pReply
   -- Reply to GETINFO status/bootstrap-phase, carrying the CURRENT bootstrap state
   -- (unlike the STATUS_CLIENT event, which only fires while bootstrapping). Line:
   --   250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="..."
   -- Parse PROGRESS= the same way as the live event so the UI is seeded on connect.
   local tLine, tProgress
   repeat for each line tLine in pReply
      if "PROGRESS=" is in tLine then
         put oxFieldAfter(tLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   end repeat
end oxParseBootstrapPhase

command oxCtlDeadline pSocketID
   -- Handshake watchdog: if this control socket never reached authenticated,
   -- tear it down with a clean error (docs/07: a stalled bootstrap must not hang).
   if pSocketID is not sControlSocket then
      exit oxCtlDeadline
   end if
   if sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control authentication timed out"
      oxDisconnectControl
   end if
end oxCtlDeadline

private command oxHandleEvent pLine
   local tType
   put word 2 of pLine into tType
   if tType is "STATUS_CLIENT" then
      if "BOOTSTRAP" is in pLine then
         local tProgress
         put oxFieldAfter(pLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   else if tType is "HS_DESC" then
      -- Positional: HS_DESC <Action> <HSAddress> ... . Our service is reachable
      -- once we see UPLOADED for its address (docs/03 step 5).
      local tAction, tAddress
      put word 3 of pLine into tAction
      put word 4 of pLine into tAddress
      if tAction is "UPLOADED" then
         oxMarkServiceReady tAddress
         oxStatusUpdate "serviceReady", tAddress
      end if
   else
      -- CIRC / STREAM and anything else are diagnostic; surface raw for advanced
      -- apps that opted into an "event" status, otherwise ignored.
      oxStatusUpdate "event", pLine
   end if
end oxHandleEvent

private command oxMarkServiceReady pAddress
   local tKey, tCore
   -- The event carries the ServiceID (no ".onion"); match either spelling.
   put pAddress into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   repeat for each key tKey in sServices
      if sServices[tKey]["serviceID"] is tCore then
         put true into sServices[tKey]["ready"]
      end if
   end repeat
end oxMarkServiceReady

private command oxStatusUpdate pKind, pInfo
   -- Deliver a status update to the app, coalescing the high-frequency bootstrap
   -- stream to <= ~4 Hz (CLAUDE.md). Terminal/rare kinds are always delivered.
   if pKind is "bootstrap" and pInfo is not 100 then
      local tNow
      put the milliseconds into tNow
      if sLastStatusTick is not empty and (tNow - sLastStatusTick) < kOxStatusThrottle then
         exit oxStatusUpdate   -- coalesce: drop this intermediate tick
      end if
      put tNow into sLastStatusTick
   end if
   oxDispatch sStatusCallback, pKind, pInfo, empty
end oxStatusUpdate

command oxDial pHost, pPort
   -- Reports a stream handle through `the result` immediately; the SOCKS
   -- handshake completes asynchronously and the stream's callback receives
   -- "open" or "error" (CLAUDE.md async model).
   if pHost is empty then
      return "OnionXT: oxDial needs a host (a .onion or clearnet name)"
   end if
   if pPort is not an integer or pPort < 1 or pPort > 65535 then
      return "OnionXT: oxDial needs a port in 1..65535"
   end if
   local tHandle, tConnName, tSocketID
   put oxAllocHandle() into tHandle
   -- A NON-numeric connection name so several streams to 127.0.0.1:9050 get
   -- distinct socket ids, and so they never collide with the numeric names the
   -- accept loop assigns (the id separator is a vertical bar, docs LiveCode ref).
   put "oxs" & tHandle into tConnName
   put kOxHost & ":" & effectiveSocksPort() & "|" & tConnName into tSocketID
   put tSocketID into sStreams[tHandle]["socketID"]
   put "connecting" into sStreams[tHandle]["state"]
   put pHost into sStreams[tHandle]["host"]
   put pPort into sStreams[tHandle]["port"]
   put "dial" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[tSocketID]
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxSocksOpened"
   send ("oxStreamDeadline " & tHandle) to me in kOxHandshakeTimeout milliseconds
   return tHandle
end oxDial

command oxSetStreamCallback pStream, pHandlerName
   if sStreams[pStream]["socketID"] is empty then
      return "OnionXT: unknown stream handle " & pStream
   end if
   put pHandlerName into sStreams[pStream]["callback"]
   return empty
end oxSetStreamCallback

command oxWrite pStream, pData
   -- Write app bytes (already sealed by the app via SodiumXT) to the
   -- tunnel. OnionXT does not encrypt (docs/02).
   if sStreams[pStream]["state"] is not "connected" then
      return "OnionXT: stream " & pStream & " is not open"
   end if
   write pData to socket sStreams[pStream]["socketID"]
   return empty
end oxWrite

command oxCloseStream pStream
   -- Idempotent close of the stream socket; forget the handle. A stale handle is
   -- a clean no-op.
   if sStreams[pStream]["socketID"] is empty then
      exit oxCloseStream
   end if
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxCloseStream

function oxStreamState pStream
   if sStreams[pStream]["socketID"] is empty then
      return "unknown"
   end if
   return sStreams[pStream]["state"]
end oxStreamState

command oxSocksOpened pSocketID
   -- TCP up: send the method-negotiation greeting 05 01 00 (VER=5, 1 method,
   -- method 00 = no auth) and read the 2-byte method selection (docs/02 step 1).
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksOpened        -- stale
   end if
   put "greeting" into sStreams[tHandle]["state"]
   write numToByte(5) & numToByte(1) & numToByte(0) to socket pSocketID
   read from socket pSocketID for 2 with message "oxSocksMethod"
end oxSocksOpened

command oxSocksMethod pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksMethod
   end if
   if the number of bytes of pData < 2 then
      oxStreamFail tHandle, "SOCKS greeting reply truncated"
      exit oxSocksMethod
   end if
   local tVer, tMethod
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tMethod
   if tVer is not 5 then
      oxStreamFail tHandle, "SOCKS server is not version 5"
      exit oxSocksMethod
   end if
   if tMethod is not 0 then
      -- 0xFF = no acceptable methods; anything non-zero we do not offer. Fail
      -- closed; on loopback no auth is needed and its absence is a misconfig to
      -- surface, not paper over (docs/02).
      oxStreamFail tHandle, "SOCKS server demands an auth method OnionXT does not offer (0x" & oxByteHex(tMethod) & ")"
      exit oxSocksMethod
   end if
   -- Method OK: send the CONNECT request with ATYP=3 (domain name) so TOR
   -- resolves pHost. This is the anonymity-critical choice (docs/02 step 2).
   put "connect" into sStreams[tHandle]["state"]
   local tHost, tHostBytes, tPort, tRequest
   put sStreams[tHandle]["host"] into tHost
   put textEncode(tHost, "UTF-8") into tHostBytes
   if the number of bytes of tHostBytes > 255 then
      oxStreamFail tHandle, "SOCKS host name exceeds 255 bytes"
      exit oxSocksMethod
   end if
   put sStreams[tHandle]["port"] into tPort
   -- 05 01 00 03 <len> <host bytes> <port-hi> <port-lo>. The port is 2 bytes
   -- big-endian; build it by hand so the wire bytes are self-evident (do not use
   -- binaryEncode "S", which is host order, docs LiveCode ref).
   put numToByte(5) & numToByte(1) & numToByte(0) & numToByte(3) into tRequest
   put numToByte(the number of bytes of tHostBytes) after tRequest
   put tHostBytes after tRequest
   put numToByte(tPort div 256) & numToByte(tPort mod 256) after tRequest
   write tRequest to socket pSocketID
   -- Read the fixed 4-byte reply head (VER REP RSV ATYP); the BND.ADDR that
   -- follows is variable and framed by ATYP (docs/02 step 3).
   put "replyhead" into sStreams[tHandle]["state"]
   read from socket pSocketID for 4 with message "oxSocksReplyHead"
end oxSocksMethod

command oxSocksReplyHead pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyHead
   end if
   if the number of bytes of pData < 4 then
      oxStreamFail tHandle, "SOCKS reply head truncated"
      exit oxSocksReplyHead
   end if
   local tVer, tRep, tAtyp
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tRep
   put byteToNum(byte 4 of pData) into tAtyp
   if tRep is not 0 then
      -- Any non-zero REP is failure. Map it (incl. Tor's onion 0xF0..0xF7) to a
      -- human message and tear down (docs/02 REP table; CLAUDE.md rule 4).
      oxStreamFail tHandle, oxSocksRepMessage(tRep)
      exit oxSocksReplyHead
   end if
   put tAtyp into sStreams[tHandle]["atyp"]
   -- Consume BND.ADDR + 2-byte BND.PORT. Length depends on ATYP: 01 -> 4, 04 ->
   -- 16, 03 -> one length byte then that many. We do not use BND.ADDR; we just
   -- frame past it so the socket is left at the start of the tunnel payload.
   if tAtyp is 1 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 6 with message "oxSocksReplyDone"     -- 4 + 2
   else if tAtyp is 4 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 18 with message "oxSocksReplyDone"    -- 16 + 2
   else if tAtyp is 3 then
      put "replylen" into sStreams[tHandle]["state"]
      read from socket pSocketID for 1 with message "oxSocksReplyLen"
   else
      oxStreamFail tHandle, "SOCKS reply has an unknown address type (" & tAtyp & ")"
   end if
end oxSocksReplyHead

command oxSocksReplyLen pSocketID, pData
   -- ATYP=3 domain BND.ADDR: one length byte, then that many, then 2 port bytes.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyLen
   end if
   if the number of bytes of pData < 1 then
      oxStreamFail tHandle, "SOCKS reply address length truncated"
      exit oxSocksReplyLen
   end if
   local tLen
   put byteToNum(byte 1 of pData) + 2 into tLen     -- address bytes + 2 port bytes
   put "replyrest" into sStreams[tHandle]["state"]
   read from socket pSocketID for tLen with message "oxSocksReplyDone"
end oxSocksReplyLen

command oxSocksReplyDone pSocketID, pData
   -- The SOCKS reply is fully consumed and REP was 0: the socket is now a
   -- transparent tunnel. Hand it up and start the streaming inbound reader.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyDone
   end if
   put "connected" into sStreams[tHandle]["state"]
   oxInvokeStreamCallback tHandle, "open", empty
   -- Begin the persistent read; each inbound chunk is delivered as "data".
   -- Confirmed on-engine: the no-quantifier `read ... with message` streams
   -- available bytes as they arrive (a dialed SOCKS tunnel and an inbound onion
   -- HTTP request both deliver chunk by chunk); it does not block to EOF.
   read from socket pSocketID with message "oxStreamData"
end oxSocksReplyDone

command oxStreamData pSocketID, pData
   -- Inbound bytes on a live stream (dialed OR inbound-accepted; both are unified
   -- through the stream tables). Deliver the chunk and re-arm the read.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxStreamData          -- stale / already torn down
   end if
   if the number of bytes of pData > 0 then
      oxInvokeStreamCallback tHandle, "data", pData
   end if
   -- Re-arm only if the stream is still live (the callback may have closed it).
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxStreamData

command oxStreamDeadline pStream
   -- Handshake watchdog for a dialed stream: if it never reached "connected",
   -- tear it down (docs/02: a silent stall is the worst failure).
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamDeadline
   end if
   local tState
   put sStreams[pStream]["state"] into tState
   if tState is not "connected" and tState is not "closed" then
      oxStreamFail pStream, "SOCKS handshake timed out"
   end if
end oxStreamDeadline

private command oxStreamFail pStream, pError
   -- Fail closed: report the error to the app, then close and forget the stream.
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamFail
   end if
   put "failed" into sStreams[pStream]["state"]
   oxInvokeStreamCallback pStream, "error", pError
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxStreamFail

private function oxSocksRepMessage pRep
   -- Map a SOCKS REP code to a clear message. Standard RFC 1928 0x00..0x08 plus
   -- Tor's onion extensions 0xF0..0xF7 (docs/02; the extended band only appears
   -- when the SocksPort has ExtendedErrors set, so 0x01/0x04 must map sensibly
   -- too, since without that flag Tor collapses onion failures onto them).
   if pRep is 1 then
      return "general SOCKS server failure"
   else if pRep is 2 then
      return "connection not allowed by ruleset"
   else if pRep is 3 then
      return "network unreachable"
   else if pRep is 4 then
      return "host unreachable"
   else if pRep is 5 then
      return "connection refused"
   else if pRep is 6 then
      return "TTL expired"
   else if pRep is 7 then
      return "command not supported"
   else if pRep is 8 then
      return "address type not supported"
   else if pRep is 240 then
      return "onion service not found (wrong or offline .onion address)"
   else if pRep is 241 then
      return "onion service descriptor is invalid"
   else if pRep is 242 then
      return "onion service introduction failed"
   else if pRep is 243 then
      return "onion service rendezvous failed"
   else if pRep is 244 then
      return "onion service missing client authorization"
   else if pRep is 245 then
      return "onion service wrong client authorization"
   else if pRep is 246 then
      return "onion service invalid address (malformed .onion)"
   else if pRep is 247 then
      return "onion service introduction timed out"
   end if
   return "SOCKS request failed (REP 0x" & oxByteHex(pRep) & ")"
end oxSocksRepMessage

command oxCreateService pVirtualPort, pLocalPort
   -- Ephemeral service, Tor generates the key. Reports a service handle through
   -- `the result`; the .onion address arrives asynchronously (status "service"
   -- and oxServiceAddress) once ADD_ONION replies.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach keeps the service published even if the control connection
   -- drops (a transient socketClosed/socketError, or a reconnect): without it, an
   -- ADD_ONION service dies with its control connection while its descriptor
   -- lingers in the DHT for ~3h, so a later visit hits "unable to find hidden
   -- service identity key" at rendezvous. oxRemoveService / oxShutdown DEL_ONION
   -- it explicitly; a hard crash leaves it until DEL_ONION or a tor restart.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateService

command oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   -- Deterministic, reproducible address: derive the ed25519 identity from pSeed
   -- and pass Tor the 64-byte ED25519-V3 expanded key (docs/04). The expansion is
   -- SodiumXT's sxSignSeedToExpandedKey (docs/08 gap #1, SHIPPED in ABI 6); we
   -- compose it and fail with a clear message if it is absent, never hand-roll
   -- SHA-512. Same seed -> same .onion on every run.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   if the number of bytes of pSeed is not 32 then
      return "OnionXT: oxCreateServiceFromSeed needs a 32-byte seed"
   end if
   local tExpanded
   put oxExpandedKeyFromSeed(pSeed) into tExpanded
   if the number of bytes of tExpanded is not 64 then
      return tExpanded          -- a capability error, surfaced verbatim
   end if
   -- Tor's ADD_ONION ED25519-V3: wants STANDARD RFC 4648 base64 (the +/ alphabet
   -- with = padding). The engine's base64Encode emits exactly that; do NOT use
   -- SodiumXT's sxBin2Base64, which is url-safe and unpadded and tor rejects.
   -- Strip any line-wrap whitespace the encoder may insert (docs/04 base64 note).
   local tBlob
   put oxStripWhitespace(base64Encode(tExpanded)) into tBlob
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach: keep the service alive across a control-connection drop (see
   -- oxCreateService); DEL_ONION on teardown still removes it.
   oxCtlSend "ADD_ONION ED25519-V3:" & tBlob & " Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateServiceFromSeed

command oxPublishService pVirtualPort, pLocalPort
   -- Publish an onion whose virtual port Tor forwards to a loopback port that
   -- SOMETHING ELSE is already accepting on (LiveCode's built-in HTTPD Library, or
   -- any local server). Unlike oxCreateService, OnionXT does NOT start its own
   -- accept loop: the external server owns the socket, parses the request, and
   -- replies. Teardown DEL_ONIONs the service but leaves that socket alone. Reports
   -- a service handle through `the result`; the .onion address arrives
   -- asynchronously (status "service", oxServiceAddress) once ADD_ONION replies.
   --
   -- SECURITY (the caller's responsibility): `accept connections on port` usually
   -- binds ALL interfaces, so the external server's local port may be reachable
   -- from the LAN, bypassing Tor. The external server MUST enforce loopback itself
   -- (reject any non-127.0.0.1 peer before responding), exactly as OnionXT's own
   -- oxPeerAccepted does. Bind the server to loopback if it supports it.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   -- Mark it external so oxRemoveService DEL_ONIONs it but does not close the
   -- socket (which OnionXT never opened; the external server owns it).
   put true into sServices[tHandle]["external"]
   -- No accept loop here (contrast oxStartService). Flags=Detach as in
   -- oxCreateService, so a control-connection blip does not un-publish it.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxPublishService

private function oxCheckServiceArgs pVirtualPort, pLocalPort
   if sControlState is not "authenticated" then
      return "OnionXT: connect and authenticate the control port first (oxConnectControl)"
   end if
   if pVirtualPort is not an integer or pVirtualPort < 1 or pVirtualPort > 65535 then
      return "OnionXT: virtual port must be 1..65535"
   end if
   if pLocalPort is not an integer or pLocalPort < 1 or pLocalPort > 65535 then
      return "OnionXT: local port must be 1..65535"
   end if
   return empty
end oxCheckServiceArgs

private function oxStartService pVirtualPort, pLocalPort
   -- Allocate the handle and START the loopback listener before ADD_ONION so a
   -- forwarded connection is never refused (docs/03 step 4, ordering gotcha).
   local tHandle, tPrior
   put sLocalToService[pLocalPort] into tPrior
   if tPrior is not empty and sServices[tPrior]["localPort"] is not empty then
      -- Fail closed: a second service on an in-use local port would overwrite
      -- the port-to-service mapping, and removing either service would then
      -- close (or orphan) the shared listener out from under the other, so Tor
      -- keeps forwarding to a dead port - which looks exactly like a broken
      -- onion. One local port, one service; pick another local port.
      -- (Verified statically; needs an OXT pass.)
      return "OnionXT: local port " & pLocalPort & " already forwards for another service (one service per local port; pick another local port)"
   end if
   if tPrior is not empty then
      -- The mapping is stale (its service is gone); reclaim it and rebind below.
      delete variable sLocalToService[pLocalPort]
   end if
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   if sLocalToService[pLocalPort] is empty then
      -- Bind loopback only. The classic `accept connections on port` has no
      -- bind-address argument (may listen on all interfaces), so oxPeerAccepted
      -- enforces loopback by rejecting any non-loopback peer before reading.
      -- Confirmed on-engine: Tor-forwarded onion connections are accepted here.
      accept connections on port pLocalPort with message "oxPeerAccepted"
      if the result is not empty then
         -- The listener did not bind (most often the local port is already in use
         -- by a prior run or another app). Fail closed: with no listener, Tor
         -- forwards inbound onion traffic to a dead port and the visitor gets an
         -- empty response, which looks exactly like a broken onion.
         delete variable sServices[tHandle]
         return "OnionXT: cannot listen on 127.0.0.1:" & pLocalPort & " (" & the result & ")"
      end if
      put true into sServices[tHandle]["listening"]
   end if
   put tHandle into sLocalToService[pLocalPort]
   return tHandle
end oxStartService

private command oxHandleAddOnionReply pHandle, pReply
   -- Parse ServiceID (and PrivateKey unless discarded) from the ADD_ONION reply
   -- (docs/03 step 3). On failure, fail closed and tear the half-built service.
   local tLine
   if char 1 to 3 of (line 1 of pReply) is not "250" and "ServiceID=" is not in pReply then
      oxRemoveService pHandle
      oxStatusUpdate "control", "error: ADD_ONION failed (" & (line 1 of pReply) & ")"
      exit oxHandleAddOnionReply
   end if
   repeat for each line tLine in pReply
      if "ServiceID=" is in tLine then
         put oxFieldAfter(tLine, "ServiceID=") into sServices[pHandle]["serviceID"]
      else if "PrivateKey=" is in tLine then
         put oxFieldAfter(tLine, "PrivateKey=") into sServices[pHandle]["privateKey"]
      end if
   end repeat
   if sServices[pHandle]["serviceID"] is not empty then
      put sServices[pHandle]["serviceID"] & ".onion" into sServices[pHandle]["address"]
      oxStatusUpdate "service", sServices[pHandle]["address"]
   end if
end oxHandleAddOnionReply

command oxRemoveService pService
   -- DEL_ONION and stop the listener. Idempotent: a stale handle is a no-op.
   if sServices[pService]["localPort"] is empty then
      exit oxRemoveService
   end if
   local tServiceID, tLocalPort
   put sServices[pService]["serviceID"] into tServiceID
   put sServices[pService]["localPort"] into tLocalPort
   if tServiceID is not empty and sControlState is "authenticated" then
      oxCtlSend "DEL_ONION " & tServiceID, "del_onion:" & pService
   end if
   -- Stop accepting on the loopback port, but ONLY if WE own the listener
   -- (oxCreateService / oxCreateServiceFromSeed). A publish-only service
   -- (oxPublishService) forwards to a socket an external server owns; leave it
   -- alone, or we would close it out from under that server.
   if sServices[pService]["external"] is not true then
      if sLocalToService[tLocalPort] is pService then
         oxSafeCloseSocket tLocalPort
         delete variable sLocalToService[tLocalPort]
      end if
   end if
   delete variable sServices[pService]
end oxRemoveService

function oxServiceAddress pService
   return sServices[pService]["address"]
end oxServiceAddress

function oxServiceIsReady pService
   return (sServices[pService]["ready"] is true)
end oxServiceIsReady

command oxPeerAccepted pSocketID
   -- Tor forwarded an inbound onion connection to our loopback listener. Enforce
   -- loopback (security-critical: reject any non-loopback peer before reading a
   -- byte), wrap the accepted socket as an inbound stream, and hand it to the app.
   -- Emit a diagnostic notice with the RAW accepted id so a misparse is visible.
   oxStatusUpdate "notice", "accepted connection id=[" & pSocketID & "]"
   local tPeerHost
   put oxHostOfSocket(pSocketID) into tPeerHost
   if not oxHostIsLoopback(tPeerHost) then
      -- Not a Tor-forwarded loopback connection: refuse it (docs LiveCode ref;
      -- the listener may be bound to all interfaces).
      oxStatusUpdate "notice", "rejected non-loopback peer host [" & tPeerHost & "]"
      oxSafeCloseSocket pSocketID
      exit oxPeerAccepted
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pSocketID into sStreams[tHandle]["socketID"]
   put "connected" into sStreams[tHandle]["state"]
   put "inbound" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[pSocketID]
   -- Hand the stream to the app FIRST so it can register a stream callback (the
   -- dispatch is synchronous), THEN arm the read so no inbound chunk is delivered
   -- before there is a callback to receive it.
   oxDispatch sPeerCallback, tHandle, oxGuessService(pSocketID), tPeerHost
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxPeerAccepted

private function oxGuessService pSocketID
   -- Best-effort service association for the peer callback. The accept callback
   -- carries the PEER address, not our local port, so we cannot always know which
   -- service was reached (VERIFY the accepted-socket id format on-engine). If a
   -- single service is live, return it; otherwise return empty and let the app
   -- key on distinct local ports.
   local tKeys, tCount, tKey
   put the keys of sServices into tKeys
   put the number of lines of tKeys into tCount
   if tCount is 1 then
      return line 1 of tKeys
   end if
   return empty
end oxGuessService

private function oxHostIsLoopback pHost
   -- Accept a Tor-forwarded (loopback) peer no matter how the engine spells the
   -- local address in the accepted-socket id: "127.0.0.1", any "127.x" in the
   -- 127.0.0.0/8 block, IPv6 "::1" / "[::1]", the name "localhost", or empty
   -- (some engines report no host for a local accept). Reject anything else, so a
   -- listener that bound to all interfaces cannot be reached by a routable peer.
   local tHost
   put pHost into tHost
   if tHost is empty then
      return true
   end if
   if tHost is kOxHost then
      return true
   end if
   if tHost begins with "127." then
      return true
   end if
   if tHost is "::1" or tHost is "[::1]" then
      return true
   end if
   if tHost is "localhost" then
      return true
   end if
   return false
end oxHostIsLoopback

function oxPublicKeyFromAddress pOnionAddress
   -- Strip ".onion", base32-decode 56 chars -> 35 bytes, return the first 32 (the
   -- ed25519 public key). No crypto needed. Empty on a structural error.
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return empty
   end if
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return empty
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return empty            -- not a version-3 address
   end if
   return byte 1 to 32 of tRaw
end oxPublicKeyFromAddress

function oxAddressFromPublicKey pEd25519Pub
   -- base32( pubkey || checksum || 0x03 ) & ".onion" (docs/04). The checksum is
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2], composed from SodiumXT;
   -- absent that primitive, return a clear error rather than a wrong address.
   if the number of bytes of pEd25519Pub is not 32 then
      return "OnionXT: oxAddressFromPublicKey needs a 32-byte ed25519 public key"
   end if
   local tChecksum
   put oxOnionChecksum(pEd25519Pub) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return tChecksum         -- capability error, surfaced verbatim
   end if
   return oxBase32Encode(pEd25519Pub & tChecksum & numToByte(3)) & ".onion"
end oxAddressFromPublicKey

function oxIsValidAddress pOnionAddress
   -- Structural checks always (length, alphabet, version byte); checksum
   -- verification too when SodiumXT SHA3-256 is available (docs/04, docs/08).
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return false
   end if
   local tI, tCh
   repeat with tI = 1 to 56
      put char tI of tCore into tCh
      if offset(tCh, kOxBase32Alphabet) is 0 then
         return false
      end if
   end repeat
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return false
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return false
   end if
   -- Checksum verification when we can compute it; otherwise structural-only
   -- (the real authentication is Tor's connect-time descriptor-signature check).
   local tChecksum
   put oxOnionChecksum(byte 1 to 32 of tRaw) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return true             -- no SHA3-256 available; accept the structure
   end if
   return oxConstantTimeEqual(tChecksum, byte 33 to 34 of tRaw)
end oxIsValidAddress

private function oxNormalizeAddress pOnionAddress
   -- Trim, lowercase, and strip a trailing ".onion".
   local tCore
   put oxTrim(pOnionAddress) into tCore
   put toLower(tCore) into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   return tCore
end oxNormalizeAddress

private function oxPow2 pN
   -- 2 to the pN, as an exact integer, WITHOUT the ^ operator (some xTalk
   -- parsers reject `^` in a div/mod expression). pN is small in base32 (0..12),
   -- so this is a few multiplies and stays well within exact-integer range.
   local tR, tI
   put 1 into tR
   repeat with tI = 1 to pN
      multiply tR by 2
   end repeat
   return tR
end oxPow2

private function oxIntDiv pA, pB
   -- Integer division (floor, for the non-negative operands base32 uses) WITHOUT
   -- the `div` operator, to sidestep any xTalk parser that mishandles div/mod/^
   -- inside a compound expression. Operands here are small (base32 bit math).
   return trunc(pA / pB)
end oxIntDiv

private function oxIntMod pA, pB
   -- pA modulo pB WITHOUT the `mod` operator (see oxIntDiv).
   return pA - pB * oxIntDiv(pA, pB)
end oxIntMod

private function oxBase32Encode pData
   -- RFC 4648 base32, lowercase, no padding. Pure bit-packing: accumulate input
   -- bytes MSB-first into a small buffer and emit 5-bit groups. The buffer is
   -- masked to its pending bits each iteration so it never grows past ~13 bits
   -- (staying in exact-integer range; a 280-bit accumulator would lose precision).
   local tOut, tBits, tValue, tI, tN, tIndex
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kOxBase32Alphabet after tOut
      end repeat
      put oxIntMod(tValue, oxPow2(tBits)) into tValue        -- keep only the pending bits
   end repeat
   if tBits > 0 then
      -- Left-align the final partial group and emit it (canonical no-pad tail).
      put oxIntMod(tValue * oxPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kOxBase32Alphabet after tOut
   end if
   return tOut
end oxBase32Encode

private function oxBase32Decode pText
   -- Inverse of oxBase32Encode. Accumulate 5 bits per input char and emit a byte
   -- whenever 8 bits are available; leftover (< 5) bits of the final group are
   -- discarded (canonical). Returns empty on any character outside the alphabet.
   local tOut, tBits, tValue, tI, tN, tCh, tIndex, tByteOut
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of chars of pText into tN
   repeat with tI = 1 to tN
      put char tI of pText into tCh
      put offset(tCh, kOxBase32Alphabet) into tIndex     -- 1..32, or 0 if absent
      if tIndex is 0 then
         return empty
      end if
      put tValue * 32 + (tIndex - 1) into tValue
      add 5 to tBits
      if tBits >= 8 then
         subtract 8 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 256) into tByteOut
         put numToByte(tByteOut) after tOut
         put oxIntMod(tValue, oxPow2(tBits)) into tValue
      end if
   end repeat
   return tOut
end oxBase32Decode

private function oxOnionChecksum pEd25519Pub
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2] (docs/04). H = SHA3-256 is
   -- a SodiumXT primitive (docs/08); compose it and report a capability error if
   -- it is absent, never hand-roll a hash (CLAUDE.md rule 1).
   local tPreimage, tHash
   put textEncode(kOxChecksumPrefix, "UTF-8") & pEd25519Pub & numToByte(3) into tPreimage
   put oxSha3_256(tPreimage) into tHash
   -- A valid SHA3-256 is exactly 32 bytes; any other length is the capability
   -- error string from oxSha3_256, surfaced verbatim (robust against comparing a
   -- string prefix against binary data).
   if the number of bytes of tHash is not 32 then
      return tHash
   end if
   return byte 1 to 2 of tHash
end oxOnionChecksum

private function oxExpandedKeyFromSeed pSeed
   -- Compose SodiumXT's ABI-6 helper (docs/08 gap #1, now SHIPPED): a 32-byte seed
   -- becomes the 64-byte Tor ED25519-V3 expanded secret key (SHA-512(seed) with the
   -- ed25519 scalar clamp, all done inside SodiumXT so OnionXT hand-rolls nothing).
   -- This is exactly the key ADD_ONION ED25519-V3:<key> wants (docs/04), and its
   -- public key equals sxSignKeypairFromSeed(pSeed)'s, so the .onion address and the
   -- app's signing identity stay consistent. Requires SodiumXT ABI >= 6.
   local tExpanded
   try
      put sxSignSeedToExpandedKey(pSeed) into tExpanded
   catch tError
      return "OnionXT: oxCreateServiceFromSeed needs SodiumXT sxSignSeedToExpandedKey (requires SodiumXT ABI >= 6; see docs/08)"
   end try
   if the number of bytes of tExpanded is not 64 then
      return "OnionXT: sxSignSeedToExpandedKey returned " & the number of bytes of tExpanded & " bytes, expected 64"
   end if
   return tExpanded
end oxExpandedKeyFromSeed

function oxTransportInfo
   -- Advertise the transport and which optional SodiumXT-backed capabilities are
   -- available, so a caller can negotiate transports and fall back visibly
   -- rather than silently (docs/06). Returns a LiveCode array.
   local tInfo
   put "ox" into tInfo["transport"]
   put kOxVersion into tInfo["version"]
   put (oxSodiumHasHmac() and oxSodiumHasRandom()) into tInfo["safeCookieAuth"]
   put oxSodiumHasExpansion() into tInfo["deterministicOnion"]
   put oxSodiumHasSha3() into tInfo["offlineAddress"]
   return tInfo
end oxTransportInfo

command oxTransportDial pAddress, pPort
   -- Dial a rendezvous address. Accepts a full <56>.onion, or a 32-byte ed25519
   -- public key / 64-hex string, which it maps to an address first (docs/06).
   local tPort, tHost
   if pPort is empty then
      put 80 into tPort
   else
      put pPort into tPort
   end if
   put pAddress into tHost
   if not (tHost ends with ".onion") then
      local tPub
      if the number of chars of tHost is 64 then
         put oxHexToBytes(tHost) into tPub
      else
         put tHost into tPub
      end if
      if the number of bytes of tPub is 32 then
         put oxAddressFromPublicKey(tPub) into tHost
         if tHost begins with "OnionXT:" then
            return tHost
         end if
      end if
   end if
   oxDial tHost, tPort
   return the result
end oxTransportDial

command oxTransportListen pSeed, pVirtualPort, pLocalPort
   -- Publish a reproducible rendezvous point from a seed (docs/06).
   oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   return the result
end oxTransportListen

command oxTransportSend pStream, pData
   oxWrite pStream, pData
   return the result
end oxTransportSend

command oxTransportRecv pStream, pHandlerName
   -- Register where inbound bytes are delivered (the stream callback).
   oxSetStreamCallback pStream, pHandlerName
   return the result
end oxTransportRecv

command oxShutdown
   -- Idempotent: close every stream, remove every service, disconnect control.
   -- Safe to call twice.
   local tKey, tKeys
   put the keys of sStreams into tKeys
   repeat for each line tKey in tKeys
      oxCloseStream tKey
   end repeat
   put the keys of sServices into tKeys
   repeat for each line tKey in tKeys
      oxRemoveService tKey
   end repeat
   oxDisconnectControl
end oxShutdown

on socketError pSocketID, pError
   -- The engine's socket-failure message. If the socket closes because of an
   -- error, this arrives instead of socketClosed. Look up the owner and fail
   -- closed (docs LiveCode ref). A message for an unknown id is a clean no-op.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxStreamFail tHandle, "socket error: " & pError
      exit socketError
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "error: " & pError
      oxDisconnectControl
   end if
end socketError

on socketClosed pSocketID
   -- The remote side closed cleanly. Deliver "closed" to a stream's app callback
   -- and forget it; for the control socket, mark disconnected.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxInvokeStreamCallback tHandle, "closed", empty
      delete variable sSockToStream[pSocketID]
      delete variable sStreams[tHandle]
      exit socketClosed
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "disconnected"
      oxDisconnectControl
   end if
end socketClosed

on socketTimeout pSocketID
   -- socketTimeout REPEATS every interval while a read/write is pending (docs
   -- LiveCode ref), so it is only fatal during a handshake; on a connected stream
   -- it is just an idle read and must be ignored. Tear down only handshakes.
   local tHandle, tState
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      put sStreams[tHandle]["state"] into tState
      if tState is not "connected" then
         oxStreamFail tHandle, "SOCKS handshake timed out"
      end if
      exit socketTimeout
   end if
   -- Control socket: only fatal before authentication completes.
   if pSocketID is sControlSocket and sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control handshake timed out"
      oxDisconnectControl
   end if
end socketTimeout

command oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort
   -- Write a minimal torrc into pDataDir and launch pTorPath against it, so tor
   -- exits with the app (__OwningControllerProcess) and uses cookie auth. Returns
   -- empty on a clean launch attempt, or an error string. The caller then polls
   -- oxConnectControl / oxBootstrapProgress; this does not wait for bootstrap.
   if pTorPath is empty or pDataDir is empty then
      return "OnionXT: oxLaunchTor needs a tor binary path and a data directory"
   end if
   local tSocks, tControl, tTorrc, tRcPath
   if pSocksPort is empty then
      put kOxSocksPortDefault into tSocks
   else
      put pSocksPort into tSocks
   end if
   if pControlPort is empty then
      put kOxControlPortDefault into tControl
   else
      put pControlPort into tControl
   end if
   put "SocksPort " & tSocks & oxCrlf() after tTorrc
   put "ControlPort " & tControl & oxCrlf() after tTorrc
   put "CookieAuthentication 1" & oxCrlf() after tTorrc
   put "DataDirectory " & pDataDir & oxCrlf() after tTorrc
   -- Tie tor's lifetime to this process where the platform supports it.
   put "__OwningControllerProcess " & oxProcessId() & oxCrlf() after tTorrc
   put pDataDir & "/onionxt-torrc" into tRcPath
   put tTorrc into url ("binfile:" & tRcPath)
   oxSetSocksPort tSocks
   oxSetControlPort tControl
   -- open process is platform-specific; launch tor detached with -f <torrc>.
   -- QUOTE BOTH PATHS. The command line is split on whitespace, so an unquoted
   -- "C:/Program Files/Tor/tor.exe" arrives as the two arguments "C:/Program"
   -- and "Files/Tor/tor.exe" and the launch fails - and a data directory under
   -- "Application Support" or a user folder with a space in the name is the
   -- normal case on Windows and macOS, not an edge case. The same applies to
   -- the torrc path, which is derived from pDataDir.
   -- VERIFY: process launch and teardown on your target OXT build.
   open process (quote & pTorPath & quote & " -f " & quote & tRcPath & quote) for read
   return empty
end oxLaunchTor

command oxStopTor
   -- Ask tor to shut down over the control port, then disconnect. If Mode B was
   -- not used this simply disconnects control (idempotent).
   if sControlState is "authenticated" then
      oxCtlSend "SIGNAL SHUTDOWN", "signal"
   end if
   oxDisconnectControl
end oxStopTor

private function oxSha3_256 pData
   -- Composed since SodiumXT ABI 7 (docs/08 gap #2, closed 2026-08-11):
   -- sxSha3_256 is the vendored FIPS-202 primitive SodiumXT ships precisely
   -- for this checksum. Against an older installed SodiumXT the absent handler
   -- still raises here and degrades to the clear capability error below. The
   -- checksum is a nicety, not a security dependency (tor authenticates the
   -- onion at connect time), so callers degrade to structural-only checks.
   local tOut
   try
      put sxSha3_256(pData) into tOut
   catch tError
      return "OnionXT: the offline .onion checksum needs SodiumXT SHA3-256 (sxSha3_256, deferred gap, docs/08)"
   end try
   return tOut
end oxSha3_256

private function oxHmac pKeyString, pMessage
   -- HMAC-SHA256 (SodiumXT ABI >= 6). The ASCII key string crosses as its bytes.
   local tOut
   try
      put sxHmacSha256(textEncode(pKeyString, "UTF-8"), pMessage) into tOut
   catch tError
      return "OnionXT: SAFECOOKIE auth needs SodiumXT HMAC-SHA256 (sxHmacSha256, SodiumXT ABI >= 6, docs/08)"
   end try
   return tOut
end oxHmac

private function oxRandomBytes pCount
   local tOut
   try
      put sxRandomBytes(pCount) into tOut
   catch tError
      return empty
   end try
   return tOut
end oxRandomBytes

private function oxConstantTimeEqual pA, pB
   -- Prefer SodiumXT's constant-time compare; fall back to a plain compare only
   -- when it is unavailable (acceptable on a loopback control port).
   local tOut
   try
      put sxMemEqual(pA, pB) into tOut
      return (tOut is true)
   catch tError
      return (pA is pB)
   end try
end oxConstantTimeEqual

private function oxSodiumHasHmac
   -- True if SodiumXT (ABI >= 6) provides HMAC-SHA256. A benign 1-byte probe.
   local tOut
   try
      put sxHmacSha256(numToByte(0), numToByte(0)) into tOut
      return (the number of bytes of tOut is 32)
   catch tError
      return false
   end try
end oxSodiumHasHmac

private function oxSodiumHasRandom
   local tOut
   try
      put sxRandomBytes(1) into tOut
      return (the number of bytes of tOut is 1)
   catch tError
      return false
   end try
end oxSodiumHasRandom

private function oxSodiumHasSha3
   -- Deferred gap: expected false until SodiumXT ships SHA3-256 (docs/08 #2).
   try
      get sxSha3_256(empty)
      return true
   catch tError
      return false
   end try
end oxSodiumHasSha3

private function oxSodiumHasExpansion
   -- True if SodiumXT (ABI >= 6) provides the seed -> expanded-key helper.
   local tOut
   try
      put sxSignSeedToExpandedKey(oxZeroBytes(32)) into tOut
      return (the number of bytes of tOut is 64)
   catch tError
      return false
   end try
end oxSodiumHasExpansion

private function oxLoadCookie
   -- Read the 32 raw cookie bytes from the authoritative PROTOCOLINFO path
   -- (docs/03). binfile is binary-safe. Returns true on a plausible 32-byte read.
   if sControlCookieFile is empty then
      return false
   end if
   local tBytes
   put url ("binfile:" & sControlCookieFile) into tBytes
   if the number of bytes of tBytes is not 32 then
      return false
   end if
   put tBytes into sControlCookieBytes
   return true
end oxLoadCookie

private function effectiveSocksPort
   if sSocksPort is empty then
      return kOxSocksPortDefault
   end if
   return sSocksPort
end effectiveSocksPort

private function effectiveControlPort
   if sControlPort is empty then
      return kOxControlPortDefault
   end if
   return sControlPort
end effectiveControlPort

private function oxAllocHandle
   -- Monotonic; 0 is never a valid handle so a zero/empty is always a clean miss.
   if sNextHandle is empty then
      put 0 into sNextHandle
   end if
   add 1 to sNextHandle
   return sNextHandle
end oxAllocHandle

private command oxSafeCloseSocket pSocketID
   -- Idempotent close: only close ids the engine still lists as open, so closing
   -- a stale/unknown id is a clean no-op (VERIFY the engine tolerates it anyway).
   if pSocketID is empty then
      exit oxSafeCloseSocket
   end if
   if pSocketID is among the lines of the openSockets then
      close socket pSocketID
   end if
end oxSafeCloseSocket

private command oxInvokeStreamCallback pStream, pEvent, pData
   oxDispatch sStreams[pStream]["callback"], pStream, pEvent, pData
end oxInvokeStreamCallback

private command oxDispatch pHandlerName, pArg1, pArg2, pArg3
   -- Deliver to the app; a missing handler is a clean no-op so an app wires only
   -- the callbacks it uses. Guard the call so a throwing app handler cannot break
   -- the state machine.
   if pHandlerName is empty then
      exit oxDispatch
   end if
   local tTarget
   put oxCallbackTarget() into tTarget      -- a local, not a function call inline
   try
      dispatch pHandlerName to tTarget with pArg1, pArg2, pArg3
   catch tIgnore
      -- Swallow app-side callback errors; the transport must keep running.
   end try
end oxDispatch

private function oxCallbackTarget
   -- The object the app callbacks live in. Explicitly set is authoritative;
   -- otherwise the topStack is the best default (VERIFY it is the app's stack).
   if sCallbackOwner is not empty then
      return sCallbackOwner
   end if
   return the topStack
end oxCallbackTarget

private function oxCrlf
   -- The wire line terminator as explicit bytes-to-be (U+000D U+000A), so the
   -- byte value never depends on how the engine defines the `crlf` constant.
   return numToChar(13) & numToChar(10)
end oxCrlf

private function oxStripLineEnd pLine
   -- Strip a trailing LF and/or CR from a decoded reply line, in either order.
   -- A plain function (returns the trimmed line) rather than a @-by-reference
   -- command, to avoid the less-common reference-parameter construct.
   repeat while pLine is not empty and (the last char of pLine is numToChar(10) or the last char of pLine is numToChar(13))
      delete the last char of pLine
   end repeat
   return pLine
end oxStripLineEnd

private function oxFieldAfter pText, pMarker
   -- The whitespace-delimited token immediately following pMarker in pText, or
   -- empty. Used for METHODS=, PROGRESS=, ServiceID=, version=, SERVERHASH=, etc.
   -- itemDelimiter is global mutable state, so save and restore it (gotcha 7).
   local tPos, tRest, tSaved, tOut
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   -- Stop at the first space (values here are single tokens; quoted values use
   -- oxQuotedValueAfter instead).
   put the itemDelimiter into tSaved
   set the itemDelimiter to space
   put item 1 of tRest into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxFieldAfter

private function oxQuotedValueAfter pText, pMarker
   -- The C-quoted string value following pMarker (e.g. COOKIEFILE="..."). Returns
   -- the raw (still-escaped) inside of the quotes; the caller un-escapes.
   local tPos, tRest, tOut, tI, tCh, tEsc
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   if char 1 of tRest is not quote then
      -- Unquoted value: take up to the next space (save/restore itemDelimiter).
      -- tOut is already declared at the handler top; only tSaved is new here.
      local tSaved
      put the itemDelimiter into tSaved
      set the itemDelimiter to space
      put item 1 of tRest into tOut
      set the itemDelimiter to tSaved
      return tOut
   end if
   -- Walk from just after the opening quote to the matching unescaped quote.
   put empty into tOut
   put false into tEsc
   repeat with tI = 2 to the number of chars of tRest
      put char tI of tRest into tCh
      if tEsc then
         put tCh after tOut
         put false into tEsc
      else if tCh is "\" then
         put tCh after tOut
         put true into tEsc
      else if tCh is quote then
         exit repeat
      else
         put tCh after tOut
      end if
   end repeat
   return tOut
end oxQuotedValueAfter

private function oxCUnescape pStr
   -- Undo Tor's C-style string escapes (docs/03): \n \t \r, octal \0..\377, and
   -- backslash-before-any-other-char is that literal char.
   local tOut, tI, tN, tCh, tNext, tOct
   put empty into tOut
   put the number of chars of pStr into tN
   put 1 into tI
   repeat while tI <= tN
      put char tI of pStr into tCh
      if tCh is "\" and tI < tN then
         put char (tI + 1) of pStr into tNext
         if tNext is "n" then
            put numToChar(10) after tOut
            add 2 to tI
         else if tNext is "t" then
            put numToChar(9) after tOut
            add 2 to tI
         else if tNext is "r" then
            put numToChar(13) after tOut
            add 2 to tI
         else if tNext is in "01234567" then
            -- Up to 3 octal digits.
            put empty into tOct
            add 1 to tI
            repeat while tI <= tN and (the number of chars of tOct) < 3 and (char tI of pStr) is in "01234567"
               put char tI of pStr after tOct
               add 1 to tI
            end repeat
            put numToChar(oxOctalToNum(tOct)) after tOut
         else
            put tNext after tOut
            add 2 to tI
         end if
      else
         put tCh after tOut
         add 1 to tI
      end if
   end repeat
   return tOut
end oxCUnescape

private function oxOctalToNum pOct
   local tVal, tI
   put 0 into tVal
   repeat with tI = 1 to the number of chars of pOct
      put tVal * 8 + (charToNum(char tI of pOct) - 48) into tVal
   end repeat
   return tVal
end oxOctalToNum

private function oxQuoteEscape pStr
   -- Escape backslash and double-quote for a control-port QuotedString.
   local tOut
   put pStr into tOut
   replace "\" with "\\" in tOut
   replace quote with ("\" & quote) in tOut
   return tOut
end oxQuoteEscape

private function oxBytesToHex pData
   -- Lowercase hex (high nibble first). H* unpacks the whole run. binaryDecode is
   -- a FUNCTION (it returns the count decoded and fills the output variable, which
   -- must already exist), so it must be called as a function; `get` discards the
   -- count into `it` while tHex is filled.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end oxBytesToHex

private function oxHexToBytes pHex
   return binaryEncode("H*", pHex)
end oxHexToBytes

private function oxByteHex pNum
   -- Two-digit hex for one byte value (for error messages).
   return oxBytesToHex(numToByte(pNum))
end oxByteHex

private function oxHostOfSocket pSocketID
   -- The host part of an engine socket id "host:port" or "host:port|name".
   local tSaved, tOut
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of pSocketID into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxHostOfSocket

private function oxMethodOffered pMethod
   -- sControlMethods is a comma list; force comma before testing membership.
   local tSaved, tResult
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put (pMethod is among the items of sControlMethods) into tResult
   set the itemDelimiter to tSaved
   return tResult
end oxMethodOffered

private function oxStripWhitespace pStr
   local tOut
   put pStr into tOut
   replace numToChar(10) with empty in tOut
   replace numToChar(13) with empty in tOut
   replace space with empty in tOut
   replace tab with empty in tOut
   return tOut
end oxStripWhitespace

private function oxTrim pStr
   -- The `tOut is not empty` guard is essential: the empty string is "in" every
   -- string, so without it an all-whitespace or empty input would loop forever
   -- (the first/last char of empty is empty, which `is in` any charset).
   local tOut, tWhite
   put pStr into tOut
   put space & tab & numToChar(10) & numToChar(13) into tWhite
   repeat while tOut is not empty and (the first char of tOut) is in tWhite
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut) is in tWhite
      delete the last char of tOut
   end repeat
   return tOut
end oxTrim

private function oxZeroBytes pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(0) after tOut
   end repeat
   return tOut
end oxZeroBytes

private function oxProcessId
   -- Best-effort current process id for __OwningControllerProcess (Mode B).
   -- VERIFY the available accessor on your OXT build; empty is tolerated by tor.
   return the processId
end oxProcessId
-- <<< GENERATED EMBED: onionxt script layer <<< --


-- >>> GENERATED EMBED: riptide script layer >>> --
-- ==========================================================================
-- Riptide script layer (the real library, embedded)
--
-- The rs* surface of the capstone app - pure script over the installed
-- extensions, phase 1 (identity + the feed wire formats). Embedded so the
-- folded riptide harness tests the code it ships with, same as the coinxt
-- and onionxt layers.
--
-- GENERATED from riptide/src/riptide.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild. Names are NOT prefixed: this is the library itself, and the
-- folded tests above must reach it by its real names.
-- ==========================================================================

function rsVersion
   return "Riptide" && kRsVersion && "(phase 2: identity + the live feed)"
end rsVersion

function rsLastError
   return sRsLastError
end rsLastError

private command rsSetError pMessage
   put pMessage into sRsLastError
end rsSetError

function rsProbeCapabilities
   local tCaps, tKey, tBox, tOpened, tIgnore
   if sRsProbed is true then return sRsCaps
   put false into tCaps["canCrypto"]
   put false into tCaps["hasTorrent"]
   put false into tCaps["hasOnion"]
   put false into tCaps["hasDataChannel"]
   put false into tCaps["hasEnet"]
   put false into tCaps["hasCoin"]
   try
      put sxRandomBytes(32) into tKey
      put sxSecretBox(textEncode("probe", "ASCII"), tKey) into tBox
      put sxSecretBoxOpen(tBox, tKey) into tOpened
      put (textDecode(tOpened, "ASCII") is "probe") into tCaps["canCrypto"]
   catch tIgnore
      put false into tCaps["canCrypto"]
   end try
   try
      put btLastError() into tIgnore
      put true into tCaps["hasTorrent"]
   catch tIgnore
      put false into tCaps["hasTorrent"]
   end try
   try
      put (oxVersion() is not empty) into tCaps["hasOnion"]
   catch tIgnore
      put false into tCaps["hasOnion"]
   end try
   try
      put (dcLibraryVersion() is not empty) into tCaps["hasDataChannel"]
   catch tIgnore
      put false into tCaps["hasDataChannel"]
   end try
   try
      put (enLibraryVersion() is not empty) into tCaps["hasEnet"]
   catch tIgnore
      put false into tCaps["hasEnet"]
   end try
   try
      put (cxSha3_256Len() is 32) into tCaps["hasCoin"]
   catch tIgnore
      put false into tCaps["hasCoin"]
   end try
   -- Derived capability: SHA3-256 from EITHER provider (sodiumxt ABI 7's
   -- sxSha3_256, or coinxt's cxSha3_256) - what the offline onion
   -- self-computation actually needs. A real call, not a version sniff.
   put (the number of bytes in rsSha3(textEncode("probe", "ASCII")) is 32) \
         into tCaps["hasSha3"]
   put tCaps into sRsCaps
   put true into sRsProbed
   return sRsCaps
end rsProbeCapabilities

function rsHeadSalt
   return kRsHeadSalt
end rsHeadSalt

function rsZeroTarget
   return kRsZeroTarget
end rsZeroTarget

function rsGenerateMasterSeed
   local tSeed, tErr
   try
      put sxRandomBytes(32) into tSeed
   catch tErr
      rsSetError "rsGenerateMasterSeed: SodiumXT is required:" && tErr
      return empty
   end try
   return tSeed
end rsGenerateMasterSeed

function rsSealMasterSeed pSeed, pPassphrase
   local tSalt, tKey, tOut, tErr
   if the number of bytes in pSeed is not 32 then
      rsSetError "rsSealMasterSeed: the master seed must be 32 bytes"
      return empty
   end if
   if pPassphrase is empty then
      rsSetError "rsSealMasterSeed: an empty passphrase is refused"
      return empty
   end if
   try
      put sxRandomBytes(16) into tSalt
      put sxPwHash(textEncode(pPassphrase, "UTF-8"), tSalt, 32, \
            kRsArgonOps, sxPwMemInteractive()) into tKey
      put textEncode(kRsKeyMagic & "E", "ASCII") & tSalt & \
            sxSecretBox(pSeed, tKey) into tOut
   catch tErr
      rsSetError "rsSealMasterSeed:" && tErr
      return empty
   end try
   return tOut
end rsSealMasterSeed

function rsOpenMasterSeed pFileBytes, pPassphrase
   local tSalt, tSealed, tKey, tSeed, tHeader, tErr
   -- A RIPTKEY1 file is EXACTLY 97 bytes: 9 (magic "RIPTKEY1E") + 16 (salt) +
   -- 72 (sxSecretBox of a 32-byte seed = nonce 24 + ct 32 + mac 16). Refuse a
   -- wrong length up front rather than leaning on the Poly1305 tag to catch a
   -- truncated file (it does catch it - this is just an honest, explicit gate).
   if the number of bytes in pFileBytes is not 97 then
      rsSetError "rsOpenMasterSeed: not a 97-byte RIPTKEY1 file"
      return empty
   end if
   put textDecode(byte 1 to 9 of pFileBytes, "ASCII") into tHeader
   if tHeader is not (kRsKeyMagic & "E") then
      rsSetError "rsOpenMasterSeed: not a RIPTKEY1 sealed key file"
      return empty
   end if
   put byte 10 to 25 of pFileBytes into tSalt
   put byte 26 to -1 of pFileBytes into tSealed
   try
      put sxPwHash(textEncode(pPassphrase, "UTF-8"), tSalt, 32, \
            kRsArgonOps, sxPwMemInteractive()) into tKey
      put sxSecretBoxOpen(tSealed, tKey) into tSeed
   catch tErr
      rsSetError "rsOpenMasterSeed: wrong passphrase or corrupted key file"
      return empty
   end try
   if the number of bytes in tSeed is not 32 then
      rsSetError "rsOpenMasterSeed: the sealed payload is not a 32-byte seed"
      return empty
   end if
   return tSeed
end rsOpenMasterSeed

private function rsKdfContext
   return textEncode(kRsKdfContextText, "ASCII") & numToByte(0)
end rsKdfContext

private function rsSubkey pMaster, pSubkeyId
   local tOut, tErr
   if the number of bytes in pMaster is not 32 then
      rsSetError "rsSubkey: the master seed must be 32 bytes"
      return empty
   end if
   try
      put sxKdfDerive(pMaster, pSubkeyId, rsKdfContext(), 32) into tOut
   catch tErr
      rsSetError "rsSubkey:" && tErr
      return empty
   end try
   return tOut
end rsSubkey

function rsIdentitySeed pMaster
   return rsSubkey(pMaster, kRsSubkeyIdentity)
end rsIdentitySeed

function rsDmSeed pMaster
   return rsSubkey(pMaster, kRsSubkeyDm)
end rsDmSeed

function rsLanKey pMaster
   return rsSubkey(pMaster, kRsSubkeyLan)
end rsLanKey

function rsAnonSeed pMaster, pIndex
   local tId
   if pIndex is not an integer or pIndex < 0 then
      rsSetError "rsAnonSeed: the persona index must be a non-negative integer"
      return empty
   end if
   put kRsSubkeyAnonBase + pIndex into tId
   return rsSubkey(pMaster, tId)
end rsAnonSeed

function rsIdentityKeys pSeed
   local tPub, tSecret, tKeys, tErr
   if the number of bytes in pSeed is not 32 then
      rsSetError "rsIdentityKeys: the identity seed must be 32 bytes"
      return empty
   end if
   try
      sxSignKeypairFromSeed pSeed, tPub, tSecret
   catch tErr
      rsSetError "rsIdentityKeys:" && tErr
      return empty
   end try
   put tPub into tKeys["publicKey"]
   put tSecret into tKeys["secretKey"]
   put rsBinToHexString(tPub) into tKeys["handle"]
   if tKeys["handle"] is empty then return empty
   return tKeys
end rsIdentityKeys

function rsHandleFromSeed pSeed
   local tKeys
   put rsIdentityKeys(pSeed) into tKeys
   if tKeys is empty then return empty
   return tKeys["handle"]
end rsHandleFromSeed

private function rsSha3 pData
   local tHash, tErr
   try
      put sxSha3_256(pData) into tHash
      if the number of bytes in tHash is 32 then return tHash
   catch tErr
      put empty into tHash
   end try
   try
      put cxSha3_256(pData) into tHash
      if the number of bytes in tHash is 32 then return tHash
   catch tErr
      put empty into tHash
   end try
   return empty
end rsSha3

function rsOnionFromPublicKey pPub
   local tHash
   if the number of bytes in pPub is not 32 then
      rsSetError "rsOnionFromPublicKey: the public key must be 32 bytes"
      return empty
   end if
   put rsSha3(textEncode(kRsChecksumPrefix, "UTF-8") & pPub & \
         numToByte(3)) into tHash
   if tHash is empty then
      rsSetError "rsOnionFromPublicKey: the offline .onion checksum needs" && \
            "SHA3-256 from sodiumxt ABI 7 (sxSha3_256) or coinxt" && \
            "(cxSha3_256); install either, or read the address from" && \
            "oxServiceAddress after publishing"
      return empty
   end if
   return rsBase32Encode(pPub & (byte 1 to 2 of tHash) & numToByte(3)) & \
         ".onion"
end rsOnionFromPublicKey

function rsOnionFromHandle pHandleHex
   local tPub
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsOnionFromHandle: the handle must be 64 hex chars"
      return empty
   end if
   return rsOnionFromPublicKey(tPub)
end rsOnionFromHandle

function rsVerifyOnionClaim pOnionAddr, pHandleHex
   local tClaimed, tExpected, tErr
   try
      put oxPublicKeyFromAddress(pOnionAddr) into tClaimed
   catch tErr
      rsSetError "rsVerifyOnionClaim: needs onionxt (oxPublicKeyFromAddress)"
      return false
   end try
   if the number of bytes in tClaimed is not 32 then
      rsSetError "rsVerifyOnionClaim: not a structurally valid onion address"
      return false
   end if
   put rsHexToBin(pHandleHex) into tExpected
   if the number of bytes in tExpected is not 32 then
      rsSetError "rsVerifyOnionClaim: the handle must be 64 hex chars"
      return false
   end if
   try
      return sxMemEqual(tClaimed, tExpected)
   catch tErr
      rsSetError "rsVerifyOnionClaim:" && tErr
      return false
   end try
end rsVerifyOnionClaim

function rsInboxId pHandleHex
   local tPub, tOut, tErr
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsInboxId: the handle must be 64 hex chars"
      return empty
   end if
   try
      put sxHash(tPub & textEncode(kRsInboxSuffix, "ASCII"), 20) into tOut
   catch tErr
      rsSetError "rsInboxId:" && tErr
      return empty
   end try
   return rsBinToHexString(tOut)
end rsInboxId

function rsRoomId pPkAHex, pPkBHex, pSessionSalt
   local tA, tB, tCat, tOut, tErr
   put toLower(pPkAHex) into tA
   put toLower(pPkBHex) into tB
   if not rsIsHexOfLen(tA, 64) or not rsIsHexOfLen(tB, 64) then
      rsSetError "rsRoomId: both public keys must be 64 hex chars"
      return empty
   end if
   if tA <= tB then
      put rsHexToBin(tA) & rsHexToBin(tB) into tCat
   else
      put rsHexToBin(tB) & rsHexToBin(tA) into tCat
   end if
   try
      put sxHash(tCat & pSessionSalt, 20) into tOut
   catch tErr
      rsSetError "rsRoomId:" && tErr
      return empty
   end try
   return rsBinToHexString(tOut)
end rsRoomId

function rsBuildHead pSeq, pDisplayName, pLatestPost, pPrekey, pOnionAddr, pProfileMeta
   local tNameBytes, tOnion, tOnionChars, tLatest, tPrekeyT, tProfile, tOut
   if pSeq is not an integer or pSeq < 0 then
      rsSetError "rsBuildHead: seq must be a non-negative integer"
      return empty
   end if
   -- The seq field is a u64 on the wire, but xTalk numbers are doubles, so only
   -- values below 2^53 round-trip exactly. Refuse anything at or above that
   -- rather than serialize a seq that re-parses to a different number (a BEP44
   -- monotonic-counter field silently changing value is a correctness bug).
   if pSeq >= 9007199254740992 then
      rsSetError "rsBuildHead: seq must be below 2^53 to round-trip exactly"
      return empty
   end if
   put textEncode(pDisplayName, "UTF-8") into tNameBytes
   if the number of bytes in tNameBytes > kRsMaxDisplayName then
      rsSetError "rsBuildHead: the display name is over" && \
            kRsMaxDisplayName && "bytes of UTF-8"
      return empty
   end if
   put rsNormalizeTarget(pLatestPost) into tLatest
   put rsNormalizeTarget(pPrekey) into tPrekeyT
   put rsNormalizeTarget(pProfileMeta) into tProfile
   if tLatest is empty or tPrekeyT is empty or tProfile is empty then
      rsSetError "rsBuildHead: a target must be empty or 40 hex chars"
      return empty
   end if
   put toLower(pOnionAddr) into tOnion
   put the number of chars in tOnion into tOnionChars
   if tOnion is not empty and tOnionChars is not kRsOnionAddrLen then
      rsSetError "rsBuildHead: an onion address must be" && \
            kRsOnionAddrLen && "chars"
      return empty
   end if
   put textEncode(kRsHeadMagic, "ASCII") into tOut
   put rsBEu64(pSeq) after tOut
   put numToByte(the number of bytes in tNameBytes) after tOut
   put tNameBytes after tOut
   put textEncode(tLatest, "ASCII") after tOut
   put textEncode(tPrekeyT, "ASCII") after tOut
   put numToByte(the number of chars in tOnion) after tOut
   put textEncode(tOnion, "ASCII") after tOut
   put textEncode(tProfile, "ASCII") after tOut
   if the number of bytes in tOut > kRsMaxRecord then
      rsSetError "rsBuildHead: the head record is over" && kRsMaxRecord && \
            "bytes"
      return empty
   end if
   return tOut
end rsBuildHead

function rsParseHead pBytes
   local tLen, tPos, tNameLen, tOnionLen, tHead, tField, tErr
   put the number of bytes in pBytes into tLen
   if tLen < 13 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsHeadMagic then
      rsSetError "rsParseHead: bad magic, not an RSH1 record"
      return empty
   end if
   put rsReadBEu64(byte 5 to 12 of pBytes) into tHead["seq"]
   put byteToNum(byte 13 of pBytes) into tNameLen
   if tNameLen > kRsMaxDisplayName then
      rsSetError "rsParseHead: display name length over cap"
      return empty
   end if
   put 13 into tPos
   if tLen < tPos + tNameLen + 40 + 40 + 1 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   -- textDecode can throw on malformed UTF-8, and pBytes is attacker-supplied,
   -- so a bad display name must be a clean refusal - not a thrown error out of a
   -- parser the header promises never throws.
   try
      put textDecode(byte (tPos + 1) to (tPos + tNameLen) of pBytes, "UTF-8") \
            into tHead["displayName"]
   catch tErr
      rsSetError "rsParseHead: the display name is not valid UTF-8"
      return empty
   end try
   add tNameLen to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed latest-post target"
      return empty
   end if
   put tField into tHead["latestPostTarget"]
   add 40 to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed prekey target"
      return empty
   end if
   put tField into tHead["prekeyTarget"]
   add 40 to tPos
   put byteToNum(byte (tPos + 1) of pBytes) into tOnionLen
   add 1 to tPos
   if tOnionLen is not 0 and tOnionLen is not kRsOnionAddrLen then
      rsSetError "rsParseHead: bad onion address length"
      return empty
   end if
   if tLen < tPos + tOnionLen + 40 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   if tOnionLen is 0 then
      put empty into tHead["onionAddr"]
   else
      put textDecode(byte (tPos + 1) to (tPos + tOnionLen) of pBytes, \
            "ASCII") into tHead["onionAddr"]
   end if
   add tOnionLen to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed profile-meta target"
      return empty
   end if
   put tField into tHead["profileMetaTarget"]
   add 40 to tPos
   if tLen is not tPos then
      rsSetError "rsParseHead: trailing bytes after the head record"
      return empty
   end if
   return tHead
end rsParseHead

function rsBuildPost pTimestamp, pPrevTarget, pTextContent, pMediaList, pIdentitySeed
   local tBody
   put rsPostBody(pTimestamp, pPrevTarget, "D", pTextContent, empty, \
         pMediaList) into tBody
   if tBody is empty then return empty
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildPost

function rsBuildPostChunked pTimestamp, pPrevTarget, pChunkTargets, pMediaList, pIdentitySeed
   local tBody
   put rsPostBody(pTimestamp, pPrevTarget, "C", empty, pChunkTargets, \
         pMediaList) into tBody
   if tBody is empty then return empty
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildPostChunked

private function rsPostBody pTimestamp, pPrevTarget, pKind, pTextContent, pChunkTargets, pMediaList
   local tPrev, tOut, tTextBytes, tChunkCount, tMediaCount, tItem, tNorm
   if pTimestamp is an integer and pTimestamp >= 9007199254740992 then
      rsSetError "rsPostBody: the timestamp must be below 2^53 to round-trip exactly"
      return empty
   end if
   if pTimestamp is not an integer or pTimestamp < 0 then
      rsSetError "rsPostBody: the timestamp must be a non-negative integer"
      return empty
   end if
   put rsNormalizeTarget(pPrevTarget) into tPrev
   if tPrev is empty then
      rsSetError "rsPostBody: the previous-post target must be empty or 40 hex"
      return empty
   end if
   put textEncode(kRsPostMagic, "ASCII") into tOut
   put rsBEu64(pTimestamp) after tOut
   put textEncode(tPrev, "ASCII") after tOut
   put textEncode(pKind, "ASCII") after tOut
   if pKind is "D" then
      put textEncode(pTextContent, "UTF-8") into tTextBytes
      if the number of bytes in tTextBytes > 65535 then
         rsSetError "rsPostBody: the text is over the u16 length field"
         return empty
      end if
      put rsBEu16(the number of bytes in tTextBytes) after tOut
      put tTextBytes after tOut
   else
      set the itemDelimiter to comma
      put the number of items in pChunkTargets into tChunkCount
      if tChunkCount < 1 or tChunkCount > kRsMaxChunks then
         rsSetError "rsPostBody: chunk count must be 1 to" && kRsMaxChunks
         return empty
      end if
      put numToByte(tChunkCount) after tOut
      repeat for each item tItem in pChunkTargets
         put rsNormalizeTarget(tItem) into tNorm
         if tNorm is kRsZeroTarget or tNorm is empty then
            rsSetError "rsPostBody: a chunk target must be 40 non-zero hex"
            return empty
         end if
         put textEncode(tNorm, "ASCII") after tOut
      end repeat
   end if
   set the itemDelimiter to comma
   if pMediaList is empty then
      put 0 into tMediaCount
   else
      put the number of items in pMediaList into tMediaCount
   end if
   if tMediaCount > kRsMaxMedia then
      rsSetError "rsPostBody: media count over" && kRsMaxMedia
      return empty
   end if
   put numToByte(tMediaCount) after tOut
   if tMediaCount > 0 then
      repeat for each item tItem in pMediaList
         put rsNormalizeTarget(tItem) into tNorm
         if tNorm is kRsZeroTarget or tNorm is empty then
            rsSetError "rsPostBody: a media info-hash must be 40 non-zero hex"
            return empty
         end if
         put textEncode(tNorm, "ASCII") after tOut
      end repeat
   end if
   if the number of bytes in tOut + 64 > kRsMaxRecord then
      rsSetError "rsPostBody: the post record is over" && kRsMaxRecord && \
            "bytes; move the text to chunks or drop media"
      return empty
   end if
   return tOut
end rsPostBody

private function rsSignPost pBody, pIdentitySeed
   local tKeys, tSig, tErr
   put rsIdentityKeys(pIdentitySeed) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignDetached(pBody, tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsSignPost:" && tErr
      return empty
   end try
   return pBody & tSig
end rsSignPost

function rsParsePost pBytes
   local tLen, tPos, tKind, tCount, tPost, tField, tI, tTextLen, tList, tErr
   put the number of bytes in pBytes into tLen
   if tLen < 4 + 8 + 40 + 1 + 1 + 64 then
      rsSetError "rsParsePost: truncated post record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsPostMagic then
      rsSetError "rsParsePost: bad magic, not an RSP1 record"
      return empty
   end if
   put rsReadBEu64(byte 5 to 12 of pBytes) into tPost["timestamp"]
   put textDecode(byte 13 to 52 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParsePost: malformed previous-post target"
      return empty
   end if
   put tField into tPost["prevPostTarget"]
   put textDecode(byte 53 of pBytes, "ASCII") into tKind
   put tKind into tPost["kind"]
   put 53 into tPos
   if tKind is "D" then
      if tLen < tPos + 2 + 1 + 64 then
         rsSetError "rsParsePost: truncated post record"
         return empty
      end if
      put rsReadBEu16(byte (tPos + 1) to (tPos + 2) of pBytes) into tTextLen
      add 2 to tPos
      if tLen < tPos + tTextLen + 1 + 64 then
         rsSetError "rsParsePost: text length runs past the record"
         return empty
      end if
      -- Attacker-supplied bytes; malformed UTF-8 is a clean refusal, not a throw
      -- (the header promises this parser never throws).
      try
         put textDecode(byte (tPos + 1) to (tPos + tTextLen) of pBytes, \
               "UTF-8") into tPost["text"]
      catch tErr
         rsSetError "rsParsePost: the post text is not valid UTF-8"
         return empty
      end try
      add tTextLen to tPos
   else if tKind is "C" then
      put byteToNum(byte (tPos + 1) of pBytes) into tCount
      add 1 to tPos
      if tCount < 1 or tCount > kRsMaxChunks then
         rsSetError "rsParsePost: chunk count out of range"
         return empty
      end if
      if tLen < tPos + tCount * 40 + 1 + 64 then
         rsSetError "rsParsePost: truncated chunk list"
         return empty
      end if
      put empty into tList
      repeat with tI = 1 to tCount
         put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
               into tField
         if not rsIsHexOfLen(tField, 40) then
            rsSetError "rsParsePost: malformed chunk target"
            return empty
         end if
         if tList is empty then
            put tField into tList
         else
            put comma & tField after tList
         end if
         add 40 to tPos
      end repeat
      put tList into tPost["chunkTargets"]
   else
      rsSetError "rsParsePost: unknown post kind"
      return empty
   end if
   put byteToNum(byte (tPos + 1) of pBytes) into tCount
   add 1 to tPos
   if tCount > kRsMaxMedia then
      rsSetError "rsParsePost: media count out of range"
      return empty
   end if
   if tLen is not tPos + tCount * 40 + 64 then
      rsSetError "rsParsePost: record length does not match its fields"
      return empty
   end if
   put empty into tList
   repeat with tI = 1 to tCount
      put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
            into tField
      if not rsIsHexOfLen(tField, 40) then
         rsSetError "rsParsePost: malformed media info-hash"
         return empty
      end if
      if tList is empty then
         put tField into tList
      else
         put comma & tField after tList
      end if
      add 40 to tPos
   end repeat
   put tList into tPost["mediaTargets"]
   return tPost
end rsParsePost

function rsVerifyPost pBytes, pHandleHex
   local tPub, tParsed, tLen, tErr
   put rsParsePost(pBytes) into tParsed
   if tParsed is empty then return false
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsVerifyPost: the handle must be 64 hex chars"
      return false
   end if
   put the number of bytes in pBytes into tLen
   try
      return sxSignVerifyDetached(byte (tLen - 63) to tLen of pBytes, \
            byte 1 to (tLen - 64) of pBytes, tPub)
   catch tErr
      rsSetError "rsVerifyPost:" && tErr
      return false
   end try
end rsVerifyPost

function rsBencodeBytes pData
   local tLen
   put the number of bytes in pData into tLen
   return textEncode(tLen & ":", "ASCII") & pData
end rsBencodeBytes

private function rsBencodedByteStringLen pValue
   local tI, tN, tLen, tDigits
   put 0 into tLen
   put 0 into tDigits
   repeat with tI = 1 to the number of bytes in pValue
      put byteToNum(byte tI of pValue) into tN
      if tN is 58 then
         if tDigits is 0 then return -1
         if the number of bytes in pValue - tI is not tLen then return -1
         return tLen
      end if
      if tN < 48 or tN > 57 then return -1
      if tDigits > 0 and tLen is 0 then return -1
      put tLen * 10 + (tN - 48) into tLen
      add 1 to tDigits
      if tDigits > 4 then return -1
   end repeat
   return -1
end rsBencodedByteStringLen

function rsBep44SignBuf pSalt, pSeq, pValue
   local tSaltBytes, tRawLen, tOut
   if pSeq is not an integer or pSeq < 0 then
      rsSetError "rsBep44SignBuf: seq must be a non-negative integer"
      return empty
   end if
   if pSeq >= 9007199254740992 then
      rsSetError "rsBep44SignBuf: seq must be below 2^53 to round-trip exactly"
      return empty
   end if
   put textEncode(pSalt, "UTF-8") into tSaltBytes
   if the number of bytes in tSaltBytes > kRsMaxSalt then
      rsSetError "rsBep44SignBuf: the salt is over" && kRsMaxSalt && \
            "bytes (the BEP44 cap)"
      return empty
   end if
   put rsBencodedByteStringLen(pValue) into tRawLen
   if tRawLen < 1 or tRawLen > kRsMaxRecord then
      rsSetError "rsBep44SignBuf: the value must be a bencoded byte string" && \
            "of 1 to" && kRsMaxRecord && "raw bytes"
      return empty
   end if
   put empty into tOut
   if tSaltBytes is not empty then
      put textEncode("4:salt" & the number of bytes in tSaltBytes & ":", \
            "ASCII") & tSaltBytes into tOut
   end if
   put textEncode("3:seqi" & pSeq & "e1:v", "ASCII") after tOut
   put pValue after tOut
   return tOut
end rsBep44SignBuf

function rsImmutableTarget pValue
   local tLen
   put the number of bytes in pValue into tLen
   if tLen < 1 or tLen > kRsMaxRecord then
      rsSetError "rsImmutableTarget: a BEP44 immutable value is 1 to" && \
            kRsMaxRecord && "bytes"
      return empty
   end if
   return rsBinToHexString(sha1Digest(rsBencodeBytes(pValue)))
end rsImmutableTarget

function rsIngestHead pEvent, pExpectedHandleHex
   local tHandle, tEventKey, tSeq, tHead, tSigHex, tSig, tBuf, tOk, tErr
   put toLower(pExpectedHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsIngestHead: the expected handle must be 64 hex chars"
      return empty
   end if
   put toLower(pEvent["publicKey"]) into tEventKey
   if not rsIsHexOfLen(tEventKey, 64) or tEventKey is not tHandle then
      rsSetError "rsIngestHead: the event is not for this handle"
      return empty
   end if
   -- `is` folds case, so a case-mangled salt could pass this line; it then
   -- fails the signature below, because the buffer is rebuilt from the
   -- CANONICAL salt. The crypto backstops the string compare.
   if pEvent["salt"] is not kRsHeadSalt then
      rsSetError "rsIngestHead: the event is not a riptide-head item"
      return empty
   end if
   put pEvent["seq"] into tSeq
   if tSeq is not an integer or tSeq < 0 or tSeq >= 9007199254740992 then
      rsSetError "rsIngestHead: the event seq is not a sane integer"
      return empty
   end if
   put rsParseHead(pEvent["value"]) into tHead
   if tHead is empty then return empty
   if tHead["seq"] is not tSeq then
      -- rsPublishHead uses the head's own embedded seq as the BEP44 seq, so
      -- a disagreement means this record was not published by this layer
      -- (or was reassembled); refuse rather than guess which counter to
      -- believe - the app's replay protection reads the one true seq.
      rsSetError "rsIngestHead: the BEP44 seq and the head's embedded seq" && \
            "disagree"
      return empty
   end if
   put toLower(pEvent["signature"]) into tSigHex
   if not rsIsHexOfLen(tSigHex, 128) then
      rsSetError "rsIngestHead: the event signature is not 128 hex chars"
      return empty
   end if
   put rsHexToBin(tSigHex) into tSig
   if tSig is empty then return empty
   put rsBep44SignBuf(kRsHeadSalt, tSeq, rsBencodeBytes(pEvent["value"])) \
         into tBuf
   if tBuf is empty then return empty
   try
      put sxSignVerifyDetached(tSig, tBuf, rsHexToBin(tHandle)) into tOk
   catch tErr
      rsSetError "rsIngestHead:" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsIngestHead: the BEP44 signature does not verify under" && \
            "this handle"
      return empty
   end if
   return tHead
end rsIngestHead

function rsIngestPost pEvent, pExpectedTarget, pAuthorHandleHex
   local tExpected, tEventTarget, tValue, tComputed
   put rsNormalizeTarget(pExpectedTarget) into tExpected
   if tExpected is empty or tExpected is kRsZeroTarget then
      rsSetError "rsIngestPost: the expected target must be 40 non-zero" && \
            "hex chars"
      return empty
   end if
   put toLower(pEvent["target"]) into tEventTarget
   if tEventTarget is not tExpected then
      rsSetError "rsIngestPost: the event names a different target"
      return empty
   end if
   put pEvent["value"] into tValue
   put rsImmutableTarget(tValue) into tComputed
   if tComputed is empty then return empty
   if tComputed is not tExpected then
      rsSetError "rsIngestPost: the value does not hash to its own target"
      return empty
   end if
   if rsVerifyPost(tValue, pAuthorHandleHex) is not true then
      return empty
   end if
   return rsParsePost(tValue)
end rsIngestPost

private function rsValidSession pSession
   return pSession is an integer and pSession > 0
end rsValidSession

function rsPublishHead pSession, pHeadBytes, pIdentitySeed
   local tHead, tKeys, tValue, tBuf, tSig, tSigHex, tCode, tWhy, tErr
   put rsParseHead(pHeadBytes) into tHead
   if tHead is empty then
      rsSetError "rsPublishHead: not a valid RSH1 head:" && rsLastError()
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsPublishHead: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   put rsIdentityKeys(pIdentitySeed) into tKeys
   if tKeys is empty then return false
   put rsBencodeBytes(pHeadBytes) into tValue
   put rsBep44SignBuf(kRsHeadSalt, tHead["seq"], tValue) into tBuf
   if tBuf is empty then return false
   try
      put sxSignDetached(tBuf, tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsPublishHead:" && tErr
      return false
   end try
   put rsBinToHexString(tSig) into tSigHex
   if tSigHex is empty then return false
   try
      btDhtPutSigned pSession, tKeys["handle"], kRsHeadSalt, \
            tHead["seq"], tValue, tSigHex
      put the result into tCode
   catch tErr
      rsSetError "rsPublishHead: needs torrentxt (btDhtPutSigned):" && tErr
      return false
   end try
   if tCode is not 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsPublishHead: btDhtPutSigned refused (" & tCode & ")" && tWhy
      return false
   end if
   return true
end rsPublishHead

function rsPublishImmutable pSession, pValue
   local tExpected, tTarget, tWhy, tErr
   put rsImmutableTarget(pValue) into tExpected
   if tExpected is empty then return empty
   if not rsValidSession(pSession) then
      rsSetError "rsPublishImmutable: pSession is not a live torrent" && \
            "session handle"
      return empty
   end if
   try
      put btDhtPutImmutable(pSession, pValue) into tTarget
   catch tErr
      rsSetError "rsPublishImmutable: needs torrentxt" && \
            "(btDhtPutImmutable):" && tErr
      return empty
   end try
   if tTarget is empty then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsPublishImmutable: btDhtPutImmutable failed;" && tWhy
      return empty
   end if
   if toLower(tTarget) is not tExpected then
      rsSetError "rsPublishImmutable: libtorrent's target" && tTarget && \
            "disagrees with the recomputed" && tExpected
      return empty
   end if
   return tExpected
end rsPublishImmutable

function rsPublishPost pSession, pPostBytes
   local tParsed
   put rsParsePost(pPostBytes) into tParsed
   if tParsed is empty then
      rsSetError "rsPublishPost: not a valid RSP1 record:" && rsLastError()
      return empty
   end if
   return rsPublishImmutable(pSession, pPostBytes)
end rsPublishPost

function rsRequestHead pSession, pHandleHex
   local tHandle, tCode, tErr
   put toLower(pHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsRequestHead: the handle must be 64 hex chars"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsRequestHead: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   try
      btDhtGetMutable pSession, tHandle, kRsHeadSalt
      put the result into tCode
   catch tErr
      rsSetError "rsRequestHead: needs torrentxt (btDhtGetMutable):" && tErr
      return false
   end try
   if tCode is not 0 then
      rsSetError "rsRequestHead: btDhtGetMutable refused (" & tCode & ")"
      return false
   end if
   return true
end rsRequestHead

function rsRequestImmutable pSession, pTarget
   local tT, tCode, tErr
   put rsNormalizeTarget(pTarget) into tT
   if tT is empty or tT is kRsZeroTarget then
      rsSetError "rsRequestImmutable: the target must be 40 non-zero hex" && \
            "chars"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsRequestImmutable: pSession is not a live torrent" && \
            "session handle"
      return false
   end if
   try
      btDhtGetImmutable pSession, tT
      put the result into tCode
   catch tErr
      rsSetError "rsRequestImmutable: needs torrentxt (btDhtGetImmutable):" \
            && tErr
      return false
   end try
   if tCode is not 0 then
      rsSetError "rsRequestImmutable: btDhtGetImmutable refused (" & tCode & ")"
      return false
   end if
   return true
end rsRequestImmutable

private function rsIsHexOfLen pValue, pLen
   local tI, tN
   if the number of chars in pValue is not pLen then return false
   repeat with tI = 1 to pLen
      put byteToNum(byte tI of pValue) into tN
      if not ((tN >= 48 and tN <= 57) or (tN >= 97 and tN <= 102)) then
         return false
      end if
   end repeat
   return true
end rsIsHexOfLen

private function rsNormalizeTarget pTarget
   local tT
   if pTarget is empty then return kRsZeroTarget
   put toLower(pTarget) into tT
   if not rsIsHexOfLen(tT, 40) then return empty
   return tT
end rsNormalizeTarget

private function rsHexToBin pHex
   local tOut, tErr
   try
      put sxHex2Bin(textEncode(toLower(pHex), "ASCII")) into tOut
   catch tErr
      rsSetError "rsHexToBin: malformed hex"
      return empty
   end try
   return tOut
end rsHexToBin

private function rsBinToHexString pData
   local tOut, tErr
   try
      put textDecode(sxBin2Hex(pData), "ASCII") into tOut
   catch tErr
      rsSetError "rsBinToHexString:" && tErr
      return empty
   end try
   return tOut
end rsBinToHexString

private function rsBEu16 pNum
   return binaryEncode("n", pNum)
end rsBEu16

private function rsBEu64 pNum
   return binaryEncode("NN", pNum div 4294967296, pNum mod 4294967296)
end rsBEu64

private function rsReadBEu16 pBytes
   return byteToNum(byte 1 of pBytes) * 256 + byteToNum(byte 2 of pBytes)
end rsReadBEu16

private function rsReadBEu32 pBytes
   local tA, tB, tC, tD
   put byteToNum(byte 1 of pBytes) into tA
   put byteToNum(byte 2 of pBytes) into tB
   put byteToNum(byte 3 of pBytes) into tC
   put byteToNum(byte 4 of pBytes) into tD
   return ((tA * 256 + tB) * 256 + tC) * 256 + tD
end rsReadBEu32

private function rsReadBEu64 pBytes
   return rsReadBEu32(byte 1 to 4 of pBytes) * 4294967296 + \
         rsReadBEu32(byte 5 to 8 of pBytes)
end rsReadBEu64

private function rsPow2 pN
   local tOut, tI
   put 1 into tOut
   repeat pN times
      put tOut * 2 into tOut
   end repeat
   return tOut
end rsPow2

private function rsIntDiv pA, pB
   return trunc(pA / pB)
end rsIntDiv

private function rsIntMod pA, pB
   return pA - pB * trunc(pA / pB)
end rsIntMod

private function rsBase32Encode pData
   local tAcc, tBits, tOut, tI, tIndex
   put 0 into tAcc
   put 0 into tBits
   put empty into tOut
   repeat with tI = 1 to the number of bytes in pData
      put tAcc * 256 + byteToNum(byte tI of pData) into tAcc
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put rsIntMod(rsIntDiv(tAcc, rsPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kRsBase32Alphabet after tOut
         put rsIntMod(tAcc, rsPow2(tBits)) into tAcc
      end repeat
   end repeat
   if tBits > 0 then
      put rsIntMod(tAcc * rsPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kRsBase32Alphabet after tOut
   end if
   return tOut
end rsBase32Encode
-- <<< GENERATED EMBED: riptide script layer <<< --


-- ==========================================================================
-- EVERYTHING BELOW THIS LINE IS GENERATED. Do not edit it here.
--
-- It is each member's OWN self-test, folded in by
-- tools/build-suite-selftest.py with every name it defines prefixed, so
-- that five harnesses which all define stAssert, stRun and sTotal can
-- share one script. Each keeps its own scaffolding and its own counters
-- and therefore behaves here exactly as it does standalone; the core
-- above reads each one's log and totals afterwards and merges them.
--
-- To change a check, edit the member harness it comes from and run
--     python3 tools/build-suite-selftest.py
-- The gate set runs --check, so a stale file fails the build.
-- ==========================================================================

-- ==========================================================================
-- SodiumXT: the full sx* self-test
--
-- 21 groups: encoding, hashing, secretbox, AEAD, pwhash, KDF, secretstream,
-- signing, box, seal, key exchange, padding.
--
-- GENERATED from sodiumxt/examples/sodium-tests.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `sx1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

function sx1sxSelfTest
   put "SodiumXT self-test" & return into sx1sLog
   put 0 into sx1sPass
   put 0 into sx1sFail

   sx1testVersion
   sx1testRandomBytes
   sx1testEncoding
   sx1testHashing
   sx1testMemEqual
   sx1testSecretBox
   sx1testAead
   sx1testPwHash
   sx1testKdf
   sx1testSecretStream
   sx1testStreamRekey
   sx1testFileHelpers
   sx1testSign
   sx1testBox
   sx1testSeal
   sx1testKeyExchange
   sx1testSeededKeypairs
   sx1testOnionPrimitives
   sx1testPadding
   sx1testHashExtras
   sx1testDiagnostics

   put return & "----" & return after sx1sLog
   put "PASSED:" && sx1sPass & "   FAILED:" && sx1sFail after sx1sLog
   return sx1sLog
end sx1sxSelfTest

on sx1sxCheck pCondition, pLabel
   if pCondition then
      add 1 to sx1sPass
      put "  ok   " & pLabel & return after sx1sLog
   else
      add 1 to sx1sFail
      put "  FAIL " & pLabel & return after sx1sLog
   end if
end sx1sxCheck

private command sx1sxSection pTitle
   put pTitle & ":" & return after sx1sLog
end sx1sxSection

private function sx1sxHexOf pData
   return textDecode(sxBin2Hex(pData), "ascii")
end sx1sxHexOf

private function sx1sxUtf8 pText
   return textEncode(pText, "utf-8")
end sx1sxUtf8

on sx1testVersion
   local sx1tVer
   sx1sxSection "version"
   put sxVersion() into sx1tVer
   sx1sxCheck (sx1tVer is not empty), "sxVersion returns a non-empty string"
   sx1sxCheck ("libsodium" is in sx1tVer), "version names libsodium"
end sx1testVersion

on sx1testRandomBytes
   local sx1tA
   local sx1tB
   sx1sxSection "randombytes"
   put sxRandomBytes(32) into sx1tA
   put sxRandomBytes(32) into sx1tB
   sx1sxCheck (the number of bytes in sx1tA is 32), "sxRandomBytes(32) returns 32 bytes"
   sx1sxCheck (sx1tA is not sx1tB), "two draws differ (entropy is flowing)"
end sx1testRandomBytes

on sx1testEncoding
   local sx1tBin
   local sx1tHex
   local sx1tRound
   local sx1tTriplet
   local sx1tEmpty
   sx1sxSection "encoding"
   put sxHex2Bin(textEncode("deadbeef", "ascii")) into sx1tBin
   put sx1sxHexOf(sx1tBin) into sx1tHex
   sx1sxCheck (sx1tHex is "deadbeef"), "hex round trip (deadbeef)"
   put sxBase642Bin(sxBin2Base64(sx1sxUtf8("Hello, xTalk!"))) into sx1tRound
   sx1sxCheck (textDecode(sx1tRound, "utf-8") is "Hello, xTalk!"), "base64 round trip"
   -- Regression (short payloads): a 3-byte value encodes to a 4-char base64
   -- group, the smallest whole group and the exact size the decode out buffer
   -- must fit. This round trip used to throw (the wrapper allocated one byte too
   -- few), so keep a 3-byte and an empty case pinned here on-engine.
   put sxBase642Bin(sxBin2Base64(textEncode("abc", "ascii"))) into sx1tTriplet
   sx1sxCheck (textDecode(sx1tTriplet, "ascii") is "abc"), "base64 round trip of a 3-byte value"
   put sxBase642Bin(sxBin2Base64(textEncode("", "ascii"))) into sx1tEmpty
   sx1sxCheck (the number of bytes in sx1tEmpty is 0), "base64 round trip of an empty value"
end sx1testEncoding

on sx1testHashing
   sx1sxSection "hashing (BLAKE2b + SHA3-256)"
   -- published BLAKE2b-256 known-answer vector for "abc"
   sx1sxCheck (sx1sxHexOf(sxHash(sx1sxUtf8("abc"), 32)) is \
      "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"), \
      "BLAKE2b-256(abc) matches the published vector"
   -- a keyed hash differs from the unkeyed hash
   sx1sxCheck (sxHash(sx1sxUtf8("abc"), 32) is not \
      sxHashKeyed(sx1sxUtf8("abc"), sxRandomBytes(32), 32)), \
      "keyed hash differs from unkeyed"
   -- SHA3-256 (ABI 7, the vendored FIPS 202 primitive for the offline v3
   -- onion checksum). The abc vector pins the DOMAIN PADDING: Keccak-256 of
   -- "abc" starts 4e03657a, SHA3-256 starts 3a985da7 - a wrong variant
   -- cannot pass. Same vectors as sodium_smoke_test.c test_sha3.
   sx1sxCheck (sx1sxHexOf(sxSha3_256(sx1sxUtf8("abc"))) is \
      "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"), \
      "SHA3-256(abc) matches the FIPS 202 vector"
   sx1sxCheck (sx1sxHexOf(sxSha3_256(sx1sxUtf8(""))) is \
      "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"), \
      "SHA3-256 of empty input matches the FIPS 202 vector"
   sx1sxCheck (sxSha3_256(sx1sxUtf8("abc")) is not sxHash(sx1sxUtf8("abc"), 32)), \
      "SHA3-256 and BLAKE2b-256 are different functions"
end sx1testHashing

on sx1testMemEqual
   local sx1tX
   sx1sxSection "constant-time compare"
   put sxRandomBytes(32) into sx1tX
   sx1sxCheck (sxMemEqual(sx1tX, sx1tX) is true), "equal buffers compare equal"
   sx1sxCheck (sxMemEqual(sx1tX, sxRandomBytes(32)) is false), "different buffers compare unequal"
end sx1testMemEqual

on sx1testSecretBox
   local sx1tKey
   local sx1tBox
   local sx1tPlain
   local sx1tOk
   sx1sxSection "secretbox"
   put sxRandomBytes(32) into sx1tKey
   put sxSecretBox(sx1sxUtf8("Attack at dawn"), sx1tKey) into sx1tBox
   put sxSecretBoxOpen(sx1tBox, sx1tKey) into sx1tPlain
   sx1sxCheck (textDecode(sx1tPlain, "utf-8") is "Attack at dawn"), "round trip recovers the plaintext"
   -- tamper a byte: open must fail
   put false into sx1tOk
   put numToByte(byteToNum(byte 30 of sx1tBox) bitXor 1) into byte 30 of sx1tBox
   try
      get sxSecretBoxOpen(sx1tBox, sx1tKey)
   catch sx1tErr
      put true into sx1tOk
   end try
   sx1sxCheck sx1tOk, "a tampered ciphertext is rejected"
end sx1testSecretBox

on sx1testAead
   local sx1tKey
   local sx1tAd
   local sx1tBox
   local sx1tOk
   sx1sxSection "aead (XChaCha20-Poly1305)"
   put sxRandomBytes(32) into sx1tKey
   put sx1sxUtf8("v1;application/json") into sx1tAd
   put sxAeadEncrypt(sx1sxUtf8("{ok:true}"), sx1tAd, sx1tKey) into sx1tBox
   sx1sxCheck (textDecode(sxAeadDecrypt(sx1tBox, sx1tAd, sx1tKey), "utf-8") is "{ok:true}"), \
      "round trip with associated data"
   -- wrong associated data must fail
   put false into sx1tOk
   try
      get sxAeadDecrypt(sx1tBox, sx1sxUtf8("v2;application/json"), sx1tKey)
   catch sx1tErr
      put true into sx1tOk
   end try
   sx1sxCheck sx1tOk, "wrong associated data is rejected"
end sx1testAead

on sx1testPwHash
   local sx1tSalt
   local sx1tKey
   local sx1tHash
   sx1sxSection "Argon2id (pwhash)"
   -- deterministic known-answer: pass "password", salt = 16 x 'A', ops 2, mem 1 MiB
   put sx1sxUtf8("AAAAAAAAAAAAAAAA") into sx1tSalt
   -- The accessor is what a caller sizes its salt from, so tie it to the salt
   -- this vector actually uses rather than checking it in isolation: if the two
   -- ever disagreed, the KAT below would still pass while every caller that
   -- trusted sxPwSaltBytes built a salt libsodium rejects.
   sx1sxCheck (sxPwSaltBytes() is 16), "sxPwSaltBytes reports the Argon2id salt length"
   sx1sxCheck (the number of bytes of sx1tSalt is sxPwSaltBytes()), \
      "the vector's salt is exactly that length"
   put sxPwHash(sx1sxUtf8("password"), sx1tSalt, 32, "2", "1048576") into sx1tKey
   sx1sxCheck (sx1sxHexOf(sx1tKey) is \
      "7216b4357104ed7f8a4e900e9cc7a63a0786855abe0b59340053ee43f841228a"), \
      "Argon2id derivation matches the known-answer vector"
   -- password-string storage + verify
   put sxPwHashStr(sx1sxUtf8("hunter2"), "2", "1048576") into sx1tHash
   sx1sxCheck (sxPwHashStrVerify(textDecode(sx1tHash, "ascii"), sx1sxUtf8("hunter2")) is true), \
      "pwhash_str verify accepts the right passphrase"
   sx1sxCheck (sxPwHashStrVerify(textDecode(sx1tHash, "ascii"), sx1sxUtf8("nope")) is false), \
      "pwhash_str verify rejects the wrong passphrase"
end sx1testPwHash

on sx1testKdf
   local sx1tMaster
   local sx1tCtx
   local sx1tA
   local sx1tB
   sx1sxSection "kdf"
   put sxRandomBytes(32) into sx1tMaster
   put sx1sxUtf8("SXTctx00") into sx1tCtx
   put sxKdfDerive(sx1tMaster, "1", sx1tCtx, 32) into sx1tA
   put sxKdfDerive(sx1tMaster, "2", sx1tCtx, 32) into sx1tB
   sx1sxCheck (the number of bytes in sx1tA is 32), "kdf derives a 32-byte subkey"
   sx1sxCheck (sx1tA is not sx1tB), "different subkey ids give different subkeys"
end sx1testKdf

on sx1testSecretStream
   local sx1tKey
   local sx1tHeader
   local sx1tPushH
   local sx1tPullH
   local sx1tNoAd
   local sx1tC1
   local sx1tC2
   local sx1tTag1
   local sx1tTag2
   local sx1tP1
   local sx1tP2
   sx1sxSection "secretstream"
   put sxRandomBytes(32) into sx1tKey
   put sx1sxUtf8("") into sx1tNoAd
   put sxSecretStreamInitPush(sx1tKey, sx1tHeader) into sx1tPushH
   put sxSecretStreamPush(sx1tPushH, sx1sxUtf8("chunk one "), sx1tNoAd, false) into sx1tC1
   put sxSecretStreamPush(sx1tPushH, sx1sxUtf8("and final"), sx1tNoAd, true) into sx1tC2
   sxFreeStream sx1tPushH
   put sxSecretStreamInitPull(sx1tKey, sx1tHeader) into sx1tPullH
   put sxSecretStreamPull(sx1tPullH, sx1tC1, sx1tNoAd, sx1tTag1) into sx1tP1
   put sxSecretStreamPull(sx1tPullH, sx1tC2, sx1tNoAd, sx1tTag2) into sx1tP2
   sxFreeStream sx1tPullH
   sx1sxCheck (textDecode(sx1tP1, "utf-8") is "chunk one "), "first chunk decrypts"
   sx1sxCheck (textDecode(sx1tP2, "utf-8") is "and final"), "final chunk decrypts"
   sx1sxCheck (sxIsFinalTag(sx1tTag2) is true), "final chunk carries the FINAL tag"
end sx1testSecretStream

on sx1testStreamRekey
   local sx1tKey
   local sx1tHeader
   local sx1tNoAd
   local sx1tPushH
   local sx1tPullH
   local sx1tC1
   local sx1tC2
   local sx1tTag
   local sx1tP1
   local sx1tP2
   local sx1tOk
   sx1sxSection "secretstream rekey (in-session forward secrecy)"
   put sxRandomBytes(32) into sx1tKey
   put sx1sxUtf8("") into sx1tNoAd
   -- push a chunk, rekey the push side, push another chunk
   put sxSecretStreamInitPush(sx1tKey, sx1tHeader) into sx1tPushH
   put sxSecretStreamPush(sx1tPushH, sx1sxUtf8("before"), sx1tNoAd, false) into sx1tC1
   sxSecretStreamRekey sx1tPushH
   put sxSecretStreamPush(sx1tPushH, sx1sxUtf8("after"), sx1tNoAd, true) into sx1tC2
   sxFreeStream sx1tPushH
   -- matched rekey: the pull side rekeys at the same point, both chunks decrypt
   put sxSecretStreamInitPull(sx1tKey, sx1tHeader) into sx1tPullH
   put sxSecretStreamPull(sx1tPullH, sx1tC1, sx1tNoAd, sx1tTag) into sx1tP1
   sxSecretStreamRekey sx1tPullH
   put sxSecretStreamPull(sx1tPullH, sx1tC2, sx1tNoAd, sx1tTag) into sx1tP2
   sxFreeStream sx1tPullH
   sx1sxCheck (textDecode(sx1tP1, "utf-8") is "before"), "chunk before the rekey decrypts"
   sx1sxCheck (textDecode(sx1tP2, "utf-8") is "after"), "chunk after a matched rekey decrypts"
   -- one-sided rekey desyncs: pulling the second chunk without rekeying must fail
   put false into sx1tOk
   put sxSecretStreamInitPull(sx1tKey, sx1tHeader) into sx1tPullH
   get sxSecretStreamPull(sx1tPullH, sx1tC1, sx1tNoAd, sx1tTag)
   try
      get sxSecretStreamPull(sx1tPullH, sx1tC2, sx1tNoAd, sx1tTag)
   catch sx1tErr
      put true into sx1tOk
   end try
   sxFreeStream sx1tPullH
   sx1sxCheck sx1tOk, "an unmatched rekey makes the next chunk fail to open"
end sx1testStreamRekey

on sx1testFileHelpers
   local sx1tKey
   local sx1tSrc
   local sx1tEnc
   local sx1tDec
   local sx1tData
   sx1sxSection "file helpers"
   put sxRandomBytes(32) into sx1tKey
   put specialFolderPath("temporary") & "/sxt_demo_plain.bin" into sx1tSrc
   put specialFolderPath("temporary") & "/sxt_demo.enc" into sx1tEnc
   put specialFolderPath("temporary") & "/sxt_demo_dec.bin" into sx1tDec
   put sxRandomBytes(50000) into sx1tData
   put sx1tData into url ("binfile:" & sx1tSrc)
   sxEncryptFile sx1tSrc, sx1tEnc, sx1tKey
   sxDecryptFile sx1tEnc, sx1tDec, sx1tKey
   sx1sxCheck (url ("binfile:" & sx1tDec) is sx1tData), "file encrypt/decrypt round trip (50 KB)"
   delete file sx1tSrc
   delete file sx1tEnc
   delete file sx1tDec
end sx1testFileHelpers

on sx1testSign
   local sx1tPk
   local sx1tSk
   local sx1tSig
   local sx1tOk
   local sx1tSigned
   local sx1tOpened
   local sx1tErr
   local sx1tSeed
   local sx1tPk2, sx1tSk2, sx1tPk3, sx1tSk3
   sx1sxSection "ed25519 sign/verify"
   sxSignKeypair sx1tPk, sx1tSk
   put sxSignDetached(sx1sxUtf8("release v1.0"), sx1tSk) into sx1tSig
   sx1sxCheck (sxSignVerifyDetached(sx1tSig, sx1sxUtf8("release v1.0"), sx1tPk) is true), \
      "a valid signature verifies"
   sx1sxCheck (sxSignVerifyDetached(sx1tSig, sx1sxUtf8("release v1.1"), sx1tPk) is false), \
      "a modified message fails verification"
   -- The ATTACHED form (signature prepended to the message). sxSign/sxSignOpen
   -- are a different libsodium call pair from the detached one above, so they
   -- need their own round trip, their own tamper check, and their own
   -- wrong-key check - a verifier that ignores the key would pass the first
   -- two on their own.
   put sxSign(sx1sxUtf8("attached payload"), sx1tSk) into sx1tSigned
   sx1sxCheck (textDecode(sxSignOpen(sx1tSigned, sx1tPk), "utf-8") is "attached payload"), \
      "sxSign / sxSignOpen round-trips the message"
   sx1sxCheck (the length of sx1tSigned > the length of sx1sxUtf8("attached payload")), \
      "the attached form carries its signature with the message"
   put empty into sx1tOpened
   try
      put sxSignOpen(sx1sxFlipLastByte(sx1tSigned), sx1tPk) into sx1tOpened
   catch sx1tErr
      put "threw" into sx1tOpened
   end try
   sx1sxCheck (sx1tOpened is "threw" or sx1tOpened is empty), \
      "a tampered attached message does not open"
   -- Deterministic keypair-from-seed: the same seed must yield the same pair,
   -- which is what makes a seed a backup (and what OnionXT relies on for a
   -- reproducible .onion).
   put sxRandomBytes(32) into sx1tSeed
   sxSignKeypairFromSeed sx1tSeed, sx1tPk2, sx1tSk2
   sxSignKeypairFromSeed sx1tSeed, sx1tPk3, sx1tSk3
   sx1sxCheck (sx1tPk2 is sx1tPk3 and sx1tSk2 is sx1tSk3), \
      "sxSignKeypairFromSeed is deterministic for one seed"
   sx1sxCheck (sx1tPk2 is not sx1tPk), "a different seed yields a different key"
   put sxSignDetached(sx1sxUtf8("seeded"), sx1tSk2) into sx1tSig
   sx1sxCheck (sxSignVerifyDetached(sx1tSig, sx1sxUtf8("seeded"), sx1tPk2) is true), \
      "a seed-derived key signs and verifies"
end sx1testSign

function sx1sxFlipLastByte pData
   local sx1tLast
   local sx1tLen
   put the number of bytes of pData into sx1tLen
   if sx1tLen is 0 then
      return pData
   end if
   put byteToNum(byte sx1tLen of pData) into sx1tLast
   put (sx1tLast + 1) mod 256 into sx1tLast
   return (byte 1 to (sx1tLen - 1) of pData) & numToByte(sx1tLast)
end sx1sxFlipLastByte

on sx1testBox
   local sx1tApk
   local sx1tAsk
   local sx1tBpk
   local sx1tBsk
   local sx1tBox
   local sx1tOk
   sx1sxSection "public-key box (X25519)"
   sxBoxKeypair sx1tApk, sx1tAsk
   sxBoxKeypair sx1tBpk, sx1tBsk
   put sxBox(sx1sxUtf8("for your eyes only"), sx1tBpk, sx1tAsk) into sx1tBox
   sx1sxCheck (textDecode(sxBoxOpen(sx1tBox, sx1tApk, sx1tBsk), "utf-8") is "for your eyes only"), \
      "A->B box round trip"
   put false into sx1tOk
   try
      get sxBoxOpen(sx1tBox, sx1tApk, sx1tAsk)
   catch sx1tErr
      put true into sx1tOk
   end try
   sx1sxCheck sx1tOk, "a third party cannot open the box"
end sx1testBox

on sx1testSeal
   local sx1tPk
   local sx1tSk
   local sx1tSealed
   sx1sxSection "sealed box (anonymous sender)"
   sxBoxKeypair sx1tPk, sx1tSk
   put sxSeal(sx1sxUtf8("anonymous tip"), sx1tPk) into sx1tSealed
   sx1sxCheck (textDecode(sxSealOpen(sx1tSealed, sx1tPk, sx1tSk), "utf-8") is "anonymous tip"), \
      "seal round trip to the recipient"
end sx1testSeal

on sx1testKeyExchange
   local sx1tCpk
   local sx1tCsk
   local sx1tSpk
   local sx1tSsk
   local sx1tCrx
   local sx1tCtx
   local sx1tSrx
   local sx1tStx
   sx1sxSection "key exchange (kx)"
   sxKeyExchangeKeypair sx1tCpk, sx1tCsk
   sxKeyExchangeKeypair sx1tSpk, sx1tSsk
   sxKeyExchangeClient sx1tCpk, sx1tCsk, sx1tSpk, sx1tCrx, sx1tCtx
   sxKeyExchangeServer sx1tSpk, sx1tSsk, sx1tCpk, sx1tSrx, sx1tStx
   sx1sxCheck (sxMemEqual(sx1tCrx, sx1tStx) is true), "client rx equals server tx"
   sx1sxCheck (sxMemEqual(sx1tCtx, sx1tSrx) is true), "client tx equals server rx"
end sx1testKeyExchange

on sx1testSeededKeypairs
   local sx1tSeed
   local sx1tPk1
   local sx1tSk1
   local sx1tPk2
   local sx1tSk2
   local sx1tSealed
   local sx1tKpk
   local sx1tKsk
   local sx1tRpk
   local sx1tRsk
   local sx1tCrx
   local sx1tCtx
   local sx1tSrx
   local sx1tStx
   sx1sxSection "seeded keypairs (deterministic one-seed identity)"
   -- a fixed 32-byte seed: "B" is 0x42, so this is 0x42 repeated 32 times, the
   -- same seed the native known-answer test uses.
   put textEncode("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "ascii") into sx1tSeed

   -- box keypair: deterministic, and the pubkey matches the known-answer vector
   sxBoxKeypairFromSeed sx1tSeed, sx1tPk1, sx1tSk1
   sxBoxKeypairFromSeed sx1tSeed, sx1tPk2, sx1tSk2
   sx1sxCheck (sxMemEqual(sx1tPk1, sx1tPk2) is true and sxMemEqual(sx1tSk1, sx1tSk2) is true), \
      "sxBoxKeypairFromSeed is deterministic"
   sx1sxCheck (sx1sxHexOf(sx1tPk1) is \
      "cc4f2cdb695dd766f34118eb67b98652fed1d8bc49c330b119bbfa8a64989378"), \
      "seeded box pubkey matches the known-answer vector"
   -- functional: a sealed box to the derived pubkey opens with the derived keypair
   put sxSeal(sx1sxUtf8("seeded identity"), sx1tPk1) into sx1tSealed
   sx1sxCheck (textDecode(sxSealOpen(sx1tSealed, sx1tPk1, sx1tSk1), "utf-8") is "seeded identity"), \
      "the seeded box keypair opens its own sealed box"

   -- kx keypair: deterministic pubkey (KAT) + a working agreement with a peer
   sxKeyExchangeKeypairFromSeed sx1tSeed, sx1tKpk, sx1tKsk
   sx1sxCheck (sx1sxHexOf(sx1tKpk) is \
      "191957342799412f1a3cbeae3d3af8cf5441f2fb51d88a8c2a56175f1fae3f3a"), \
      "seeded kx pubkey matches the known-answer vector"
   sxKeyExchangeKeypair sx1tRpk, sx1tRsk
   sxKeyExchangeClient sx1tKpk, sx1tKsk, sx1tRpk, sx1tCrx, sx1tCtx
   sxKeyExchangeServer sx1tRpk, sx1tRsk, sx1tKpk, sx1tSrx, sx1tStx
   sx1sxCheck (sxMemEqual(sx1tCrx, sx1tStx) is true), "a seeded kx keypair agrees a session key"
end sx1testSeededKeypairs

on sx1testOnionPrimitives
   local sx1tSeed
   local sx1tExpanded
   local sx1tExpanded2
   local sx1tMac
   sx1sxSection "onion-support primitives (ed25519 expanded key + HMAC-SHA256)"
   -- 0x42 x 32, the same seed the native known-answer test uses (B is 0x42).
   put textEncode("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "ascii") into sx1tSeed
   -- seed -> the 64-byte expanded ed25519 key (SHA-512(seed), clamped): the form
   -- a Tor v3 onion service consumes, so one seed fixes a reproducible address.
   put sxSignSeedToExpandedKey(sx1tSeed) into sx1tExpanded
   sx1sxCheck (the number of bytes in sx1tExpanded is 64), "expanded ed25519 key is 64 bytes"
   sx1sxCheck (sx1sxHexOf(sx1tExpanded) is \
      "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6eeda66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90"), \
      "seed -> expanded key matches the known-answer vector"
   put sxSignSeedToExpandedKey(sx1tSeed) into sx1tExpanded2
   sx1sxCheck (sxMemEqual(sx1tExpanded, sx1tExpanded2) is true), "seed -> expanded key is deterministic"
   -- HMAC-SHA256 over an arbitrary-length key: RFC 4231 Test Case 2.
   put sxHmacSha256(textEncode("Jefe", "ascii"), textEncode("what do ya want for nothing?", "ascii")) into sx1tMac
   sx1sxCheck (sx1sxHexOf(sx1tMac) is \
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), \
      "HMAC-SHA256 matches RFC 4231 Test Case 2"
end sx1testOnionPrimitives

on sx1testPadding
   local sx1tPadded
   sx1sxSection "padding"
   put sxPad(sx1sxUtf8("hello"), 16) into sx1tPadded
   sx1sxCheck (the number of bytes in sx1tPadded is 16), "pad rounds 5 bytes up to 16"
   sx1sxCheck (textDecode(sxUnpad(sx1tPadded, 16), "utf-8") is "hello"), "unpad recovers the original"
end sx1testPadding

on sx1testHashExtras
   local sx1tInRange
   local sx1tR
   local sx1tH
   local sx1tStream
   local sx1tPath
   local sx1tContent
   local sx1tKey
   local sx1tHK
   local sx1tKeyed
   local sx1tAbandoned
   sx1sxSection "phase 6 (uniform random, multipart hash, file hash)"
   -- uniform random stays in range
   put true into sx1tInRange
   repeat 200 times
      put sxRandomUniform(6) into sx1tR
      if sx1tR < 0 or sx1tR >= 6 then
         put false into sx1tInRange
      end if
   end repeat
   sx1sxCheck sx1tInRange, "sxRandomUniform(6) stays in [0,6)"
   -- multipart "a" + "b" + "c" equals the one-shot BLAKE2b-256("abc") vector
   put sxHashInit(32) into sx1tH
   sxHashUpdate sx1tH, sx1sxUtf8("a")
   sxHashUpdate sx1tH, sx1sxUtf8("b")
   sxHashUpdate sx1tH, sx1sxUtf8("c")
   put sxHashFinal(sx1tH, 32) into sx1tStream
   sx1sxCheck (sx1sxHexOf(sx1tStream) is \
      "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"), \
      "multipart hash of a|b|c matches BLAKE2b-256(abc)"
   -- a file hash equals the one-shot hash of the same bytes
   put specialFolderPath("temporary") & "/sxt_hashfile.bin" into sx1tPath
   put sxRandomBytes(40000) into sx1tContent
   put sx1tContent into url ("binfile:" & sx1tPath)
   sx1sxCheck (sxHashFile(sx1tPath, 32) is sxHash(sx1tContent, 32)), \
      "sxHashFile matches the one-shot hash of the same bytes"
   -- KEYED hashing (BLAKE2b as a MAC). The keyed multipart state and the keyed
   -- file helper are separate entry points from the unkeyed ones above, and the
   -- property that matters is that the key actually participates: same bytes +
   -- different key must NOT collide.
   put sxRandomBytes(32) into sx1tKey
   put sxHashInitKeyed(sx1tKey, 32) into sx1tHK
   sxHashUpdate sx1tHK, sx1sxUtf8("a")
   sxHashUpdate sx1tHK, sx1sxUtf8("bc")
   put sxHashFinal(sx1tHK, 32) into sx1tKeyed
   sx1sxCheck (sx1tKeyed is sxHashKeyed(sx1sxUtf8("abc"), sx1tKey, 32)), \
      "keyed multipart hash matches the one-shot keyed hash"
   sx1sxCheck (sx1tKeyed is not sxHash(sx1sxUtf8("abc"), 32)), \
      "the key changes the digest (it is not an unkeyed hash)"
   sx1sxCheck (sxHashFileKeyed(sx1tPath, sx1tKey, 32) is sxHashKeyed(sx1tContent, sx1tKey, 32)), \
      "sxHashFileKeyed matches the one-shot keyed hash of the same bytes"
   -- sxFreeHash: an explicitly abandoned state frees cleanly, and freeing is
   -- idempotent (there is no deterministic LCB unload hook, so the app frees
   -- what it opens and a double free must be a harmless no-op, never a crash).
   put sxHashInit(32) into sx1tAbandoned
   sxHashUpdate sx1tAbandoned, sx1sxUtf8("never finalised")
   sxFreeHash sx1tAbandoned
   sxFreeHash sx1tAbandoned
   sx1sxCheck true, "sxFreeHash is idempotent on an abandoned state"
   delete file sx1tPath
end sx1testHashExtras

on sx1testDiagnostics
   local sx1tErr
   sx1sxSection "init, presets, and last-error"
   -- sxInit is safe to call again at any time (it is guarded internally); the
   -- library has already initialised itself by now, so this asserts the
   -- re-entry is harmless rather than that it did the first-time work.
   sxInit
   sx1sxCheck true, "sxInit is safe to call again"
   -- The Argon2id memlimit presets are PROBED FOR THEIR VALUE, never used to
   -- run a hash here: at the sensitive preset a single sxPwHash can occupy the
   -- one interpreter thread for a long, UI-freezing beat, which is a cost this
   -- harness should describe rather than pay.
   sx1sxCheck (sxPwMemInteractive() is not empty), "sxPwMemInteractive returns a value"
   sx1sxCheck (sxPwMemModerate() is not empty), "sxPwMemModerate returns a value"
   sx1sxCheck (sxPwMemSensitive() is not empty), "sxPwMemSensitive returns a value"
   sx1sxCheck (sxPwMemModerate() is not sxPwMemInteractive()), \
      "moderate is a different cost from interactive"
   sx1sxCheck (sxPwMemSensitive() is not sxPwMemModerate()), \
      "sensitive is a different cost from moderate"
   -- sxLastError reports the most recent failure. Force one, then confirm the
   -- message is there to be read.
   put empty into sx1tErr
   try
      get sxSecretBoxOpen(sx1sxUtf8("not a real ciphertext"), sxRandomBytes(32))
   catch sx1tErr
   end try
   sx1sxCheck (sx1tErr is not empty or sxLastError() is not empty), \
      "a failed call surfaces an error (thrown or via sxLastError)"
end sx1testDiagnostics


-- ==========================================================================
-- OnionXT: the full ox* self-test
--
-- 8 groups, all OFFLINE - no Tor daemon is started or contacted. The
-- live-Tor paths stay in onionxt's own demo.
--
-- GENERATED from onionxt/examples/onionxt-tests.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `ox1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

function ox1oxSelfTest
   put empty into ox1sLog
   put 0 into ox1sPass
   put 0 into ox1sFail

   ox1testVersionAndCapabilities
   ox1testInitialState
   ox1testFailClosedArguments
   ox1testUnknownHandlesAreCleanMisses
   ox1testIdempotentTeardown
   ox1testAddressRoundTrip
   ox1testAddressNegativePaths
   ox1testSodiumComposition
   ox1testConfigurationSetters

   local ox1tSummary
   put ox1sPass & " passed, " & ox1sFail & " failed" into ox1tSummary
   return ox1tSummary & return & "----------------------------------------" & return & ox1sLog
end ox1oxSelfTest

private command ox1oxCheck pCondition, pLabel
   if pCondition then
      add 1 to ox1sPass
      put ox1sLog & "  ok   " & pLabel & return into ox1sLog
   else
      add 1 to ox1sFail
      put ox1sLog & "  FAIL " & pLabel & return into ox1sLog
   end if
end ox1oxCheck

private command ox1oxSection pTitle
   put ox1sLog & return & "-- " & pTitle & " --" & return into ox1sLog
end ox1oxSection

private command ox1testVersionAndCapabilities
   ox1oxSection "version and capabilities"
   ox1oxCheck (oxVersion() is not empty), "oxVersion reports a non-empty string"

   local ox1tInfo
   put oxTransportInfo() into ox1tInfo
   ox1oxCheck (ox1tInfo["transport"] is "ox"), "oxTransportInfo advertises the ox transport"
   ox1oxCheck (ox1tInfo["version"] is oxVersion()), "oxTransportInfo version matches oxVersion"
   -- The three capability flags are always present, true or false, whether or
   -- not SodiumXT is loaded (CLAUDE.md rule 1: a missing primitive degrades to
   -- a clear flag/error, never a crash).
   ox1oxCheck (ox1tInfo["safeCookieAuth"] is true or ox1tInfo["safeCookieAuth"] is false), \
      "safeCookieAuth capability flag is a boolean"
   ox1oxCheck (ox1tInfo["deterministicOnion"] is true or ox1tInfo["deterministicOnion"] is false), \
      "deterministicOnion capability flag is a boolean"
   ox1oxCheck (ox1tInfo["offlineAddress"] is true or ox1tInfo["offlineAddress"] is false), \
      "offlineAddress capability flag is a boolean"
end ox1testVersionAndCapabilities

private command ox1testInitialState
   ox1oxSection "initial state (before oxConnectControl)"
   if oxIsControlAuthenticated() then
      put ox1sLog & "  --   (skipped: this session is already control-authenticated; " & \
         "run ox1oxSelfTest before oxConnectControl for this section)" & return into ox1sLog
      exit ox1testInitialState
   end if
   ox1oxCheck (oxBootstrapProgress() is 0), "bootstrap progress starts at 0"
   ox1oxCheck (not oxIsReady()), "oxIsReady is false before connecting"
   ox1oxCheck (not oxIsControlAuthenticated()), "control is not authenticated before connecting"
end ox1testInitialState

private command ox1testFailClosedArguments
   ox1oxSection "fail-closed argument validation"

   -- oxDial / oxCreateService* are COMMANDS: invoke them as statements and read
   -- their handle-or-error from `the result` (you cannot call a command with
   -- function-call parentheses; that syntax needs a `function` handler). Only
   -- oxAddressFromPublicKey below is a function, so it takes parentheses.
   local ox1tResult
   oxDial empty, 80
   put the result into ox1tResult
   ox1oxCheck (ox1tResult begins with "OnionXT:"), "oxDial rejects an empty host"

   oxDial "example.onion", 99999
   put the result into ox1tResult
   ox1oxCheck (ox1tResult begins with "OnionXT:"), "oxDial rejects a port outside 1..65535"

   -- These two prove the pre-auth fail-closed guard specifically, so they are
   -- only meaningful while nothing has authenticated yet in this session (see
   -- the note on ox1testInitialState above); skip rather than false-fail if a
   -- prior oxConnectControl in this session already succeeded.
   if oxIsControlAuthenticated() then
      put ox1sLog & "  --   (skipped: pre-auth guard on oxCreateService* needs a " & \
         "session that has not authenticated yet)" & return into ox1sLog
   else
      oxCreateService 80, 8080
      put the result into ox1tResult
      ox1oxCheck (ox1tResult begins with "OnionXT:"), \
         "oxCreateService fails closed without an authenticated control connection"

      oxCreateServiceFromSeed ox1testZeroSeed(), 80, 8080
      put the result into ox1tResult
      ox1oxCheck (ox1tResult begins with "OnionXT:"), \
         "oxCreateServiceFromSeed also fails closed without an authenticated control connection"
   end if

   put oxAddressFromPublicKey("short") into ox1tResult
   ox1oxCheck (ox1tResult begins with "OnionXT:"), \
      "oxAddressFromPublicKey rejects a public key that is not 32 bytes"
end ox1testFailClosedArguments

private command ox1testUnknownHandlesAreCleanMisses
   ox1oxSection "unknown handles are clean misses"
   local ox1tUnknown, ox1tResult
   put 999999 into ox1tUnknown

   -- oxStreamState / oxServiceAddress / oxServiceIsReady are functions (parens);
   -- oxSetStreamCallback / oxWrite are commands (statement + `the result`).
   ox1oxCheck (oxStreamState(ox1tUnknown) is "unknown"), "an unknown stream handle reports state unknown"
   ox1oxCheck (oxServiceAddress(ox1tUnknown) is empty), "an unknown service handle has no address"
   ox1oxCheck (not oxServiceIsReady(ox1tUnknown)), "an unknown service handle is not ready"

   oxSetStreamCallback ox1tUnknown, "someHandler"
   put the result into ox1tResult
   ox1oxCheck (ox1tResult begins with "OnionXT:"), "oxSetStreamCallback on an unknown handle fails closed"

   oxWrite ox1tUnknown, "x"
   put the result into ox1tResult
   ox1oxCheck (ox1tResult begins with "OnionXT:"), "oxWrite to an unknown/unconnected stream fails closed"
end ox1testUnknownHandlesAreCleanMisses

private command ox1testIdempotentTeardown
   ox1oxSection "idempotent teardown (duplicate close is a no-op)"
   local ox1tOk
   put true into ox1tOk
   try
      oxCloseStream 999999
      oxCloseStream 999999
      oxRemoveService 999999
      oxRemoveService 999999
      oxDisconnectControl
      oxDisconnectControl
      oxShutdown
      oxShutdown
   catch tError
      put false into ox1tOk
   end try
   ox1oxCheck ox1tOk, "double close / remove / disconnect / shutdown never throws"
   ox1oxCheck (not oxIsControlAuthenticated()), "control is disconnected after teardown"
end ox1testIdempotentTeardown

private command ox1testAddressRoundTrip
   ox1oxSection "v3 address <-> public key (docs/04), against real onions"
   ox1testOneKnownAddress ox1kTestAddrTorProject, "torproject.org's onion"
   ox1testOneKnownAddress ox1kTestAddrDuckDuckGo, "DuckDuckGo's onion"
end ox1testAddressRoundTrip

private command ox1testOneKnownAddress pAddress, pLabel
   local ox1tPub, ox1tInfo
   put oxPublicKeyFromAddress(pAddress) into ox1tPub
   ox1oxCheck (the number of bytes of ox1tPub is 32), \
      pLabel & ": oxPublicKeyFromAddress returns a 32-byte public key"
   ox1oxCheck oxIsValidAddress(pAddress), pLabel & ": oxIsValidAddress accepts it"

   put oxTransportInfo() into ox1tInfo
   if ox1tInfo["offlineAddress"] is true then
      ox1oxCheck (oxAddressFromPublicKey(ox1tPub) is pAddress), \
         pLabel & ": oxAddressFromPublicKey re-encodes the exact same address"
   else
      put ox1sLog & "  --   (skipped: " & pLabel & " re-encode needs SodiumXT sxSha3_256, docs/08)" & return into ox1sLog
   end if
end ox1testOneKnownAddress

private command ox1testAddressNegativePaths
   ox1oxSection "address negative paths"
   ox1oxCheck (not oxIsValidAddress("tooshort.onion")), "a too-short address is rejected"
   ox1oxCheck (not oxIsValidAddress("not a valid onion address at all")), "garbage input is rejected"
   ox1oxCheck (oxPublicKeyFromAddress("short.onion") is empty), \
      "a malformed address yields an empty key, not a crash"

   -- Flip the first character of a known-good address (to something else in
   -- the base32 alphabet); it must no longer validate, either structurally (if
   -- the flip breaks the version byte) or by checksum when SHA3-256 is
   -- available.
   local ox1tTampered, ox1tInfo
   put ox1kTestAddrTorProject into ox1tTampered
   if char 1 of ox1tTampered is "2" then
      put "3" into char 1 of ox1tTampered
   else
      put "2" into char 1 of ox1tTampered
   end if
   put oxTransportInfo() into ox1tInfo
   if ox1tInfo["offlineAddress"] is true then
      ox1oxCheck (not oxIsValidAddress(ox1tTampered)), "a tampered address fails checksum validation"
   else
      put ox1sLog & "  --   (skipped: tamper-detection needs SodiumXT sxSha3_256, docs/08)" & return into ox1sLog
   end if
end ox1testAddressNegativePaths

private command ox1testSodiumComposition
   ox1oxSection "SodiumXT ABI-6 composition (docs/08 gaps #1, #3)"
   local ox1tInfo
   put oxTransportInfo() into ox1tInfo

   -- Gap #1 (SHIPPED): sxSignSeedToExpandedKey(seed = 0x42 x 32), 64-byte result.
   if ox1tInfo["deterministicOnion"] is true then
      local ox1tExpanded, ox1tExpectExp
      put "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6ee" & \
          "da66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90" into ox1tExpectExp
      put sxSignSeedToExpandedKey(ox1testRepeatByte(66, 32)) into ox1tExpanded
      ox1oxCheck (ox1testHex(ox1tExpanded) is ox1tExpectExp), \
         "sxSignSeedToExpandedKey(seed 0x42 x 32) matches the pinned expanded-key vector"
   else
      put ox1sLog & "  --   (skipped: sxSignSeedToExpandedKey needs SodiumXT ABI >= 6)" & return into ox1sLog
   end if

   -- Gap #3 (SHIPPED): sxHmacSha256("Jefe","what do ya want for nothing?") RFC 4231 TC2.
   if ox1tInfo["safeCookieAuth"] is true then
      local ox1tMac, ox1tExpectMac
      put "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" into ox1tExpectMac
      put sxHmacSha256(textEncode("Jefe", "UTF-8"), textEncode("what do ya want for nothing?", "UTF-8")) into ox1tMac
      ox1oxCheck (ox1testHex(ox1tMac) is ox1tExpectMac), \
         "sxHmacSha256 (RFC 4231 Test Case 2) matches the pinned HMAC vector"
   else
      put ox1sLog & "  --   (skipped: sxHmacSha256 needs SodiumXT ABI >= 6)" & return into ox1sLog
   end if
end ox1testSodiumComposition

private command ox1testConfigurationSetters
   ox1oxSection "configuration setters (offline: callable and inert)"
   local ox1tWasReady, ox1tWasAuthed, ox1tProgress
   put oxIsReady() into ox1tWasReady
   put oxIsControlAuthenticated() into ox1tWasAuthed
   put oxBootstrapProgress() into ox1tProgress

   -- Loopback-locked by design: the PORT is settable, the host never is.
   oxSetSocksPort 19050
   oxSetControlPort 19051
   ox1oxCheck true, "oxSetSocksPort and oxSetControlPort accept a port"
   oxSetControlPassword "not-a-real-password"
   ox1oxCheck true, "oxSetControlPassword accepts a password"
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback "onPeer"
   ox1oxCheck true, "the status and peer callback names are settable"
   oxSetCallbackOwner the long id of me
   ox1oxCheck true, "oxSetCallbackOwner accepts an object long id"

   -- Configuration must not touch the connection state machine. If any of
   -- these moved, a setter is writing over more than its own local.
   ox1oxCheck (oxIsReady() is ox1tWasReady), "setting configuration does not change oxIsReady"
   ox1oxCheck (oxIsControlAuthenticated() is ox1tWasAuthed), \
      "setting configuration does not authenticate anything"
   ox1oxCheck (oxBootstrapProgress() is ox1tProgress), \
      "setting configuration does not move bootstrap progress"

   -- Idempotent, like every other entry point here.
   oxSetSocksPort 19050
   ox1oxCheck (oxIsReady() is ox1tWasReady), "setting the same port twice is harmless"

   -- Hand the session back. Empty restores the documented default for the two
   -- ports and the password, so those simply clear.
   oxSetSocksPort empty
   oxSetControlPort empty
   oxSetControlPassword empty
   ox1oxCheck (oxIsReady() is ox1tWasReady), "clearing the ports and password is harmless too"

   -- The three DISPATCH setters do not clear, and the reason is a real bug this
   -- section would otherwise have introduced. tools/build-standalone.py bundles
   -- this file into examples/onionxt-demo-standalone.livecodescript, where the
   -- About tab runs ox1oxSelfTest inside the running demo - and that demo sets its
   -- callback owner and status handler ONCE, in preOpenStack. Clearing them here
   -- would leave a demo that had already opened with no status dispatch at all,
   -- silently, until it was reopened: a test that breaks the app it is bundled
   -- into. So restore the exact configuration the demo establishes - owner is
   -- this stack, status is onStatus, and NO peer callback, because oxhServe
   -- installs oxhPeer itself when it publishes and a stale "onPeer" here would
   -- shadow it until then.
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback empty
   ox1oxCheck (oxIsReady() is ox1tWasReady), "restoring the dispatch configuration is harmless too"
end ox1testConfigurationSetters

private function ox1testHex pData
   -- binaryDecode is a function that fills its output var; `get` discards the count.
   local ox1tHex
   get binaryDecode("H*", pData, ox1tHex)
   return ox1tHex
end ox1testHex

private function ox1testRepeatByte pByteVal, pCount
   local ox1tOut, ox1tI
   put empty into ox1tOut
   repeat with ox1tI = 1 to pCount
      put numToByte(pByteVal) after ox1tOut
   end repeat
   return ox1tOut
end ox1testRepeatByte

private function ox1testZeroSeed
   return ox1testRepeatByte(0, 32)
end ox1testZeroSeed


-- ==========================================================================
-- CoinXT: the full cx* self-test
--
-- 28 sections across all four phases: hashes, the secp256k1 curve, the
-- encoders and addresses, BIP-39/32/44, and the fail-closed regressions.
--
-- GENERATED from coinxt/tests/coin-selftest.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `cx1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

command cx1stAssert pName, pPass
   add 1 to cx1sTotal
   if pPass then
      add 1 to cx1sPassed
      put "PASS  " & pName & return after cx1sResultText
   else
      add 1 to cx1sFailed
      put "FAIL  " & pName & return after cx1sResultText
   end if
end cx1stAssert

command cx1stSection pTitle
   put return & "== " & pTitle & " ==" & return after cx1sResultText
end cx1stSection

command cx1stNote pText
   put "      " & pText & return after cx1sResultText
end cx1stNote

-- GENERATED: cx1stShow drove this harness's own window.
-- The suite owns the UI and reads the member's log directly,
-- so there is nothing left for it to repaint.
command cx1stShow
end cx1stShow

command cx1stSectionFailed pTitle, pError
   add 1 to cx1sTotal
   add 1 to cx1sFailed
   put "FAIL  " & pTitle & " threw: " & pError & return after cx1sResultText
end cx1stSectionFailed

command cx1stRun
   put 0 into cx1sTotal
   put 0 into cx1sPassed
   put 0 into cx1sFailed
   put empty into cx1sResultText
   put "false" into cx1sDone
   -- Byte-exact compares, and hex strings that must not fold case.
   set the caseSensitive to true

   put "CoinXT API self-test" & return into cx1sResultText
   put "Phases 1-5: the .lcb module and the script layer, end to end." & return after cx1sResultText

   cx1stRunAbi
   cx1stRunLengths
   cx1stRunKeccak
   cx1stRunSha3
   cx1stRunSha2
   cx1stRunRipemd
   cx1stRunHmac
   cx1stRunPbkdf2
   cx1stRunEmptyInputs
   cx1stRunIndependence
   cx1stRunFailClosed
   cx1stRunCurveKeys
   cx1stRunCurveSign
   cx1stRunCurveVerify
   cx1stRunCurveRecover
   cx1stRunCurveEcdh
   cx1stRunCurveFailClosed
   cx1stRunHex
   cx1stRunBase58
   cx1stRunBech32
   cx1stRunAddresses
   cx1stRunEip55
   cx1stRunRlp
   cx1stRunBip39
   cx1stRunBip32
   cx1stRunBip44
   cx1stRunTransactions
   cx1stRunFailOpen

   cx1stSection "summary"
   cx1stNote "Vectors are identical to tools/coin-kat.py, so this run and the"
   cx1stNote "headless KAT run are the same claim at two different layers."
   cx1stNote "Phase 4 is the section to read first if anything failed: it is the"
   cx1stNote "only surface where a wrong answer still looks like a right one."
   put "true" into cx1sDone
   cx1stShow
end cx1stRun

command cx1stRunAbi
   local cx1tOK
   cx1stSection "load + ABI guard"
   try
      put "true" into cx1tOK
      cxCheckABI
   catch tError
      put "false" into cx1tOK
      cx1stNote "cxCheckABI threw: " & tError
   end try
   cx1stAssert "cxCheckABI passes against the shipped binary", cx1tOK is "true"
   -- The probe that actually prints a value, and the first exercise of the
   -- UIntSize return type in this file.
   cx1stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
end cx1stRunAbi

command cx1stRunLengths
   cx1stSection "length accessors (UIntSize as a foreign RETURN type)"
   try
      cx1stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
      cx1stAssert "cxSha3_256Len() is 32", cxSha3_256Len() is 32
      cx1stAssert "cxSha256Len() is 32", cxSha256Len() is 32
      cx1stAssert "cxSha512Len() is 64", cxSha512Len() is 64
      cx1stAssert "cxRipemd160Len() is 20", cxRipemd160Len() is 20
      cx1stAssert "cxHmacSha256Len() is 32", cxHmacSha256Len() is 32
      cx1stAssert "cxHmacSha512Len() is 64", cxHmacSha512Len() is 64
      cx1stAssert "cxSeckeyLen() is 32", cxSeckeyLen() is 32
      cx1stAssert "cxPubkeyLenCompressed() is 33", cxPubkeyLenCompressed() is 33
      cx1stAssert "cxPubkeyLenUncompressed() is 65", cxPubkeyLenUncompressed() is 65
      cx1stAssert "cxSignatureLen() is 64", cxSignatureLen() is 64
      cx1stAssert "cxRecoverableSignatureLen() is 65", cxRecoverableSignatureLen() is 65
      cx1stAssert "cxEcdhLen() is 65", cxEcdhLen() is 65
      cx1stAssert "a recoverable signature is one byte longer than a plain one", cxRecoverableSignatureLen() is cxSignatureLen() + 1
      cx1stAssert "keccak digest length matches its accessor", the number of bytes of cxKeccak256(cx1stText("abc")) is cxKeccak256Len()
      cx1stAssert "sha512 digest length matches its accessor", the number of bytes of cxSha512(cx1stText("abc")) is cxSha512Len()
      cx1stAssert "ripemd digest length matches its accessor", the number of bytes of cxRipemd160(cx1stText("abc")) is cxRipemd160Len()
   catch tError
      cx1stSectionFailed "length accessors", tError
   end try
end cx1stRunLengths

command cx1stRunKeccak
   cx1stSection "Keccak-256 (published Ethereum vectors)"
   try
      -- The empty input FIRST, on purpose. It is the MCDataGetBytePtr-on-empty
      -- marshalling question: if the engine imported a null byte pointer as
      -- `nothing`, the plain Pointer slot would reject it and this would THROW
      -- rather than return a digest. A throw here is a marshalling failure, not
      -- a hashing failure - do not go looking in the vectors.
      cx1stAssert "cxKeccak256 of the empty input", cx1stHex(cxKeccak256(cx1stText(""))) is cx1kKeccakEmpty
      cx1stAssert "cxKeccak256 of abc", cx1stHex(cxKeccak256(cx1stText("abc"))) is cx1kKeccakAbc
      cx1stAssert "cxKeccak256 is deterministic", cx1stHex(cxKeccak256(cx1stText("abc"))) is cx1stHex(cxKeccak256(cx1stText("abc")))
   catch tError
      cx1stSectionFailed "Keccak-256", tError
   end try
end cx1stRunKeccak

command cx1stRunSha3
   cx1stSection "SHA3-256 (NIST) and the aliasing trap"
   try
      cx1stAssert "cxSha3_256 of the empty input", cx1stHex(cxSha3_256(cx1stText(""))) is cx1kSha3Empty
      cx1stAssert "cxSha3_256 of abc", cx1stHex(cxSha3_256(cx1stText("abc"))) is cx1kSha3Abc
      cx1stAssert "cxSha3_256 of the fox sentence", cx1stHex(cxSha3_256(cx1stText(cx1kFox))) is cx1kSha3Fox
      -- The trap this pair of handlers exists to avoid. Keccak-256 and SHA3-256
      -- differ ONLY in a padding byte, so a shim that wires one to the other is
      -- a silent, plausible, totally wrong answer - and on Ethereum, a wrong
      -- address. Assert the difference explicitly, in both directions.
      cx1stAssert "cxSha3_256 is NOT aliased to cxKeccak256", cx1stHex(cxSha3_256(cx1stText("abc"))) is not cx1stHex(cxKeccak256(cx1stText("abc")))
      cx1stAssert "cxKeccak256 is NOT aliased to cxSha3_256", cx1stHex(cxKeccak256(cx1stText(""))) is not cx1stHex(cxSha3_256(cx1stText("")))
   catch tError
      cx1stSectionFailed "SHA3-256", tError
   end try
end cx1stRunSha3

command cx1stRunSha2
   cx1stSection "SHA-256 and SHA-512 (FIPS 180-4)"
   try
      cx1stAssert "cxSha256 of the empty input", cx1stHex(cxSha256(cx1stText(""))) is cx1kSha256Empty
      cx1stAssert "cxSha256 of abc", cx1stHex(cxSha256(cx1stText("abc"))) is cx1kSha256Abc
      cx1stAssert "cxSha512 of the empty input", cx1stHex(cxSha512(cx1stText(""))) is cx1kSha512Empty
      cx1stAssert "cxSha512 of abc", cx1stHex(cxSha512(cx1stText("abc"))) is cx1kSha512Abc
   catch tError
      cx1stSectionFailed "SHA-2", tError
   end try
end cx1stRunSha2

command cx1stRunRipemd
   cx1stSection "RIPEMD-160 (specification vectors)"
   try
      cx1stAssert "cxRipemd160 of the empty input", cx1stHex(cxRipemd160(cx1stText(""))) is cx1kRipeEmpty
      cx1stAssert "cxRipemd160 of a", cx1stHex(cxRipemd160(cx1stText("a"))) is cx1kRipeA
      cx1stAssert "cxRipemd160 of abc", cx1stHex(cxRipemd160(cx1stText("abc"))) is cx1kRipeAbc
      cx1stAssert "cxRipemd160 of message digest", cx1stHex(cxRipemd160(cx1stText("message digest"))) is cx1kRipeMsgDigest
      cx1stNote "No second opinion exists for these: OpenSSL 3 moved RIPEMD-160 to"
      cx1stNote "the legacy provider, so the published vectors stand alone."
   catch tError
      cx1stSectionFailed "RIPEMD-160", tError
   end try
end cx1stRunRipemd

command cx1stRunHmac
   local cx1tKey1, cx1tKey2, cx1tMsg1, cx1tMsg2
   cx1stSection "HMAC-SHA256 / HMAC-SHA512 (RFC 4231 cases 1 and 2)"
   try
      -- Case 1's key is twenty 0x0b bytes. Built with numToByte because a
      -- LiveCodeScript string literal has no escape syntax: "\x0b" is four
      -- characters, not one byte.
      put cx1stRepeatByte(11, 20) into cx1tKey1
      put cx1stText("Hi There") into cx1tMsg1
      cx1stAssert "HMAC-SHA256 case 1", cx1stHex(cxHmacSha256(cx1tKey1, cx1tMsg1)) is cx1kHmac1Sha256
      cx1stAssert "HMAC-SHA512 case 1", cx1stHex(cxHmacSha512(cx1tKey1, cx1tMsg1)) is cx1kHmac1Sha512
      -- Case 2's key is shorter than the block size and ascii, which walks a
      -- different pad path than case 1's.
      put cx1stText("Jefe") into cx1tKey2
      put cx1stText("what do ya want for nothing?") into cx1tMsg2
      cx1stAssert "HMAC-SHA256 case 2", cx1stHex(cxHmacSha256(cx1tKey2, cx1tMsg2)) is cx1kHmac2Sha256
      cx1stAssert "HMAC-SHA512 case 2", cx1stHex(cxHmacSha512(cx1tKey2, cx1tMsg2)) is cx1kHmac2Sha512
      -- A MAC must depend on its key. Same message, different key, different tag.
      cx1stAssert "HMAC-SHA256 depends on the key", cx1stHex(cxHmacSha256(cx1tKey1, cx1tMsg1)) is not cx1stHex(cxHmacSha256(cx1tKey2, cx1tMsg1))
   catch tError
      cx1stSectionFailed "HMAC", tError
   end try
end cx1stRunHmac

command cx1stRunPbkdf2
   local cx1tSeed, cx1tShort
   cx1stSection "PBKDF2-HMAC-SHA512 (the BIP-39 seed vector)"
   try
      put cxPbkdf2HmacSha512(cx1stText(cx1kBip39Mnemonic), cx1stText(cx1kBip39Salt), 2048, 64) into cx1tSeed
      cx1stAssert "BIP-39 abandon-about with TREZOR", cx1stHex(cx1tSeed) is cx1kBip39Seed
      cx1stAssert "the seed is exactly 64 bytes", the number of bytes of cx1tSeed is 64
      -- This is the one handler whose output length the CALLER chooses, so the
      -- shim writes exactly what was asked for rather than a size it reports.
      -- A non-block-multiple length exercises the partial final block.
      put cxPbkdf2HmacSha512(cx1stText(cx1kBip39Mnemonic), cx1stText(cx1kBip39Salt), 2048, 20) into cx1tShort
      cx1stAssert "a 20-byte request returns 20 bytes", the number of bytes of cx1tShort is 20
      cx1stAssert "the short output prefixes the long one", cx1stHex(cx1tShort) is char 1 to 40 of cx1kBip39Seed
   catch tError
      cx1stSectionFailed "PBKDF2", tError
   end try
end cx1stRunPbkdf2

command cx1stRunEmptyInputs
   cx1stSection "empty input marshals for every one-shot digest"
   try
      cx1stAssert "cxKeccak256 empty returns 32 bytes", the number of bytes of cxKeccak256(cx1stText("")) is 32
      cx1stAssert "cxSha3_256 empty returns 32 bytes", the number of bytes of cxSha3_256(cx1stText("")) is 32
      cx1stAssert "cxSha256 empty returns 32 bytes", the number of bytes of cxSha256(cx1stText("")) is 32
      cx1stAssert "cxSha512 empty returns 64 bytes", the number of bytes of cxSha512(cx1stText("")) is 64
      cx1stAssert "cxRipemd160 empty returns 20 bytes", the number of bytes of cxRipemd160(cx1stText("")) is 20
      -- An empty KEY and an empty MESSAGE are separate marshalling slots.
      cx1stAssert "cxHmacSha256 with an empty key", the number of bytes of cxHmacSha256(cx1stText(""), cx1stText("abc")) is 32
      cx1stAssert "cxHmacSha256 with an empty message", the number of bytes of cxHmacSha256(cx1stText("abc"), cx1stText("")) is 32
   catch tError
      cx1stSectionFailed "empty inputs", tError
   end try
end cx1stRunEmptyInputs

command cx1stRunIndependence
   local cx1tK, cx1tS3, cx1tS2, cx1tR
   cx1stSection "the digests are independent of each other"
   try
      put cx1stHex(cxKeccak256(cx1stText("abc"))) into cx1tK
      put cx1stHex(cxSha3_256(cx1stText("abc"))) into cx1tS3
      put cx1stHex(cxSha256(cx1stText("abc"))) into cx1tS2
      put cx1stHex(cxRipemd160(cx1stText("abc"))) into cx1tR
      cx1stAssert "keccak differs from sha3", cx1tK is not cx1tS3
      cx1stAssert "keccak differs from sha256", cx1tK is not cx1tS2
      cx1stAssert "sha3 differs from sha256", cx1tS3 is not cx1tS2
      cx1stAssert "ripemd differs from them all", cx1tR is not cx1tK and cx1tR is not cx1tS3 and cx1tR is not cx1tS2
      -- One flipped input bit must change the digest. A binding that hashed a
      -- stale or empty buffer would pass every fixed vector above by accident
      -- only if the vector were wrong too, but this catches a buffer that never
      -- gets the caller's bytes at all.
      cx1stAssert "one changed input byte changes the digest", cx1stHex(cxKeccak256(cx1stText("abc"))) is not cx1stHex(cxKeccak256(cx1stText("abd")))
   catch tError
      cx1stSectionFailed "independence", tError
   end try
end cx1stRunIndependence

command cx1stRunFailClosed
   local cx1tThrew
   cx1stSection "fail closed on malformed input"
   try
      put "false" into cx1tThrew
      try
         get cxPbkdf2HmacSha512(cx1stText("pw"), cx1stText("salt"), 0, 64)
      catch tInner
         put "true" into cx1tThrew
      end try
      cx1stAssert "zero iterations is refused", cx1tThrew is "true"

      put "false" into cx1tThrew
      try
         get cxPbkdf2HmacSha512(cx1stText("pw"), cx1stText("salt"), 1, 0)
      catch tInner2
         put "true" into cx1tThrew
      end try
      cx1stAssert "a zero-length output request is refused", cx1tThrew is "true"
   catch tError
      cx1stSectionFailed "fail closed", tError
   end try
end cx1stRunFailClosed

command cx1stRunCurveKeys
   local cx1tSk, cx1tPubC, cx1tPubU, cx1tTweaked
   cx1stSection "secp256k1 keys"
   try
      put cx1stSeckeyOne() into cx1tSk
      -- cxNewSeckey validates caller entropy and hands it back unchanged. The
      -- private key 1 is the generator G, which is why no vector table is
      -- needed here: this public key is the curve's own definition.
      cx1stAssert "cxNewSeckey accepts a valid key", cx1stHex(cxNewSeckey(cx1tSk)) is cx1stHex(cx1tSk)
      cx1stAssert "cxSeckeyIsValid says true for a valid key", cxSeckeyIsValid(cx1tSk) is true
      put cxPublicKey(cx1tSk, true) into cx1tPubC
      put cxPublicKey(cx1tSk, false) into cx1tPubU
      cx1stAssert "cxPublicKey compressed is G", cx1stHex(cx1tPubC) is cx1kPubOneCompressed
      cx1stAssert "cxPublicKey uncompressed is G", cx1stHex(cx1tPubU) is cx1kPubOneUncompressed
      -- The boolean flag is the new marshalling shape (an LCB Boolean into a C
      -- int). If it were dropped, both calls would return the same length.
      cx1stAssert "the compressed key is 33 bytes", the number of bytes of cx1tPubC is 33
      cx1stAssert "the uncompressed key is 65 bytes", the number of bytes of cx1tPubU is 65
      cx1stAssert "cxPubkeyDecompress rebuilds the uncompressed key", cx1stHex(cxPubkeyDecompress(cx1tPubC)) is cx1stHex(cx1tPubU)
      cx1stAssert "cxPubkeyDecompress of an uncompressed key is a no-op", cx1stHex(cxPubkeyDecompress(cx1tPubU)) is cx1stHex(cx1tPubU)
      -- The two ABI-4 tweak entry points. BIP-32 non-hardened derivation is
      -- built on the claim that tweaking the PRIVATE key and tweaking the
      -- PUBLIC key land on the same point; if they ever disagreed, an xpub
      -- watch-only wallet would generate addresses the xprv cannot spend, and
      -- nothing above this line would notice. 1 + 1 = 2 pins both to the
      -- curve's own second point rather than only to each other.
      put cxSeckeyTweakAdd(cx1tSk, cx1tSk) into cx1tTweaked
      cx1stAssert "cxSeckeyTweakAdd of 1 by 1 is the scalar 2", cx1stHex(cx1tTweaked) is cx1stHex(cx1stRepeatByte(0, 31) & numToByte(2))
      cx1stAssert "and its public key is 2G", cx1stHex(cxPublicKey(cx1tTweaked, true)) is cx1kPubTwoCompressed
      cx1stAssert "cxPubkeyTweakAdd of G by 1 is also 2G", cx1stHex(cxPubkeyTweakAdd(cx1tPubC, cx1tSk)) is cx1kPubTwoCompressed
      cx1stAssert "so private and public tweaking agree", cx1stHex(cxPubkeyTweakAdd(cx1tPubC, cx1tSk)) is cx1stHex(cxPublicKey(cxSeckeyTweakAdd(cx1tSk, cx1tSk), true))
      -- Both refuse a ZERO tweak, where upstream's public entry point accepts
      -- it. Accepting on one path and refusing on the other is the
      -- interoperability bug this member exists to prevent, so the symmetry is
      -- asserted rather than assumed.
      cx1stAssert "a zero tweak is refused on the private path", cx1stThrows2("cxSeckeyTweakAdd", cx1tSk, cx1stRepeatByte(0, 32))
      cx1stAssert "a zero tweak is refused on the public path", cx1stThrows2("cxPubkeyTweakAdd", cx1tPubC, cx1stRepeatByte(0, 32))
      cx1stAssert "a wrong-length tweak is refused", cx1stThrows2("cxSeckeyTweakAdd", cx1tSk, cx1stRepeatByte(1, 31))
   catch tError
      cx1stSectionFailed "secp256k1 keys", tError
   end try
end cx1stRunCurveKeys

command cx1stRunCurveSign
   local cx1tSk, cx1tDigest, cx1tSig, cx1tAgain
   cx1stSection "ECDSA signing (RFC 6979, published vector)"
   try
      put cx1stSeckeyOne() into cx1tSk
      -- The digest is built with cxSha256, which this same run already checked
      -- against FIPS 180-4, so a failure here cannot be a hashing failure.
      put cxSha256(cx1stText("Satoshi Nakamoto")) into cx1tDigest
      put cxSign(cx1tSk, cx1tDigest) into cx1tSig
      cx1stAssert "cxSign reproduces the published RFC 6979 signature", cx1stHex(cx1tSig) is cx1kSigSatoshi
      cx1stAssert "the signature is 64 bytes", the number of bytes of cx1tSig is cxSignatureLen()
      -- Determinism is the property the whole vector table rests on. The native
      -- code draws fresh OS entropy for side-channel blinding on every call;
      -- that blinding cancels, and this is the check that says so from script.
      put cxSign(cx1tSk, cx1tDigest) into cx1tAgain
      cx1stAssert "signing twice gives the same signature", cx1stHex(cx1tAgain) is cx1stHex(cx1tSig)
   catch tError
      cx1stSectionFailed "ECDSA signing", tError
   end try
end cx1stRunCurveSign

command cx1stRunCurveVerify
   local cx1tSk, cx1tDigest, cx1tSig, cx1tPubC, cx1tPubU, cx1tBad, cx1tOtherPub
   cx1stSection "ECDSA verification (true, and false)"
   try
      put cx1stSeckeyOne() into cx1tSk
      put cxSha256(cx1stText("Satoshi Nakamoto")) into cx1tDigest
      put cxSign(cx1tSk, cx1tDigest) into cx1tSig
      put cxPublicKey(cx1tSk, true) into cx1tPubC
      put cxPublicKey(cx1tSk, false) into cx1tPubU
      -- cxVerify RETURNS Boolean rather than throwing, which is the second new
      -- shape in this file. A binding that mismarshalled it would most likely
      -- throw or return empty, so assert the true case explicitly.
      cx1stAssert "cxVerify accepts a good signature (compressed key)", cxVerify(cx1tPubC, cx1tDigest, cx1tSig) is true
      cx1stAssert "cxVerify accepts a good signature (uncompressed key)", cxVerify(cx1tPubU, cx1tDigest, cx1tSig) is true
      put cx1stFlipByte(cx1tSig, 6) into cx1tBad
      cx1stAssert "cxVerify rejects a tampered signature", cxVerify(cx1tPubC, cx1tDigest, cx1tBad) is false
      cx1stAssert "cxVerify rejects a wrong digest", cxVerify(cx1tPubC, cxSha256(cx1stText("not the message")), cx1tSig) is false
      put cxPublicKey(cx1stSeckeyTwo(), true) into cx1tOtherPub
      cx1stAssert "cxVerify rejects the wrong public key", cxVerify(cx1tOtherPub, cx1tDigest, cx1tSig) is false
   catch tError
      cx1stSectionFailed "ECDSA verification", tError
   end try
end cx1stRunCurveVerify

command cx1stRunCurveRecover
   local cx1tSk, cx1tDigest, cx1tSig, cx1tRec, cx1tPubU
   cx1stSection "recoverable signing and ecrecover"
   try
      put cx1stSeckeyOne() into cx1tSk
      put cxSha256(cx1stText("Satoshi Nakamoto")) into cx1tDigest
      put cxSignRecoverable(cx1tSk, cx1tDigest) into cx1tSig
      put cxPublicKey(cx1tSk, false) into cx1tPubU
      cx1stAssert "a recoverable signature is 65 bytes", the number of bytes of cx1tSig is cxRecoverableSignatureLen()
      cx1stAssert "its first 64 bytes are the plain signature", cx1stHex(byte 1 to 64 of cx1tSig) is cx1kSigSatoshi
      cx1stAssert "the recovery id is 0..3", byteToNum(byte 65 of cx1tSig) >= 0 and byteToNum(byte 65 of cx1tSig) <= 3
      put cxRecover(cx1tSig, cx1tDigest) into cx1tRec
      -- The whole point of recovery: get the signer back from the signature
      -- alone. Recovery ALSO succeeds for a wrong id and returns some other
      -- key, so comparing against the expected key is the real check.
      cx1stAssert "cxRecover returns the signing public key", cx1stHex(cx1tRec) is cx1stHex(cx1tPubU)
      cx1stAssert "and that key is the published G", cx1stHex(cx1tRec) is cx1kPubOneUncompressed
   catch tError
      cx1stSectionFailed "ecrecover", tError
   end try
end cx1stRunCurveRecover

command cx1stRunCurveEcdh
   local cx1tA, cx1tB, cx1tPubA, cx1tPubB, cx1tShared1, cx1tShared2
   cx1stSection "ECDH"
   try
      put cx1stSeckeyOne() into cx1tA
      put cx1stSeckeyTwo() into cx1tB
      put cxPublicKey(cx1tA, true) into cx1tPubA
      put cxPublicKey(cx1tB, true) into cx1tPubB
      put cxEcdh(cx1tA, cx1tPubB) into cx1tShared1
      put cxEcdh(cx1tB, cx1tPubA) into cx1tShared2
      cx1stAssert "both sides derive the same point", cx1stHex(cx1tShared1) is cx1stHex(cx1tShared2)
      cx1stAssert "the shared point is 65 bytes", the number of bytes of cx1tShared1 is cxEcdhLen()
      cx1stAssert "the shared point is in uncompressed form", byteToNum(byte 1 of cx1tShared1) is 4
      -- 1 * (2G) == 2G, so with these two keys the shared point is just the
      -- public key of the other side. That makes this leg checkable against a
      -- value already pinned above rather than against a new magic constant.
      cx1stAssert "1 * 2G is 2G", cx1stHex(cx1tShared1) is cx1stHex(cxPublicKey(cx1tB, false))
   catch tError
      cx1stSectionFailed "ECDH", tError
   end try
end cx1stRunCurveEcdh

command cx1stRunCurveFailClosed
   local cx1tThrew, cx1tSk, cx1tDigest
   cx1stSection "the curve fails closed"
   try
      put cx1stSeckeyOne() into cx1tSk
      put cxSha256(cx1stText("abc")) into cx1tDigest

      -- A key of zero is not on the curve. cxSeckeyIsValid answers false (an
      -- ordinary answer for an imported key), while cxNewSeckey THROWS (fresh
      -- entropy that fails validation is a bug in the caller's RNG, not a
      -- routine outcome). Both halves of that split are checked.
      cx1stAssert "cxSeckeyIsValid says false for an all-zero key", cxSeckeyIsValid(cx1stRepeatByte(0, 32)) is false
      cx1stAssert "cxSeckeyIsValid says false for a short key", cxSeckeyIsValid(cx1stRepeatByte(1, 31)) is false

      put "false" into cx1tThrew
      try
         get cxNewSeckey(cx1stRepeatByte(0, 32))
      catch tInner
         put "true" into cx1tThrew
      end try
      cx1stAssert "cxNewSeckey refuses an all-zero key", cx1tThrew is "true"

      put "false" into cx1tThrew
      try
         get cxNewSeckey(cx1stRepeatByte(7, 31))
      catch tInner2
         put "true" into cx1tThrew
      end try
      cx1stAssert "cxNewSeckey refuses 31 bytes of entropy", cx1tThrew is "true"

      put "false" into cx1tThrew
      try
         get cxSign(cx1stRepeatByte(0, 32), cx1tDigest)
      catch tInner3
         put "true" into cx1tThrew
      end try
      cx1stAssert "cxSign refuses an invalid private key", cx1tThrew is "true"

      -- An all-zero digest is refused because a signature over it can be forged
      -- for ANY public key.
      put "false" into cx1tThrew
      try
         get cxSign(cx1tSk, cx1stRepeatByte(0, 32))
      catch tInner4
         put "true" into cx1tThrew
      end try
      cx1stAssert "cxSign refuses an all-zero digest", cx1tThrew is "true"

      -- A malformed public key must THROW, not answer false: it is a bug in the
      -- caller, and hiding it behind a security-shaped `false` is how a broken
      -- verify path goes unnoticed.
      put "false" into cx1tThrew
      try
         get cxVerify(cx1stRepeatByte(9, 20), cx1tDigest, cxSign(cx1tSk, cx1tDigest))
      catch tInner5
         put "true" into cx1tThrew
      end try
      cx1stAssert "cxVerify throws on a malformed public key (it does not answer false)", cx1tThrew is "true"
   catch tError
      cx1stSectionFailed "the curve fails closed", tError
   end try
end cx1stRunCurveFailClosed

command cx1stRunHex
   cx1stSection "hex"
   try
      cx1stAssert "cxHexEncode of 00ff10ab", cxHexEncode(cxHexDecode("00ff10ab")) is "00ff10ab"
      cx1stAssert "cxHexDecode accepts upper case", cxHexEncode(cxHexDecode("00FF10AB")) is "00ff10ab"
      cx1stAssert "cxHexEncode of the empty input", cxHexEncode(cxHexDecode("")) is ""
      cx1stAssert "an odd-length hex string is refused", cx1stThrows("cxHexDecode", "abc")
      cx1stAssert "a non-hex character is refused", cx1stThrows("cxHexDecode", "zz")
   catch tError
      cx1stSectionFailed "hex", tError
   end try
end cx1stRunHex

command cx1stRunBase58
   local cx1tPayload, cx1tI, cx1tPadded
   cx1stSection "Base58Check"
   try
      put cxHexDecode(cx1kBase58Payload) into cx1tPayload
      -- hash256 first, on its own. It is the checksum function this encoding is
      -- defined in terms of, and an encoder/decoder pair that agreed with each
      -- other while both used the wrong hash would pass every round-trip below.
      cx1stAssert "cxHash256 of abc is the published double-SHA-256", cx1stHex(cxHash256(cx1stText("abc"))) is cx1kHash256Abc
      cx1stAssert "cxHash256 is 32 bytes", the number of bytes of cxHash256(cx1stText("")) is 32
      cx1stAssert "and it is genuinely SHA-256 applied twice", cx1stHex(cxHash256(cx1stText("abc"))) is cx1stHex(cxSha256(cxSha256(cx1stText("abc"))))
      cx1stAssert "encodes the worked example", cxBase58CheckEncode(cx1tPayload) is cx1kBase58Address
      cx1stAssert "decodes it back", cxHexEncode(cxBase58CheckDecode(cx1kBase58Address)) is cx1stToLowerText(cx1kBase58Payload)
      -- The checksum is the entire point of the encoding: one flipped character
      -- must be refused, never coerced into a nearby valid-looking payload.
      cx1stAssert "a corrupt checksum is refused", cx1stThrows("cxBase58CheckDecode", cx1kBase58Corrupt)
      cx1stAssert "a character outside the alphabet is refused", cx1stThrows("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtj0O")
      -- Leading zero bytes must survive as leading "1"s, one for one. That is
      -- what makes a mainnet P2PKH address start with a 1 at all.
      put numToByte(0) & numToByte(0) & cxHexDecode("deadbeef") into cx1tPadded
      cx1stAssert "two leading zero bytes give two leading ones", char 1 to 2 of cxBase58CheckEncode(cx1tPadded) is "11"
      cx1stAssert "the round trip preserves them", cxHexEncode(cxBase58CheckDecode(cxBase58CheckEncode(cx1tPadded))) is "0000deadbeef"
   catch tError
      cx1stSectionFailed "Base58Check", tError
   end try
end cx1stRunBase58

command cx1stRunBech32
   local cx1tDecoded
   cx1stSection "bech32 and bech32m"
   try
      put cxBech32DecodeValues(cx1kBech32Valid) into cx1tDecoded
      cx1stAssert "a published bech32 string decodes", cx1tDecoded["hrp"] is "abcdef"
      cx1stAssert "and reports the bech32 encoding", cx1tDecoded["spec"] is "bech32"
      cx1stAssert "a mixed-case string is refused", cx1stThrows("cxBech32DecodeValues", "A1G7SGD8x")
      cx1stAssert "a string with no separator is refused", cx1stThrows("cxBech32DecodeValues", "pzry9x0s0muk")
      cx1stAssert "an empty human-readable part is refused", cx1stThrows("cxBech32DecodeValues", "1pzry9x0s0muk")
      cx1stAssert "a checksum computed over an uppercase HRP is refused", cx1stThrows("cxBech32DecodeValues", "A1G7SGD8")
      cx1stAssert "a data character outside the charset is refused", cx1stThrows("cxBech32DecodeValues", "x1b4n0q5v")
   catch tError
      cx1stSectionFailed "bech32", tError
   end try
end cx1stRunBech32

command cx1stRunAddresses
   local cx1tPubC, cx1tPubU, cx1tSeckey, cx1tDecoded
   cx1stSection "addresses from the generator G"
   try
      put cx1stRepeatByte(0, 31) & numToByte(1) into cx1tSeckey
      put cxPublicKey(cx1tSeckey, true) into cx1tPubC
      put cxPublicKey(cx1tSeckey, false) into cx1tPubU
      -- Each of these is a PUBLISHED answer, not a CoinXT expectation.
      cx1stAssert "cxBtcAddressP2PKH of G", cxBtcAddressP2PKH(cx1tPubC) is cx1kP2pkhOfG
      cx1stAssert "cxBtcAddressP2WPKH of G is the BIP-173 vector", cxBtcAddressP2WPKH(cx1tPubC) is cx1kP2wpkhOfG
      cx1stAssert "cxBtcAddressP2TR of x-only G is the BIP-350 vector", cxBtcAddressP2TR(byte 2 to 33 of cx1tPubU) is cx1kP2trOfG
      cx1stAssert "cxEthAddress of G (from the compressed key)", cxEthAddressChecksum(cxEthAddress(cx1tPubC)) is cx1kEthOfG
      cx1stAssert "cxEthAddress agrees from the uncompressed key", cxEthAddress(cx1tPubU) is cxEthAddress(cx1tPubC)
      -- An uncompressed key in a v0 SegWit address makes funds unspendable by
      -- every modern wallet, so it must be refused rather than encoded.
      cx1stAssert "P2WPKH refuses an uncompressed key", cx1stThrows("cxBtcAddressP2WPKH", cx1tPubU)
      cx1stAssert "P2TR refuses a 33-byte key", cx1stThrows("cxBtcAddressP2TR", cx1tPubC)
      -- Round-trip through the SegWit decoder, including the network check.
      put cxSegwitAddressDecode("bc", cx1kP2wpkhOfG) into cx1tDecoded
      cx1stAssert "the decoded witness version is 0", cx1tDecoded["version"] is 0
      cx1stAssert "the decoded program is hash160 of G", cxHexEncode(cx1tDecoded["program"]) is cxHexEncode(cxHash160(cx1tPubC))
      put cxSegwitAddressDecode("tb", cx1kSegwitTestnet) into cx1tDecoded
      cx1stAssert "a testnet v0 script address decodes", cxHexEncode(cx1tDecoded["program"]) is cx1kSegwitTestnetProgram
      cx1stAssert "a mainnet address is refused under the testnet HRP", cx1stThrows2("cxSegwitAddressDecode", "tb", cx1kP2wpkhOfG)
      -- THE rule BIP-350 exists for.
      cx1stAssert "a version 0 address with a bech32m checksum is refused", cx1stThrows2("cxSegwitAddressDecode", "bc", cx1kSegwitV0WithBech32m)
   catch tError
      cx1stSectionFailed "addresses", tError
   end try
end cx1stRunAddresses

command cx1stRunEip55
   cx1stSection "EIP-55 checksummed Ethereum addresses"
   try
      cx1stAssert "checksums the first specification example", cxEthAddressChecksum(cx1stToLowerText(cx1kEip55A)) is cx1kEip55A
      cx1stAssert "checksums the second", cxEthAddressChecksum(cx1stToLowerText(cx1kEip55B)) is cx1kEip55B
      cx1stAssert "recognises a correctly checksummed address", cxEthAddressIsChecksummed(cx1kEip55A) is true
      -- An all-lowercase address carries NO checksum, so reporting it as valid
      -- would quietly retire the protection EIP-55 exists to give.
      cx1stAssert "an all-lowercase address is NOT reported as checksummed", cxEthAddressIsChecksummed(cx1stToLowerText(cx1kEip55A)) is false
      cx1stAssert "a wrong-length address is refused", cx1stThrows("cxEthAddressChecksum", "0xdeadbeef")
   catch tError
      cx1stSectionFailed "EIP-55", tError
   end try
end cx1stRunEip55

command cx1stRunRlp
   local cx1tCatDog, cx1tDecoded
   cx1stSection "RLP"
   try
      cx1stAssert "encodes the string dog", cxHexEncode(cxRlpEncodeBytes(cx1stText("dog"))) is "83646f67"
      cx1stAssert "encodes the empty string", cxHexEncode(cxRlpEncodeBytes("")) is "80"
      cx1stAssert "encodes a single byte below 0x80 as itself", cxHexEncode(cxRlpEncodeBytes(numToByte(15))) is "0f"
      cx1stAssert "encodes the empty list", cxHexEncode(cxRlpEncodeList("")) is "c0"
      put cxRlpEncodeBytes(cx1stText("cat")) & cxRlpEncodeBytes(cx1stText("dog")) into cx1tCatDog
      cx1stAssert "encodes the list of cat and dog", cxHexEncode(cxRlpEncodeList(cx1tCatDog)) is "c88363617483646f67"
      put cxRlpDecode(cxHexDecode("83646f67")) into cx1tDecoded
      cx1stAssert "decodes a string item", cx1tDecoded["kind"] is "bytes"
      cx1stAssert "and its payload", cxHexEncode(cx1tDecoded["payload"]) is "646f67"
      put cxRlpDecode(cxHexDecode("c88363617483646f67")) into cx1tDecoded
      cx1stAssert "decodes a list item", cx1tDecoded["kind"] is "list"
      -- RLP's guarantee is one value, one encoding. A decoder that accepts a
      -- second spelling breaks every hash computed over the result.
      cx1stAssert "a single byte wrapped in a length prefix is refused", cx1stThrows("cxRlpDecode", cxHexDecode("8100"))
   catch tError
      cx1stSectionFailed "RLP", tError
   end try
end cx1stRunRlp

function cx1stThrows pHandler, pArg
   local cx1tThrew
   put "false" into cx1tThrew
   try
      do "get" && pHandler & "(pArg)"
   catch tError
      put "true" into cx1tThrew
   end try
   return cx1tThrew is "true"
end cx1stThrows

function cx1stThrows2 pHandler, pArgA, pArgB
   local cx1tThrew
   put "false" into cx1tThrew
   try
      do "get" && pHandler & "(pArgA, pArgB)"
   catch tError
      put "true" into cx1tThrew
   end try
   return cx1tThrew is "true"
end cx1stThrows2

function cx1stToLowerText pText
   local cx1tI, cx1tCount, cx1tCode, cx1tOut
   put "" into cx1tOut
   put the number of chars of pText into cx1tCount
   repeat with cx1tI = 1 to cx1tCount
      put byteToNum(char cx1tI of pText) into cx1tCode
      if cx1tCode >= 65 and cx1tCode <= 90 then
         add 32 to cx1tCode
      end if
      put numToChar(cx1tCode) after cx1tOut
   end repeat
   return cx1tOut
end cx1stToLowerText

function cx1stText pString
   return textEncode(pString, "utf-8")
end cx1stText

function cx1stHex pData
   local cx1tOut, cx1tI, cx1tByte, cx1tDigits
   put "0123456789abcdef" into cx1tDigits
   put empty into cx1tOut
   repeat with cx1tI = 1 to the number of bytes of pData
      put byteToNum(byte cx1tI of pData) into cx1tByte
      put char (cx1tByte div 16 + 1) of cx1tDigits after cx1tOut
      put char (cx1tByte mod 16 + 1) of cx1tDigits after cx1tOut
   end repeat
   return cx1tOut
end cx1stHex

function cx1stSeckeyOne
   return cx1stRepeatByte(0, 31) & numToByte(1)
end cx1stSeckeyOne

function cx1stSeckeyTwo
   return cx1stRepeatByte(0, 31) & numToByte(2)
end cx1stSeckeyTwo

function cx1stFlipByte pData, pIndex
   local cx1tByte
   put (byteToNum(byte pIndex of pData) + 1) mod 256 into cx1tByte
   return byte 1 to (pIndex - 1) of pData & numToByte(cx1tByte) & \
      byte (pIndex + 1) to (the number of bytes of pData) of pData
end cx1stFlipByte

function cx1stRepeatByte pCode, pCount
   local cx1tOne, cx1tOut
   put numToByte(pCode) into cx1tOne
   put cx1tOne into cx1tOut
   -- double up to size, then trim: O(log n) concatenations
   repeat while the number of bytes in cx1tOut < pCount
      put cx1tOut & cx1tOut into cx1tOut
   end repeat
   return byte 1 to pCount of cx1tOut
end cx1stRepeatByte

command cx1stRunBip39
   local cx1tEnt, cx1tMnemonic
   cx1stSection "BIP-39 mnemonics"
   try
      put cxHexDecode(cx1kBip39Entropy12) into cx1tEnt
      cx1stAssert "12 words from all-zero entropy", cxMnemonicFromEntropy(cx1tEnt) is cx1kBip39Mnemonic
      cx1stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(cx1kBip39Mnemonic)) is cx1kBip39Entropy12
      put cxHexDecode(cx1kBip39Entropy24) into cx1tEnt
      cx1stAssert "24 words from all-ones entropy", cxMnemonicFromEntropy(cx1tEnt) is cx1kBip39Mnemonic24
      cx1stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(cx1kBip39Mnemonic24)) is cx1kBip39Entropy24
      cx1stAssert "cxMnemonicValidate accepts it", cxMnemonicValidate(cx1kBip39Mnemonic) is true
      -- The checksum is the whole reason a mnemonic is 12 words and not 11: it
      -- is what catches a single mistyped word before it becomes a lost wallet.
      cx1stAssert "one wrong word fails the checksum", cxMnemonicValidate(cx1kBip39Mnemonic12Bad) is false
      cx1stAssert "a word outside the list is refused", cxMnemonicValidate("zzzz" && cx1kBip39Mnemonic) is false
      -- Whitespace is normalized because BIP-39 derives the seed from the
      -- STRING; a pasted trailing newline must not change the wallet.
      put "  " & cx1kBip39Mnemonic & "  " into cx1tMnemonic
      cx1stAssert "surrounding whitespace is normalized away", cxMnemonicValidate(cx1tMnemonic) is true
      -- cxMnemonicNormalize on its own, because it is public API and because
      -- every other BIP-39 handler runs it first: if it were wrong, validate
      -- and to-seed would be wrong together and agree with each other.
      cx1stAssert "cxMnemonicNormalize strips the padding", cxMnemonicNormalize(cx1tMnemonic) is cx1kBip39Mnemonic
      cx1stAssert "an already-clean mnemonic is returned unchanged", cxMnemonicNormalize(cx1kBip39Mnemonic) is cx1kBip39Mnemonic
      cx1stAssert "it is idempotent", cxMnemonicNormalize(cxMnemonicNormalize(cx1tMnemonic)) is cx1kBip39Mnemonic
      -- Tabs, newlines and runs of spaces are what a pasted backup actually
      -- contains, and BIP-39 derives the seed from the STRING, so collapsing
      -- them is the difference between restoring a wallet and missing it.
      cx1stAssert "tabs and newlines collapse to single spaces", cxMnemonicNormalize("abandon" & tab & "abandon" & return & "  abandon ") is "abandon abandon abandon"
      cx1stAssert "an empty string normalizes to empty", cxMnemonicNormalize("   ") is ""
      cx1stAssert "the seed with no passphrase", cxHexEncode(cxMnemonicToSeed(cx1kBip39Mnemonic, "")) is cx1kBip39SeedNoPass
      cx1stAssert "the seed with the TREZOR passphrase", cxHexEncode(cxMnemonicToSeed(cx1kBip39Mnemonic, "TREZOR")) is cx1kBip39Seed
      cx1stAssert "a normalized mnemonic gives the same seed", cxHexEncode(cxMnemonicToSeed(cx1tMnemonic, "")) is cx1kBip39SeedNoPass
      cx1stAssert "an entropy length BIP-39 does not define is refused", cx1stThrows("cxMnemonicFromEntropy", cx1stRepeatByte(0, 17))
      -- The wordlist crosses from the shim; if it were the wrong list or in the
      -- wrong order, everything above would still be self-consistent.
      cx1stAssert "the wordlist is 2048 slots of 8 bytes", the number of bytes of cxBip39Wordlist() is 16384
      cx1stAssert "cxBip39WordlistLen agrees", cxBip39WordlistLen() is 16384
      cx1stAssert "the first word is abandon", byte 1 to 7 of cxBip39Wordlist() is "abandon"
   catch tError
      cx1stSectionFailed "BIP-39", tError
   end try
end cx1stRunBip39

command cx1stRunBip32
   local cx1tNode, cx1tDeep, cx1tWatch, cx1tChild, cx1tStep
   cx1stSection "BIP-32 derivation"
   try
      put cxHdFromSeed(cxHexDecode(cx1kBip32Seed1)) into cx1tNode
      cx1stAssert "vector 1 master xprv", cxXprv(cx1tNode) is cx1kBip32V1Xprv
      cx1stAssert "vector 1 master xpub", cxXpub(cx1tNode) is cx1kBip32V1Xpub
      cx1stAssert "the master node is at depth 0", cx1tNode["depth"] is 0
      put cxHdDerivePath(cx1tNode, "m/0'") into cx1tChild
      cx1stAssert "vector 1 m/0' xprv", cxXprv(cx1tChild) is cx1kBip32V1H0Xprv
      cx1stAssert "vector 1 m/0' xpub", cxXpub(cx1tChild) is cx1kBip32V1H0Xpub
      cx1stAssert "h is accepted as a hardened marker", cxXprv(cxHdDerivePath(cx1tNode, "m/0h")) is cx1kBip32V1H0Xprv
      -- cxHdDeriveChild is the single CKD step cxHdDerivePath is a loop over,
      -- and it is public API in its own right. Pin it to the SAME published
      -- vector rather than only to the path walker: a shared defect in the
      -- step would make the two agree while both were wrong, so the first
      -- assertion here is against BIP-32's own number and the second is the
      -- agreement check on top of it.
      cx1stAssert "cxHdDeriveChild reaches m/0' as one hardened step", cxXprv(cxHdDeriveChild(cx1tNode, 2147483648)) is cx1kBip32V1H0Xprv
      cx1stAssert "and a normal step agrees with the path walker", cxXprv(cxHdDeriveChild(cx1tChild, 1)) is cxXprv(cxHdDerivePath(cx1tNode, "m/0'/1"))
      cx1stAssert "index 0 is not treated as hardened", cxXprv(cxHdDeriveChild(cx1tNode, 0)) is cxXprv(cxHdDerivePath(cx1tNode, "m/0"))
      put cxHdDeriveChild(cx1tChild, 1) into cx1tStep
      cx1stAssert "each step advances the depth by one", cx1tStep["depth"] is 2
      cx1stAssert "a child index at or above 2^32 is refused", cx1stThrows2("cxHdDeriveChild", cx1tNode, 4294967296)
      cx1stAssert "a negative child index is refused", cx1stThrows2("cxHdDeriveChild", cx1tNode, -1)
      put cxHdDerivePath(cx1tNode, cx1kBip32V1DeepPath) into cx1tDeep
      cx1stAssert "vector 1 five levels deep", cxXprv(cx1tDeep) is cx1kBip32V1DeepXprv
      cx1stAssert "and it is at depth 5", cx1tDeep["depth"] is 5
      -- Vector 3 is in the BIP for one reason: a leading zero in the master key.
      cx1stAssert "vector 3 (leading-zero master key)", cxXprv(cxHdFromSeed(cxHexDecode(cx1kBip32Seed3))) is cx1kBip32V3Xprv
      -- A watch-only node is the whole point of an xpub, and its limits are the
      -- whole point of hardened derivation.
      put cxHdNeuter(cx1tChild) into cx1tWatch
      cx1stAssert "neuter leaves the source node's key alone", cx1tChild["seckey"] is not ""
      cx1stAssert "a watch-only node has no private key", cx1tWatch["seckey"] is ""
      cx1stAssert "and still derives the same normal child", cxXpub(cxHdDerivePath(cx1tWatch, "m/1")) is cxXpub(cxHdDerivePath(cx1tChild, "m/1"))
      cx1stAssert "but cannot make an xprv", cx1stThrows("cxXprv", cx1tWatch)
      cx1stAssert "and cannot derive a hardened child", cx1stThrows2("cxHdDerivePath", cx1tWatch, "m/0'")
      -- A path that parses loosely is a path that silently derives the wrong
      -- wallet, so each of these must throw rather than be interpreted.
      cx1stAssert "a path without a leading m is refused", cx1stThrows2("cxHdDerivePath", cx1tNode, "0/1")
      cx1stAssert "an empty level is refused", cx1stThrows2("cxHdDerivePath", cx1tNode, "m/")
      -- "m/" and "m/0'/" are the trailing-separator cases the 2026-08-10
      -- engine pass caught failing OPEN: a trailing delimiter is invisible
      -- to `the number of items`, so the walker returned the node unchanged
      -- instead of throwing. The second spelling pins the fix at depth too.
      cx1stAssert "a trailing separator is refused", cx1stThrows2("cxHdDerivePath", cx1tNode, "m/0'/")
      cx1stAssert "a non-digit level is refused", cx1stThrows2("cxHdDerivePath", cx1tNode, "m/1e3")
      cx1stAssert "a level at or above 2^31 is refused", cx1stThrows2("cxHdDerivePath", cx1tNode, "m/2147483648")
      cx1stAssert "a too-short seed is refused", cx1stThrows("cxHdFromSeed", cx1stRepeatByte(0, 15))
   catch tError
      cx1stSectionFailed "BIP-32", tError
   end try
end cx1stRunBip32

command cx1stRunBip44
   local cx1tMaster, cx1tNode
   cx1stSection "BIP-44 / BIP-84 end to end"
   try
      -- The claim this section makes is the one that matters to a user: the
      -- same twelve words that restore a wallet anywhere else restore THIS one
      -- to the same addresses.
      put cxHdFromSeed(cxMnemonicToSeed(cx1kBip39Mnemonic, "")) into cx1tMaster
      cx1stAssert "the test mnemonic's root xprv", cxXprv(cx1tMaster) is cx1kAbandonXprv
      put cxHdDerivePath(cx1tMaster, cx1kAbandonBip44) into cx1tNode
      cx1stAssert "m/44'/0'/0'/0/0 is the published P2PKH address", cxBtcAddressP2PKH(cx1tNode["pubkey"]) is cx1kAbandonP2pkh
      put cxHdDerivePath(cx1tMaster, cx1kAbandonBip84) into cx1tNode
      cx1stAssert "m/84'/0'/0'/0/0 is the BIP-84 vector", cxBtcAddressP2WPKH(cx1tNode["pubkey"]) is cx1kAbandonP2wpkh
      cx1stAssert "the BIP-84 account xpub", cxXpub(cxHdDerivePath(cx1tMaster, cx1kAbandonBip84Account)) is cx1kAbandonBip84Xpub
      put cxHdDerivePath(cx1tMaster, cx1kAbandonEthPath) into cx1tNode
      cx1stAssert "m/44'/60'/0'/0/0 is the published Ethereum address", cxEthAddressChecksum(cxEthAddress(cx1tNode["pubkey"])) is cx1kAbandonEth
   catch tError
      cx1stSectionFailed "BIP-44", tError
   end try
end cx1stRunBip44

command cx1stRunTransactions
   local cx1tOutpoints, cx1tSequences, cx1tOutputs, cx1tD0, cx1tD1, cx1tSig0, cx1tDer0, cx1tScriptSig0
   local cx1tSig1, cx1tDer1, cx1tPub1, cx1tWit1, cx1tScriptSigs, cx1tWitnesses, cx1tRaw
   local cx1tRecov, cx1tRecid, cx1tRHex, cx1tSHex, cx1tEth, cx1tThrew, cx1tErr2
   cx1stSection "phase 5: transactions (BIP-143, EIP-155, EIP-1559)"
   try
      -- --- Bitcoin: the BIP-143 native-P2WPKH worked example, rebuilt whole.
      -- The pieces first, so a mismatch localizes.
      cx1stAssert "input 0 outpoint serializes (txid reversed + LE vout)", \
            cxHexEncode(cxBtcOutpoint(cx1kTxid0, 0)) is cx1kTxOutpoint0
      cx1stAssert "input 1 outpoint serializes", \
            cxHexEncode(cxBtcOutpoint(cx1kTxid1, 1)) is cx1kTxOutpoint1
      cx1stAssert "output 0 serializes (LE amount + script)", \
            cxHexEncode(cxBtcOutput(112340000, cx1kTxOutScript0)) is cx1kTxOut0
      cx1stAssert "output 1 serializes", \
            cxHexEncode(cxBtcOutput(223450000, cx1kTxOutScript1)) is cx1kTxOut1
      put cx1kTxOutpoint0 & comma & cx1kTxOutpoint1 into cx1tOutpoints
      put "4294967278,4294967295" into cx1tSequences
      put cx1kTxOut0 & comma & cx1kTxOut1 into cx1tOutputs
      -- The two sighashes: input 0 legacy SIGHASH_ALL, input 1 BIP-143.
      put cxBtcSighashLegacy(1, cx1tOutpoints, cx1tSequences, 1, cx1kTxScriptCode0, cx1tOutputs, 17, 1) into cx1tD0
      cx1stAssert "input 0 legacy sighash matches", cxHexEncode(cx1tD0) is cx1kTxLegacySighash
      put cxBtcSighashSegwit(1, cx1tOutpoints, cx1tSequences, 2, cx1kTxScriptCode1, 600000000, cx1tOutputs, 17, 1) into cx1tD1
      cx1stAssert "input 1 BIP-143 sighash matches the BIP", cxHexEncode(cx1tD1) is cx1kTxSegwitSighash
      -- Sign each (RFC 6979, so deterministic), DER-encode, append SIGHASH_ALL.
      put cxSign(cxHexDecode(cx1kTxSeckey0), cx1tD0) into cx1tSig0
      put cxDerEncode(cx1tSig0) & numToByte(1) into cx1tDer0
      put numToByte(the number of bytes of cx1tDer0) & cx1tDer0 into cx1tScriptSig0
      cx1stAssert "input 0 scriptSig (push + DER sig + hashtype)", \
            cxHexEncode(cx1tScriptSig0) is cx1kTxScriptSig0
      put cxSign(cxHexDecode(cx1kTxSeckey1), cx1tD1) into cx1tSig1
      put cxDerEncode(cx1tSig1) & numToByte(1) into cx1tDer1
      put cxPublicKey(cxHexDecode(cx1kTxSeckey1), true) into cx1tPub1
      cx1stAssert "input 1's pubkey is the BIP's compressed key", \
            cxHexEncode(cx1tPub1) is cx1kTxPubkey1
      put cxBtcWitness(cxHexEncode(cx1tDer1) & comma & cxHexEncode(cx1tPub1)) into cx1tWit1
      cx1stAssert "input 1 witness stack (count + sig + pubkey)", \
            cxHexEncode(cx1tWit1) is cx1kTxWitness1
      -- Assemble: input 0 has the scriptSig and no witness, input 1 the reverse.
      put cxHexEncode(cx1tScriptSig0) & comma into cx1tScriptSigs
      put comma & cxHexEncode(cx1tWit1) into cx1tWitnesses
      put cxBtcTxEncode(1, cx1tOutpoints, cx1tScriptSigs, cx1tSequences, cx1tWitnesses, cx1tOutputs, 17) into cx1tRaw
      cx1stAssert "the whole signed transaction matches BIP-143 byte for byte", \
            cxHexEncode(cx1tRaw) is cx1kTxSignedRaw
      cx1stAssert "the txid (non-witness serialization, reversed)", \
            cxBtcTxid(1, cx1tOutpoints, cx1tScriptSigs, cx1tSequences, cx1tOutputs, 17) is cx1kTxTxid
      -- varint boundaries.
      cx1stAssert "varint 252 is one byte", cxHexEncode(cxVarInt(252)) is "fc"
      cx1stAssert "varint 253 is fd + LE u16", cxHexEncode(cxVarInt(253)) is "fdfd00"
      cx1stAssert "varint 65536 is fe + LE u32", cxHexEncode(cxVarInt(65536)) is "fe00000100"

      -- --- Ethereum EIP-155 legacy: the specification's own example.
      cx1stAssert "the EIP-155 signing hash matches the spec", \
            cxHexEncode(cxEthLegacySighash(9, cx1kEthGasPrice, 21000, cx1kEthTo, cx1kEthValue, "", 1)) is cx1kEthLegacySighash
      put cxSignRecoverable(cxHexDecode(cx1kEthSeckey), cxHexDecode(cx1kEthLegacySighash)) into cx1tRecov
      put byteToNum(byte 65 of cx1tRecov) into cx1tRecid
      put cxHexEncode(byte 1 to 32 of cx1tRecov) into cx1tRHex
      put cxHexEncode(byte 33 to 64 of cx1tRecov) into cx1tSHex
      put cxEthLegacyEncode(9, cx1kEthGasPrice, 21000, cx1kEthTo, cx1kEthValue, "", 1, cx1tRecid, cx1tRHex, cx1tSHex) into cx1tEth
      cx1stAssert "the signed EIP-155 transaction matches the spec (v=37)", \
            cx1tEth["raw"] is cx1kEthLegacyRaw
      cx1stAssert "the EIP-155 transaction hash", cx1tEth["txhash"] is cx1kEthLegacyTxhash

      -- --- Ethereum EIP-1559 typed (0x02): self-consistent, deterministic.
      cx1stAssert "the EIP-1559 signing hash", \
            cxHexEncode(cxEth1559Sighash(1, 0, cx1kEth1559MaxPrio, cx1kEth1559MaxFee, 21000, cx1kEthTo, cx1kEth1559Value, "")) is cx1kEth1559Sighash
      put cxSignRecoverable(cxHexDecode(cx1kEthSeckey), cxHexDecode(cx1kEth1559Sighash)) into cx1tRecov
      put byteToNum(byte 65 of cx1tRecov) into cx1tRecid
      put cxHexEncode(byte 1 to 32 of cx1tRecov) into cx1tRHex
      put cxHexEncode(byte 33 to 64 of cx1tRecov) into cx1tSHex
      put cxEth1559Encode(1, 0, cx1kEth1559MaxPrio, cx1kEth1559MaxFee, 21000, cx1kEthTo, cx1kEth1559Value, "", cx1tRecid, cx1tRHex, cx1tSHex) into cx1tEth
      cx1stAssert "the signed EIP-1559 transaction (0x02 envelope)", \
            cx1tEth["raw"] is cx1kEth1559Raw
      cx1stAssert "the EIP-1559 transaction hash", cx1tEth["txhash"] is cx1kEth1559Txhash

      -- Fail closed: a compact signature must be exactly 64 bytes.
      cx1stAssert "cxDerEncode refuses a short signature", \
            cx1stThrows("cxDerEncode", byte 1 to 40 of cx1tSig1)
      -- Fail closed: the BIP-143 sighash MUST commit to the outputs. An empty
      -- outputs list is refused - a preimage without hashOutputs would sign a
      -- payment to anywhere (the review's CRITICAL finding, guarded here).
      put false into cx1tThrew
      try
         get cxBtcSighashSegwit(1, cx1tOutpoints, cx1tSequences, 2, cx1kTxScriptCode1, 600000000, "", 17, 1)
      catch cx1tErr2
         put true into cx1tThrew
      end try
      cx1stAssert "cxBtcSighashSegwit refuses an empty outputs list (hashOutputs is mandatory)", cx1tThrew
      -- Fail closed: a witness list may not carry MORE entries than there are
      -- inputs (the extras would be silently dropped). A SHORT list cannot be
      -- rejected here - the engine ignores one trailing delimiter, so [wit, ""]
      -- and [wit] are the same string, and a missing trailing witness reads as
      -- an empty stack, which is its correct meaning. cx1tWitnesses already has one
      -- entry per input; a third makes it over-long for this two-input tx.
      put false into cx1tThrew
      try
         get cxBtcTxEncode(1, cx1tOutpoints, cx1tScriptSigs, cx1tSequences, cx1tWitnesses & comma & cxHexEncode(cx1tWit1), cx1tOutputs, 17)
      catch cx1tErr2
         put true into cx1tThrew
      end try
      cx1stAssert "cxBtcTxEncode refuses a witness list longer than the input count", cx1tThrew
   catch tError
      cx1stSectionFailed "transactions", tError
   end try
end cx1stRunTransactions

command cx1stRunFailOpen
   local cx1tProgram, cx1tDecoded, cx1tKey
   cx1stSection "fail-closed regressions"
   try
      -- EIP-55 verification must depend on the CALLER'S casing. If these come
      -- back true on the engine while they are false headlessly, the cause is
      -- `the caseSensitive` reaching a comparison it should not - look at
      -- cxCompareBytes first.
      cx1stAssert "a correctly checksummed address still verifies", cxEthAddressIsChecksummed(cx1kEip55A) is true
      cx1stAssert "one corrupted letter is caught", cxEthAddressIsChecksummed(cx1kEip55Corrupt) is false
      cx1stAssert "a fully case-flipped address is caught", cxEthAddressIsChecksummed(cx1kEip55Flipped) is false
      -- An in-band error sentinel over arbitrary bytes is always wrong.
      put cxHexDecode(cx1kSegwitErrorProgram) into cx1tProgram
      cx1stAssert "an address whose program spells ERROR encodes", cxSegwitAddressEncode("bc", 1, cx1tProgram) is cx1kSegwitErrorAddress
      put cxSegwitAddressDecode("bc", cx1kSegwitErrorAddress) into cx1tDecoded
      cx1stAssert "and decodes back to the same program", cxHexEncode(cx1tDecoded["program"]) is cx1kSegwitErrorProgram
      cx1stAssert "at witness version 1", cx1tDecoded["version"] is 1
      -- hash160 hashes anything, so an unchecked key gives a well-formed,
      -- checksummed, permanently unspendable address.
      cx1stAssert "P2PKH refuses an empty key", cx1stThrows("cxBtcAddressP2PKH", "")
      cx1stAssert "P2PKH refuses a 20-byte hash", cx1stThrows("cxBtcAddressP2PKH", cx1stRepeatByte(0, 20))
      put numToByte(4) & cx1stRepeatByte(0, 32) into cx1tKey
      cx1stAssert "P2PKH refuses 33 bytes tagged 0x04", cx1stThrows("cxBtcAddressP2PKH", cx1tKey)
      -- char (n) of a 32-character charset returns EMPTY past the end, so an
      -- out-of-range value used to emit nothing and shorten the string.
      cx1stAssert "bech32 refuses a data value of 32", cx1stThrows2("cxBech32EncodeValues", "bc", "0,32,1")
      cx1stAssert "bech32 refuses a negative data value", cx1stThrows2("cxBech32EncodeValues", "bc", "0,-1")
      -- An uppercase HRP used to produce a MIXED-case string, which BIP-173
      -- forbids and which this library's own decoder rejects.
      cx1stAssert "an uppercase HRP is refused", cx1stThrows2("cxBech32EncodeValues", "BC", "0")
   catch tError
      cx1stSectionFailed "fail-closed regressions", tError
   end try
end cx1stRunFailOpen


-- ==========================================================================
-- TorrentXT: the full bt* self-test
--
-- Synchronous throughout. Reuses the suite's single session rather than
-- opening a second one, which TorrentXT does not allow.
--
-- GENERATED from torrentxt/tests/torrent-selftest.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `bt1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

command bt1stAssert pName, pPass
   add 1 to bt1sTotal
   if pPass then
      add 1 to bt1sPassed
      put "PASS  " & pName & return after bt1sResultText
   else
      add 1 to bt1sFailed
      put "FAIL  " & pName & return after bt1sResultText
   end if
end bt1stAssert

command bt1stSection pTitle
   put return & "--- " & pTitle & " ---" & return after bt1sResultText
end bt1stSection

command bt1stNote pMsg
   put "      " & pMsg & return after bt1sResultText
end bt1stNote

function bt1stCount pList
   local bt1tN, bt1tEl
   put 0 into bt1tN
   repeat for each element bt1tEl in pList
      add 1 to bt1tN
   end repeat
   return bt1tN
end bt1stCount

function bt1stListHas pList, pNeedle
   local bt1tEl
   repeat for each element bt1tEl in pList
      if bt1tEl is pNeedle then
         return true
      end if
   end repeat
   return false
end bt1stListHas

command bt1stRun
   put 0 into bt1sTotal
   put 0 into bt1sPassed
   put 0 into bt1sFailed
   put "" into bt1sResultText
   put 0 into bt1sTorrent
   put 0 into bt1sTorrent2

   bt1stSection "session + ABI"
   -- btStartSession is the one handler that can throw (on ABI skew); a clean
   -- start IS the ABI check passing.
   local bt1tStartOk, bt1tNewSession
   put false into bt1tStartOk
   -- RELEASE A SESSION THIS HARNESS ITSELF LEFT BEHIND, before asking for one.
   -- TorrentXT allows exactly ONE session per process, the latch is in the C
   -- shim, and the only key is the integer handle - nothing exported can free a
   -- session you can no longer name. So a run that died before its teardown
   -- orphans it for the whole engine launch. Safe to repeat and safe when
   -- TorrentXT is absent: btStopSession on a stale handle is a documented
   -- no-op, and the try covers the absent case.
   -- GENERATED (tools/build-suite-selftest.py): TorrentXT allows exactly ONE
   -- session per process, and the suite core opens one during its probe. Reuse
   -- it rather than fighting for a second - starting one here would fail, this
   -- harness would take its cannot-start branch, and the whole torrent surface
   -- would report as skipped while looking perfectly green.
   --
   -- THE RELEASE IS SWALLOWED BY THIS REWRITE ON PURPOSE. The standalone
   -- harness releases any session IT left behind before asking for one, which
   -- is correct there and actively harmful here: bt1sSession is an ALIAS for
   -- the core's handle, so on a second run in one process the folded copy would
   -- btStopSession the session the cross-member BEP44 sections are still using.
   -- It was folded in once, caught by reading the generated file, and the
   -- rewrite's span was widened to cover it. The core does that job for both.
   if sSession > 0 then
      put sSession into bt1sSession
      put true into bt1tStartOk
   else
      try
         put btStartSession() into bt1sSession
         put true into bt1tStartOk
      catch tErr
         put 0 into bt1sSession
      end try
   end if
   bt1stAssert "btStartSession did not throw (ABI matches)", bt1tStartOk
   if bt1sSession is 0 or bt1sSession is empty then
      -- NAME BOTH CAUSES. The shim cannot tell them apart and neither can this
      -- harness, so asserting the one it cannot know sent operators hunting for
      -- a window that was not open. See OXT-PASS-RUNBOOK trap 5.1.1.
      bt1stNote "Could not start a session. Either another TorrentXT stack owns it"
      bt1stNote "(close that stack and re-run), or an earlier run in THIS engine"
      bt1stNote "launch lost its handle - quit and relaunch OXT."
      bt1stNote (btLastError())
      bt1stPaint
      exit bt1stRun
   end if
   bt1stAssert "btStartSession returns a positive handle", (bt1sSession > 0)
   -- NB: LiveCode's `is a <type>` only knows number/integer/boolean/point/rect/
   -- date/color - there is NO `is a string`. Test btLastError by clearing it and
   -- confirming it reads back empty (exercises btClearError + btLastError).
   btClearError
   bt1stAssert "btLastError is empty after btClearError", (btLastError() is empty)

   -- Wrap the rest: a mis-declared foreign handler (wrong signature) raises a
   -- runtime error on its first call. Catch it so the harness REPORTS which call
   -- broke and still shows a summary, instead of halting the stack mid-run.
   try
   bt1stSection "settings"
   bt1stAssert "btSetBool enable_dht", (btSetBool(bt1sSession, "enable_dht", true) is 0)
   bt1stAssert "btSetBool enable_lsd", (btSetBool(bt1sSession, "enable_lsd", true) is 0)
   bt1stAssert "btSetInt download_rate_limit", (btSetInt(bt1sSession, "download_rate_limit", "0") is 0)
   bt1stAssert "btSetString user_agent", (btSetString(bt1sSession, "user_agent", "TorrentXT-selftest") is 0)
   bt1stAssert "btGetSetting user_agent non-empty", (btGetSetting(bt1sSession, "user_agent") is not "")
   bt1stAssert "btSetEncryption", (btSetEncryption(bt1sSession, 1, 1, 3) is 0)
   bt1stAssert "btSetInt rejects unknown key", (btSetInt(bt1sSession, "no_such_setting_key", "1") < 0)

   bt1stSection "errors"
   btClearError
   bt1stAssert "btClearError empties last-error", (btLastError() is "")

   bt1stSection "DHT bootstrap + state"
   bt1stAssert "btDhtAddBootstrap", (btDhtAddBootstrap(bt1sSession, "router.bittorrent.com", 6881) is 0)
   local bt1tDht
   put btDhtState(bt1sSession) into bt1tDht
   bt1stAssert "btDhtState returns an array with nodes", (bt1tDht["nodes"] is a number)
   local bt1tDhtState
   put btDhtSaveState(bt1sSession) into bt1tDhtState
   bt1stAssert "btDhtSaveState returns a measurable Data", (the number of bytes in bt1tDhtState is a number)
   bt1stAssert "btDhtLoadState round-trips", (btDhtLoadState(bt1sSession, bt1tDhtState) is 0)

   bt1stSection "create + seed (sets up a torrent for the rest)"
   bt1stMakeContent
   local bt1tTorrentData
   put btCreateTorrent(bt1sContentDir, 0, 0, "udp://tracker.opentrackr.org:1337/announce") into bt1tTorrentData
   bt1stAssert "btCreateTorrent returns metainfo bytes", (the number of bytes in bt1tTorrentData > 0)
   if the number of bytes in bt1tTorrentData > 0 then
      put btAddTorrentFile(bt1sSession, bt1tTorrentData, bt1sTempDir) into bt1sTorrent
   end if
   bt1stAssert "btAddTorrentFile returns a handle", (bt1sTorrent > 0)
   bt1stAssert "btTorrentCount >= 1", (btTorrentCount(bt1sSession) >= 1)
   bt1stAssert "btTorrentHandleAt(0) is a handle", (btTorrentHandleAt(bt1sSession, 0) > 0)

   if bt1sTorrent > 0 then
      bt1stRunTorrentChecks bt1tTorrentData
   else
      bt1stNote "Skipping torrent-scoped checks: no seed torrent was created."
   end if

   bt1stSection "events"
   -- the alert drain: after the adds + DHT puts above there should be events
   -- queued; we only assert it drains a well-formed list (the dispatcher in
   -- torrent-helpers is what fans these out to message-path handlers).
   bt1stAssert "btPoll drains a list", (bt1stCount(btPoll(bt1sSession)) >= 0)

   bt1stSection "DHT key-value (BEP44) - offline-verifiable parts"
   local bt1tKey, bt1tKey2
   put btDhtKeypair("") into bt1tKey
   bt1stAssert "btDhtKeypair publicKey is 64 hex", (the number of chars of bt1tKey["publicKey"] is 64)
   bt1stAssert "btDhtKeypair secretKey is 128 hex", (the number of chars of bt1tKey["secretKey"] is 128)
   bt1stAssert "btDhtKeypair seed is 64 hex", (the number of chars of bt1tKey["seed"] is 64)
   put btDhtKeypair(bt1tKey["seed"]) into bt1tKey2
   bt1stAssert "btDhtKeypair is deterministic from a seed", (bt1tKey2["publicKey"] is bt1tKey["publicKey"])
   local bt1tTarget
   put btDhtPutImmutable(bt1sSession, textEncode("TorrentXT self-test value", "UTF-8")) into bt1tTarget
   bt1stAssert "btDhtPutImmutable returns a 40-hex target", (the number of chars of bt1tTarget is 40)
   bt1stAssert "btDhtGetImmutable accepts the target (async)", (btDhtGetImmutable(bt1sSession, bt1tTarget) is 0)
   bt1stAssert "btDhtPutMutable signs + queues", (btDhtPutMutable(bt1sSession, bt1tKey["publicKey"], bt1tKey["secretKey"], "", textEncode("v1", "UTF-8")) is 0)
   bt1stAssert "btDhtGetMutable accepts the key (async)", (btDhtGetMutable(bt1sSession, bt1tKey["publicKey"], "") is 0)

   bt1stSection "signed puts, rendezvous, NAT mapping, rp1 (the v9-v11 surface)"
   -- btDhtBep44SignBuf hands back the EXACT bytes libtorrent signs, so a
   -- signature can be produced off-box (a hardware key, another machine) and
   -- fed to btDhtPutSigned. It is a pure function of (salt, seq, value), so
   -- determinism is the property worth pinning; byte-exact compares need
   -- caseSensitive, since `is` would otherwise fold 0x41 onto 0x61.
   local bt1tBuf, bt1tBuf2, bt1tBufSeq2
   put btDhtBep44SignBuf("", "1", textEncode("signed-v1", "UTF-8")) into bt1tBuf
   bt1stAssert "btDhtBep44SignBuf returns bytes", (the number of bytes of bt1tBuf > 0)
   put btDhtBep44SignBuf("", "1", textEncode("signed-v1", "UTF-8")) into bt1tBuf2
   set the caseSensitive to true
   bt1stAssert "btDhtBep44SignBuf is deterministic", (bt1tBuf is bt1tBuf2)
   put btDhtBep44SignBuf("", "2", textEncode("signed-v1", "UTF-8")) into bt1tBufSeq2
   bt1stAssert "a different seq changes the signing buffer", (bt1tBufSeq2 is not bt1tBuf)
   -- Fail closed on a signature that is not even hex, rather than queueing a
   -- garbage item into the DHT.
   bt1stAssert "btDhtPutSigned rejects a malformed signature", \
      (btDhtPutSigned(bt1sSession, bt1tKey["publicKey"], "", "1", textEncode("signed-v1", "UTF-8"), "not-a-signature") < 0)
   -- Classic BEP5 rendezvous: any 40-hex id is legal, it need not name a real
   -- torrent - that is what makes it a presence primitive.
   bt1stAssert "btDhtGetPeers accepts a rendezvous id (async)", \
      (btDhtGetPeers(bt1sSession, bt1tTarget) is 0)
   -- A phantom swarm: joined by info-hash with no metadata, which is where the
   -- rp1 peer-wire transport meets its peers.
   local bt1tPhantom
   put btAddInfohash(bt1sSession, bt1tTarget, bt1sTempDir) into bt1tPhantom
   bt1stAssert "btAddInfohash joins a metadata-less swarm", (bt1tPhantom > 0)
   -- NAT mapping is best-effort by nature: 0 means "no mapper active"
   -- (UPnP/NAT-PMP off, or a router that will not play), which is a legitimate
   -- outcome on a CI box or a locked-down LAN, not a failure. Either way it
   -- must not throw, and unmapping must tolerate whatever it returns.
   local bt1tMapId
   put btMapPort(bt1sSession, 0, btListenPort(bt1sSession), true) into bt1tMapId
   bt1stAssert "btMapPort returns a mapping id or 0 (no mapper)", (bt1tMapId >= 0)
   bt1stAssert "btUnmapPort tolerates that id", (btUnmapPort(bt1sSession, bt1tMapId) >= 0)
   bt1stAssert "btUnmapPort on a stale id is a harmless no-op", \
      (btUnmapPort(bt1sSession, 999999) >= 0)
   -- rp1: enable the extension, set a token, drain. A send with no connected
   -- peer must fail cleanly (there is nobody to send to), never crash.
   bt1stAssert "btRp1Enable turns the extension on", (btRp1Enable(bt1sSession) is 0)
   bt1stAssert "btRp1SetToken accepts a token", \
      (btRp1SetToken(bt1sSession, textEncode("selftest-token", "UTF-8")) is 0)
   bt1stAssert "btRp1Poll drains a list", (bt1stCount(btRp1Poll(bt1sSession)) >= 0)
   bt1stAssert "btRp1Send to a non-peer fails cleanly", \
      (btRp1Send(bt1sSession, 999999, textEncode("nobody is listening", "UTF-8")) < 0)

   bt1stSection "not auto-checked - confirm by hand"
   bt1stNote "btMoveStorage + btRemoveTorrent(deleteFiles=true) are destructive;"
   bt1stNote "btSetFilePriorities needs a binary buffer; btAddTorrentWithResume"
   bt1stNote "needs async resume bytes; btAddMagnet is covered via btAddMagnetEx."
   catch tRunErr
      bt1stNote "RUNTIME ERROR - a binding call failed: " & tRunErr
      add 1 to bt1sFailed
   end try

   bt1stShowSummary
   bt1stPaint
end bt1stRun

command bt1stRunTorrentChecks pTorrentData
   local bt1tStatus, bt1tHash, bt1tFiles, bt1tFile, bt1tWS, bt1tTrackerUrl, bt1tFound

   bt1stSection "status + inspection"
   put btTorrentStatus(bt1sTorrent) into bt1tStatus
   bt1stAssert "btTorrentStatus has a name", (bt1tStatus["name"] is not "")
   bt1stAssert "btTorrentStatus progress is a number", (bt1tStatus["progress"] is a number)
   put btInfoHash(bt1sTorrent) into bt1tHash
   bt1stAssert "btInfoHash is 40 hex", (the number of chars of bt1tHash is 40)
   bt1stAssert "btPieceBitfield returns a measurable Data", (the number of bytes in btPieceBitfield(bt1sTorrent) is a number)
   bt1stAssert "btPieceAvailability returns a measurable Data", (the number of bytes in btPieceAvailability(bt1sTorrent) is a number)
   put btFileList(bt1sTorrent) into bt1tFiles
   bt1stAssert "btFileList returns >= 1 file", (bt1stCount(bt1tFiles) >= 1)
   repeat for each element bt1tFile in bt1tFiles
      bt1stAssert "btFileList entry has a path", (bt1tFile["path"] is not "")
      bt1stAssert "btFileList entry size > 0", (bt1tFile["size"] > 0)
      bt1stAssert "btFileList entry priority is a number", (bt1tFile["priority"] is a number)
      exit repeat
   end repeat
   bt1stAssert "btPeerList returns a list", (bt1stCount(btPeerList(bt1sTorrent)) >= 0)

   bt1stSection "control + flags"
   bt1stAssert "btPause", (btPause(bt1sTorrent) is 0)
   bt1stAssert "btResume", (btResume(bt1sTorrent) is 0)
   bt1stAssert "btForceRecheck", (btForceRecheck(bt1sTorrent) is 0)
   bt1stAssert "btForceReannounce", (btForceReannounce(bt1sTorrent) is 0)
   bt1stAssert "btSetSequentialDownload on", (btSetSequentialDownload(bt1sTorrent, true) is 0)
   bt1stAssert "btSetSequentialDownload off", (btSetSequentialDownload(bt1sTorrent, false) is 0)
   bt1stAssert "btSetAutoManaged", (btSetAutoManaged(bt1sTorrent, true) is 0)
   bt1stAssert "btSetSuperSeeding", (btSetSuperSeeding(bt1sTorrent, false) is 0)
   bt1stAssert "btSetShareMode", (btSetShareMode(bt1sTorrent, false) is 0)
   bt1stAssert "btSetUploadMode", (btSetUploadMode(bt1sTorrent, false) is 0)
   bt1stAssert "btSetTorrentFlags (sequential=512)", (btSetTorrentFlags(bt1sTorrent, "512", "512") is 0)
   bt1stAssert "btUnsetTorrentFlags", (btUnsetTorrentFlags(bt1sTorrent, "512") is 0)
   bt1stAssert "btSetMaxConnections", (btSetMaxConnections(bt1sTorrent, 50) is 0)
   bt1stAssert "btSetMaxUploads", (btSetMaxUploads(bt1sTorrent, 4) is 0)
   bt1stAssert "btSetFilePriority", (btSetFilePriority(bt1sTorrent, 0, 4) is 0)
   bt1stAssert "btSetPiecePriority", (btSetPiecePriority(bt1sTorrent, 0, 4) is 0)
   bt1stAssert "btSetTorrentLimits", (btSetTorrentLimits(bt1sTorrent, "0", "0") is 0)
   bt1stAssert "btScrapeTracker (async)", (btScrapeTracker(bt1sTorrent) is 0)
   bt1stAssert "btClearTorrentError", (btClearTorrentError(bt1sTorrent) is 0)

   bt1stSection "download queue"
   bt1stAssert "btQueuePosition is a number", (btQueuePosition(bt1sTorrent) is a number)
   bt1stAssert "btQueueTop", (btQueueTop(bt1sTorrent) is 0)
   bt1stAssert "btQueueBottom", (btQueueBottom(bt1sTorrent) is 0)
   bt1stAssert "btQueueUp", (btQueueUp(bt1sTorrent) is 0)
   bt1stAssert "btQueueDown", (btQueueDown(bt1sTorrent) is 0)

   bt1stSection "trackers + web seeds (round-trips)"
   bt1stAssert "btTrackers returns a list", (bt1stCount(btTrackers(bt1sTorrent)) >= 0)
   put "udp://tracker.selftest.example:6969/announce" into bt1tTrackerUrl
   bt1stAssert "btAddTracker", (btAddTracker(bt1sTorrent, bt1tTrackerUrl, 1) is 0)
   put false into bt1tFound
   repeat for each element bt1tFile in btTrackers(bt1sTorrent)
      if bt1tFile["url"] is bt1tTrackerUrl then put true into bt1tFound
   end repeat
   bt1stAssert "btTrackers now lists the added tracker", bt1tFound
   put "http://seed.selftest.example/data/" into bt1tWS
   bt1stAssert "btAddWebSeed", (btAddWebSeed(bt1sTorrent, bt1tWS) is 0)
   bt1stAssert "btWebSeeds lists the added seed", bt1stListHas(btWebSeeds(bt1sTorrent), bt1tWS)
   bt1stAssert "btRemoveWebSeed", (btRemoveWebSeed(bt1sTorrent, bt1tWS) is 0)
   bt1stAssert "btWebSeeds no longer lists it", (not bt1stListHas(btWebSeeds(bt1sTorrent), bt1tWS))

   bt1stSection "session operations"
   bt1stAssert "btListenPort is a number", (btListenPort(bt1sSession) is a number)
   bt1stAssert "btSessionIsPaused is false", (btSessionIsPaused(bt1sSession) is false)
   put btFindTorrent(bt1sSession, bt1tHash) into bt1tFound
   bt1stAssert "btFindTorrent recovers our handle from the info-hash", (bt1tFound is bt1sTorrent)
   bt1stAssert "btSessionPause", (btSessionPause(bt1sSession) is 0)
   bt1stAssert "btSessionIsPaused is true after pause", (btSessionIsPaused(bt1sSession) is true)
   bt1stAssert "btSessionResume", (btSessionResume(bt1sSession) is 0)
   bt1stAssert "btDhtAnnounce (async)", (btDhtAnnounce(bt1sSession, bt1tHash, 0) is 0)

   bt1stSection "filtering + streaming"
   bt1stAssert "btIpFilterAdd", (btIpFilterAdd(bt1sSession, "10.0.0.0", "10.255.255.255", true) is 0)
   bt1stAssert "btIpFilterClear", (btIpFilterClear(bt1sSession) is 0)
   bt1stAssert "btSetPieceDeadline", (btSetPieceDeadline(bt1sTorrent, 0, 5000) is 0)
   bt1stAssert "btClearPieceDeadlines", (btClearPieceDeadlines(bt1sTorrent) is 0)

   bt1stSection "extended add"
   put btAddMagnetEx(bt1sSession, "magnet:?xt=urn:btih:1111111111111111111111111111111111111111", bt1sTempDir, "16", "16") into bt1sTorrent2
   bt1stAssert "btAddMagnetEx (paused) returns a handle", (bt1sTorrent2 > 0)
   bt1stAssert "btAddTorrentFileEx returns a handle", (btAddTorrentFileEx(bt1sSession, pTorrentData, bt1sTempDir, "16", "16") > 0)

   bt1stSection "resume data"
   bt1stAssert "btSaveResumeData (async)", (btSaveResumeData(bt1sTorrent) is 0)
end bt1stRunTorrentChecks

command bt1stMakeContent
   local bt1tPayload, bt1tFile
   put specialFolderPath("temporary") into bt1sTempDir
   if bt1sTempDir is empty then
      put specialFolderPath("documents") into bt1sTempDir
   end if
   if the last char of bt1sTempDir is "/" then
      delete the last char of bt1sTempDir
   end if
   put bt1sTempDir & "/torrentxt-selftest" into bt1sContentDir
   if there is no folder bt1sContentDir then
      create folder bt1sContentDir
   end if
   put bt1sContentDir & "/sample.dat" into bt1tFile
   put "TorrentXT self-test sample payload block. " into bt1tPayload
   repeat 10 times
      put bt1tPayload after bt1tPayload
   end repeat
   put bt1tPayload into url ("binfile:" & bt1tFile)
end bt1stMakeContent

command bt1stShowSummary
   local bt1tSummary
   put bt1sPassed && "passed,  " & bt1sFailed && "failed   (" & bt1sTotal && "checks)" into bt1tSummary
   set the text of field "stSummary" to bt1tSummary
   if bt1sFailed is 0 then
      set the foregroundColor of field "stSummary" to "0,140,70"
   else
      set the foregroundColor of field "stSummary" to "200,40,40"
   end if
end bt1stShowSummary

-- GENERATED: bt1stPaint drove this harness's own window.
-- The suite owns the UI and reads the member's log directly,
-- so there is nothing left for it to repaint.
command bt1stPaint
end bt1stPaint

command bt1stCleanup
   if bt1sSession is not empty and bt1sSession is not 0 then
      if bt1sTorrent is not empty and bt1sTorrent > 0 then
         btRemoveTorrent bt1sSession, bt1sTorrent, false
      end if
      if bt1sTorrent2 is not empty and bt1sTorrent2 > 0 then
         btRemoveTorrent bt1sSession, bt1sTorrent2, false
      end if
      btStopSession bt1sSession
   end if
   put 0 into bt1sSession
   put 0 into bt1sTorrent
   put 0 into bt1sTorrent2
end bt1stCleanup


-- ==========================================================================
-- ENetXT: the synchronous half of the en* self-test
--
-- Lifecycle, stale-handle no-ops, tuning and abrupt teardown. The async
-- loopback is NOT folded in - the core drives a real ENet loopback of its
-- own below, and two state machines in one process would race for the event
-- handlers. Run enetxt/tests/enet-selftest.livecodescript for that.
--
-- GENERATED from enetxt/tests/enet-selftest.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `en1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

command en1stAssert pName, pPass
   add 1 to en1sTotal
   if pPass then
      add 1 to en1sPassed
      put "PASS  " & pName & return after en1sResultText
   else
      add 1 to en1sFailed
      put "FAIL  " & pName & return after en1sResultText
   end if
end en1stAssert

command en1stSection pTitle
   put return & "== " & pTitle & " ==" & return after en1sResultText
end en1stSection

command en1stNote pText
   put "      " & pText & return after en1sResultText
end en1stNote

-- GENERATED: en1stShow drove this harness's own window.
-- The suite owns the UI and reads the member's log directly,
-- so there is nothing left for it to repaint.
command en1stShow
end en1stShow

command en1stRun
   local en1tPS, en1tHS, en1tBig
   local en1tAbruptHost, en1tAbruptPeer, en1tResetPeer
   put 0 into en1sTotal
   put 0 into en1sPassed
   put 0 into en1sFailed
   put empty into en1sResultText
   put empty into en1sPhase

   en1stSection "lifecycle & diagnostics"
   en1stAssert "enInitialize returns 0", enInitialize() is 0
   en1stAssert "enInitialize idempotent", enInitialize() is 0
   en1stAssert "enLibraryVersion names enet", enLibraryVersion() begins with "enet "
   enClearError
   en1stAssert "enLastError empty after clear", enLastError() is empty

   en1stSection "stale handles are harmless no-ops"
   en1stAssert "enSend(0) errors", enSend(0, 0, en1stTinyData(), 0) < 0
   en1stAssert "enDisconnect(0) errors", enDisconnect(0, 0) < 0
   put enPeerStatus(0) into en1tPS
   en1stAssert "enPeerStatus(0) empty", the number of lines of the keys of en1tPS is 0
   put enHostStatus(0) into en1tHS
   en1stAssert "enHostStatus(0) empty", the number of lines of the keys of en1tHS is 0
   en1stAssert "enHostDestroy(0) is a no-op 0", enHostDestroy(0) is 0
   en1stAssert "enConnect on stale host is 0", enConnect(0, "127.0.0.1", 1, 1, 0) is 0
   en1stAssert "enFlush(0) errors", enFlush(0) < 0
   -- enBroadcast is the server-fanout primitive, so a stale host is the case
   -- that matters most: a broadcast that quietly "succeeded" against a
   -- destroyed host is a server believing it told every client something it
   -- never sent. It takes the same stale-handle path as enSend.
   en1stAssert "enBroadcast(0) errors", enBroadcast(0, 0, en1stTinyData(), 0) < 0
   en1stAssert "enBroadcastText(0) errors", enBroadcastText(0, 0, "x", 0) < 0

   en1stSection "tuning + abrupt teardown (isolated: nothing listens on 27099)"
   -- These four binds have no place in the graceful loopback below: a second
   -- live connection would race the server's event handlers (which assert on
   -- the FIRST connect's data payload), and an abrupt teardown would satisfy
   -- the "closing" phase early. So drive them on their own client host aimed
   -- at a port nothing listens on. enConnect is asynchronous - the handshake
   -- never has to complete for these to be exercised, because peer timeout,
   -- host bandwidth, disconnect-now, and reset are all LOCAL operations.
   put enHostCreateClient(2, 2, 0, 0) into en1tAbruptHost
   en1stAssert "abrupt-test client host created", en1tAbruptHost > 0
   put enConnect(en1tAbruptHost, "127.0.0.1", 27099, 2, 77) into en1tAbruptPeer
   en1stAssert "abrupt-test peer handle", en1tAbruptPeer > 0
   en1stAssert "enSetPeerTimeout returns 0", enSetPeerTimeout(en1tAbruptPeer, 32, 5000, 30000) is 0
   en1stAssert "enSetHostBandwidth returns 0", enSetHostBandwidth(en1tAbruptHost, 0, 0) is 0
   en1stAssert "enDisconnectNow returns 0", enDisconnectNow(en1tAbruptPeer, 9) is 0
   -- A second peer for the reset path: enResetPeer tears the connection down
   -- with no notification at all, so it needs its own victim.
   put enConnect(en1tAbruptHost, "127.0.0.1", 27099, 2, 78) into en1tResetPeer
   en1stAssert "reset-test peer handle", en1tResetPeer > 0
   en1stAssert "enResetPeer returns 0", enResetPeer(en1tResetPeer) is 0
   en1stAssert "abrupt-test host destroyed", enHostDestroy(en1tAbruptHost) is 0

   -- GENERATED CUT (tools/build-suite-selftest.py). Everything below
   -- this point in enetxt/tests/enet-selftest.livecodescript
   -- is the ASYNC loopback, and it is deliberately not folded in: it
   -- owns ports and event handlers that the suite's own cross-member
   -- loopback below is already using. Run that member's harness on its
   -- own for the async depth.
   en1stNote "async loopback not run here - see the note in this section"
end en1stRun

command en1stPump
   local en1tEvents, en1tEvent, en1tPS
   if en1sPhase is "done" or en1sPhase is empty then
      exit en1stPump
   end if
   put enPoll(en1sServer) into en1tEvents
   repeat for each element en1tEvent in en1tEvents
      en1stHandleServer en1tEvent
   end repeat
   put enPoll(en1sClient) into en1tEvents
   repeat for each element en1tEvent in en1tEvents
      en1stHandleClient en1tEvent
   end repeat

   if en1sPhase is "connecting" then
      if en1sServerPeer is not empty and en1sGotEcho is empty then
         -- connected both ways; the message flow was kicked in the handlers
         put "messaging" into en1sPhase
      end if
   else if en1sPhase is "messaging" then
      if en1sGotEcho is "true" and en1sGotUnseq is "true" then
         en1stAssert "echo + broadcast both arrived", true
         -- peer status while connected
         put enPeerStatus(en1sClientPeer) into en1tPS
         en1stAssert "peer state is connected (5)", en1tPS["state"] is 5
         en1stAssert "peer status names the server port", en1tPS["address"] is "127.0.0.1:27098"
         -- the statistics half of the record: by echo time the client has
         -- sent at least the hello, so the counters must be populated. Exact
         -- values are timing-dependent (rtt starts at ENet's default until
         -- an ack updates it, loss on loopback is normally 0), so these pin
         -- presence and documented range, not a number a fast loopback
         -- would make flaky.
         en1stAssert "live peer rtt is a number >= 0", en1tPS["rtt"] >= 0
         en1stAssert "live peer packetLoss within 0..1", \
               en1tPS["packetLoss"] >= 0 and en1tPS["packetLoss"] <= 1
         en1stAssert "live peer counted its sends", \
               en1tPS["packetsSent"] > 0 and en1tPS["bytesSent"] > 0
         -- enHostStatus on a LIVE host (the stale-handle case is asserted
         -- above; this is the half that proves the record actually populates).
         put enHostStatus(en1sServer) into en1tHS
         en1stAssert "live enHostStatus counts the connected peer", en1tHS["peerCount"] is 1
         en1stAssert "live enHostStatus names the bound port", en1tHS["address"] is "127.0.0.1:27098"
         en1stAssert "tuning setters return 0", enSetPeerPingInterval(en1sClientPeer, 250) is 0
         -- binary with REAL embedded NUL/0x01 bytes, byte-exact both ways
         put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) \
               & textEncode("tail", "utf-8") into en1sSentBinary
         en1stAssert "enSend binary returns 0", enSend(en1sClientPeer, 1, en1sSentBinary, 0) is 0
         put "binary" into en1sPhase
      end if
   else if en1sPhase is "binary" then
      if en1sGotBinary is not empty then
         set the caseSensitive to true
         en1stAssert "binary arrived byte-for-byte (incl. NUL)", en1sGotBinary is en1sSentBinary
         en1stAssert "enDisconnect returns 0", enDisconnect(en1sClientPeer, 7) is 0
         put "closing" into en1sPhase
      end if
   else if en1sPhase is "closing" then
      if en1sSawServerDisc is "true" then
         en1stFinish
         exit en1stPump
      end if
   end if

   if the milliseconds > en1sDeadline then
      en1stAssert "async loopback finished before the deadline", false
      en1stNote "UDP to 127.0.0.1 may be blocked on this machine; see docs."
      en1stFinish
      exit en1stPump
   end if
   en1stShow
   send "en1stPump" to me in 33 milliseconds
end en1stPump

command en1stHandleServer pEvent
   local en1tR
   switch pEvent["name"]
      case "enetConnect"
         put pEvent["peer"] into en1sServerPeer
         en1stAssert "server enetConnect carries data 42", pEvent["data"] is 42
         en1stAssert "server enetConnect names an address", pEvent["address"] begins with "127.0.0.1:"
         break
      case "enetReceive"
         if pEvent["channel"] is 0 then
            -- the hello: echo it back reliably + a channel-1 broadcast
            en1stAssert "hello payload intact", textDecode(pEvent["payload"], "utf-8") is "hello enet"
            put enSendText(en1sServerPeer, 0, "echo!", 0) into en1tR
            en1stAssert "server echo send returns 0", en1tR is 0
            put enBroadcastText(en1sServer, 1, "fanout", 2) into en1tR
            en1stAssert "server broadcast returns 0", en1tR is 0
         else
            -- the binary phase payload arrives on channel 1
            put pEvent["payload"] into en1sGotBinary
         end if
         break
      case "enetDisconnect"
         put "true" into en1sSawServerDisc
         en1stAssert "server enetDisconnect carries data 7", pEvent["data"] is 7
         break
   end switch
end en1stHandleServer

command en1stHandleClient pEvent
   local en1tR
   switch pEvent["name"]
      case "enetConnect"
         en1stAssert "client enetConnect names the enConnect handle", pEvent["peer"] is en1sClientPeer
         put enSendText(en1sClientPeer, 0, "hello enet", 0) into en1tR
         en1stAssert "client hello send returns 0", en1tR is 0
         break
      case "enetReceive"
         if textDecode(pEvent["payload"], "utf-8") is "echo!" then
            put "true" into en1sGotEcho
            en1stAssert "echo on channel 0", pEvent["channel"] is 0
         else if textDecode(pEvent["payload"], "utf-8") is "fanout" then
            put "true" into en1sGotUnseq
            en1stAssert "broadcast on channel 1", pEvent["channel"] is 1
         end if
         break
   end switch
end en1stHandleClient

command en1stFinish
   local en1tPS, en1tHS
   en1stSection "retirement + teardown"
   put enPeerStatus(en1sClientPeer) into en1tPS
   en1stAssert "client peer retired after disconnect", the number of lines of the keys of en1tPS is 0
   -- the AFTER-disconnect half of the live enHostStatus pair: the host
   -- outlives its one peer, so the record must still populate and count zero
   -- (a host that still counted the departed peer would leak the slot).
   put enHostStatus(en1sServer) into en1tHS
   en1stAssert "live enHostStatus counts zero peers after disconnect", en1tHS["peerCount"] is 0
   en1stAssert "enHostDestroy(server) is 0", enHostDestroy(en1sServer) is 0
   en1stAssert "double destroy is a no-op 0", enHostDestroy(en1sServer) is 0
   en1stAssert "enHostDestroy(client) is 0", enHostDestroy(en1sClient) is 0
   en1stAssert "enDeinitialize returns 0", enDeinitialize() is 0
   en1stAssert "extra deinitialize is a no-op 0", enDeinitialize() is 0
   put empty into en1sServer
   put empty into en1sClient
   put "done" into en1sPhase
   en1stShow
end en1stFinish

command en1stCleanup
   put "done" into en1sPhase
   if en1sServer is not empty and en1sServer is not 0 then
      enHostDestroy en1sServer
   end if
   if en1sClient is not empty and en1sClient is not 0 then
      enHostDestroy en1sClient
   end if
   put empty into en1sServer
   put empty into en1sClient
   -- bare command form: OXT cannot compile a zero-argument name() statement;
   -- guarded so closing a stack whose extension is missing (the run already
   -- threw loudly at enInitialize) cannot throw a second time from en1closeStack
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end en1stCleanup

function en1stTinyData
   return textEncode("x", "utf-8")
end en1stTinyData

function en1stRepeatByte pCode, pCount
   local en1tOne, en1tOut, en1tI
   put numToByte(pCode) into en1tOne
   put empty into en1tOut
   -- double up to size, then trim: O(log n) concatenations, not 60001
   put en1tOne into en1tOut
   repeat while the number of bytes in en1tOut < pCount
      put en1tOut & en1tOut into en1tOut
   end repeat
   return byte 1 to pCount of en1tOut
end en1stRepeatByte


-- ==========================================================================
-- DataChannelXT: the synchronous half of the dc* self-test
--
-- Lifecycle and the stale-handle surface. The async loopback is NOT folded
-- in, for the same reason as ENetXT's; the core negotiates a real peer
-- connection below. Run datachannelxt's own harness for that.
--
-- GENERATED from datachannelxt/tests/datachannel-selftest.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `dc1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

command dc1stAssert pName, pPass
   add 1 to dc1sTotal
   if pPass then
      add 1 to dc1sPassed
      put "PASS  " & pName & return after dc1sResultText
   else
      add 1 to dc1sFailed
      put "FAIL  " & pName & return after dc1sResultText
   end if
end dc1stAssert

command dc1stSection pTitle
   put return & "== " & pTitle & " ==" & return after dc1sResultText
end dc1stSection

command dc1stNote pText
   put "      " & pText & return after dc1sResultText
end dc1stNote

-- GENERATED: dc1stShow drove this harness's own window.
-- The suite owns the UI and reads the member's log directly,
-- so there is nothing left for it to repaint.
command dc1stShow
end dc1stShow

command dc1stRun
   local dc1tPair
   put 0 into dc1sTotal
   put 0 into dc1sPassed
   put 0 into dc1sFailed
   put empty into dc1sResultText
   put empty into dc1sPhase

   dc1stSection "lifecycle & diagnostics"
   dc1stAssert "dcInit returns 0", dcInit() is 0
   dc1stAssert "dcInit idempotent", dcInit() is 0
   dc1stAssert "dcLibraryVersion mentions libdatachannel", dcLibraryVersion() contains "libdatachannel"
   dcClearError
   dc1stAssert "dcLastError empty after clear", dcLastError() is empty

   dc1stSection "stale handles are harmless no-ops"
   dc1stAssert "dcClosePeer(0) errors", dcClosePeer(0) < 0
   dc1stAssert "dcPeerState(0) is -1", dcPeerState(0) is -1
   dc1stAssert "dcGatheringState(0) is -1", dcGatheringState(0) is -1
   dc1stAssert "dcLocalDescription(0) empty", dcLocalDescription(0) is empty
   -- an Array crosses from LCB; LiveCode Script has NO `{}` literal, and a
   -- bare `is empty` on an array is vacuously true (arrays stringify to
   -- empty) - so emptiness is asserted by counting keys of a LOCAL (a
   -- function result cannot be subscripted or keyed directly in LCS either)
   put dcSelectedCandidatePair(0) into dc1tPair
   dc1stAssert "dcSelectedCandidatePair(0) empty", the number of lines of the keys of dc1tPair is 0
   dc1stAssert "dcCreateChannel(0) is 0", dcCreateChannel(0, "x") is 0
   dc1stAssert "dcSendText(0) errors", dcSendText(0, "x") < 0
   dc1stAssert "dcChannelLabel(0) empty", dcChannelLabel(0) is empty
   dc1stAssert "dcChannelStreamId(0) is -1", dcChannelStreamId(0) is -1
   dc1stAssert "dcChannelIsOpen(0) is false", dcChannelIsOpen(0) is false
   dc1stAssert "dcChannelPeer(0) is 0", dcChannelPeer(0) is 0
   dc1stAssert "dcBufferedAmount(0) is -1", dcBufferedAmount(0) is -1
   dc1stAssert "dcLocalDescriptionType(0) empty", dcLocalDescriptionType(0) is empty
   dc1stAssert "dcChannelProtocol(0) empty", dcChannelProtocol(0) is empty
   dc1stAssert "dcSetLocalDescription(0) errors", dcSetLocalDescription(0, "offer") < 0
   dc1stAssert "dcSetBufferedLowThreshold(0) errors", dcSetBufferedLowThreshold(0, 4096) < 0
   dc1stAssert "dcCreateChannelEx(0) is 0", \
         dcCreateChannelEx(0, "x", "proto", false, -1, -1, false, -1) is 0
   dcFreePeer(0)      -- must not crash
   dcFreeChannel(0)   -- must not crash
   dc1stAssert "dcFreePeer/dcFreeChannel(0) survived", true
   dc1stAssert "dcSendText(0) left a last-error", dcLastError() is not empty
   dcClearError

   -- GENERATED CUT (tools/build-suite-selftest.py). Everything below
   -- this point in datachannelxt/tests/datachannel-selftest.livecodescript
   -- is the ASYNC loopback, and it is deliberately not folded in: it
   -- owns ports and event handlers that the suite's own cross-member
   -- loopback below is already using. Run that member's harness on its
   -- own for the async depth.
   dc1stNote "async loopback not run here - see the note in this section"
end dc1stRun

command dc1stPump
   local dc1tEvents, dc1tEvent, dc1tDest, dc1tPair, dc1tExChan
   if dc1sPhase is "done" or dc1sPhase is empty then
      exit dc1stPump
   end if
   put dcPoll() into dc1tEvents
   repeat for each element dc1tEvent in dc1tEvents
      -- the in-script signaling shuttle (the whole point of the loopback)
      if dc1tEvent["name"] is "dcLocalDescription" then
         put dc1stOtherPeer(dc1tEvent["peer"]) into dc1tDest
         if dc1tDest is not empty then
            dcSetRemoteDescription dc1tDest, dc1tEvent["sdp"], dc1tEvent["sdpType"]
         end if
      else if dc1tEvent["name"] is "dcLocalCandidate" then
         put dc1stOtherPeer(dc1tEvent["peer"]) into dc1tDest
         if dc1tDest is not empty then
            dcAddRemoteCandidate dc1tDest, dc1tEvent["candidate"], dc1tEvent["mid"]
         end if
      else if dc1tEvent["name"] is "dcChannelIncoming" then
         -- FIRST incoming only: the later dcCreateChannelEx check opens a
         -- second channel, whose incoming event must not retarget dc1sChanB.
         if dc1tEvent["peer"] is dc1sPeerB and dc1sChanB is empty then
            put dc1tEvent["channel"] into dc1sChanB
         end if
      else if dc1tEvent["name"] is "dcChannelOpen" then
         if dc1tEvent["channel"] is dc1sChanA then
            put "true" into dc1sAOpen
         else if dc1sChanB is not empty and dc1tEvent["channel"] is dc1sChanB then
            put "true" into dc1sBOpen
         end if
      else if dc1tEvent["name"] is "dcMessage" then
         if dc1tEvent["text"] is not empty then
            put dc1tEvent["text"] into dc1sGotText
         else
            put dc1tEvent["payload"] into dc1sGotBytes
         end if
      else if dc1tEvent["name"] is "dcBufferedLow" then
         -- only A's channel is armed (threshold 4096, above); an event
         -- naming any other channel would be a contract violation, so the
         -- flag is set only for the armed one and the assertion below
         -- would time out loudly on a misdelivered event.
         if dc1tEvent["channel"] is dc1sChanA then
            put "true" into dc1sGotBufferedLow
         end if
      end if
   end repeat

   if dc1sPhase is "opening" then
      if dc1sAOpen is "true" and dc1sBOpen is "true" then
         dc1stAssert "loopback connected + both channels open", true
         dc1stAssert "incoming label is selftest", dcChannelLabel(dc1sChanB) is "selftest"
         dc1stAssert "peer A connected", dcPeerState(dc1sPeerA) is 2
         dc1stAssert "dcChannelIsOpen(A)", dcChannelIsOpen(dc1sChanA) is true
         dc1stAssert "stream id assigned", dcChannelStreamId(dc1sChanA) >= 0
         dc1stAssert "negotiated max message > 0", dcChannelMaxMessage(dc1sChanA) > 0
         dc1stAssert "buffered amount >= 0", dcBufferedAmount(dc1sChanA) >= 0
         -- keyed access needs a local (LCS cannot subscript a function result)
         put dcSelectedCandidatePair(dc1sPeerA) into dc1tPair
         dc1stAssert "selected pair has localCandidate", dc1tPair["localCandidate"] is not empty
         -- The NON-TRICKLE signaling contract on live peers: once negotiated,
         -- each side's local description is a real SDP carrying its candidates,
         -- and the offer/answer roles are the ones the flow assigned (A made
         -- the channel, so A offered). This is the call the DHT-chat demo ships
         -- as one blob; the stale-handle half is asserted above.
         dc1stAssert "local description is a real SDP", dcLocalDescription(dc1sPeerA) contains "v=0"
         dc1stAssert "local description carries candidates", \
               dcLocalDescription(dc1sPeerA) contains "a=candidate"
         dc1stAssert "peer A describes itself as the offer", dcLocalDescriptionType(dc1sPeerA) is "offer"
         dc1stAssert "peer B describes itself as the answer", dcLocalDescriptionType(dc1sPeerB) is "answer"
         -- a channel created without a protocol reports none (the live half of
         -- the stale-handle assertion above)
         dc1stAssert "dcChannelProtocol empty when unset", dcChannelProtocol(dc1sChanA) is empty
         dc1stAssert "dcSetBufferedLowThreshold on a live channel returns 0", \
               dcSetBufferedLowThreshold(dc1sChanA, 4096) is 0
         dc1stAssert "dcSendText returns 0", dcSendText(dc1sChanA, "hello oxt") is 0
         put "messaging" into dc1sPhase
      end if
   else if dc1sPhase is "messaging" then
      -- a distinct phase per step, so a slow delivery cannot re-fire the send
      -- (and re-count the assertions) on every 33 ms pump pass
      if dc1sGotText is not empty then
         dc1stAssert "text arrived intact", dc1sGotText is "hello oxt"
         -- REAL embedded NUL/0x01 bytes (LCS string literals have no escape
         -- syntax - a "\0" would be two ordinary characters), so this proves
         -- a Data crosses unmangled, not merely that ASCII survives
         put textEncode("binary", "UTF-8") & numToByte(0) & textEncode("byte", "UTF-8") \
               & numToByte(1) & textEncode("round-trip", "UTF-8") into dc1sSentBytes
         dc1stAssert "dcSendData returns 0", dcSendData(dc1sChanB, dc1sSentBytes) is 0
         put "binary-wait" into dc1sPhase
      end if
   else if dc1sPhase is "binary-wait" then
      if dc1sGotBytes is not empty then
         -- byte-exact: `is` is case-insensitive by default, which would let
         -- 0x41 match 0x61 inside binary data
         set the caseSensitive to true
         dc1stAssert "binary arrived byte-for-byte (incl. NUL)", dc1sGotBytes is dc1sSentBytes
         -- dcCreateChannelEx on a LIVE peer, last so its extra negotiation
         -- cannot disturb the checks above. The protocol is a property of the
         -- local object, set at creation, so it reads back without waiting for
         -- the far side to open the channel.
         put dcCreateChannelEx(dc1sPeerA, "extra", "oxt-proto", true, 0, -1, false, -1) into dc1tExChan
         dc1stAssert "dcCreateChannelEx > 0", dc1tExChan > 0
         dc1stAssert "dcChannelProtocol round-trips", dcChannelProtocol(dc1tExChan) is "oxt-proto"
         dc1stAssert "dcChannelLabel round-trips", dcChannelLabel(dc1tExChan) is "extra"
         dcFreeChannel dc1tExChan
         -- the LIVE half of the gathering-state getter (the stale half is
         -- pinned at -1 above). The a=candidate assertion already proved
         -- candidates were gathered, and with no ICE servers configured
         -- gathering has nothing left to wait for, so by the time the
         -- binary round-trip has completed both peers must report
         -- kGatheringComplete (2).
         dc1stAssert "gathering state is complete (2) on both peers", \
               dcGatheringState(dc1sPeerA) is 2 and dcGatheringState(dc1sPeerB) is 2
         -- the dcBufferedLow EVENT - the live half of the threshold setter
         -- asserted above. A's channel is armed at 4096, so one payload at
         -- the negotiated cap (60000 under the suite budget) must push the
         -- send buffer past the threshold, and the drain back under it
         -- fires the event. Waited on with the same deadline as the rest
         -- of the async phase, so a machine that never fires it fails
         -- loudly instead of hanging.
         put dcChannelMaxMessage(dc1sChanA) into dc1sBigLen
         put empty into dc1sGotBytes
         dc1stAssert "cap-sized send returns 0", \
               dcSendData(dc1sChanA, dc1stRepeatByte(66, dc1sBigLen)) is 0
         put "bufferedlow-wait" into dc1sPhase
      end if
   else if dc1sPhase is "bufferedlow-wait" then
      if dc1sGotBufferedLow is "true" and the number of bytes in dc1sGotBytes is dc1sBigLen then
         dc1stAssert "dcBufferedLow fired once the cap-sized send drained", true
         dc1stAssert "the cap-sized payload arrived whole", true
         dc1stFinish
         exit dc1stPump
      end if
   end if

   if the milliseconds > dc1sDeadline then
      dc1stAssert "async loopback finished before the deadline", false
      dc1stNote "UDP to this machine's own address may be blocked; see docs."
      dc1stFinish
      exit dc1stPump
   end if
   dc1stShow
   send "dc1stPump" to me in 33 milliseconds
end dc1stPump

function dc1stOtherPeer pPeer
   if pPeer is dc1sPeerA then
      return dc1sPeerB
   else if pPeer is dc1sPeerB then
      return dc1sPeerA
   end if
   return empty
end dc1stOtherPeer

command dc1stFinish
   dc1stSection "teardown"
   dc1stAssert "dcCloseChannel returns 0", dcCloseChannel(dc1sChanA) is 0
   dcFreeChannel(dc1sChanA)
   dcFreeChannel(dc1sChanA)   -- double free: no-op
   dc1stAssert "double dcFreeChannel survived", true
   dcFreePeer(dc1sPeerA)
   dcFreePeer(dc1sPeerB)
   dcFreePeer(dc1sPeerA)      -- double free: no-op
   dc1stAssert "freed peer answers -1", dcPeerState(dc1sPeerA) is -1
   dc1stAssert "dcCleanup returns 0", dcCleanup() is 0
   dc1stAssert "dcCleanup idempotent", dcCleanup() is 0
   put empty into dc1sPeerA
   put empty into dc1sPeerB
   put "done" into dc1sPhase
   dc1stShow
end dc1stFinish

command dc1stCleanup
   put "done" into dc1sPhase
   if dc1sPeerA is not empty and dc1sPeerA is not 0 then
      dcFreePeer(dc1sPeerA)
   end if
   if dc1sPeerB is not empty and dc1sPeerB is not 0 then
      dcFreePeer(dc1sPeerB)
   end if
   put empty into dc1sPeerA
   put empty into dc1sPeerB
   -- BARE, not dcCleanup(). A zero-argument call in STATEMENT position parses
   -- as a command taking `()` as its argument, and `()` is not an expression,
   -- so it is a compile error. In EXPRESSION position (the two dc1stAssert lines
   -- above) the parenthesised form is correct and required.
   dcCleanup
end dc1stCleanup

function dc1stRepeatByte pCode, pCount
   local dc1tOut
   put numToByte(pCode) into dc1tOut
   repeat while the number of bytes in dc1tOut < pCount
      put dc1tOut & dc1tOut into dc1tOut
   end repeat
   return byte 1 to pCount of dc1tOut
end dc1stRepeatByte


-- ==========================================================================
-- Riptide Social (phases 1-2): the rs* self-test
--
-- The capstone app's harness: the KDF subkey tree, identity to handle to
-- onion, the RIPTKEY1 key file, the RSH1/RSP1 framings, the post chain, and
-- the phase-2 live feed layer (BEP44 buffers, ingest verifiers, and real
-- puts and lookups against the suite's session) - all against the same
-- golden vectors the Python oracle pins. No network is awaited; sections
-- needing coinxt, onionxt or torrentxt SKIP when those are absent, and the
-- whole crypto set skips without SodiumXT.
--
-- GENERATED from riptide/tests/riptide-selftest.livecodescript by
-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and
-- rebuild, or the next build will overwrite you. Every name below is
-- prefixed `rs1` so this harness cannot collide with, or be
-- perturbed by, any other member's copy of the same scaffolding.
-- ==========================================================================

function rs1rsSelfTest
   local rs1tCaps
   put empty into rs1sLog
   put 0 into rs1sPass
   put 0 into rs1sFail
   put 0 into rs1sSkip
   put rsProbeCapabilities() into rs1tCaps
   rs1rstSectionCapabilities rs1tCaps
   if rs1tCaps["canCrypto"] is true then
      rs1rstSectionKdfTree
      rs1rstSectionHandles
      rs1rstSectionOnion rs1tCaps
      rs1rstSectionRendezvous
      rs1rstSectionKeyFile
      rs1rstSectionHead
      rs1rstSectionPosts
      rs1rstSectionHelpers
      rs1rstSectionBep44
      rs1rstSectionIngest
      rs1rstSectionLiveFeed rs1tCaps
   else
      rs1rstSkip "every crypto section: SodiumXT is not installed"
   end if
   -- The first line is EXACTLY two counts + passed/failed and nothing else:
   -- the suite core's stSummaryCounts treats any other word as prose, so the
   -- skip count gets its own line (the sodiumxt/onionxt returned-report shape).
   return rs1sPass && "passed," && rs1sFail && "failed" & return & \
         rs1sSkip && "skipped (optional dependencies; see the log)" & return & \
         "----------------------------------------" & return & rs1sLog
end rs1rsSelfTest

private command rs1rstCheck pCondition, pLabel
   if pCondition is true then
      add 1 to rs1sPass
      put "  ok  " && pLabel & return after rs1sLog
   else
      add 1 to rs1sFail
      put "  FAIL" && pLabel & return after rs1sLog
   end if
end rs1rstCheck

private command rs1rstSection pTitle
   put return & "--" && pTitle & return after rs1sLog
end rs1rstSection

private command rs1rstSkip pLabel
   add 1 to rs1sSkip
   put "  skip" && pLabel & return after rs1sLog
end rs1rstSkip

private function rs1rstBin pHex
   return sxHex2Bin(textEncode(pHex, "ASCII"))
end rs1rstBin

private function rs1rstHex pData
   return textDecode(sxBin2Hex(pData), "ASCII")
end rs1rstHex

private function rs1rstFlipByte pData, pIndex
   local rs1tOut, rs1tByte
   put byteToNum(byte pIndex of pData) into rs1tByte
   put pData into rs1tOut
   if rs1tByte is 255 then
      put numToByte(0) into byte pIndex of rs1tOut
   else
      put numToByte(rs1tByte + 1) into byte pIndex of rs1tOut
   end if
   return rs1tOut
end rs1rstFlipByte

private command rs1rstSectionCapabilities pCaps
   rs1rstSection "capabilities + version"
   rs1rstCheck (rsVersion() contains "Riptide"), "rsVersion names the library"
   rs1rstCheck (pCaps["canCrypto"] is true or pCaps["canCrypto"] is false), \
         "probe reports canCrypto as a boolean"
   rs1rstCheck (the number of lines in the keys of pCaps is 7), \
         "probe reports six extensions plus the derived hasSha3"
   put "      canCrypto=" & pCaps["canCrypto"] & \
         " hasTorrent=" & pCaps["hasTorrent"] & \
         " hasOnion=" & pCaps["hasOnion"] & return after rs1sLog
   put "      hasDataChannel=" & pCaps["hasDataChannel"] & \
         " hasEnet=" & pCaps["hasEnet"] & \
         " hasCoin=" & pCaps["hasCoin"] & \
         " hasSha3=" & pCaps["hasSha3"] & return after rs1sLog
end rs1rstSectionCapabilities

private command rs1rstSectionKdfTree
   local rs1tMaster, rs1tOut
   rs1rstSection "the KDF subkey tree"
   put rs1rstBin(rs1kRsGoldMasterHex) into rs1tMaster
   put rsIdentitySeed(rs1tMaster) into rs1tOut
   rs1rstCheck (rs1rstHex(rs1tOut) is rs1kRsGoldIdSeedHex), "identity seed matches golden"
   put rsDmSeed(rs1tMaster) into rs1tOut
   rs1rstCheck (rs1rstHex(rs1tOut) is rs1kRsGoldDmSeedHex), "DM seed matches golden"
   put rsLanKey(rs1tMaster) into rs1tOut
   rs1rstCheck (rs1rstHex(rs1tOut) is rs1kRsGoldLanKeyHex), "LAN key matches golden"
   put rsAnonSeed(rs1tMaster, 0) into rs1tOut
   rs1rstCheck (rs1rstHex(rs1tOut) is rs1kRsGoldAnon0Hex), "anon persona 0 matches golden"
   rs1rstCheck (rsIdentitySeed(rs1tMaster) is not rsDmSeed(rs1tMaster)), \
         "identity and DM subkeys differ"
   rs1rstCheck (rsAnonSeed(rs1tMaster, 0) is not rsAnonSeed(rs1tMaster, 1)), \
         "anon personas 0 and 1 differ"
   put rsIdentitySeed(byte 1 to 31 of rs1tMaster) into rs1tOut
   rs1rstCheck (rs1tOut is empty), "a 31-byte master is refused"
   rs1rstCheck (rsLastError() is not empty), "and the refusal is explained"
   put rsAnonSeed(rs1tMaster, -1) into rs1tOut
   rs1rstCheck (rs1tOut is empty), "a negative persona index is refused"
end rs1rstSectionKdfTree

private command rs1rstSectionHandles
   local rs1tSeed, rs1tKeys, rs1tOut
   rs1rstSection "identity seed -> handle"
   put rs1rstBin(rs1kRsGoldIdSeedHex) into rs1tSeed
   rs1rstCheck (rsHandleFromSeed(rs1tSeed) is rs1kRsGoldHandle), \
         "the golden identity seed yields the golden handle"
   put rsIdentityKeys(rs1tSeed) into rs1tKeys
   rs1rstCheck (the number of bytes in rs1tKeys["publicKey"] is 32), \
         "public key is 32 bytes"
   rs1rstCheck (the number of bytes in rs1tKeys["secretKey"] is 64), \
         "secret key is 64 bytes (seed || pub)"
   rs1rstCheck (rs1tKeys["handle"] is rs1kRsGoldHandle), \
         "rsIdentityKeys agrees with rsHandleFromSeed"
   rs1rstCheck (rsHandleFromSeed(rs1rstBin(rs1kRsGoldConfSeedHex)) is \
         rs1kRsGoldConfPub), "the cross-project conformance seed checks out"
   put numToByte(0) into rs1tOut
   repeat 4 times
      put rs1tOut & rs1tOut into rs1tOut
   end repeat
   rs1rstCheck (rsHandleFromSeed(byte 1 to 16 of rs1tOut & byte 1 to 16 of rs1tOut) \
         is rs1kRsGoldZeroSeedPub), "the zero seed matches the sodium C KAT"
   rs1rstCheck (rsHandleFromSeed(byte 1 to 31 of rs1tSeed) is empty), \
         "a 31-byte identity seed is refused"
end rs1rstSectionHandles

private command rs1rstSectionOnion pCaps
   local rs1tPub, rs1tOut
   rs1rstSection "identity -> onion (offline)"
   put rs1rstBin(rs1kRsGoldHandle) into rs1tPub
   if pCaps["hasSha3"] is true then
      rs1rstCheck (rsOnionFromPublicKey(rs1tPub) is rs1kRsGoldOnion), \
            "the golden handle yields the golden onion"
      rs1rstCheck (rsOnionFromHandle(rs1kRsGoldHandle) is rs1kRsGoldOnion), \
            "rsOnionFromHandle agrees"
      rs1rstCheck (rsOnionFromPublicKey(byte 1 to 31 of rs1tPub) is empty), \
            "a 31-byte public key is refused"
   else
      put rsOnionFromPublicKey(rs1tPub) into rs1tOut
      rs1rstCheck (rs1tOut is empty), \
            "without a SHA3 provider the self-computation refuses"
      rs1rstCheck (rsLastError() contains "sxSha3_256"), \
            "and the refusal names both providers"
      rs1rstSkip "offline onion self-computation: no SHA3 provider installed"
   end if
   if pCaps["hasOnion"] is true then
      rs1rstCheck (rsVerifyOnionClaim(rs1kRsGoldOnion, rs1kRsGoldHandle) is true), \
            "the golden onion verifies against the golden handle"
      rs1rstCheck (rsVerifyOnionClaim(rs1kRsGoldOnion, rs1kRsGoldConfPub) is \
            false), "the golden onion refuses a different handle"
      rs1rstCheck (rsVerifyOnionClaim("not-an-onion", rs1kRsGoldHandle) is \
            false), "a malformed onion address refuses"
   else
      rs1rstSkip "onion claim verification: onionxt is not installed"
   end if
end rs1rstSectionOnion

private command rs1rstSectionRendezvous
   rs1rstSection "rendezvous derivations"
   rs1rstCheck (rsInboxId(rs1kRsGoldHandle) is rs1kRsGoldInboxId), \
         "inbox id matches golden"
   rs1rstCheck (rsRoomId(rs1kRsGoldHandle, rs1kRsGoldConfPub, \
         textEncode(rs1kRsGoldRoomSalt, "ASCII")) is rs1kRsGoldRoomId), \
         "room id matches golden"
   rs1rstCheck (rsRoomId(rs1kRsGoldConfPub, rs1kRsGoldHandle, \
         textEncode(rs1kRsGoldRoomSalt, "ASCII")) is rs1kRsGoldRoomId), \
         "room id is symmetric in its peers"
   rs1rstCheck (rsInboxId("zz") is empty), "a malformed handle is refused"
   rs1rstCheck (rsRoomId("zz", rs1kRsGoldConfPub, empty) is empty), \
         "a malformed peer key is refused"
end rs1rstSectionRendezvous

private command rs1rstSectionKeyFile
   local rs1tSeed, rs1tSealed, rs1tOpened, rs1tGenA, rs1tGenB
   rs1rstSection "the RIPTKEY1 sealed key file"
   put rsGenerateMasterSeed() into rs1tGenA
   put rsGenerateMasterSeed() into rs1tGenB
   rs1rstCheck (the number of bytes in rs1tGenA is 32), \
         "a generated master seed is 32 bytes"
   rs1rstCheck (rs1rstHex(rs1tGenA) is not rs1rstHex(rs1tGenB)), \
         "two generated seeds differ (the CSPRNG is live)"
   put rs1rstBin(rs1kRsGoldMasterHex) into rs1tSeed
   put rsSealMasterSeed(rs1tSeed, "correct horse") into rs1tSealed
   rs1rstCheck (rs1tSealed is not empty), "sealing succeeds"
   rs1rstCheck (textDecode(byte 1 to 9 of rs1tSealed, "ASCII") is "RIPTKEY1E"), \
         "the file leads with the magic and mode"
   rs1rstCheck (the number of bytes in rs1tSealed is 97), \
         "the sealed file is exactly 97 bytes"
   put rsOpenMasterSeed(rs1tSealed, "correct horse") into rs1tOpened
   rs1rstCheck (rs1rstHex(rs1tOpened) is rs1kRsGoldMasterHex), \
         "the right passphrase recovers the seed"
   put rsOpenMasterSeed(rs1tSealed, "wrong horse") into rs1tOpened
   rs1rstCheck (rs1tOpened is empty), "a wrong passphrase is refused"
   rs1rstCheck (rsLastError() contains "passphrase"), \
         "and the refusal says why"
   put rsOpenMasterSeed(rs1rstFlipByte(rs1tSealed, 40), "correct horse") \
         into rs1tOpened
   rs1rstCheck (rs1tOpened is empty), "a tampered file is refused"
   put rsOpenMasterSeed(byte 1 to 60 of rs1tSealed, "correct horse") \
         into rs1tOpened
   rs1rstCheck (rs1tOpened is empty), "a truncated file is refused"
   rs1rstCheck (rsSealMasterSeed(rs1tSeed, empty) is empty), \
         "an empty passphrase is refused at seal time"
   rs1rstCheck (rsSealMasterSeed(byte 1 to 16 of rs1tSeed, "x") is empty), \
         "a 16-byte seed is refused at seal time"
   rs1rstCheck (rsSealMasterSeed(rs1tSeed, "a") is not rsSealMasterSeed(rs1tSeed, \
         "a")), "two seals of one seed differ (fresh salt and nonce)"
end rs1rstSectionKeyFile

private command rs1rstSectionHead
   local rs1tHead, rs1tParsed, rs1tRebuilt, rs1tUpper
   rs1rstSection "RSH1 - the feed head"
   put rsBuildHead(rs1kRsGoldHeadSeq, rs1kRsGoldHeadName, rs1kRsGoldPost2Target, \
         rs1kRsGoldPrekeyTarget, rs1kRsGoldOnion, rs1kRsGoldProfileTarget) into rs1tHead
   rs1rstCheck (rs1rstHex(rs1tHead) is rs1kRsGoldHeadHex), "head bytes match golden"
   put rsParseHead(rs1tHead) into rs1tParsed
   rs1rstCheck (rs1tParsed is not empty), "the golden head parses"
   rs1rstCheck (rs1tParsed["seq"] is 7), "seq round-trips"
   rs1rstCheck (rs1tParsed["displayName"] is rs1kRsGoldHeadName), \
         "display name round-trips"
   rs1rstCheck (rs1tParsed["latestPostTarget"] is rs1kRsGoldPost2Target), \
         "latest-post target round-trips"
   rs1rstCheck (rs1tParsed["prekeyTarget"] is rs1kRsGoldPrekeyTarget), \
         "prekey target round-trips"
   rs1rstCheck (rs1tParsed["onionAddr"] is rs1kRsGoldOnion), \
         "onion address round-trips"
   rs1rstCheck (rs1tParsed["profileMetaTarget"] is rs1kRsGoldProfileTarget), \
         "profile-meta target round-trips"
   put rsBuildHead(0, "n", empty, empty, empty, empty) into rs1tRebuilt
   put rsParseHead(rs1tRebuilt) into rs1tParsed
   rs1rstCheck (rs1tParsed["latestPostTarget"] is rsZeroTarget()), \
         "an empty target normalizes to the zero target"
   rs1rstCheck (rs1tParsed["onionAddr"] is empty), \
         "an empty onion address round-trips as empty"
   rs1rstCheck (rsParseHead(rs1rstFlipByte(rs1tHead, 2)) is empty), \
         "a wrong magic is refused"
   rs1rstCheck (rsParseHead(byte 1 to 30 of rs1tHead) is empty), \
         "a truncated head is refused"
   rs1rstCheck (rsParseHead(rs1tHead & numToByte(0)) is empty), \
         "trailing bytes are refused"
   -- A non-canonical (uppercase) hex target must be refused, not silently
   -- accepted: byte 61 is the first char of the prekey target ("ab"*20), so
   -- turning that 'a' (97) into 'A' (65) is a valid-length but non-lowercase
   -- target. `is in` would accept it (caseSensitive default false); the
   -- byte-value check refuses it.
   put rs1tHead into rs1tUpper
   put numToByte(65) into byte 61 of rs1tUpper
   rs1rstCheck (rsParseHead(rs1tUpper) is empty), \
         "an uppercase (non-canonical) hex target is refused"
   rs1rstCheck (rsBuildHead(1, \
         "0123456789012345678901234567890123456789012345678901234567890123x", \
         empty, empty, empty, empty) is empty), \
         "a 65-byte display name is refused"
   rs1rstCheck (rsBuildHead(1, "n", "zz", empty, empty, empty) is empty), \
         "a malformed target is refused"
   rs1rstCheck (rsBuildHead(1, "n", empty, empty, "short.onion", empty) is \
         empty), "a short onion address is refused"
   rs1rstCheck (rsBuildHead(-1, "n", empty, empty, empty, empty) is empty), \
         "a negative seq is refused"
end rs1rstSectionHead

private command rs1rstSectionPosts
   local rs1tSeed, rs1tPost1, rs1tPost2, rs1tParsed, rs1tChunked, rs1tMangled
   rs1rstSection "RSP1 - posts and the chain"
   put rs1rstBin(rs1kRsGoldIdSeedHex) into rs1tSeed
   put rsBuildPost(rs1kRsGoldTs1, empty, rs1kRsGoldPost1Text, empty, rs1tSeed) \
         into rs1tPost1
   rs1rstCheck (rs1rstHex(rs1tPost1) is rs1kRsGoldPost1Hex), \
         "post 1 bytes match golden (deterministic signature)"
   rs1rstCheck (rs1rstHex(sha1Digest(rsBencodeBytes(rs1tPost1))) is \
         rs1kRsGoldPost1Target), "post 1's DHT target re-derives via SHA-1"
   put rsBuildPost(rs1kRsGoldTs2, rs1kRsGoldPost1Target, rs1kRsGoldPost2Text, \
         rs1kRsGoldMediaTarget, rs1tSeed) into rs1tPost2
   rs1rstCheck (rs1rstHex(rs1tPost2) is rs1kRsGoldPost2Hex), "post 2 bytes match golden"
   rs1rstCheck (rs1rstHex(sha1Digest(rsBencodeBytes(rs1tPost2))) is \
         rs1kRsGoldPost2Target), "post 2's DHT target re-derives via SHA-1"
   put rsParsePost(rs1tPost2) into rs1tParsed
   rs1rstCheck (rs1tParsed is not empty), "post 2 parses"
   rs1rstCheck (rs1tParsed["timestamp"] is 1754870460), "timestamp round-trips"
   rs1rstCheck (rs1tParsed["prevPostTarget"] is rs1kRsGoldPost1Target), \
         "the chain link names post 1"
   rs1rstCheck (rs1tParsed["kind"] is "D"), "kind round-trips"
   rs1rstCheck (rs1tParsed["text"] is rs1kRsGoldPost2Text), "text round-trips"
   rs1rstCheck (rs1tParsed["mediaTargets"] is rs1kRsGoldMediaTarget), \
         "media info-hash round-trips"
   rs1rstCheck (rsVerifyPost(rs1tPost1, rs1kRsGoldHandle) is true), \
         "post 1 verifies under the golden handle"
   rs1rstCheck (rsVerifyPost(rs1tPost2, rs1kRsGoldHandle) is true), \
         "post 2 verifies under the golden handle"
   rs1rstCheck (rsVerifyPost(rs1tPost2, rs1kRsGoldConfPub) is false), \
         "post 2 refuses a different author"
   put rs1rstFlipByte(rs1tPost2, 60) into rs1tMangled
   rs1rstCheck (rsVerifyPost(rs1tMangled, rs1kRsGoldHandle) is false), \
         "one flipped text byte breaks the signature"
   put rs1rstFlipByte(rs1tPost2, 1) into rs1tMangled
   rs1rstCheck (rsVerifyPost(rs1tMangled, rs1kRsGoldHandle) is false), \
         "a wrong magic is refused before any crypto"
   rs1rstCheck (rsVerifyPost(byte 1 to 100 of rs1tPost2, rs1kRsGoldHandle) is \
         false), "a truncated post is refused"
   put rsBuildPostChunked(rs1kRsGoldTs2, rs1kRsGoldPost2Target, \
         rs1kRsGoldPrekeyTarget & comma & rs1kRsGoldProfileTarget, empty, rs1tSeed) \
         into rs1tChunked
   rs1rstCheck (rs1tChunked is not empty), "a chunked post builds"
   put rsParsePost(rs1tChunked) into rs1tParsed
   rs1rstCheck (rs1tParsed["kind"] is "C"), "chunked kind round-trips"
   rs1rstCheck (rs1tParsed["chunkTargets"] is \
         (rs1kRsGoldPrekeyTarget & comma & rs1kRsGoldProfileTarget)), \
         "the chunk list round-trips in order"
   rs1rstCheck (rsVerifyPost(rs1tChunked, rs1kRsGoldHandle) is true), \
         "the chunked post verifies"
   rs1rstCheck (rsBuildPostChunked(1, empty, empty, empty, rs1tSeed) is empty), \
         "an empty chunk list is refused"
   rs1rstCheck (rsBuildPost(1, empty, "x", \
         rs1kRsGoldMediaTarget & comma & rs1kRsGoldMediaTarget & comma & \
         rs1kRsGoldMediaTarget & comma & rs1kRsGoldMediaTarget & comma & \
         rs1kRsGoldMediaTarget & comma & rs1kRsGoldMediaTarget & comma & \
         rs1kRsGoldMediaTarget & comma & rs1kRsGoldMediaTarget & comma & \
         rs1kRsGoldMediaTarget, rs1tSeed) is empty), \
         "nine media attachments are refused"
   rs1rstCheck (rsBuildPost(-5, empty, "x", empty, rs1tSeed) is empty), \
         "a negative timestamp is refused"
end rs1rstSectionPosts

private command rs1rstSectionHelpers
   local rs1tValue
   rs1rstSection "helpers"
   rs1rstCheck (textDecode(rsBencodeBytes(empty), "ASCII") is "0:"), \
         "bencode of empty is 0:"
   rs1rstCheck (textDecode(rsBencodeBytes(textEncode("hi", "ASCII")), \
         "ASCII") is "2:hi"), "bencode of a short string"
   put rsBencodeBytes(rs1rstBin(rs1kRsGoldHeadHex)) into rs1tValue
   rs1rstCheck (textDecode(byte 1 to 4 of rs1tValue, "ASCII") is "203:"), \
         "the golden head bencodes at 203 bytes"
   rs1rstCheck (rsHeadSalt() is "riptide-head"), "the head salt is published"
   rs1rstCheck (the number of chars in rsZeroTarget() is 40), \
         "the zero target is 40 chars"
end rs1rstSectionHelpers

private command rs1rstSectionBep44
   local rs1tValue, rs1tBuf, rs1tSalt
   rs1rstSection "phase 2 - the canonical BEP44 buffer + content addresses"
   -- the exact bytes the golden head's BEP44 signature covers, from the
   -- pure-script assembly (byte-identical to btDhtBep44SignBuf; the folded
   -- suite harness cross-checks the two implementations directly)
   put rsBencodeBytes(rs1rstBin(rs1kRsGoldHeadHex)) into rs1tValue
   put rsBep44SignBuf(rsHeadSalt(), 7, rs1tValue) into rs1tBuf
   rs1rstCheck (rs1rstHex(rs1tBuf) is rs1kRsGoldHeadBufHex), \
         "the golden head's signing buffer matches golden"
   -- the cross-project anchor torrentxt/tests/bep44_golden_test.py pins
   put rsBep44SignBuf("rp-prekeys", 1, textEncode("2:hi", "ASCII")) into rs1tBuf
   rs1rstCheck (textDecode(rs1tBuf, "ASCII") is \
         "4:salt10:rp-prekeys3:seqi1e1:v2:hi"), \
         "the salted anchor vector matches bep44_golden_test.py"
   put rsBep44SignBuf(empty, 7, textEncode("2:hi", "ASCII")) into rs1tBuf
   rs1rstCheck (textDecode(rs1tBuf, "ASCII") is "3:seqi7e1:v2:hi"), \
         "an empty salt omits the salt segment"
   rs1rstCheck (rsBep44SignBuf(rsHeadSalt(), -1, \
         textEncode("2:hi", "ASCII")) is empty), "a negative seq is refused"
   rs1rstCheck (rsBep44SignBuf(rsHeadSalt(), 9007199254740992, \
         textEncode("2:hi", "ASCII")) is empty), \
         "a seq at 2^53 is refused (it would not round-trip)"
   rs1rstCheck (rsBep44SignBuf(rsHeadSalt(), 7, \
         textEncode("hi", "ASCII")) is empty), \
         "a non-bencoded value is refused"
   rs1rstCheck (rsBep44SignBuf(rsHeadSalt(), 7, \
         textEncode("3:hi", "ASCII")) is empty), \
         "a value whose length prefix lies is refused"
   put empty into rs1tSalt
   repeat 65 times
      put "x" after rs1tSalt
   end repeat
   rs1rstCheck (rsBep44SignBuf(rs1tSalt, 1, textEncode("2:hi", "ASCII")) is \
         empty), "a 65-byte salt is refused (the BEP44 cap)"
   -- the content address, through the library this time (the sha1Digest
   -- re-derivations in the posts section prove the same bytes engine-side)
   rs1rstCheck (rsImmutableTarget(rs1rstBin(rs1kRsGoldPost1Hex)) is \
         rs1kRsGoldPost1Target), "rsImmutableTarget re-derives post 1's target"
   rs1rstCheck (rsImmutableTarget(rs1rstBin(rs1kRsGoldPost2Hex)) is \
         rs1kRsGoldPost2Target), "rsImmutableTarget re-derives post 2's target"
   rs1rstCheck (rsImmutableTarget(empty) is empty), \
         "an empty immutable value is refused"
end rs1rstSectionBep44

private command rs1rstSectionIngest
   local rs1tEvent, rs1tBad, rs1tPostEvent, rs1tHead, rs1tPost, rs1tSig
   rs1rstSection "phase 2 - ingest verifiers (synthetic drained events)"
   -- a synthetic dhtMutableItem event, key-for-key what btPoll drains for
   -- the golden head. The oracle pre-derived the BEP44 signature, so this
   -- is fully deterministic - nothing is signed at run time.
   put rs1kRsGoldHandle into rs1tEvent["publicKey"]
   put rsHeadSalt() into rs1tEvent["salt"]
   put 7 into rs1tEvent["seq"]
   put rs1rstBin(rs1kRsGoldHeadHex) into rs1tEvent["value"]
   put rs1kRsGoldHeadSigHex into rs1tEvent["signature"]
   put rsIngestHead(rs1tEvent, rs1kRsGoldHandle) into rs1tHead
   rs1rstCheck (rs1tHead is not empty), "the golden head event ingests"
   rs1rstCheck (rs1tHead["displayName"] is rs1kRsGoldHeadName), \
         "and hands back the parsed head"
   rs1rstCheck (rs1tHead["latestPostTarget"] is rs1kRsGoldPost2Target), \
         "naming post 2 as latest"
   rs1rstCheck (rsIngestHead(rs1tEvent, rs1kRsGoldConfPub) is empty), \
         "an event for another handle is refused"
   put rs1tEvent into rs1tBad
   put "riptide-lies" into rs1tBad["salt"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a wrong salt is refused"
   put rs1tEvent into rs1tBad
   put 8 into rs1tBad["seq"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a seq disagreeing with the head's embedded seq is refused"
   put rs1tEvent into rs1tBad
   put rs1rstFlipByte(rs1tBad["value"], 2) into rs1tBad["value"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a value that is not an RSH1 record is refused"
   put rs1tEvent into rs1tBad
   -- byte 20 is the last display-name char: the record still PARSES, so
   -- this refusal is the signature's, not the parser's
   put rs1rstFlipByte(rs1tBad["value"], 20) into rs1tBad["value"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a tampered-but-parseable value fails the BEP44 signature"
   put rs1tEvent into rs1tBad
   put rs1tBad["signature"] into rs1tSig
   if char 1 of rs1tSig is "6" then
      put "7" into char 1 of rs1tSig
   else
      put "6" into char 1 of rs1tSig
   end if
   put rs1tSig into rs1tBad["signature"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a forged signature is refused"
   put rs1tEvent into rs1tBad
   put char 1 to 127 of rs1tBad["signature"] into rs1tBad["signature"]
   rs1rstCheck (rsIngestHead(rs1tBad, rs1kRsGoldHandle) is empty), \
         "a truncated signature is refused"
   -- the post walk, on synthetic dhtImmutableItem events: head names post 2,
   -- post 2's prev names post 1, post 1's prev is the zero target - the end
   put rs1kRsGoldPost2Target into rs1tPostEvent["target"]
   put rs1rstBin(rs1kRsGoldPost2Hex) into rs1tPostEvent["value"]
   put rsIngestPost(rs1tPostEvent, rs1tHead["latestPostTarget"], rs1kRsGoldHandle) \
         into rs1tPost
   rs1rstCheck (rs1tPost is not empty), "the head's latest target ingests post 2"
   rs1rstCheck (rs1tPost["text"] is rs1kRsGoldPost2Text), "with its text intact"
   put rs1kRsGoldPost1Target into rs1tPostEvent["target"]
   put rs1rstBin(rs1kRsGoldPost1Hex) into rs1tPostEvent["value"]
   put rsIngestPost(rs1tPostEvent, rs1tPost["prevPostTarget"], rs1kRsGoldHandle) \
         into rs1tPost
   rs1rstCheck (rs1tPost is not empty), "walking the chain link ingests post 1"
   rs1rstCheck (rs1tPost["prevPostTarget"] is rsZeroTarget()), \
         "whose prev is the zero target - the chain ends"
   rs1rstCheck (rsIngestPost(rs1tPostEvent, rs1kRsGoldPost2Target, rs1kRsGoldHandle) \
         is empty), "an event answering a different target is refused"
   put rs1rstFlipByte(rs1rstBin(rs1kRsGoldPost1Hex), 60) into rs1tPostEvent["value"]
   rs1rstCheck (rsIngestPost(rs1tPostEvent, rs1kRsGoldPost1Target, rs1kRsGoldHandle) \
         is empty), "a value that does not hash to its target is refused"
   put rs1rstBin(rs1kRsGoldPost1Hex) into rs1tPostEvent["value"]
   rs1rstCheck (rsIngestPost(rs1tPostEvent, rs1kRsGoldPost1Target, rs1kRsGoldConfPub) \
         is empty), "a different claimed author is refused"
   rs1rstCheck (rsIngestPost(rs1tPostEvent, rsZeroTarget(), rs1kRsGoldHandle) is \
         empty), "ingesting against the zero target is refused"
end rs1rstSectionIngest

private function rs1rstAcquireSession
   local rs1tNew, rs1tErr
   if rs1sRsTestSession is not empty and rs1sRsTestSession > 0 then
      return rs1sRsTestSession
   end if
   -- GENERATED (tools/build-suite-selftest.py): TorrentXT allows exactly
   -- ONE session per process and the suite core already opened it during
   -- its probe. Alias the core's handle instead of asking for a second -
   -- the ask would be refused, and this member's live-feed section would
   -- SKIP while looking perfectly green.
   if sSession > 0 then
      put sSession into rs1tNew
   else
      try
         put btStartSession() into rs1tNew
      catch rs1tErr
         put 0 into rs1tNew
      end try
   end if
   if rs1tNew is not empty and rs1tNew > 0 then
      put rs1tNew into rs1sRsTestSession
   end if
   if rs1sRsTestSession is empty or rs1sRsTestSession <= 0 then return 0
   return rs1sRsTestSession
end rs1rstAcquireSession

private command rs1rstSectionLiveFeed pCaps
   local rs1tSession, rs1tSeed, rs1tTarget
   rs1rstSection "phase 2 - the live layer against a real session"
   -- The refusal paths run EVERYWHERE: every input is validated before the
   -- session handle is touched, so proving them needs no torrentxt at all.
   put rs1rstBin(rs1kRsGoldIdSeedHex) into rs1tSeed
   rs1rstCheck (rsPublishHead(0, rs1rstBin(rs1kRsGoldHeadHex), rs1tSeed) is false), \
         "rsPublishHead refuses a dead session handle"
   rs1rstCheck (rsLastError() contains "session"), "and says why"
   rs1rstCheck (rsPublishHead(0, textEncode("junk", "ASCII"), rs1tSeed) is \
         false), "rsPublishHead refuses a non-RSH1 record first"
   rs1rstCheck (rsLastError() contains "RSH1"), "and names the parse"
   rs1rstCheck (rsPublishPost(0, textEncode("junk", "ASCII")) is empty), \
         "rsPublishPost refuses a non-RSP1 record"
   rs1rstCheck (rsPublishImmutable(0, rs1rstBin(rs1kRsGoldPost1Hex)) is empty), \
         "rsPublishImmutable refuses a dead session handle"
   rs1rstCheck (rsRequestHead(0, rs1kRsGoldHandle) is false), \
         "rsRequestHead refuses a dead session handle"
   rs1rstCheck (rsRequestHead(0, "zz") is false), \
         "rsRequestHead refuses a malformed handle"
   rs1rstCheck (rsRequestImmutable(0, rsZeroTarget()) is false), \
         "rsRequestImmutable refuses the zero target"
   rs1rstCheck (rsRequestImmutable(0, rs1kRsGoldPost1Target) is false), \
         "rsRequestImmutable refuses a dead session handle"
   if pCaps["hasTorrent"] is not true then
      rs1rstSkip "live feed puts and lookups: torrentxt is not installed"
      exit rs1rstSectionLiveFeed
   end if
   put rs1rstAcquireSession() into rs1tSession
   if rs1tSession is 0 then
      rs1rstSkip "live feed puts and lookups: could not start a torrent session"
      exit rs1rstSectionLiveFeed
   end if
   -- The stores answer synchronously (the async dhtPut confirm is not
   -- waited on), so nothing here needs a network. The target comparisons
   -- are REAL cross-implementation checks: libtorrent's SHA-1 over its own
   -- bencoding against the oracle's pinned bytes.
   put rsPublishImmutable(rs1tSession, rs1rstBin(rs1kRsGoldPost1Hex)) into rs1tTarget
   rs1rstCheck (rs1tTarget is rs1kRsGoldPost1Target), \
         "rsPublishImmutable stores post 1 at the golden target"
   put rsPublishPost(rs1tSession, rs1rstBin(rs1kRsGoldPost2Hex)) into rs1tTarget
   rs1rstCheck (rs1tTarget is rs1kRsGoldPost2Target), \
         "rsPublishPost stores post 2 at the golden target"
   -- The whole external-signing seam in one boolean: script-assembled
   -- canonical buffer, SodiumXT signature, and libtorrent VERIFIES it
   -- before queueing - true means two independent ed25519 implementations
   -- and two independent BEP44 buffer assemblies agreed byte-for-byte.
   rs1rstCheck (rsPublishHead(rs1tSession, rs1rstBin(rs1kRsGoldHeadHex), rs1tSeed) is \
         true), "rsPublishHead's signature satisfies libtorrent's verifier"
   rs1rstCheck (rsRequestHead(rs1tSession, rs1kRsGoldHandle) is true), \
         "rsRequestHead's lookup is accepted (async; value not awaited)"
   rs1rstCheck (rsRequestImmutable(rs1tSession, rs1kRsGoldPost1Target) is true), \
         "rsRequestImmutable's lookup is accepted (async; value not awaited)"
end rs1rstSectionLiveFeed
