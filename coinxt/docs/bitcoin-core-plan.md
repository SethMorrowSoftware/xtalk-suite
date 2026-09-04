# Bitcoin Core as a backend: the upgrade plan

**Status: written 2026-09-03 as a plan; phases 1 to 4 landed as code on
2026-09-04** - the `core-rpc`, `core-tor` and `core-cli` backends, the chain
guard, tip and fees, the `addr()` scan tier, the watch tier (createwallet,
importdescriptors with a birth date, listunspent, listtransactions, rescan
progress and the re-import on derive), the Node screen, the mempool and
`testmempoolaccept` cards, and the regtest sandbox. See [wallet.md](wallet.md),
"Bitcoin Core as a backend" and "The Node screen". Most of phase 5
went with them: the PSBT and address cross-checks on Tools
(`validateaddress`, `getdescriptorinfo`, `analyzepsbt`), the mempool card,
`testmempoolaccept`, `core-tor`, and a fee bump priced from the node's own
ancestor package. **Nothing described here has met a node**; what is left of
the plan is `verifymessage`, JSON-RPC batching for Core, and every claim
below that only a real node can settle. This document is
the design and the
order of work for making the CoinXT Wallet talk to a person's own Bitcoin Core
node - local or self-hosted - for everything a node can do for a wallet, and
for a few things only a node can do (mining on regtest, mempool policy checks,
reorg drills). It is written against the wallet as it stands in
[wallet.md](wallet.md) and follows every rule in [`../CLAUDE.md`](../CLAUDE.md)
that a new transport has to follow: pure script, ASCII, one paste-and-run
file, the kit look, the control registry, the UI-version fingerprint, the boot
gate's modelled transports, and the honesty labels.

## 1. What "Core" means here

Bitcoin Core 26 or later with descriptor wallets (the default since 23), spoken
to over its JSON-RPC interface. Chains and their default RPC ports:

| wallet network | Core chain name | RPC port | data directory |
|---|---|---|---|
| mainnet | main | 8332 | `~/.bitcoin` |
| testnet | test | 18332 | `~/.bitcoin/testnet3` |
| testnet4 | testnet4 | 48332 | `~/.bitcoin/testnet4` (Core 28+) |
| signet | signet | 38332 | `~/.bitcoin/signet` |
| regtest | regtest | 18443 | `~/.bitcoin/regtest` |

The wallet already has all five networks on the Wallet screen. The chain guard
that refuses a backend serving the wrong chain (the boot gate's "chain guard"
checks) extends to Core: `getblockchaininfo.chain` must equal the wallet's
network or the backend is refused with both names in the message.

## 2. Two channels, and when each is used

**Channel A: JSON-RPC over HTTP (the integrated path, the default).** POST to
`http://host:port/` (or `/wallet/<name>` for wallet calls) with basic auth,
one JSON-RPC 1.0 request per POST or a batch array. Works for a local node, a
node on the LAN, a node behind an SSH tunnel, and a node published as an onion
service (Section 6). No binary on the machine is needed. This is the path every
screen uses.

**Channel B: `shell("bitcoin-cli ...")` (the zero-config and lifecycle path).**
LiveCode's `shell()` runs a command and returns its output. It is used only
where it saves real time or where RPC cannot reach:

- **Zero configuration.** A person who already has `bitcoin-cli` working
  (`bitcoin-cli -testnet getblockchaininfo` answers) has told the wallet
  everything: the binary finds the data directory, the cookie and the port on
  its own. The Network screen's "Use bitcoin-cli" choice needs no host, port
  or password, and the wallet reads the same answers it would read over RPC.
- **Node lifecycle.** Starting a node cannot be done over RPC because there is
  no node yet: the regtest sandbox (Section 8) runs `bitcoind -regtest
  -daemon` and `bitcoin-cli -regtest stop`, and `bitcoin-cli -rpcwait` is the
  cheapest "wait until it answers".
- **Never for keys or coins.** No command that moves funds or touches private
  keys is ever run through either channel; this wallet signs its own
  transactions and Core holds a watch-only wallet at most.

Rules for channel B, because a shell is a sharp tool:

1. **An allowlist, built from constants.** Every command is assembled from a
   fixed verb table (`kWaCliVerbs`: `getblockchaininfo`, `getblockcount`,
   `estimatesmartfee`, `scantxoutset`, `listunspent`, `listtransactions`,
   `gettransaction`, `getrawtransaction`, `sendrawtransaction`,
   `testmempoolaccept`, `getmempoolentry`, `getnetworkinfo`, `getwalletinfo`,
   `getindexinfo`, `createwallet`, `importdescriptors`, `generatetoaddress`,
   `invalidateblock`, `reconsiderblock`, `stop`). A method not in the table is
   never run, whatever a field says.
2. **Arguments are quoted by one function** (`waCliQuote`): single quotes on
   POSIX, double quotes on Windows, and a value containing a quote, a newline
   or a shell metacharacter outside hex, base58, bech32 and JSON is refused
   before the shell sees it. Descriptors, JSON payloads and hex are the only
   argument shapes; all of them pass that filter.
3. **`-named` and `-stdin` for anything long.** `importdescriptors` payloads and
   raw transactions go through stdin (`echo` is not used; LiveCode's `shell`
   has no stdin, so long arguments are written to a temporary file and passed
   with `-rpcclienttimeout=N` and, where the version allows, read back from
   the file rather than the command line). Where a payload cannot be passed
   safely, channel B refuses and says to use channel A.
4. **`shell()` blocks the engine.** Every call carries `-rpcclienttimeout`, the
   wallet paints "asking bitcoin-cli ..." before it calls and never calls from
   a timer, and on Windows `the hideConsoleWindows` is set so no console
   flashes. A call that takes longer than a few seconds (a rescan, a scan of
   the UTXO set) is not made through the shell at all; it goes over RPC where
   the wallet can poll `getwalletinfo.scanning` and keep painting.
5. **Output is JSON or a refusal.** The wallet parses stdout with
   `cwJsonParse`; a non-JSON answer (a usage message, "could not connect",
   "error code: -28") is shown whole on the Node screen and logged, never
   interpreted.
6. **The binary is found once and shown.** `which bitcoin-cli` (POSIX) or
   `where bitcoin-cli` (Windows), its `-version`, and the resolved data
   directory are printed on the Node screen so a wrong binary is visible.

## 3. Capability map

What each wallet feature asks the node for, in both channels, and which tier
(Section 5) it needs. "cli" means the same call through `bitcoin-cli`.

| wallet feature | RPC (channel A) | tier | notes |
|---|---|---|---|
| chain tip | `getblockcount`, `getbestblockhash` | any | `getblockchaininfo` once per sync for chain, headers, IBD, pruned, verification progress |
| fee estimates | `estimatesmartfee 1/6/144` (economical), `getmempoolinfo.mempoolminfee` | any | the floor for a replacement is the node's own policy, not a guess |
| coins (scan tier) | `scantxoutset "start" [descriptors]` | scan | one call, whole UTXO set, no history, no mempool; works on pruned nodes |
| coins (watch tier) | `listunspent 0 9999999 [] true` on the watch wallet | watch | includes mempool coins at 0 confirmations |
| history | `listtransactions "*" N 0 true`, `listsinceblock` | watch | one call replaces the per-address history requests |
| transaction bytes | `gettransaction txid true` (watch), `getrawtransaction txid false` (needs `txindex=1` for foreign transactions) | watch or txindex | the Inspect and CPFP paths; the scan tier says "needs txindex" instead of fetching |
| broadcast | `testmempoolaccept [hex]` then `sendrawtransaction hex maxfeerate` | any | a replacement paying too little is refused by the node with its reason before it is sent |
| fee bump pricing | `getmempoolentry txid` (fees.ancestor, ancestorsize, descendants) | any | CPFP pays for the whole ancestor package as the node sees it |
| PSBT | `decodepsbt`, `analyzepsbt`, `utxoupdatepsbt`, `finalizepsbt` | any | cross-checks on Tools; the wallet still signs |
| address validation | `validateaddress`, `getdescriptorinfo` | any | the descriptor checksum on the Wallet screen is re-derived by the node |
| message verification | `verifymessage` (P2PKH only) | any | a second opinion on the 2011 format; BIP-322 stays in the wallet |
| labels | `importdescriptors` labels, `setlabel` | watch | BIP-329 stays the interchange format; Core's labels mirror it |
| mempool watch | `getrawmempool`, `getmempoolentry` | any | History rows show "in the node's mempool" or "not in the mempool" |
| block watch | poll `getbestblockhash` each tick; `waitfornewblock` is never used (it blocks) | any | a new block re-reads confirmations |
| node status | `getblockchaininfo`, `getnetworkinfo`, `getpeerinfo` (count only), `getindexinfo`, `uptime` | any | the Node screen |
| regtest mining | `generatetoaddress N address` | any (regtest only) | refused on every other chain by the wallet, whatever the node allows |
| reorg drill | `invalidateblock`, `reconsiderblock` | any (regtest only) | proves the wallet's reorg handling on demand |
| node lifecycle | channel B only: `bitcoind -daemon`, `bitcoin-cli stop`, `-rpcwait` | sandbox | Section 8 |

Not on the map, and why: BIP-352 silent payment RECEIVING (Core has no tweak
index; the wallet's sending side needs nothing from the node beyond coins);
`bumpfee`/`psbtbumpfee` (they need Core's keys or Core's coin selection; the
wallet builds its own replacement); `sendtoaddress` and every other spending
call (never); ZMQ notifications (no ZMQ client in script; polling is enough at
one call per tick); `rescanblockchain` is used only as the watch wallet's own
first import, never on a schedule.

## 4. The transport

`core-rpc` is a fourth transport beside `esplora-clear`, `esplora-tor`,
`electrum-clear` and `electrum-tor`, and `core-cli` a fifth that shares its
request shapes and reply handling. The request kinds the sync machine already
uses (`tip`, `fees`, `history`, `utxos`, `tx`, `broadcast`) keep their names; a
seventh, `rpc`, carries a method and params for the Node screen's calls that
have no wallet-side kind (mining, mempool entries, node status).

**HTTP over the socket transport.** The clearnet Electrum path owns a socket
and a line-framed reader; the Tor Esplora path already parses HTTP status
lines, headers and bodies out of a stream. Core's server is HTTP/1.1 with
keep-alive (idle connections are closed after `rpcservertimeout`, 30 seconds
by default, which the wallet treats exactly like the Electrum server closing an
idle stream: the next request dials again, nothing is counted). Each request
is one POST:

    POST /wallet/coinxt-<fingerprint> HTTP/1.1
    Host: 127.0.0.1:18443
    Authorization: Basic <base64 of user:password or cookie>
    Content-Type: application/json
    Content-Length: N
    Connection: keep-alive

    {"jsonrpc":"1.0","id":<n>,"method":"...","params":[...]}

The reply is `Content-Length`-framed JSON (Core does not chunk). Batches are
JSON arrays, answered by arrays, with the same id correlation the Electrum
batching already does and the same halving on refusal.

**Errors, mapped once.** HTTP 401 is "the node refused the credentials";
403 is "the node does not allow this address" (`rpcallowip`); 404 on a wallet
path is "no wallet of that name is loaded" (Section 5); 500 carries a JSON
error object whose code is mapped: -28 "the node is still starting (loading
block index or verifying); try again in a moment", -5 "not found", -25, -26
and -27 for `sendrawtransaction` (missing inputs, policy rejection with the
node's own text, already in chain), -8 for parameter errors (a wallet bug,
logged whole). Every mapped message keeps the node's text after a colon.

**Authentication.** Two forms, chosen on the Network screen: a cookie file
path (read fresh at every dial, because the cookie rotates when the node
restarts; the default path follows the chain table above) or `user:password`
(`rpcauth` on the node side). The Authorization header is REDACTED in the log:
the log line for a request prints the method and params, never the headers.
Credentials live in the stack's custom properties with the other Network
settings, never in the wallet file, and the wallet file's `waSerializeWallet`
is asserted by the boot gate never to contain them.

**One wallet name per account.** Wallet calls go to
`/wallet/coinxt-<master fingerprint>` so two accounts on one node never share
a watch wallet. The wallet never calls `unloadwallet` on a name it did not
create and never `createwallet` over an existing one (it uses the existing
one and says so).

**Chain guard.** `getblockchaininfo.chain` is compared to the wallet's
network before anything else is asked, and on every reconnect; a mismatch
refuses the backend the way a wrong Esplora root is refused today. IBD
(`initialblockdownload true`) is not a refusal, but the Node screen and the
rail pill say "syncing, N% verified" and coins are labelled provisional.

## 5. Two tiers of node wallet

**Scan tier (no wallet in Core).** One `scantxoutset` over the account's two
descriptors, each with a range of `[0, derived - 1]`, plus one `addr(...)`
entry per prepared leaf (inscription commits and timelocks live outside the
descriptor ranges). Returns every unspent output with height and amount in one
answer. No history, no mempool: a payment arriving at the wallet is invisible
until it confirms, and the Coins screen says so in its detail text. The scan
takes tens of seconds on a mainnet UTXO set and a second on regtest; it runs
as one request with the deadline-for-silence rule (the request is not timed
out while `scantxoutset "status"` reports progress). This tier is the one that
works on a pruned node and needs nothing set up on the node side.

**Watch tier (a watch-only descriptor wallet in Core).** On first use:

1. `createwallet "coinxt-<fp>" true true "" false true` (disable private keys,
   blank, descriptors, no autoload: the wallet loads it by name at each dial
   with `loadwallet`, and unloads nothing).
2. `importdescriptors` with four kinds of entry: the receive descriptor
   (`range [0, N]`, `internal false`, `active false`), the change descriptor
   (`internal true`), one `addr(<address>)` entry per prepared leaf, and a
   `timestamp` that is the wallet's birth (a new field in the wallet file,
   `birth\t<unix time>`, written at creation and asked for on restore: "when
   was this seed first used? An earlier date is safe, a later one loses
   history"). `"now"` for a wallet created in this session.
3. Poll `getwalletinfo.scanning` and paint "rescanning: N%" on the Node screen
   and the rail pill until it is false; a pruned node that cannot rescan far
   enough answers with an error the wallet shows whole, and offers the scan
   tier instead.
4. Thereafter a sync is three calls: `getblockchaininfo`, `listunspent 0`, and
   `listtransactions "*" 500 0 true` (paged by 500 when a page is full), with
   `gettransaction txid true` on demand for bytes. Unconfirmed coins arrive
   with 0 confirmations and the wallet's own broadcast memory (the `SPT` mark)
   still applies between syncs.
5. When the Addresses screen derives past the imported range, the wallet
   re-imports the two descriptors with the larger range (Core extends ranges
   only for active descriptors, and these are inactive on purpose), and
   imports each new leaf as it is prepared.

The tier is chosen on the Network screen; the default is the scan tier because
it changes nothing on the node, and the screen says in one line what the watch
tier adds and costs.

## 6. Remote and onion nodes

A node on another machine is reached the same way over the LAN or an SSH
tunnel (host and port fields; the wallet refuses to send credentials to a
non-local clearnet host unless the person ticks "I know this is not
localhost", and says why). A node published as an onion service is reached
through OnionXT the way Esplora over Tor is today: the HTTP framing is the
same, only the stream differs, so `core-tor` is the same transport over a Tor
stream and is the one honest way to use a home node from elsewhere. Channel B
has no remote form.

## 7. The Node screen

A thirteenth screen, `nd_`, a kit adopter like the others, in the control
registry and the UI-version fingerprint:

- **Status card:** chain, blocks and headers (and "N behind" when they
  differ), verification progress during IBD, pruned or not (and the prune
  height), `txindex` on or off (from `getindexinfo`), peers (count), uptime,
  the node's version, the transport in use and the wallet name loaded.
- **Fees card:** the node's estimates for 1, 6 and 144 blocks and the mempool
  minimum, with a button that writes the chosen one into the Send screen's
  rate field.
- **Mempool card:** for the History screen's selected transaction, its
  mempool entry (fee, size, ancestors, descendants, time in mempool) or
  "not in this node's mempool", and a Test button that runs
  `testmempoolaccept` on the last signed transaction and prints the verdict.
- **Watch wallet card (watch tier):** created or not, descriptors imported,
  range, rescan progress, a Re-import button, and the birth date.
- **Regtest card (regtest only, Section 8):** mine N blocks to this wallet,
  mine to a foreign address, invalidate the tip and reconsider it, start and
  stop the sandbox node, and the sandbox's data directory.
- The honesty footer, like every screen.

The Network screen gains the backend choices (`Core (RPC)`, `Core
(bitcoin-cli)`, `Core over Tor`), host, port, auth mode and value, cookie
path, wallet name (read-only, derived), tier, and the Test button asks
`getblockchaininfo` and prints chain, blocks and whether the chain matches.

## 8. The regtest sandbox

The reason to build any of this first. With a regtest node the autotest
script's whole chain phase runs in minutes and needs no faucet:

1. **Start:** `shell("bitcoind -regtest -daemon -datadir=<sandbox>
   -fallbackfee=0.0001 -rpcport=18443")` into a directory the wallet creates
   beside its wallet file (or a temporary one), then `bitcoin-cli -regtest
   -datadir=<sandbox> -rpcwait getblockchaininfo` until it answers. The
   Node screen shows the directory and the process's answer.
2. **Fund:** `generatetoaddress 101 <first receive address>` (coinbase
   maturity is 100 blocks), then a sync: the wallet holds 50 BTC of regtest
   coin and every feature that spends is live.
3. **Confirm on demand:** a "Mine 1 block" button, and the autotest calls the
   same handler between steps: the commit funds, the reveal confirms, the
   vault reaches its height with `generatetoaddress 12`, the CPFP child and
   its parent confirm together, and the summary is complete in one press.
4. **Reorg drill:** `invalidateblock <tip>` then mine two blocks on the
   shorter chain and `reconsiderblock`; the History screen's confirmations
   must move down and back up, coins must leave and return, and the boot
   gate's reorg fixtures get a real counterpart.
5. **Stop:** `bitcoin-cli -regtest -datadir=<sandbox> stop`; the wallet
   never deletes the directory itself.

The sandbox is refused outside regtest by the wallet before the shell is
reached, and every sandbox command is logged whole (minus nothing: regtest
has no secrets).

## 9. Gates and proof

The boot gate models every transport headlessly and this one is no different:

- **The HTTP framing** is driven through the modelled socket world: a POST is
  asserted byte for byte (method, path, `Content-Length`, the auth header
  present and REDACTED in the log), a `Content-Length` reply is parsed, a
  keep-alive reuse and an idle close are both driven, and 401, 403, 404, 500
  with each mapped code are answered and their messages checked.
- **The sync plan** is asserted as a request list: scan tier is one call with
  the two descriptors (checksums re-derived by the oracle, which already
  computes Core's descriptor checksum) and one `addr()` per leaf; watch tier
  is the three calls, paged.
- **The reply shapes** are fixtures: a `scantxoutset` answer, a `listunspent`
  answer with a 0-confirmation coin, a `listtransactions` page, a
  `gettransaction` with hex, an `estimatesmartfee` with and without an
  estimate, a `getmempoolentry`, a `testmempoolaccept` refusal.
- **Channel B** is modelled by a `shell` stand-in in the interpreter that
  records the exact command line and answers a fixture; the allowlist is
  mutation-tested (a verb outside the table is refused, an argument with a
  quote is refused, a non-JSON answer is shown not parsed), and no fixture
  ever contains a key.
- **The chain guard, the tier switch, the wallet name, the credentials
  never in the wallet file, the regtest-only refusals** are each a check.
- **Coverage:** every new `wa*` handler is reached by the gate or listed with
  a reason, per the suite's coverage ratchet.

Proof on a real node is the cheapest engine pass this project has: a regtest
node on the maintainer's machine, the sandbox started from the Node screen,
the autotest pressed once. The runbook gets a section for it, and every
honesty label in this plan flips from "Not run on a node" only on that
record.

## 10. Phases

| phase | delivers | needs a node | gate additions |
|---|---|---|---|
| 0. spike | HTTP POST over the socket client to a local regtest node: framing, auth, one `getblockchaininfo`; an engine pass on the maintainer's machine settles the framing questions in Section 11 | yes (regtest) | none yet; the spike is a scratch stack |
| 1. transport and Node screen | `core-rpc` and `core-cli`, the Network screen fields, the chain guard, tip and fees, `testmempoolaccept` and broadcast, the status card | regtest | framing, errors, redaction, chain guard, shell allowlist |
| 2. scan tier | coins via `scantxoutset` with leaves, balance and Send working, the Coins screen's "no mempool on this tier" note | regtest | the scan plan, the reply fixture, the leaf `addr()` entries |
| 3. watch tier | create and import, birth date in the wallet file, rescan progress, history, mempool coins, bytes on demand, re-import on derive | regtest, then testnet4 for a real rescan | the import payload, paging, progress, the pruned refusal |
| 4. regtest sandbox | start, fund, mine, reorg drill, stop; the autotest's chain phase self-contained | regtest | the sandbox refusals, the shell command lines |
| 5. depth | mempool card, PSBT cross-checks, `validateaddress` and `getdescriptorinfo` on Tools, `verifymessage`, `core-tor`, RPC batches, block watch | regtest, an onion node for `core-tor` | one fixture per call |

Phases 1 and 2 are each on the order of the Electrum transport that landed in
the week of 2026-09-01: a day or two of script with the gate, plus an engine
pass. Phase 3 is the same again; phase 4 is smaller; phase 5 is a list of
afternoons. Phase 0 comes first because it costs an hour and answers the
questions below with facts instead of guesses.

## 11. Open questions and risks

- **HTTP/1.1 over a LiveCode socket.** Keep-alive, `Content-Length` framing of
  large replies (a `listtransactions` page can be a megabyte), and the
  engine's socket buffer behaviour under that load are the spike's questions.
  The fallback is `Connection: close` per request, which costs a dial each
  time and nothing else.
- **`shell()` blocks.** A stalled `bitcoin-cli` stalls the engine until its
  own timeout; the rules in Section 2 keep every shell call short, but a
  person who chooses channel B is choosing that trade, and the Network screen
  says so.
- **Windows.** Console flashes (`hideConsoleWindows`), path quoting, the
  cookie under `%APPDATA%\Bitcoin`, and `where` instead of `which`. Channel A
  has none of these.
- **Pruned nodes** cannot rescan pruned history: the watch tier's import fails
  past the prune height, and the wallet must offer the scan tier with the
  reason rather than a generic error.
- **Core versions.** `scantxoutset` since 0.17; descriptor wallets default
  since 23; testnet4 since 28; miniscript inside `tr()` since 26 for the
  timelock leaves, but inscription envelopes are not descriptors, so every
  leaf is imported as `addr()` regardless.
- **Ranges.** Inactive descriptors do not extend themselves; the re-import on
  derive is the wallet's job and the gate must refuse a derive that does not
  re-import.
- **Credentials.** In custom properties with the Network settings, redacted
  in the log, never in the wallet file, never sent to a non-local clearnet
  host without the explicit tick.
- **The one-file demo.** A sixth transport and a thirteenth screen add
  perhaps two thousand lines to a file that is already large; the embed order
  and the UI fingerprint handle it, but the About text and the runbook must
  say where the new things are, which the 2026-09-04 discoverability lesson
  in `../CLAUDE.md` makes a requirement rather than a courtesy.

Not run on a node: the parts that are code say so in wallet.md, and the rest
is a plan, as the top of this document says.
