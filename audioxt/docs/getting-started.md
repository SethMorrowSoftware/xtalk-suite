# Getting started with audioxt

audioxt gives a stack a mixer: you load or make sounds, start them, and any number play at
once. It also opens a microphone. This page is what to know before the
[API reference](api-reference.md).

It does not replace anything. The `play` command and the player object are the engine's own
and work as they always have; a stack can use both.

To hear what it does before reading on, open the demo, Sound Stage
(`examples/audioxt-demo.livecodescript`): each of its scenes is one of the ideas below, at
work, and its code is written to be read.

## The conventions

- **Handles are integers.** An engine, a sound, a group or a capture is a number; 0 is
  "none" and is what a refused create returns. A handle to something freed is refused by
  every call, harmlessly: getters answer 0 or empty, actions do nothing. Freeing an engine
  frees its sounds and groups.
- **Every time is in seconds**, as a number with a fraction: 0.25 is a quarter of a second.
- **A volume is a multiplier.** 1 is the sound as recorded, 0.5 half, 0 silence, up to 100.
  A sound's volume, its group's and its engine's multiply together.
- **Several numbers come back as text.** `auEnginePeak` returns `"left,right"`, a position
  `"x,y,z"`. The decimal point is `.` in every locale.
- **Sound data is binary data.** A sound file read from a `binfile:` URL or kept in a custom
  property goes in as it is; samples and WAV files come back the same way.
- **Every parameter is typed.** A number parameter must be given a number: empty is an
  engine error at the call, before audioxt sees it. Pass 0, not empty.
- **Nothing throws.** A call with a bad argument does nothing, returns 0 or empty, and
  `auLastError()` says why. The one exception is a native library from a different release
  than the binding: the first call throws and names the ABI it needs.
- **Nothing sends a message.** The library never calls your script. To learn that a sound
  has ended, ask (`auPollEnded`), usually on a timer.

## An engine, and sounds on it

```livecodescript
local sEngine, sMusic, sClick

on openStack
   put auEngineCreate(0, 0, 0) into sEngine
   if sEngine is 0 then
      answer "No sound: " & auLastError()
      exit openStack
   end if
   put auSoundLoad(sEngine, specialFolderPath("resources") & "/theme.mp3", true) into sMusic
   put auSoundLoad(sEngine, specialFolderPath("resources") & "/click.wav", false) into sClick
   auSoundSetLooping sMusic, true
   auSoundStart sMusic
   send "soundTick" to me in 100 milliseconds
end openStack

on soundTick
   local tIndex
   repeat with tIndex = 1 to auPollEnded()
      -- auEndedSound(tIndex) is a sound that just finished
   end repeat
   send "soundTick" to me in 100 milliseconds
end soundTick

on closeStack
   auShutDown
end closeStack
```

`auEngineCreate(0, 0, 0)` opens the system's default device in the device's own format, which
is what almost every stack wants. The last argument of `auSoundLoad` chooses how the file is
read: `false` decodes all of it into memory now, so it starts instantly and can be cloned;
`true` streams it from disk while it plays, which is right for anything longer than a few
seconds.

To play one effect several times at once, clone it. A clone shares the samples and costs
almost nothing:

```livecodescript
put auSoundClone(sClick) into tShot
auSoundSetAutoFree tShot, true        -- freed by the auPollEnded that reports its end
auSoundSetPan tShot, random(200) / 100 - 1
auSoundStart tShot
```

## Timing that does not drift

A script timer is late by a few milliseconds every time, which a listener hears in a rhythm.
The engine has its own clock, counted in samples (`auEngineTime`), and a sound can be told to
start at a time on it:

```livecodescript
put auEngineTime(sEngine) + 0.1 into tWhen
repeat with tBeat = 0 to 15
   auSoundStartAt auSoundClone(sTick), tWhen + tBeat * 0.5
end repeat
```

Schedule a little ahead (a tenth of a second is plenty) and the sounds land on the sample.

## Groups

```livecodescript
put auGroupCreate(sEngine) into sEffects
auSoundSetGroup sClick, sEffects
auGroupSetVolume sEffects, the thumbPosition of scrollbar "effects" / 100
```

Clones do not inherit their original's group: route each clone you make.

## The microphone

```livecodescript
local sMic, sRecording

on startListening
   put auCaptureOpen(0, "s16", 16000, 1, 5) into sMic
   if sMic is 0 or not auCaptureStart(sMic) then
      answer "No microphone: " & auLastError()
      exit startListening
   end if
   put empty into sRecording
   send "micTick" to me in 100 milliseconds
end startListening

on micTick
   if not auCaptureIsValid(sMic) then exit micTick
   put auCaptureRead(sMic) after sRecording
   set the thumbPosition of scrollbar "level" to auCapturePeak(sMic) * 100
   send "micTick" to me in 100 milliseconds
end micTick

on stopListening
   auCaptureClose sMic
   put auWAVEncode(sRecording, "s16", 16000, 1) into url ("binfile:" & specialFolderPath("documents") & "/memo.wav")
end stopListening
```

The samples arrive in the format you asked for, whatever the device uses. To save a long
recording without holding it in memory, let the library write the file as the sound arrives:
`auCaptureRecordStart sMic, tPath`, later `auCaptureRecordStop(sMic)`.

**Permission.** The operating system decides who may listen. A standalone must declare that
it uses the microphone: on Android the `RECORD_AUDIO` permission (and the person's consent,
asked by the system), on macOS and iOS a microphone usage description in the application's
property list, in a browser the visitor's answer to the browser's own prompt. Without it the
open fails or the samples are silence, and `auLastError()` says what the system reported. A
browser offers a microphone only to a page served over https or from the visitor's own
computer: on a plain http page `auCaptureOpen` returns 0 and `auLastError()` says so.

## Sample formats

Wherever a format is asked for it is one of five names:

| Name | One sample is | Range |
|---|---|---|
| `u8` | 1 byte, unsigned | 0 to 255, silence at 128 |
| `s16` | 2 bytes, signed, little-endian | -32768 to 32767 |
| `s24` | 3 bytes, signed, little-endian | -8388608 to 8388607 |
| `s32` | 4 bytes, signed, little-endian | -2147483648 to 2147483647 |
| `f32` | 4 bytes, floating point | -1 to 1 |

A FRAME is one sample for every channel, and channels are interleaved: stereo `s16` is left,
right, left, right, four bytes a frame. `binaryDecode("s", ...)` reads an `s16` sample.

## Six rules that decide whether a sound is heard

1. **Keep the handle.** A sound lives until it is freed or its engine is. A handle put in a
   handler's local variable is not freed when the handler ends: the sound goes on playing and
   you can no longer stop it. Keep handles in script locals, or mark one-shot sounds
   `auSoundSetAutoFree` and call `auPollEnded` now and then.
2. **Auto-free needs the poll.** Nothing is freed behind your back: the `auPollEnded` call
   that reports a sound's end is the one that frees it. A stack that marks sounds auto-free
   and never polls keeps them all (up to 65,536, then loads are refused).
3. **In a browser, sound waits for the visitor.** A page may not make sound until the
   visitor has clicked, tapped or pressed a key on it. Open the engine and start sounds
   whenever you like; they are heard from that moment on.
4. **A stream cannot be cloned, and a tone has no end.** `auSoundClone` works on sounds
   loaded whole or made from samples. A tone or noise plays until stopped; stop it at a time
   with `auSoundStopAt`.
5. **Scan before choosing a device.** Device numbers are positions in the lists
   `auDeviceScan` made. 0 is always the default device and needs no scan.
6. **Shut down when the stack closes.** `auShutDown` closes every device. Without it a
   device can stay open, and sound can go on, after the stack's window has gone.

## The limits every call is held to

An argument outside these limits is refused before miniaudio sees it, and `auLastError()`
says which.

| What | Limit |
|---|---|
| A volume | 0 to 100 |
| A pan | -1 to 1 |
| A pitch | 0.01 to 100 |
| A sample rate | 8,000 to 192,000 hertz |
| Channels | 1 to 8 |
| A tone's frequency | 1 to 96,000 hertz; its amplitude 0 to 1 |
| A fade | 0 to 3,600 seconds |
| A coordinate | finite, within 1,000,000 either side of 0 |
| A distance range | nearest 0.001 or more, farthest not below it |
| A rolloff, a Doppler factor | 0 to 100 |
| One block of bytes, in or out | 256 MB |
| A capture's buffer | 0.1 to 600 seconds |
| A path | 1 to 4,096 bytes, not ending in a dot |
| Engines at once | 16 |
| Captures at once | 16 |
| Sounds at once | 65,536 |
| Groups at once | 1,024 |

## What it does not do

- **Ogg Vorbis, Opus, AAC.** WAV, FLAC and MP3 only.
- **Effects** (reverb, filters, equalisers). The mixer has volume, pan, pitch, fades and 3D.
- **Recording what the computer is playing** (loopback), and choosing a device's own format.
- **MIDI.** Tones are made with `auSoundTone`; there is no synthesiser.
