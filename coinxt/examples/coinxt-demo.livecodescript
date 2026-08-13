script "coinXTDemo"

-- coinxt-demo.livecodescript - the phase-6 demo stack: the full CoinXT path,
-- from a mnemonic to a signed transaction, on one self-building card.
--
-- WHAT IT WALKS (the IMPLEMENTATION-PLAN phase-6 list): generate or import a
-- BIP-39 mnemonic, derive the standard accounts, show the Bitcoin (BIP-84 and
-- BIP-44) and Ethereum addresses, sign and verify a message, then build a
-- native-P2WPKH Bitcoin transaction and an EIP-1559 Ethereum transaction -
-- each shown DECODED, as human intent, beside the bytes that intent became.
-- CoinXT is a calculator, so every step here is synchronous and deterministic:
-- no session, no network, nothing to tear down on close.
--
-- HONESTY (the suite convention): this stack is verified statically
-- (tools/check-livecodescript.py) and NEEDS an on-engine OXT pass before any
-- runtime claim. Every cx* handler it calls is individually engine-proven
-- (the 2026-08-12 pass ran all 78), so a failure here is most likely this
-- stack's own wiring, not the library.
--
-- SETUP: install the packaged coinxt extension, then put the script layer in
-- the message path before opening this stack:
--
--    start using stack "coinxt"
--
-- SodiumXT is OPTIONAL: the Generate button draws entropy from sxRandomBytes
-- and disables itself with a clear message when SodiumXT is absent. Import
-- (typing a mnemonic) works without it.
--
-- THE LOOK is the suite UI kit, carried verbatim below between the marker
-- lines (master: tools/ui-kit.livecodescript at the suite root;
-- tools/check-ui-kit-drift.py holds every copy byte-identical). Change the
-- look in the master and re-carry it; never patch the block here.
--
-- CUSTODY, said plainly (CLAUDE.md rule 2, and read docs/getting-started.md):
-- this is a DEMO, not a wallet. The mnemonic sits in a visible field, keys
-- live briefly in engine variables, and OXT script memory is not locked or
-- reliably zeroed. Never type a mnemonic that guards real funds into it. The
-- prefilled mnemonic is BIP-39's public test mnemonic, burned by design. The
-- Bitcoin transaction's default prevout is SYNTHETIC (a made-up txid), so the
-- signed result is intentionally unbroadcastable.
--
-- The LCS lessons this file was written under (the family CLAUDE.md list): no
-- braces, no subscripted function results (a local first), constants literal
-- and before use, binary via numToByte/textEncode, zero-argument statement
-- calls BARE, no throw from inside a catch, and key variables cleared as soon
-- as each handler is done with them.

-- ---- constants ---------------------------------------------------------------
constant kTestMnemonic is "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
constant kPath84 is "m/84'/0'/0'/0/0"
constant kPath44 is "m/44'/0'/0'/0/0"
constant kPathEth is "m/44'/60'/0'/0/0"
constant kPathAccount84 is "m/84'/0'/0'"
constant kBtcVersion is 2
constant kBtcSequence is "4294967293"
constant kBtcLocktime is 0
constant kGweiWei is 1000000000

-- ==== SUITE UI KIT v1 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg is "237,239,243"
constant kUiAccent is "44,90,160"
constant kUiAccentText is "255,255,255"
constant kUiOk is "20,120,40"
constant kUiWarn is "160,90,10"
constant kUiBad is "170,30,30"
constant kUiMuted is "90,96,110"
constant kUiMono is "Courier"

-- The window chrome every adopter shares: stack size, ground color, the
-- title band, and the one status line under it (write it with uiStatus).
command uiChrome pTitle, pWidth, pHeight
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & ",30", 15
   set the opaque of field "uiTitle" to true
   set the backgroundColor of field "uiTitle" to kUiAccent
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   uiLabel "uiStatus", empty, "16,34," & (pWidth - 16) & ",52", 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiMuted
   end if
end uiStatus

-- A numbered bold section header.
command uiSection pName, pText, pRect
   uiLabel pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
end uiSection

-- A static caption (idempotent, borderless, transparent).
command uiLabel pName, pText, pRect, pSize
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
end uiLabel

-- A one-line entry field, mono because hex, addresses and paths are what
-- this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the textSize of field pName to 11
   set the textFont of field pName to kUiMono
end uiInput

-- A read-only output/list area: mono, scrolling.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to kUiMono
end uiArea

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiLabel "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v1 END ====

-- ---- probe state -------------------------------------------------------------
local sHaveCoin       -- "true" once the .lcb extension answered
local sHaveScript     -- "true" once the script layer answered
local sHaveSodium     -- "true" once sxRandomBytes answered

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   cdBuild
   cdProbe
end openStack

on closeStack
   -- CoinXT is stateless: nothing to free, nothing to stop. The one hygiene
   -- step is emptying the visible mnemonic so a reopened stack starts clean.
   put kTestMnemonic into field "cdMnemonic"
   put empty into field "cdPassphrase"
end closeStack

on mouseUp
   switch the short name of the target
      case "cdGenerate"
         cdGenerate
         break
      case "cdDerive"
         cdDerive
         break
      case "cdSign"
         cdSignMessage
         break
      case "cdBtcBuild"
         cdBtcBuild
         break
      case "cdEthBuild"
         cdEthBuild
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; the kit owns the look) --------------------
command cdBuild
   if there is a field "uiTitle" then
      exit cdBuild
   end if
   lock screen
   uiChrome "CoinXT - from a mnemonic to a signed transaction", 780, 940

   -- 1. wallet
   uiSection "cdSec1", "1. Wallet: mnemonic in, addresses out", "16,58,764,76"
   uiInput "cdMnemonic", "16,80,600,124"
   put kTestMnemonic into field "cdMnemonic"
   uiButton "cdGenerate", "Generate new", "612,80,764,104"
   uiButton "cdDerive", "Derive", "612,108,764,132"
   uiLabel "cdPassLabel", "Passphrase (optional):", "16,128,180,146", 11
   uiInput "cdPassphrase", "184,128,420,148"
   uiArea "cdWalletOut", "16,152,764,258"

   -- 2. sign + verify
   uiSection "cdSec2", "2. Sign and verify a message (the BIP-84 key)", "16,264,764,282"
   uiInput "cdMessage", "16,286,600,308"
   put "hello coinxt" into field "cdMessage"
   uiButton "cdSign", "Sign + verify", "612,286,764,310"
   uiArea "cdSignOut", "16,314,764,392"

   -- 3. bitcoin transaction
   uiSection "cdSec3", "3. Bitcoin: build + sign a native-P2WPKH spend (synthetic prevout)", "16,398,764,416"
   uiLabel "cdBtcL1", "prev txid / vout / input sat:", "16,420,196,438", 11
   uiInput "cdBtcPrev", "200,420,560,440"
   put "2222222222222222222222222222222222222222222222222222222222222222" into field "cdBtcPrev"
   uiInput "cdBtcVout", "566,420,610,440"
   put "0" into field "cdBtcVout"
   uiInput "cdBtcIn", "616,420,700,440"
   put "100000" into field "cdBtcIn"
   uiLabel "cdBtcL2", "pay to (bech32) / amount sat:", "16,444,196,462", 11
   uiInput "cdBtcDest", "200,444,610,464"
   uiInput "cdBtcOut", "616,444,700,464"
   put "99000" into field "cdBtcOut"
   uiButton "cdBtcBuild", "Build + sign", "706,432,764,456"
   uiArea "cdBtcOutArea", "16,470,764,600"

   -- 4. ethereum transaction
   uiSection "cdSec4", "4. Ethereum: build + sign an EIP-1559 transaction", "16,606,764,624"
   uiLabel "cdEthL1", "nonce / prio gwei / max gwei / gas:", "16,628,236,646", 11
   uiInput "cdEthNonce", "240,628,290,648"
   put "0" into field "cdEthNonce"
   uiInput "cdEthPrio", "296,628,346,648"
   put "2" into field "cdEthPrio"
   uiInput "cdEthMax", "352,628,402,648"
   put "30" into field "cdEthMax"
   uiInput "cdEthGas", "408,628,470,648"
   put "21000" into field "cdEthGas"
   uiLabel "cdEthL2", "to (0x...) / value (WEI, hex) / chain id:", "16,652,236,670", 11
   uiInput "cdEthTo", "240,652,560,672"
   uiInput "cdEthValue", "566,652,700,672"
   put "2386f26fc10000" into field "cdEthValue"
   uiInput "cdEthChain", "706,652,764,672"
   put "1" into field "cdEthChain"
   uiButton "cdEthBuild", "Build + sign", "706,676,764,700"
   uiArea "cdEthOutArea", "16,704,764,834"

   uiFooter \
         "This is a demo, not a wallet: the mnemonic is on screen, keys pass" \
         & " through unlocked engine memory, and nothing here is custody." \
         & " Never type a mnemonic that guards real funds. The default Bitcoin" \
         & " prevout is synthetic, so its signed transaction cannot broadcast." \
         & " Review every decoded line before you sign anything, anywhere.", \
         "16,842,764,930"
   unlock screen
end cdBuild

-- ---- probes (fail closed, name the missing piece) ----------------------------
command cdProbe
   local tStatus
   put empty into sHaveCoin
   put empty into sHaveScript
   put empty into sHaveSodium
   try
      if cxKeccak256Len() is 32 then
         put "true" into sHaveCoin
      end if
   catch tStatus
      -- extension absent; reported below
   end try
   try
      if cxHexEncode(numToByte(0)) is "00" then
         put "true" into sHaveScript
      end if
   catch tStatus
      -- script layer not in the message path; reported below
   end try
   try
      if the number of bytes of sxRandomBytes(4) is 4 then
         put "true" into sHaveSodium
      end if
   catch tStatus
      -- optional; only Generate needs it
   end try
   put empty into tStatus
   if sHaveCoin is not "true" then
      uiStatus "CoinXT extension NOT loaded: install org.openxtalk.library.coin first.", "bad"
   else if sHaveScript is not "true" then
      uiStatus "CoinXT script layer NOT in the message path: start using stack" && quote & "coinxt" & quote & ".", "bad"
   else if sHaveSodium is not "true" then
      uiStatus "Ready (SodiumXT absent: Generate is disabled; Import + Derive work).", "warn"
   else
      uiStatus "Ready: CoinXT extension + script layer + SodiumXT entropy all present.", "ok"
   end if
end cdProbe

-- ---- 1. wallet ---------------------------------------------------------------
command cdGenerate
   local tErr
   if sHaveSodium is not "true" then
      put "Generate needs SodiumXT (sxRandomBytes) for entropy. Install it, or type a mnemonic." into field "cdWalletOut"
      exit cdGenerate
   end if
   try
      -- 16 bytes of entropy is a 12-word mnemonic; the caller supplies the
      -- randomness (CoinXT has no ambient RNG for key material, by rule)
      put cxMnemonicFromEntropy(sxRandomBytes(16)) into field "cdMnemonic"
      put "Fresh 12-word mnemonic generated. Write real ones on paper, never in a demo." into field "cdWalletOut"
   catch tErr
      put "Generate failed:" && tErr into field "cdWalletOut"
   end try
end cdGenerate

command cdDerive
   local tMnemonic, tSeed, tMaster, tNode, tOut, tErr, tFailed
   put false into tFailed
   put cdNormalizedMnemonic() into tMnemonic
   -- Validate FIRST, the documented pattern: cxMnemonicToSeed accepts any
   -- string by BIP-39 design, so a typo yields a perfectly good seed for the
   -- wrong wallet. Only a checksum-valid mnemonic goes further here.
   try
      if cxMnemonicValidate(tMnemonic) is not true then
         put "Mnemonic REFUSED: the BIP-39 checksum does not close." \
               && "One mistyped word means a different wallet, so nothing was derived." into field "cdWalletOut"
         exit cdDerive
      end if
      put cxMnemonicToSeed(tMnemonic, field "cdPassphrase") into tSeed
      put cxHdFromSeed(tSeed) into tMaster
      put empty into tSeed
      put "DERIVED (account 0, external chain, index 0):" & return into tOut
      put cxHdDerivePath(tMaster, kPath84) into tNode
      put "  BTC bech32 " & kPath84 & ":  " & cxBtcAddressP2WPKH(tNode["pubkey"]) & return after tOut
      put cxBtcAddressP2WPKH(tNode["pubkey"]) into field "cdBtcDest"
      put cxHdDerivePath(tMaster, kPath44) into tNode
      put "  BTC legacy " & kPath44 & ":  " & cxBtcAddressP2PKH(tNode["pubkey"]) & return after tOut
      put cxHdDerivePath(tMaster, kPathEth) into tNode
      put "  ETH        " & kPathEth & ": " & cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) & return after tOut
      put cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) into field "cdEthTo"
      put cxHdDerivePath(tMaster, kPathAccount84) into tNode
      put "  account xpub (" & kPathAccount84 & "): " & return & "    " & cxXpub(cxHdNeuter(tNode)) & return after tOut
      put "  (both transaction sections below now pay YOU: self-spends)" & return after tOut
   catch tErr
      put true into tFailed
   end try
   -- key hygiene: the node arrays carried the private keys; drop them the
   -- moment the addresses are on screen (the tx sections re-derive on click)
   put empty into tMaster
   put empty into tNode
   put empty into tSeed
   if tFailed then
      put "Derive failed:" && tErr into field "cdWalletOut"
   else
      put tOut into field "cdWalletOut"
   end if
end cdDerive

-- The mnemonic field, squeezed through the library's own normalizer so what
-- the user SEES validated is what the seed is derived from.
function cdNormalizedMnemonic
   return cxMnemonicNormalize(field "cdMnemonic")
end cdNormalizedMnemonic

-- ---- 2. sign + verify --------------------------------------------------------
command cdSignMessage
   local tNode, tDigest, tSig, tOut, tErr, tFailed, tTampered
   put false into tFailed
   try
      put cdKeyNode(kPath84) into tNode
      put cxSha256(textEncode(field "cdMessage", "UTF-8")) into tDigest
      put cxSign(tNode["seckey"], tDigest) into tSig
      put "message digest (SHA-256): " & cxHexEncode(tDigest) & return into tOut
      put "signature (RFC 6979, compact): " & cxHexEncode(tSig) & return after tOut
      put "signature (DER): " & cxHexEncode(cxDerEncode(tSig)) & return after tOut
      put "verifies against the signing key: " & cxVerify(tNode["pubkey"], tDigest, tSig) & return after tOut
      -- and the negative, because a verifier that cannot say no proves nothing
      put cxSha256(textEncode(field "cdMessage" & ".", "UTF-8")) into tTampered
      put "verifies against a TAMPERED digest: " & cxVerify(tNode["pubkey"], tTampered, tSig) & return after tOut
   catch tErr
      put true into tFailed
   end try
   put empty into tNode
   if tFailed then
      put "Sign failed:" && tErr into field "cdSignOut"
   else
      put tOut into field "cdSignOut"
   end if
end cdSignMessage

-- Re-derive the requested node from the mnemonic field on demand, so no
-- private key outlives the click that needed it.
function cdKeyNode pPath
   local tMnemonic, tSeed, tMaster, tNode
   put cdNormalizedMnemonic() into tMnemonic
   if cxMnemonicValidate(tMnemonic) is not true then
      throw "the mnemonic in section 1 does not validate; fix it and Derive first"
   end if
   put cxMnemonicToSeed(tMnemonic, field "cdPassphrase") into tSeed
   put cxHdFromSeed(tSeed) into tMaster
   put empty into tSeed
   put cxHdDerivePath(tMaster, pPath) into tNode
   put empty into tMaster
   return tNode
end cdKeyNode

-- ---- 3. bitcoin --------------------------------------------------------------
command cdBtcBuild
   local tNode, tPub, tInSat, tOutSat, tDest, tDecoded, tProgram
   local tOutpoint, tSpk, tScriptCode, tOutRec, tDigest, tSig, tWit, tTx, tTxid
   local tOut, tErr, tFailed
   put false into tFailed
   try
      put field "cdBtcIn" into tInSat
      put field "cdBtcOut" into tOutSat
      if tInSat is not an integer or tOutSat is not an integer \
            or tInSat <= 0 or tOutSat <= 0 or tOutSat >= tInSat then
         throw "amounts must be positive integers with output < input (the difference IS the fee)"
      end if
      put word 1 of field "cdBtcDest" into tDest
      put cxSegwitAddressDecode("bc", tDest) into tDecoded
      put tDecoded["program"] into tProgram
      if tDecoded["version"] is not 0 or the number of bytes of tProgram is not 20 then
         throw "this demo pays P2WPKH only: a version-0 address with a 20-byte program"
      end if
      put cdKeyNode(kPath84) into tNode
      put tNode["pubkey"] into tPub
      put cxHexEncode(cxBtcOutpoint(word 1 of field "cdBtcPrev", field "cdBtcVout")) into tOutpoint
      put "0014" & cxHexEncode(tProgram) into tSpk
      put cxHexEncode(cxBtcOutput(tOutSat, tSpk)) into tOutRec
      -- BIP-143 P2WPKH scriptCode is the matching P2PKH script of OUR key
      put "76a914" & cxHexEncode(cxHash160(tPub)) & "88ac" into tScriptCode
      put cxBtcSighashSegwit(kBtcVersion, tOutpoint, kBtcSequence, 1, tScriptCode, \
            tInSat, tOutRec, kBtcLocktime, 1) into tDigest
      put cxDerEncode(cxSign(tNode["seckey"], tDigest)) & numToByte(1) into tSig
      put cxBtcWitness(cxHexEncode(tSig) & comma & cxHexEncode(tPub)) into tWit
      put cxBtcTxEncode(kBtcVersion, tOutpoint, "", kBtcSequence, cxHexEncode(tWit), \
            tOutRec, kBtcLocktime) into tTx
      put cxBtcTxid(kBtcVersion, tOutpoint, "", kBtcSequence, tOutRec, kBtcLocktime) into tTxid
      put "YOU ARE SIGNING (review every line before any real signer):" & return into tOut
      put "  spend: " & tInSat && "sat from" && cxBtcAddressP2WPKH(tPub) & return after tOut
      put "  pay:   " & tOutSat && "sat ->" && tDest & return after tOut
      put "  fee:   " & (tInSat - tOutSat) && "sat (input minus output; nothing else)" & return after tOut
      put "  seq " & kBtcSequence && "(opt-in RBF), version" && kBtcVersion & comma && "locktime" && kBtcLocktime & return after tOut
      put "  the default prevout is SYNTHETIC: this cannot broadcast" & return after tOut
      put "sighash (BIP-143): " & cxHexEncode(tDigest) & return after tOut
      put "txid: " & tTxid & return after tOut
      put "raw tx: " & cxHexEncode(tTx) & return after tOut
   catch tErr
      put true into tFailed
   end try
   put empty into tNode
   if tFailed then
      put "Build failed:" && tErr into field "cdBtcOutArea"
   else
      put tOut into field "cdBtcOutArea"
   end if
end cdBtcBuild

-- ---- 4. ethereum -------------------------------------------------------------
command cdEthBuild
   local tNode, tNonce, tPrio, tMax, tGas, tChain, tTo, tToHex, tValHex
   local tDigest, tSig, tRecId, tRes, tFrom, tOut, tErr, tFailed
   put false into tFailed
   try
      put field "cdEthNonce" into tNonce
      put field "cdEthPrio" into tPrio
      put field "cdEthMax" into tMax
      put field "cdEthGas" into tGas
      put field "cdEthChain" into tChain
      if tNonce is not an integer or tGas is not an integer or tChain is not an integer \
            or tPrio is not an integer or tMax is not an integer \
            or tNonce < 0 or tGas <= 0 or tChain <= 0 or tPrio <= 0 or tMax < tPrio then
         throw "nonce/gas/chain must be integers, fees positive gwei with max >= prio"
      end if
      if tPrio > 9000000 or tMax > 9000000 then
         -- 9e6 gwei * 1e9 approaches 2^53; beyond that an xTalk number would
         -- silently lose wei precision, the exact failure the hex path avoids
         throw "gwei fields above 9000000 need the raw-hex path; this demo caps them"
      end if
      put word 1 of field "cdEthTo" into tTo
      put cdEthAddressHex(tTo) into tToHex
      put cdCleanHex(field "cdEthValue") into tValHex
      get cxHexDecode(tValHex)   -- fail closed on a malformed value before signing
      put cdKeyNode(kPathEth) into tNode
      put cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) into tFrom
      put cxEth1559Sighash(tChain, tNonce, cdIntToHex(tPrio * kGweiWei), \
            cdIntToHex(tMax * kGweiWei), tGas, tToHex, tValHex, "") into tDigest
      put cxSignRecoverable(tNode["seckey"], tDigest) into tSig
      put byteToNum(byte 65 of tSig) into tRecId
      put cxEth1559Encode(tChain, tNonce, cdIntToHex(tPrio * kGweiWei), \
            cdIntToHex(tMax * kGweiWei), tGas, tToHex, tValHex, "", tRecId, \
            cxHexEncode(byte 1 to 32 of tSig), cxHexEncode(byte 33 to 64 of tSig)) into tRes
      put "YOU ARE SIGNING (review every line before any real signer):" & return into tOut
      put "  from:  " & tFrom & return after tOut
      put "  to:    0x" & tToHex & return after tOut
      put "  value: 0x" & tValHex && "wei (hex; wei-scale numbers exceed xTalk integers)" & return after tOut
      put "  fees:  prio" && tPrio && "gwei, max" && tMax && "gwei, gas" && tGas & return after tOut
      put "  chain id" && tChain && "(EIP-1559 typed, empty data, no access list)" & return after tOut
      put "signing hash: " & cxHexEncode(tDigest) & return after tOut
      put "tx hash: " & tRes["txhash"] & return after tOut
      put "raw tx (0x02 envelope): " & tRes["raw"] & return after tOut
   catch tErr
      put true into tFailed
   end try
   put empty into tNode
   put empty into tSig
   if tFailed then
      put "Build failed:" && tErr into field "cdEthOutArea"
   else
      put tOut into field "cdEthOutArea"
   end if
end cdEthBuild

-- ---- small helpers -----------------------------------------------------------
-- Strip an optional 0x and refuse anything that is not clean hex.
function cdCleanHex pText
   local tHex
   put word 1 of pText into tHex
   if char 1 to 2 of tHex is "0x" then
      delete char 1 to 2 of tHex
   end if
   if tHex is empty then
      throw "an empty hex field"
   end if
   get cxHexDecode(tHex)   -- throws on odd length or a non-hex character
   return toLower(tHex)
end cdCleanHex

-- An Ethereum address for the encoder: 20 bytes of hex, checksum-checked when
-- the caller wrote it in mixed case (EIP-55's whole point), accepted plain
-- when all-lowercase (no checksum was claimed).
function cdEthAddressHex pAddress
   local tHex, tPlain
   put cdCleanHex(pAddress) into tHex
   if the number of chars of tHex is not 40 then
      throw "an Ethereum address is 20 bytes (40 hex characters)"
   end if
   put word 1 of pAddress into tPlain
   if char 1 to 2 of tPlain is "0x" then
      delete char 1 to 2 of tPlain
   end if
   if tPlain is not toLower(tPlain) then
      if cxEthAddressIsChecksummed("0x" & tPlain) is not true then
         throw "the mixed-case address FAILS its EIP-55 checksum; refusing rather than guessing"
      end if
   end if
   return tHex
end cdEthAddressHex

-- Minimal big-endian hex of a nonnegative integer (gwei * 1e9 stays exact
-- well under 2^53; the guard in cdEthBuild keeps it there).
function cdIntToHex pN
   local tN, tBytes
   put pN into tN
   if tN is 0 then
      return "00"
   end if
   put empty into tBytes
   repeat while tN > 0
      put numToByte(tN mod 256) & tBytes into tBytes
      put tN div 256 into tN
   end repeat
   return cxHexEncode(tBytes)
end cdIntToHex
