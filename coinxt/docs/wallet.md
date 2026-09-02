# The CoinXT Wallet

`examples/coin-wallet.livecodescript` is a full Bitcoin wallet in one
paste-and-run stack, modelled on Electrum. It is the largest thing built on
CoinXT and it exists to answer one question: what does this library actually
make possible?

It is built out of `examples/wallet-core.livecodescript`, a pure calculator
layer that holds no state, touches no control, opens no socket, and reads no
file. That separation is the whole reason the wallet can be checked: the engine
is executable headlessly, so `tools/check-wallet-vectors.py` runs the SHIPPED
bytes of it against an independent implementation before anybody pastes it into
anything.

## Reading order

* [Two files, and why](#two-files-and-why)
* [What it does](#what-it-does)
* [The network, and the shape it was forced into](#the-network-and-the-shape-it-was-forced-into)
* [What is proven and what is not](#what-is-proven-and-what-is-not)
* [Custody, said plainly](#custody-said-plainly)
* [The engine API](#the-engine-api)
* [Running it](#running-it)

## Two files, and why

| File | What it is |
|---|---|
| `examples/wallet-core.livecodescript` | The engine. Prefix `cw`. Pure functions over CoinXT: scripts, addresses, extended keys, amounts, sizes, fees, coin selection, sighash dispatch, witness shapes, PSBT, signed messages, payment URIs, output descriptors, transaction decoding, JSON and QR. |
| `examples/coin-wallet.livecodescript` | The wallet. Prefix `wa`. Ten screens, the key custody, the wallet file, the network, and the window. Carries CoinXT, the engine above, and OnionXT, so it is one file to paste. |

The engine ships under `examples/` rather than `src/` for the reason
`enetxt/examples/enet-helpers.livecodescript` does: it is a library a demo
carries, not part of the extension's published surface. Everything in it is
composed from `cx*` calls and nothing is added to what CoinXT installs.

Three properties of the engine are deliberate and each one buys something.

**No state.** Not one script-level `local`. Every handler is a function of its
arguments, so there is nothing to initialise, nothing to tear down, no order of
calls to get wrong, and no way for one screen to leave another screen's answer
stale.

**No `item` and no `line` chunks.** Lists are arrays, keyed `1..n` with an `n`
count. `the itemDelimiter` and `the lineDelimiter` are global mutable state in
this engine family, and this member's own `CLAUDE.md` records nine handlers
that a hostile delimiter turned into wrong ANSWERS rather than errors: a valid
seed phrase reported invalid, an address built from the wrong bytes. CoinXT
answered that with a save/set/use/restore wrapper around every affected handler.
Not reading those chunks at all is the stronger answer, and it was available
here only because this layer was written after the lesson instead of before it.

**No UI and no I/O.** That is what lets the vector gate run it.

## What it does

**Wallet kinds.** A new seed (24 words, entropy from SodiumXT and no fallback),
a restored seed with an optional BIP-39 passphrase, watch-only from an account
`xpub`/`ypub`/`zpub`/`tpub`/`upub`/`vpub`, a single imported WIF key, or an
m-of-n P2WSH multisig from cosigner account keys.

**The seed this wallet starts with is PUBLIC.** It opens holding BIP-39's
published test mnemonic so every screen has something true to show without you
inventing a seed first. Those twelve words are printed in the specification, so
anyone can derive the same private keys and spend anything sent to them. Mainnet
is not blocked - that is deliberate - but the wallet says so on the Wallet
screen, at the top of Receive above the address itself, and on Send. Generate or
restore a seed of your own before you accept a single real coin.

**Networks.** mainnet, testnet, signet and regtest, each with its own base58
version bytes, bech32 HRP and extended-key versions. A network change drops the
address and balance state rather than showing addresses from one chain beside
balances from another.

**Script types.** Legacy P2PKH (BIP-44), nested SegWit P2SH-P2WPKH (BIP-49),
native SegWit P2WPKH (BIP-84), Taproot P2TR key-path (BIP-86), and P2WSH
multisig (BIP-48, with BIP-67 key ordering so every cosigner independently
derives the same address).

**Receive.** The next unused address, a BIP-21 URI carrying an optional amount,
label and message, and a scannable QR code of that URI. The QR is byte mode at
error level M, versions 1 to 15, rendered as an uncompressed BMP into an image
control.

**Addresses.** Both chains to a gap-limit window, with per-address labels, use,
balance, and an explicit "derive twenty more" that says what going past the gap
limit costs.

**Send.** One payment or many, amounts in BTC, mBTC or satoshi, `MAX`, a fee
rate in sat/vB with a plain-language description of what that rate means, four
coin-selection strategies plus manual coin control, opt-in RBF, a locktime, and
a review panel that shows every output in full, the fee, the change address and
which coins are being spent, before anything is signed. It can also stop at an
unsigned PSBT.

**Coins.** The UTXO set with freeze and thaw, ticking for manual selection, and
a hand-entry path so an offline wallet can be told what it owns.

**History.** Transactions with confirmations, amounts and fees, a full decode of
any of them (Inspect asks the backend for the raw bytes it does not hold and
paints the decode when they arrive), and a BIP-125 fee bump that BUILDS the
replacement: same inputs,
same payments, the extra fee out of the change, signed and printed line by line
and not broadcast. It can do that for a spend this window signed, because
signing records what the spend was made of - an input's value is committed to by
BIP-143 and is not carried in the raw transaction. For a transaction made in an
earlier session it prints the arithmetic and says plainly why it cannot build
one.

**Tools.** Sign and verify a message in the 2011 Bitcoin format, load, sign,
combine and finalize a PSBT, inspect anything you paste (a raw transaction, a
PSBT, an extended key, a WIF, an address or a URI), decode a bare script from
hex, validate an address or an extended key on EVERY chain rather than only this
one, convert entropy to a mnemonic and a mnemonic back to entropy (with the
master fingerprint with and without a BIP-39 passphrase), mint a single key,
derive at an arbitrary path, sweep a private key, and export descriptors and
account keys.

**A right-click anywhere** opens a menu for the screen you are on. Every item on
it routes to the same handler the screen's own buttons route to, so an item can
only ever mean what a button means. `popup` and `menuPick` are documented
LiveCode, but no stack in this suite has opened a menu on a real engine yet: if
the engine declines, the right-click does nothing and the wallet is otherwise
exactly as it was.

**Settings.** The wallet file and its password, the display unit, the gap limit,
and the honesty record.

## The network, and the shape it was forced into

There are four transports and the differences between them are real.

| Transport | How | What it costs you |
|---|---|---|
| Esplora over Tor | A `.onion` mirror over plain HTTP through OnionXT's SOCKS client | The server learns which addresses are asked about together. Nobody else learns anything. |
| Electrum over Tor | A `.onion` server, JSON-RPC over the same circuit | The same, except the server is asked about SCRIPT HASHES rather than addresses. |
| Esplora over clearnet | The engine's own `load URL` | The server learns your addresses AND your IP; on `http://` so does everyone in between. |
| Offline | Nothing | Nothing. Everything except Broadcast still works. |

**HTTPS over Tor is not on that list because it cannot be.** An already-open
socket cannot be upgraded to TLS in this engine, and `open secure socket` talks
TLS directly to a host, so it cannot perform a SOCKS handshake first. A `.onion`
endpoint over plain HTTP is the correct shape here, not a compromise: the
circuit is the encryption and the authentication.

**Which chain a backend carries is not a detail.** Esplora serves each chain
under its own root - `/api` for mainnet, `/testnet/api`, `/signet/api` - and the
wallet builds that root from the network it is on. It did not always: every
request went to the mainnet index, so a funded testnet address reported no
coins, which is the wrong-but-plausible answer this member exists to refuse. The
two failure modes are not equally visible, which is why there is now a guard as
well as a fix. Esplora answers an address off its chain with a 400, and only the
Tor transports read an HTTP status - `load URL` hands the callback a body and no
code. An Electrum server is worse: asked about a script hash from another chain
it answers with an empty list, a well-formed "this address has never been used",
so a testnet wallet on a mainnet server reports itself synced, green and empty.
The wallet now refuses a backend that does not carry the selected chain, before
it builds a request, and says which host to change. Regtest has no public
backend at all, so it is refused against every built-in host and needs your own.

The clearnet option is offered with what it costs written on the screen rather
than assumed away. This suite has never measured what the engine does about TLS
certificates (`docs/OXT-ENGINE-NOTES.md` 6.8), so `https://` here carries no
claim about verification.

`socketError`, `socketClosed` and `socketTimeout` are the engine's names and a
script may define each exactly once. The wallet carries OnionXT, so the wallet
defines all three and hands each event to OnionXT's named function first, then
passes. `tools/sync-demo-embeds.py`'s `DROP_HANDLERS`, keyed by (app, provider)
pair, drops OnionXT's own wrappers from the embed and asserts that both halves
of that arrangement are present.

## What is proven and what is not

There are three layers here and each has its own answer, so they are separated
rather than averaged.

**The engine layer is RUN.** `tools/check-wallet-vectors.py` drives the shipped
`wallet-core.livecodescript` through `tools/lcs-interp.py` against
`tools/wallet_reference.py`, an independent implementation anchored at import to
the published BIP vectors, with the real native CoinXT library supplying every
hash and every signature. Among its checks: the BIP-44, BIP-49, BIP-84 and
BIP-86 first receive addresses for the public test mnemonic; BIP-49's and
BIP-84's own account `ypub` and `zpub`; every address in both directions on two
networks; Bitcoin Core's two published descriptor checksums; the classic 226 and
141 virtual sizes; the 546/540/330/294 dust thresholds derived from Core's own
branch; and complete signed transactions on all five spend paths,
byte-identical to the independent implementation's. Run it for the count; a
number written here would be true on the day it was typed and quietly wrong
afterwards.

**And it is run TWICE, under two comparison rules.** `the caseSensitive`
defaults to FALSE on OXT, which makes `is` and `offset()` case-INSENSITIVE;
`lcs-interp.py` models both case-SENSITIVELY and says so. So the whole vector
set runs a second time with those two folded to the engine's rule, and the same
answers are required. That tier is not decoration: it is there because the
first version of this layer had **two real defects of exactly that shape** - a
descriptor checksum that came out wrong for every descriptor containing a
letter (Core's input alphabet carries `abcdefgh` at position 18 and `ABCDEFGH`
at 82, so a folded `offset()` returns the wrong twin), and a multisig account
key serialized with the single-signature `zpub` version because the stems `"z"`
and `"Z"` were told apart with `is`. Both were green under 414 checks, because
every one of those checks ran under the rule the engine does not use.

**The stack layer is BOOTED.** `tools/check-wallet-boot.py` opens the shipped
`coin-wallet.livecodescript` headlessly - `preOpenStack`, `openStack`, the
queued self-check tick - over riptide's engine object model (imported, not
copied) with the COMMITTED `coinxt.so` underneath, and then drives it: every
navigation button through the real click router, the show/hide sweep checked
control by control across all ten screens, a real spend built and signed and
decoded by the oracle, the same spend exported as a PSBT and round-tripped
through the Tools screen, a message signed and verified (and refused for a
case-mangled Base58 address), a fee bump built and decoded by the oracle and
checked against BIP-125 rules 1 to 4, every item of every screen's context menu
walked through the router, and the wallet file sealed, re-opened, and refused
after one flipped bit. SodiumXT is modelled there and each model is
declared in the gate; OnionXT answers its version probe and nothing else,
because a gate that dialled a real onion would be a gate that fails when the
network does.

CoinXT itself has had two on-engine passes (2026-08-10 and 2026-08-12), so the
cryptography under all of that is engine-observed.

**Not proven.** None of this is an OXT pass. What the two gates settle is that
the code RUNS and what it computes; an interpreter is an approximation of the
engine and never the engine, and where they disagree the engine is right.

**THE FIRST ENGINE RUN OF THE WALLET ARRIVED 2026-09-01**, as a pasted log
rather than a harness report, and it settled two things the gates could not.
The Electrum-over-clearnet transport spoke to a real server
(electrum.blockstream.info:50001, mainnet, the demonstration wallet): every
request from `headers.subscribe` through 40 addresses of `listunspent` and
`get_history` was answered on one persistent socket, each reply correlated by
id, a 16 KB history included. That flipped the label on one of the four
transports. **The next day (2026-09-02) the person running it reported creating
a testnet wallet and RECEIVING coins at it over both clearnet transports**, which
flips Esplora-over-clearnet as well - a receive is a sync that found the coin -
and is the first coin this wallet has ever held on any chain. The two Tor
transports have still not spoken to a backend from here. The same run is why a
fresh sync is now forty-two requests rather than eighty-two: history is asked of
every address, and unspent outputs only of the addresses whose history says
there are any. And the same log carried twenty-seven identical
"does not pass its BIP-39 checksum" lines, which is the defect record in
`coinxt/CLAUDE.md` for that date: a failed Open committed the bad phrase as
wallet state and every later click re-validated it. Fixed the same day, with
the specific reason on screen (which word, how many words, or that the phrase
is an Electrum seed - which the wallet now opens).
Everything in `docs/OXT-ENGINE-NOTES.md` that the interpreter models
differently is invisible to both, the case rule above excepted. A green boot
here does not mean a window appeared. The three network transports have never
spoken to a real backend from here until 2026-09-01, when Electrum over
clearnet did, and 2026-09-02, when a testnet receive over both clearnet
transports was reported (above). Later on 2026-09-02 a second pasted log
closed two more: **Esplora over Tor** dialled the onion mirror through
OnionXT's SOCKS client on a real engine and answered every request kind (tip,
fees, history, unspent outputs) over 147 circuits, and **the wallet's first
broadcast** went out over that transport - a 226 vB legacy spend, txid
`7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, accepted by the mirror and seen spent by
the sync that followed. Electrum over Tor is the one transport that has still
not spoken to a backend from here. Until that log, no transaction this wallet built had been broadcast to any
network, so "this would confirm" is a claim nobody has tested.

## Custody, said plainly

OXT script variables are not locked memory. A seed typed into this stack can be
paged to disk by the operating system, and any process that can read this one's
memory can read the key. That is the machine's trust boundary, not this file's,
and nothing in it moves that boundary.

Use it on testnet, or with an amount you would be relaxed about losing, or as
the watch-only half of a setup whose keys live somewhere colder. The wallet file
is sealed with XChaCha20-Poly1305 under an Argon2id key when SodiumXT is
installed; without SodiumXT it is written in the clear and says so, because a
password field that does nothing is worse than no password field at all.

## The engine API

`wallet-core.livecodescript` is a library like any other in this suite: it can
be `start using`-ed, or embedded, and its public handlers all carry the `cw`
prefix (`tools/check-cross-library-names.py` holds that, and holds every one of
its names disjoint from every other library in the suite). The groups are:

| Group | Handlers |
|---|---|
| Networks | `cwNetworks`, `cwNetHrp`, `cwNetP2pkhVersion`, `cwNetP2shVersion`, `cwNetWifVersion`, `cwNetCoinType`, `cwXKeyVersion` |
| Script types | `cwScriptTypes`, `cwTypePurpose`, `cwTypeStem` |
| Scripts | `cwPush`, `cwScriptP2pkh`, `cwScriptP2sh`, `cwScriptP2wpkh`, `cwScriptP2wsh`, `cwScriptP2tr`, `cwRedeemP2shP2wpkh`, `cwScriptP2shP2wpkh`, `cwMultisigScript`, `cwScriptKind`, `cwScriptAsm` |
| Addresses | `cwAddressForScript`, `cwScriptForAddress`, `cwAddressKind`, `cwAddressIsValid`, `cwAddressProblem`, `cwElectrumScripthash` |
| Derivation | `cwParsePath`, `cwFormatPath`, `cwAccountPath`, `cwFingerprint`, `cwXKeyEncode`, `cwXKeyDecode`, `cwXKeyIsPrivate`, `cwXKeyRespell`, `cwAccountXKey`, `cwChainNode`, `cwAddressAt`, `cwMultisigAddressAt` |
| Amounts | `cwSatToBtc`, `cwBtcToSat`, `cwFormatAmount`, `cwParseAmount` |
| Size and fees | `cwVarIntLen`, `cwInputBaseBytes`, `cwInputWitnessBytes`, `cwOutputBytes`, `cwEstimateVsize`, `cwSimpleInputs`, `cwFeeFor`, `cwDustThreshold`, `cwRbfMinFee`, `cwFeeRateLabel` |
| Coin selection | `cwSelectCoins` |
| Transactions | `cwTxInput`, `cwTxOutput`, `cwOutpointsHex`, `cwSequencesList`, `cwOutputsHex`, `cwSighash`, `cwSignInput`, `cwSignTaproot`, `cwSignMultisig`, `cwMultisigKeys`, `cwWitnessBytes`, `cwCompressPubkey`, `cwTxSerialize`, `cwTxid`, `cwTxDecode` |
| PSBT | `cwPsbtCreate`, `cwPsbtParse`, `cwPsbtEmit`, `cwPsbtSign`, `cwPsbtFinalize`, `cwPsbtCombine`, `cwPsbtSummary`, `cwPsbtFind`, `cwPsbtFindAll`, `cwPsbtInputAmount`, `cwPsbtInputScript`, `cwPsbtInputType`, `cwPathBytes`, `cwPathFromBytes`, `cwPsbtUnsignedTx` |
| Messages | `cwMsgDigest`, `cwMsgSign`, `cwMsgVerify` |
| URIs | `cwUriParse`, `cwUriBuild`, `cwPercentEncode`, `cwPercentDecode` |
| Descriptors | `cwDescriptorChecksum`, `cwDescriptor`, `cwDescriptorMultisig` |
| JSON | `cwJsonParse`, `cwJsonType`, `cwJsonCount`, `cwJsonAt`, `cwJsonMember`, `cwJsonKeys`, `cwJsonText`, `cwJsonPath`, `cwJsonGet`, `cwJsonEscape`, `cwJsonString2` |
| QR | `cwQrVersionFor`, `cwQrCodewords`, `cwQrMatrix`, `cwQrText`, `cwQrBmp` |
| Lists and bytes | `cwCharIndex`, `cwSameBytes`, `cwListNew`, `cwListAdd`, `cwListCount`, `cwLeBytes`, `cwBeBytes`, `cwLeRead`, `cwBeRead`, `cwReverseBytes`, `cwHexIsClean`, `cwHexCompare`, `cwSortHexList`, `cwLower`, `cwUpper`, `cwTrim`, `cwB64Encode`, `cwB64Decode`, `cwStripWhitespace`, `cwVarIntHex`, `cwHexListHas`, `cwSigsList`, `cwWifInfo`, `cwMnemonicStrength`, `cwMnemonicWordCount`, `cwVersion` |

Errors are thrown strings beginning `wallet-core: `, matching CoinXT's own
convention. Two handlers answer a question instead of throwing, for the same
reason `cxMnemonicValidate` does: `cwAddressIsValid` and `cwHexIsClean` are
asked on every keystroke of a form, and a validator that raises cannot say no.

**`cwCharIndex` and `cwSameBytes` exist for one reason and it is worth knowing
before you reach for `offset()` or `is`.** Both of those honour `the
caseSensitive`, which defaults to FALSE, so both fold case - and Base58,
Bitcoin Core's descriptor alphabet and WIF are all case-SIGNIFICANT. Anywhere
this layer looks a character up in an alphabet whose two cases sit at different
positions, or binds a signature to a particular address string, it uses these
instead. CoinXT's own header calls that the single most dangerous line in its
file; this layer had to learn it a second time, and
`tools/check-wallet-vectors.py` now re-runs every vector under the engine's
rule so it cannot be forgotten a third.

## Running it

Paste `examples/coin-wallet.livecodescript` into a stack script and open the
stack. Nothing else is needed: the CoinXT script layer, the wallet engine and
OnionXT are embedded in the file.

The packaged extensions do the rest:

* **coinxt** (`org.openxtalk.library.coin`) is REQUIRED. Without it the wallet
  cannot derive, sign, or even check an address, and every screen says so.
* **sodiumxt** (`org.openxtalk.library.sodium`) is optional. Without it,
  Generate is disabled (there is no entropy source here fit to make a key from,
  and there is deliberately no fallback) and the wallet file cannot be
  encrypted.
* **a tor daemon** is optional, and only the two Tor transports want it.

The wallet opens on testnet with BIP-39's public test mnemonic already in the
seed box, so every screen has something true to show before you type anything.
That phrase's funds are burned by design. Do not type one that guards real coins
into this stack.

Run the vector gate with:

```sh
cd coinxt && python3 tools/check-wallet-vectors.py
```

It builds the native shim from `native/coinxt.c`, so it needs a C compiler; with
none, it runs the constant checks and says loudly that it skipped the rest.
