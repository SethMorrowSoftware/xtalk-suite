script "coinXTWallet"

-- coin-wallet.livecodescript - CoinXT Wallet: a full Bitcoin wallet in one
-- paste-and-run stack, modelled on Electrum.
--
-- WHAT IT IS. The whole wallet surface CoinXT makes possible, on ten screens:
--
--   Wallet     create a new seed, restore one, watch an xpub/ypub/zpub/tpub,
--              import a single key, or build an m-of-n multisig; four
--              networks (mainnet, testnet, signet, regtest) and five script
--              types (legacy, nested SegWit, native SegWit, taproot, P2WSH
--              multisig)
--   Receive    the next unused address, its BIP-21 URI and a scannable QR
--   Addresses  the derived receive and change chains with labels, use and
--              balance, and a gap-limit scan
--   Send       pay one address or many, choose a fee rate, opt into RBF, set
--              a locktime, control which coins are spent, and see the fee
--              and the change before anything is signed
--   Coins      the UTXO set, with freeze and unfreeze
--   History    transactions with confirmations, amounts, fee and labels
--   Tools      sign and verify a message, load/sign/combine/finalize a PSBT,
--              inspect any raw transaction, sweep a private key, export a
--              descriptor or an account key, and BIP-39 conversions
--   Network    which backend, over what transport, and what it last said
--   Log        every request and response, so nothing the wallet did is
--              invisible
--   Settings   the wallet file, its password, the gap limit, the display
--              unit, and the honesty record
--
-- WHAT IT IS NOT. It is not a custody solution, and this is not modesty.
-- OXT script variables are not locked memory: a seed typed into this stack
-- can be paged to disk by the operating system, and any process that can read
-- this one's memory can read the key. That is the machine's trust boundary,
-- not this file's, and no amount of care here moves it. Use this on testnet,
-- or with an amount you would be relaxed about losing, or as the watch-only
-- half of a setup whose keys live somewhere colder. The wallet file is
-- encrypted at rest when SodiumXT is installed and says so loudly when it is
-- not.
--
-- SETUP: nothing. The CoinXT script layer, the wallet engine and OnionXT are
-- embedded in this file. The packaged extensions do the rest:
--
--   coinxt    (org.openxtalk.library.coin)    REQUIRED - every key and hash
--   sodiumxt  (org.openxtalk.library.sodium)  optional - fresh entropy for a
--                                             new seed, and encryption of the
--                                             wallet file. Without it the
--                                             wallet is restore-only and
--                                             stores its file in the clear,
--                                             and every screen that depends on
--                                             it says so rather than guessing.
--   a tor daemon                              optional - the Tor transports.
--                                             Nothing else needs it.
--
-- THE NETWORK, and why it is shaped like this. There are four transports and
-- the differences between them are real:
--
--   Esplora over Tor        a .onion Esplora mirror over plain HTTP through
--                           OnionXT's SOCKS client. The onion circuit is the
--                           encryption and the authentication, so no TLS is
--                           needed and none is used. This is the private
--                           option and the recommended one.
--   Electrum over Tor       a .onion Electrum server, JSON-RPC over the same
--                           circuit. Same privacy, a chattier protocol, and
--                           the server learns only scripthashes.
--   Esplora over clearnet   the engine's own `load URL`. Simple, and it tells
--                           the server which addresses are yours AND, on
--                           http://, tells everyone between you and it. The
--                           suite has never proven the engine's TLS behaviour
--                           (docs/OXT-ENGINE-NOTES 6.8), so https:// here is
--                           offered with that written on the screen rather
--                           than assumed.
--   offline                 always available and always honest: the wallet
--                           derives, builds, signs and exports, and you carry
--                           the bytes to the network yourself.
--
-- HTTPS OVER TOR IS NOT ON THAT LIST because it cannot be: an already-open
-- socket cannot be upgraded to TLS in this engine, and `open secure socket`
-- talks TLS directly to a host, so it cannot perform a SOCKS handshake first.
-- A .onion endpoint over plain HTTP is the correct shape here, not a
-- compromise.
--
-- HONESTY (the suite convention). This stack is verified statically
-- (tools/check-livecodescript.py) and NEEDS AN ON-ENGINE OXT PASS before any
-- runtime claim; the Tor transports additionally need a live-Tor pass. What
-- IS settled is the arithmetic underneath it: every handler of the embedded
-- wallet engine is driven by tools/check-wallet-vectors.py through
-- tools/lcs-interp.py against tools/wallet_reference.py, an independent
-- implementation anchored to the published BIP vectors, with the real native
-- CoinXT library supplying the cryptography - so the transactions this wallet
-- builds are known to be byte-identical to another implementation's, on every
-- script type. That is logic, not parser behaviour, and it promotes nothing
-- out of "needs an OXT pass".
--
-- THE LOOK is the suite UI kit, carried verbatim below between its marker
-- lines (master: tools/ui-kit.livecodescript). Change the look in the master
-- and re-carry it; never patch the block here.
--
-- THE LCS lessons this file is written under (the family list): ASCII only,
-- no braces, no subscripted function results, constants literal and declared
-- before first use, binary through numToByte/byteToNum, zero-argument
-- statement calls BARE, no throw inside a catch, no `repeat with ... step`,
-- every delayed handler pins the defaultStack, and key material cleared as
-- soon as the handler that needed it is done.

-- ---- constants ---------------------------------------------------------------

constant kWaVersion = "1.0.0"
constant kWaUiVersion = "coinwallet-1"

-- The window, inside the family's 720p budget (tools/check-stack-size.py).
constant kWaWidth = 1200
constant kWaHeight = 640
constant kWaBandH = 30

-- The content box, to the right of the navigation rail.
constant kWaContentLeft = 184
constant kWaContentTop = 60
constant kWaContentRight = 1184
constant kWaContentBottom = 594

-- The ten screens, in rail order, and their labels.
constant kWaScreens = "wallet,receive,addresses,send,coins,history,tools,network,log,settings"
constant kWaScreenLabels = "Wallet,Receive,Addresses,Send,Coins,History,Tools,Network,Log,Settings"

-- The BIP-39 test mnemonic. It is the phrase every wallet ships in its own
-- tests, its funds are burned by design, and it is prefilled here so a reader
-- can see the whole wallet work before typing anything of their own. Never
-- type a phrase that guards real coins into this stack.
constant kWaTestMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

-- How far past the last used address the wallet keeps looking before it
-- decides a chain has ended. Twenty is BIP-44's own number and what every
-- other wallet uses, which is what makes a wallet restored elsewhere find the
-- same addresses.
constant kWaGapLimit = 20

-- How many addresses each chain is derived to on load. A wallet with no
-- network cannot know which are used, so it shows a window rather than
-- claiming to know where the chain ends.
constant kWaPrefill = 20

-- The poll and repaint cadence. Four times a second is the family ceiling for
-- UI updates; the network poll is deliberately much slower than that because
-- a public backend is somebody else's machine.
constant kWaTick = 250
constant kWaNetPoll = 20000

-- A network request that has produced nothing at all by here is dead, whatever
-- the socket thinks. A stalled peer accepts the connection and then says
-- nothing, which no socket timeout resolves on its own.
constant kWaNetDeadline = 45000

-- The cap on one response body. A backend that never stops sending hits a wall
-- here rather than exhausting the engine's memory.
constant kWaMaxBody = 4194304

-- The default backends. Blockstream's onion mirror is the private default;
-- the clearnet host is the same service and is offered second, with what it
-- costs written on the Network screen.
constant kWaEsploraOnion = "explorerzydxu5ecjrkwceayqybizmpjjznk5izmitf2modhcusuqlid.onion"
constant kWaEsploraClear = "blockstream.info"
constant kWaElectrumOnion = "explorernuoc63nb.onion"
constant kWaElectrumPort = 110

-- The Tor SOCKS port. 9050 is a system tor daemon; 9150 is Tor Browser's.
constant kWaSocksDefault = 9050

-- The wallet file's format marker. It is the plaintext associated data of the
-- AEAD when SodiumXT is present, so a tampered header is caught even though
-- the header itself is readable.
constant kWaFileMagic = "COINXT-WALLET-1"

-- The Argon2id preset used to turn a password into the file key. Sensitive is
-- deliberate: this is a seed at rest, the cost is paid once per unlock, and a
-- person who notices the pause is being told something true about what it is
-- protecting.
constant kWaKdfOps = "4"

-- ---- state -------------------------------------------------------------------
-- Everything the wallet knows, in one place. The engine layer below holds NO
-- state at all, so this is the whole of it and there is nowhere else to look.

local sWaBuilt            -- "true" once the window has been built
local sWaScreen           -- the visible screen's name
local sWaHaveCoin         -- "true" when the coinxt extension answered
local sWaHaveSodium       -- "true" when sodiumxt answered
local sWaSodiumWhy        -- why not, when it did not
local sWaHaveOnion        -- "true" when the OnionXT script layer is present

local sWaNetwork          -- mainnet | testnet | signet | regtest
local sWaScriptType       -- p2pkh | p2sh-p2wpkh | p2wpkh | p2tr | p2wsh
local sWaKind             -- seed | watch | key | multisig
local sWaAccount          -- the BIP-44 account number
local sWaLabel            -- the wallet's own name
local sWaUnit             -- BTC | mBTC | sat

local sWaMnemonic         -- the seed phrase, while a seed wallet is open
local sWaPassphrase       -- the BIP-39 passphrase (the "25th word")
local sWaAccountXpub      -- the account extended key, always present
local sWaAccountXprv      -- the account extended PRIVATE key, seed wallets only
local sWaFingerprint      -- the master fingerprint, for descriptors and PSBT
local sWaImportedWif      -- a single imported key, for a key wallet
local sWaCosigners        -- a list of cosigner account xpubs, multisig only
local sWaM                -- the m of m-of-n, multisig only

local sWaAddresses        -- list of derived address records, both chains
local sWaLabels           -- array: address -> the user's label for it
local sWaUtxos            -- list of UTXO records
local sWaHistory          -- list of transaction records
local sWaBalance          -- array: confirmed, unconfirmed, frozen
local sWaSelected         -- array: "txid:vout" -> true, the ticked coins
local sWaFrozen           -- array: "txid:vout" -> true

local sWaBackend          -- esplora-tor | electrum-tor | esplora-clear | offline
local sWaHost             -- the backend host
local sWaPort             -- the backend port
local sWaSocksPort        -- the Tor SOCKS port
local sWaNetState         -- idle | dialing | busy | ok | failed
local sWaNetWhy           -- the last network message
local sWaTipHeight        -- the chain tip, when a backend has told us
local sWaFeeRates         -- array: target blocks -> sat/vB, from the backend

local sWaQueue            -- list of pending request records
local sWaInFlight         -- the request record being served, or empty
local sWaStream           -- the OnionXT stream handle in flight, or empty
local sWaBuffer           -- the bytes accumulated for the in-flight request
local sWaReqId            -- a monotonic id, so a late reply cannot be mistaken
local sWaPolling          -- "true" while the tick is armed

local sWaLog              -- the request/response log text
local sWaLastPsbt         -- the PSBT the Tools screen is holding
local sWaLastRaw          -- the raw transaction the Send screen produced
local sWaQrCache          -- array: payload -> the BMP bytes already rendered
local sWaCtrlByScreen     -- array: screen -> comma list of its control names
local sWaBusyUntil        -- the milliseconds a long build is allowed to run to

-- ==============================================================================
-- LIFECYCLE
-- ==============================================================================

on preOpenStack
   waBuild
end preOpenStack

on openStack
   waBoot
end openStack

on closeStack
   -- FREE WHAT WE OPENED. There is no deterministic unload hook in this
   -- engine, so every socket, stream and timer this stack started is stopped
   -- here, and every teardown is safe to call twice.
   local tError
   put "false" into sWaPolling
   waNetAbort
   try
      oxShutdown
   catch tError
   end try
   -- key hygiene: the seed and the account private key do not outlive the
   -- window. The wallet file, if there is one, already has them.
   put empty into sWaMnemonic
   put empty into sWaPassphrase
   put empty into sWaAccountXprv
   put empty into sWaImportedWif
   if there is a field "wl_mnemonic" then
      put empty into field "wl_mnemonic"
   end if
   if there is a field "st_password" then
      put empty into field "st_password"
   end if
end closeStack

command waBoot
   -- The order matters. Probe first, because every screen's advice depends on
   -- which extensions answered; then load or start a wallet; then arm the
   -- pump; then run the boot self-check, which reports what all of that found.
   waProbe
   waResetWallet
   waShow "wallet"
   waRefreshAll
   put "true" into sWaPolling
   send "waTick" to me in kWaTick milliseconds
   waScRun
end waBoot

command waProbe
   -- Capability probing, the family idiom: call the real primitive inside a
   -- try and believe the answer, because there is no `there is a library`
   -- test and an absent extension raises a catchable execution error.
   local tError, tVersion
   put "false" into sWaHaveCoin
   put "false" into sWaHaveSodium
   put "false" into sWaHaveOnion
   put empty into sWaSodiumWhy
   try
      get cxSha256("probe")
      put "true" into sWaHaveCoin
   catch tError
      put "false" into sWaHaveCoin
   end try
   try
      -- sxVersion runs the ABI compare before it reads anything, so a string
      -- back proves BOTH the extension and a matching native binary. A mixed
      -- package lands in the same catch as a missing one, which is why the
      -- reason is kept and shown rather than reduced to a boolean.
      put sxVersion() into tVersion
      get sxRandomBytes(8)
      put "true" into sWaHaveSodium
   catch tError
      put "false" into sWaHaveSodium
      put line 1 of tError into sWaSodiumWhy
   end try
   try
      get oxVersion()
      put "true" into sWaHaveOnion
   catch tError
      put "false" into sWaHaveOnion
   end try
end waProbe

command waResetWallet
   -- A wallet that has not been opened yet, but a REAL one: the published
   -- test mnemonic on testnet, so every screen has something true to show and
   -- nobody has to type a seed to find out what the thing does.
   put "testnet" into sWaNetwork
   put "p2wpkh" into sWaScriptType
   put "seed" into sWaKind
   put 0 into sWaAccount
   put "Demonstration wallet" into sWaLabel
   put "BTC" into sWaUnit
   put kWaTestMnemonic into sWaMnemonic
   put empty into sWaPassphrase
   put empty into sWaImportedWif
   put 2 into sWaM
   put waEmptyList() into sWaCosigners
   put waEmptyList() into sWaUtxos
   put waEmptyList() into sWaHistory
   put waEmptyList() into sWaAddresses
   put empty into sWaLabels
   put empty into sWaSelected
   put empty into sWaFrozen
   put 0 into sWaBalance["confirmed"]
   put 0 into sWaBalance["unconfirmed"]
   put 0 into sWaBalance["frozen"]
   put "offline" into sWaBackend
   put kWaEsploraOnion into sWaHost
   put 80 into sWaPort
   put kWaSocksDefault into sWaSocksPort
   put "idle" into sWaNetState
   put empty into sWaNetWhy
   put empty into sWaTipHeight
   put empty into sWaFeeRates
   put waEmptyList() into sWaQueue
   put empty into sWaInFlight
   put empty into sWaStream
   put empty into sWaBuffer
   put 0 into sWaReqId
   put empty into sWaLastPsbt
   put empty into sWaLastRaw
   put empty into sWaQrCache
   if sWaHaveCoin is "true" then
      waDeriveAccount
   end if
end waResetWallet

function waEmptyList
   local tList
   put 0 into tList["n"]
   return tList
end waEmptyList

-- ---- the pump ----------------------------------------------------------------

on waTick
   -- PIN THE STACK FIRST. This handler arrives from `send ... in`, and
   -- everything it reaches writes to controls by unqualified name; inside
   -- openStack the defaultStack happens to be this stack and here it is
   -- whatever is in front (tools/check-timer-stack-pin.py holds this).
   set the defaultStack to the short name of this stack
   local tError
   if sWaPolling is not "true" then
      exit waTick
   end if
   try
      waNetPump
   catch tError
      waLog "pump error: " & tError
   end try
   send "waTick" to me in kWaTick milliseconds
end waTick

-- ==============================================================================
-- THE WINDOW
--
-- Every control of every screen is created ONCE, at open, and screens are
-- switched by visibility. There is no reparenting in this engine (no way to
-- move a control into a group after the fact), so a "tab" is a naming
-- convention plus a show/hide sweep, and that is what this is: every screen's
-- controls are named "<code>_<thing>", the sweep matches the first three
-- characters, and the chrome and the navigation rail match none of them and
-- therefore never move.
--
-- Building everything up front costs one pass at startup and buys two things:
-- the boot self-check can assert that every control this script names exists
-- (a lazily built screen would report its own controls missing), and a screen
-- switch is a visibility change rather than a construction.
-- ==============================================================================

command waBuild
   if the uUiVersion of this stack is kWaUiVersion then
      exit waBuild
   end if
   lock screen
   uiChrome "CoinXT Wallet", kWaWidth, kWaHeight, kWaBandH
   waBuildNav
   waBuildWallet
   waBuildReceive
   waBuildAddresses
   waBuildSend
   waBuildCoins
   waBuildHistory
   waBuildTools
   waBuildNetwork
   waBuildLog
   waBuildSettings
   uiFooter "CoinXT Wallet " & kWaVersion & " - a DEMONSTRATION wallet. " & \
         "Script memory is not locked, so a seed typed here can be paged to " & \
         "disk: use testnet, or an amount you would be relaxed about losing. " & \
         "Verified statically and by tools/check-wallet-vectors.py against an " & \
         "independent implementation; needs an OXT pass (Tor: + a live-Tor pass).", \
         "16,598,1184,636"
   set the uUiVersion of this stack to kWaUiVersion
   put "true" into sWaBuilt
   unlock screen
end waBuild

command waBuildNav
   local tI, tTop, tName, tCode
   uiPanel "nv_panel", "12,58,176,590"
   repeat with tI = 1 to 10
      put 66 + (tI - 1) * 30 into tTop
      put "nv_" & waScreenCode(tI) into tName
      uiButton tName, waScreenLabel(tI), "20," & tTop & ",168," & (tTop + 26)
   end repeat
   uiSection "nv_bal", "Balance", "20,372,168,390"
   uiLabel "nv_confirmed", "-", "20,394,168,412", 13
   uiLabel "nv_pending", "-", "20,414,168,430", 11
   uiLabel "nv_frozenamt", "-", "20,432,168,448", 11
   uiPill "nv_net", "offline", "20,458,168,478", "wait"
   uiLabel "nv_chain", "-", "20,484,168,500", 11
   uiLabel "nv_tip", "-", "20,502,168,518", 11
   uiLabel "nv_wallet", "-", "20,524,168,556", 11
   uiButton "nv_refresh", "Refresh", "20,560,168,586"
end waBuildNav

function waScreenCode pIndex
   -- The two-letter code each screen's controls are named with. Kept as a
   -- function rather than a constant list because the sweep and the rail both
   -- read it, and two copies of a mapping is one copy too many.
   if pIndex is 1 then
      return "wl"
   else if pIndex is 2 then
      return "rc"
   else if pIndex is 3 then
      return "ad"
   else if pIndex is 4 then
      return "sd"
   else if pIndex is 5 then
      return "cn"
   else if pIndex is 6 then
      return "hs"
   else if pIndex is 7 then
      return "tl"
   else if pIndex is 8 then
      return "nw"
   else if pIndex is 9 then
      return "lg"
   end if
   return "st"
end waScreenCode

function waScreenLabel pIndex
   return cwListAt(kWaScreenLabels, pIndex)
end waScreenLabel

function waScreenName pIndex
   return cwListAt(kWaScreens, pIndex)
end waScreenName

function waCodeForScreen pScreen
   local tI
   repeat with tI = 1 to 10
      if waScreenName(tI) is pScreen then
         return waScreenCode(tI)
      end if
   end repeat
   return ""
end waCodeForScreen

command waShow pScreen
   -- The sweep. Every control whose name is "<code>_..." belongs to a screen;
   -- everything else (the chrome, the rail, the footer) belongs to all of
   -- them and is never touched.
   local tCode, tI, tCount, tName, tPrefix
   put waCodeForScreen(pScreen) into tCode
   if tCode is "" then
      exit waShow
   end if
   put pScreen into sWaScreen
   lock screen
   put the number of controls of this card into tCount
   repeat with tI = 1 to tCount
      put the short name of control tI of this card into tName
      if char 3 of tName is "_" then
         put char 1 to 2 of tName into tPrefix
         if tPrefix is "nv" or tPrefix is "ui" then
            next repeat
         end if
         set the visible of control tI of this card to (tPrefix is tCode)
      end if
   end repeat
   repeat with tI = 1 to 10
      waNavPaint waScreenCode(tI), (waScreenName(tI) is pScreen)
   end repeat
   unlock screen
   waRefreshScreen
end waShow

private command waNavPaint pCode, pActive
   local tName
   put "nv_" & pCode into tName
   if there is no button tName then
      exit waNavPaint
   end if
   set the hilite of button tName to pActive
end waNavPaint

-- ---- 1. Wallet ---------------------------------------------------------------

command waBuildWallet
   uiPanel "wl_panelA", "184,58,700,590"
   uiPanel "wl_panelB", "708,58,1184,590"
   uiSection "wl_sec1", "1. What kind of wallet", "196,66,688,84"
   uiButton "wl_kindSeed", "New seed", "196,90,290,114"
   uiButton "wl_kindRestore", "Restore seed", "294,90,392,114"
   uiButton "wl_kindWatch", "Watch-only", "396,90,486,114"
   uiButton "wl_kindKey", "Import key", "490,90,580,114"
   uiButton "wl_kindMulti", "Multisig", "584,90,688,114"
   uiSection "wl_sec2", "2. Network and script type", "196,122,688,140"
   uiButton "wl_netMain", "mainnet", "196,146,286,170"
   uiButton "wl_netTest", "testnet", "290,146,380,170"
   uiButton "wl_netSignet", "signet", "384,146,474,170"
   uiButton "wl_netReg", "regtest", "478,146,568,170"
   uiButton "wl_typeLegacy", "Legacy 44", "196,174,286,198"
   uiButton "wl_typeNested", "Nested 49", "290,174,380,198"
   uiButton "wl_typeNative", "Native 84", "384,174,474,198"
   uiButton "wl_typeTaproot", "Taproot 86", "478,174,568,198"
   uiButton "wl_typeMulti", "Multisig 48", "572,174,688,198"
   uiCap "wl_accountCap", "Account number", "196,204,320,220"
   uiInput "wl_account", "324,202,400,222"
   uiCap "wl_labelCap", "Wallet name", "410,204,520,220"
   uiInput "wl_label", "524,202,688,222"
   uiSection "wl_sec3", "3. The secret", "196,230,688,248"
   uiCap "wl_mnemonicCap", "Seed phrase (12, 15, 18, 21 or 24 words)", \
         "196,252,688,268"
   uiArea "wl_mnemonic", "196,270,688,326"
   uiCap "wl_passCap", "BIP-39 passphrase (the 25th word; blank is normal)", \
         "196,332,688,348"
   uiInput "wl_pass", "196,350,688,372"
   uiCap "wl_xkeyCap", "Extended key, WIF, or one cosigner key per line", \
         "196,378,688,394"
   uiArea "wl_xkey", "196,396,688,452"
   uiCap "wl_mCap", "Multisig: signatures required", "196,458,400,474"
   uiInput "wl_m", "404,456,470,476"
   uiButton "wl_generate", "Generate a new seed", "196,484,380,510"
   uiButton "wl_open", "Open this wallet", "384,484,540,510"
   uiButton "wl_addCosigner", "Add cosigner", "544,484,688,510"
   uiWrap "wl_warn", "", "196,516,688,584", 11
   uiSection "wl_sec4", "This wallet", "720,66,1172,84"
   uiArea "wl_out", "720,90,1172,470"
   uiButton "wl_copyXpub", "Copy account key", "720,478,880,504"
   uiButton "wl_copyDesc", "Copy descriptor", "884,478,1030,504"
   uiButton "wl_backup", "Backup checklist", "1034,478,1172,504"
   uiWrap "wl_custody", "", "720,512,1172,584", 11
end waBuildWallet

-- ---- 2. Receive --------------------------------------------------------------

command waBuildReceive
   uiPanel "rc_panelA", "184,58,700,590"
   uiPanel "rc_panelB", "708,58,1184,590"
   uiSection "rc_sec1", "The next unused address", "196,66,688,84"
   uiArea "rc_address", "196,90,688,128"
   uiButton "rc_copy", "Copy address", "196,134,340,160"
   uiButton "rc_next", "Skip to the next one", "344,134,520,160"
   uiButton "rc_verify", "Show its derivation", "524,134,688,160"
   uiCap "rc_amountCap", "Request an amount (optional)", "196,170,420,186"
   uiInput "rc_amount", "196,188,340,210"
   uiCap "rc_labelCap", "Label this request (kept locally)", "348,170,688,186"
   uiInput "rc_label", "348,188,688,210"
   uiCap "rc_messageCap", "Message to the payer (optional)", "196,218,688,234"
   uiInput "rc_message", "196,236,688,258"
   uiSection "rc_sec2", "The BIP-21 payment URI", "196,266,688,284"
   uiArea "rc_uri", "196,288,688,336"
   uiButton "rc_copyUri", "Copy the URI", "196,342,340,368"
   uiButton "rc_showQr", "Redraw the QR", "344,342,490,368"
   uiWrap "rc_detail", "", "196,378,688,584", 11
   uiSection "rc_sec3", "Scan this", "720,66,1172,84"
   uiGfx "rc_qrframe", "720,92,1172,540"
   uiLabel "rc_qrhint", "", "720,546,1172,584", 11
end waBuildReceive

-- ---- 3. Addresses ------------------------------------------------------------

command waBuildAddresses
   uiPanel "ad_panel", "184,58,1184,590"
   uiSection "ad_sec1", "Derived addresses", "196,66,1172,84"
   uiButton "ad_receive", "Receive chain", "196,90,330,116"
   uiButton "ad_change", "Change chain", "334,90,468,116"
   uiButton "ad_more", "Derive 20 more", "472,90,610,116"
   uiButton "ad_scan", "Scan for use", "614,90,740,116"
   uiCap "ad_labelCap", "Label the selected address", "750,94,930,110"
   uiInput "ad_label", "934,92,1090,114"
   uiButton "ad_setLabel", "Set", "1094,90,1172,116"
   uiTable "ad_table", "196,124,1172,520", "60,420,120,90,140"
   uiWrap "ad_detail", "", "196,528,1172,584", 11
end waBuildAddresses

-- ---- 4. Send -----------------------------------------------------------------

command waBuildSend
   uiPanel "sd_panelA", "184,58,700,590"
   uiPanel "sd_panelB", "708,58,1184,590"
   uiSection "sd_sec1", "1. Pay to", "196,66,688,84"
   uiCap "sd_toCap", "One address per line: address, amount (or MAX)", \
         "196,88,688,104"
   uiArea "sd_to", "196,106,688,186"
   uiButton "sd_paste", "Read a BIP-21 URI", "196,192,360,218"
   uiButton "sd_addSelf", "Pay myself", "364,192,490,218"
   uiSection "sd_sec2", "2. Fee and options", "196,226,688,244"
   uiCap "sd_rateCap", "Fee rate, sat/vB", "196,250,320,266"
   uiInput "sd_rate", "324,248,400,268"
   uiCap "sd_strategyCap", "Coin selection", "410,250,520,266"
   uiButton "sd_stratBnb", "Auto", "196,274,280,298"
   uiButton "sd_stratLargest", "Largest", "284,274,368,298"
   uiButton "sd_stratSmallest", "Smallest", "372,274,456,298"
   uiButton "sd_stratOldest", "Oldest", "460,274,544,298"
   uiButton "sd_stratManual", "Ticked coins", "548,274,688,298"
   uiCheckbox "sd_rbf", "Replaceable (BIP-125 opt-in RBF)", "196,304,470,326"
   uiCap "sd_locktimeCap", "Locktime", "480,308,560,324"
   uiInput "sd_locktime", "564,304,688,326"
   uiWrap "sd_ratehint", "", "196,332,688,364", 11
   uiSection "sd_sec3", "3. Review, then sign", "196,372,688,390"
   uiButton "sd_preview", "Build (unsigned)", "196,396,352,422"
   uiButton "sd_sign", "Sign", "356,396,450,422"
   uiButton "sd_broadcast", "Broadcast", "454,396,564,422"
   uiButton "sd_toPsbt", "As PSBT", "568,396,688,422"
   uiWrap "sd_warn", "", "196,430,688,584", 11
   uiSection "sd_sec4", "What you are about to authorise", "720,66,1172,84"
   uiArea "sd_out", "720,90,1172,530"
   uiButton "sd_copyRaw", "Copy the raw transaction", "720,538,940,564"
   uiButton "sd_clear", "Clear", "944,538,1050,564"
end waBuildSend

-- ---- 5. Coins ----------------------------------------------------------------

command waBuildCoins
   uiPanel "cn_panel", "184,58,1184,590"
   uiSection "cn_sec1", "Unspent outputs", "196,66,1172,84"
   uiButton "cn_tick", "Tick / untick", "196,90,330,116"
   uiButton "cn_freeze", "Freeze / thaw", "334,90,468,116"
   uiButton "cn_tickAll", "Tick all", "472,90,580,116"
   uiButton "cn_tickNone", "Tick none", "584,90,700,116"
   uiButton "cn_addManual", "Add a coin by hand", "704,90,890,116"
   uiWrap "cn_hint", "", "900,90,1172,120", 11
   uiTable "cn_table", "196,124,1172,500", "40,40,300,120,120,120"
   uiWrap "cn_detail", "", "196,508,1172,584", 11
end waBuildCoins

-- ---- 6. History --------------------------------------------------------------

command waBuildHistory
   uiPanel "hs_panel", "184,58,1184,590"
   uiSection "hs_sec1", "Transactions", "196,66,1172,84"
   uiButton "hs_refresh", "Refresh from the backend", "196,90,420,116"
   uiButton "hs_inspect", "Inspect the selected one", "424,90,640,116"
   uiButton "hs_bump", "Bump its fee (RBF)", "644,90,830,116"
   uiButton "hs_copyTxid", "Copy txid", "834,90,950,116"
   uiTable "hs_table", "196,124,1172,470", "90,180,120,120,120,200"
   uiArea "hs_detail", "196,478,1172,584"
end waBuildHistory

-- ---- 7. Tools ----------------------------------------------------------------

command waBuildTools
   uiPanel "tl_panelA", "184,58,700,590"
   uiPanel "tl_panelB", "708,58,1184,590"
   uiSection "tl_sec1", "Sign or verify a message", "196,66,688,84"
   uiCap "tl_msgCap", "Message", "196,88,688,104"
   uiArea "tl_msg", "196,106,688,160"
   uiCap "tl_msgAddrCap", "Address (blank signs with the first receive key)", \
         "196,166,688,182"
   uiInput "tl_msgAddr", "196,184,688,206"
   uiCap "tl_msgSigCap", "Signature", "196,212,688,228"
   uiArea "tl_msgSig", "196,230,688,278"
   uiButton "tl_msgSign", "Sign", "196,284,300,310"
   uiButton "tl_msgVerify", "Verify", "304,284,410,310"
   uiSection "tl_sec2", "Inspect or sweep", "196,318,688,336"
   uiCap "tl_hexCap", "A raw transaction, a PSBT, a WIF, or an extended key", \
         "196,340,688,356"
   uiArea "tl_hex", "196,358,688,438"
   uiButton "tl_inspect", "Inspect", "196,444,300,470"
   uiButton "tl_psbtSign", "Sign the PSBT", "304,444,440,470"
   uiButton "tl_psbtFinal", "Finalize", "444,444,554,470"
   uiButton "tl_psbtCombine", "Combine with held", "558,444,688,470"
   uiButton "tl_sweep", "Sweep this key", "196,476,340,502"
   uiButton "tl_entropy", "Entropy to mnemonic", "344,476,530,502"
   uiButton "tl_hold", "Hold as the current PSBT", "534,476,688,502"
   uiWrap "tl_note", "", "196,510,688,584", 11
   uiSection "tl_sec3", "Result", "720,66,1172,84"
   uiArea "tl_out", "720,90,1172,530"
   uiButton "tl_copyOut", "Copy this", "720,538,860,564"
   uiButton "tl_export", "Export descriptors + keys", "864,538,1096,564"
end waBuildTools

-- ---- 8. Network --------------------------------------------------------------

command waBuildNetwork
   uiPanel "nw_panelA", "184,58,700,590"
   uiPanel "nw_panelB", "708,58,1184,590"
   uiSection "nw_sec1", "How this wallet reaches the chain", "196,66,688,84"
   uiButton "nw_bOffline", "Offline", "196,90,320,116"
   uiButton "nw_bEsploraTor", "Esplora over Tor", "324,90,500,116"
   uiButton "nw_bElectrumTor", "Electrum over Tor", "504,90,688,116"
   uiButton "nw_bEsploraClear", "Esplora over clearnet", "196,120,420,146"
   uiCap "nw_hostCap", "Host", "196,156,250,172"
   uiInput "nw_host", "254,154,560,176"
   uiCap "nw_portCap", "Port", "570,156,610,172"
   uiInput "nw_port", "614,154,688,176"
   uiCap "nw_socksCap", "Tor SOCKS port (9050 daemon, 9150 Tor Browser)", \
         "196,182,560,198"
   uiInput "nw_socks", "564,180,688,202"
   uiButton "nw_test", "Test the connection", "196,210,390,236"
   uiButton "nw_syncNow", "Sync the wallet", "394,210,560,236"
   uiButton "nw_stop", "Stop", "564,210,688,236"
   uiPill "nw_state", "offline", "196,246,340,268"
   uiWrap "nw_why", "", "350,244,688,300", 11
   uiSection "nw_sec2", "What each choice costs you", "196,308,688,326"
   uiWrap "nw_privacy", "", "196,330,688,584", 11
   uiSection "nw_sec3", "The backend's answers", "720,66,1172,84"
   uiArea "nw_out", "720,90,1172,584"
end waBuildNetwork

-- ---- 9. Log ------------------------------------------------------------------

command waBuildLog
   uiPanel "lg_panel", "184,58,1184,590"
   uiSection "lg_sec1", "Everything this wallet has done", "196,66,1172,84"
   uiButton "lg_copy", "Copy the log", "196,90,340,116"
   uiButton "lg_clear", "Clear", "344,90,450,116"
   uiWrap "lg_hint", "A wallet that does things you cannot see is a wallet " & \
         "you are trusting rather than using. Every request, every reply and " & \
         "every refusal lands here.", "460,90,1172,120", 11
   uiArea "lg_text", "196,124,1172,584"
end waBuildLog

-- ---- 10. Settings ------------------------------------------------------------

command waBuildSettings
   uiPanel "st_panelA", "184,58,700,590"
   uiPanel "st_panelB", "708,58,1184,590"
   uiSection "st_sec1", "The wallet file", "196,66,688,84"
   uiCap "st_pathCap", "Where to keep it", "196,88,688,104"
   uiInput "st_path", "196,106,688,128"
   uiCap "st_passwordCap", "Password (empty means NO encryption)", \
         "196,134,688,150"
   uiInput "st_password", "196,152,688,174"
   uiButton "st_save", "Save", "196,182,300,208"
   uiButton "st_load", "Open", "304,182,408,208"
   uiButton "st_browse", "Choose a file", "412,182,560,208"
   uiWrap "st_filenote", "", "196,216,688,300", 11
   uiSection "st_sec2", "Display", "196,308,688,326"
   uiButton "st_unitBtc", "BTC", "196,332,290,356"
   uiButton "st_unitMbtc", "mBTC", "294,332,388,356"
   uiButton "st_unitSat", "sat", "392,332,486,356"
   uiCap "st_gapCap", "Gap limit", "196,366,280,382"
   uiInput "st_gap", "284,364,360,386"
   uiButton "st_forget", "Forget this wallet", "196,396,370,422"
   uiWrap "st_forgetnote", "", "196,430,688,584", 11
   uiSection "st_sec3", "What is proven, and what is not", "720,66,1172,84"
   uiArea "st_about", "720,90,1172,584"
end waBuildSettings

-- ==============================================================================
-- THE CLICK ROUTER
--
-- One mouseUp, a "<screen>_<role>" naming scheme, and a dispatch by role. A
-- disabled control never reaches here, which is how the wallet gates a flow:
-- a button that cannot yet do anything is disabled and says so, rather than
-- being clickable and then complaining.
-- ==============================================================================

on mouseUp
   local tName, tPrefix, tRole, tError, tI
   put the short name of the target into tName
   if char 3 of tName is not "_" then
      pass mouseUp
   end if
   put char 1 to 2 of tName into tPrefix
   put char 4 to -1 of tName into tRole
   try
      if tPrefix is "nv" then
         waNavClick tRole
      else if tPrefix is "wl" then
         waWalletClick tRole
      else if tPrefix is "rc" then
         waReceiveClick tRole
      else if tPrefix is "ad" then
         waAddressesClick tRole
      else if tPrefix is "sd" then
         waSendClick tRole
      else if tPrefix is "cn" then
         waCoinsClick tRole
      else if tPrefix is "hs" then
         waHistoryClick tRole
      else if tPrefix is "tl" then
         waToolsClick tRole
      else if tPrefix is "nw" then
         waNetworkClick tRole
      else if tPrefix is "lg" then
         waLogClick tRole
      else if tPrefix is "st" then
         waSettingsClick tRole
      else
         pass mouseUp
      end if
   catch tError
      -- EVERY failure reaches the person, on the status line and in the log.
      -- A wallet that swallows an error has decided on the user's behalf that
      -- they did not need to know why nothing happened.
      uiStatus line 1 of tError, "bad"
      waLog "error: " & tError
   end try
end mouseUp

command waNavClick pRole
   local tI
   repeat with tI = 1 to 10
      if waScreenCode(tI) is pRole then
         waShow waScreenName(tI)
         exit waNavClick
      end if
   end repeat
   if pRole is "refresh" then
      waRefreshAll
      if sWaBackend is not "offline" then
         waSync
      end if
   end if
end waNavClick

-- ==============================================================================
-- THE WALLET MODEL
--
-- CoinXT holds a key for the microseconds of one operation and this stack
-- holds it for the lifetime of a window, which is the whole difference
-- between a calculator and a wallet, and the whole of what makes custody the
-- app's problem. So: the seed lives in one script local, the account private
-- key is derived from it and kept only while a seed wallet is open, and every
-- signing path re-derives the one key it needs and clears it on the way out.
-- ==============================================================================

command waDeriveAccount
   -- Turn whatever the user gave us into the account-level key material every
   -- other screen works from. Four wallet kinds arrive here and each one ends
   -- with the same two facts: an account extended PUBLIC key (always) and an
   -- account extended private key (only when we actually hold the secret).
   local tSeed, tMaster, tNode, tPath, tError, tRec
   put empty into sWaAccountXpub
   put empty into sWaAccountXprv
   put empty into sWaFingerprint
   if sWaKind is "watch" then
      put cwXKeyDecode(sWaAccountXpub) into tNode
      exit waDeriveAccount
   end if
   if sWaKind is "key" then
      -- a single imported key has no account and no chain; the Addresses
      -- screen shows exactly one address per script type and says so
      exit waDeriveAccount
   end if
   if sWaMnemonic is empty then
      exit waDeriveAccount
   end if
   if cxMnemonicValidate(cxMnemonicNormalize(sWaMnemonic)) is not true then
      throw "that seed phrase does not pass its BIP-39 checksum. One mistyped " & \
            "word is a different wallet, so nothing has been derived."
   end if
   put cxMnemonicToSeed(cxMnemonicNormalize(sWaMnemonic), sWaPassphrase) into tSeed
   put cxHdFromSeed(tSeed) into tMaster
   put empty into tSeed
   put cwFingerprint(cxHexEncode(tMaster["pubkey"])) into sWaFingerprint
   put cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) into tPath
   put cxHdDerivePath(tMaster, tPath) into tNode
   put cwXKeyEncode(tNode, cwXKeyVersion(sWaNetwork, sWaScriptType, false), true) \
         into sWaAccountXprv
   put cwXKeyEncode(cxHdNeuter(tNode), \
         cwXKeyVersion(sWaNetwork, sWaScriptType, true), false) into sWaAccountXpub
   put empty into tMaster
   put empty into tNode
   waDeriveAddresses
end waDeriveAccount

function waAccountNode
   -- The account node, rebuilt on demand from whichever half we hold. A
   -- watch-only wallet answers with a neutered node and everything that only
   -- needs public keys keeps working; anything that needs to sign asks for
   -- the private half separately and gets a clean refusal.
   if sWaAccountXprv is not empty then
      return cwXKeyDecode(sWaAccountXprv)
   end if
   if sWaAccountXpub is not empty then
      return cwXKeyDecode(sWaAccountXpub)
   end if
   throw "this wallet has no account key yet. Open one on the Wallet screen."
end waAccountNode

command waDeriveAddresses
   -- Derive both chains to the prefill window. Non-hardened both steps, which
   -- is exactly why a watch-only wallet holding only the account xpub can
   -- follow them - and the reason the account level sits where it does.
   local tNode, tI, tRec, tList, tCosigners, tJ, tCount
   put waEmptyList() into tList
   if sWaKind is "key" then
      put waImportedRecords() into sWaAddresses
      exit waDeriveAddresses
   end if
   if sWaKind is "multisig" then
      put cwListCount(sWaCosigners) into tCount
      if tCount < 1 then
         put tList into sWaAddresses
         exit waDeriveAddresses
      end if
      put waEmptyList() into tCosigners
      repeat with tJ = 1 to tCount
         put cwListAdd(tCosigners, cwXKeyDecode(sWaCosigners[tJ])) into tCosigners
      end repeat
      repeat with tJ = 0 to 1
         repeat with tI = 0 to (kWaPrefill - 1)
            put cwMultisigAddressAt(tCosigners, sWaM, sWaNetwork, tJ, tI, true) into tRec
            put cwListAdd(tList, tRec) into tList
         end repeat
      end repeat
      put tList into sWaAddresses
      exit waDeriveAddresses
   end if
   put waAccountNode() into tNode
   repeat with tJ = 0 to 1
      repeat with tI = 0 to (kWaPrefill - 1)
         put cwAddressAt(tNode, sWaScriptType, sWaNetwork, tJ, tI) into tRec
         put cwListAdd(tList, tRec) into tList
      end repeat
   end repeat
   put empty into tNode
   put tList into sWaAddresses
end waDeriveAddresses

private function waImportedRecords
   local tInfo, tList, tRec, tAddr
   put waEmptyList() into tList
   if sWaImportedWif is empty then
      return tList
   end if
   put cwWifInfo(sWaImportedWif, sWaNetwork) into tInfo
   put tInfo[sWaScriptType] into tAddr
   if tAddr is "" then
      put tInfo["p2pkh"] into tAddr
   end if
   put tAddr into tRec["address"]
   put tInfo["pubkey"] into tRec["pubkey"]
   put tInfo["seckey"] into tRec["seckey"]
   put 0 into tRec["change"]
   put 0 into tRec["index"]
   put sWaScriptType into tRec["scripttype"]
   put cwScriptForAddress(sWaNetwork, tAddr) into tRec["script"]
   put "(imported)" into tRec["suffix"]
   return cwListAdd(tList, tRec)
end waImportedRecords

function waAddressCount
   return cwListCount(sWaAddresses)
end waAddressCount

function waRecordFor pAddress
   local tI, tCount, tRec
   put cwListCount(sWaAddresses) into tCount
   repeat with tI = 1 to tCount
      put sWaAddresses[tI] into tRec
      if tRec["address"] is pAddress then
         return tRec
      end if
   end repeat
   return ""
end waRecordFor

function waIsMine pAddress
   return waRecordFor(pAddress) is not ""
end waIsMine

function waNextUnused pChange
   -- The first address on this chain that nothing has ever been sent to. With
   -- no backend the wallet does not KNOW what is used, so it says so on the
   -- Receive screen rather than pretending index 0 is unused forever.
   local tI, tCount, tRec, tSeen
   put waUsedAddresses() into tSeen
   put cwListCount(sWaAddresses) into tCount
   repeat with tI = 1 to tCount
      put sWaAddresses[tI] into tRec
      if tRec["change"] is pChange then
         if tSeen[tRec["address"]] is not "true" then
            return tRec
         end if
      end if
   end repeat
   return ""
end waNextUnused

private function waUsedAddresses
   local tSeen, tI, tCount, tRec
   put empty into tSeen
   put cwListCount(sWaHistory) into tCount
   repeat with tI = 1 to tCount
      put sWaHistory[tI] into tRec
      if tRec["address"] is not "" then
         put "true" into tSeen[tRec["address"]]
      end if
   end repeat
   put cwListCount(sWaUtxos) into tCount
   repeat with tI = 1 to tCount
      put sWaUtxos[tI] into tRec
      put "true" into tSeen[tRec["address"]]
   end repeat
   return tSeen
end waUsedAddresses

-- ---- balances ----------------------------------------------------------------

command waRecomputeBalance
   local tI, tCount, tRec, tKey, tConfirmed, tPending, tFrozen
   put 0 into tConfirmed
   put 0 into tPending
   put 0 into tFrozen
   put cwListCount(sWaUtxos) into tCount
   repeat with tI = 1 to tCount
      put sWaUtxos[tI] into tRec
      put tRec["txid"] & ":" & tRec["vout"] into tKey
      if sWaFrozen[tKey] is "true" then
         add tRec["value"] to tFrozen
      else if tRec["confirmations"] + 0 > 0 then
         add tRec["value"] to tConfirmed
      else
         add tRec["value"] to tPending
      end if
   end repeat
   put tConfirmed into sWaBalance["confirmed"]
   put tPending into sWaBalance["unconfirmed"]
   put tFrozen into sWaBalance["frozen"]
end waRecomputeBalance

function waAmount pSat
   return cwFormatAmount(pSat, sWaUnit)
end waAmount

-- ==============================================================================
-- REPAINTING
--
-- One handler per screen, all of them idempotent, and one that calls them
-- all. Repainting is cheap and being wrong is not, so anything that changes
-- state repaints rather than trying to work out what moved.
-- ==============================================================================

command waRefreshAll
   waRecomputeBalance
   waPaintNav
   waRefreshScreen
end waRefreshAll

command waRefreshScreen
   local tError
   try
      if sWaScreen is "wallet" then
         waPaintWallet
      else if sWaScreen is "receive" then
         waPaintReceive
      else if sWaScreen is "addresses" then
         waPaintAddresses
      else if sWaScreen is "send" then
         waPaintSend
      else if sWaScreen is "coins" then
         waPaintCoins
      else if sWaScreen is "history" then
         waPaintHistory
      else if sWaScreen is "tools" then
         waPaintTools
      else if sWaScreen is "network" then
         waPaintNetwork
      else if sWaScreen is "log" then
         waPaintLog
      else if sWaScreen is "settings" then
         waPaintSettings
      end if
   catch tError
      uiStatus line 1 of tError, "bad"
   end try
end waRefreshScreen

command waPaintNav
   local tKind
   set the defaultStack to the short name of this stack
   put waAmount(sWaBalance["confirmed"]) into field "nv_confirmed"
   if sWaBalance["unconfirmed"] is 0 then
      put "no pending" into field "nv_pending"
   else
      put waAmount(sWaBalance["unconfirmed"]) && "pending" into field "nv_pending"
   end if
   if sWaBalance["frozen"] is 0 then
      put "nothing frozen" into field "nv_frozenamt"
   else
      put waAmount(sWaBalance["frozen"]) && "frozen" into field "nv_frozenamt"
   end if
   put "wait" into tKind
   if sWaBackend is "offline" then
      put "wait" into tKind
   else if sWaNetState is "ok" then
      put "ok" into tKind
   else if sWaNetState is "failed" then
      put "bad" into tKind
   end if
   uiPill "nv_net", waBackendLabel(), "20,458,168,478", tKind
   put sWaNetwork && "/" && sWaScriptType into field "nv_chain"
   if sWaTipHeight is empty then
      put "tip unknown" into field "nv_tip"
   else
      put "tip" && sWaTipHeight into field "nv_tip"
   end if
   put sWaLabel & return & sWaKind && "wallet" into field "nv_wallet"
end waPaintNav

function waBackendLabel
   if sWaBackend is "offline" then
      return "offline"
   end if
   if sWaBackend is "esplora-tor" then
      return "Esplora / Tor"
   end if
   if sWaBackend is "electrum-tor" then
      return "Electrum / Tor"
   end if
   return "Esplora / clear"
end waBackendLabel

command waLog pText
   -- Append one line, bounded. A log that grows without limit is a memory
   -- leak with a nice name, and a wallet left open for a week is exactly the
   -- thing that would find it.
   set the defaultStack to the short name of this stack
   put pText & return after sWaLog
   if the number of chars of sWaLog > 200000 then
      put char -120000 to -1 of sWaLog into sWaLog
   end if
   if there is a field "lg_text" then
      put sWaLog into field "lg_text"
      set the scroll of field "lg_text" to the formattedHeight of field "lg_text"
   end if
end waLog

-- ==============================================================================
-- 1. WALLET
-- ==============================================================================

command waPaintWallet
   local tOut, tError, tNode, tPath, tRec, tI, tCount
   set the defaultStack to the short name of this stack
   waPaintChoice "wl_kind", "Seed,Restore,Watch,Key,Multi", waKindChoice()
   waPaintChoice "wl_net", "Main,Test,Signet,Reg", waNetChoice()
   waPaintChoice "wl_type", "Legacy,Nested,Native,Taproot,Multi", waTypeChoice()
   put sWaAccount into field "wl_account"
   put sWaLabel into field "wl_label"
   if field "wl_mnemonic" is empty then
      put sWaMnemonic into field "wl_mnemonic"
   end if
   put cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) into tPath
   put "network        " & sWaNetwork & return into tOut
   put "script type    " & sWaScriptType && "(" & waTypeName() & ")" & return after tOut
   put "kind           " & sWaKind & return after tOut
   put "account path   " & tPath & return after tOut
   if sWaFingerprint is not empty then
      put "master f.p.    " & sWaFingerprint & return after tOut
   end if
   if sWaAccountXpub is not empty then
      put return & "account extended PUBLIC key (safe to hand out, and it" & return after tOut
      put "reveals every address this account will ever use):" & return after tOut
      put "  " & sWaAccountXpub & return after tOut
      put return & "descriptor (what Bitcoin Core and Sparrow want):" & return after tOut
      try
         put "  " & waDescriptorFor(0) & return after tOut
         put "  " & waDescriptorFor(1) & return after tOut
      catch tError
         put "  (no descriptor for this wallet kind)" & return after tOut
      end try
   else
      put return & "No account key yet. Choose a kind and press Open." & return after tOut
   end if
   if sWaKind is "multisig" then
      put return & "cosigners (" & sWaM & " of " & cwListCount(sWaCosigners) & \
            " required):" & return after tOut
      put cwListCount(sWaCosigners) into tCount
      repeat with tI = 1 to tCount
         put "  " & tI & ". " & char 1 to 24 of sWaCosigners[tI] & "..." & return after tOut
      end repeat
   end if
   put waAddressCount() into tCount
   put return & tCount && "addresses derived (" & kWaPrefill & \
         " per chain), gap limit " & kWaGapLimit & return after tOut
   put tOut into field "wl_out"
   put waWalletAdvice() into field "wl_warn"
   put "CUSTODY: this stack holds the seed in ordinary script memory, which " & \
         "this engine does not lock. The operating system may page it to disk. " & \
         "Treat every key here as compromised the moment the machine is." \
         into field "wl_custody"
end waPaintWallet

private function waWalletAdvice
   local tOut
   put "" into tOut
   if sWaHaveCoin is not "true" then
      return "CoinXT is not installed, so this wallet cannot derive, sign or " & \
            "even check an address. Install org.openxtalk.library.coin."
   end if
   if sWaHaveSodium is not "true" then
      put "SodiumXT is absent, so Generate is disabled (there is no source of " & \
            "entropy here that is fit to make a key from) and the wallet file " & \
            "cannot be encrypted. Restoring a phrase you already have works." into tOut
      if sWaSodiumWhy is not empty then
         put tOut & return & "It said: " & sWaSodiumWhy into tOut
      end if
      return tOut
   end if
   if sWaNetwork is "mainnet" then
      return "This is MAINNET. Everything on the Send screen spends real coins."
   end if
   return "This is " & sWaNetwork & ", so nothing here is worth anything. That " & \
         "is the right place to learn what the buttons do."
end waWalletAdvice

private command waPaintChoice pPrefix, pNames, pActive
   -- A segmented control made of ordinary buttons: the active one is
   -- hilited. There is no radio-group construction to do here because there
   -- is no reparenting, so the group is a naming convention and this handler.
   local tI, tName
   put 1 into tI
   repeat while cwListAt(pNames, tI) is not ""
      put pPrefix & cwListAt(pNames, tI) into tName
      if there is a button tName then
         set the hilite of button tName to (cwListAt(pNames, tI) is pActive)
      end if
      add 1 to tI
   end repeat
end waPaintChoice

private function waKindChoice
   if sWaKind is "watch" then
      return "Watch"
   end if
   if sWaKind is "key" then
      return "Key"
   end if
   if sWaKind is "multisig" then
      return "Multi"
   end if
   if sWaMnemonic is kWaTestMnemonic then
      return "Restore"
   end if
   return "Seed"
end waKindChoice

private function waNetChoice
   if sWaNetwork is "mainnet" then
      return "Main"
   end if
   if sWaNetwork is "testnet" then
      return "Test"
   end if
   if sWaNetwork is "signet" then
      return "Signet"
   end if
   return "Reg"
end waNetChoice

private function waTypeChoice
   if sWaScriptType is "p2pkh" then
      return "Legacy"
   end if
   if sWaScriptType is "p2sh-p2wpkh" then
      return "Nested"
   end if
   if sWaScriptType is "p2tr" then
      return "Taproot"
   end if
   if sWaScriptType is "p2wsh" then
      return "Multi"
   end if
   return "Native"
end waTypeChoice

function waTypeName
   if sWaScriptType is "p2pkh" then
      return "BIP-44, addresses starting 1 or m"
   end if
   if sWaScriptType is "p2sh-p2wpkh" then
      return "BIP-49, SegWit wrapped in P2SH, addresses starting 3 or 2"
   end if
   if sWaScriptType is "p2tr" then
      return "BIP-86, taproot, addresses starting bc1p"
   end if
   if sWaScriptType is "p2wsh" then
      return "BIP-48, m-of-n multisig, addresses starting bc1q and long"
   end if
   return "BIP-84, native SegWit, addresses starting bc1q"
end waTypeName

function waDescriptorFor pChange
   local tXpub, tKeys, tI, tCount
   if sWaKind is "multisig" then
      put waEmptyList() into tKeys
      put cwListCount(sWaCosigners) into tCount
      repeat with tI = 1 to tCount
         put cwListAdd(tKeys, cwXKeyRespell(sWaCosigners[tI], sWaNetwork, \
               "p2pkh", true)) into tKeys
      end repeat
      return cwDescriptorMultisig(sWaM, tKeys, pChange, true)
   end if
   -- The descriptor carries the BIP-32 xpub spelling even for a wpkh()
   -- wallet: the wrapper already names the script type, and Bitcoin Core
   -- rejects a SLIP-132 zpub inside a descriptor outright.
   put cwXKeyRespell(sWaAccountXpub, sWaNetwork, "p2pkh", true) into tXpub
   return cwDescriptor(sWaScriptType, tXpub, sWaFingerprint, \
         cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount), pChange)
end waDescriptorFor

command waWalletClick pRole
   local tEntropy, tText, tI, tCount, tLine, tKey, tInfo
   if pRole is "kindSeed" then
      put "seed" into sWaKind
      put empty into field "wl_mnemonic"
      put empty into sWaMnemonic
      uiStatus "Press Generate for a fresh seed, or type one you already have.", ""
   else if pRole is "kindRestore" then
      put "seed" into sWaKind
      put kWaTestMnemonic into field "wl_mnemonic"
      uiStatus "Type your own phrase over the test one, then press Open.", ""
   else if pRole is "kindWatch" then
      put "watch" into sWaKind
      uiStatus "Paste an account xpub, ypub, zpub, tpub, upub or vpub below.", ""
   else if pRole is "kindKey" then
      put "key" into sWaKind
      uiStatus "Paste one private key in WIF form below.", ""
   else if pRole is "kindMulti" then
      put "multisig" into sWaKind
      put "p2wsh" into sWaScriptType
      uiStatus "Paste one cosigner account key per line, then set how many " & \
            "signatures are required.", ""
   else if pRole is "netMain" then
      waSetNetwork "mainnet"
   else if pRole is "netTest" then
      waSetNetwork "testnet"
   else if pRole is "netSignet" then
      waSetNetwork "signet"
   else if pRole is "netReg" then
      waSetNetwork "regtest"
   else if pRole is "typeLegacy" then
      waSetType "p2pkh"
   else if pRole is "typeNested" then
      waSetType "p2sh-p2wpkh"
   else if pRole is "typeNative" then
      waSetType "p2wpkh"
   else if pRole is "typeTaproot" then
      waSetType "p2tr"
   else if pRole is "typeMulti" then
      waSetType "p2wsh"
   else if pRole is "generate" then
      waGenerateSeed
   else if pRole is "open" then
      waOpenWallet
   else if pRole is "addCosigner" then
      waAddCosigners
   else if pRole is "copyXpub" then
      set the clipboardData["text"] to sWaAccountXpub
      uiCopyFlash "wl_copyXpub"
   else if pRole is "copyDesc" then
      set the clipboardData["text"] to waDescriptorFor(0) & return & waDescriptorFor(1)
      uiCopyFlash "wl_copyDesc"
   else if pRole is "backup" then
      put waBackupChecklist() into field "wl_out"
      exit waWalletClick
   end if
   waRefreshAll
end waWalletClick

command waSetNetwork pNetwork
   -- Changing network changes every address in the wallet, so it re-derives
   -- and drops the chain state rather than showing addresses from one network
   -- beside balances from another.
   put pNetwork into sWaNetwork
   put waEmptyList() into sWaUtxos
   put waEmptyList() into sWaHistory
   put empty into sWaTipHeight
   if sWaHaveCoin is "true" and sWaMnemonic is not empty then
      waDeriveAccount
   end if
   uiStatus "Now on " & pNetwork & ". Addresses and balances were dropped, " & \
         "because they belong to the other chain.", "warn"
end waSetNetwork

command waSetType pType
   put pType into sWaScriptType
   if pType is "p2wsh" then
      put "multisig" into sWaKind
   else if sWaKind is "multisig" then
      put "seed" into sWaKind
   end if
   put waEmptyList() into sWaUtxos
   put waEmptyList() into sWaHistory
   if sWaHaveCoin is "true" and sWaMnemonic is not empty and sWaKind is "seed" then
      waDeriveAccount
   end if
   uiStatus "Script type " & pType & ": " & waTypeName() & ".", ""
end waSetType

command waGenerateSeed
   -- Fresh key material is the CALLER's job in this family and the only
   -- sanctioned source is SodiumXT. There is deliberately no fallback: an
   -- engine random() seeded from the clock is exactly the kind of thing that
   -- looks like it worked.
   local tEntropy, tWords
   if sWaHaveSodium is not "true" then
      throw "Generate needs SodiumXT for entropy, and it is not installed. " & \
            "A seed made from anything weaker is a seed somebody else can " & \
            "guess, so there is no fallback here on purpose."
   end if
   put sxRandomBytes(32) into tEntropy
   put cxMnemonicFromEntropy(tEntropy) into tWords
   put empty into tEntropy
   put tWords into field "wl_mnemonic"
   put tWords into sWaMnemonic
   put empty into tWords
   put "seed" into sWaKind
   waDeriveAccount
   uiStatus "A new 24-word seed. WRITE IT DOWN NOW, on paper, before you do " & \
         "anything else with this window.", "warn"
end waGenerateSeed

command waOpenWallet
   local tText, tInfo, tNode
   put cwTrim(field "wl_label") into sWaLabel
   if sWaLabel is "" then
      put "Wallet" into sWaLabel
   end if
   if field "wl_account" is an integer then
      put field "wl_account" + 0 into sWaAccount
   end if
   put waEmptyList() into sWaUtxos
   put waEmptyList() into sWaHistory
   if sWaKind is "watch" then
      put cwTrim(field "wl_xkey") into tText
      put cwXKeyDecode(tText) into tNode
      if tNode["network"] is not sWaNetwork then
         throw "that extended key belongs to " & tNode["network"] & \
               " and this wallet is on " & sWaNetwork & \
               ". Switch the network, or paste the right key."
      end if
      put tText into sWaAccountXpub
      put empty into sWaAccountXprv
      put tNode["scripttype"] into sWaScriptType
      put cwFingerprint(cxHexEncode(tNode["pubkey"])) into sWaFingerprint
      waDeriveAddresses
      uiStatus "Watching " & tNode["scripttype"] & " addresses from that " & \
            "account key. This wallet cannot sign anything.", "ok"
      exit waOpenWallet
   end if
   if sWaKind is "key" then
      put cwTrim(field "wl_xkey") into tText
      put cwWifInfo(tText, sWaNetwork) into tInfo
      put tText into sWaImportedWif
      put empty into sWaAccountXpub
      put empty into sWaAccountXprv
      waDeriveAddresses
      if tInfo["warning"] is not "" then
         uiStatus tInfo["warning"] & ". Nothing was derived on the wrong chain.", "bad"
      else
         uiStatus "One key imported. It has exactly one address per script " & \
               "type, and no chain to scan.", "ok"
      end if
      exit waOpenWallet
   end if
   if sWaKind is "multisig" then
      waAddCosigners
      exit waOpenWallet
   end if
   put cwTrim(field "wl_mnemonic") into sWaMnemonic
   put field "wl_pass" into sWaPassphrase
   waDeriveAccount
   uiStatus "Open: " & sWaLabel & ", " & sWaScriptType & " on " & sWaNetwork & \
         ", " & waAddressCount() & " addresses derived.", "ok"
end waOpenWallet

command waAddCosigners
   -- Every cosigner's ACCOUNT key, one per line. They are checked for the
   -- same network before anything is derived, because a multisig built from
   -- keys on two chains produces an address nobody can ever spend from and
   -- there is no later moment at which that becomes obvious.
   local tText, tI, tCount, tLine, tNode, tList, tKey
   put field "wl_xkey" into tText
   put waEmptyList() into tList
   put the number of lines of tText into tCount
   repeat with tI = 1 to tCount
      put cwTrim(line tI of tText) into tLine
      if tLine is "" then
         next repeat
      end if
      put cwXKeyDecode(tLine) into tNode
      if tNode["network"] is not sWaNetwork then
         throw "cosigner " & tI & " is a " & tNode["network"] & " key and this " & \
               "wallet is on " & sWaNetwork & ". A multisig mixing chains " & \
               "produces an address nobody can spend."
      end if
      put cwListAdd(tList, tLine) into tList
   end repeat
   if cwListCount(tList) < 1 then
      throw "paste at least one cosigner account key, one per line."
   end if
   if field "wl_m" is an integer then
      put field "wl_m" + 0 into sWaM
   end if
   if sWaM < 1 or sWaM > cwListCount(tList) then
      throw "the number of required signatures must be between 1 and the " & \
            "number of cosigners (" & cwListCount(tList) & ")."
   end if
   put tList into sWaCosigners
   put "multisig" into sWaKind
   put "p2wsh" into sWaScriptType
   waDeriveAddresses
   uiStatus sWaM & "-of-" & cwListCount(tList) & " multisig, " & \
         waAddressCount() & " addresses derived. Every cosigner must derive " & \
         "the same addresses, which BIP-67 key ordering is what guarantees.", "ok"
end waAddCosigners

function waBackupChecklist
   local tOut
   put "BACKING THIS WALLET UP" & return & return into tOut
   put "1. Write the seed phrase on PAPER. Not a photo, not a password" & return after tOut
   put "   manager you cannot reach without a working computer, not this" & return after tOut
   put "   window. Twelve or twenty-four ordinary words." & return & return after tOut
   put "2. Write down the BIP-39 passphrase separately IF you used one." & return after tOut
   put "   It is not in the phrase and cannot be recovered from it. An" & return after tOut
   put "   empty passphrase is normal; a forgotten one is a lost wallet." & return & return after tOut
   put "3. Write down the derivation path: " & \
         cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) & return after tOut
   put "   Another wallet restoring your phrase needs it to find the same" & return after tOut
   put "   addresses. " & sWaScriptType && "(" & waTypeName() & ")." & return & return after tOut
   put "4. Check the backup by restoring it: type the words back in on a" & return after tOut
   put "   fresh open of this stack and confirm the first receive address" & return after tOut
   put "   matches. A backup nobody has ever restored is a hope." & return & return after tOut
   if sWaKind is "multisig" then
      put "5. MULTISIG: keep every cosigner's account key too. The seed" & return after tOut
      put "   alone cannot rebuild the address; it needs all " & \
            cwListCount(sWaCosigners) & " public keys." & return & return after tOut
   end if
   put "The first receive address for this wallet right now:" & return after tOut
   put "   " & waFirstAddress() & return after tOut
   return tOut
end waBackupChecklist

function waFirstAddress
   local tRec
   if waAddressCount() < 1 then
      return "(nothing derived yet)"
   end if
   put sWaAddresses[1] into tRec
   return tRec["address"]
end waFirstAddress

-- ==============================================================================
-- 2. RECEIVE
-- ==============================================================================

command waPaintReceive
   local tRec, tAddr, tUri, tAmount, tOut, tError
   set the defaultStack to the short name of this stack
   put waCurrentReceive() into tRec
   if tRec is "" then
      put "No address yet. Open a wallet first." into field "rc_address"
      put "" into field "rc_uri"
      put "" into field "rc_detail"
      exit waPaintReceive
   end if
   put tRec["address"] into tAddr
   put tAddr into field "rc_address"
   put -1 into tAmount
   if cwTrim(field "rc_amount") is not "" then
      try
         put cwParseAmount(field "rc_amount", sWaUnit) into tAmount
      catch tError
         put -1 into tAmount
      end try
   end if
   if tAmount > 0 then
      put cwUriBuild(tAddr, tAmount, field "rc_label", field "rc_message") into tUri
   else
      put cwUriBuild(tAddr, "", field "rc_label", field "rc_message") into tUri
   end if
   put tUri into field "rc_uri"
   put "derivation   " & cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) & \
         tRec["suffix"] & return into tOut
   put "script type  " & tRec["scripttype"] & return after tOut
   put "scriptPubKey " & tRec["script"] & return after tOut
   if sWaBackend is "offline" then
      put return & "This wallet is OFFLINE, so it cannot know whether this " & \
            "address has been used. It is showing index " & tRec["index"] & \
            " of the receive chain; if you have used this wallet before, " & \
            "press Skip until you reach one you have not handed out." after tOut
   else
      put return & "Nothing has been paid to this address yet." after tOut
   end if
   put tOut into field "rc_detail"
   waDrawQr tUri
end waPaintReceive

function waCurrentReceive
   local tRec, tI, tCount, tWanted
   put waNextUnused(0) into tRec
   if tRec is not "" and the uReceiveIndex of this stack is empty then
      return tRec
   end if
   put the uReceiveIndex of this stack into tWanted
   if tWanted is empty then
      return tRec
   end if
   put cwListCount(sWaAddresses) into tCount
   repeat with tI = 1 to tCount
      put sWaAddresses[tI] into tRec
      if tRec["change"] is 0 and tRec["index"] is tWanted then
         return tRec
      end if
   end repeat
   return waNextUnused(0)
end waCurrentReceive

command waDrawQr pPayload
   -- The QR is CACHED by payload. Building one is hundreds of thousands of
   -- interpreted steps (eight mask evaluations over the whole symbol), and
   -- this handler is called from every repaint of the screen - so without the
   -- cache, typing a label would rebuild the code on every keystroke.
   local tBmp, tError
   set the defaultStack to the short name of this stack
   if pPayload is empty then
      exit waDrawQr
   end if
   if sWaQrCache["payload"] is pPayload then
      exit waDrawQr
   end if
   put "" into tBmp
   try
      put cwQrBmp(pPayload, 8, 4) into tBmp
   catch tError
      put "" into tBmp
      put "That payload is too long for a QR code this wallet can draw: " & \
            line 1 of tError into field "rc_qrhint"
      exit waDrawQr
   end try
   put pPayload into sWaQrCache["payload"]
   if there is no image "rc_qr" then
      create image
      set the name of the last image to "rc_qr"
   end if
   -- The engine may or may not accept a BMP into an image's text; if it does
   -- not, the code is still available as text on the Tools screen, and saying
   -- so beats a blank rectangle nobody can explain.
   try
      set the text of image "rc_qr" to tBmp
      set the lockLocation of image "rc_qr" to true
      set the rect of image "rc_qr" to "726,98,1166,538"
      set the visible of image "rc_qr" to (sWaScreen is "receive")
      put "Point a phone at this. It carries the URI above, not just the " & \
            "address, so the amount and label travel with it." into field "rc_qrhint"
   catch tError
      put "This engine would not take the image (" & line 1 of tError & \
            "). The URI above is the same thing in text." into field "rc_qrhint"
   end try
end waDrawQr

command waReceiveClick pRole
   local tRec, tIndex
   if pRole is "copy" then
      set the clipboardData["text"] to field "rc_address"
      uiCopyFlash "rc_copy"
   else if pRole is "copyUri" then
      set the clipboardData["text"] to field "rc_uri"
      uiCopyFlash "rc_copyUri"
   else if pRole is "next" then
      put waCurrentReceive() into tRec
      if tRec is "" then
         throw "there is no address to skip past yet."
      end if
      put tRec["index"] + 1 into tIndex
      if tIndex >= kWaPrefill then
         throw "that is the end of the derived window. Press 'Derive 20 more' " & \
               "on the Addresses screen first."
      end if
      set the uReceiveIndex of this stack to tIndex
   else if pRole is "verify" then
      put waCurrentReceive() into tRec
      put waAddressProof(tRec) into field "rc_detail"
      exit waReceiveClick
   else if pRole is "showQr" then
      put empty into sWaQrCache["payload"]
   end if
   waRefreshScreen
end waReceiveClick

function waAddressProof pRec
   -- Show the whole chain of reasoning from the account key to this address,
   -- because "trust me, this is yours" is what a person is being asked to
   -- believe when they hand it to somebody who owes them money.
   local tOut
   if pRec is "" then
      return "No address."
   end if
   put "WHY THIS ADDRESS IS YOURS" & return & return into tOut
   put "account key   " & sWaAccountXpub & return after tOut
   put "path          " & cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) & \
         pRec["suffix"] & return after tOut
   put "public key    " & pRec["pubkey"] & return after tOut
   if pRec["internalkey"] is not "" then
      put "internal key  " & pRec["internalkey"] & return after tOut
      put "output key    " & pRec["outputkey"] && "(BIP-341 tweak, empty root)" & \
            return after tOut
   end if
   if pRec["redeem"] is not "" then
      put "redeem script " & pRec["redeem"] & return after tOut
   end if
   if pRec["witnessscript"] is not "" then
      put "witnessScript " & pRec["witnessscript"] & return after tOut
   end if
   put "scriptPubKey  " & pRec["script"] & return after tOut
   put "address       " & pRec["address"] & return & return after tOut
   put "Anybody holding the account key above can recompute this whole " & \
         "chain and get the same address. That is what makes a watch-only " & \
         "wallet possible, and it is also why the account key is not a " & \
         "secret you should publish." after tOut
   return tOut
end waAddressProof

-- ==============================================================================
-- 3. ADDRESSES
-- ==============================================================================

command waPaintAddresses
   local tChain, tI, tCount, tRec, tRows, tUsed, tBal, tLabel, tTab
   set the defaultStack to the short name of this stack
   put waChainShown() into tChain
   set the hilite of button "ad_receive" to (tChain is 0)
   set the hilite of button "ad_change" to (tChain is 1)
   put waUsedAddresses() into tUsed
   put waBalanceByAddress() into tBal
   put numToChar(9) into tTab
   put "index" & tTab & "address" & tTab & "state" & tTab & "balance" & tTab & \
         "label" & return into tRows
   put cwListCount(sWaAddresses) into tCount
   repeat with tI = 1 to tCount
      put sWaAddresses[tI] into tRec
      if tRec["change"] is not tChain then
         next repeat
      end if
      put sWaLabels[tRec["address"]] into tLabel
      put tRows & tRec["index"] & tTab & tRec["address"] & tTab into tRows
      if tUsed[tRec["address"]] is "true" then
         put "used" after tRows
      else if sWaBackend is "offline" then
         put "unknown" after tRows
      else
         put "unused" after tRows
      end if
      put tTab & waAmount(tBal[tRec["address"]] + 0) & tTab & tLabel & return after tRows
   end repeat
   put tRows into field "ad_table"
   put waAddressesHint(tChain) into field "ad_detail"
end waPaintAddresses

private function waAddressesHint pChain
   if pChain is 1 then
      return "The CHANGE chain. Every transaction that does not spend a coin " & \
            "exactly pays its remainder back to the next unused address here. " & \
            "You never hand these out; they are why a wallet's balance is not " & \
            "the balance of the address somebody paid." & return & \
            "Gap limit " & kWaGapLimit & ": another wallet restoring your seed " & \
            "stops looking after that many unused addresses in a row, which " & \
            "is why skipping past it can hide coins from your own backup."
   end if
   return "The RECEIVE chain: the addresses you hand out. Using a fresh one " & \
         "each time is the single cheapest privacy measure there is - reusing " & \
         "one publishes every payment you have ever received to everybody you " & \
         "give it to." & return & "Select a row and type a label to remember " & \
         "who you gave it to. Labels are kept locally and go in the wallet file."
end waAddressesHint

function waChainShown
   if the uChainShown of this stack is 1 then
      return 1
   end if
   return 0
end waChainShown

private function waBalanceByAddress
   local tI, tCount, tRec, tOut
   put empty into tOut
   put cwListCount(sWaUtxos) into tCount
   repeat with tI = 1 to tCount
      put sWaUtxos[tI] into tRec
      add tRec["value"] to tOut[tRec["address"]]
   end repeat
   return tOut
end waBalanceByAddress

command waAddressesClick pRole
   local tRow, tAddr, tTab, tNode, tI, tRec, tList, tCount
   put numToChar(9) into tTab
   if pRole is "receive" then
      set the uChainShown of this stack to 0
   else if pRole is "change" then
      set the uChainShown of this stack to 1
   else if pRole is "more" then
      waDeriveMore
   else if pRole is "scan" then
      if sWaBackend is "offline" then
         throw "a scan needs a backend. Choose one on the Network screen."
      end if
      waSync
   else if pRole is "setLabel" then
      put waSelectedAddress() into tAddr
      if tAddr is "" then
         throw "select a row first."
      end if
      put field "ad_label" into sWaLabels[tAddr]
      uiStatus "Labelled " & tAddr & ".", "ok"
   end if
   waRefreshScreen
end waAddressesClick

function waSelectedAddress
   -- SAVE, SET, USE, RESTORE. `the itemDelimiter` is global mutable state in
   -- this engine and everything else in this stack assumes the default; a
   -- handler that sets it to tab and walks away leaves every later `item`
   -- expression parsing something else. Restoring it to comma would be a
   -- guess about what the caller had.
   local tLine, tTab, tText, tSaved
   set the defaultStack to the short name of this stack
   put the hilitedLine of field "ad_table" into tLine
   if tLine is empty or tLine < 2 then
      return ""
   end if
   put line tLine of field "ad_table" into tText
   put numToChar(9) into tTab
   put the itemDelimiter into tSaved
   set the itemDelimiter to tTab
   put item 2 of tText into tText
   set the itemDelimiter to tSaved
   return cwTrim(tText)
end waSelectedAddress

command waDeriveMore
   -- Extend both chains by another window. Deliberately explicit rather than
   -- automatic: past the gap limit, an address this wallet derives is one a
   -- wallet restored from the same seed elsewhere will NOT find, and that is
   -- a decision a person should make on purpose.
   local tNode, tI, tCount, tRec, tList, tStart, tJ
   put sWaAddresses into tList
   put cwListCount(tList) into tCount
   put waAccountNode() into tNode
   put waHighestIndex(0) + 1 into tStart
   repeat with tJ = 0 to 1
      put waHighestIndex(tJ) + 1 into tStart
      repeat with tI = tStart to (tStart + kWaPrefill - 1)
         if sWaKind is "multisig" then
            put waMultisigRecord(tJ, tI) into tRec
         else
            put cwAddressAt(tNode, sWaScriptType, sWaNetwork, tJ, tI) into tRec
         end if
         put cwListAdd(tList, tRec) into tList
      end repeat
   end repeat
   put empty into tNode
   put tList into sWaAddresses
   uiStatus "Derived to index " & (tStart + kWaPrefill - 1) & " on both chains. " & \
         "Past the gap limit of " & kWaGapLimit & ", another wallet restoring " & \
         "your seed will not look this far.", "warn"
end waDeriveMore

private function waHighestIndex pChain
   local tI, tCount, tRec, tBest
   put -1 into tBest
   put cwListCount(sWaAddresses) into tCount
   repeat with tI = 1 to tCount
      put sWaAddresses[tI] into tRec
      if tRec["change"] is pChain and tRec["index"] > tBest then
         put tRec["index"] into tBest
      end if
   end repeat
   return tBest
end waHighestIndex

private function waMultisigRecord pChange, pIndex
   local tCosigners, tJ, tCount
   put waEmptyList() into tCosigners
   put cwListCount(sWaCosigners) into tCount
   repeat with tJ = 1 to tCount
      put cwListAdd(tCosigners, cwXKeyDecode(sWaCosigners[tJ])) into tCosigners
   end repeat
   return cwMultisigAddressAt(tCosigners, sWaM, sWaNetwork, pChange, pIndex, true)
end waMultisigRecord

-- ==============================================================================
-- 4. SEND
--
-- The screen where a mistake costs money, so it is built around ONE rule:
-- nothing is signed until the person has been shown, in words, what they are
-- authorising - every output, the fee, the change, and which coins are being
-- spent. CoinXT's own rule 3 says a blind signer is a footgun; this is what
-- not being one looks like.
-- ==============================================================================

command waPaintSend
   local tRate, tHint
   set the defaultStack to the short name of this stack
   waPaintChoice "sd_strat", "Bnb,Largest,Smallest,Oldest,Manual", waStrategyChoice()
   if field "sd_rate" is empty then
      put waDefaultRate() into field "sd_rate"
   end if
   if field "sd_locktime" is empty then
      put "0" into field "sd_locktime"
   end if
   put field "sd_rate" into tRate
   if tRate is a number then
      put "At " & tRate & " sat/vB: " & cwFeeRateLabel(tRate + 0) into tHint
   else
      put "Type a fee rate in sat/vB." into tHint
   end if
   if sWaFeeRates["1"] is not "" then
      put tHint & return & "The backend suggests " & sWaFeeRates["1"] & \
            " sat/vB for the next block and " & sWaFeeRates["6"] & \
            " for within six." into tHint
   end if
   put tHint into field "sd_ratehint"
   put waSendWarning() into field "sd_warn"
end waPaintSend

private function waStrategyChoice
   local tS
   put the uStrategy of this stack into tS
   if tS is "largest" then
      return "Largest"
   end if
   if tS is "smallest" then
      return "Smallest"
   end if
   if tS is "oldest" then
      return "Oldest"
   end if
   if tS is "manual" then
      return "Manual"
   end if
   return "Bnb"
end waStrategyChoice

function waStrategy
   local tS
   put the uStrategy of this stack into tS
   if tS is "" then
      return "bnb"
   end if
   return tS
end waStrategy

private function waDefaultRate
   if sWaFeeRates["6"] is not "" then
      return sWaFeeRates["6"]
   end if
   return "5"
end waDefaultRate

private function waSendWarning
   if sWaKind is "watch" then
      return "This is a WATCH-ONLY wallet. It can build a transaction and " & \
            "export it as a PSBT for something that holds the keys, but it " & \
            "cannot sign. Sign is disabled."
   end if
   if cwListCount(sWaUtxos) < 1 then
      return "There are no coins to spend. Either this wallet is empty, or it " & \
            "is offline and has never been told what it owns - the Coins " & \
            "screen can take a UTXO by hand if you know one."
   end if
   if sWaNetwork is "mainnet" then
      return "MAINNET. Read every line of the review panel before pressing " & \
            "Sign, and read the destination address in full: the first and " & \
            "last few characters matching is exactly what address-swapping " & \
            "malware relies on."
   end if
   return "On " & sWaNetwork & ". Nothing here is worth anything, which makes " & \
         "it the right place to press every button once."
end waSendWarning

command waSendClick pRole
   if pRole is "stratBnb" then
      set the uStrategy of this stack to "bnb"
   else if pRole is "stratLargest" then
      set the uStrategy of this stack to "largest"
   else if pRole is "stratSmallest" then
      set the uStrategy of this stack to "smallest"
   else if pRole is "stratOldest" then
      set the uStrategy of this stack to "oldest"
   else if pRole is "stratManual" then
      set the uStrategy of this stack to "manual"
   else if pRole is "paste" then
      waReadUri
   else if pRole is "addSelf" then
      waAddSelfPayment
   else if pRole is "preview" then
      waBuildSpend false, false
   else if pRole is "sign" then
      waBuildSpend true, false
   else if pRole is "toPsbt" then
      waBuildSpend false, true
   else if pRole is "broadcast" then
      waBroadcast
   else if pRole is "copyRaw" then
      set the clipboardData["text"] to sWaLastRaw
      uiCopyFlash "sd_copyRaw"
   else if pRole is "clear" then
      put empty into field "sd_to"
      put empty into field "sd_out"
      put empty into sWaLastRaw
   end if
   waRefreshScreen
end waSendClick

command waReadUri
   -- BIP-21 in, one payment line out. A req- parameter this wallet does not
   -- understand is a REFUSAL, not a warning: the sender attached a condition
   -- to the payment and paying without honouring it is not the same payment.
   local tUri, tRec, tReq, tCount, tLine
   put cwTrim(field "sd_to") into tUri
   if tUri is "" then
      throw "paste a bitcoin: URI into the Pay to box first."
   end if
   put cwUriParse(line 1 of tUri) into tRec
   put cwListCount(tRec["required"]) into tCount
   if tCount > 0 then
      put tRec["required"] into tReq
      throw "that URI carries " & tReq[1] & ", a req- parameter this wallet " & \
            "does not understand. BIP-21 says a wallet must refuse rather " & \
            "than pay and ignore the condition."
   end if
   if cwAddressIsValid(sWaNetwork, tRec["address"]) is not true then
      throw "that URI's address is not valid on " & sWaNetwork & ": " & \
            cwAddressProblem(sWaNetwork, tRec["address"])
   end if
   put tRec["address"] into tLine
   if tRec["amountsat"] > 0 then
      put tLine & ", " & cwSatToBtc(tRec["amountsat"]) into tLine
   end if
   put tLine & return into field "sd_to"
   if tRec["label"] is not "" then
      put tRec["label"] into sWaLabels[tRec["address"]]
   end if
   uiStatus "Read a BIP-21 URI" & waUriExtra(tRec) & ".", "ok"
end waReadUri

private function waUriExtra pRec
   local tOut
   put "" into tOut
   if pRec["amountsat"] > 0 then
      put " for " & cwSatToBtc(pRec["amountsat"]) & " BTC" into tOut
   end if
   if pRec["label"] is not "" then
      put tOut & " from " & pRec["label"] into tOut
   end if
   return tOut
end waUriExtra

command waAddSelfPayment
   local tRec
   put waNextUnused(0) into tRec
   if tRec is "" then
      throw "this wallet has no address to pay."
   end if
   put tRec["address"] & ", 0.0001" & return after field "sd_to"
end waAddSelfPayment

function waParsePayments
   -- One payment per line: "<address>, <amount>" or "<address>, MAX". The
   -- comma is split by hand rather than with `item` so this does not depend
   -- on the engine's current itemDelimiter, which anything in the process may
   -- have changed.
   local tText, tI, tCount, tLine, tPos, tAddr, tAmountText, tRec, tList, tMax
   put field "sd_to" into tText
   put waEmptyList() into tList
   put false into tMax
   put the number of lines of tText into tCount
   repeat with tI = 1 to tCount
      put cwTrim(line tI of tText) into tLine
      if tLine is "" then
         next repeat
      end if
      put offset(",", tLine) into tPos
      if tPos is 0 then
         put tLine into tAddr
         put "" into tAmountText
      else
         put cwTrim(char 1 to (tPos - 1) of tLine) into tAddr
         put cwTrim(char (tPos + 1) to -1 of tLine) into tAmountText
      end if
      if cwAddressIsValid(sWaNetwork, tAddr) is not true then
         throw "line " & tI & ": " & cwAddressProblem(sWaNetwork, tAddr)
      end if
      put "" into tRec
      put tAddr into tRec["address"]
      put cwScriptForAddress(sWaNetwork, tAddr) into tRec["script"]
      put cwScriptKind(tRec["script"]) into tRec["kind"]
      if cwUpper(tAmountText) is "MAX" then
         if tMax is true then
            throw "only one output can be MAX: two of them have no answer."
         end if
         put true into tMax
         put true into tRec["max"]
         put 0 into tRec["value"]
      else
         if tAmountText is "" then
            throw "line " & tI & ": that address has no amount. Write " & \
                  quote & "address, 0.001" & quote & " or " & quote & \
                  "address, MAX" & quote & "."
         end if
         put false into tRec["max"]
         put cwParseAmount(tAmountText, sWaUnit) into tRec["value"]
         if tRec["value"] <= 0 then
            throw "line " & tI & ": an amount must be positive."
         end if
         if tRec["value"] < cwDustThreshold(tRec["kind"]) then
            throw "line " & tI & ": " & tRec["value"] & \
                  " sat is below the dust threshold for a " & tRec["kind"] & \
                  " output (" & cwDustThreshold(tRec["kind"]) & \
                  " sat). The network will not relay it."
         end if
      end if
      put cwListAdd(tList, tRec) into tList
   end repeat
   if cwListCount(tList) < 1 then
      throw "there is nothing to pay. Put an address and an amount in the Pay " & \
            "to box."
   end if
   return tList
end waParsePayments

function waSpendableCoins
   -- The UTXO set as the selector wants it, carrying the freeze and tick
   -- flags the Coins screen sets.
   local tI, tCount, tRec, tKey, tOut, tCoin
   put waEmptyList() into tOut
   put cwListCount(sWaUtxos) into tCount
   repeat with tI = 1 to tCount
      put sWaUtxos[tI] into tRec
      put tRec["txid"] & ":" & tRec["vout"] into tKey
      put tRec into tCoin
      put (sWaFrozen[tKey] is "true") into tCoin["frozen"]
      put (sWaSelected[tKey] is "true") into tCoin["selected"]
      put cwListAdd(tOut, tCoin) into tOut
   end repeat
   return tOut
end waSpendableCoins

command waBuildSpend pSign, pAsPsbt
   -- The whole spend path in one place: parse, select, build, review, and
   -- only then sign. Every early return leaves the review panel saying what
   -- stopped it.
   local tPays, tCoins, tTarget, tRate, tSel, tOutTypes, tI, tCount, tRec
   local tInputs, tOutputs, tChangeRec, tLock, tSeq, tResult, tOut, tMaxIndex
   local tChangeType, tFee, tChange, tVsize, tError, tNode, tSigs, tWits
   local tDigest, tSig, tRaw, tTxid, tPsbt, tMeta, tKey, tAmounts, tScripts
   set the defaultStack to the short name of this stack
   put waParsePayments() into tPays
   put field "sd_rate" into tRate
   if tRate is not a number or tRate <= 0 then
      throw "the fee rate must be a positive number of sat/vB."
   end if
   put field "sd_locktime" into tLock
   if tLock is not an integer or tLock < 0 then
      put 0 into tLock
   end if
   put waSequenceNumber() into tSeq
   put waSpendableCoins() into tCoins
   if cwListCount(tCoins) < 1 then
      throw "this wallet holds no coins to spend."
   end if
   -- the target and the output types the estimator needs
   put 0 into tTarget
   put -1 into tMaxIndex
   put waEmptyList() into tOutTypes
   put cwListCount(tPays) into tCount
   repeat with tI = 1 to tCount
      put tPays[tI] into tRec
      if tRec["max"] is true then
         put tI into tMaxIndex
      else
         add tRec["value"] to tTarget
      end if
      put cwListAdd(tOutTypes, tRec["kind"]) into tOutTypes
   end repeat
   put waChangeType() into tChangeType
   if tMaxIndex > 0 then
      put waMaxSpend(tCoins, tOutTypes, tRate) into tResult
   else
      put cwSelectCoins(tCoins, tTarget, tRate, waInputType(), tOutTypes, \
            tChangeType, waStrategy(), sWaM, cwListCount(sWaCosigners)) into tResult
   end if
   if tResult["ok"] is not true then
      put "Cannot build this spend: " & tResult["why"] & return & return & \
            waCoinAdvice(tResult, tTarget) into field "sd_out"
      uiStatus tResult["why"], "bad"
      exit waBuildSpend
   end if
   put tResult["selected"] into tSel
   put tResult["fee"] into tFee
   put tResult["change"] into tChange
   put tResult["vsize"] into tVsize
   -- inputs
   put waEmptyList() into tInputs
   put cwListCount(tSel) into tCount
   repeat with tI = 1 to tCount
      put tSel[tI] into tRec
      put cwListAdd(tInputs, cwTxInput(tRec["txid"], tRec["vout"], tSeq)) into tInputs
   end repeat
   -- outputs, with MAX taking whatever is left
   put waEmptyList() into tOutputs
   repeat with tI = 1 to cwListCount(tPays)
      put tPays[tI] into tRec
      if tRec["max"] is true then
         put tResult["totalin"] - tTarget - tFee into tRec["value"]
         if tRec["value"] < cwDustThreshold(tRec["kind"]) then
            throw "after the fee, the MAX output would be " & tRec["value"] & \
                  " sat, which is dust."
         end if
         put tRec into tPays[tI]
      end if
      put cwListAdd(tOutputs, cwTxOutput(tRec["value"], tRec["script"])) into tOutputs
   end repeat
   put "" into tChangeRec
   if tChange > 0 then
      put waNextUnused(1) into tChangeRec
      if tChangeRec is "" then
         throw "there is no change address left in the derived window. Derive " & \
               "more on the Addresses screen."
      end if
      put cwListAdd(tOutputs, cwTxOutput(tChange, tChangeRec["script"])) into tOutputs
   end if
   put waReviewText(tPays, tSel, tFee, tChange, tChangeRec, tVsize, tRate, \
         tSeq, tLock, tResult) into tOut
   if pAsPsbt is true then
      put waMakePsbt(tInputs, tOutputs, tSel, tLock) into tPsbt
      put tPsbt into sWaLastPsbt
      put tOut & return & "PSBT (unsigned, ready for a cosigner or a signer):" & \
            return & tPsbt & return into field "sd_out"
      uiStatus "Built a PSBT. It is on the Tools screen too.", "ok"
      exit waBuildSpend
   end if
   if pSign is not true then
      put tOut & return & "Nothing has been signed. Press Sign when every " & \
            "line above is what you meant." into field "sd_out"
      uiStatus "Built, unsigned: " & tVsize & " vB, fee " & waAmount(tFee) & ".", ""
      exit waBuildSpend
   end if
   if sWaKind is "watch" then
      throw "this is a watch-only wallet and holds no keys. Build a PSBT " & \
            "instead and sign it where the keys are."
   end if
   put waSignSpend(tInputs, tOutputs, tSel, tLock) into tRaw
   put sWaLastRaw into tRaw
   put cwTxDecode(tRaw) into tRec
   put tOut & return & "SIGNED." & return & \
         "txid    " & tRec["txid"] & return & \
         "size    " & tRec["size"] & " bytes, " & tRec["vsize"] & " vB" & return & \
         "raw     " & tRaw & return & return & \
         "Nothing has been broadcast. Press Broadcast to send it, or copy the " & \
         "raw transaction and push it from somewhere else." into field "sd_out"
   uiStatus "Signed " & tRec["txid"] & ".", "ok"
end waBuildSpend

function waSequenceNumber
   -- BIP-125 opt-in replaceability is a SEQUENCE NUMBER, not a flag in the
   -- transaction: anything below 0xFFFFFFFE says "this may be replaced", and
   -- a wallet that cannot bump a stuck transaction is a wallet whose only
   -- answer to a fee that turned out too low is to wait.
   set the defaultStack to the short name of this stack
   if the hilite of button "sd_rbf" is true then
      return kCwSeqRbf
   end if
   return kCwSeqNoRbf
end waSequenceNumber

function waInputType
   if sWaKind is "multisig" then
      return "p2wsh"
   end if
   return sWaScriptType
end waInputType

function waChangeType
   -- Change goes to the same script type as the wallet, which is what keeps
   -- it from standing out: a transaction whose change output is a different
   -- type than its other outputs tells a chain analyst which one it is.
   return waInputType()
end waChangeType

private function waMaxSpend pCoins, pOutTypes, pRate
   -- MAX: spend every unfrozen coin, pay the fee, and hand the rest to the
   -- one MAX output. There is no change, by construction.
   local tI, tCount, tRec, tSel, tTotal, tVsize, tFee, tOut, tIns
   put waEmptyList() into tSel
   put 0 into tTotal
   put cwListCount(pCoins) into tCount
   repeat with tI = 1 to tCount
      put pCoins[tI] into tRec
      if tRec["frozen"] is true then
         next repeat
      end if
      if waStrategy() is "manual" and tRec["selected"] is not true then
         next repeat
      end if
      put cwListAdd(tSel, tRec) into tSel
      add tRec["value"] to tTotal
   end repeat
   put cwSimpleInputs(waInputType(), cwListCount(tSel), sWaM, \
         cwListCount(sWaCosigners)) into tIns
   put cwEstimateVsize(tIns, pOutTypes) into tVsize
   put cwFeeFor(tVsize, pRate) into tFee
   put "" into tOut
   put tSel into tOut["selected"]
   put tFee into tOut["fee"]
   put 0 into tOut["change"]
   put tTotal into tOut["totalin"]
   put tVsize into tOut["vsize"]
   put "max" into tOut["strategy"]
   if cwListCount(tSel) < 1 then
      put false into tOut["ok"]
      put "no spendable coins" into tOut["why"]
      return tOut
   end if
   if tTotal <= tFee then
      put false into tOut["ok"]
      put "the fee (" & tFee & " sat) is more than everything this wallet has" \
            into tOut["why"]
      return tOut
   end if
   put true into tOut["ok"]
   put "MAX: every unfrozen coin, less the fee" into tOut["why"]
   return tOut
end waMaxSpend

private function waCoinAdvice pResult, pTarget
   local tOut
   put "You asked to pay " & waAmount(pTarget) & "." & return into tOut
   put "This wallet holds " & waAmount(sWaBalance["confirmed"]) & " confirmed" after tOut
   if sWaBalance["unconfirmed"] > 0 then
      put ", " & waAmount(sWaBalance["unconfirmed"]) & " unconfirmed" after tOut
   end if
   if sWaBalance["frozen"] > 0 then
      put ", " & waAmount(sWaBalance["frozen"]) & " frozen (thaw it on the " & \
            "Coins screen if you meant to spend it)" after tOut
   end if
   put "." & return after tOut
   if waStrategy() is "manual" then
      put "You are on 'Ticked coins', so only the coins you ticked were " & \
            "considered." & return after tOut
   end if
   return tOut
end waCoinAdvice

function waReviewText pPays, pSel, pFee, pChange, pChangeRec, pVsize, pRate, pSeq, pLock, pResult
   -- WHAT YOU ARE ABOUT TO AUTHORISE. Every output in full, every coin being
   -- spent, the fee both as an amount and as a rate, and where the change
   -- goes. Nothing is abbreviated: an address shown as "bc1q...8z3" is an
   -- address the reader cannot check, and checking it is the entire point of
   -- this panel.
   local tOut, tI, tCount, tRec, tTotalOut, tKey
   put "YOU ARE ABOUT TO AUTHORISE" & return & return into tOut
   put 0 into tTotalOut
   put cwListCount(pPays) into tCount
   repeat with tI = 1 to tCount
      put pPays[tI] into tRec
      add tRec["value"] to tTotalOut
      put "  pay    " & waAmount(tRec["value"]) & return after tOut
      put "  to     " & tRec["address"] & return after tOut
      if waIsMine(tRec["address"]) then
         put "         (an address of THIS wallet - a self-send)" & return after tOut
      end if
      if sWaLabels[tRec["address"]] is not "" then
         put "         labelled: " & sWaLabels[tRec["address"]] & return after tOut
      end if
      put return after tOut
   end repeat
   if pChange > 0 then
      put "  change " & waAmount(pChange) & return after tOut
      put "  back to " & pChangeRec["address"] & \
            "  (your own change chain, index " & pChangeRec["index"] & ")" & \
            return & return after tOut
   else
      put "  change none: " & pResult["why"] & return & return after tOut
   end if
   put "  fee    " & waAmount(pFee) & "  (" & pVsize & " vB at " & pRate & \
         " sat/vB)" & return after tOut
   put "         " & cwFeeRateLabel(pRate + 0) & return & return after tOut
   put "  spending " & cwListCount(pSel) & " coin(s), " & \
         waAmount(pResult["totalin"]) & " in total, chosen by " & \
         pResult["strategy"] & ":" & return after tOut
   put cwListCount(pSel) into tCount
   repeat with tI = 1 to tCount
      put pSel[tI] into tRec
      put "    " & waAmount(tRec["value"]) & "  " & char 1 to 16 of tRec["txid"] & \
            "..:" & tRec["vout"] & "  " & tRec["address"] & return after tOut
   end repeat
   put return & "  replaceable  " after tOut
   if pSeq < kCwSeqNoRbf then
      put "yes (BIP-125 opt-in RBF; the fee can be bumped later)" & return after tOut
   else
      put "NO. If the fee turns out too low this cannot be bumped." & return after tOut
   end if
   put "  locktime     " & pLock & return after tOut
   put "  network      " & sWaNetwork after tOut
   if sWaNetwork is "mainnet" then
      put "  - THIS IS REAL MONEY" after tOut
   end if
   put return after tOut
   return tOut
end waReviewText

function waSignSpend pInputs, pOutputs, pSel, pLock
   -- Sign every input. The key for each one is re-derived from the account
   -- node at the moment it is needed and dropped immediately after, so no
   -- private key outlives the loop iteration that used it.
   local tNode, tI, tCount, tRec, tAddrRec, tDigest, tSig, tSigs, tWits
   local tScripts, tAmounts, tType, tRaw, tVersion, tWs, tKeys
   put 2 into tVersion
   put waEmptyList() into tSigs
   put waEmptyList() into tWits
   put waInputType() into tType
   if tType is "p2pkh" then
      put 1 into tVersion
   end if
   put waAccountNode() into tNode
   if tNode["kind"] is not "private" and sWaKind is not "key" then
      throw "this wallet has no private key loaded, so it cannot sign."
   end if
   -- taproot commits to every input's scriptPubKey and amount, so those are
   -- gathered before the loop rather than per input
   put waEmptyList() into tScripts
   put waEmptyList() into tAmounts
   put cwListCount(pSel) into tCount
   repeat with tI = 1 to tCount
      put pSel[tI] into tRec
      put waRecordFor(tRec["address"]) into tAddrRec
      if tAddrRec is "" then
         throw "coin " & tI & " is at " & tRec["address"] & \
               ", which is not an address this wallet derives. It cannot be signed here."
      end if
      put cwListAdd(tScripts, tAddrRec["script"]) into tScripts
      put cwListAdd(tAmounts, tRec["value"]) into tAmounts
   end repeat
   repeat with tI = 1 to tCount
      put pSel[tI] into tRec
      put waRecordFor(tRec["address"]) into tAddrRec
      if sWaKind is "multisig" then
         put tAddrRec["witnessscript"] into tWs
         put waCosignerKeys(tAddrRec) into tKeys
         put cwSighash("p2wsh", tVersion, pInputs, pOutputs, tI, pLock, "", \
               tRec["value"], tWs, waEmptyList(), waEmptyList()) into tDigest
         put cwSignMultisig(tKeys, tDigest, tWs) into tSig
      else if tType is "p2tr" then
         put cwSighash("p2tr", tVersion, pInputs, pOutputs, tI, pLock, "", 0, "", \
               tScripts, tAmounts) into tDigest
         put cwSignTaproot(waSeckeyFor(tAddrRec), tDigest, "") into tSig
      else
         put cwSighash(tType, tVersion, pInputs, pOutputs, tI, pLock, \
               tAddrRec["pubkey"], tRec["value"], "", waEmptyList(), \
               waEmptyList()) into tDigest
         put cwSignInput(tType, waSeckeyFor(tAddrRec), tDigest, \
               tAddrRec["pubkey"]) into tSig
      end if
      put cwListAdd(tSigs, tSig["scriptsig"]) into tSigs
      put cwListAdd(tWits, tSig["witness"]) into tWits
   end repeat
   put empty into tNode
   put cwTxSerialize(tVersion, pInputs, pOutputs, pLock, tSigs, tWits) into tRaw
   put tRaw into sWaLastRaw
   return tRaw
end waSignSpend

private function waSeckeyFor pAddrRec
   -- The private key for one derived address, re-derived on demand. The
   -- record carries it when the account node held the private half; a
   -- watch-only wallet's records do not, and this is where that becomes a
   -- clean refusal rather than a signature over nothing.
   local tInfo
   if pAddrRec["seckey"] is not "" then
      return pAddrRec["seckey"]
   end if
   if sWaKind is "key" and sWaImportedWif is not empty then
      -- a function result cannot be subscripted in this dialect, so the
      -- record lands in a local first
      put cxWifDecode(sWaImportedWif) into tInfo
      return tInfo["seckey"]
   end if
   throw "no private key for " & pAddrRec["address"] & \
         ". This wallet is watch-only for that address."
end waSeckeyFor

private function waCosignerKeys pAddrRec
   -- The cosigner keys THIS wallet holds for a multisig input. Normally one:
   -- the other signatures come from the other cosigners, through a PSBT.
   local tKeys, tNode, tRec
   put waEmptyList() into tKeys
   if sWaAccountXprv is empty then
      return tKeys
   end if
   put cwXKeyDecode(sWaAccountXprv) into tNode
   put cwChainNode(tNode, pAddrRec["change"], pAddrRec["index"]) into tRec
   put empty into tNode
   return cwListAdd(tKeys, cxHexEncode(tRec["seckey"]))
end waCosignerKeys

function waMakePsbt pInputs, pOutputs, pSel, pLock
   -- A PSBT carrying everything a signer needs and nothing it does not: the
   -- witness UTXO (so BIP-143 has the amount it commits to), the redeem or
   -- witness script where the type needs one, the taproot internal key where
   -- it does, and the BIP-32 derivation so a signer can find the key without
   -- being told which one.
   local tMeta, tI, tCount, tRec, tAddrRec, tType, tKeys, tVersion, tOutMeta
   put waInputType() into tType
   put 2 into tVersion
   if tType is "p2pkh" then
      put 1 into tVersion
   end if
   put empty into tMeta
   put cwListCount(pSel) into tCount
   repeat with tI = 1 to tCount
      put pSel[tI] into tRec
      put waRecordFor(tRec["address"]) into tAddrRec
      put "" into tMeta[tI]
      put tAddrRec["script"] into tMeta[tI]["witnessutxoscript"]
      put tRec["value"] into tMeta[tI]["witnessutxovalue"]
      if tAddrRec["redeem"] is not "" then
         put tAddrRec["redeem"] into tMeta[tI]["redeemscript"]
      end if
      if tAddrRec["witnessscript"] is not "" then
         put tAddrRec["witnessscript"] into tMeta[tI]["witnessscript"]
      end if
      if tAddrRec["internalkey"] is not "" then
         put tAddrRec["internalkey"] into tMeta[tI]["tapinternalkey"]
      end if
      if tAddrRec["pubkey"] is not "" and sWaFingerprint is not "" then
         put waEmptyList() into tKeys
         put cwListAdd(tKeys, waBip32Record(tAddrRec)) into tKeys
         put tKeys into tMeta[tI]["bip32"]
      end if
   end repeat
   put empty into tOutMeta
   return cwPsbtCreate(tVersion, pInputs, pOutputs, pLock, tMeta, tOutMeta)
end waMakePsbt

private function waBip32Record pAddrRec
   local tRec
   put pAddrRec["pubkey"] into tRec["pubkey"]
   put sWaFingerprint into tRec["fingerprint"]
   put cwAccountPath(sWaScriptType, sWaNetwork, sWaAccount) & \
         pAddrRec["suffix"] into tRec["path"]
   return tRec
end waBip32Record
