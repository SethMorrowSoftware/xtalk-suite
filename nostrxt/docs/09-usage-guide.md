# 09 - Usage Guide: From Zero to a Signed Event on a Relay

> STATUS: verified statically; needs an OXT pass. Every relay recipe additionally
> needs a live-relay pass. The snippets below call only handlers that exist, match
> the member harness's style, and follow both error conventions - but none of them
> has run on a real engine yet. The last section says exactly what that means and
> where the runbook is.

Task-oriented recipes, in the order an app grows. Each one states which extensions
it needs; the two error conventions (core functions return empty and record for
`nxLastError()`; relay commands report through `the result`) are used correctly
throughout, and copying a recipe means copying its error handling too - the refusal
paths are the part this member is most careful about.

## 0. Load, wire, probe

For a real project, `start using` both stacks (core first - the relay layer
composes it). The shipped demo instead CARRIES both between sync-demo-embeds
sentinels, so it is one paste-and-run file; either way the calls below are
identical.

```livecodescript
on preOpenStack
   start using stack "nostrxt"        -- the core: nx* (load first)
   start using stack "nostr-relay"    -- the relay client: nxr*
   -- Callbacks dispatch to the topStack unless you name an owner; naming
   -- one removes any ambiguity about which script receives them.
   nxrInit the long id of me
end preOpenStack
```

Probe before you promise features to the user - a missing extension disables
exactly its feature, and the probe is how an app finds out cleanly:

```livecodescript
command showCapabilities
   local tCaps
   put nxProbeCapabilities() into tCaps
   if tCaps["canSign"] is not true then
      answer "CoinXT is not installed: ids, signatures and NIP-44 are unavailable"
   end if
   if tCaps["hasSodium"] is not true then
      answer "SodiumXT is not installed: key generation is unavailable"
   end if
   -- tCaps["canNip44Cipher"] is false when the installed SodiumXT predates
   -- ABI 10 (docs/07); nxNip44HasCipher() re-probes that one seam live.
end showCapabilities
```

## 1. Generate keys and show an npub

Needs SodiumXT (randomness) and CoinXT (validation, derivation). `nxKeyGenerate()`
refuses outright without them - it never degrades to weaker randomness.

```livecodescript
local sSeckey                         -- script-local; OXT variables are not
                                      -- locked memory - storage at rest is
                                      -- the app's decision, made knowingly

command makeIdentity
   local tPubkey
   put nxKeyGenerate() into sSeckey
   if sSeckey is empty then
      answer "no key: " & nxLastError()
      exit makeIdentity
   end if
   put nxKeyPublic(sSeckey) into tPubkey
   put nxNpubEncode(tPubkey) into field "npubField"
   -- Show the npub, not the nsec. nxNsecEncode(sSeckey) exists for an
   -- explicit backup flow; nxUriEncode REFUSES to wrap an nsec at all,
   -- because a secret key in a URI ends up in somebody's chat log.
end makeIdentity
```

## 2. Build, sign and verify a text note

Needs CoinXT. Builders return UNSIGNED events; `nxEventSign(...)` fills pubkey, id
and sig. The empty aux argument draws fresh BIP-340 auxiliary randomness - a fixed
aux is for KATs, not for apps.

```livecodescript
command makeNote pContent
   local tTags, tEvent, tSigned
   put "t" into tTags[1][1]           -- a topic tag: 1-based, name then value
   put "openxtalk" into tTags[1][2]
   put nxEventBuild(1, pContent, tTags, empty) into tEvent
   if tEvent is empty then
      answer "bad event: " & nxLastError()
      exit makeNote
   end if
   put nxEventSign(tEvent, sSeckey, empty) into tSigned
   if tSigned is empty then
      answer "signing failed: " & nxLastError()
      exit makeNote
   end if
   -- Belt and braces: what we sign must verify. A false here means a
   -- real defect, not user error.
   if nxEventVerify(tSigned) is not true then
      answer "self-verify failed: " & nxLastError()
      exit makeNote
   end if
   put nxEventToJson(tSigned) into field "wireField"
end makeNote
```

## 3. Parse and verify an event from JSON

An event from ANYWHERE - a relay with verification turned off, a file, a paste - is
untrusted text until `nxEventVerify(...)` passes. (Events delivered through the
relay callback's `"event"` kind are already verified, because verification is on by
default.)

```livecodescript
command readInboundEvent pJson
   local tEvent
   put nxEventFromJson(pJson) into tEvent
   if tEvent is empty then
      answer "unparseable: " & nxLastError()
      exit readInboundEvent
   end if
   -- Structure is not trust: nxEventFromJson checked the SHAPE only.
   if nxEventVerify(tEvent) is not true then
      answer "REFUSED: " & nxLastError()
      exit readInboundEvent
   end if
   -- Now the fields mean what they say.
   put tEvent["content"] into field "contentField"
   put nxTagValues(tEvent, "p") into field "mentionsField"
end readInboundEvent
```

## 4. Encode and decode entities

Pure compute, no extensions needed. `nxEntityDecode(...)` accepts any NIP-19 entity
(and strips a `nostr:` prefix), so one handler serves a paste box; the typed
decoders (`nxNpubDecode(...)` and friends) refuse the wrong entity type, which is
what you want when the code KNOWS what it expects.

```livecodescript
command decodePasted pText
   local tFields
   put nxEntityDecode(pText) into tFields
   if tFields is empty then
      answer "not a NIP-19 entity: " & nxLastError()
      exit decodePasted
   end if
   switch tFields["type"]
      case "npub"
         put tFields["pubkey"] into field "hexField"
         break
      case "note"
         put tFields["id"] into field "hexField"
         break
      case "nprofile"
         -- pubkey plus relay hints, one relay per line
         put tFields["pubkey"] & return & tFields["relays"] into field "hexField"
         break
      case "nevent"
         put tFields["id"] into field "hexField"
         break
      case "naddr"
         put tFields["kind"] && tFields["identifier"] into field "hexField"
         break
      case "nsec"
         -- handle a pasted SECRET key deliberately: never echo it back
         answer "that is a secret key - not displaying it"
         break
   end switch
end decodePasted
```

Encoding a shareable pointer to an event, relay hint included:

```livecodescript
put nxNeventEncode(tSigned["id"], "wss://relay.example.com", tSigned["pubkey"], 1) \
      into field "shareField"
put nxUriEncode(field "shareField") into field "uriField"   -- "nostr:nevent1..."
```

## 5. Build filters and a REQ

Pure compute. A filter is an array in, a canonical JSON object out; the REQ takes
one filter object per line, so multi-filter subscriptions are just more lines.

```livecodescript
command buildMyFeedReq pAuthorHex
   local tFilter, tFilterJson, tWire
   put pAuthorHex into tFilter["authors"]   -- one 64-hex pubkey per line
   put "1,7" into tFilter["kinds"]          -- notes and reactions
   put 1700000000 into tFilter["since"]
   put 50 into tFilter["limit"]
   put nxFilterBuild(tFilter) into tFilterJson
   if tFilterJson is empty then
      answer "bad filter: " & nxLastError()
      exit buildMyFeedReq
   end if
   put nxClientReq("my-feed", tFilterJson) into tWire
   -- tWire is the exact ["REQ",...] text; nxrSubscribe builds the same
   -- thing itself, so you only need nxClientReq for a transport of your own.
   -- Client-side, the same filter re-checks an event:
   --   nxFilterMatches(tFilterJson, tEvent) is true
end buildMyFeedReq
```

## 6. Connect to a relay and subscribe

The relay layer, live. `nxrConnect` returns the handle IMMEDIATELY; the handshake
finishes asynchronously and the callback's `"open"` is the moment the relay becomes
usable - which is why the first REQ belongs inside that branch, not on the line
after the connect. Note the honesty label: ws:// mirrors OnionXT's engine-proven
socket idioms; wss:// is written but engine-unproven (docs/07 gap #2).

```livecodescript
local sRelay

command connectToRelay pUrl
   local tHandle
   nxrConnect pUrl
   put the result into tHandle
   if tHandle is not an integer then
      answer tHandle                  -- a "NostrXT relay: ..." refusal
      exit connectToRelay
   end if
   put tHandle into sRelay
   nxrSetCallback sRelay, "onRelay"
   -- Verification is ON by default: events arrive through "event" already
   -- id-and-signature checked, failures arrive as "invalid". Leave it on.
end connectToRelay
```

The whole callback contract in one handler - every `pKind` the layer delivers:

```livecodescript
on onRelay pRelay, pKind, pArgOne, pArgTwo
   local tSavedItemDelim, tVerdict, tFilter, tFilterJson
   -- Reached from socket callbacks and watchdogs, so if this handler
   -- touches controls by unqualified name, pin the defaultStack FIRST
   -- (the family's timer-stack-pin lesson: delayed handlers resolve
   -- unqualified controls against the defaultStack, not this stack).
   set the defaultStack to the short name of this stack
   switch pKind
      case "open"
         -- The handshake completed; the relay is usable NOW. Subscribing
         -- any earlier is refused (the connection is not open yet).
         put "1" into tFilter["kinds"]
         put 20 into tFilter["limit"]
         put nxFilterBuild(tFilter) into tFilterJson
         nxrSubscribe pRelay, "recent-notes", tFilterJson
         if the result is not empty then
            answer the result
         end if
         break
      case "event"
         -- pArgOne = subscription id; pArgTwo = the raw event JSON,
         -- already VERIFIED. Parse when you need the fields:
         --   put nxEventFromJson(pArgTwo) into tEvent
         break
      case "invalid"
         -- pArgTwo says why the event was refused (failed verify, or
         -- CoinXT absent while verification is on - fail closed). A relay
         -- doing this repeatedly is misbehaving; say so in the log.
         break
      case "eose"
         -- Stored events for pArgOne are done; what follows is live.
         break
      case "ok"
         -- pArgOne = event id; pArgTwo = "true"/"false", a tab, the reason.
         put the itemDelimiter into tSavedItemDelim
         set the itemDelimiter to tab
         put item 1 of pArgTwo into tVerdict
         set the itemDelimiter to tSavedItemDelim
         if tVerdict is "true" then
            -- the relay accepted the publish keyed by pArgOne
         else
            -- refused; the rest of pArgTwo is the relay's reason
         end if
         break
      case "closed"
         -- The RELAY ended subscription pArgOne; pArgTwo says why.
         break
      case "notice"
         -- pArgOne is human-readable relay chatter; show it somewhere.
         break
      case "auth"
         -- pArgOne is the NIP-42 challenge; see recipe 8 (it is also
         -- kept for nxrChallenge, so answering later works too).
         break
      case "error"
         -- pArgOne says what failed. The relay is ALREADY torn down -
         -- do not call nxrDisconnect; just forget the handle.
         if pRelay is sRelay then
            put empty into sRelay
         end if
         break
      case "disconnected"
         -- The relay is gone: peer close, error teardown, or your own
         -- nxrDisconnect. Forget the handle; a reconnect is a new connect.
         if pRelay is sRelay then
            put empty into sRelay
         end if
         break
   end switch
end onRelay
```

## 7. Publish and read the ok verdict

Publishing is fire-and-callback: the command only confirms the frame was sent; the
relay's verdict arrives asynchronously as the `"ok"` callback, keyed by the event
id you published.

```livecodescript
command publishNote pContent
   local tEvent, tSigned
   if sRelay is empty then
      answer "connect to a relay first"
      exit publishNote
   end if
   put nxEventBuild(1, pContent, empty, empty) into tEvent
   put nxEventSign(tEvent, sSeckey, empty) into tSigned
   if tSigned is empty then
      answer "signing failed: " & nxLastError()
      exit publishNote
   end if
   nxrPublish sRelay, tSigned
   if the result is not empty then
      answer the result
      exit publishNote
   end if
   -- Remember tSigned["id"]: the "ok" callback (recipe 6) reports the
   -- relay's accept/refuse verdict against exactly that id.
end publishNote
```

## 8. Answer a NIP-42 challenge

Some relays demand authentication before serving or accepting events; they send an
AUTH challenge, which arrives as the `"auth"` callback and is also kept for
`nxrChallenge(...)`. The answer is an ordinary signed event of kind 22242 naming
the relay url and the challenge.

```livecodescript
command answerAuthChallenge pRelay
   local tChallenge, tAuth, tSigned
   put nxrChallenge(pRelay) into tChallenge
   if tChallenge is empty then
      answer "this relay has not sent an AUTH challenge"
      exit answerAuthChallenge
   end if
   put nxAuthBuild(nxrUrl(pRelay), tChallenge, empty) into tAuth
   put nxEventSign(tAuth, sSeckey, empty) into tSigned
   if tSigned is empty then
      answer "auth signing failed: " & nxLastError()
      exit answerAuthChallenge
   end if
   nxrAuth pRelay, tSigned
   if the result is not empty then
      answer the result
   end if
end answerAuthChallenge
```

## 9. NIP-44, as it stands

The honest recipe. The whole construction works against a current SodiumXT: the
once-missing raw cipher shipped upstream as ABI 10's `sxChaCha20IetfXor` on
2026-08-23 (`07-capabilities-required.md` is the closed request). On an installed
SodiumXT older than that, encrypt and decrypt FAIL CLOSED with the capability
error. Probe the seam live either way - this same code branches correctly on any
install, which is why the recipe below has not changed since the day the gap was
open.

```livecodescript
command demoNip44 pTheirPubkeyHex
   local tConvHex, tPayload, tPlain
   -- Works today: the shared conversation key, symmetric in the roles.
   put nxNip44ConversationKey(sSeckey, pTheirPubkeyHex) into tConvHex
   if tConvHex is empty then
      answer nxLastError()            -- e.g. "... needs CoinXT cxEcdh ..."
      exit demoNip44
   end if
   if nxNip44HasCipher() is true then
      -- The upstream primitive shipped: the full payload path is live.
      put nxNip44Encrypt(sSeckey, pTheirPubkeyHex, "hello", empty) into tPayload
      if tPayload is empty then
         answer "encrypt failed: " & nxLastError()
         exit demoNip44
      end if
      put nxNip44Decrypt(sSeckey, pTheirPubkeyHex, tPayload) into tPlain
      -- tPlain is "hello"; a tampered payload refuses AT THE MAC.
   else
      -- The pre-ABI-10 install path: fail closed, naming the remedy.
      get nxNip44Encrypt(sSeckey, pTheirPubkeyHex, "hello", empty)
      answer nxLastError()
      -- "nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT
      --  ABI 10; the installed SodiumXT predates it -
      --  docs/07-capabilities-required.md)"
   end if
end demoNip44
```

## 10. Verify a NIP-05 identifier

The core builds the well-known url and judges the fetched document; the FETCH is
yours, because the core does no I/O. libURL's blocking GET is the shortest
spelling; it stalls the interpreter for the round trip, so a shipping app should
prefer `load URL` with a callback.

```livecodescript
command verifyNip05 pPubkeyHex
   local tUrl, tBody
   put nxNip05Url("bob@example.com") into tUrl
   if tUrl is empty then
      answer nxLastError()
      exit verifyNip05
   end if
   put URL tUrl into tBody            -- the app's fetch, the app's choice
   if nxNip05Verify(tBody, "bob", pPubkeyHex) is true then
      answer "bob@example.com does map to that key"
   else
      answer "NOT verified: " & nxLastError()
   end if
end verifyNip05
```

## 11. Teardown rules

OXT has no deterministic unload hook, so the app frees what it opens - the family
rule every socket member follows. One line covers it:

```livecodescript
on closeStack
   nxrShutdown          -- closes every relay; idempotent, safe to call twice
end closeStack
```

`nxrDisconnect pRelay` closes ONE relay (a close frame when the link is up, then
teardown); a stale handle into either is a clean no-op. After `"error"` or
`"disconnected"` the relay is already gone - forget the handle, and reconnect with
a fresh `nxrConnect` if you want it back.

## Where this leaves you, honestly

Everything above is **verified statically; needs an OXT pass** - and every recipe
from 6 onward **needs an OXT pass + a live-relay pass**. What stands behind the
snippets today: `tools/nostr-kat.py` sweeps the full published BIP-340, NIP-44 v2,
BIP-173 and NIP-19 vector sets through the independent oracle, and
`tools/check-selftest-vectors.py` re-derives every constant the member harness pins,
by name, on every build. What does not stand behind them yet: a real engine, a real
relay, and the wss:// question (docs/07 gap #2).

When you sit down at an engine: the suite runbook, `docs/OXT-PASS-RUNBOOK.md` at
the repository root, is what to do and in what order; the member harness
(`examples/nostrxt-tests.livecodescript`, or its fold inside the suite paste) is
the first thing to run; and the demo (`examples/nostrxt-demo.livecodescript`) is
the paste-and-run stack that exercises these exact recipes against a live relay.
Record what the engine actually does in `docs/OXT-ENGINE-NOTES.md` at the suite
root and in `nostrxt/CLAUDE.md`'s as-built notes - that is how these labels get
upgraded, one observed fact at a time.
