# Getting started with CoinXT (from zero)

CoinXT gives an xTalk app Bitcoin and Ethereum primitives: hashes, the
secp256k1 curve, encodings and addresses, HD wallets from a BIP-39 mnemonic,
and transaction construction. This page is the from-zero path: install,
verify, run the demo, then the same path as code you can paste. Read the
honesty section before you build anything real on top; it is short and it is
the part that protects your users.

## What CoinXT is, and is not

CoinXT is a **calculator**. Every call is a pure, synchronous function: bytes
in, bytes out, nothing retained. That buys you determinism (everything is
testable against public vectors) and it draws the line you must not forget:

- **Custody is the app's job.** CoinXT holds a key only for the microseconds
  of one operation. Storage, backup, recovery phrases on paper, and
  confirm-before-sign screens are yours to build.
- **There is no network in CoinXT.** It does not fetch balances, estimate
  fees, or broadcast. Nonces, fee rates, gas parameters and prevouts are
  INPUTS your app must obtain from a node or service it trusts.
- **It is not hardware-wallet isolation.** An OXT script variable is not
  locked memory: it can be paged to disk, copied by the engine, and is not
  reliably zeroed. Clear key variables the moment you are done
  (`put empty into tSeed`) and understand that this narrows the window
  rather than closing it.

## Install and verify

1. Install the packaged **coinxt** extension (Tools > Extension Manager), the
   same way as any suite member. The native library resolves automatically.
2. Put the **script layer** in the message path. The hashes and curve live in
   the extension; the encoders, addresses, HD wallet and transaction builders
   are `src/coinxt.livecodescript`, a script:

   ```
   start using stack "coinxt"
   ```

3. Verify both layers from the message box:

   ```
   put cxKeccak256Len()                 -- extension loaded: prints 32
   put cxHexEncode(numToByte(0))        -- script layer loaded: prints 00
   ```

   A `handler not found` on the second line means step 2 was skipped; that is
   a setup problem, not a defect, and it is the first thing to check whenever
   "the hashes work but the addresses do not".

## Run the demo

`examples/coinxt-demo.livecodescript` walks the whole path on one
self-building card: paste it into a new stack's stack script (Object > Stack
Script), apply, then close and reopen the stack. It shows, in order: a
mnemonic (the public BIP-39 test mnemonic is prefilled; a Generate button
draws fresh entropy from SodiumXT when installed), the derived BIP-84 and
BIP-44 Bitcoin addresses and the Ethereum address, sign/verify on a message
digest, and then one Bitcoin (native P2WPKH) and one Ethereum (EIP-1559)
transaction, each shown **decoded as human intent** next to the raw bytes.
The default Bitcoin prevout is synthetic, so its signed transaction is
deliberately unbroadcastable.

## The same path as code

```
-- a typed mnemonic: VALIDATE FIRST. BIP-39 defines a seed for any string,
-- so a typo yields a perfectly good seed for the wrong wallet.
put cxMnemonicNormalize(field "mnemonic") into tMnemonic
if cxMnemonicValidate(tMnemonic) is not true then
   answer "That mnemonic fails its checksum; one word is wrong."
   exit to top
end if

-- mnemonic -> seed -> master node -> the standard first receive address
put cxMnemonicToSeed(tMnemonic, tPassphrase) into tSeed
put cxHdFromSeed(tSeed) into tMaster
put empty into tSeed                              -- key hygiene, every time
put cxHdDerivePath(tMaster, "m/84'/0'/0'/0/0") into tNode
put cxBtcAddressP2WPKH(tNode["pubkey"]) into tBtcAddress
put cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) into tEthAddress

-- sign a 32-byte digest the APP built and displayed to its human first
put cxSign(tNode["seckey"], tDigest) into tSig    -- RFC 6979, deterministic
put cxVerify(tNode["pubkey"], tDigest, tSig) into tOk
put empty into tMaster
put empty into tNode
```

Fresh keys come from the caller: compose SodiumXT
(`cxMnemonicFromEntropy(sxRandomBytes(16))`) or another entropy source you
trust; CoinXT deliberately has no ambient RNG for key material. For
transaction construction (`cxBtcSighashSegwit`, `cxBtcTxEncode`,
`cxEth1559Sighash`, `cxEth1559Encode` and friends), start from the demo's
build handlers and the transactions section of
[api-reference.md](api-reference.md); the demo is the worked example.

## The honesty section (build these rules into your app)

- **Never sign opaque bytes.** Decode and display exactly what a transaction
  does - destination, amount, fee (for Bitcoin the fee IS input minus
  outputs; nothing states it for you), chain id, nonce, gas - and get a human
  yes before `cxSign` runs. A blind signer is a footgun, and CoinXT will not
  save you from one: it signs the digest you hand it.
- **Wei-scale numbers cross as hex strings.** An Ethereum value above 2^53
  silently loses precision as an xTalk number - a wrong amount that looks
  right. That is why value and fee fields are minimal big-endian hex; keep
  them that way end to end.
- **Backups are words on paper.** The mnemonic is the wallet. If your app
  generates one, make the user record it offline before anything else, and
  never store it in a field, a file, or a preference in the clear.
- **Broadcastable is a claim about the outside world.** CoinXT's transaction
  families are independently accepted (python-bitcointx and eth-account, see
  the status block in api-reference.md), but a live testnet broadcast is
  still the one unclaimed bar. Test your app's transactions against a node
  you run before real value touches them.

## Where the depth lives

[api-reference.md](api-reference.md) documents every handler and its
contract; [SPEC.md](../SPEC.md) is the design; [CLAUDE.md](../CLAUDE.md) is
the as-built record and the hard-won lessons;
`tests/coin-selftest.livecodescript` is the 230-check engine harness, and the
gates listed in the README keep all of it honest on every push.
