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
-- HOW MUCH OF IT ACTUALLY RAN IS PART OF THE REPORT (2026-08-17). Seven of the
-- sections above can bail out when the environment cannot support them, and
-- every one of those bail-outs is now a COUNTED skip (oxSkip below), reported
-- as a third number on the summary line: "n passed, m failed, k skipped". It
-- used to be a line in the log and nothing else, which meant the one line a
-- reader actually reads could not tell 61 checks from 33 checks and 8 skips -
-- both printed as green with zero failures. The suite core reads that third
-- count now, and it also applies a FLOOR to what this harness attempts; the
-- arithmetic behind that number, section by section, is beside the OnionXT
-- call site in tests/suite-selftest.core.livecodescript's stRunMemberHarnesses.
-- Add or remove a check here and that floor moves: it is a ratchet, and it is
-- meant to be re-derived in the same change, not quietly lowered.
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
-- the risk surface is much smaller than the library itself. The 2026-08-17
-- skip counting - sSkip, oxSkip, and the third number on the summary line -
-- has NOT run on an engine: verified statically; needs an OXT pass. What an
-- engine would settle is one thing this repo cannot check headlessly: that
-- the summary line still reads as a summary to the suite core, which is why
-- the parse rule is quoted in full beside the line that builds it.

-- Two real, published v3 onion addresses, the same vectors pinned in
-- tools/onion-kat.py, so the Python KAT and this livecodescript suite agree.
constant kTestAddrTorProject = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kTestAddrDuckDuckGo = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"

local sLog
local sPass
local sFail
local sSkip      -- a skipped check COUNTS (see oxSkip); it is not just a log line

-- ==========================================================================
-- Entry point.
-- ==========================================================================

function oxSelfTest
   put empty into sLog
   put 0 into sPass
   put 0 into sFail
   put 0 into sSkip

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
   testHttpdHelpers

   local tSummary
   -- THE SHAPE OF THIS LINE IS A CONTRACT with the suite core's
   -- stSummaryCounts: a line counts as the summary only if every word on it is
   -- a number or the word passed/failed/skipped, in that order, and EXACTLY
   -- ONE line in the whole report may qualify - zero matches and two matches
   -- are both reported failures there rather than a silent zero folded into
   -- the suite totals. The skip count is the third number as of 2026-08-17;
   -- the two-number spelling still parses, so a member that has no skips to
   -- report is not forced to grow one.
   put sPass & " passed, " & sFail & " failed, " & sSkip & " skipped" into tSummary
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

-- A SKIP IS A COUNTED OUTCOME, not a line in the log (2026-08-17).
--
-- WHY THIS EXISTS. Seven sites in this file bail out when the environment
-- cannot support a check - a session that is already control-authenticated, a
-- SodiumXT without sxSha3_256 or older than ABI 6, a run where oxHostOfSocket
-- is not in this script - and every one of them used to append to sLog and
-- touch NO counter. The suite core folds this harness in through
-- stMergeReturned, which reads the counts back out of the SUMMARY LINE, so a
-- skipped section was invisible in the one line an engine session actually
-- reads: 33 checks and 8 skips printed "33 passed, 0 failed", the same green
-- as all 61. Now the summary carries the skips, the core adds them to the
-- suite's own sSkipped, and its floor refuses a run that attempted fewer items
-- than this harness can attempt in its worst environment.
--
-- The LOG line keeps its exact old shape on purpose. The report is read by eye
-- on an engine pass and nothing about a skip's prose changed - only whether
-- anything counted it. pReason is the sentence that used to sit inside the
-- parentheses, so a site converts by deleting its wrapper, not by rewording.
private command oxSkip pReason
   add 1 to sSkip
   put sLog & "  --   (skipped: " & pReason & ")" & return into sLog
end oxSkip

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
      oxSkip "this session is already control-authenticated; " & \
         "run oxSelfTest before oxConnectControl for this section"
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
      oxSkip "pre-auth guard on oxCreateService* needs a " & \
         "session that has not authenticated yet"
   else
      oxCreateService 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateService fails closed without an authenticated control connection"

      oxCreateServiceFromSeed testZeroSeed(), 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateServiceFromSeed also fails closed without an authenticated control connection"

      -- THE SAME GUARD, REACHED BY THE PUBLISH AND TRANSPORT NAMES. Both were
      -- exempted from the suite coverage ratchet as "live-daemon", and both
      -- reasons were wrong on the code: oxPublishService opens no socket and
      -- starts no process - it validates its arguments, fills sServices, and
      -- calls oxCtlSend, which exits while sControlSocket is empty. What it
      -- needs is an authenticated STATE, not a daemon. oxTransportListen is a
      -- one-line wrapper over oxCreateServiceFromSeed, tested two lines above
      -- under its own name and by nothing under this one.
      oxPublishService 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxPublishService fails closed without an authenticated control connection"

      oxTransportListen testZeroSeed(), 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxTransportListen fails closed too (it wraps oxCreateServiceFromSeed)"
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

   -- THE EMBEDDABLE SOCKET SPLIT (2026-08-24). oxSocketError / oxSocketClosed
   -- / oxSocketTimeout carry what the three engine socket messages used to do
   -- inline, and answer one question: was that socket MINE, and did I handle
   -- it? An embedding app calls them where it would otherwise `pass`, so
   -- "false for a socket that is not ours" is not a detail - it IS the
   -- contract that keeps a co-embedded library's events flowing. A wrong
   -- answer here is a SILENT HANG in the app, never an error, so it is pinned
   -- offline where it costs nothing. (The true legs need a live stream and
   -- ride the live-Tor pass with everything else in this file's Mode A.)
   oxCheck (oxSocketError(tUnknown, "boom") is false), \
         "oxSocketError disowns a socket that is not ours"
   oxCheck (oxSocketClosed(tUnknown) is false), \
         "oxSocketClosed disowns a socket that is not ours"
   oxCheck (oxSocketTimeout(tUnknown) is false), \
         "oxSocketTimeout disowns a socket that is not ours"

   -- The transport names reach the two guards above and nothing else: they are
   -- one-line wrappers (oxTransportSend -> oxWrite, oxTransportRecv ->
   -- oxSetStreamCallback). Both were exempted from the coverage ratchet as
   -- "live-daemon: writes to / reads from a live Tor stream", which is what the
   -- WRAPPED handler does with a real stream - not what the wrapper needs to be
   -- exercised. A stale handle stops at the same state guard under either name.
   oxTransportSend tUnknown, "x"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), \
      "oxTransportSend on an unknown stream fails closed (it wraps oxWrite)"

   oxTransportRecv tUnknown, "someHandler"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), \
      "oxTransportRecv on an unknown stream fails closed (it wraps oxSetStreamCallback)"
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
      oxSkip pLabel & " re-encode needs SodiumXT sxSha3_256, docs/08"
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
      oxSkip "tamper-detection needs SodiumXT sxSha3_256, docs/08"
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
      oxSkip "sxSignSeedToExpandedKey needs SodiumXT ABI >= 6"
   end if

   -- Gap #3 (SHIPPED): sxHmacSha256("Jefe","what do ya want for nothing?") RFC 4231 TC2.
   if tInfo["safeCookieAuth"] is true then
      local tMac, tExpectMac
      put "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" into tExpectMac
      put sxHmacSha256(textEncode("Jefe", "UTF-8"), textEncode("what do ya want for nothing?", "UTF-8")) into tMac
      oxCheck (testHex(tMac) is tExpectMac), \
         "sxHmacSha256 (RFC 4231 Test Case 2) matches the pinned HMAC vector"
   else
      oxSkip "sxHmacSha256 needs SodiumXT ABI >= 6"
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
   -- section would otherwise have introduced. tools/sync-demo-embeds.py bundles
   -- this file into examples/onionxt-demo.livecodescript, where the
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
-- engine: tools/sync-demo-embeds.py concatenates them into the demo itself
-- (whose About tab runs oxSelfTest), and the suite generator does the same for
-- tests/suite-selftest.livecodescript. Run instead as two library stacks, the
-- call raises a catchable "no such handler" execution error - the same mechanism
-- the sx* probes in section 8 rely on - so probe once and SKIP with a note
-- rather than reporting a phantom failure in a configuration where the check
-- simply cannot see the code. Making them public just to test them would be the
-- worse trade: it would put two internals in the published ABI (docs/05) and in
-- the suite coverage denominator forever.
-- ==========================================================================

-- ==========================================================================
-- The oxh* HTTP layer: 11 public handlers and a dozen private helpers that,
-- until 2026-08-19, no test in this tree named even once. It is PURE COMPUTE -
-- header parsing, framing, escaping, MIME - and it is the layer riptide's anon
-- persona and nocloud's Tor path both serve through, reachable by anyone who
-- has the onion address. That combination is the argument for testing it.
--
-- SAME PRIVATE-HANDLER PROBLEM as the loopback guard above, and the same
-- answer: these helpers are private to onion-httpd.livecodescript, so they
-- resolve only where the harness and that file are ONE script. That is the
-- onionxt DEMO (sync-demo-embeds carries onionxt + onion-httpd + this harness
-- into it). It is deliberately NOT the suite paste, which carries the ox*
-- surface but not the httpd app on top of it - so this section SKIPs there,
-- honestly, rather than reporting a phantom failure.
-- ==========================================================================

private command testHttpdHelpers
   oxSection "oxh* HTTP layer (pure compute: parse, frame, escape, MIME)"
   local tProbe, tError, tCRLF, tReq, tH, tBody

   try
      put oxhTrim("  x  ") into tProbe
   catch tError
      oxSkip "the oxh* helpers are private to onion-httpd.livecodescript; " & \
         "run the onionxt demo, where sync-demo-embeds makes the harness " & \
         "and that layer one script"
      exit testHttpdHelpers
   end try
   oxCheck (tProbe is "x"), "oxhTrim strips surrounding whitespace"

   put numToChar(13) & numToChar(10) into tCRLF

   -- ---- the request line ------------------------------------------------
   put "GET /a/b?x=1&y=2 HTTP/1.1" & tCRLF & "Host: example.onion" & tCRLF into tReq
   put oxhParseHeaders(textEncode(tReq, "UTF-8")) into tH
   oxCheck (tH["__method"] is "GET"), "oxhParseHeaders reads the method"
   oxCheck (tH["__path"] is "/a/b"), "oxhParseHeaders splits the path from the query"
   oxCheck (tH["__query"] is "x=1&y=2"), "oxhParseHeaders keeps the whole query"
   oxCheck (tH["__resource"] is "/a/b?x=1&y=2"), "oxhParseHeaders keeps the raw resource"
   oxCheck (tH["host"] is "example.onion"), "a header name is lowercased and its value trimmed"

   -- ---- THE REGRESSION THIS SECTION EXISTS FOR --------------------------
   -- A client header named __path used to be written into the SAME array the
   -- request line had already populated, so it replaced the parsed path -
   -- which oxhHandle uses to pick a route and to call oxhServeStatic. Fixed
   -- 2026-08-19 by refusing any header name in the "__" namespace, the guard
   -- nocloud's qsHttpParseHead has always carried.
   put "GET /safe HTTP/1.1" & tCRLF & "__path: /../../etc/passwd" & tCRLF & \
       "__method: DELETE" & tCRLF & "__query: evil=1" & tCRLF & \
       "Host: example.onion" & tCRLF into tReq
   put oxhParseHeaders(textEncode(tReq, "UTF-8")) into tH
   oxCheck (tH["__path"] is "/safe"), \
         "a client header named __path CANNOT replace the parsed path"
   oxCheck (tH["__method"] is "GET"), \
         "a client header named __method CANNOT replace the parsed method"
   oxCheck (tH["__query"] is empty), \
         "a client header named __query CANNOT invent a query string"
   oxCheck (tH["host"] is "example.onion"), \
         "refusing the __ namespace does not disturb ordinary headers"

   -- ---- framing ---------------------------------------------------------
   put "GET / HTTP/1.1" & tCRLF & "Host: h" & tCRLF & tCRLF into tReq
   oxCheck (oxhHeaderEnd(textEncode(tReq, "UTF-8")) > 0), \
         "oxhHeaderEnd finds the blank line that ends the head"
   oxCheck (oxhHeaderEnd(textEncode("GET / HTTP/1.1" & tCRLF, "UTF-8")) is 0), \
         "oxhHeaderEnd answers 0 while the head is still incomplete"
   oxCheck (oxhRequestComplete(textEncode(tReq, "UTF-8")) is true), \
         "a bodyless GET is complete once its head is"

   -- a declared Content-Length is not satisfied until the body arrives
   put "POST /x HTTP/1.1" & tCRLF & "Content-Length: 5" & tCRLF & tCRLF into tReq
   oxCheck (oxhRequestComplete(textEncode(tReq, "UTF-8")) is false), \
         "a POST is incomplete while its declared body is missing"
   oxCheck (oxhRequestComplete(textEncode(tReq & "hello", "UTF-8")) is true), \
         "...and complete once the declared bytes are all there"

   -- ---- escaping and encoding -------------------------------------------
   put oxhHtmlEscape("<a href=" & quote & "x" & quote & ">&</a>") into tBody
   oxCheck (tBody contains "&lt;"), "oxhHtmlEscape escapes <"
   oxCheck (tBody contains "&gt;"), "oxhHtmlEscape escapes >"
   oxCheck (tBody contains "&amp;"), "oxhHtmlEscape escapes &"
   oxCheck (not (tBody contains "<a href")), \
         "oxhHtmlEscape leaves no raw markup (the directory listing's whole defence)"

   oxCheck (oxhPathEncode("a b") contains "%20"), "oxhPathEncode encodes a space"
   oxCheck (oxhStripTrailingSlash("/x/y/") is "/x/y"), "oxhStripTrailingSlash trims one slash"
   oxCheck (oxhStripTrailingSlash("/x/y") is "/x/y"), "...and leaves a bare path alone"

   -- ---- MIME and status reasons -----------------------------------------
   oxCheck (oxhMimeType("/a/b.html") contains "text/html"), "oxhMimeType maps .html"
   oxCheck (oxhMimeType("/a/b.png") contains "image/png"), "oxhMimeType maps .png"
   oxCheck (oxhMimeType("/a/b.unknownext") is not empty), \
         "oxhMimeType falls back rather than answering empty"
   oxCheck (oxhReason(200) is not empty), "oxhReason names 200"
   oxCheck (oxhReason(404) is not empty), "oxhReason names 404"
end testHttpdHelpers

private command testLoopbackGuard
   oxSection "inbound loopback guard (socket id parse + verdict)"
   local tProbe, tError
   try
      put oxHostOfSocket("127.0.0.1:9050") into tProbe
   catch tError
      oxSkip "oxHostOfSocket / oxHostIsLoopback are private to " & \
         "onionxt.livecodescript; run the demo standalone or the suite paste, where " & \
         "the harness and the library are one script"
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
