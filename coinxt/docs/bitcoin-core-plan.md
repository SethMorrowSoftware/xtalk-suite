# Bitcoin Core as a backend: the design

**Status.** Written 2026-09-03 as a plan; phases 1 to 4 and most of phase 5 were built on 2026-09-04: the
`core-rpc`, `core-tor` and `core-cli` backends, the chain guard, tip and fees, the `addr()` scan tier, the
watch tier (createwallet, importdescriptors with a birth date, listunspent, listtransactions, rescan
progress and the re-import on derive), the Node screen, the mempool and `testmempoolaccept` cards, the
regtest sandbox, the Tools cross-checks (`validateaddress`, `getdescriptorinfo`, `analyzepsbt`) and a
fee bump priced from the node's ancestor package. [wallet.md](wallet.md), "Bitcoin Core as a backend,
and the Node screen", describes what was built; this file keeps the design reasoning, the parts that
differ from the build, what is out of scope and why, and the questions only a real node can answer.
All of it is gated headlessly against modelled sockets, streams and a modelled shell; the Core backends
have not yet been run against a real node. Not built: a `verifymessage` second opinion, JSON-RPC
batching for Core, and a Node-screen card for the sandbox's own mining address (tracked, with the
real-node session, in the suite's docs/WORK-PLAN.md).

The rules a new transport follows are the wallet's own (pure script, ASCII, one paste-and-run file, the
kit look, the control registry, the UI-version fingerprint, the boot gate's modelled transports, and
the honesty labels); see [`../CLAUDE.md`](../CLAUDE.md).

## 1. What "Core" means here

Bitcoin Core 26 or later with descriptor wallets (the default since 23), spoken to over JSON-RPC.
`scantxoutset` exists since 0.17; testnet4 since 28.

| wallet network | Core chain name | RPC port | data directory |
|---|---|---|---|
| mainnet | main | 8332 | `~/.bitcoin` |
| testnet | test | 18332 | `~/.bitcoin/testnet3` |
| testnet4 | testnet4 | 48332 | `~/.bitcoin/testnet4` |
| signet | signet | 38332 | `~/.bitcoin/signet` |
| regtest | regtest | 18443 | `~/.bitcoin/regtest` |

`getblockchaininfo.chain` must equal the wallet's network, or the backend is refused with both names in
the message; the node's answer outranks this port table.

## 2. Two channels, and when each is used

**Channel A: JSON-RPC over HTTP** (the default): a POST with basic auth to `http://host:port/` (or
`/wallet/<name>` for wallet calls). It serves a local node, a LAN node, a node behind an SSH tunnel, and
a node published as an onion service (section 6). No binary is needed on the machine.

**Channel B: `shell("bitcoin-cli ...")`**, only where it saves real time or RPC cannot reach: zero
configuration (a working `bitcoin-cli` has already found the data directory, cookie and port), and node
lifecycle (the regtest sandbox starts `bitcoind` and uses `bitcoin-cli -rpcwait`, because there is no
node to speak RPC to yet). Never for keys or coins, through either channel: this wallet signs its own
transactions, and Core holds a watch-only wallet at most.

The channel-B rules, as built:

1. **An allowlist built from constants.** Every RPC method comes from `kWaCoreMethods` (the plan named it
   `kWaCliVerbs`); a method not in it is never run, whatever a field says. One parameter builder,
   `waCoreParams`, serves both channels.
2. **Quoting by one function** (`waCliQuoteFor`, its shell style a parameter so both styles are
   gated): single quotes on POSIX, where a JSON payload passes untouched. On Windows a structured
   argument is REFUSED, with `core-rpc` named as the remedy, rather than double-quoted as planned: an
   escaping scheme this suite cannot test is not one it ships. So the scan, the import, listunspent and
   testmempoolaccept are RPC-only on Windows.
3. **`shell()` blocks the engine.** Every call carries `-rpcclienttimeout`; cli requests run from a
   button press and never from the poll tick; `the hideConsoleWindows` is set on Windows.
4. **Output is JSON or a refusal**: parsed with `cwJsonParse`; anything else is shown whole and logged,
   never interpreted.

## 3. Capability map

| wallet feature | RPC | tier |
|---|---|---|
| chain, tip, pruning, initial download | `getblockchaininfo` | any |
| fee estimates | `estimatesmartfee` 1 / 6 / 144 | any |
| coins | `scantxoutset` (scan); `listunspent` on the watch wallet, mempool coins at 0 confirmations (watch) | scan / watch |
| history | `listtransactions` | watch |
| transaction bytes | `gettransaction` (watch), `getrawtransaction` (foreign transactions need `txindex=1`) | watch or txindex |
| broadcast | `sendrawtransaction`; `testmempoolaccept` on the Node screen | any |
| fee bump pricing | `getmempoolentry` (the ancestor package) | any |
| PSBT, address and descriptor cross-checks | `analyzepsbt`, `validateaddress`, `getdescriptorinfo` | any |
| regtest mining and reorg drill | `generatetoaddress`, `invalidateblock`, `reconsiderblock`, through the sandbox's `bitcoin-cli` | regtest only |

**Out of scope, and why.** BIP-352 silent-payment RECEIVING via Core: Core has no tweak index.
`bumpfee` / `psbtbumpfee`: they need Core's keys or Core's coin selection; the wallet builds its own
replacement. `sendtoaddress` or any other spending call: never. ZMQ notifications: there is no ZMQ
client in script, and polling is enough. `waitfornewblock`: never, it blocks. `rescanblockchain`: only as
the watch wallet's own first import, never on a schedule.

## 4. The transport

`core-rpc` sits beside the Esplora and Electrum transports and keeps their request kinds (`tip`, `fees`,
`history`, `utxos`, `tx`, `broadcast`), plus `rpc` for Node-screen calls. Each request is one POST
(`{"jsonrpc":"1.0","id":<n>,"method":...,"params":[...]}`) down a kept-alive socket; Core closes an idle
connection after `rpcservertimeout` (30 s by default), and the next request dials again with nothing
counted. Errors are mapped once: HTTP 401 (credentials), 403 (`rpcallowip`), 404 (no such wallet
loaded), and in a 500 the RPC code: -28 still starting, -5 not found, -25 / -26 / -27 for
`sendrawtransaction` (missing inputs, policy with the node's text, already in chain), -8 a parameter
error (a wallet bug, logged whole). The node's text is kept after a colon.

**Credentials**: a cookie file read fresh at every request (it rotates when the node restarts), or
`user:password`; the Authorization header never reaches the log (method and size only); credentials live
with the Network settings and never in the wallet file, which the boot gate asserts. Wallet calls go to
`/wallet/coinxt-<master fingerprint>`, so two accounts on one node never share a watch wallet; the wallet
never unloads a wallet it did not create and never creates over an existing one.

## 5. Two tiers of node wallet

**Scan tier** (nothing set up on the node; the default): ONE `scantxoutset` with an `addr()` entry per
address and per prepared leaf. The plan used the account's two ranged descriptors; the build uses
`addr()` throughout, so leaves and derived addresses take one path. No history, no mempool: a payment on
its way is invisible until it confirms. Works on a pruned node.

**Watch tier** (a watch-only descriptor wallet in Core): `createwallet` with private keys disabled and
blank; `importdescriptors` of every address and leaf as `addr()` with a `timestamp` that is the wallet's
birth (asked for on restore, never guessed; an earlier date is safe, a later one loses history); rescan
progress from `getwalletinfo`; thereafter a sync is `getblockchaininfo`, `listunspent` and
`listtransactions`. When the address window grows past what was imported, the next sync re-imports before
it asks anything, because a wallet watching some of its addresses reports a balance missing the rest.

## 6. Remote and onion nodes

A LAN node or an SSH tunnel uses the host and port fields; the wallet sends credentials to a non-local
clearnet host only after an explicit tick, because Core's RPC is unencrypted. A node published as an
onion service is `core-tor`: the same HTTP framing over an OnionXT stream, with no default onion (there
is no public Core onion) and never inheriting a public explorer's onion as the node host. Channel B has
no remote form.

## 7. The Node screen

The thirteenth screen (`nd_`), a kit adopter in the control registry and the UI fingerprint: status
(chain, blocks and headers, pruning, initial download, version, peers), fees for 1 / 6 / 144 blocks with
buttons that write into Send, the watch-wallet controls, the mempool card with Test, and the regtest
sandbox. [wallet.md](wallet.md) describes each as built.

## 8. The regtest sandbox

The reason to build any of this first: with a regtest node every screen that spends is exercisable
without a faucet or a ten-minute block. Start makes `bitcoind -regtest` in a directory beside the wallet
file and waits with `-rpcwait`; Mine pays six blocks to this wallet's first address; Reorg invalidates
the tip, mines a longer chain and reconsiders the old block; Stop stops the node and never deletes the
directory. Every sandbox command is refused by name outside regtest before a program runs, and logged
whole (regtest has no secrets).

## 9. Gates and proof

The boot gate (`tools/check-wallet-boot.py`) models every transport headlessly: the POST is asserted byte
for byte (path, `Content-Length`, the auth header present and absent from the log); `Content-Length`
replies, keep-alive reuse and the idle close are driven; 401 / 403 / 404 and each mapped RPC code are
answered and their messages checked; the scan and watch request lists are asserted; the reply shapes
(`scantxoutset`, `listunspent` with a 0-confirmation coin, a `listtransactions` page, `gettransaction`,
`estimatesmartfee` with and without an estimate, `getmempoolentry`, a `testmempoolaccept` refusal) are
fixtures; channel B runs through a `shell` stand-in that records the exact command line, with the
allowlist, the quoting refusals and the non-JSON path each checked; and the chain guard, the tier
switch, the wallet name, the credentials-never-in-the-file rule and the regtest-only refusals are each a
check. No fixture contains a key.

**Proof on a real node** is the cheapest engine pass this member has: a Bitcoin Core 26+ regtest node on
the maintainer's machine, the sandbox started from the Node screen, the wallet's autotest pressed once,
then `core-rpc` and `core-cli` against the same node, and `core-tor` once the node is published as an
onion. Every "not run against a node" label in wallet.md flips only on that record.

## 10. Phases

| phase | delivered | state |
|---|---|---|
| 0. spike | framing, auth and one `getblockchaininfo` against a real regtest node | not done: it needs a node on the maintainer's machine |
| 1. transport and Node screen | `core-rpc`, `core-cli`, the Network fields, the chain guard, tip and fees, broadcast, `testmempoolaccept`, the status card | built 2026-09-04 |
| 2. scan tier | coins via `scantxoutset`, Send working, the no-mempool note | built 2026-09-04 |
| 3. watch tier | create and import, birth date, rescan progress, history, mempool coins, re-import on derive | built 2026-09-04 |
| 4. regtest sandbox | start, mine, reorg, stop | built 2026-09-04 |
| 5. depth | mempool card, PSBT / address / descriptor cross-checks, `core-tor`, the package-priced bump | built 2026-09-04, except `verifymessage` and RPC batches |

## 11. Open questions and risks (what only a real node settles)

- **HTTP/1.1 over a LiveCode socket**: keep-alive, and `Content-Length` framing of large replies (a
  `listtransactions` page can be a megabyte) under the engine's socket buffering. The fallback is
  `Connection: close` per request, which costs a dial each time and nothing else.
- **`shell()` blocks**: a stalled `bitcoin-cli` stalls the engine until its own timeout. Choosing
  channel B is choosing that trade, and the Network screen says so.
- **Windows**: console flashes (suppressed with `hideConsoleWindows`), the cookie under
  `%APPDATA%\Bitcoin`, `where` instead of `which`, and the structured-argument refusal above. Channel A
  has none of these.
- **Pruned nodes** cannot rescan past their prune height: the watch tier's import fails there, and the
  wallet must offer the scan tier with the reason rather than a generic error.
- **Ranges**: the imports are inactive, so they never extend themselves; the re-import on derive is the
  wallet's job, and the boot gate checks that a grown window is re-imported first. How long a real
  rescan takes, and what a real node answers to a re-import, are for the real-node session.
