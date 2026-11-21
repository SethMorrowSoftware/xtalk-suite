# Getting started with midixt

midixt sends and receives MIDI from OpenXTalk (OXT), and from LiveCode 9.6.3 or later: the
messages keyboards, pad controllers, synthesizers, lighting desks and music software use to
talk to each other. It is RtMidi (Gary P. Scavone's C++ library) behind a small C shim and
an LCB binding, and it uses each system's own MIDI service: ALSA on Linux, CoreMIDI on
macOS, Windows MM on Windows. No driver or other program is needed.

- [1. Install](#1-install)
- [2. Check that it loaded](#2-check-that-it-loaded)
- [3. Receive: let the helper call you](#3-receive-let-the-helper-call-you)
- [4. Receive by hand](#4-receive-by-hand)
- [5. Send](#5-send)
- [6. No hardware: virtual ports and loopback drivers](#6-no-hardware-virtual-ports-and-loopback-drivers)
- [7. The self-test](#7-the-self-test)
- [Troubleshooting](#troubleshooting)

## 1. Install

The native library ships inside the extension, one per platform, under
`src/code/<arch>-<platform>/midixt.{so,dll,dylib}`. In OXT open **Tools > Extension
Builder**, open `src/midi.lcb`, and press **Package**: the `.lce` it makes carries those
libraries, and **Tools > Extension Manager** installs it. The engine then loads the right
library for the machine by itself: no `/usr/lib`, no `sudo`, no renaming.

While developing, **Test** in the Extension Builder loads the `.lcb` in place, with the
`code/` folder beside it. The library is opened at the first call of a `midi...` handler,
not when the extension loads.

On Linux the library uses the system's ALSA library (`libasound.so.2`), which every desktop
Linux has; it is not bundled.

## 2. Check that it loaded

In the Message Box:

```livecodescript
put midiVersion()      -- 2: the extension and its library are loaded, and they match
put midiInputPorts()   -- the inputs this machine has (possibly none)
```

A "handler not found" error means the extension is not loaded. "unable to load foreign
library" on the first call means it loaded without its library: install the packaged `.lce`,
or Test with the `code/` folder beside the `.lcb`. An error naming the ABI means the library
and the extension come from different releases.

## 3. Receive: let the helper call you

MIDI that arrives is never pushed into your script: nothing may call script from the MIDI
service's thread (the suite's rule 1). RtMidi queues every message with its timing, and you
collect the queue with `midiPoll`. `examples/midi-helpers.livecodescript` runs that poll for
you on a timer and sends one message per event. Paste it into your stack's script (or a
library stack you `start using`), then:

```livecodescript
local sIn

on openCard
   put midiOpenInput(0) into sIn             -- the first input midiInputPorts lists
   if sIn is 0 then
      answer "No MIDI input:" && midiLastError()
      exit openCard
   end if
   scMidiStartListening sIn                    -- polls every 3 ms
end openCard

on scNoteOn pChannel, pNote, pVelocity
   put "note" && pNote && "velocity" && pVelocity && "channel" && pChannel & return after field "Log"
end scNoteOn

on scMidiCC pChannel, pController, pValue
   if pController is 7 then set the thumbPosition of scrollbar "Volume" to pValue
end scMidiCC

on closeCard
   scMidiStopListening sIn
   midiClose sIn
end closeCard
```

The messages are `scNoteOn`, `scNoteOff` (a note-on of velocity 0 arrives as one, as MIDI
means it), `scMidiCC`, `scProgramChange`, `scPitchBend` (0 to 16383, 8192 is no bend) and
`scMidiOther` for everything else, with the whole event array as its third parameter. They
go to the object that called `scMidiStartListening`, and up its message path, or to the
object whose long id you give as the third parameter.

- Each input has its own listener: listen to several, each with its own target.
- `scMidiStopListening pHandle` stops one; `scMidiStopListening` alone stops them all.
  Messages that arrive meanwhile wait in the queue for the next start.
- `scMidiIsListening(pHandle)` says whether an input is being listened to. It turns false
  by itself when the port is closed, and when one of your handlers throws an error: the
  error is reported as usual, and listening stops until you start it again.
- A handle of 0 (an open that failed) starts nothing; `the result` says why.

The poll interval (the second parameter, 3 ms when empty) only sets the delay. Messages and
their timing wait in the queue between polls, so a slower timer loses nothing.

## 4. Receive by hand

The helper is a convenience; `midiPoll` is the whole mechanism. One call returns every
message waiting (at most 256: call again at once when you get 256), oldest first, each an
array:

| Key | What |
|---|---|
| `kind` | `noteOn`, `noteOff`, `controlChange`, `programChange`, `pitchBend`, `channelPressure`, `polyAftertouch`, `sysex`, `system` or `other` |
| `channel` | 1 to 16 (0 for `sysex` and `system`) |
| `data1`, `data2` | the data bytes: note and velocity, controller and value, ... |
| `value14` | pitch bends only: 0 to 16383 |
| `bytes` | the raw message, as binary data |
| `delta` | seconds since the message before it, as RtMidi timed it |

```livecodescript
on pollMidi
   local tEvent
   repeat for each element tEvent in midiPoll(sIn)
      if tEvent["kind"] is "noteOn" then playNote tEvent["data1"], tEvent["data2"]
   end repeat
   send "pollMidi" to me in 3 milliseconds
end pollMidi
```

A new input skips SysEx, timing clock and active sensing, as RtMidi does:
`midiIgnoreTypes sIn, false, true, true` lets SysEx through. `midiDecode` reads raw bytes
from anywhere else (a file, a test) into the same array.

## 5. Send

Channels are 1 to 16. The senders build the status byte for you:

```livecodescript
local sOut

on playChord
   put midiOpenOutput(0) into sOut
   midiNoteOn sOut, 1, 60, 100                 -- channel 1, middle C, velocity 100
   midiNoteOn sOut, 1, 64, 100
   midiNoteOn sOut, 1, 67, 100
   send "stopChord" to me in 500 milliseconds
end playChord

on stopChord
   midiNoteOff sOut, 1, 60, 64
   midiNoteOff sOut, 1, 64, 64
   midiNoteOff sOut, 1, 67, 64
   midiClose sOut
end stopChord
```

`midiControlChange`, `midiProgramChange`, `midiChannelPressure` and `midiPitchBend` work the
same way, and `midiSend` sends any bytes (a SysEx message, say). Pass whole numbers, and
`round` a computed one: 60.6 is not refused, it plays note 60, because the engine cuts a
fraction toward zero where it becomes a byte (the suite's engine note 6.15). An empty value
is an error at the call (engine note 6.4).

Nothing here throws for a mistake in what you pass. A send that cannot go out does nothing,
and `midiLastError()` says why: a closed handle, empty data, or, on macOS and Windows, a
non-SysEx message longer than 3 bytes (those systems send one message at a time; Linux
splits a longer run itself).

## 6. No hardware: virtual ports and loopback drivers

On macOS and Linux, `midiOpenVirtualOutput("My Show Out")` makes a new output that other
programs (a DAW, a synthesizer) list as an input, and `midiOpenVirtualInput("My Show In")`
one they can send to. On macOS the **IAC Driver** in Audio MIDI Setup connects programs
too; on Linux `aconnect -l` lists what ALSA sees.

Windows has no virtual ports: the two calls return 0, and the error names the fix. Install
a loopback driver such as **loopMIDI**: its ports appear in `midiInputPorts()` and
`midiOutputPorts()` like any device. Every Windows machine also has an output named
"Microsoft GS Wavetable Synth" that plays what you send.

## 7. The self-test

`examples/midi-selftest.livecodescript` checks the extension on your machine with no MIDI
hardware. Paste it into a stack script and run `put runMidiSelfTest()` in the Message Box.
Tier 1 decodes every kind of message, Tier 2 lists the ports and opens a virtual output,
and Tier 3 sends a note, a controller, a bend and a SysEx through a virtual output and reads
them back through the system's MIDI service (Linux and macOS; on Windows it says why it
skipped).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "handler not found" on a `midi...` call | The extension is not loaded: install the `.lce`, or Test the `.lcb`. |
| "unable to load foreign library" | The extension loaded without its library. Install the packaged `.lce`, or keep `code/` beside the `.lcb`. On Linux, also check that `libasound.so.2` is installed. |
| `midiInputPorts()` is empty, and `midiLastError()` says "no MIDI input backend" | The system's MIDI service is not running or not reachable (a Linux server without the ALSA sequencer, a sandbox). |
| A device is plugged in but not listed | The ports are read at each call: re-plug it and call again. On Linux check `aconnect -l`. |
| Nothing arrives | The wrong port number (the list's position minus 1), the timer stopped (`scMidiIsListening`), or SysEx or clock you have not enabled with `midiIgnoreTypes`. |
| A burst of messages arrives cut short | More than 1024 messages arrived between two polls: poll more often. |
| A long non-SysEx send does nothing on macOS or Windows | Send one message per call; `midiLastError()` says this too. |
