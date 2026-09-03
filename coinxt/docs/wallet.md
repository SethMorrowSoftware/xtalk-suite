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

**Ordinals** (a screen of its own since 2026-09-04). A content type with three
quick picks, a body, a line that prices the reveal as you type, and two
numbered buttons: 1 prepares the commit address (and saves the recipe with
the wallet), 2 signs the reveal once that address holds a coin. A table lists
every inscription this wallet prepared with its state - unfunded, funded
(press 2), revealed - and a box on the right reads any transaction's
inscription or runestone. Every control carries a tooltip.

**Vault** (the same day). A block height, or +1 day / week / month / year
from the tip, a line saying how far away that is, and Prepare, which makes
the CLTV address and saves its recipe. A table lists every vault address
with its state read from the tip - locked with the blocks to go, or
UNLOCKED - and what it holds. Locked coins are left out of every spend;
unlocked ones are spent from Send with the locktime raised automatically.

**Send.** One payment or many, amounts in BTC, mBTC or satoshi, `MAX`, a fee
rate in sat/vB with a plain-language description of what that rate means, four
coin-selection strategies plus manual coin control, opt-in RBF, a locktime, and
a review panel that shows every output in full, the fee, the change address and
which coins are being spent, before anything is signed. It can also stop at an
unsigned PSBT. Since 2026-09-04 a line reading `note: some text` (or
`data: hex`) adds one OP_RETURN output of value 0 carrying those bytes - a note
to the chain - sized, selected for, reviewed, signed and fee-bumped like any
other output; one per transaction, because a second is what most nodes refuse
to relay, and anything over eighty bytes is warned about for the same reason.
Inspect reads such outputs back as text, and reads an Ordinals inscription
(content type, size, body) out of any witness that carries one. A BIP-352
silent payment address (`sp1...`, `tsp1...`) goes on a line like any other
since the same day; its taproot output is derived from the coins chosen to
fund it, so it is signed here, never as a PSBT (the section below).

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
the sync that followed. Electrum over Tor was the one transport that had still
not spoken to a backend from here, and the 2026-09-02 log said why: the
built-in address was `explorernuoc63nb.onion`, a sixteen-character VERSION-2
onion that the Tor network stopped resolving in 2021, and the daemon answered
every dial of it with "general SOCKS server failure" - the same words a failed
circuit gets, so the wallet retried it once, as designed, and failed again.
The constant is Blockstream's version-3 onion now (the same address the
Esplora mirror uses, with the chain selected by port: 110 mainnet, 143 testnet),
the wallet refuses a v2 shape by name before it dials, and **on 2026-09-03 the
transport ran** - the sixth engine log: port 143 on testnet, a full sync of the
test seed (tip, fees, forty histories, unspent outputs), a second wallet
synced, and a broadcast, txid
`9bab6640f2bbe01f96a95ffdeca3e96881f1819e677348562ef8bf87da6b719a`, seen spent
by the sync that followed. Mainnet on port 110 is still the operator's
published table and nothing more. That log also dialled a fresh Tor stream for
every one of its 173 requests, so the stream is now kept open for the whole
sync the way the clearnet socket is - and the seventh log, later the same day,
ran two full syncs down one stream each, with a header the server pushed on
the idle stream between them logged and ignored. Esplora over Tor opened
a stream per request in that log, by design (HTTP/1.0 with Connection: close,
so there was no chunked-transfer decoder to get wrong); later the same day it
was moved to HTTP/1.1 keep-alive with a reply decoder (Content-Length,
chunked, Connection: close, and a fallback to close-delimited reading for a
reply with no framing), so both Tor transports run a sync down one stream -
**seen in the eighth log**, later the same day: a whole Esplora sync of
fifty-one requests down one Tor stream on HTTP/1.1. The same log saw both of
Blockstream's Electrum servers, onion and clearnet, take JSON-RPC BATCHES: an
Electrum sync sends its histories, and then its unspent-output requests, as
arrays of requests in one line, and a sync of fifty-one requests was five
round trips. A server that refuses a batch is asked with half as many on the
next line, and half again on the next refusal, down to one at a time (since
2026-09-03, after an onion server closed the connection on a batch of 22 and
the sync fell to 41 single Tor round trips); a member's own error counts as
that member's failure only, and a member
the server leaves unanswered is asked again alone. After that log the tip and
the fee estimate ride in the first batch too (three round trips for a fresh
sync), which has not run on an engine; nor has the same day's other trimming
(a tip under thirty seconds old and a fee estimate under ten minutes old are
not asked for again, which every sync in that log defeated by changing the
backend first; the screen is repainted once a second during a sync rather
than on every reply; the next request leaves the moment a reply lands rather
than on the next 250 ms tick).
Until the 2026-09-02 log, no transaction this wallet built had been broadcast to any
network, so "this would confirm" is a claim nobody has tested.

## Updating from main

Since 2026-09-04 the Settings screen has an **Update from main** button, and
every right-click menu ends with the same item. It fetches this file - the
raw text of `coinxt/examples/coin-wallet.livecodescript` at the tip of the
repository's `main` branch, one `get URL` of a fixed address - reads it, and
offers it: the version it declares, its size and its SHA-256 next to the
running version. Nothing replaces the script until Update is pressed. The
reading refuses, with the reason, anything that does not begin the way this
script begins, is too short to be a whole wallet or too long to be this one,
declares no version, or lacks the handler that brings the wallet back after
the swap; and it refuses a copy identical to the running script as already
current.

On Update the wallet as the wallet file would hold it, plus the Network
settings and the screen, is parked in a stack property; the network is
stopped; the stack's script is replaced; and `preOpenStack` and `openStack`
are sent to the new script, whose boot reads the carry back, clears it, and
says what version it came from. The log stays, because the log is a field
and fields are not rebuilt. A script that does not compile on the engine
leaves everything as it was and says so. The carry is cleared on close as
well, so a swap that never came back cannot leave a seed on a saved stack.

**What that trusts, said plainly.** Whoever can write to `main` can put code
in front of your keys, and so can anyone who can answer for
`raw.githubusercontent.com` if the engine's TLS is not doing its job (this
suite has not measured that; see the engine notes). The version and the
SHA-256 in the offer are there so a person can compare them with the commit
they expect before pressing Update. Everything around the swap - the check,
the carry, the restore, the button and the menu route - is gated headlessly;
the swap itself (`set the script of this stack` from inside one of that
script's own handlers) is engine work and has not run on an engine.

## Signed messages, in both formats

The Tools screen signs in the 2011 format (the header that names the key's
shape, the one Electrum and every explorer read) for legacy, nested and
native SegWit addresses, and since 2026-09-04 in **BIP-322** as well: always
for taproot, which the 2011 format cannot express, and for native SegWit
when the box beside Verify is ticked. BIP-322 proves an address by SPENDING
it - a virtual transaction pays the message's tagged hash to the address, a
second one spends that output to OP_RETURN, and the signature is the second
one's witness, base64 - so a verifier checks it the way a node would. Verify
reads the format off the signature (the 2011 form is exactly 65 bytes; a
witness stack never is). The vector gate holds the BIP's published message
hashes, to_spend txids and signatures for its test key, and both shapes
against the reference byte for byte. Not run on an engine.

## Child pays for parent

The History screen's Bump button replaces a transaction when it can (BIP-125,
for a spend this wallet built with the opt-in and some change). Since
2026-09-04 it does the other thing when it cannot: for a transaction this
wallet did not build - a stuck incoming payment, typically - or one built
without the opt-in or without change, if this wallet holds an unconfirmed
output of it, Bump builds a CHILD that spends that output back to the
wallet's next change address at a fee covering the parent's bytes as well as
its own at the Send screen's rate. A miner takes the pair as a package. The
parent's size comes from its bytes (fetched like Inspect fetches them, or
from the weight Esplora reports); its fee is known only where the backend
says it, and when it is not the child pays for both sizes in full and says
so. The child signals RBF so a rate that proves too low can be raised. Not
run on an engine.

For a transaction this wallet built itself, the size and the fee come from
the spend record and no bytes are asked for: the 2026-09-03 engine run
pressed Bump on the wallet's own note transaction and was told to press it
again when the server's copy arrived. Not run on an engine since.

## What the wallet remembers about a broadcast

A transaction this wallet hands to the network is its own word about its
coins, and since 2026-09-03 it acts on it from the moment the broadcast is
QUEUED, before the next sync and before any server answers. The inputs the
transaction spends are marked (the Coins screen shows them as `SPT`), and a
marked coin is not offered to the selector, not offered to a
child-pays-for-parent bump, and not counted in the balance. Every output
that comes back to this wallet - the change, usually - is listed as a coin
at 0 confirmations and counted as pending, so a second spend a moment later
has the change to draw on and reuses nothing. A broadcast the backend
refuses for good (after its one retry) hands the coins back and drops the
outputs it had added, with a log line saying so. The reason is two engine
runs on 2026-09-03: in the first, a silent payment and, a minute later, the
funding of an inscription commit spent the same input, because the coin
list was still the last sync's; in the second, with marks made only on
acceptance, both were built on a change output while the fee bump that
voided it was still queued behind Tor, and both were refused by every node.

For the same reason, Bump refuses to replace a transaction whose output a
queued or broadcast spend of this wallet already uses: the replacement makes
different outputs, so that child would spend a coin that never exists. The
refusal names the child and says to bump that one instead, or wait for the
parent to confirm.

The memory is subordinate to the backend. The next sync of an address
replaces the coins at that address with what the backend lists, and a coin
the backend still lists as unspent loses its mark and is offered again,
with a log line naming the transaction that was supposed to have spent it.
And a refused broadcast quotes the backend's REASON: the Tor Esplora reader
holds a non-2xx status line until the body has arrived, so the log says
"400 Bad Request: bad-txns-inputs-missingorspent" rather than the status
line and two headers, which is all the 2026-09-03 evening log had to offer.
A replacement (an RBF bump) re-marks the inputs with its own txid and drops
the coins that had been added from the transaction it replaced. Nothing is
saved: the marks live for the session, like the spend records. Not run on
an engine.

## Silent payments, the sending side

Since 2026-09-04 the Pay-to box takes a **BIP-352 silent payment address**
(`sp1...` on mainnet, `tsp1...` on the test networks) on a line like any
other. Such an address is two public keys, not a script: the output that
actually receives the coins is a taproot output derived from the private
keys of the coins that fund the transaction and its smallest outpoint, so
paying the same address twice lands on two unrelated outputs and only the
payee's scan key can find either. That shape decides what the wallet does.
The parser keeps the two keys and gives the line a taproot kind, which is
all the sizer and the dust rule need; coin selection runs as usual; and
only then, with the inputs known, is the output derived (a taproot input's
key is the tweaked one, negated to even y as the BIP says) and its script
written into the payment. The review names the derived address, and Inspect
shows a plain taproot output, because that is all the chain ever sees. It is
refused where it cannot be honest: as a PSBT and from a watch-only wallet
(there is no script to hand a signer, only a derivation only the key holder
can repeat), and from a multisig wallet, whose P2WSH inputs take no part in
the BIP at all. The Tools inspector explains one instead of showing a
scriptPubKey it does not have.

The derivation is wallet-core's, staged so the vector gate can hold each
step to the BIP's published sending vectors (`tests/bip352-sending-vectors.json`,
the published file's sending half): the address decode under the BIP's own
1023-character waiver on bech32m, the input key sum done in hex mod n (the
native tweak-add refuses a zero intermediate, and one of the BIP's vectors
is exactly that), the input hash over the smallest outpoint, the shared
secret, and the outputs with their per-scan-key counter, including the
three refusals - no eligible input, a zero key sum, and more than 2323
outputs to one scan key. Which inputs take part is the receiver's rule, and
the oracle implements that side of it too, checked against the vectors'
own input lists. Receiving - scanning the chain for payments to a scan key
of this wallet's own - is not built, and the reason is a library gap rather
than a design choice: the receiver sums the INPUT PUBLIC KEYS of every
transaction it scans, which is point addition, and coinxt exposes scalar
multiplication (ECDH), scalar tweaks and point compression but no
point-plus-point. That is one native handler away (a `cxPubkeyCombine`
over secp256k1_ec_pubkey_combine, with binaries refreshed on every
platform), and until it lands the wallet says so wherever it mentions the
feature. Not run on an engine.

## Runes, read only

Since 2026-09-04 Inspect reads a **runestone** - the Runes protocol's
OP_RETURN OP_13 output - and prints what it says under the output: the
etching with its name (spacers as dots, since the source cannot carry the
bullet), symbol, divisibility, premine and open-mint terms; the mint; the
pointer; every edict as rune id, amount and destination output; and the
CENOTAPH verdict with its flaws, because a malformed runestone burns the
runes it touches and a reader that stayed quiet about that would be lying by
omission. The numbers are 128-bit, so wallet-core keeps them as decimal
strings and never lets one near a double: LEB128 decoding, the delta-encoded
edict ids, the modified-base-26 name and the amount display are all digit
loops. Read only is the whole of it - no etching, no minting, no balances,
which need an indexer that has seen every block since the protocol began.
The vector gate holds the reader to the reference implementation's own test
cases (names from `A` to the 2^128 - 1 edge, the spacer and divisibility
tables, the all-tags etching, the specification's delta-encoding example,
and each cenotaph rule by name). Not run on an engine.

## Inscriptions, by commit and reveal

Since 2026-09-04 the Tools screen inscribes. The protocol has two steps and
so does the button: with `inscribe: text/plain; hello` (or `inscribehex:
<type>; <hex>`) in the paste box, Inscribe prepares the **commit** - a
taproot output whose single hidden leaf is the ord envelope
(`<key> OP_CHECKSIG OP_FALSE OP_IF "ord" <type> <body> OP_ENDIF`) keyed by
the next unused receive key; the commit address joins the wallet's own
address list so sync watches it, the recipe is saved with the wallet so a
reopen rebuilds it, and the report says how much to fund it with. Once the
coin is seen, Inscribe with the box empty signs the **reveal**: one input
spent through the leaf (the witness is the Schnorr signature by the internal
key, the leaf script and the control block), one output to the next receive
address, which receives the first sat and with it the inscription - and
that output is frozen on the Coins screen from the moment the reveal is
signed, so no ordinary spend can hand the inscribed sat to a miner as fee
or to a payee who never asked; unfreeze it when you mean to move the
inscription. Inspect on the reveal reads the envelope back out of its
witness, which is the loop this wallet could already close from the other
end. The pieces are
wallet-core's: a leaf hash with a real compact size (coinxt's stops at 252
bytes, and an inscription body is exactly the script that exceeds it), the
envelope in pushes of at most 520 bytes, the commit (tweak by the leaf,
control block, script), the script-path sighash and the witness. The vector
gate holds each to the oracle, the boot gate drives both presses and
rebuilds the reveal's signature from the same key byte for byte. A commit
coin spent any other way is still spendable - waSignSpend signs any coin of
this wallet through its leaf - but the reveal builder is the intended path,
and a silent payment funded from one tweaks by the leaf as BIP-352 requires.
Not run on an engine.

## Coins locked until a block

The same one-leaf machinery, turned the other way, is a vault. Since
2026-09-04 `lock: <height>` in the Tools paste box and the Lock button
prepare an address whose only leaf is `<height> OP_CHECKLOCKTIMEVERIFY
OP_DROP <receive key> OP_CHECKSIG` under the NUMS point as internal key -
so there is no key-path spend to go around it, and whatever is paid there
cannot move before that block, not by this wallet and not by anyone holding
its seed, because consensus refuses the only script that releases it. The
address joins the wallet's list and the recipe is saved with the wallet,
like an inscription commit. The Coins screen marks such a coin `LCK`; while
the tip is below the height it is withheld from selection (a transaction
every node would reject is not a spend), and from the height on the Send
screen spends it like any other coin: it raises the locktime itself, says
so in the review, and signs through the leaf. The boot gate drives the
button, plants a coin, checks the withholding on both sides of the height,
and rebuilds the release's signature from the same key. Not run on an
engine.

## Lightning invoices, read out

Since 2026-09-04 Inspect and Validate read a **BOLT11 Lightning invoice**
and say what it asks before anyone pays it somewhere else: the network, the
amount (the invoice's unit is bitcoin with a multiplier letter; the wallet
prints millisatoshi and the whole-satoshi part in its own unit), the payee's
node key recovered from the signature, the description or its hash, the
payment hash, when it was issued and when it expires, the final CLTV, the
on-chain fallback address if it carries one (which this wallet CAN pay),
route hints hop by hop, feature bits and payment metadata. It refuses what
the specification calls invalid, naming the reason: a bad checksum or
mixed case, a bad amount or multiplier, sub-millisatoshi precision, an
unknown required feature bit, a missing payment hash, secret or
description, a signature that does not recover, or one that disagrees with
the node key the invoice names. The reader is wallet-core's: the long
bech32 decoder from the silent-payment work, the 5-bit field walk, and
coinxt's signature recovery. The vector gate holds every field of every
example in the specification (`tests/bolt11-vectors.json`) and each of its
invalid examples. A BIP-21 URI that carries a `lightning=` parameter - the
unified QR most Lightning wallets now show - is read as both halves, the
on-chain address and amount with the invoice beneath, and one with no
address at all is read as the invoice alone. This wallet holds no channels
and cannot pay an invoice; it says so on the same screen. Not run on an
engine.

## Testnet4, and labels that travel

Since 2026-09-04 the Wallet screen offers **testnet4** beside testnet. It is
a different chain with testnet3's bytes everywhere (prefixes, WIF, extended
keys, coin type), so the backend is the only thing that tells them apart:
Blockstream's mirrors index testnet3 and are refused for it by name, with
`mempool.space` - the built-in second Esplora host, which serves `/testnet4`
- offered as the remedy; the built-in Electrum servers are refused too.
Testnet3 is being retired, so this is where new test coins will come from.
Not run on an engine, nor against mempool.space's testnet4 index.

The Settings screen exports and imports labels in **BIP-329**, one JSON
object per line, the format Sparrow, Bitcoin Core and the rest read. Address
labels go out as `addr` records; frozen coins as `output` records with
`spendable: false`; both come back, and the record types this wallet keeps
no home for (tx, input, pubkey, xpub) are counted and skipped, never
refused. The file sits beside the wallet file, named for it. The gate drives
the round trip, the BIP's own example lines, and the refusals.

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

## The next engine pass, and what each step proves

Everything dated 2026-09-04 above says "not run on an engine". The order
below is shortest feedback first; each line names the honesty label it
flips when it comes back clean.

1. **Boot, and the log.** Open the stack; the boot self-check prints its
   own record. Green flips nothing new but is the precondition for all of it.
2. **Tools, paste box.** Paste any `lnbc...` invoice and press Inspect: the
   payee node key, amount and fields. Then a mainnet transaction id known
   to carry a runestone (any Runes etching or transfer; block 840,000
   onward) with a backend chosen on Network, press Inspect, and read the
   runestone under its OP_RETURN output. Both flip their sections' labels.
3. **Tools, `inscribe: text/plain; hello` and Inscribe.** The commit
   address appears and joins the Addresses screen; save the wallet, reopen
   it, and the commit is still there (the recipe line). Flips the commit
   half of the inscription section. Funding it on signet or testnet4 and
   pressing Inscribe again with the box empty, then Broadcast, is the reveal
   half - an explorer that reads inscriptions will show it at `<txid>i0`.
4. **Tools, `lock: <height a few blocks ahead>` and Lock.** Pay the address
   from the Send screen; the Coins screen shows `LCK`; before the height a
   MAX spend leaves it out, after the height a manual spend of it signs with
   the raised locktime, and a node accepts the broadcast. Flips the timelock
   section.
5. **Send, a `tsp1...` line.** Any silent payment address for the network
   (a wallet that supports BIP-352 receiving can give one); Preview shows
   the derived `tb1p...` output, Sign, Broadcast, and the receiving wallet
   finds it. Flips the silent-payment section. Paying one from a mainnet
   wallet is real money to an address only the payee can find; test first.
6. **Tools, BIP-322.** Sign with a taproot wallet's first address and verify
   the result in Bitcoin Core's `verifymessage` or Sparrow. Flips the
   signed-messages section.

What comes back from an engine goes into the section it belongs to, dated,
and into `CLAUDE.md` - the convention the rest of this file follows.

