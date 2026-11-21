# oscxt API reference

The 8 public handlers of the `osc` library, from the doc blocks in `src/osc.lcb` (the IDE
dictionary reads the same blocks; `tools/build-api-reference.py` writes this file from them,
and its `--check` is a gate). Read [getting-started.md](getting-started.md) first.

## The library

### `oscVersion`

`oscVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 2.

Every other call checks this number first and throws when it is not 2, which means the native library and this binding come from different releases.

```livecodescript
put oscVersion() into field "status"
```

## Building messages and bundles

### `oscBuildMessage`

`oscBuildMessage(in pAddress as String, in pArgs as List) returns Data`

Builds one OSC message, ready to send.

- pAddress: The OSC address, such as "/1/fader1". It starts with "/".
- pArgs: The arguments as ONE flat list: a type code, then its value, then the next type code, and so on. Type codes: "i" (32-bit integer), "f" (32-bit float), "d" (64-bit float), "s" (text), "h" (64-bit integer), "t" (timetag), "b" (binary data), and "T", "F", "N", "I" (true, false, nil and impulse, which take no value: give empty).

Returns: The message as binary data, or empty when it cannot be built.

Values for i, f, d, s, h and t may be numbers or text. A number is sent exactly; text is read as a number with a "." for the decimal point, whatever the computer's language. Give an h or t value above 2^53 as text, since a script number cannot hold it exactly. An i value outside the 32-bit range is clamped to it.

```livecodescript
local tArgs, tData
put "f" into tArgs[1]
put 0.5 into tArgs[2]
put oscBuildMessage("/1/fader1", tArgs) into tData
write tData to socket "127.0.0.1:9000"
```

### `oscBuildBundle`

`oscBuildBundle(in pTimetag as String, in pMessages as List) returns Data`

Builds an OSC bundle: several messages sent as one datagram.

- pTimetag: When the receiver should act, as an NTP timetag in decimal text. "1" means immediately.
- pMessages: A list of messages, each built by `oscBuildMessage` (or another bundle).

Returns: The bundle as binary data, or empty when it cannot be built.

An element that is empty or is not binary data makes the whole bundle fail: the result is empty and `oscLastError` says why.

```livecodescript
local tMsgs, tBundle
put oscBuildMessage("/a", empty) into tMsgs[1]
put oscBuildMessage("/b", empty) into tMsgs[2]
put oscBuildBundle("1", tMsgs) into tBundle
```

## Parsing

### `oscParse`

`oscParse(in pData as Data) returns Array`

Reads an OSC message or bundle that arrived as bytes.

- pData: The bytes of one datagram.

Returns: An array. For a message it holds "isBundle" (false), "address", "types" (the type codes, such as "fsi") and "args" (the values, 1 to N). For a bundle it holds "isBundle" (true), "timetag" (decimal text) and "messages" (an array of message arrays, nested bundles included). For bytes that are not OSC it holds "isBundle" (false), an empty "address", and "error".

Integers and floats come back as numbers, h and t values as decimal text (a script number cannot hold every 64-bit value), b values as binary data, T and F as true and false, N and I as empty. A malformed datagram never reads past its end; it is refused with a reason.

```livecodescript
put oscParse(pData) into tMsg
if tMsg["address"] is "/1/fader1" then put tMsg["args"][1] into tLevel
```

## Matching addresses, errors, and loading the library by hand

### `oscMatch`

`oscMatch(in pPattern as String, in pAddress as String) returns Boolean`

Tells whether an OSC address matches an OSC address pattern.

- pPattern: The pattern, which may use the OSC 1.0 wildcards: ? (one character), * (any run of characters), [abc] and [a-z] (one of a set), [!abc] (one not in a set) and {foo,bar} (one of the words). None of them crosses a "/".
- pAddress: The address to test, such as "/1/fader1".

Returns: true or false.

A pattern so complex it would take too long or nest too deeply returns false rather than stalling the engine.

```livecodescript
if oscMatch("/1/fader*", tMsg["address"]) then put tMsg["args"][1] into tLevel
```

### `oscLastError`

`oscLastError() returns String`

Says why the last build or parse was refused.

Returns: The reason, or empty when the last `oscBuildMessage`, `oscBuildBundle` or `oscParse` succeeded.

```livecodescript
put oscBuildMessage(tAddress, tArgs) into tData
if tData is empty then answer oscLastError()
```

### `oscLoadNativeLib`

`oscLoadNativeLib(in pPath as String) returns Integer`

Loads the native library from a path you choose (Linux).

- pPath: The full path of oscxt.so.

Returns: 1 when it loaded, 0 when it did not (`oscLoadNativeLibError` says why).

Only needed when the library is not where the engine looks for it. Call it on Linux only, before any other call of this library.

```livecodescript
if the platform is "Linux" then get oscLoadNativeLib(tFolder & "/oscxt.so")
```

### `oscLoadNativeLibError`

`oscLoadNativeLibError() returns String`

Says why `oscLoadNativeLib` could not load the library.

Returns: The system's reason for the last `oscLoadNativeLib` that returned 0, or empty when the last one loaded the library (or none has run).

The reason is read when the load fails and kept until the next `oscLoadNativeLib`, so it can be asked for at any time after.
