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
* [Updating from main](#updating-from-main)
* [Signed messages, fee bumps and the broadcast memory](#signed-messages-fee-bumps-and-the-broadcast-memory)
* [Bitcoin Core as a backend, and the Node screen](#bitcoin-core-as-a-backend-and-the-node-screen)
* [Silent payments](#silent-payments)
* [Runes, inscriptions, timelocks, Lightning invoices, testnet4 and labels](#runes-inscriptions-timelocks-lightning-invoices-testnet4-and-labels)
* [Custody, said plainly](#custody-said-plainly)
* [The engine API](#the-engine-api)
* [Running it](#running-it)

## Two files, and why

| File | What it is |
|---|---|
| `examples/wallet-core.livecodescript` | The engine. Prefix `cw`. Pure functions over CoinXT: scripts, addresses, extended keys, amounts, sizes, fees, coin selection, sighash dispatch, witness shapes, PSBT, signed messages, payment URIs, output descriptors, transaction decoding, silent payments, Runes, inscriptions, BOLT11, JSON and QR. |
| `examples/coin-wallet.livecodescript` | The wallet. Prefix `wa`. Thirteen screens, the key custody, the wallet file, the network, and the window. Carries CoinXT, the engine above, and OnionXT, so it is one file to paste. |

The engine ships under `examples/` rather than `src/` because it is a library a
demo carries, not part of the extension's published surface (the same reason
`enetxt/examples/enet-helpers.livecodescript` lives there). Everything in it is
composed from `cx*` calls and nothing is added to what CoinXT installs.

Three properties of the engine are deliberate and each one buys something.

**No state.** Not one script-level `local`. Every handler is a function of its
arguments, so there is nothing to initialise, nothing to tear down, no order of
calls to get wrong, and no way for one screen to leave another screen's answer
stale.

**No `item` and no `line` chunks.** Lists are arrays, keyed `1..n` with an `n`
count. `the itemDelimiter` and `the lineDelimiter` are global mutable state in
this engine family, and this member's `CLAUDE.md` records nine CoinXT handlers
that a hostile delimiter turned into wrong ANSWERS rather than errors. CoinXT
answered that with a save/set/use/restore wrapper; not reading those chunks at
all is the stronger answer, available here because this layer was written after
the lesson.

**No UI and no I/O.** That is what lets the vector gate run it.

## What it does

The wallet has thirteen screens (`kWaScreenCount`): Wallet, Receive, Addresses,
Send, Coins, History, Ordinals, Vault, Tools, Network, Node, Log and Settings.

**Wallet kinds.** A new seed (24 words, entropy from SodiumXT and no fallback),
a restored seed with an optional BIP-39 passphrase (an Electrum-format seed is
recognised and opened), watch-only from an account
`xpub`/`ypub`/`zpub`/`tpub`/`upub`/`vpub`, a single imported WIF key, or an
m-of-n P2WSH multisig from cosigner account keys.

**The seed this wallet starts with is PUBLIC.** It opens holding BIP-39's
published test mnemonic so every screen has something true to show. Those
twelve words are printed in the specification, so anyone can derive the same
private keys and spend anything sent to them. Mainnet is not blocked - that is
a decision - but the wallet says so on the Wallet screen, at the top of Receive
above the address itself, and on Send. Generate or restore a seed of your own
before you accept a single real coin.

**Networks.** mainnet, testnet, testnet4, signet and regtest, each with its own
base58 version bytes, bech32 HRP and extended-key versions. A network change
drops the address and balance state rather than showing addresses from one
chain beside balances from another.

**Script types.** Legacy P2PKH (BIP-44), nested SegWit P2SH-P2WPKH (BIP-49),
native SegWit P2WPKH (BIP-84), Taproot P2TR key-path (BIP-86), and P2WSH
multisig (BIP-48, with BIP-67 key ordering so every cosigner independently
derives the same address).

**Receive.** The next unused address, a BIP-21 URI carrying an optional amount,
label and message, and a scannable QR code of that URI (byte mode, error level
M, versions 1 to 15, rendered as an uncompressed BMP into an image control). A
seed wallet also shows its BIP-352 silent-payment address, with a copy button.

**Addresses.** Both chains to a gap-limit window, with per-address labels, use,
balance, and an explicit "derive twenty more" that says what going past the gap
limit costs. The window also extends itself when it has to: an inscription
commit, a timelock, a change output or a reveal that finds every address of its
chain used derives a further window first and says so in the log.

**Send.** One payment or many, amounts in BTC, mBTC or satoshi, `MAX`, a fee
rate in sat/vB with a plain-language description of what that rate means, four
coin-selection strategies plus manual coin control, opt-in RBF, a locktime, and
a review panel that shows every output in full, the fee, the change address and
which coins are being spent, before anything is signed. It can also stop at an
unsigned PSBT. A line reading `note: some text` (or `data: hex`) adds one
OP_RETURN output of value 0 carrying those bytes; one per transaction, because a
second is what most nodes refuse to relay, and anything over eighty bytes is
warned about for the same reason. A BIP-352 silent payment address (`sp1...`,
`tsp1...`) goes on a line like any other.

**Coins.** The UTXO set with freeze and thaw, ticking for manual selection, and
a hand-entry path so an offline wallet can be told what it owns. Spent-but-
unconfirmed coins show as `SPT`, time-locked ones as `LCK`.

**History.** Transactions with confirmations, amounts and fees, a full decode of
any of them (Inspect asks the backend for raw bytes it does not hold and paints
the decode when they arrive), and a fee bump (below). For a transaction made in
an earlier session it prints the arithmetic and says plainly why it cannot build
a replacement: signing records what a spend was made of, and an input's value is
committed to by BIP-143 but not carried in the raw transaction.

**Ordinals.** A content type with three quick picks, a body, a line that prices
the reveal as you type, and two numbered buttons: 1 prepares the commit address
(and saves the recipe with the wallet), 2 signs the reveal once that address
holds a coin. A table lists every inscription this wallet prepared with its
state (unfunded, funded, revealed), and a box reads any transaction's
inscription or runestone.

**Vault.** A block height, or +1 day / week / month / year from the tip, a line
saying how far away that is, and Prepare, which makes the CLTV address and saves
its recipe. A table lists every vault address with its state read from the tip
(locked with the blocks to go, or UNLOCKED) and what it holds.

**Tools.** Sign and verify a message, load, sign, combine and finalize a PSBT,
inspect anything you paste (a raw transaction, a PSBT, an extended key, a WIF,
an address, a URI, a BOLT11 invoice), decode a bare script from hex, validate
an address or an extended key on EVERY chain, convert entropy to a mnemonic and
back (with the master fingerprint with and without a passphrase), mint a single
key, derive at an arbitrary path, sweep a private key, export descriptors and
account keys, inscribe, lock, and ask a Bitcoin Core node for a second opinion.

**Network, Node, Log, Settings.** The backend and its hosts (next section); a
Bitcoin Core node's status, fees, mempool and sandbox; the log; the wallet file
and its password, the display unit, the gap limit, BIP-329 labels, Update from
main, and the honesty record.

**A right-click anywhere** opens a menu for the screen you are on. Every item
routes to the same handler the screen's own buttons route to, so an item can
only ever mean what a button means.

## The network, and the shape it was forced into

There are eight backend choices and the differences between them are real.

| Backend | How | What it costs you |
|---|---|---|
| `esplora-tor` | A `.onion` Esplora mirror over plain HTTP/1.1 through OnionXT's SOCKS client, one kept stream per sync | The server learns which addresses are asked about together. Nobody else learns anything. |
| `electrum-tor` | A `.onion` Electrum server, JSON-RPC over the same kind of circuit, batched | The same, except the server is asked about SCRIPT HASHES rather than addresses. |
| `esplora-clear` | The engine's own `load URL` | The server learns your addresses AND your IP; on `http://` so does everyone in between. `load URL` is a GET, so it cannot broadcast (refused by name) and sees no status code. |
| `electrum-clear` | A TCP socket to an Electrum server, batched | Addresses (as script hashes) and your IP. |
| `core-rpc` | Your own Bitcoin Core node, JSON-RPC over HTTP | Nothing leaves your machines. Needs a node. |
| `core-tor` | The same POST to your node published as a hidden service | The circuit is the encryption; there is no default onion. |
| `core-cli` | `bitcoin-cli` through `shell()` | Zero configuration if `bitcoin-cli` already works; blocks the window while it runs. |
| `offline` | Nothing | Nothing. Everything except Broadcast still works. |

**HTTPS over Tor is not on that list because it cannot be.** An already-open
socket cannot be upgraded to TLS in this engine, and `open secure socket` talks
TLS directly to a host, so it cannot perform a SOCKS handshake first. A `.onion`
endpoint over plain HTTP is the correct shape here, not a compromise: the
circuit is the encryption and the authentication.

**Which chain a backend carries is not a detail.** Esplora serves each chain
under its own root (`/api`, `/testnet/api`, `/signet/api`, and `/testnet4` on
mempool.space), and the wallet builds the root from the network it is on. An
Electrum server is worse: asked about a script hash from another chain it
answers with an empty list, a well-formed "this address has never been used",
so a testnet wallet on a mainnet server would report itself synced and empty.
The wallet refuses a backend that does not carry the selected chain before it
builds a request, and says which host to change. Blockstream's onion Electrum
server selects the chain by port (110 mainnet, 143 testnet). Regtest has no
public backend, so it is refused against every built-in host.

The clearnet options are offered with what they cost written on the screen.
This suite has never measured what the engine does about TLS certificates (the
suite's docs/OXT-ENGINE-NOTES.md 6.8), so `https://` here carries no claim about
verification.

`socketError`, `socketClosed` and `socketTimeout` are the engine's names and a
script may define each exactly once. The wallet carries OnionXT, so it defines
all three and hands each event to OnionXT's named function first.
`tools/sync-demo-embeds.py`'s `DROP_HANDLERS`, keyed by (app, provider) pair,
drops OnionXT's own wrappers from the embed and asserts both halves.

## What is proven and what is not

Three layers, each with its own answer.

**The engine layer is RUN.** `tools/check-wallet-vectors.py` drives the shipped
`wallet-core.livecodescript` through `tools/lcs-interp.py` against
`tools/wallet_reference.py`, an independent implementation anchored at import to
the published vectors, with the real native CoinXT library supplying every hash
and signature. Among its checks: the BIP-44/49/84/86 first receive addresses for
the test mnemonic; BIP-49's and BIP-84's own account `ypub` and `zpub`; every
address in both directions on two networks; Bitcoin Core's descriptor
checksums; the 226 and 141 virtual sizes; the 546/540/330/294 dust thresholds;
complete signed transactions on all five spend paths; BIP-322's published
vectors; the BIP-352 sending and receiving vectors
(`tests/bip352-sending-vectors.json`, `tests/bip352-receiving-vectors.json`);
the Runes reference cases; and every example in the BOLT11 specification
(`tests/bolt11-vectors.json`). Run it for the count.

**And it is run TWICE.** `the caseSensitive` defaults to FALSE on OXT, which
makes `is` and `offset()` case-INSENSITIVE, while `lcs-interp.py` models them
case-sensitively. So the whole set runs a second time with those two folded to
the engine's rule, and the same answers are required. The tier exists because
the first version of this layer had two defects of exactly that shape, green
under 414 checks: a descriptor checksum wrong for every descriptor containing a
letter (Core's alphabet carries `abcdefgh` at position 18 and `ABCDEFGH` at 82,
so a folded `offset()` returns the wrong twin), and a multisig account key
serialized as `zpub` instead of `Zpub` because the stems were told apart with
`is`.

**The stack layer is BOOTED.** `tools/check-wallet-boot.py` opens the shipped
`coin-wallet.livecodescript` headlessly - `preOpenStack`, `openStack`, the
queued self-check tick - over riptide's engine object model (imported, not
copied) with the COMMITTED `coinxt.so` underneath, then drives it: every
navigation button through the real click router, the show/hide sweep across all
thirteen screens, a spend built, signed and decoded by the oracle, a PSBT round
trip, messages signed and verified, fee bumps checked against BIP-125, every
context-menu item, the wallet file sealed, re-opened and refused after one
flipped bit, and every backend through modelled sockets, Tor streams and a
modelled shell. SodiumXT is modelled and declared in the gate; OnionXT answers
its version probe and nothing else. `tools/test-wallet-boot.py` seeds real
defects into copies and requires the gate to fail on each.

**The library has six engine passes** (2026-08-08 through 2026-09-24, the last
at 296/296 in the suite paste), so the cryptography under the wallet is
engine-observed, `cxPubkeyCombine` (ABI 7, which the silent-payment receiver
uses) included since 2026-09-24. The receiver built on it has not run.

An interpreter is an approximation of the engine and never the engine; where
they disagree the engine is right. What the gates settle is that the code RUNS
and what it computes.

### Engine evidence

Pasted logs from one person's engine (platform not recorded), on testnet unless
stated. Each row is condensed; the full record is `CLAUDE.md`, "The wallet on an
engine".

| Date | What ran | Result |
|---|---|---|
| 2026-09-01 | electrum-clear, MAINNET, `electrum.blockstream.info:50001`, the demonstration wallet | a full sync on one persistent socket, replies correlated by id, a 16 KB history. The same log's 27 repeated BIP-39 lines exposed a failed Open committing a bad phrase (fixed that day) |
| 2026-09-02 | REPORTED, no log: a testnet receive over both clearnet transports | the first coin held; recorded as reported, no more |
| 2026-09-02, second log | esplora-tor, 147 circuits; electrum-clear's reshaped sync (42 requests) | **the first broadcast**, over esplora-tor: a 226 vB legacy spend, txid `7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, seen spent by the next sync |
| 2026-09-02, fourth log | a fresh open, boot self-check green | esplora-clear, esplora-tor and electrum-clear all fire on both chains |
| 2026-09-02, fifth log | electrum-tor against the retired v2 onion; the right-click menu | "general SOCKS server failure" and the retry-once seen working; the menu opened on an engine and acted on the previously selected row (fixed; the fix has not run on an engine) |
| 2026-09-03, sixth log | **electrum-tor**, Blockstream's v3 onion, port 143 | a full sync, a second wallet, and a broadcast, txid `9bab6640f2bbe01f96a95ffdeca3e96881f1819e677348562ef8bf87da6b719a`, seen spent |
| 2026-09-03, seventh log | electrum-tor with kept streams | two full syncs, one stream each; a header pushed on the idle stream logged and ignored |
| 2026-09-03, eighth log | esplora-tor on HTTP/1.1; Electrum batches | 51 requests down one Tor stream; both Blockstream Electrum servers take JSON-RPC batches (51 requests in five round trips) |
| 2026-09-03 evening | autotest chain phase, electrum-tor | an onion server refused a batch of 22 and the halving answered every line of 11 (41 requests in eight round trips) |
| 2026-09-03 19:42 EDT, tenth log | the autotest's chain phase, p2pkh wallet, electrum-tor | 41 passed / 0 failed / 4 skipped: an OP_RETURN note and its RBF bump (voiding the note's coins), a silent-payment send and an inscription commit built on the replacement's change and accepted, the reveal accepted (inscription `f002bfb2bde8ff4354c89ca590291bea96416ed6e2e5797c0e863b9be79bc0eei0`), the vault paid and its coin withheld, every acceptance reserved at queue time |
| 2026-09-03 20:30 EDT, eleventh log | the second autotest | a refused broadcast released its coin with the node's reason (`mempool-script-verify-flag-failed`); a bump refused naming the queued child; a change-less sweep bumped by a CPFP child priced from the spend record, accepted |
| 2026-09-03 21:54 EDT, twelfth log | the second autotest on the wallet as fixed by it | 14/14, nothing skipped: the same three again, both address windows extending themselves, and every queued transaction (the CPFP pair included) accepted by the network afterwards |

### What has not run on an engine or a node

- Everything added from 2026-09-04: the Ordinals and Vault screens as screens,
  testnet4 and BIP-329 labels, BIP-322, Runes, BOLT11, silent-payment
  receiving (its `cxPubkeyCombine` has run in the library harness since
  2026-09-24; the receiver has not), the Bitcoin Core backends (no node
  has been met at all), and the 2026-09-10 audit fixes.
- Update from main's swap itself.
- Electrum on the mainnet onion (port 110).
- The right-click menu's row-selection fix and its three corrected items.
- The stale-answer skip (a fresh tip or fee estimate is not asked for again),
  the paint and pump timing, and the tip and fee estimate riding in the first
  batch.
- The backend un-marking a coin it still lists, and Esplora's 400 body reaching
  the log.
- A vault release after its height; CPFP on a transaction this wallet did not
  build; an Electrum-format seed opening real coins.
- A native P2WPKH broadcast. No Ethereum transaction and no mainnet spend has
  been broadcast.

## Updating from main

The Settings screen has an **Update from main** button, and every right-click
menu ends with the same item. It fetches the raw text of
`coinxt/examples/coin-wallet.livecodescript` at the tip of the repository's
`main` branch (one `get URL` of a fixed address), reads it, and offers it: the
version it declares, its size and its SHA-256 next to the running version.
Nothing replaces the script until Update is pressed. The reading refuses, with
the reason, anything that does not begin the way this script begins, is under
half or over three times the running script's size, declares no version, lacks
`waUpdateRestore`, `preOpenStack` or `openStack`, or is identical to the running
script.

On Update the wallet (as the wallet file would hold it), the Network settings
and the screen are parked in a stack property; the network is stopped; the
stack's script is replaced; and `preOpenStack` and `openStack` are sent to the
new script, whose boot reads the carry back, clears it, and says what version
it came from. A script that does not compile leaves everything as it was. The
carry is cleared on close as well, so a swap that never came back cannot leave
a seed on a saved stack.

**What that trusts, said plainly.** Whoever can write to `main` can put code in
front of your keys, and so can anyone who can answer for
`raw.githubusercontent.com` if the engine's TLS is not doing its job (this suite
has not measured that). The version and SHA-256 in the offer are there so a
person can compare them with the commit they expect before pressing Update. The
check, the carry, the restore, the button and the menu route are gated
headlessly; the swap itself (`set the script of this stack` from inside one of
that script's own handlers) is engine work and has not run on an engine.

## Signed messages, fee bumps and the broadcast memory

**Signed messages.** Tools signs in the 2011 format (the header that names the
key's shape, read by Electrum and every explorer) for legacy, nested and native
SegWit addresses, and in **BIP-322**: always for taproot, which the 2011 format
cannot express, and for native SegWit when the box beside Verify is ticked.
BIP-322 proves an address by SPENDING it: a virtual transaction pays the
message's tagged hash to the address, a second spends that output to OP_RETURN,
and the signature is the second one's witness, base64. Verify reads the format
off the signature (the 2011 form is exactly 65 bytes; a witness stack never is).
The vector gate holds the BIP's published message hashes, to_spend txids and
signatures.

**Replace by fee.** For a spend this window signed, with the opt-in and some
change, Bump BUILDS the BIP-125 replacement: same inputs, same payments, the
extra fee out of the change, signed and printed line by line, not broadcast.

**Child pays for parent.** For a transaction this wallet did not build (a stuck
incoming payment), or one built without the opt-in or without change, if this
wallet holds an unconfirmed output of it, Bump builds a CHILD that spends that
output back to the next change address at a fee covering the parent's bytes as
well as its own at the Send screen's rate. The parent's size comes from its
bytes (fetched like Inspect fetches them, or from the weight Esplora reports);
its fee is known only where the backend says it, and when it is not the child
pays for both sizes in full and says so. For the wallet's own transactions the
size and fee come from the spend record, with no request. The child signals RBF.
On a Core backend the mempool card supplies the whole unconfirmed ancestor
package, so a bump prices the package exactly.

**The broadcast memory.** A transaction this wallet hands to the network is its
own word about its coins, from the moment the broadcast is QUEUED: the inputs are
marked (`SPT`), a marked coin is not offered to the selector or to a CPFP bump
and is not counted in the balance, and every output that comes back to this
wallet is listed at 0 confirmations and counted as pending, so a second spend a
moment later has the change to draw on and reuses nothing. A broadcast the
backend refuses for good (after one retry) hands the coins back and drops the
outputs it added, quoting the backend's REASON (the Tor Esplora reader holds a
non-2xx status until the body arrives, so the log says
`400 Bad Request: bad-txns-inputs-missingorspent` rather than a status line). A
replacement re-marks the inputs with its own txid and drops the coins added from
the transaction it replaced. Bump refuses to replace a transaction whose output
a queued or broadcast spend of this wallet already uses, and names that child.
The memory is subordinate to the backend: a coin the backend still lists as
unspent loses its mark and is offered again, with a log line naming the
transaction that was supposed to have spent it. Nothing is saved; the marks live
for the session, like the spend records.

## Bitcoin Core as a backend, and the Node screen

The design, the capability map, what is deliberately out of scope and the risks
a real node must settle are [bitcoin-core-plan.md](bitcoin-core-plan.md). What is
built:

**The node is spoken to over JSON-RPC 1.0 on plain HTTP**, one POST per request
down a socket kept open between requests (Core drops a quiet client after thirty
seconds; the next request connects again and nothing is counted). The host is
127.0.0.1 and the port follows the chain by Core's own table (8332, 18332, 48332
for testnet4, 38332, 18443 for regtest), both editable. Credentials are the
cookie file the running node writes, read at EVERY request because it changes
when the node restarts (the path is filled in for the chain and the platform),
or `rpcuser:rpcpassword`, which wins when both are filled. A node that is not on
this machine gets the credentials only if you tick the box for it, because Core's
RPC is unencrypted; an SSH tunnel to 127.0.0.1 is the better answer. The log
line for a request is the method and its size, never the headers, and the wallet
file never carries the credentials.

**The chain is asked, not assumed.** The first request of a sync to an unknown
node is `getblockchaininfo`; a node on another chain is refused with both names
in the sentence, the queue emptied, and the refusal held until the network or the
host moves. The same answer gives the tip, whether the node is pruned or still in
its initial block download (balances from a node still downloading are
provisional), and how far behind its headers it is.

**The scan tier** needs nothing set up on the node: a sync is three requests
however many addresses there are (the chain, `estimatesmartfee` for six blocks,
and ONE `scantxoutset` over an `addr()` entry for every address, leaves
included), which is what makes a pruned node enough. A scan reads the chain and
not the mempool, so a payment on its way to you is invisible until it confirms,
and it has no history; both are written on the screen. A coin this wallet spent
and the node still lists stays marked spent, because a scan is not mempool
evidence either way.

**The watch tier** asks the node to keep a wallet of its own for your
addresses, named `coinxt-<master fingerprint>` so two accounts on one node never
share one, created blank with private keys DISABLED: the node can never be asked
to sign. A sync is then what that wallet has found, mempool included, with
history from `listtransactions`. It costs one rescan when created, from the
first-used date: an earlier date is safe and slow, a later one silently loses
history, so an empty box means the genesis block and the wallet never guesses (a
seed generated here records its own birth). When the address window grows past
what the node was given, the next sync re-imports first.

**A broadcast is `sendrawtransaction`**, and a refusal comes back as the node's
own words with its RPC code (-26 policy, -25 and -27 missing inputs and
already-in-chain, -28 still starting, -5 not found), released to the coins like
any refusal. HTTP 401, 403 and 404 are mapped to sentences naming the cookie,
`rpcallowip` and the wallet path.

**Three ways to reach the same node.** `core-rpc` is the socket above.
`core-tor` sends the identical POST down a Tor stream to a node you have
published as a hidden service (no default onion, and no credentials tick, since
the circuit is the encryption). `core-cli` runs `bitcoin-cli` instead: no host,
port, cookie or password to type. It blocks the window while the program runs,
so its requests go when you press a button and never on the poll timer. Every
command is built from the `kWaCoreMethods` allowlist and never for keys or
coins; on POSIX a single-quoted argument carries a JSON payload untouched, and
on Windows a structured argument is refused with `core-rpc` named as the remedy.

**The Node screen** shows the node's host, credentials in use, reported chain
against the wallet's, blocks and headers, pruning or initial download, version
and peer count; its fee estimates for 1, 6 and 144 blocks, each with a button
that writes it into Send; the watch-tier controls; a **mempool card** for a
selected history row (size, fee, ancestors, descendants, age, replaceability)
and **Test**, which asks `testmempoolaccept` whether the node WOULD accept the
last signed transaction and sends nothing; and on regtest only a **sandbox**:
Start makes a node in a directory beside the wallet file and waits for it, Mine
pays six blocks to this wallet's first address, Reorg throws the tip away, mines
a longer chain and reconsiders the old block, and Stop stops it without deleting
anything. The sandbox's `bitcoind` / `bitcoin-cli` commands are refused by name
on every other chain before any program runs. On Tools, **Ask the node** sends an
address to `validateaddress`, a descriptor to `getdescriptorinfo` and a PSBT to
`analyzepsbt`: a cross-check and never an authority; the node is never given a
key.

Not run against a node: all of this is driven headlessly by
`tools/check-wallet-boot.py` through a modelled socket, Tor stream and shell,
against fixtures of the node's reply shapes, with the request bytes and command
lines asserted.

## Silent payments

**Sending.** An `sp1...` / `tsp1...` address is two public keys, not a script:
the output that receives the coins is a taproot output derived from the private
keys of the coins funding the transaction and its smallest outpoint, so paying
the same address twice lands on two unrelated outputs. The parser gives the line
a taproot kind (all the sizer and dust rule need), coin selection runs as usual,
and only then, with the inputs known, is the output derived (a taproot input's
key is the tweaked one, negated to even y) and its script written into the
payment. It is refused as a PSBT, from a watch-only wallet (there is no script
to hand a signer) and from a multisig wallet (P2WSH inputs take no part in the
BIP). The derivation is staged so the vector gate holds each step to the BIP's
sending vectors: the address decode under BIP-352's 1023-character bech32m
waiver, the input key sum in hex mod n (the native tweak-add refuses a zero
intermediate, and one vector is exactly that), the input hash, the shared
secret, the outputs with their per-scan-key counter, and the three refusals (no
eligible input, a zero key sum, more than 2323 outputs to one scan key; K_max is
counted first). Paying one from a mainnet wallet is real money to an address
only the payee can find; test on testnet first.

**Receiving.** A receiver holds a scan key and a spend key (BIP-352's
`m/352'/coin'/0'/1'/0` and `.../0'/0`) and, for every transaction it is given,
repeats what a sender computed and asks whether `B_spend + t_k * G` is one of its
taproot outputs. The sum of the input public keys is ABI 7's `cxPubkeyCombine`,
summed over the whole set at once. `cwSpInputPubkey` is the reference's
`get_pubkey_from_input`; `cwSpPubkeySum`, `cwSpScan`, `cwSpLabelTweak` and
`cwSpReceiveAddress` are the rest. A found output's private key is
`b_spend + tweak` and it signs UNTWEAKED (`cwSignKeyPath`). Every stage is held
to all 29 of the BIP's receiving cases on both the script and the oracle; the
K_max case alone is proven by the oracle and checked in the script as a source
shape (millions of interpreted iterations otherwise).

The wallet does NOT scan the chain: finding a payment needs the script each input
spends, which a raw transaction does not carry, and no backend here publishes a
tweak index. It scans a transaction it is HANDED: paste it on Tools and press
Inspect, and a SILENT PAYMENT CHECK line follows the report; the wallet asks the
backend for each input's parent transaction (the fee bump's own request, on
every backend), keeps at most 64 parents so a second Inspect scans at once, and
runs the scan when the last one lands. Offline, paste the script each input
spends under the transaction, one per line in input order. A found output joins
the address list at its own taproot address and is written to the wallet file
as an `sp` line. Labels are not used on the receiving side.

## Runes, inscriptions, timelocks, Lightning invoices, testnet4 and labels

**Runes, read only.** Inspect reads a runestone (the OP_RETURN OP_13 output):
the etching with its name (spacers as dots), symbol, divisibility, premine and
open-mint terms; the mint; the pointer; every edict; and the CENOTAPH verdict
with its flaws, applying the rules in the specification's order, because a
malformed runestone burns the runes it touches. The numbers are 128-bit, so they
stay decimal strings and never meet a double. No etching, minting or balances,
which need an indexer. The vector gate holds the reader to the reference
implementation's own test cases.

**Inscriptions, by commit and reveal.** With `inscribe: text/plain; hello` (or
`inscribehex: <type>; <hex>`) in the Tools box, or on the Ordinals screen,
Inscribe prepares the commit: a taproot output whose single hidden leaf is the
ord envelope (`<key> OP_CHECKSIG OP_FALSE OP_IF "ord" <type> <body> OP_ENDIF`,
pushes of at most 520 bytes) keyed by the next unused receive key; the commit
address joins the wallet's list and the recipe is saved with the wallet. Once
the coin is seen, Inscribe signs the reveal: one input spent through the leaf,
one output to the next receive address, which is frozen from the moment the
reveal is signed so no ordinary spend can hand the inscribed sat to a miner or a
payee. The leaf hash uses a real compact size, because CoinXT's `cxTapLeafHash`
stops at 252 bytes and an inscription is exactly the script that exceeds it.

**Coins locked until a block.** `lock: <height>` (or the Vault screen) prepares an
address whose only leaf is `<height> OP_CHECKLOCKTIMEVERIFY OP_DROP
<receive key> OP_CHECKSIG` under the NUMS point as internal key, so there is no
key-path spend around it. The Coins screen marks such a coin `LCK`; below the
height it is withheld from selection, and from the height on Send spends it with
the locktime raised automatically and said so in the review.

**Lightning invoices, read out.** Inspect and Validate read a BOLT11 invoice:
the network, the amount (in millisatoshi and the wallet's unit), the payee node
key recovered from the signature, the description or its hash, the payment
hash, issue and expiry, the final CLTV, an on-chain fallback address (which this
wallet can pay), route hints, feature bits and metadata. It refuses what the
specification calls invalid, naming the reason. A BIP-21 URI with a
`lightning=` parameter is read as both halves. This wallet holds no channels and
cannot pay an invoice, and says so.

**Testnet4.** A different chain with testnet3's bytes everywhere, so the
backend is the only thing that tells them apart: Blockstream's mirrors index
testnet3 and are refused for it by name, with mempool.space (`/testnet4`)
offered; the built-in Electrum servers are refused too.

**BIP-329 labels.** Settings exports and imports one JSON object per line:
address labels as `addr` records, frozen coins as `output` records with
`spendable: false`. Record types this wallet has no home for (tx, input,
pubkey, xpub) are counted and skipped, never refused. The file sits beside the
wallet file.

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
prefix (the suite's `tools/check-cross-library-names.py` holds every name
disjoint from every other library). The groups are:

| Group | Handlers |
|---|---|
| Networks | `cwNetworks`, `cwNetHrp`, `cwNetP2pkhVersion`, `cwNetP2shVersion`, `cwNetWifVersion`, `cwNetCoinType`, `cwXKeyVersion` |
| Script types | `cwScriptTypes`, `cwTypePurpose`, `cwTypeStem` |
| Scripts | `cwPush`, `cwPushLen`, `cwScriptNum`, `cwScriptP2pkh`, `cwScriptP2sh`, `cwScriptP2wpkh`, `cwScriptP2wsh`, `cwScriptP2tr`, `cwRedeemP2shP2wpkh`, `cwScriptP2shP2wpkh`, `cwMultisigScript`, `cwScriptKind`, `cwScriptAsm`, `cwScriptItems`, `cwScriptCheck`, `cwOpReturnScript`, `cwOpReturnData` |
| Addresses | `cwAddressForScript`, `cwScriptForAddress`, `cwAddressKind`, `cwAddressIsValid`, `cwAddressProblem`, `cwElectrumScripthash` |
| Derivation | `cwParsePath`, `cwFormatPath`, `cwAccountPath`, `cwFingerprint`, `cwXKeyEncode`, `cwXKeyDecode`, `cwXKeyIsPrivate`, `cwXKeyRespell`, `cwAccountXKey`, `cwChainNode`, `cwAddressAt`, `cwMultisigAddressAt` |
| Amounts | `cwSatToBtc`, `cwBtcToSat`, `cwFormatAmount`, `cwParseAmount`, `cwExpandExponent` |
| Size and fees | `cwVarIntLen`, `cwInputBaseBytes`, `cwInputWitnessBytes`, `cwOutputBytes`, `cwEstimateVsize`, `cwSimpleInputs`, `cwTapscriptInputVsize`, `cwFeeFor`, `cwDustThreshold`, `cwRbfMinFee`, `cwFeeRateLabel` |
| Coin selection | `cwSelectCoins` |
| Transactions | `cwTxInput`, `cwTxOutput`, `cwOutpointsHex`, `cwSequencesList`, `cwOutputsHex`, `cwSighash`, `cwSighashTaproot`, `cwSignInput`, `cwSignTaproot`, `cwSignKeyPath`, `cwSignMultisig`, `cwMultisigKeys`, `cwWitnessBytes`, `cwWitnessStackEncode`, `cwWitnessStackDecode`, `cwCompressPubkey`, `cwDerToCompact`, `cwTxSerialize`, `cwTxid`, `cwTxDecode` |
| Taproot script path | `cwTapLeafHash`, `cwTapCommit`, `cwTapscriptSighash`, `cwSignTapscript`, `cwScalarAdd`, `cwScalarNegate`, `cwInscriptionScript`, `cwTimelockScript` |
| PSBT | `cwPsbtCreate`, `cwPsbtParse`, `cwPsbtEmit`, `cwPsbtSign`, `cwPsbtFinalize`, `cwPsbtCombine`, `cwPsbtSummary`, `cwPsbtFind`, `cwPsbtFindAll`, `cwPsbtInputAmount`, `cwPsbtInputScript`, `cwPsbtInputType`, `cwPathBytes`, `cwPathFromBytes`, `cwPsbtUnsignedTx` |
| Messages | `cwMsgDigest`, `cwMsgSign`, `cwMsgVerify`, `cwBip322Hash`, `cwBip322ToSpendTxid`, `cwBip322Digest`, `cwBip322Sign`, `cwBip322Verify` |
| Silent payments | `cwSpIsAddress`, `cwSpHrp`, `cwSpDecode`, `cwSpEncode`, `cwSpPath`, `cwSpEligible`, `cwSpInputSum`, `cwSpInputHash`, `cwSpSharedSecret`, `cwSpOutputs`, `cwSpSend`, `cwSpInputPubkey`, `cwSpPubkeySum`, `cwSpScan`, `cwSpLabelTweak`, `cwSpLabeledSpend`, `cwSpReceiveAddress` |
| Runes | `cwRunestoneDecode`, `cwRunestonePayload`, `cwRunestoneIntegers`, `cwRuneName`, `cwRuneSpaced`, `cwRuneAmountText`, `cwLeb128Decode`, `cwLeb128Encode` |
| Decimal strings | `cwDecAdd`, `cwDecSub1`, `cwDecMulAdd`, `cwDecDivMod`, `cwDecCompare`, `cwDecCheck` |
| Lightning | `cwBolt11IsInvoice`, `cwBolt11Prefix`, `cwBolt11Decode`, `cwBolt11AmountMsat`, `cwBech32DecodeLong`, `cwBech32EncodeLong`, `cwHexToBits`, `cwBitsToHex` |
| URIs | `cwUriParse`, `cwUriBuild`, `cwPercentEncode`, `cwPercentDecode` |
| Descriptors | `cwDescriptorChecksum`, `cwDescriptor`, `cwDescriptorMultisig` |
| JSON | `cwJsonParse`, `cwJsonType`, `cwJsonCount`, `cwJsonAt`, `cwJsonMember`, `cwJsonKeys`, `cwJsonText`, `cwJsonPath`, `cwJsonGet`, `cwJsonEscape`, `cwJsonString2` |
| QR | `cwQrVersionFor`, `cwQrCodewords`, `cwQrMatrix`, `cwQrText`, `cwQrBmp` |
| Lists and bytes | `cwCharIndex`, `cwSameBytes`, `cwListNew`, `cwListAdd`, `cwListCount`, `cwLeBytes`, `cwBeBytes`, `cwLeRead`, `cwBeRead`, `cwReverseBytes`, `cwHexIsClean`, `cwHexCompare`, `cwSortHexList`, `cwLower`, `cwUpper`, `cwTrim`, `cwB64Encode`, `cwB64Decode`, `cwStripWhitespace`, `cwVarIntHex`, `cwHexListHas`, `cwSigsList`, `cwWifInfo`, `cwMnemonicStrength`, `cwMnemonicWordCount`, `cwUnixDate`, `cwVersion` |

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
instead. `tools/check-wallet-vectors.py` re-runs every vector under the engine's
rule so it cannot be forgotten.

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
* **a tor daemon** is optional, and only the Tor backends want it.
* **Bitcoin Core** 26 or later is optional, and only the Core backends want it.

The wallet opens on testnet with BIP-39's public test mnemonic already in the
seed box. That phrase's funds are burned by design. Do not type one that guards
real coins into this stack.

Run the vector gate with:

```sh
cd coinxt && python3 tools/check-wallet-vectors.py
```

It builds the native shim from `native/coinxt.c`, so it needs a C compiler; with
none, it runs the constant checks and says loudly that it skipped the rest.

### The next engine pass, shortest feedback first

Each step names what green looks like. The legs the 2026-09-03 logs already
closed (the silent-payment send, an inscription commit and reveal through the
autotest, the vault paid and its coin withheld) are left out. Silent-payment
receiving and the Bitcoin Core backends are separate sessions (the suite work
plan's coinxt engine rows).

1. **Boot.** Open the stack; the boot self-check prints its own record with no
   FAIL line. It flips nothing new, but everything below depends on it.
2. **Tools, Inspect.** Paste any `lnbc...` invoice: the payee node key, the
   amount and the fields are read out. Then, with a mainnet backend chosen on
   Network, a transaction id known to carry a runestone (any Runes etching or
   transfer; block 840,000 onward): the runestone is read under its OP_RETURN
   output. Flips BOLT11 and Runes.
3. **Ordinals screen.** Type `hello` as text and press "1. Prepare the commit
   address": the commit address joins Addresses. Save the wallet and reopen
   it: the commit and its recipe are still there. Fund it on signet or
   testnet4, press "2. Sign the reveal", then Broadcast: an explorer that reads
   inscriptions shows it at `<txid>i0`. Flips the screen and the saved recipe.
4. **Vault screen.** Prepare the locked address for a height a few blocks
   ahead and pay it from Send; Coins shows `LCK`. Before the height a MAX
   spend leaves it out; after the height a manual spend of it signs with the
   raised locktime, and a node accepts the broadcast. Flips the release after the height (the
   autotest skipped it).
5. **Tools, BIP-322.** Sign with a taproot wallet's first address and verify the
   result in Bitcoin Core's `verifymessage` or in Sparrow. Flips signed
   messages (the autotest skipped it on a p2pkh wallet).
6. **Testnet4 and labels.** Choose testnet4 with mempool.space's `/testnet4`
   backend and sync; export BIP-329 labels on Settings and import the file into
   a fresh open: the address labels and frozen coins come back. Flips testnet4
   and BIP-329.

Every other line of "What has not run on an engine or a node" above flips when
a pasted log shows it once. What comes back from an engine goes into
`CLAUDE.md`'s evidence ledger, dated, and that list shrinks by the line.
