script "coinSelfTest"

-- coin-selftest.livecodescript - a self-building RUNTIME harness that drives
-- the CoinXT public API in OXT and reports PASS / FAIL per handler. This is the
-- OXT-pass companion to tools/coin-kat.py: the KAT harness proves the SHIM
-- against public vectors headless, through ctypes; this proves the .lcb BINDING
-- (the foreign-decl signatures, the UIntSize returns, the Data marshalling, the
-- allocate-and-copy-back path) actually runs - the one layer CI cannot reach,
-- since OXT has no headless way to compile or run a .lcb.
--
-- WHY THIS FILE EXISTS. CoinXT was the only member with no self-building
-- harness. That is exactly why the 2026-08-08 suite pass could reach just 4 of
-- the 16 public cx* handlers: there was no paste-and-run way to drive the rest.
-- This file closes that. It calls ALL 16, by name, and checks every deterministic
-- output against the same published vector tools/coin-kat.py pins, so a green run
-- here and a green run there are the same claim at two different layers.
--
-- COVERAGE NOTE (honest): every public cx* handler is driven here, across all
-- three built phases. Phase 1 (the .lcb): cxCheckABI, the seven hash *Len
-- accessors, cxKeccak256, cxSha3_256, cxSha256, cxSha512, cxRipemd160,
-- cxHmacSha256, cxHmacSha512, cxPbkdf2HmacSha512. Phase 2 (the .lcb):
-- cxNewSeckey, cxSeckeyIsValid, cxPublicKey, cxPubkeyDecompress, cxSign,
-- cxVerify, cxSignRecoverable, cxRecover, cxEcdh and their six length
-- accessors. Phase 3 (src/coinxt.livecodescript): the hex, Base58Check,
-- bech32/bech32m and RLP encoders, cxHash160/cxHash256, and the four address
-- builders. The vectors are Keccak-256 (Ethereum 0x01 padding), FIPS 180-4
-- SHA-2, the RIPEMD-160 specification vectors, NIST SHA3-256, RFC 4231 HMAC
-- cases 1 and 2, the BIP-39 abandon-about/TREZOR seed, the secp256k1 generator
-- G, the published RFC 6979 signature of sha256("Satoshi Nakamoto") under the
-- private key 1, and for phase 3 the BIP-173/BIP-350 addresses, the EIP-55
-- examples and the RLP yellow-paper examples.
--
-- TWO DIFFERENT LOADS ARE BEING TESTED HERE, and it is worth knowing which is
-- which when something fails. Phases 1 and 2 are the .lcb extension. Phase 3 is
-- a SCRIPT that must be in the message path (`start using stack "coinxt"`), the
-- way OnionXT ships its ox* surface. If every phase-3 section fails with
-- "handler not found" while the earlier ones pass, the extension loaded and the
-- script did not - that is a setup problem, not a defect.
--
-- THIS FILE HAS NOT ITSELF BEEN RUN ON AN ENGINE YET, so it is verified
-- statically. Running it is what turns the 12 phase-1 handlers the 2026-08-08
-- suite pass could not reach, all 15 phase-2 handlers, and the whole phase-3
-- surface into runtime results. Phase 3's LOGIC has been executed headlessly by
-- tools/check-script-vectors.py against these same vectors; what is still
-- unobserved for it is engine PARSER behaviour, which only a real engine
-- settles.
--
-- WHAT IT DELIBERATELY DOES NOT PROVE: anything about HD wallets or mnemonics.
-- Those are phase 4 and do not exist yet. Nor Taproot key tweaking: cxBtcAddressP2TR
-- encodes an output key it is GIVEN and does not derive one (see its comment).
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK script
-- (Object > Stack Script), then close+reopen. It builds its own UI, runs every
-- check synchronously, and shows a green/red list. Needs the installed
-- org.openxtalk.library.coin extension. Nothing here is asynchronous and nothing
-- holds state, so there is no teardown and no deadline: CoinXT is a calculator.
--
-- The LCS lessons this file was written under (the gotcha list carried in the
-- family CLAUDE.md files): no braces, no subscripted function results, binary
-- payloads built with numToByte (string literals have no escapes), byte-exact
-- compares under caseSensitive, and zero-argument calls BARE in statement
-- position - which is why cxCheckABI is invoked as a command and not as
-- cxCheckABI(). It is declared `returns nothing`, so `put cxCheckABI()` would
-- print a blank line and prove nothing; it THROWS on ABI skew, so silence is the
-- pass.

-- ---- the pinned vectors ------------------------------------------------------
-- Every one of these is a PUBLIC known answer, identical to the value pinned in
-- tools/coin-kat.py. Do not "fix" one to match an implementation: if a digest
-- here disagrees with the library, the library is what is wrong.

-- Keccak-256, Ethereum's 0x01-padded variant. NOT SHA3-256 (see kSha3Abc).
constant kKeccakEmpty = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
constant kKeccakAbc = "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"

-- NIST SHA3-256. The empty and "abc" answers differ from Keccak-256 above by
-- the padding byte alone, which is the entire reason both handlers exist.
constant kSha3Empty = "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
constant kSha3Abc = "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
constant kSha3Fox = "69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04"

-- FIPS 180-4 worked examples.
constant kSha256Empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
constant kSha256Abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
constant kSha512Empty = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
constant kSha512Abc = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"

-- The RIPEMD-160 specification's own vectors. These stand alone: OpenSSL 3
-- moved RIPEMD-160 to the legacy provider, so Python's hashlib usually cannot
-- offer a second opinion, and coin-kat.py says so rather than skipping quietly.
constant kRipeEmpty = "9c1185a5c5e9fc54612808977ee8f548b2258d31"
constant kRipeA = "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"
constant kRipeAbc = "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
constant kRipeMsgDigest = "5d0689ef49d2fae572b881b123a85ffa21595f36"

-- RFC 4231 test case 1: key = 0x0b repeated 20 times, message = "Hi There".
constant kHmac1Sha256 = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
constant kHmac1Sha512 = "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"

-- RFC 4231 test case 2: a SHORT ascii key, which exercises the pad path that a
-- 20-byte key does not.
constant kHmac2Sha256 = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
constant kHmac2Sha512 = "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"

-- The BIP-39 vector everyone knows. This pins the REAL call shape CoinXT will
-- use the KDF for in phase 4 (salt = "mnemonic" + passphrase, 2048 iterations,
-- a 64-byte seed), not merely the primitive in the abstract.
constant kBip39Mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
constant kBip39Salt = "mnemonicTREZOR"
constant kBip39Seed = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

constant kFox = "The quick brown fox jumps over the lazy dog"

-- ---- secp256k1 (phase 2) -----------------------------------------------------
-- The private key 1 is the curve's generator G, so its public key needs no
-- vector table: it IS the published definition of secp256k1. That is why the
-- curve sections below use it rather than a random-looking test key.
constant kPubOneCompressed = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
constant kPubOneUncompressed = "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
-- 2G, for the same reason: it is the curve's own second point, so the two tweak
-- entry points can be pinned to a published answer rather than only to each
-- other. 1 + 1 = 2 is the smallest case of the homomorphism BIP-32 rests on.
constant kPubTwoCompressed = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

-- The RFC 6979 deterministic signature of sha256("Satoshi Nakamoto") under that
-- same key: the most-republished vector for secp256k1 + SHA-256, and identical
-- to the one pinned in tools/coin-kat.py. Low-s, as both Bitcoin relay policy
-- and Ethereum consensus require.
constant kSigSatoshi = "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d82442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"

-- ---- phase 3: encodings and addresses ----------------------------------------
-- Every one of these is a PUBLISHED vector, identical to the values
-- tools/coin_reference.py pins and tools/check-script-vectors.py runs the real
-- script against. Two of them are worth pointing at, because they make this
-- harness stronger than it looks: hash160 of the compressed generator G is
-- 751e76e8...33bd6, which is EXACTLY the witness program in BIP-173's own
-- example address, and the x-only G is the program in BIP-350's. So deriving an
-- address from the private key 1 lands on a published answer at both witness
-- versions - no CoinXT-invented expectations anywhere in this section.
-- SHA-256(SHA-256("abc")). hash256 is the function Base58Check's four-byte tail
-- IS, so pinning it directly turns "the address round-trips" into "the address
-- round-trips AND the checksum is the one Bitcoin specifies", which a
-- self-consistent encoder/decoder pair cannot tell you on its own.
constant kHash256Abc = "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358"
constant kBase58Payload = "00010966776006953D5567439E5E39F86A0D273BEE"
constant kBase58Address = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM"
constant kBase58Corrupt = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvN"
constant kP2wpkhOfG = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
constant kP2trOfG = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"
constant kP2pkhOfG = "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH"
constant kEthOfG = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"
constant kEip55A = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
constant kEip55B = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
constant kBech32Valid = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
constant kSegwitTestnet = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"
constant kSegwitTestnetProgram = "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262"
-- BIP-350's invalid list: a version 0 address carrying a bech32m checksum. This
-- is the single most important rejection in the whole encoding surface.
constant kSegwitV0WithBech32m = "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5"

-- ---- WIF (wallet import format) ----------------------------------------------
-- The Bitcoin wiki's worked-example private key, the same page the Base58Check
-- worked example above comes from. It is a published, burned test key, safe to
-- commit (the KAT rule: public test-vector keys only). The mainnet/uncompressed
-- string is the wiki's own; the compressed and testnet forms are derived by
-- tools/coin_reference.py, whose import self-check anchors the derivation to
-- the published string - all three are re-derived by check-selftest-vectors.py.
constant kWifSeckey = "0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d"
constant kWifUncompressed = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
constant kWifCompressed = "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"
constant kWifTestnet = "cMzLdeGd5vEqxB8B6VFQoRopQ3sLAAvEzDAoQgvX54xwofSWj1fx"
-- kWifUncompressed with its final character changed, so the checksum must
-- refuse it (checked genuinely corrupt by the gate, the kBase58Corrupt rule).
constant kWifBadChecksum = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTk"

-- ---- the fail-closed regression set ------------------------------------------
-- One constant per defect an adversarial review found in the shipped script
-- layer. Every one of them FAILED OPEN - a wrong answer that looked like a right
-- one - and every one of them slipped past a vector set that only ever fed the
-- handlers well-formed input. That is the lesson worth carrying: a positive
-- vector cannot catch a check that is not being made.

-- kEip55A with one letter's case corrupted, and with every letter's case
-- flipped. cxEthAddressIsChecksummed used to answer true to both, because it
-- compared a value against itself.
constant kEip55Corrupt = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"
constant kEip55Flipped = "0x5AaEB6053f3e94c9B9a09F33669435e7eF1bEaEd"
-- A REAL bech32m v1 address whose 32-byte witness program begins with the bytes
-- 45 52 52 4F 52. The decoder used to signal its own failure with the string
-- "ERROR" in place of the bytes, so it rejected this address as malformed - an
-- address this very file's encoder produces.
constant kSegwitErrorProgram = "4552524f52000102030405060708090a0b0c0d0e0f101112131415161718191a"
constant kSegwitErrorAddress = "bc1pg4f9yn6jqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydqqwyhrw"

-- ---- HD wallets and mnemonics (phase 4) --------------------------------------
-- Every value below is PUBLISHED. That matters more here than anywhere else in
-- this file, because phase 4 is the only surface that can be wrong WITHOUT
-- FAILING: a mis-packed mnemonic is still twelve English words and a
-- mis-derived path is still a valid address. Nothing tells the user until the
-- funds are somewhere they cannot reach.

-- The all-zero entropy vector, and the 24-word all-ones one, from BIP-39's own
-- english test set. kBip39Mnemonic above is the 12-word one.
constant kBip39Entropy12 = "00000000000000000000000000000000"
constant kBip39Entropy24 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
constant kBip39Mnemonic24 = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
-- The same 12 words with NO passphrase. kBip39Seed above is the same mnemonic
-- with "TREZOR", so the pair also proves the passphrase reaches the KDF.
constant kBip39SeedNoPass = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
-- The same mnemonic with one word replaced, so the checksum must reject it.
constant kBip39Mnemonic12Bad = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"

-- BIP-32 test vector 1: seed 000102...0f, and three levels of its published
-- chain. The last one is five levels deep and mixes hardened with normal.
constant kBip32Seed1 = "000102030405060708090a0b0c0d0e0f"
constant kBip32V1Xprv = "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
constant kBip32V1Xpub = "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
constant kBip32V1H0Xprv = "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7"
constant kBip32V1H0Xpub = "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
constant kBip32V1DeepPath = "m/0'/1/2'/2/1000000000"
constant kBip32V1DeepXprv = "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76"
-- BIP-32 test vector 3 exists SOLELY because its master private key has a
-- leading zero byte, the case a "strip leading zeros" bignum bug gets wrong.
constant kBip32Seed3 = "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
constant kBip32V3Xprv = "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6"

-- The end-to-end claim: the test mnemonic every wallet ships with, walked down
-- BIP-44 and BIP-84 paths to the addresses those wallets show.
constant kAbandonXprv = "xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu"
constant kAbandonBip44 = "m/44'/0'/0'/0/0"
constant kAbandonP2pkh = "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
constant kAbandonBip84 = "m/84'/0'/0'/0/0"
constant kAbandonP2wpkh = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
constant kAbandonBip84Account = "m/84'/0'/0'"
constant kAbandonBip84Xpub = "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V"
constant kAbandonEthPath = "m/44'/60'/0'/0/0"
constant kAbandonEth = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"

-- Phase 5. Transaction building and signing. The Bitcoin case IS the BIP-143
-- native-P2WPKH worked example: a two-input transaction that exercises BOTH a
-- legacy SIGHASH_ALL preimage (input 0, a P2PK spend) and a BIP-143 segwit
-- preimage (input 1, P2WPKH), reproduced byte-for-byte including its witness.
-- The Ethereum cases are the EIP-155 specification's own example and a
-- self-consistent EIP-1559 typed transaction. All the "expected" constants are
-- re-derived from tools/coin_reference.py by check-selftest-vectors.py; the
-- inputs are the published fixtures.
constant kTxSeckey0 = "bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"
constant kTxSeckey1 = "619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"
constant kTxPubkey1 = "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant kTxid0 = "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"
constant kTxid1 = "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"
constant kTxScriptCode0 = "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac"
constant kTxScriptCode1 = "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac"
constant kTxOutScript0 = "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant kTxOutScript1 = "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant kTxOutpoint0 = "fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000"
constant kTxOutpoint1 = "ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a01000000"
constant kTxOut0 = "202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant kTxOut1 = "9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant kTxLegacySighash = "63cec688ee06a91e913875356dd4dea2f8e0f2a2659885372da2a37e32c7532e"
constant kTxSegwitSighash = "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670"
constant kTxScriptSig0 = "4830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01"
constant kTxWitness1 = "0247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant kTxSignedRaw = "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000"
constant kTxTxid = "e8151a2af31c368a35053ddd4bdb285a8595c769a3ad83e0fa02314a602d4609"
constant kEthSeckey = "4646464646464646464646464646464646464646464646464646464646464646"
constant kEthTo = "3535353535353535353535353535353535353535"
constant kEthGasPrice = "04a817c800"
constant kEthValue = "0de0b6b3a7640000"
constant kEthLegacySighash = "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53"
constant kEthLegacyRaw = "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
constant kEthLegacyTxhash = "33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
constant kEth1559MaxPrio = "3b9aca00"
constant kEth1559MaxFee = "04a817c800"
constant kEth1559Value = "016345785d8a0000"
constant kEth1559Sighash = "bf4c3dfa4164868c98534322ecbbce3c022d6d0dee3580b1504da0a28fff9199"
constant kEth1559Raw = "02f8730180843b9aca008504a817c80082520894353535353535353535353535353535353535353588016345785d8a000080c001a0180a63d9ea767ab51941f4cb5d3f4f1113ae08861b4a660eb72770967ddc8987a04a41c8877f4e53a06c3a7d6f2787f113d9700bd112168f6714ff3b8957f1b123"
constant kEth1559Txhash = "1d723f02967119095427907564da7762bd6d3a5d8edb1291db53b97191749e7f"

-- ---- BIP-340 Schnorr and BIP-341 Taproot (ABI 6) -----------------------------
-- Every value here is PUBLISHED, and both specifications publish the negatives
-- as well as the positives - which is the whole reason a Schnorr vector file
-- exists. An implementation that only ever meets good signatures passes every
-- positive case while happily accepting a forged one.
--   BIP-340: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
--   BIP-341: https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json
-- The full 19-case BIP-340 set and the full 14-case BIP-341 set run headlessly
-- in tools/coin-kat.py; this file carries the subset that a human pasting one
-- stack into OXT should see, chosen so every new handler is called by name and
-- both a positive and a negative reach each one.

-- BIP-340 test vector 1 (a nonzero key, message and aux, so no field is
-- accidentally right because it was zero).
constant kSchnorrSk1 = "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef"
constant kSchnorrPub1 = "dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659"
constant kSchnorrAux1 = "0000000000000000000000000000000000000000000000000000000000000001"
constant kSchnorrMsg1 = "243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89"
constant kSchnorrSig1 = "6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de33418906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a"
-- BIP-340 vector 5's public key: 32 bytes that are NOT the X coordinate of any
-- point on the curve. Its expected verification result is FALSE, not an error,
-- and that distinction is the reason this constant is here.
constant kSchnorrPubOffCurve = "eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34"
-- BIP-340 vector 6's signature: well formed, over the right message and key,
-- and invalid because has_even_y(R) is false. A verifier that skipped that one
-- rule would accept it.
constant kSchnorrSigOddR = "fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a14602975563cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2"

-- BIP-341 scriptPubKey vector 0 and keyPathSpending input 0: the KEY-PATH-ONLY
-- case, where the merkle root is the specification's EMPTY BYTE STRING. This is
-- the shape a single-signature wallet actually uses, and the one that separates
-- a correct implementation from one that hashes 32 zero bytes instead.
constant kTapSeckey0 = "6b973d88838f27366ed61c9ad6367663045cb456e28335c109e30717ae0c6baa"
constant kTapInternal0 = "d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d"
constant kTapOutput0 = "53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343"
constant kTapTweaked0 = "2405b971772ad26915c8dcdf10f238753a9b837e5f8e6a86fd7c0cce5b7296d9"
constant kTapAddress0 = "bc1p2wsldez5mud2yam29q22wgfh9439spgduvct83k3pm50fcxa5dps59h4z5"
-- BIP-341 scriptPubKey vector 1: the same operation WITH a script-tree root, so
-- the two branches of the tagged hash (32 bytes of input versus 64) are both
-- exercised by a published answer.
constant kTapInternal1 = "187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27"
constant kTapRoot1 = "5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21"
constant kTapOutput1 = "147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3"
constant kTapAddress1 = "bc1pz37fc4cn9ah8anwm4xqqhvxygjf9rjf2resrw8h8w4tmvcs0863sa2e586"

constant kStTitle = "coinxt - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------

-- ---- the scaffolding (carried) ----------------------------------------------
-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: tools/harness-scaffold.livecodescript; gate: tools/check-harness-scaffold-drift.py) ====
-- The harness scaffolding as one carried block: counters, the window, the
-- assertion plumbing, the report surface. The adopting harness declares
-- kStTitle/kStWidth/kStHeight above this block, owns openStack/stRun/
-- stCleanup, calls stResetCounters first in stRun and stReportDone when
-- the run completes. Do not edit this block in place: change the master
-- and re-carry it.
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sStRunDone           -- "true" once the run finished (drives the color)

-- The platform's own terminal face (the demo kit's uiMonoFont, by value).
function stMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end stMonoFont

-- ---- the window (idempotent; the fold drops this half) -----------------------
command stBuild
   -- the guard is on a control this VERSION of the scaffold adds, so a stack
   -- built by an older scaffold rebuilds once and picks up the new layout
   -- (the builders re-rect existing controls by name; nothing needs deleting)
   if there is a button "stCopy" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to kStWidth
   set the height of this stack to kStHeight
   set the backgroundColor of this card to "240,242,246"
   set the title of this stack to kStTitle
   stMakeLabel "stTitle", "  " & kStTitle, "0,0," & kStWidth & ",30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38," & (kStWidth - 200) & ",66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", (kStWidth - 184) & ",38," & (kStWidth - 100) & ",64"
   stMakeButton "stRerun", "Re-run", (kStWidth - 94) & ",38," & (kStWidth - 16) & ",64"
   stMakeList "stResults", "16,72," & (kStWidth - 16) & "," & (kStHeight - 16)
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
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to "225,229,236"
   set the opaque of field pName to true
   set the backgroundColor of field pName to "255,255,255"
   set the textSize of field pName to 11
   set the textFont of field pName to stMonoFont()
end stMakeList

-- ---- assertion plumbing (this half folds into the suite harness) -------------
command stResetCounters
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put empty into sStRunDone
end stResetCounters

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

-- A SKIP is a first-class outcome, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this piece is
-- not here", and something that blew up very much is.
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
   if sStRunDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "23,128,63"
      else
         set the foregroundColor of field "stSummary" to "176,58,46"
      end if
   end if
end stShow

-- paint the results list: red FAIL, green PASS, amber SKIP, muted the rest
command stPaint
   local tN, tI, tLine, tErr
   put the number of lines of field "stResults" into tN
   lock screen
   try
      repeat with tI = 1 to tN
         put line tI of field "stResults" into tLine
         if tLine begins with "FAIL" then
            set the foregroundColor of line tI of field "stResults" to "176,58,46"
         else if tLine begins with "PASS" then
            set the foregroundColor of line tI of field "stResults" to "23,128,63"
         else if tLine begins with "SKIP" then
            set the foregroundColor of line tI of field "stResults" to "150,110,40"
         else
            set the foregroundColor of line tI of field "stResults" to "138,146,158"
         end if
      end repeat
   catch tErr
   end try
   set the vScroll of field "stResults" to 0
   unlock screen
end stPaint

-- The run's one epilogue: mark done, render, paint. Synchronous harnesses
-- call this at the end of stRun; async ones from the tick that ends the run.
command stReportDone
   put "true" into sStRunDone
   stShow
   stPaint
end stReportDone

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back
   -- verbatim into the OXT-pass record, so nobody has to retype a result.
   local tError
   try
      set the clipboardData["text"] to sResultText
      answer "Results copied to the clipboard."
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

on closeStack
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
-- ==== SUITE HARNESS SCAFFOLD v1 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack











-- Nothing to release: coinxt is stateless (no sessions, no sockets, no
-- handles). The scaffold's Re-run button and closeStack call this all the
-- same, so it exists and says why it is empty.
command stCleanup
end stCleanup

-- ---- the run -----------------------------------------------------------------
command stRun
   stResetCounters
   -- Byte-exact compares, and hex strings that must not fold case.
   set the caseSensitive to true

   put "CoinXT API self-test" & return into sResultText
   put "Phases 1-5: the .lcb module and the script layer, end to end." & return after sResultText

   stRunAbi
   stRunLengths
   stRunKeccak
   stRunSha3
   stRunSha2
   stRunRipemd
   stRunHmac
   stRunPbkdf2
   stRunEmptyInputs
   stRunIndependence
   stRunFailClosed
   stRunCurveKeys
   stRunCurveSign
   stRunCurveVerify
   stRunCurveRecover
   stRunCurveEcdh
   stRunCurveFailClosed
   stRunHex
   stRunBase58
   stRunBech32
   stRunAddresses
   stRunEip55
   stRunRlp
   stRunWif
   stRunBip39
   stRunBip32
   stRunBip44
   stRunTransactions
   stRunSchnorr
   stRunTaproot
   stRunFailOpen

   stSection "summary"
   stNote "Vectors are identical to tools/coin-kat.py, so this run and the"
   stNote "headless KAT run are the same claim at two different layers."
   stNote "Phase 4 is the section to read first if anything failed: it is the"
   stNote "only surface where a wrong answer still looks like a right one."
   stReportDone
end stRun

-- The ABI guard, called BY NAME at last. cxCheckABI is `returns nothing` and
-- throws on skew, so silence is the pass; there is no value to inspect.
command stRunAbi
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tOK
   stSection "load + ABI guard"
   try
      put "true" into tOK
      cxCheckABI
   catch tError
      put "false" into tOK
      stNote "cxCheckABI threw: " & tError
   end try
   stAssert "cxCheckABI passes against the shipped binary", tOK is "true"
   -- The probe that actually prints a value, and the first exercise of the
   -- UIntSize return type in this file.
   stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
end stRunAbi

-- The seven length accessors. These are the whole UIntSize-as-a-foreign-RETURN
-- surface: our lengths are C size_t, so they marshal as UIntSize, not CUInt.
-- Each is checked twice over - against its known digest size, and against the
-- length of a digest the library actually produced - because a length that is
-- self-consistently wrong would still size every buffer wrong.
command stRunLengths
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "length accessors (UIntSize as a foreign RETURN type)"
   try
      stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
      stAssert "cxSha3_256Len() is 32", cxSha3_256Len() is 32
      stAssert "cxSha256Len() is 32", cxSha256Len() is 32
      stAssert "cxSha512Len() is 64", cxSha512Len() is 64
      stAssert "cxRipemd160Len() is 20", cxRipemd160Len() is 20
      stAssert "cxHmacSha256Len() is 32", cxHmacSha256Len() is 32
      stAssert "cxHmacSha512Len() is 64", cxHmacSha512Len() is 64
      stAssert "cxSeckeyLen() is 32", cxSeckeyLen() is 32
      stAssert "cxPubkeyLenCompressed() is 33", cxPubkeyLenCompressed() is 33
      stAssert "cxPubkeyLenUncompressed() is 65", cxPubkeyLenUncompressed() is 65
      stAssert "cxSignatureLen() is 64", cxSignatureLen() is 64
      stAssert "cxRecoverableSignatureLen() is 65", cxRecoverableSignatureLen() is 65
      stAssert "cxEcdhLen() is 65", cxEcdhLen() is 65
      stAssert "a recoverable signature is one byte longer than a plain one", cxRecoverableSignatureLen() is cxSignatureLen() + 1
      stAssert "keccak digest length matches its accessor", the number of bytes of cxKeccak256(stText("abc")) is cxKeccak256Len()
      stAssert "sha512 digest length matches its accessor", the number of bytes of cxSha512(stText("abc")) is cxSha512Len()
      stAssert "ripemd digest length matches its accessor", the number of bytes of cxRipemd160(stText("abc")) is cxRipemd160Len()
   catch tError
      stSectionFailed "length accessors", tError
   end try
end stRunLengths

command stRunKeccak
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "Keccak-256 (published Ethereum vectors)"
   try
      -- The empty input FIRST, on purpose. It is the MCDataGetBytePtr-on-empty
      -- marshalling question: if the engine imported a null byte pointer as
      -- `nothing`, the plain Pointer slot would reject it and this would THROW
      -- rather than return a digest. A throw here is a marshalling failure, not
      -- a hashing failure - do not go looking in the vectors.
      stAssert "cxKeccak256 of the empty input", stHex(cxKeccak256(stText(""))) is kKeccakEmpty
      stAssert "cxKeccak256 of abc", stHex(cxKeccak256(stText("abc"))) is kKeccakAbc
      stAssert "cxKeccak256 is deterministic", stHex(cxKeccak256(stText("abc"))) is stHex(cxKeccak256(stText("abc")))
   catch tError
      stSectionFailed "Keccak-256", tError
   end try
end stRunKeccak

command stRunSha3
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "SHA3-256 (NIST) and the aliasing trap"
   try
      stAssert "cxSha3_256 of the empty input", stHex(cxSha3_256(stText(""))) is kSha3Empty
      stAssert "cxSha3_256 of abc", stHex(cxSha3_256(stText("abc"))) is kSha3Abc
      stAssert "cxSha3_256 of the fox sentence", stHex(cxSha3_256(stText(kFox))) is kSha3Fox
      -- The trap this pair of handlers exists to avoid. Keccak-256 and SHA3-256
      -- differ ONLY in a padding byte, so a shim that wires one to the other is
      -- a silent, plausible, totally wrong answer - and on Ethereum, a wrong
      -- address. Assert the difference explicitly, in both directions.
      stAssert "cxSha3_256 is NOT aliased to cxKeccak256", stHex(cxSha3_256(stText("abc"))) is not stHex(cxKeccak256(stText("abc")))
      stAssert "cxKeccak256 is NOT aliased to cxSha3_256", stHex(cxKeccak256(stText(""))) is not stHex(cxSha3_256(stText("")))
   catch tError
      stSectionFailed "SHA3-256", tError
   end try
end stRunSha3

command stRunSha2
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "SHA-256 and SHA-512 (FIPS 180-4)"
   try
      stAssert "cxSha256 of the empty input", stHex(cxSha256(stText(""))) is kSha256Empty
      stAssert "cxSha256 of abc", stHex(cxSha256(stText("abc"))) is kSha256Abc
      stAssert "cxSha512 of the empty input", stHex(cxSha512(stText(""))) is kSha512Empty
      stAssert "cxSha512 of abc", stHex(cxSha512(stText("abc"))) is kSha512Abc
   catch tError
      stSectionFailed "SHA-2", tError
   end try
end stRunSha2

command stRunRipemd
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "RIPEMD-160 (specification vectors)"
   try
      stAssert "cxRipemd160 of the empty input", stHex(cxRipemd160(stText(""))) is kRipeEmpty
      stAssert "cxRipemd160 of a", stHex(cxRipemd160(stText("a"))) is kRipeA
      stAssert "cxRipemd160 of abc", stHex(cxRipemd160(stText("abc"))) is kRipeAbc
      stAssert "cxRipemd160 of message digest", stHex(cxRipemd160(stText("message digest"))) is kRipeMsgDigest
      stNote "No second opinion exists for these: OpenSSL 3 moved RIPEMD-160 to"
      stNote "the legacy provider, so the published vectors stand alone."
   catch tError
      stSectionFailed "RIPEMD-160", tError
   end try
end stRunRipemd

command stRunHmac
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tKey1, tKey2, tMsg1, tMsg2
   stSection "HMAC-SHA256 / HMAC-SHA512 (RFC 4231 cases 1 and 2)"
   try
      -- Case 1's key is twenty 0x0b bytes. Built with numToByte because a
      -- LiveCodeScript string literal has no escape syntax: "\x0b" is four
      -- characters, not one byte.
      put stRepeatByte(11, 20) into tKey1
      put stText("Hi There") into tMsg1
      stAssert "HMAC-SHA256 case 1", stHex(cxHmacSha256(tKey1, tMsg1)) is kHmac1Sha256
      stAssert "HMAC-SHA512 case 1", stHex(cxHmacSha512(tKey1, tMsg1)) is kHmac1Sha512
      -- Case 2's key is shorter than the block size and ascii, which walks a
      -- different pad path than case 1's.
      put stText("Jefe") into tKey2
      put stText("what do ya want for nothing?") into tMsg2
      stAssert "HMAC-SHA256 case 2", stHex(cxHmacSha256(tKey2, tMsg2)) is kHmac2Sha256
      stAssert "HMAC-SHA512 case 2", stHex(cxHmacSha512(tKey2, tMsg2)) is kHmac2Sha512
      -- A MAC must depend on its key. Same message, different key, different tag.
      stAssert "HMAC-SHA256 depends on the key", stHex(cxHmacSha256(tKey1, tMsg1)) is not stHex(cxHmacSha256(tKey2, tMsg1))
   catch tError
      stSectionFailed "HMAC", tError
   end try
end stRunHmac

command stRunPbkdf2
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSeed, tShort
   stSection "PBKDF2-HMAC-SHA512 (the BIP-39 seed vector)"
   try
      put cxPbkdf2HmacSha512(stText(kBip39Mnemonic), stText(kBip39Salt), 2048, 64) into tSeed
      stAssert "BIP-39 abandon-about with TREZOR", stHex(tSeed) is kBip39Seed
      stAssert "the seed is exactly 64 bytes", the number of bytes of tSeed is 64
      -- This is the one handler whose output length the CALLER chooses, so the
      -- shim writes exactly what was asked for rather than a size it reports.
      -- A non-block-multiple length exercises the partial final block.
      put cxPbkdf2HmacSha512(stText(kBip39Mnemonic), stText(kBip39Salt), 2048, 20) into tShort
      stAssert "a 20-byte request returns 20 bytes", the number of bytes of tShort is 20
      stAssert "the short output prefixes the long one", stHex(tShort) is char 1 to 40 of kBip39Seed
   catch tError
      stSectionFailed "PBKDF2", tError
   end try
end stRunPbkdf2

-- The empty input, generalised. The suite pass settled this for cxKeccak256
-- only; every one-shot digest marshals its IN buffer the same way, so each one
-- should return a full-length digest rather than throw.
command stRunEmptyInputs
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "empty input marshals for every one-shot digest"
   try
      stAssert "cxKeccak256 empty returns 32 bytes", the number of bytes of cxKeccak256(stText("")) is 32
      stAssert "cxSha3_256 empty returns 32 bytes", the number of bytes of cxSha3_256(stText("")) is 32
      stAssert "cxSha256 empty returns 32 bytes", the number of bytes of cxSha256(stText("")) is 32
      stAssert "cxSha512 empty returns 64 bytes", the number of bytes of cxSha512(stText("")) is 64
      stAssert "cxRipemd160 empty returns 20 bytes", the number of bytes of cxRipemd160(stText("")) is 20
      -- An empty KEY and an empty MESSAGE are separate marshalling slots.
      stAssert "cxHmacSha256 with an empty key", the number of bytes of cxHmacSha256(stText(""), stText("abc")) is 32
      stAssert "cxHmacSha256 with an empty message", the number of bytes of cxHmacSha256(stText("abc"), stText("")) is 32
   catch tError
      stSectionFailed "empty inputs", tError
   end try
end stRunEmptyInputs

-- Four digests of the same input must be four DIFFERENT answers. If any two
-- agree, a wire has been crossed somewhere in the binding.
command stRunIndependence
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tK, tS3, tS2, tR
   stSection "the digests are independent of each other"
   try
      put stHex(cxKeccak256(stText("abc"))) into tK
      put stHex(cxSha3_256(stText("abc"))) into tS3
      put stHex(cxSha256(stText("abc"))) into tS2
      put stHex(cxRipemd160(stText("abc"))) into tR
      stAssert "keccak differs from sha3", tK is not tS3
      stAssert "keccak differs from sha256", tK is not tS2
      stAssert "sha3 differs from sha256", tS3 is not tS2
      stAssert "ripemd differs from them all", tR is not tK and tR is not tS3 and tR is not tS2
      -- One flipped input bit must change the digest. A binding that hashed a
      -- stale or empty buffer would pass every fixed vector above by accident
      -- only if the vector were wrong too, but this catches a buffer that never
      -- gets the caller's bytes at all.
      stAssert "one changed input byte changes the digest", stHex(cxKeccak256(stText("abc"))) is not stHex(cxKeccak256(stText("abd")))
   catch tError
      stSectionFailed "independence", tError
   end try
end stRunIndependence

-- CoinXT handles money, so a malformed input must produce a clean error, never
-- a wrong-but-plausible answer. Both of these are guards in the shim
-- (CNX_ERR_RANGE and CNX_ERR_BADLEN), surfaced by the .lcb as a throw.
command stRunFailClosed
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tThrew
   stSection "fail closed on malformed input"
   try
      put "false" into tThrew
      try
         get cxPbkdf2HmacSha512(stText("pw"), stText("salt"), 0, 64)
      catch tInner
         put "true" into tThrew
      end try
      stAssert "zero iterations is refused", tThrew is "true"

      put "false" into tThrew
      try
         get cxPbkdf2HmacSha512(stText("pw"), stText("salt"), 1, 0)
      catch tInner2
         put "true" into tThrew
      end try
      stAssert "a zero-length output request is refused", tThrew is "true"
   catch tError
      stSectionFailed "fail closed", tError
   end try
end stRunFailClosed

-- ---- the secp256k1 curve (phase 2) -------------------------------------------
-- These sections are the reason phase 2 needs an engine pass at all. The shim
-- itself is already proven headless by tools/coin-kat.py against the same
-- vectors; what only an engine can answer is whether the BINDING carries them.
-- Two shapes below are new to coinxt.lcb and are the ones to watch if this run
-- goes red: cxPublicKey passes a boolean through a C int flag, and cxVerify and
-- cxSeckeyIsValid RETURN Boolean where every phase-1 handler returned Data.

command stRunCurveKeys
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tPubC, tPubU, tTweaked
   stSection "secp256k1 keys"
   try
      put stSeckeyOne() into tSk
      -- cxNewSeckey validates caller entropy and hands it back unchanged. The
      -- private key 1 is the generator G, which is why no vector table is
      -- needed here: this public key is the curve's own definition.
      stAssert "cxNewSeckey accepts a valid key", stHex(cxNewSeckey(tSk)) is stHex(tSk)
      stAssert "cxSeckeyIsValid says true for a valid key", cxSeckeyIsValid(tSk) is true
      put cxPublicKey(tSk, true) into tPubC
      put cxPublicKey(tSk, false) into tPubU
      stAssert "cxPublicKey compressed is G", stHex(tPubC) is kPubOneCompressed
      stAssert "cxPublicKey uncompressed is G", stHex(tPubU) is kPubOneUncompressed
      -- The boolean flag is the new marshalling shape (an LCB Boolean into a C
      -- int). If it were dropped, both calls would return the same length.
      stAssert "the compressed key is 33 bytes", the number of bytes of tPubC is 33
      stAssert "the uncompressed key is 65 bytes", the number of bytes of tPubU is 65
      stAssert "cxPubkeyDecompress rebuilds the uncompressed key", stHex(cxPubkeyDecompress(tPubC)) is stHex(tPubU)
      stAssert "cxPubkeyDecompress of an uncompressed key is a no-op", stHex(cxPubkeyDecompress(tPubU)) is stHex(tPubU)
      -- The two ABI-4 tweak entry points. BIP-32 non-hardened derivation is
      -- built on the claim that tweaking the PRIVATE key and tweaking the
      -- PUBLIC key land on the same point; if they ever disagreed, an xpub
      -- watch-only wallet would generate addresses the xprv cannot spend, and
      -- nothing above this line would notice. 1 + 1 = 2 pins both to the
      -- curve's own second point rather than only to each other.
      put cxSeckeyTweakAdd(tSk, tSk) into tTweaked
      stAssert "cxSeckeyTweakAdd of 1 by 1 is the scalar 2", stHex(tTweaked) is stHex(stRepeatByte(0, 31) & numToByte(2))
      stAssert "and its public key is 2G", stHex(cxPublicKey(tTweaked, true)) is kPubTwoCompressed
      stAssert "cxPubkeyTweakAdd of G by 1 is also 2G", stHex(cxPubkeyTweakAdd(tPubC, tSk)) is kPubTwoCompressed
      stAssert "so private and public tweaking agree", stHex(cxPubkeyTweakAdd(tPubC, tSk)) is stHex(cxPublicKey(cxSeckeyTweakAdd(tSk, tSk), true))
      -- Both refuse a ZERO tweak, where upstream's public entry point accepts
      -- it. Accepting on one path and refusing on the other is the
      -- interoperability bug this member exists to prevent, so the symmetry is
      -- asserted rather than assumed.
      stAssert "a zero tweak is refused on the private path", stThrows2("cxSeckeyTweakAdd", tSk, stRepeatByte(0, 32))
      stAssert "a zero tweak is refused on the public path", stThrows2("cxPubkeyTweakAdd", tPubC, stRepeatByte(0, 32))
      stAssert "a wrong-length tweak is refused", stThrows2("cxSeckeyTweakAdd", tSk, stRepeatByte(1, 31))
   catch tError
      stSectionFailed "secp256k1 keys", tError
   end try
end stRunCurveKeys

command stRunCurveSign
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tDigest, tSig, tAgain
   stSection "ECDSA signing (RFC 6979, published vector)"
   try
      put stSeckeyOne() into tSk
      -- The digest is built with cxSha256, which this same run already checked
      -- against FIPS 180-4, so a failure here cannot be a hashing failure.
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSign(tSk, tDigest) into tSig
      stAssert "cxSign reproduces the published RFC 6979 signature", stHex(tSig) is kSigSatoshi
      stAssert "the signature is 64 bytes", the number of bytes of tSig is cxSignatureLen()
      -- Determinism is the property the whole vector table rests on. The native
      -- code draws fresh OS entropy for side-channel blinding on every call;
      -- that blinding cancels, and this is the check that says so from script.
      put cxSign(tSk, tDigest) into tAgain
      stAssert "signing twice gives the same signature", stHex(tAgain) is stHex(tSig)
   catch tError
      stSectionFailed "ECDSA signing", tError
   end try
end stRunCurveSign

command stRunCurveVerify
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tDigest, tSig, tPubC, tPubU, tBad, tOtherPub
   stSection "ECDSA verification (true, and false)"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSign(tSk, tDigest) into tSig
      put cxPublicKey(tSk, true) into tPubC
      put cxPublicKey(tSk, false) into tPubU
      -- cxVerify RETURNS Boolean rather than throwing, which is the second new
      -- shape in this file. A binding that mismarshalled it would most likely
      -- throw or return empty, so assert the true case explicitly.
      stAssert "cxVerify accepts a good signature (compressed key)", cxVerify(tPubC, tDigest, tSig) is true
      stAssert "cxVerify accepts a good signature (uncompressed key)", cxVerify(tPubU, tDigest, tSig) is true
      put stFlipByte(tSig, 6) into tBad
      stAssert "cxVerify rejects a tampered signature", cxVerify(tPubC, tDigest, tBad) is false
      stAssert "cxVerify rejects a wrong digest", cxVerify(tPubC, cxSha256(stText("not the message")), tSig) is false
      put cxPublicKey(stSeckeyTwo(), true) into tOtherPub
      stAssert "cxVerify rejects the wrong public key", cxVerify(tOtherPub, tDigest, tSig) is false
   catch tError
      stSectionFailed "ECDSA verification", tError
   end try
end stRunCurveVerify

command stRunCurveRecover
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tDigest, tSig, tRec, tPubU
   stSection "recoverable signing and ecrecover"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSignRecoverable(tSk, tDigest) into tSig
      put cxPublicKey(tSk, false) into tPubU
      stAssert "a recoverable signature is 65 bytes", the number of bytes of tSig is cxRecoverableSignatureLen()
      stAssert "its first 64 bytes are the plain signature", stHex(byte 1 to 64 of tSig) is kSigSatoshi
      stAssert "the recovery id is 0..3", byteToNum(byte 65 of tSig) >= 0 and byteToNum(byte 65 of tSig) <= 3
      put cxRecover(tSig, tDigest) into tRec
      -- The whole point of recovery: get the signer back from the signature
      -- alone. Recovery ALSO succeeds for a wrong id and returns some other
      -- key, so comparing against the expected key is the real check.
      stAssert "cxRecover returns the signing public key", stHex(tRec) is stHex(tPubU)
      stAssert "and that key is the published G", stHex(tRec) is kPubOneUncompressed
   catch tError
      stSectionFailed "ecrecover", tError
   end try
end stRunCurveRecover

command stRunCurveEcdh
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tA, tB, tPubA, tPubB, tShared1, tShared2
   stSection "ECDH"
   try
      put stSeckeyOne() into tA
      put stSeckeyTwo() into tB
      put cxPublicKey(tA, true) into tPubA
      put cxPublicKey(tB, true) into tPubB
      put cxEcdh(tA, tPubB) into tShared1
      put cxEcdh(tB, tPubA) into tShared2
      stAssert "both sides derive the same point", stHex(tShared1) is stHex(tShared2)
      stAssert "the shared point is 65 bytes", the number of bytes of tShared1 is cxEcdhLen()
      stAssert "the shared point is in uncompressed form", byteToNum(byte 1 of tShared1) is 4
      -- 1 * (2G) == 2G, so with these two keys the shared point is just the
      -- public key of the other side. That makes this leg checkable against a
      -- value already pinned above rather than against a new magic constant.
      stAssert "1 * 2G is 2G", stHex(tShared1) is stHex(cxPublicKey(tB, false))
   catch tError
      stSectionFailed "ECDH", tError
   end try
end stRunCurveEcdh

command stRunCurveFailClosed
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tThrew, tSk, tDigest
   stSection "the curve fails closed"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("abc")) into tDigest

      -- A key of zero is not on the curve. cxSeckeyIsValid answers false (an
      -- ordinary answer for an imported key), while cxNewSeckey THROWS (fresh
      -- entropy that fails validation is a bug in the caller's RNG, not a
      -- routine outcome). Both halves of that split are checked.
      stAssert "cxSeckeyIsValid says false for an all-zero key", cxSeckeyIsValid(stRepeatByte(0, 32)) is false
      stAssert "cxSeckeyIsValid says false for a short key", cxSeckeyIsValid(stRepeatByte(1, 31)) is false

      put "false" into tThrew
      try
         get cxNewSeckey(stRepeatByte(0, 32))
      catch tInner
         put "true" into tThrew
      end try
      stAssert "cxNewSeckey refuses an all-zero key", tThrew is "true"

      put "false" into tThrew
      try
         get cxNewSeckey(stRepeatByte(7, 31))
      catch tInner2
         put "true" into tThrew
      end try
      stAssert "cxNewSeckey refuses 31 bytes of entropy", tThrew is "true"

      put "false" into tThrew
      try
         get cxSign(stRepeatByte(0, 32), tDigest)
      catch tInner3
         put "true" into tThrew
      end try
      stAssert "cxSign refuses an invalid private key", tThrew is "true"

      -- An all-zero digest is refused because a signature over it can be forged
      -- for ANY public key.
      put "false" into tThrew
      try
         get cxSign(tSk, stRepeatByte(0, 32))
      catch tInner4
         put "true" into tThrew
      end try
      stAssert "cxSign refuses an all-zero digest", tThrew is "true"

      -- A malformed public key must THROW, not answer false: it is a bug in the
      -- caller, and hiding it behind a security-shaped `false` is how a broken
      -- verify path goes unnoticed.
      put "false" into tThrew
      try
         get cxVerify(stRepeatByte(9, 20), tDigest, cxSign(tSk, tDigest))
      catch tInner5
         put "true" into tThrew
      end try
      stAssert "cxVerify throws on a malformed public key (it does not answer false)", tThrew is "true"
   catch tError
      stSectionFailed "the curve fails closed", tError
   end try
end stRunCurveFailClosed


-- ---- phase 3: the pure-script encodings --------------------------------------
-- These handlers live in src/coinxt.livecodescript, NOT in the .lcb module, so
-- they only resolve once that script is in the message path (`start using stack
-- "coinxt"`, the same way OnionXT ships its ox* surface). A "handler not found"
-- in this whole block means the script layer was not loaded, which is a setup
-- problem and not a phase-3 defect - check that first before reading further.

command stRunHex
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "hex"
   try
      stAssert "cxHexEncode of 00ff10ab", cxHexEncode(cxHexDecode("00ff10ab")) is "00ff10ab"
      stAssert "cxHexDecode accepts upper case", cxHexEncode(cxHexDecode("00FF10AB")) is "00ff10ab"
      stAssert "cxHexEncode of the empty input", cxHexEncode(cxHexDecode("")) is ""
      stAssert "an odd-length hex string is refused", stThrows("cxHexDecode", "abc")
      stAssert "a non-hex character is refused", stThrows("cxHexDecode", "zz")
   catch tError
      stSectionFailed "hex", tError
   end try
end stRunHex

command stRunBase58
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tPayload, tI, tPadded
   stSection "Base58Check"
   try
      put cxHexDecode(kBase58Payload) into tPayload
      -- hash256 first, on its own. It is the checksum function this encoding is
      -- defined in terms of, and an encoder/decoder pair that agreed with each
      -- other while both used the wrong hash would pass every round-trip below.
      stAssert "cxHash256 of abc is the published double-SHA-256", stHex(cxHash256(stText("abc"))) is kHash256Abc
      stAssert "cxHash256 is 32 bytes", the number of bytes of cxHash256(stText("")) is 32
      stAssert "and it is genuinely SHA-256 applied twice", stHex(cxHash256(stText("abc"))) is stHex(cxSha256(cxSha256(stText("abc"))))
      stAssert "encodes the worked example", cxBase58CheckEncode(tPayload) is kBase58Address
      stAssert "decodes it back", cxHexEncode(cxBase58CheckDecode(kBase58Address)) is stToLowerText(kBase58Payload)
      -- The checksum is the entire point of the encoding: one flipped character
      -- must be refused, never coerced into a nearby valid-looking payload.
      stAssert "a corrupt checksum is refused", stThrows("cxBase58CheckDecode", kBase58Corrupt)
      stAssert "a character outside the alphabet is refused", stThrows("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtj0O")
      -- Leading zero bytes must survive as leading "1"s, one for one. That is
      -- what makes a mainnet P2PKH address start with a 1 at all.
      put numToByte(0) & numToByte(0) & cxHexDecode("deadbeef") into tPadded
      stAssert "two leading zero bytes give two leading ones", char 1 to 2 of cxBase58CheckEncode(tPadded) is "11"
      stAssert "the round trip preserves them", cxHexEncode(cxBase58CheckDecode(cxBase58CheckEncode(tPadded))) is "0000deadbeef"
   catch tError
      stSectionFailed "Base58Check", tError
   end try
end stRunBase58

command stRunBech32
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tDecoded
   stSection "bech32 and bech32m"
   try
      put cxBech32DecodeValues(kBech32Valid) into tDecoded
      stAssert "a published bech32 string decodes", tDecoded["hrp"] is "abcdef"
      stAssert "and reports the bech32 encoding", tDecoded["spec"] is "bech32"
      stAssert "a mixed-case string is refused", stThrows("cxBech32DecodeValues", "A1G7SGD8x")
      stAssert "a string with no separator is refused", stThrows("cxBech32DecodeValues", "pzry9x0s0muk")
      stAssert "an empty human-readable part is refused", stThrows("cxBech32DecodeValues", "1pzry9x0s0muk")
      stAssert "a checksum computed over an uppercase HRP is refused", stThrows("cxBech32DecodeValues", "A1G7SGD8")
      stAssert "a data character outside the charset is refused", stThrows("cxBech32DecodeValues", "x1b4n0q5v")
   catch tError
      stSectionFailed "bech32", tError
   end try
end stRunBech32

command stRunAddresses
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tPubC, tPubU, tSeckey, tDecoded
   stSection "addresses from the generator G"
   try
      put stRepeatByte(0, 31) & numToByte(1) into tSeckey
      put cxPublicKey(tSeckey, true) into tPubC
      put cxPublicKey(tSeckey, false) into tPubU
      -- Each of these is a PUBLISHED answer, not a CoinXT expectation.
      stAssert "cxBtcAddressP2PKH of G", cxBtcAddressP2PKH(tPubC) is kP2pkhOfG
      stAssert "cxBtcAddressP2WPKH of G is the BIP-173 vector", cxBtcAddressP2WPKH(tPubC) is kP2wpkhOfG
      stAssert "cxBtcAddressP2TR of x-only G is the BIP-350 vector", cxBtcAddressP2TR(byte 2 to 33 of tPubU) is kP2trOfG
      stAssert "cxEthAddress of G (from the compressed key)", cxEthAddressChecksum(cxEthAddress(tPubC)) is kEthOfG
      stAssert "cxEthAddress agrees from the uncompressed key", cxEthAddress(tPubU) is cxEthAddress(tPubC)
      -- An uncompressed key in a v0 SegWit address makes funds unspendable by
      -- every modern wallet, so it must be refused rather than encoded.
      stAssert "P2WPKH refuses an uncompressed key", stThrows("cxBtcAddressP2WPKH", tPubU)
      stAssert "P2TR refuses a 33-byte key", stThrows("cxBtcAddressP2TR", tPubC)
      -- Round-trip through the SegWit decoder, including the network check.
      put cxSegwitAddressDecode("bc", kP2wpkhOfG) into tDecoded
      stAssert "the decoded witness version is 0", tDecoded["version"] is 0
      stAssert "the decoded program is hash160 of G", cxHexEncode(tDecoded["program"]) is cxHexEncode(cxHash160(tPubC))
      put cxSegwitAddressDecode("tb", kSegwitTestnet) into tDecoded
      stAssert "a testnet v0 script address decodes", cxHexEncode(tDecoded["program"]) is kSegwitTestnetProgram
      stAssert "a mainnet address is refused under the testnet HRP", stThrows2("cxSegwitAddressDecode", "tb", kP2wpkhOfG)
      -- THE rule BIP-350 exists for.
      stAssert "a version 0 address with a bech32m checksum is refused", stThrows2("cxSegwitAddressDecode", "bc", kSegwitV0WithBech32m)
   catch tError
      stSectionFailed "addresses", tError
   end try
end stRunAddresses

command stRunEip55
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   stSection "EIP-55 checksummed Ethereum addresses"
   try
      stAssert "checksums the first specification example", cxEthAddressChecksum(stToLowerText(kEip55A)) is kEip55A
      stAssert "checksums the second", cxEthAddressChecksum(stToLowerText(kEip55B)) is kEip55B
      stAssert "recognises a correctly checksummed address", cxEthAddressIsChecksummed(kEip55A) is true
      -- An all-lowercase address carries NO checksum, so reporting it as valid
      -- would quietly retire the protection EIP-55 exists to give.
      stAssert "an all-lowercase address is NOT reported as checksummed", cxEthAddressIsChecksummed(stToLowerText(kEip55A)) is false
      stAssert "a wrong-length address is refused", stThrows("cxEthAddressChecksum", "0xdeadbeef")
   catch tError
      stSectionFailed "EIP-55", tError
   end try
end stRunEip55

command stRunRlp
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tCatDog, tDecoded
   stSection "RLP"
   try
      stAssert "encodes the string dog", cxHexEncode(cxRlpEncodeBytes(stText("dog"))) is "83646f67"
      stAssert "encodes the empty string", cxHexEncode(cxRlpEncodeBytes("")) is "80"
      stAssert "encodes a single byte below 0x80 as itself", cxHexEncode(cxRlpEncodeBytes(numToByte(15))) is "0f"
      stAssert "encodes the empty list", cxHexEncode(cxRlpEncodeList("")) is "c0"
      put cxRlpEncodeBytes(stText("cat")) & cxRlpEncodeBytes(stText("dog")) into tCatDog
      stAssert "encodes the list of cat and dog", cxHexEncode(cxRlpEncodeList(tCatDog)) is "c88363617483646f67"
      put cxRlpDecode(cxHexDecode("83646f67")) into tDecoded
      stAssert "decodes a string item", tDecoded["kind"] is "bytes"
      stAssert "and its payload", cxHexEncode(tDecoded["payload"]) is "646f67"
      put cxRlpDecode(cxHexDecode("c88363617483646f67")) into tDecoded
      stAssert "decodes a list item", tDecoded["kind"] is "list"
      -- RLP's guarantee is one value, one encoding. A decoder that accepts a
      -- second spelling breaks every hash computed over the result.
      stAssert "a single byte wrapped in a length prefix is refused", stThrows("cxRlpDecode", cxHexDecode("8100"))
   catch tError
      stSectionFailed "RLP", tError
   end try
end stRunRlp

command stRunWif
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tDecoded, tThrew
   stSection "WIF (wallet import format)"
   try
      -- The mainnet/uncompressed answer IS the Bitcoin wiki's published worked
      -- example; the other forms are oracle-derived (see the constants block).
      stAssert "encodes the wiki worked example (mainnet, uncompressed)", cxWifEncode(kWifSeckey, "mainnet", false) is kWifUncompressed
      stAssert "the compressed form is the same key with the 0x01 marker", cxWifEncode(kWifSeckey, "mainnet", true) is kWifCompressed
      stAssert "the testnet form differs only in its version byte", cxWifEncode(kWifSeckey, "testnet", true) is kWifTestnet
      -- The three encodings must be three different strings, or the network
      -- and the flag are not reaching the payload at all.
      stAssert "compressed and uncompressed forms are distinct", kWifCompressed is not kWifUncompressed
      stAssert "mainnet and testnet forms are distinct", kWifTestnet is not kWifCompressed
      put cxWifDecode(kWifCompressed) into tDecoded
      stAssert "decodes back to the same key", tDecoded["seckey"] is kWifSeckey
      stAssert "and reports mainnet", tDecoded["network"] is "mainnet"
      stAssert "and reports the compressed flag", tDecoded["compressed"] is true
      put cxWifDecode(kWifUncompressed) into tDecoded
      stAssert "the uncompressed form reports compressed false", tDecoded["compressed"] is false
      put cxWifDecode(kWifTestnet) into tDecoded
      stAssert "the testnet form reports testnet", tDecoded["network"] is "testnet"
      -- The refusals. A typo in a pasted key must never decode to a plausible
      -- neighbouring wallet, so "it threw" is the assertion.
      stAssert "a corrupt checksum is refused", stThrows("cxWifDecode", kWifBadChecksum)
      stAssert "an xprv is refused (wrong payload length)", stThrows("cxWifDecode", kBip32V1Xprv)
      put "false" into tThrew
      try
         get cxWifEncode(kWifSeckey, "regtest", true)
      catch tInner
         put "true" into tThrew
      end try
      stAssert "an unknown network is refused", tThrew is "true"
      put "false" into tThrew
      try
         get cxWifEncode("deadbeef", "mainnet", true)
      catch tInner2
         put "true" into tThrew
      end try
      stAssert "a short key is refused", tThrew is "true"
   catch tError
      stSectionFailed "WIF", tError
   end try
end stRunWif

-- ==============================================================================
-- ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak.
--
-- NEW SURFACE, NO ENGINE PASS YET. These handlers postdate the 2026-08-10 and
-- 2026-08-12 runs. What they owe an engine, specifically: that cxSchnorrSign's
-- THREE-argument shape marshals, that an EMPTY Data in the aux and merkle-root
-- slots reaches the shim as a length of 0 (this is the family's proven "absent"
-- spelling - cxKeccak256("") settled it on 2026-08-08 - but it has never been
-- used for an OPTIONAL argument before), that cxSchnorrVerify's Boolean answers
-- both ways, and that cxTaprootTweak's array return reads back by name.
-- ==============================================================================

command stRunSchnorr
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tPub, tMsg, tAux, tSig, tFreshA, tFreshB
   stSection "BIP-340 Schnorr (published vectors, positive and negative)"
   try
      put cxHexDecode(kSchnorrSk1) into tSk
      put cxHexDecode(kSchnorrMsg1) into tMsg
      put cxHexDecode(kSchnorrAux1) into tAux
      put cxXOnlyPubkey(tSk) into tPub
      stAssert "cxXOnlyPubkey reproduces BIP-340 vector 1's x-only key", stSameHex(cxHexEncode(tPub), kSchnorrPub1)
      put cxSchnorrSign(tSk, tMsg, tAux) into tSig
      stAssert "cxSchnorrSign reproduces vector 1 byte for byte", stSameHex(cxHexEncode(tSig), kSchnorrSig1)
      stAssert "cxSchnorrVerify accepts it", cxSchnorrVerify(tPub, tMsg, tSig) is true
      -- The negatives. A Schnorr verifier that only ever meets good signatures
      -- passes every positive case above while accepting a forgery.
      stAssert "cxSchnorrVerify rejects a tampered signature", cxSchnorrVerify(tPub, tMsg, stFlipByte(tSig, 40)) is false
      stAssert "cxSchnorrVerify rejects the wrong message", cxSchnorrVerify(tPub, tSk, tSig) is false
      stAssert "cxSchnorrVerify rejects the wrong key", cxSchnorrVerify(cxHexDecode(kTapInternal0), tMsg, tSig) is false
      -- BIP-340 case 5. The expected result is FALSE, not an error: a verifier
      -- that threw here would be unusable on a third party's signature.
      stAssert "a public key that is not on the curve answers false, not an error", cxSchnorrVerify(cxHexDecode(kSchnorrPubOffCurve), tMsg, tSig) is false
      -- BIP-340 case 6: has_even_y(R) is false.
      stAssert "a signature whose R has an odd Y is rejected", cxSchnorrVerify(tPub, tMsg, cxHexDecode(kSchnorrSigOddR)) is false
      -- An ABSENT aux means FRESH randomness, never an all-zero aux. Two calls
      -- must differ, both must verify, and neither may be the pinned vector -
      -- which is what would come back if empty were passed through as a null
      -- and upstream read it as zeros.
      put cxSchnorrSign(tSk, tMsg, empty) into tFreshA
      put cxSchnorrSign(tSk, tMsg, empty) into tFreshB
      stAssert "an absent aux gives two DIFFERENT signatures", not stSameHex(cxHexEncode(tFreshA), cxHexEncode(tFreshB))
      stAssert "and neither one is the zero-aux signature", not stSameHex(cxHexEncode(tFreshA), kSchnorrSig1)
      stAssert "both signatures still verify", cxSchnorrVerify(tPub, tMsg, tFreshA) is true and cxSchnorrVerify(tPub, tMsg, tFreshB) is true
      -- The three new length accessors, called by name.
      stAssert "cxSchnorrSignatureLen is 64", cxSchnorrSignatureLen() is 64
      stAssert "cxXOnlyPubkeyLen is 32", cxXOnlyPubkeyLen() is 32
      stAssert "cxTaprootOutputLen is 33 (key plus a parity byte)", cxTaprootOutputLen() is 33
      -- Fail closed.
      stAssert "cxXOnlyPubkey refuses a 33-byte public key", stThrows("cxXOnlyPubkey", cxHexDecode(kPubOneCompressed))
      stAssert "cxSchnorrVerify refuses a 33-byte key (a length is a caller bug, not a verdict)", stThrows3("cxSchnorrVerify", cxHexDecode(kPubOneCompressed), tMsg, tSig)
   catch tError
      stSectionFailed "BIP-340 Schnorr", tError
   end try
end stRunSchnorr

command stRunTaproot
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tInternal, tTweak, tZeroTweak, tSeckey, tTweaked, tOutKey, tSig, tMsg, tRecord
   stSection "BIP-341 Taproot (published wallet vectors)"
   try
      put cxHexDecode(kTapInternal0) into tInternal
      put cxTaprootTweak(tInternal, empty) into tTweak
      put tTweak["outputKey"] into tOutKey
      stAssert "the key-path-only output key matches BIP-341 vector 0", stSameHex(cxHexEncode(tOutKey), kTapOutput0)
      stAssert "the parity byte is 0 or 1", tTweak["parity"] is 0 or tTweak["parity"] is 1
      -- cxTaprootTweakPubkey is the .lcb handler cxTaprootTweak is a thin
      -- slicer over, and it is public API in its own right. Pin it to the
      -- PUBLISHED key first and only then assert the two agree - the
      -- cxHdDeriveChild lesson: testing only the wrapper cannot separate "the
      -- record is right" from "the record and the slicing are wrong in the
      -- same direction". This also pins the 33-byte layout: 32 bytes of key
      -- then one parity byte, in that order.
      put cxTaprootTweakPubkey(tInternal, empty) into tRecord
      stAssert "cxTaprootTweakPubkey returns a 33-byte record", the number of bytes of tRecord is cxTaprootOutputLen()
      stAssert "its first 32 bytes are the published output key", stSameHex(cxHexEncode(byte 1 to 32 of tRecord), kTapOutput0)
      stAssert "and its last byte is the parity cxTaprootTweak reports", byteToNum(byte 33 of tRecord) is tTweak["parity"]
      stAssert "and the address is BIP-341's published bc1p string", cxBtcAddressP2TRFromInternal(tInternal, empty) is kTapAddress0
      -- The same operation WITH a script tree, so both lengths of tagged-hash
      -- input (32 bytes and 64) have a published answer behind them.
      put cxTaprootTweak(cxHexDecode(kTapInternal1), cxHexDecode(kTapRoot1)) into tTweak
      stAssert "a script-tree root gives vector 1's output key", stSameHex(cxHexEncode(tTweak["outputKey"]), kTapOutput1)
      stAssert "and vector 1's published address", cxBtcAddressP2TRFromInternal(cxHexDecode(kTapInternal1), cxHexDecode(kTapRoot1)) is kTapAddress1
      -- THE CONSENSUS DISTINCTION. An EMPTY merkle root is the specification's
      -- empty byte string; 32 ZERO BYTES is a script commitment to a zero root.
      -- They hash different lengths and must give different output keys. If
      -- these ever agreed, every key-path-only address this library produced
      -- would be wrong, and it would still look like an address.
      put cxTaprootTweak(tInternal, stRepeatByte(0, 32)) into tZeroTweak
      stAssert "an EMPTY merkle root is not a 32-zero root", not stSameHex(cxHexEncode(tZeroTweak["outputKey"]), kTapOutput0)
      -- The private half, and then the loop closed: the tweaked PRIVATE key
      -- must sign for the output key the PUBLIC path derived on its own.
      put cxHexDecode(kTapSeckey0) into tSeckey
      stAssert "the internal key is the x-only key of its private key", stSameHex(cxHexEncode(cxXOnlyPubkey(tSeckey)), kTapInternal0)
      put cxTaprootTweakSeckey(tSeckey, empty) into tTweaked
      stAssert "the tweaked private key matches BIP-341's published value", stSameHex(cxHexEncode(tTweaked), kTapTweaked0)
      put cxHexDecode(kSchnorrMsg1) into tMsg
      put cxSchnorrSign(tTweaked, tMsg, cxHexDecode(kSchnorrAux1)) into tSig
      stAssert "the tweaked private key signs for the tweaked public key", cxSchnorrVerify(tOutKey, tMsg, tSig) is true
      -- cxBtcAddressP2TR is UNCHANGED and must stay so: it encodes the output
      -- key it is given and never tweaks. If a future edit made it tweak, every
      -- existing correct call would silently become a DOUBLE tweak - a
      -- valid-looking address nobody can spend from - so the two handlers
      -- disagreeing on the same 32 bytes is the assertion.
      stAssert "cxBtcAddressP2TR still does NOT tweak", cxBtcAddressP2TR(tInternal) is not kTapAddress0
      -- Fail closed.
      stAssert "a 33-byte internal key is refused", stThrows2("cxTaprootTweak", cxHexDecode(kPubOneCompressed), empty)
      stAssert "an internal key that is not on the curve is refused", stThrows2("cxTaprootTweak", cxHexDecode(kSchnorrPubOffCurve), empty)
      stAssert "a 31-byte merkle root is refused", stThrows2("cxTaprootTweak", tInternal, stRepeatByte(0, 31))
      stAssert "cxBtcAddressP2TRFromInternal refuses a 33-byte key", stThrows2("cxBtcAddressP2TRFromInternal", cxHexDecode(kPubOneCompressed), empty)
      stAssert "cxTaprootTweakSeckey refuses a 31-byte key", stThrows2("cxTaprootTweakSeckey", stRepeatByte(0, 31), empty)
   catch tError
      stSectionFailed "BIP-341 Taproot", tError
   end try
end stRunTaproot

-- ---- small helpers -----------------------------------------------------------
-- Did calling pHandler with one argument throw? The encoders fail closed by
-- throwing, and "it threw" is the assertion, so this keeps each check to one
-- readable line instead of a nested try per case.
function stThrows pHandler, pArg
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArg)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows

-- The two-argument form (cxSegwitAddressDecode takes an HRP and an address).
function stThrows2 pHandler, pArgA, pArgB
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArgA, pArgB)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows2

-- The three-argument form (cxSchnorrVerify takes a key, a message and a
-- signature).
function stThrows3 pHandler, pArgA, pArgB, pArgC
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArgA, pArgB, pArgC)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows3

-- Byte-exact equality for two HEX STRINGS, which `is` alone cannot promise.
-- `is` compares two operands that both LOOK numeric as NUMBERS, and a hex
-- string can be all decimal digits - rarely for a 64-byte signature, but this
-- library's whole discipline is that "rarely" is not "never", and the
-- Base58Check checksum path already had to be moved off `is` for exactly this
-- reason. Prefixing a letter forces the string comparison, which with `the
-- caseSensitive` set true (stRun does) is byte for byte.
function stSameHex pA, pB
   return ("h" & pA) is ("h" & pB)
end stSameHex

-- ASCII lowercase, by byte value, so it does not depend on the caseSensitive.
function stToLowerText pText
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
end stToLowerText


-- Text to Data. Every cx* input is a Data; a bare literal would be text, and the
-- engine would be free to re-encode it.
function stText pString
   return textEncode(pString, "utf-8")
end stText

-- Lowercase hex, encoded here rather than borrowed. CoinXT's own hex encoder is
-- a phase-2 script-layer encoding that does not exist yet, and reaching for
-- SodiumXT's sxBin2Hex would make a CoinXT check fail whenever SodiumXT is the
-- absent member. A harness must not need one member present to test another.
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

-- The private key 1: 31 zero bytes then a 1. Built rather than written as a hex
-- literal because this file has no hex DECODER (cxHexDecode is a phase-3
-- script-layer encoding that does not exist yet), and a harness must not depend
-- on the layer it is testing for its own inputs.
function stSeckeyOne
   return stRepeatByte(0, 31) & numToByte(1)
end stSeckeyOne

-- The private key 2, whose public key is 2G.
function stSeckeyTwo
   return stRepeatByte(0, 31) & numToByte(2)
end stSeckeyTwo

-- Return pData with byte pIndex changed to a different value, for the "must be
-- rejected" checks. Addition mod 256 rather than bitXor: the family gotcha list
-- warns that bitAnd/bitOr/bitXor are OPERATORS, not functions, and this file
-- avoids the whole question.
function stFlipByte pData, pIndex
   local tByte
   put (byteToNum(byte pIndex of pData) + 1) mod 256 into tByte
   return byte 1 to (pIndex - 1) of pData & numToByte(tByte) & \
      byte (pIndex + 1) to (the number of bytes of pData) of pData
end stFlipByte

-- pCount copies of byte pCode, built without string-escape folklore.
function stRepeatByte pCode, pCount
   local tOne, tOut
   put numToByte(pCode) into tOne
   put tOne into tOut
   -- double up to size, then trim: O(log n) concatenations
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte

-- ==============================================================================
-- Phase 4. The most consequential sections in this file: see the note above the
-- phase-4 constants for why a wrong answer here does not announce itself.
-- ==============================================================================

command stRunBip39
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tEnt, tMnemonic
   stSection "BIP-39 mnemonics"
   try
      put cxHexDecode(kBip39Entropy12) into tEnt
      stAssert "12 words from all-zero entropy", cxMnemonicFromEntropy(tEnt) is kBip39Mnemonic
      stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(kBip39Mnemonic)) is kBip39Entropy12
      put cxHexDecode(kBip39Entropy24) into tEnt
      stAssert "24 words from all-ones entropy", cxMnemonicFromEntropy(tEnt) is kBip39Mnemonic24
      stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(kBip39Mnemonic24)) is kBip39Entropy24
      stAssert "cxMnemonicValidate accepts it", cxMnemonicValidate(kBip39Mnemonic) is true
      -- The checksum is the whole reason a mnemonic is 12 words and not 11: it
      -- is what catches a single mistyped word before it becomes a lost wallet.
      stAssert "one wrong word fails the checksum", cxMnemonicValidate(kBip39Mnemonic12Bad) is false
      stAssert "a word outside the list is refused", cxMnemonicValidate("zzzz" && kBip39Mnemonic) is false
      -- Whitespace is normalized because BIP-39 derives the seed from the
      -- STRING; a pasted trailing newline must not change the wallet.
      put "  " & kBip39Mnemonic & "  " into tMnemonic
      stAssert "surrounding whitespace is normalized away", cxMnemonicValidate(tMnemonic) is true
      -- cxMnemonicNormalize on its own, because it is public API and because
      -- every other BIP-39 handler runs it first: if it were wrong, validate
      -- and to-seed would be wrong together and agree with each other.
      stAssert "cxMnemonicNormalize strips the padding", cxMnemonicNormalize(tMnemonic) is kBip39Mnemonic
      stAssert "an already-clean mnemonic is returned unchanged", cxMnemonicNormalize(kBip39Mnemonic) is kBip39Mnemonic
      stAssert "it is idempotent", cxMnemonicNormalize(cxMnemonicNormalize(tMnemonic)) is kBip39Mnemonic
      -- Tabs, newlines and runs of spaces are what a pasted backup actually
      -- contains, and BIP-39 derives the seed from the STRING, so collapsing
      -- them is the difference between restoring a wallet and missing it.
      stAssert "tabs and newlines collapse to single spaces", cxMnemonicNormalize("abandon" & tab & "abandon" & return & "  abandon ") is "abandon abandon abandon"
      stAssert "an empty string normalizes to empty", cxMnemonicNormalize("   ") is ""
      stAssert "the seed with no passphrase", cxHexEncode(cxMnemonicToSeed(kBip39Mnemonic, "")) is kBip39SeedNoPass
      stAssert "the seed with the TREZOR passphrase", cxHexEncode(cxMnemonicToSeed(kBip39Mnemonic, "TREZOR")) is kBip39Seed
      stAssert "a normalized mnemonic gives the same seed", cxHexEncode(cxMnemonicToSeed(tMnemonic, "")) is kBip39SeedNoPass
      stAssert "an entropy length BIP-39 does not define is refused", stThrows("cxMnemonicFromEntropy", stRepeatByte(0, 17))
      -- The wordlist crosses from the shim; if it were the wrong list or in the
      -- wrong order, everything above would still be self-consistent.
      stAssert "the wordlist is 2048 slots of 8 bytes", the number of bytes of cxBip39Wordlist() is 16384
      stAssert "cxBip39WordlistLen agrees", cxBip39WordlistLen() is 16384
      stAssert "the first word is abandon", byte 1 to 7 of cxBip39Wordlist() is "abandon"
   catch tError
      stSectionFailed "BIP-39", tError
   end try
end stRunBip39

command stRunBip32
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tNode, tDeep, tWatch, tChild, tStep
   stSection "BIP-32 derivation"
   try
      put cxHdFromSeed(cxHexDecode(kBip32Seed1)) into tNode
      stAssert "vector 1 master xprv", cxXprv(tNode) is kBip32V1Xprv
      stAssert "vector 1 master xpub", cxXpub(tNode) is kBip32V1Xpub
      stAssert "the master node is at depth 0", tNode["depth"] is 0
      put cxHdDerivePath(tNode, "m/0'") into tChild
      stAssert "vector 1 m/0' xprv", cxXprv(tChild) is kBip32V1H0Xprv
      stAssert "vector 1 m/0' xpub", cxXpub(tChild) is kBip32V1H0Xpub
      stAssert "h is accepted as a hardened marker", cxXprv(cxHdDerivePath(tNode, "m/0h")) is kBip32V1H0Xprv
      -- cxHdDeriveChild is the single CKD step cxHdDerivePath is a loop over,
      -- and it is public API in its own right. Pin it to the SAME published
      -- vector rather than only to the path walker: a shared defect in the
      -- step would make the two agree while both were wrong, so the first
      -- assertion here is against BIP-32's own number and the second is the
      -- agreement check on top of it.
      stAssert "cxHdDeriveChild reaches m/0' as one hardened step", cxXprv(cxHdDeriveChild(tNode, 2147483648)) is kBip32V1H0Xprv
      stAssert "and a normal step agrees with the path walker", cxXprv(cxHdDeriveChild(tChild, 1)) is cxXprv(cxHdDerivePath(tNode, "m/0'/1"))
      stAssert "index 0 is not treated as hardened", cxXprv(cxHdDeriveChild(tNode, 0)) is cxXprv(cxHdDerivePath(tNode, "m/0"))
      put cxHdDeriveChild(tChild, 1) into tStep
      stAssert "each step advances the depth by one", tStep["depth"] is 2
      stAssert "a child index at or above 2^32 is refused", stThrows2("cxHdDeriveChild", tNode, 4294967296)
      stAssert "a negative child index is refused", stThrows2("cxHdDeriveChild", tNode, -1)
      put cxHdDerivePath(tNode, kBip32V1DeepPath) into tDeep
      stAssert "vector 1 five levels deep", cxXprv(tDeep) is kBip32V1DeepXprv
      stAssert "and it is at depth 5", tDeep["depth"] is 5
      -- Vector 3 is in the BIP for one reason: a leading zero in the master key.
      stAssert "vector 3 (leading-zero master key)", cxXprv(cxHdFromSeed(cxHexDecode(kBip32Seed3))) is kBip32V3Xprv
      -- A watch-only node is the whole point of an xpub, and its limits are the
      -- whole point of hardened derivation.
      put cxHdNeuter(tChild) into tWatch
      stAssert "neuter leaves the source node's key alone", tChild["seckey"] is not ""
      stAssert "a watch-only node has no private key", tWatch["seckey"] is ""
      stAssert "and still derives the same normal child", cxXpub(cxHdDerivePath(tWatch, "m/1")) is cxXpub(cxHdDerivePath(tChild, "m/1"))
      stAssert "but cannot make an xprv", stThrows("cxXprv", tWatch)
      stAssert "and cannot derive a hardened child", stThrows2("cxHdDerivePath", tWatch, "m/0'")
      -- A path that parses loosely is a path that silently derives the wrong
      -- wallet, so each of these must throw rather than be interpreted.
      stAssert "a path without a leading m is refused", stThrows2("cxHdDerivePath", tNode, "0/1")
      stAssert "an empty level is refused", stThrows2("cxHdDerivePath", tNode, "m/")
      -- "m/" and "m/0'/" are the trailing-separator cases the 2026-08-10
      -- engine pass caught failing OPEN: a trailing delimiter is invisible
      -- to `the number of items`, so the walker returned the node unchanged
      -- instead of throwing. The second spelling pins the fix at depth too.
      stAssert "a trailing separator is refused", stThrows2("cxHdDerivePath", tNode, "m/0'/")
      stAssert "a non-digit level is refused", stThrows2("cxHdDerivePath", tNode, "m/1e3")
      stAssert "a level at or above 2^31 is refused", stThrows2("cxHdDerivePath", tNode, "m/2147483648")
      stAssert "a too-short seed is refused", stThrows("cxHdFromSeed", stRepeatByte(0, 15))
   catch tError
      stSectionFailed "BIP-32", tError
   end try
end stRunBip32

command stRunBip44
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tMaster, tNode
   stSection "BIP-44 / BIP-84 end to end"
   try
      -- The claim this section makes is the one that matters to a user: the
      -- same twelve words that restore a wallet anywhere else restore THIS one
      -- to the same addresses.
      put cxHdFromSeed(cxMnemonicToSeed(kBip39Mnemonic, "")) into tMaster
      stAssert "the test mnemonic's root xprv", cxXprv(tMaster) is kAbandonXprv
      put cxHdDerivePath(tMaster, kAbandonBip44) into tNode
      stAssert "m/44'/0'/0'/0/0 is the published P2PKH address", cxBtcAddressP2PKH(tNode["pubkey"]) is kAbandonP2pkh
      put cxHdDerivePath(tMaster, kAbandonBip84) into tNode
      stAssert "m/84'/0'/0'/0/0 is the BIP-84 vector", cxBtcAddressP2WPKH(tNode["pubkey"]) is kAbandonP2wpkh
      stAssert "the BIP-84 account xpub", cxXpub(cxHdDerivePath(tMaster, kAbandonBip84Account)) is kAbandonBip84Xpub
      put cxHdDerivePath(tMaster, kAbandonEthPath) into tNode
      stAssert "m/44'/60'/0'/0/0 is the published Ethereum address", cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) is kAbandonEth
   catch tError
      stSectionFailed "BIP-44", tError
   end try
end stRunBip44

command stRunTransactions
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tOutpoints, tSequences, tOutputs, tD0, tD1, tSig0, tDer0, tScriptSig0
   local tSig1, tDer1, tPub1, tWit1, tScriptSigs, tWitnesses, tRaw
   local tRecov, tRecid, tRHex, tSHex, tEth, tThrew, tErr2
   stSection "phase 5: transactions (BIP-143, EIP-155, EIP-1559)"
   try
      -- --- Bitcoin: the BIP-143 native-P2WPKH worked example, rebuilt whole.
      -- The pieces first, so a mismatch localizes.
      stAssert "input 0 outpoint serializes (txid reversed + LE vout)", \
            cxHexEncode(cxBtcOutpoint(kTxid0, 0)) is kTxOutpoint0
      stAssert "input 1 outpoint serializes", \
            cxHexEncode(cxBtcOutpoint(kTxid1, 1)) is kTxOutpoint1
      stAssert "output 0 serializes (LE amount + script)", \
            cxHexEncode(cxBtcOutput(112340000, kTxOutScript0)) is kTxOut0
      stAssert "output 1 serializes", \
            cxHexEncode(cxBtcOutput(223450000, kTxOutScript1)) is kTxOut1
      put kTxOutpoint0 & comma & kTxOutpoint1 into tOutpoints
      put "4294967278,4294967295" into tSequences
      put kTxOut0 & comma & kTxOut1 into tOutputs
      -- The two sighashes: input 0 legacy SIGHASH_ALL, input 1 BIP-143.
      put cxBtcSighashLegacy(1, tOutpoints, tSequences, 1, kTxScriptCode0, tOutputs, 17, 1) into tD0
      stAssert "input 0 legacy sighash matches", cxHexEncode(tD0) is kTxLegacySighash
      put cxBtcSighashSegwit(1, tOutpoints, tSequences, 2, kTxScriptCode1, 600000000, tOutputs, 17, 1) into tD1
      stAssert "input 1 BIP-143 sighash matches the BIP", cxHexEncode(tD1) is kTxSegwitSighash
      -- Sign each (RFC 6979, so deterministic), DER-encode, append SIGHASH_ALL.
      put cxSign(cxHexDecode(kTxSeckey0), tD0) into tSig0
      put cxDerEncode(tSig0) & numToByte(1) into tDer0
      put numToByte(the number of bytes of tDer0) & tDer0 into tScriptSig0
      stAssert "input 0 scriptSig (push + DER sig + hashtype)", \
            cxHexEncode(tScriptSig0) is kTxScriptSig0
      put cxSign(cxHexDecode(kTxSeckey1), tD1) into tSig1
      put cxDerEncode(tSig1) & numToByte(1) into tDer1
      put cxPublicKey(cxHexDecode(kTxSeckey1), true) into tPub1
      stAssert "input 1's pubkey is the BIP's compressed key", \
            cxHexEncode(tPub1) is kTxPubkey1
      put cxBtcWitness(cxHexEncode(tDer1) & comma & cxHexEncode(tPub1)) into tWit1
      stAssert "input 1 witness stack (count + sig + pubkey)", \
            cxHexEncode(tWit1) is kTxWitness1
      -- Assemble: input 0 has the scriptSig and no witness, input 1 the reverse.
      put cxHexEncode(tScriptSig0) & comma into tScriptSigs
      put comma & cxHexEncode(tWit1) into tWitnesses
      put cxBtcTxEncode(1, tOutpoints, tScriptSigs, tSequences, tWitnesses, tOutputs, 17) into tRaw
      stAssert "the whole signed transaction matches BIP-143 byte for byte", \
            cxHexEncode(tRaw) is kTxSignedRaw
      stAssert "the txid (non-witness serialization, reversed)", \
            cxBtcTxid(1, tOutpoints, tScriptSigs, tSequences, tOutputs, 17) is kTxTxid
      -- varint boundaries.
      stAssert "varint 252 is one byte", cxHexEncode(cxVarInt(252)) is "fc"
      stAssert "varint 253 is fd + LE u16", cxHexEncode(cxVarInt(253)) is "fdfd00"
      stAssert "varint 65536 is fe + LE u32", cxHexEncode(cxVarInt(65536)) is "fe00000100"

      -- --- Ethereum EIP-155 legacy: the specification's own example.
      stAssert "the EIP-155 signing hash matches the spec", \
            cxHexEncode(cxEthLegacySighash(9, kEthGasPrice, 21000, kEthTo, kEthValue, "", 1)) is kEthLegacySighash
      put cxSignRecoverable(cxHexDecode(kEthSeckey), cxHexDecode(kEthLegacySighash)) into tRecov
      put byteToNum(byte 65 of tRecov) into tRecid
      put cxHexEncode(byte 1 to 32 of tRecov) into tRHex
      put cxHexEncode(byte 33 to 64 of tRecov) into tSHex
      put cxEthLegacyEncode(9, kEthGasPrice, 21000, kEthTo, kEthValue, "", 1, tRecid, tRHex, tSHex) into tEth
      stAssert "the signed EIP-155 transaction matches the spec (v=37)", \
            tEth["raw"] is kEthLegacyRaw
      stAssert "the EIP-155 transaction hash", tEth["txhash"] is kEthLegacyTxhash

      -- --- Ethereum EIP-1559 typed (0x02): self-consistent, deterministic.
      stAssert "the EIP-1559 signing hash", \
            cxHexEncode(cxEth1559Sighash(1, 0, kEth1559MaxPrio, kEth1559MaxFee, 21000, kEthTo, kEth1559Value, "")) is kEth1559Sighash
      put cxSignRecoverable(cxHexDecode(kEthSeckey), cxHexDecode(kEth1559Sighash)) into tRecov
      put byteToNum(byte 65 of tRecov) into tRecid
      put cxHexEncode(byte 1 to 32 of tRecov) into tRHex
      put cxHexEncode(byte 33 to 64 of tRecov) into tSHex
      put cxEth1559Encode(1, 0, kEth1559MaxPrio, kEth1559MaxFee, 21000, kEthTo, kEth1559Value, "", tRecid, tRHex, tSHex) into tEth
      stAssert "the signed EIP-1559 transaction (0x02 envelope)", \
            tEth["raw"] is kEth1559Raw
      stAssert "the EIP-1559 transaction hash", tEth["txhash"] is kEth1559Txhash

      -- Fail closed: a compact signature must be exactly 64 bytes.
      stAssert "cxDerEncode refuses a short signature", \
            stThrows("cxDerEncode", byte 1 to 40 of tSig1)
      -- Fail closed: the BIP-143 sighash MUST commit to the outputs. An empty
      -- outputs list is refused - a preimage without hashOutputs would sign a
      -- payment to anywhere (the review's CRITICAL finding, guarded here).
      put false into tThrew
      try
         get cxBtcSighashSegwit(1, tOutpoints, tSequences, 2, kTxScriptCode1, 600000000, "", 17, 1)
      catch tErr2
         put true into tThrew
      end try
      stAssert "cxBtcSighashSegwit refuses an empty outputs list (hashOutputs is mandatory)", tThrew
      -- Fail closed: a witness list may not carry MORE entries than there are
      -- inputs (the extras would be silently dropped). A SHORT list cannot be
      -- rejected here - the engine ignores one trailing delimiter, so [wit, ""]
      -- and [wit] are the same string, and a missing trailing witness reads as
      -- an empty stack, which is its correct meaning. tWitnesses already has one
      -- entry per input; a third makes it over-long for this two-input tx.
      put false into tThrew
      try
         get cxBtcTxEncode(1, tOutpoints, tScriptSigs, tSequences, tWitnesses & comma & cxHexEncode(tWit1), tOutputs, 17)
      catch tErr2
         put true into tThrew
      end try
      stAssert "cxBtcTxEncode refuses a witness list longer than the input count", tThrew
   catch tError
      stSectionFailed "transactions", tError
   end try
end stRunTransactions

-- ==============================================================================
-- The fail-closed regression set. Read the note above its constants: each of
-- these is a case where the library used to give a WRONG ANSWER THAT LOOKED
-- RIGHT, which is the only failure mode that matters on a surface that moves
-- money. They are also the cases most likely to behave differently on a real
-- engine than in the headless interpreter, because three of them turn on `is`
-- and on `the caseSensitive`.
-- ==============================================================================

command stRunFailOpen
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tProgram, tDecoded, tKey
   stSection "fail-closed regressions"
   try
      -- EIP-55 verification must depend on the CALLER'S casing. If these come
      -- back true on the engine while they are false headlessly, the cause is
      -- `the caseSensitive` reaching a comparison it should not - look at
      -- cxCompareBytes first.
      stAssert "a correctly checksummed address still verifies", cxEthAddressIsChecksummed(kEip55A) is true
      stAssert "one corrupted letter is caught", cxEthAddressIsChecksummed(kEip55Corrupt) is false
      stAssert "a fully case-flipped address is caught", cxEthAddressIsChecksummed(kEip55Flipped) is false
      -- An in-band error sentinel over arbitrary bytes is always wrong.
      put cxHexDecode(kSegwitErrorProgram) into tProgram
      stAssert "an address whose program spells ERROR encodes", cxSegwitAddressEncode("bc", 1, tProgram) is kSegwitErrorAddress
      put cxSegwitAddressDecode("bc", kSegwitErrorAddress) into tDecoded
      stAssert "and decodes back to the same program", cxHexEncode(tDecoded["program"]) is kSegwitErrorProgram
      stAssert "at witness version 1", tDecoded["version"] is 1
      -- hash160 hashes anything, so an unchecked key gives a well-formed,
      -- checksummed, permanently unspendable address.
      stAssert "P2PKH refuses an empty key", stThrows("cxBtcAddressP2PKH", "")
      stAssert "P2PKH refuses a 20-byte hash", stThrows("cxBtcAddressP2PKH", stRepeatByte(0, 20))
      put numToByte(4) & stRepeatByte(0, 32) into tKey
      stAssert "P2PKH refuses 33 bytes tagged 0x04", stThrows("cxBtcAddressP2PKH", tKey)
      -- char (n) of a 32-character charset returns EMPTY past the end, so an
      -- out-of-range value used to emit nothing and shorten the string.
      stAssert "bech32 refuses a data value of 32", stThrows2("cxBech32EncodeValues", "bc", "0,32,1")
      stAssert "bech32 refuses a negative data value", stThrows2("cxBech32EncodeValues", "bc", "0,-1")
      -- An uppercase HRP used to produce a MIXED-case string, which BIP-173
      -- forbids and which this library's own decoder rejects.
      stAssert "an uppercase HRP is refused", stThrows2("cxBech32EncodeValues", "BC", "0")
   catch tError
      stSectionFailed "fail-closed regressions", tError
   end try
end stRunFailOpen
