# Getting started with oscxt

oscxt builds and reads Open Sound Control messages from OpenXTalk (OXT), and from LiveCode
9.6.3 or later. OSC is how TouchOSC, QLab, Resolume, Ableton Live (through Max), SuperCollider,
Pure Data and most show software talk to each other over a network. oscxt is a codec: it
turns values into an OSC datagram and a datagram back into values. The network is the
engine's own UDP sockets, so nothing here opens a socket, starts a thread or calls you back.

- [1. Install](#1-install)
- [2. Check that it loaded](#2-check-that-it-loaded)
- [3. Sending](#3-sending)
- [4. Receiving](#4-receiving)
- [5. Types, numbers and text](#5-types-numbers-and-text)
- [6. Bundles and address patterns](#6-bundles-and-address-patterns)
- [7. The self-test](#7-the-self-test)
- [Troubleshooting](#troubleshooting)

## 1. Install

The native library ships inside the extension, one per platform, under
`src/code/<arch>-<platform>/oscxt.{so,dll,dylib}`. In OXT open **Tools > Extension
Builder**, open `src/osc.lcb` and press **Package**; **Tools > Extension Manager** installs
the `.lce` it makes, and the engine loads the right library for the machine by itself.
While developing, **Test** in the Extension Builder loads the `.lcb` in place, with the
`code/` folder beside it.

## 2. Check that it loaded

```livecodescript
put oscVersion()   -- 2: the extension and its library are loaded, and they match
```

"handler not found" means the extension is not loaded; "unable to load foreign library" on
the first call means it loaded without its library.

## 3. Sending

LiveCode Script has no `[...]` list literal (that is LiveCode Builder syntax), so the
arguments are built by assignment, a type code and then its value.
`examples/osc-helpers.livecodescript` does that with `scAddArg`, and `scOscSend` builds the
message, opens the datagram socket the first time and writes it:

```livecodescript
-- with examples/osc-helpers.livecodescript pasted into the stack script
on mouseUp
   local tArgs
   scAddArg tArgs, "f", 0.75
   scOscSend "127.0.0.1", 7000, "/composition/layers/1/video/opacity/values", tArgs
end mouseUp
```

By hand, that is `oscBuildMessage`, which returns the datagram as binary data, and the
engine's sockets. The engine only writes to a socket that is OPEN: `write ... to socket
"host:port"` on a name never opened sends nothing and sets the result to "socket is not
open".

```livecodescript
local tArgs, tData
put "i" into tArgs[1]
put 60 into tArgs[2]
put "s" into tArgs[3]
put "go" into tArgs[4]
put oscBuildMessage("/cue/fire", tArgs) into tData
if tData is empty then answer oscLastError()      -- refused: it says why
open datagram socket to "192.168.1.20:53000"      -- once
write tData to socket "192.168.1.20:53000"
```

Broadcasting additionally needs `set the allowDatagramBroadcasts to true`.

## 4. Receiving

An accepted datagram socket calls your message once per datagram, with the sender
("host:port"), the data and the socket, in that order, and keeps delivering: there is nothing
to `read`. The helper's `socketReceived` parses each one and sends `scOscMessage` with the
address, the arguments and the sender, unpacking bundles (nested ones too):

```livecodescript
on openCard
   accept datagram connections on port 9000 with message "socketReceived"
end openCard

on scOscMessage pAddress, pArgs, pSender
   if pAddress is "/1/fader1" then set the thumbPosition of scrollbar "Volume" to pArgs[1] * 100
end scOscMessage

on closeCard
   close socket "9000"           -- an accepted socket is named by its port alone
end closeCard
```

By hand, `oscParse(tData)` returns an array: `address`, `types` (the type tag, such as
`"fs"`), `args` (1-based), and `isBundle` false; for a bundle `isBundle` is true, with
`timetag` and `messages`, a list of the same arrays. A datagram that is not OSC gives
`error` and empty fields, never a throw: bytes from the network are untrusted, and the
parser reads only what a bounds-checked scan has proven is there.

## 5. Types, numbers and text

| Code | Type | Value you pass | Value you get back |
|---|---|---|---|
| `i` | int32 | a number or its text | a number |
| `f` | float32 | a number or its text | a number (float precision) |
| `d` | float64 | a number or its text | a number |
| `h` | int64 | its decimal text | its decimal text |
| `t` | timetag | its decimal text (`"1"` is "now") | its decimal text |
| `s` | string | text (UTF-8 on the wire) | text |
| `b` | blob | binary data | binary data |
| `T` `F` `N` `I` | true, false, nil, impulse | empty (or nothing at the end) | true, false, empty, empty |

int64s and timetags cross as decimal text because the engine has no 64-bit integer type.
A number crosses EXACTLY, whether the engine holds it as text or as a computed number: an
`i` of 1234567.0 sends 1234567, a `d` of 1/3 keeps every digit, and an `s` of 1234567.0 is
the text "1234567" (ShowControl's binding wrote a computed number with six significant
digits first, so those sent 1, 0.333333 and "1.23457e+06"). An `i` beyond the int32 range
is clamped to it (2147483647 or -2147483648) on every platform, and a fraction is cut
toward zero (2.7 sends 2). A float written as text is read with a dot whatever the
system's locale.

## 6. Bundles and address patterns

`oscBuildBundle(pTimetag, pMessages)` wraps already-built messages (and bundles) into one
datagram; `oscParse` unpacks it. `oscMatch(pPattern, pAddress)` answers whether an
address matches an OSC 1.0 pattern (`?`, `*`, `[a-z]`, `[!abc]`, `{one,two}`); a pattern
too deeply nested to check is answered "no match", never a hang or a crash.

## 7. The self-test

`examples/osc-selftest.livecodescript` checks the extension on your machine with nothing
else running: paste it into a stack script and run `put runOscSelfTest()`. Tier 1 builds
and parses every type, bundles, patterns and byte-exact goldens; Tier 2 sends a message to
itself over a real UDP socket on 127.0.0.1, and its result arrives a moment later
(`put oscSelfTestLog()`).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `oscBuildMessage` returns empty | It was refused: `oscLastError()` says why (an unknown type code, a value missing, a NUL in a string, a blob that is not binary data). |
| Nothing is sent | The socket was never opened: `open datagram socket to "host:port"` first (`scOscSend` does). |
| Nothing arrives | Another program holds the port, or a firewall drops it; `accept` sets `the result` when it cannot bind. |
| `oscParse` returns an `error` | The bytes were not OSC (or a partial read): check that the handler gets whole datagrams. |
| A float arrives slightly different | `f` is 32-bit, about seven significant digits: use `d` for 64 bits. |
