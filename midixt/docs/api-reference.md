# midixt API reference

The 21 public handlers of the `midi` library, from the doc blocks in `src/midi.lcb` (the IDE
dictionary reads the same blocks; `tools/build-api-reference.py` writes this file from them,
and its `--check` is a gate). Read [getting-started.md](getting-started.md) first.

## The library

### `midiVersion`

`midiVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 2.

Every call that lists or opens ports checks this number first and throws when it is not 2, which means the native library and this binding come from different releases.

```livecodescript
put midiVersion() into field "status"
```

## Listing the ports

### `midiInputPorts`

`midiInputPorts() returns List`

Lists the MIDI inputs this computer has.

Returns: A list of port names. The first is port 0, the second port 1, and so on: pass that number to `midiOpenInput`.

An empty list means no inputs, or no MIDI service at all: then `midiLastError` says so.

```livecodescript
put midiInputPorts() into tPorts
repeat with tIndex = 1 to the number of elements of tPorts
   put tIndex - 1 & ":" && tPorts[tIndex] & return after field "Inputs"
end repeat
```

### `midiOutputPorts`

`midiOutputPorts() returns List`

Lists the MIDI outputs this computer has.

Returns: A list of port names. The first is port 0, the second port 1, and so on: pass that number to `midiOpenOutput`.

An empty list means no outputs, or no MIDI service at all: then `midiLastError` says so.

```livecodescript
put midiOutputPorts() into tPorts
```

## Opening and closing ports

### `midiOpenInput`

`midiOpenInput(in pIndex as Integer) returns Integer`

Opens a MIDI input so that its messages can be read.

- pIndex: The port's number: 0 for the first name `midiInputPorts` lists, 1 for the second, and so on.

Returns: The port's handle, or 0 when it would not open (`midiLastError` says why).

Read what arrives with `midiPoll`, and close the port with `midiClose` when you are done with it.

```livecodescript
put midiOpenInput(0) into tIn
if tIn is 0 then answer "No MIDI in:" && midiLastError()
```

### `midiOpenOutput`

`midiOpenOutput(in pIndex as Integer) returns Integer`

Opens a MIDI output so that messages can be sent to it.

- pIndex: The port's number: 0 for the first name `midiOutputPorts` lists, 1 for the second, and so on.

Returns: The port's handle, or 0 when it would not open (`midiLastError` says why).

Close the port with `midiClose` when you are done with it.

```livecodescript
put midiOpenOutput(0) into tOut
if tOut is 0 then answer midiLastError()
```

### `midiOpenVirtualInput`

`midiOpenVirtualInput(in pName as String) returns Integer`

Makes a new MIDI input that other programs can send to (macOS and Linux).

- pName: The name other programs list it under. Empty gives "ShowControl In".

Returns: The port's handle, or 0 when it could not be made (`midiLastError` says why).

Windows has no virtual ports: there this returns 0 and the error names the fix, a loopback driver such as loopMIDI, whose ports `midiOpenInput` opens like any other.

```livecodescript
put midiOpenVirtualInput("My Show In") into tIn
```

### `midiOpenVirtualOutput`

`midiOpenVirtualOutput(in pName as String) returns Integer`

Makes a new MIDI output that other programs can receive from (macOS and Linux).

- pName: The name other programs list it under. Empty gives "ShowControl Out".

Returns: The port's handle, or 0 when it could not be made (`midiLastError` says why).

Windows has no virtual ports: there this returns 0 and the error names the fix, a loopback driver such as loopMIDI, whose ports `midiOpenOutput` opens like any other.

```livecodescript
put midiOpenVirtualOutput("My Show Out") into tOut
```

### `midiClose`

`midiClose(in pHandle as Integer)`

Closes a MIDI port.

- pHandle: The handle an open call returned.

After this the handle is dead: every call with it does nothing. Closing 0, or a handle that is already closed, does nothing.

```livecodescript
midiClose tOut
```

### `midiIgnoreTypes`

`midiIgnoreTypes(in pHandle as Integer, in pSysex as Boolean, in pTime as Boolean, in pSense as Boolean)`

Chooses which kinds of message an input skips.

- pHandle: The handle `midiOpenInput` or `midiOpenVirtualInput` returned.
- pSysex: true to skip SysEx messages.
- pTime: true to skip MIDI timing clock and time code.
- pSense: true to skip active sensing.

A new input skips all three, as RtMidi does, so call this with false for any kind you want to receive.

```livecodescript
midiIgnoreTypes tIn, false, true, true -- keep SysEx, skip clock and sensing
```

## Sending

### `midiSend`

`midiSend(in pHandle as Integer, in pBytes as Data)`

Sends any MIDI bytes to an output.

- pHandle: The handle `midiOpenOutput` or `midiOpenVirtualOutput` returned.
- pBytes: The message, as binary data: one complete MIDI message, or a whole SysEx message (F0 ... F7).

When nothing is sent -- a closed handle, empty data, or a send the MIDI service refused -- `midiLastError` says why, and is empty after a send that went out. On macOS and Windows a message that is not SysEx must be one message of 1 to 3 bytes; Linux also takes several messages in one call.

```livecodescript
midiSend tOut, numToByte(240) & numToByte(126) & numToByte(127) & numToByte(6) & numToByte(1) & numToByte(247)
```

### `midiNoteOn`

`midiNoteOn(in pHandle as Integer, in pChannel as Integer, in pNote as Integer, in pVelocity as Integer)`

Sends a Note On.

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pNote: The note number, 0 to 127 (60 is middle C).
- pVelocity: How hard, 1 to 127; 0 is read as a Note Off by most receivers.

A note or velocity outside 0 to 127 is clamped into it, and a channel outside 1 to 16 wraps (17 is channel 1).

```livecodescript
midiNoteOn tOut, 1, 60, 100
```

### `midiNoteOff`

`midiNoteOff(in pHandle as Integer, in pChannel as Integer, in pNote as Integer, in pVelocity as Integer)`

Sends a Note Off.

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pNote: The note number, 0 to 127.
- pVelocity: The release velocity, 0 to 127 (64 when in doubt).

```livecodescript
midiNoteOff tOut, 1, 60, 64
```

### `midiControlChange`

`midiControlChange(in pHandle as Integer, in pChannel as Integer, in pController as Integer, in pValue as Integer)`

Sends a Control Change.

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pController: The controller number, 0 to 127 (7 is volume, 1 the mod wheel).
- pValue: The value, 0 to 127.

```livecodescript
midiControlChange tOut, 1, 7, 96
```

### `midiProgramChange`

`midiProgramChange(in pHandle as Integer, in pChannel as Integer, in pProgram as Integer)`

Sends a Program Change.

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pProgram: The program number as it travels, 0 to 127 (many instruments show it as 1 to 128).

```livecodescript
midiProgramChange tOut, 1, 4
```

### `midiChannelPressure`

`midiChannelPressure(in pHandle as Integer, in pChannel as Integer, in pValue as Integer)`

Sends Channel Pressure (mono aftertouch).

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pValue: The pressure, 0 to 127.

```livecodescript
midiChannelPressure tOut, 1, 80
```

### `midiPitchBend`

`midiPitchBend(in pHandle as Integer, in pChannel as Integer, in pValue14bit as Integer)`

Sends a Pitch Bend.

- pHandle: The handle of an open output.
- pChannel: The channel, 1 to 16.
- pValue14bit: The bend, 0 to 16383; 8192 is no bend.

A value outside 0 to 16383 is clamped into it.

```livecodescript
midiPitchBend tOut, 1, 8192
```

## Receiving

### `midiPoll`

`midiPoll(in pHandle as Integer) returns List`

Collects the messages an input has received since the last call.

- pHandle: The handle `midiOpenInput` or `midiOpenVirtualInput` returned.

Returns: A list of events, oldest first (empty when nothing is waiting). Each event is an array: "kind" (such as "noteOn" or "controlChange"), "channel" (1 to 16), "data1", "data2", "value14" for a pitch bend, "bytes" (the raw message) and "delta" (seconds since the message before it).

Call it on a timer: messages wait in a queue between calls, with their timing, so a slow timer adds delay but loses nothing. One call returns at most 256 events; call again at once when you get 256. A handle that is not an open input (closed, or an output) returns an empty list, and `midiLastError` says so.

```livecodescript
repeat for each element tEvent in midiPoll(tIn)
   if tEvent["kind"] is "noteOn" then playNote tEvent["data1"], tEvent["data2"]
end repeat
```

### `midiDecode`

`midiDecode(in pBytes as Data) returns Array`

Reads one MIDI message into the same event array `midiPoll` returns.

- pBytes: One raw MIDI message, as binary data.

Returns: An array with "kind", "channel", "data1", "data2", "value14" (pitch bend only), "bytes" and "delta" (0).

For MIDI that comes from somewhere other than an input, such as a file, and for testing a stack's MIDI handling with no MIDI device at all.

```livecodescript
put midiDecode(numToByte(144) & numToByte(60) & numToByte(100)) into tEvent
-- tEvent["kind"] is "noteOn", tEvent["channel"] is 1
```

## Errors, and loading the library by hand

### `midiLastError`

`midiLastError() returns String`

Says why the last MIDI call failed.

Returns: The reason, or empty when the last call that lists, opens, sends to or polls a port succeeded.

Read it straight after the call that failed: the next such call replaces it.

```livecodescript
put midiOpenOutput(99) into tOut
if tOut is 0 then answer midiLastError()
```

### `midiLoadNativeLib`

`midiLoadNativeLib(in pPath as String) returns Integer`

Loads the native library from a path you choose (Linux).

- pPath: The full path of midixt.so.

Returns: 1 when it loaded, 0 when it did not (`midiLoadNativeLibError` says why).

Only needed when the library is not where the engine looks for it. Call it on Linux only, before any other call of this library.

```livecodescript
if the platform is "Linux" then get midiLoadNativeLib(tFolder & "/midixt.so")
```

### `midiLoadNativeLibError`

`midiLoadNativeLibError() returns String`

Says why `midiLoadNativeLib` could not load the library.

Returns: The system's reason, or empty.
