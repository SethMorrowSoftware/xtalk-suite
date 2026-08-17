-- onionxt-tests.livecodescript - OnionXT's self-test harness.
--
-- Formatted like the sibling family's test harnesses (SodiumXT's
-- sodium-tests.livecodescript: module-level sLog/sPass/sFail, an sxCheck
-- assertion helper, sxSection headers, known-answer vectors, and negative-path
-- checks under try/catch). Start using this stack alongside onionxt.livecodescript
-- and call oxSelfTest() (from a message box, a button, or the "Run self-test"
-- button on examples/onionxt-demo.livecodescript's About tab).
--
-- WHY this suite is PURE and OFFLINE, unlike SodiumXT's (read this before you
-- extend it): SodiumXT is stateless compute with zero I/O, so its self-test can
-- exercise every primitive end-to-end with no external process. OnionXT's whole
-- job is long-lived network I/O against a real tor daemon (CLAUDE.md: "OnionXT
-- owns long-lived network state... is asynchronous and event-driven"), and a
-- synchronous test function fundamentally cannot wait for an async callback
-- without blocking the one interpreter thread, which the library forbids
-- (CLAUDE.md: "never block the interpreter thread on the network"). So this
-- harness deliberately tests only what is reachable WITHOUT a daemon:
--   1. the pure address / base32 logic (docs/04), cross-checked against the
--      same known-answer vectors pinned in tools/onion-kat.py;
--   2. the fail-closed contract on every public command (CLAUDE.md rule 4:
--      argument validation, "not authenticated yet", unknown-handle misses);
--   3. idempotent teardown (duplicate close/remove/disconnect/shutdown);
--   4. the two SodiumXT ABI-6 primitives OnionXT composes (sxSignSeedToExpandedKey,
--      sxHmacSha256) against their pinned vectors - gated on SodiumXT being loaded,
--      skipped (not failed) otherwise. Needs SodiumXT ABI >= 6, not a tor daemon;
--   5. the inbound loopback guard's socket-id parse and verdict (section 10),
--      which is pure string work on the ids the engine hands oxPeerAccepted, so
--      it is testable offline even though the accept path itself is not.
-- The actual wire handshakes (SOCKS5 dial, control auth, ADD_ONION) are an
-- on-engine / integration concern: run examples/onionxt-demo.livecodescript or
-- examples/onion-roundtrip against a real tor daemon for those (see
-- IMPLEMENTATION-PLAN.md phase 4 and CLAUDE.md's on-engine VERIFY checklist).
--
-- CAUTION - side effects on shared state: OnionXT's connection/service/stream
-- state is a script-local singleton shared by the whole message path (not
-- per-object), so the idempotent-teardown section below really does call
-- oxDisconnectControl / oxShutdown. If a live demo session (or any other code
-- using this same OnionXT instance) currently has an open control connection,
-- streams, or published services, running oxSelfTest CLOSES THEM as part of
-- proving teardown is idempotent. Run this in a fresh session, or expect it to
-- tear down whatever is currently open.
--
-- STATUS: confirmed on-engine: the About-tab self-test run (via the bundled
-- standalone) executes this harness on a real engine (CLAUDE.md as-built
-- notes). Everything here is pure script with no socket I/O of its own, so
-- the risk surface is much smaller than the library itself.

-- Two real, published v3 onion addresses, the same vectors pinned in
-- tools/onion-kat.py, so the Python KAT and this livecodescript suite agree.
constant kTestAddrTorProject = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kTestAddrDuckDuckGo = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"

local sLog
local sPass
local sFail

-- ==========================================================================
-- Entry point.
-- ==========================================================================

function oxSelfTest
   put empty into sLog
   put 0 into sPass
   put 0 into sFail

   testVersionAndCapabilities
   testInitialState
   testFailClosedArguments
   testUnknownHandlesAreCleanMisses
   testIdempotentTeardown
   testAddressRoundTrip
   testAddressNegativePaths
   testSodiumComposition
   testConfigurationSetters
   testLoopbackGuard

   local tSummary
   put sPass & " passed, " & sFail & " failed" into tSummary
   return tSummary & return & "----------------------------------------" & return & sLog
end oxSelfTest

-- ==========================================================================
-- Assertion helpers (SodiumXT's sxCheck / sxSection convention).
-- ==========================================================================

private command oxCheck pCondition, pLabel
   if pCondition then
      add 1 to sPass
      put sLog & "  ok   " & pLabel & return into sLog
   else
      add 1 to sFail
      put sLog & "  FAIL " & pLabel & return into sLog
   end if
end oxCheck

private command oxSection pTitle
   put sLog & return & "-- " & pTitle & " --" & return into sLog
end oxSection

-- ==========================================================================
-- Section 1: version string and the transport capability probe.
-- ==========================================================================

private command testVersionAndCapabilities
   oxSection "version and capabilities"
   oxCheck (oxVersion() is not empty), "oxVersion reports a non-empty string"

   local tInfo
   put oxTransportInfo() into tInfo
   oxCheck (tInfo["transport"] is "ox"), "oxTransportInfo advertises the ox transport"
   oxCheck (tInfo["version"] is oxVersion()), "oxTransportInfo version matches oxVersion"
   -- The three capability flags are always present, true or false, whether or
   -- not SodiumXT is loaded (CLAUDE.md rule 1: a missing primitive degrades to
   -- a clear flag/error, never a crash).
   oxCheck (tInfo["safeCookieAuth"] is true or tInfo["safeCookieAuth"] is false), \
      "safeCookieAuth capability flag is a boolean"
   oxCheck (tInfo["deterministicOnion"] is true or tInfo["deterministicOnion"] is false), \
      "deterministicOnion capability flag is a boolean"
   oxCheck (tInfo["offlineAddress"] is true or tInfo["offlineAddress"] is false), \
      "offlineAddress capability flag is a boolean"
end testVersionAndCapabilities

-- ==========================================================================
-- Section 2: state before any connection has ever been made. Control state is
-- a script-local singleton shared by the whole message path (CLAUDE.md: state
-- is script-local, not per-object), so if this session already called
-- oxConnectControl (for example via examples/onionxt-demo.livecodescript's
-- Status tab) these checks would otherwise be a false failure, not a real bug.
-- Skip them with a clear note rather than asserting something session order
-- can make untrue; run oxSelfTest first, before connecting, for full coverage.
-- ==========================================================================

private command testInitialState
   oxSection "initial state (before oxConnectControl)"
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: this session is already control-authenticated; " & \
         "run oxSelfTest before oxConnectControl for this section)" & return into sLog
      exit testInitialState
   end if
   oxCheck (oxBootstrapProgress() is 0), "bootstrap progress starts at 0"
   oxCheck (not oxIsReady()), "oxIsReady is false before connecting"
   oxCheck (not oxIsControlAuthenticated()), "control is not authenticated before connecting"
end testInitialState

-- ==========================================================================
-- Section 3: fail-closed argument validation (CLAUDE.md rule 4). Every one of
-- these needs no network access; the library rejects the request before it
-- ever opens a socket or sends a command.
-- ==========================================================================

private command testFailClosedArguments
   oxSection "fail-closed argument validation"

   -- oxDial / oxCreateService* are COMMANDS: invoke them as statements and read
   -- their handle-or-error from `the result` (you cannot call a command with
   -- function-call parentheses; that syntax needs a `function` handler). Only
   -- oxAddressFromPublicKey below is a function, so it takes parentheses.
   local tResult
   oxDial empty, 80
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects an empty host"

   oxDial "example.onion", 99999
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects a port outside 1..65535"

   -- These two prove the pre-auth fail-closed guard specifically, so they are
   -- only meaningful while nothing has authenticated yet in this session (see
   -- the note on testInitialState above); skip rather than false-fail if a
   -- prior oxConnectControl in this session already succeeded.
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: pre-auth guard on oxCreateService* needs a " & \
         "session that has not authenticated yet)" & return into sLog
   else
      oxCreateService 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateService fails closed without an authenticated control connection"

      oxCreateServiceFromSeed testZeroSeed(), 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateServiceFromSeed also fails closed without an authenticated control connection"
   end if

   put oxAddressFromPublicKey("short") into tResult
   oxCheck (tResult begins with "OnionXT:"), \
      "oxAddressFromPublicKey rejects a public key that is not 32 bytes"
end testFailClosedArguments

-- ==========================================================================
-- Section 4: an unknown / stale handle is a clean miss, never a crash
-- (CLAUDE.md handles-and-state: "a stale or closed id must be a clean no-op /
-- error, never a crash").
-- ==========================================================================

private command testUnknownHandlesAreCleanMisses
   oxSection "unknown handles are clean misses"
   local tUnknown, tResult
   put 999999 into tUnknown

   -- oxStreamState / oxServiceAddress / oxServiceIsReady are functions (parens);
   -- oxSetStreamCallback / oxWrite are commands (statement + `the result`).
   oxCheck (oxStreamState(tUnknown) is "unknown"), "an unknown stream handle reports state unknown"
   oxCheck (oxServiceAddress(tUnknown) is empty), "an unknown service handle has no address"
   oxCheck (not oxServiceIsReady(tUnknown)), "an unknown service handle is not ready"

   oxSetStreamCallback tUnknown, "someHandler"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxSetStreamCallback on an unknown handle fails closed"

   oxWrite tUnknown, "x"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxWrite to an unknown/unconnected stream fails closed"
end testUnknownHandlesAreCleanMisses

-- ==========================================================================
-- Section 5: idempotent teardown. Every close/remove/disconnect is safe to
-- call twice, and safe to call on something that was never opened.
-- ==========================================================================

private command testIdempotentTeardown
   oxSection "idempotent teardown (duplicate close is a no-op)"
   local tOk
   put true into tOk
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
      put false into tOk
   end try
   oxCheck tOk, "double close / remove / disconnect / shutdown never throws"
   oxCheck (not oxIsControlAuthenticated()), "control is disconnected after teardown"
end testIdempotentTeardown

-- ==========================================================================
-- Section 6: the v3 address <-> public key mapping, cross-checked against two
-- REAL, published onion addresses (the same vectors tools/onion-kat.py pins).
-- No crypto here except the optional SHA3-256 checksum re-encode, which is
-- skipped (not failed) when SodiumXT does not provide it.
-- ==========================================================================

private command testAddressRoundTrip
   oxSection "v3 address <-> public key (docs/04), against real onions"
   testOneKnownAddress kTestAddrTorProject, "torproject.org's onion"
   testOneKnownAddress kTestAddrDuckDuckGo, "DuckDuckGo's onion"
end testAddressRoundTrip

private command testOneKnownAddress pAddress, pLabel
   local tPub, tInfo
   put oxPublicKeyFromAddress(pAddress) into tPub
   oxCheck (the number of bytes of tPub is 32), \
      pLabel & ": oxPublicKeyFromAddress returns a 32-byte public key"
   oxCheck oxIsValidAddress(pAddress), pLabel & ": oxIsValidAddress accepts it"

   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (oxAddressFromPublicKey(tPub) is pAddress), \
         pLabel & ": oxAddressFromPublicKey re-encodes the exact same address"
   else
      put sLog & "  --   (skipped: " & pLabel & " re-encode needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testOneKnownAddress

-- ==========================================================================
-- Section 7: structural negative paths. A malformed address must not crash
-- and must be rejected, never silently accepted (CLAUDE.md rule 4).
-- ==========================================================================

private command testAddressNegativePaths
   oxSection "address negative paths"
   oxCheck (not oxIsValidAddress("tooshort.onion")), "a too-short address is rejected"
   oxCheck (not oxIsValidAddress("not a valid onion address at all")), "garbage input is rejected"
   oxCheck (oxPublicKeyFromAddress("short.onion") is empty), \
      "a malformed address yields an empty key, not a crash"

   -- Flip the first character of a known-good address (to something else in
   -- the base32 alphabet); it must no longer validate, either structurally (if
   -- the flip breaks the version byte) or by checksum when SHA3-256 is
   -- available.
   local tTampered, tInfo
   put kTestAddrTorProject into tTampered
   if char 1 of tTampered is "2" then
      put "3" into char 1 of tTampered
   else
      put "2" into char 1 of tTampered
   end if
   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (not oxIsValidAddress(tTampered)), "a tampered address fails checksum validation"
   else
      put sLog & "  --   (skipped: tamper-detection needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testAddressNegativePaths

-- ==========================================================================
-- Section 8: the two SodiumXT ABI-6 primitives OnionXT composes, against the
-- known-answer vectors pinned in tools/onion-kat.py. Gated on availability
-- (oxTransportInfo): skipped, not failed, when SodiumXT (ABI >= 6) is not loaded.
-- These call the sx* public handlers directly, confirming the deterministic-onion
-- (gap #1) and SAFECOOKIE (gap #3) compositions produce the right bytes.
-- ==========================================================================

private command testSodiumComposition
   oxSection "SodiumXT ABI-6 composition (docs/08 gaps #1, #3)"
   local tInfo
   put oxTransportInfo() into tInfo

   -- Gap #1 (SHIPPED): sxSignSeedToExpandedKey(seed = 0x42 x 32), 64-byte result.
   if tInfo["deterministicOnion"] is true then
      local tExpanded, tExpectExp
      put "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6ee" & \
          "da66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90" into tExpectExp
      put sxSignSeedToExpandedKey(testRepeatByte(66, 32)) into tExpanded
      oxCheck (testHex(tExpanded) is tExpectExp), \
         "sxSignSeedToExpandedKey(seed 0x42 x 32) matches the pinned expanded-key vector"
   else
      put sLog & "  --   (skipped: sxSignSeedToExpandedKey needs SodiumXT ABI >= 6)" & return into sLog
   end if

   -- Gap #3 (SHIPPED): sxHmacSha256("Jefe","what do ya want for nothing?") RFC 4231 TC2.
   if tInfo["safeCookieAuth"] is true then
      local tMac, tExpectMac
      put "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" into tExpectMac
      put sxHmacSha256(textEncode("Jefe", "UTF-8"), textEncode("what do ya want for nothing?", "UTF-8")) into tMac
      oxCheck (testHex(tMac) is tExpectMac), \
         "sxHmacSha256 (RFC 4231 Test Case 2) matches the pinned HMAC vector"
   else
      put sLog & "  --   (skipped: sxHmacSha256 needs SodiumXT ABI >= 6)" & return into sLog
   end if
end testSodiumComposition

-- ==========================================================================
-- Section 9: the configuration setters.
--
-- WHAT THIS PROVES, AND WHAT IT DOES NOT. Each of these is a one-line
-- assignment into a script local, and every reader of those locals
-- (effectiveSocksPort, effectiveControlPort, the AUTHENTICATE path, oxDispatch)
-- is private and needs a live daemon to reach. So this section cannot show that
-- a set port is the port Tor is dialled on - that is a live-Tor claim and it
-- stays one.
--
-- What it CAN show, offline, is the part that actually breaks: that the handler
-- is there under the name the docs give, that it accepts its argument without
-- throwing, that setting configuration does not disturb the connection state
-- machine, and that empty restores the built-in default. Before this section
-- existed, a setter could have been renamed or deleted and every gate in the
-- repo would still have been green.
--
-- The restore at the end is not tidiness. Control state is a script-local
-- singleton shared by the whole message path (see section 2), so a harness that
-- left sSocksPort pointing at a junk port would break the NEXT thing this
-- session did - including the live-Tor pass this file is meant to precede.
-- ==========================================================================

private command testConfigurationSetters
   oxSection "configuration setters (offline: callable and inert)"
   local tWasReady, tWasAuthed, tProgress
   put oxIsReady() into tWasReady
   put oxIsControlAuthenticated() into tWasAuthed
   put oxBootstrapProgress() into tProgress

   -- Loopback-locked by design: the PORT is settable, the host never is.
   oxSetSocksPort 19050
   oxSetControlPort 19051
   oxCheck true, "oxSetSocksPort and oxSetControlPort accept a port"
   oxSetControlPassword "not-a-real-password"
   oxCheck true, "oxSetControlPassword accepts a password"
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback "onPeer"
   oxCheck true, "the status and peer callback names are settable"
   oxSetCallbackOwner the long id of me
   oxCheck true, "oxSetCallbackOwner accepts an object long id"

   -- Configuration must not touch the connection state machine. If any of
   -- these moved, a setter is writing over more than its own local.
   oxCheck (oxIsReady() is tWasReady), "setting configuration does not change oxIsReady"
   oxCheck (oxIsControlAuthenticated() is tWasAuthed), \
      "setting configuration does not authenticate anything"
   oxCheck (oxBootstrapProgress() is tProgress), \
      "setting configuration does not move bootstrap progress"

   -- Idempotent, like every other entry point here.
   oxSetSocksPort 19050
   oxCheck (oxIsReady() is tWasReady), "setting the same port twice is harmless"

   -- Hand the session back. Empty restores the documented default for the two
   -- ports and the password, so those simply clear.
   oxSetSocksPort empty
   oxSetControlPort empty
   oxSetControlPassword empty
   oxCheck (oxIsReady() is tWasReady), "clearing the ports and password is harmless too"

   -- The three DISPATCH setters do not clear, and the reason is a real bug this
   -- section would otherwise have introduced. tools/build-standalone.py bundles
   -- this file into examples/onionxt-demo-standalone.livecodescript, where the
   -- About tab runs oxSelfTest inside the running demo - and that demo sets its
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
   oxCheck (oxIsReady() is tWasReady), "restoring the dispatch configuration is harmless too"
end testConfigurationSetters

-- ==========================================================================
-- Section 10: the inbound loopback guard - the socket-id parse plus the
-- accept/refuse verdict oxPeerAccepted makes on it.
--
-- WHY THIS IS WORTH A SECTION even though it is two private helpers: it is the
-- only security DECISION in this library that runs on attacker-reachable input.
-- `accept connections on port` takes no bind address (oxStartService says so),
-- so the listener Tor forwards to may also be reachable from the network, and
-- oxHostIsLoopback is what stands between a routable peer and the stream tables.
-- Until 2026-08-17 the parse in front of it took item 1 with the itemDelimiter
-- set to colon, which on an IPv6-shaped id yields an EMPTY host - and the guard
-- accepted empty. "::ffff:203.0.113.9:1234" therefore came in as loopback: a
-- fail-open on the one guard that must fail closed. Nothing on-engine would have
-- shown it (an accepted connection looks the same either way), and no gate in
-- the repo could see it, which is exactly the kind of hole a fixture table is
-- for. The five ids the fix was written against are pinned below, plus a second
-- 127.0.0.0/8 address, the IPv4-mapped loopback that must still be let IN, and
-- the unparseable id that must now be refused.
--
-- HOW IT REACHES A PRIVATE HANDLER. oxHostOfSocket / oxHostIsLoopback are
-- private to src/onionxt.livecodescript, so they resolve only where this harness
-- and that library share one script - which is how it actually runs on an
-- engine: tools/build-standalone.py concatenates them into the demo standalone
-- (whose About tab runs oxSelfTest), and the suite generator does the same for
-- tests/suite-selftest.livecodescript. Run instead as two library stacks, the
-- call raises a catchable "no such handler" execution error - the same mechanism
-- the sx* probes in section 8 rely on - so probe once and SKIP with a note
-- rather than reporting a phantom failure in a configuration where the check
-- simply cannot see the code. Making them public just to test them would be the
-- worse trade: it would put two internals in the published ABI (docs/05) and in
-- the suite coverage denominator forever.
-- ==========================================================================

private command testLoopbackGuard
   oxSection "inbound loopback guard (socket id parse + verdict)"
   local tProbe, tError
   try
      put oxHostOfSocket("127.0.0.1:9050") into tProbe
   catch tError
      put sLog & "  --   (skipped: oxHostOfSocket / oxHostIsLoopback are private to " & \
         "onionxt.livecodescript; run the demo standalone or the suite paste, where " & \
         "the harness and the library are one script)" & return into sLog
      exit testLoopbackGuard
   end try

   -- The shape we mint ourselves, and a second address from 127.0.0.0/8. The
   -- old parse handled both correctly; they are here so the rewrite cannot fix
   -- IPv6 by breaking IPv4.
   testOneSocketID "127.0.0.1:9050|oxs3", "127.0.0.1", true, "dialed SOCKS id with a |name suffix"
   testOneSocketID "127.9.9.9:1024", "127.9.9.9", true, "another 127.0.0.0/8 address"
   testOneSocketID "192.0.2.5:1234", "192.0.2.5", false, "routable IPv4 peer (TEST-NET-1) is refused"

   -- The one the old parse got wrong in the HARMLESS direction: item 1 was "[",
   -- so a genuine loopback peer was refused.
   testOneSocketID "[::1]:54321|3", "::1", true, "bracketed IPv6 loopback with a |name suffix"

   -- And the three whose item 1 was EMPTY, which the guard accepted. Two of them
   -- got the right answer with no reasoning behind it; the third is the fail-open
   -- itself, a routable address let in as loopback.
   testOneSocketID "::1:54321", "::1", true, "bare IPv6 loopback"
   testOneSocketID "::ffff:127.0.0.1:1234", "::ffff:127.0.0.1", true, \
      "IPv4-mapped loopback is still let in"
   testOneSocketID "::ffff:203.0.113.9:1234", "::ffff:203.0.113.9", false, \
      "IPv4-mapped ROUTABLE peer (TEST-NET-3) is refused"

   -- The new default. An id whose shape we do not understand parses to no host,
   -- and no host is a REFUSAL now; oxPeerAccepted prints the raw id beside it so
   -- an unknown spelling announces itself instead of being waved through.
   testOneSocketID ":54321", empty, false, "an id with no host parses empty and is refused"
   oxCheck (not oxHostIsLoopback(empty)), "the guard refuses an empty host (it used to accept one)"
   oxCheck oxHostIsLoopback("localhost"), "the name localhost is still loopback"
end testLoopbackGuard

private command testOneSocketID pSocketID, pExpectHost, pExpectLoopback, pLabel
   -- Both halves are asserted separately on purpose: a parse that returns the
   -- right verdict for the wrong reason is the bug this section exists to catch
   -- (empty-host-means-loopback gave the RIGHT answer for "::1:54321" and the
   -- wrong one for "::ffff:203.0.113.9:1234", from the identical parse result).
   local tHost
   put oxHostOfSocket(pSocketID) into tHost
   oxCheck (tHost is pExpectHost), \
      pLabel & ": [" & pSocketID & "] parses to host [" & pExpectHost & "]"
   oxCheck (oxHostIsLoopback(tHost) is pExpectLoopback), \
      pLabel & ": loopback verdict is " & pExpectLoopback
end testOneSocketID

-- ==========================================================================
-- Small local helpers (test glue only).
-- ==========================================================================

private function testHex pData
   -- binaryDecode is a function that fills its output var; `get` discards the count.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end testHex

private function testRepeatByte pByteVal, pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(pByteVal) after tOut
   end repeat
   return tOut
end testRepeatByte

private function testZeroSeed
   return testRepeatByte(0, 32)
end testZeroSeed
