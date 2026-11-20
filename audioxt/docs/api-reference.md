# audioxt API reference

The 112 public handlers, from the doc blocks in `src/audioxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the units, the limits every
call is held to, and the handful of rules that decide whether a sound is heard.

## The library

### `auABIVersion`

`auABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `auLibraryVersion`

`auLibraryVersion() returns String`

Returns the versions of the native library and of miniaudio inside it.

Returns: Text such as "audioxt ABI 1; miniaudio 0.11.26".

It throws if the library on disk has a different ABI from this binding, which means the two come from different releases.

```
put auLibraryVersion() into field "status"
```

### `auLastError`

`auLastError() returns String`

Returns why the last refused call was refused.

Returns: A short sentence, or empty if nothing has been refused yet.

A call given a bad argument does nothing and returns 0 or empty; it never throws. This says what was wrong, for example "the pan must be -1 (left) to 1 (right)" or the reason a sound file would not load. A successful create clears it.

### `auOutSampleRate`

`auOutSampleRate() returns Integer`

Returns the sample rate of the samples the last decode, render or capture read returned.

Returns: The sample rate in hertz, or 0 before the first such call.

`auDecodeFile` and `auDecodeData` can keep a file's own sample rate; this is how a script learns what that was.

### `auOutChannels`

`auOutChannels() returns Integer`

Returns the channel count of the samples the last decode, render or capture read returned.

Returns: The channel count (1 is mono, 2 stereo), or 0 before the first such call.

### `auBackendName`

`auBackendName() returns String`

Returns the name of the audio system the library is using.

Returns: A name such as "WASAPI", "Core Audio", "PulseAudio", "ALSA", "AAudio" or "Web Audio", or empty if this machine has none the library can use.

Asking opens the audio system if it is not open yet.

## Devices

### `auDeviceScan`

`auDeviceScan() returns Integer`

Asks the audio system which playback and capture devices it has.

Returns: How many devices were found in all, or -1 if there is no audio system to ask.

The device numbers taken by `auEngineCreate` and `auCaptureOpen` are positions in the lists this call made, so scan before letting someone choose a device. Device 0 always means the system's default and needs no scan. In a web browser there is one playback device and one capture device.

```
if auDeviceScan() > 0 then
repeat with i = 1 to auPlaybackDeviceCount()
put auPlaybackDeviceName(i) & return after field "devices"
end repeat
end if
```

### `auPlaybackDeviceCount`

`auPlaybackDeviceCount() returns Integer`

Returns how many playback devices the last scan found.

Returns: The count; 0 before the first `auDeviceScan`.

### `auPlaybackDeviceName`

`auPlaybackDeviceName(in pIndex as Integer) returns String`

Returns the name of a playback device.

- pIndex: The device's number, from 1 to `auPlaybackDeviceCount`.

Returns: The device's name as the system shows it, or empty if there is no such device.

### `auPlaybackDeviceIsDefault`

`auPlaybackDeviceIsDefault(in pIndex as Integer) returns Boolean`

Reports whether a playback device is the system's default.

- pIndex: The device's number, from 1 to `auPlaybackDeviceCount`.

Returns: True if it is the one the system plays through by default.

### `auCaptureDeviceCount`

`auCaptureDeviceCount() returns Integer`

Returns how many capture devices (microphones and other inputs) the last scan found.

Returns: The count; 0 before the first `auDeviceScan`.

### `auCaptureDeviceName`

`auCaptureDeviceName(in pIndex as Integer) returns String`

Returns the name of a capture device.

- pIndex: The device's number, from 1 to `auCaptureDeviceCount`.

Returns: The device's name as the system shows it, or empty if there is no such device.

### `auCaptureDeviceIsDefault`

`auCaptureDeviceIsDefault(in pIndex as Integer) returns Boolean`

Reports whether a capture device is the system's default.

- pIndex: The device's number, from 1 to `auCaptureDeviceCount`.

Returns: True if it is the one the system records from by default.

## Engines

### `auEngineCreate`

`auEngineCreate(in pDevice as Integer, in pSampleRate as Integer, in pChannels as Integer) returns Integer`

Opens a playback device and starts mixing sounds into it.

- pDevice: The device: 0 for the system's default, 1 or more for a device of the last `auDeviceScan`, -1 for the silent test device.
- pSampleRate: The sample rate in hertz (8000 to 192000), or 0 for the device's own.
- pChannels: The channel count (1 to 8), or 0 for the device's own.

Returns: The engine's handle, or 0 if the device could not be opened (`auLastError` says why).

An engine is one mixer playing into one device. Every sound belongs to an engine, and any number of them can play at once. Most stacks need one engine, created when the stack opens and freed with `auEngineFree` or `auShutDown` when it closes. Up to 16 can be open.

```
put auEngineCreate(0, 0, 0) into sEngine
put auSoundLoad(sEngine, specialFolderPath("resources") & "/click.wav", false) into sClick
auSoundStart sClick
```

### `auEngineCreateOffline`

`auEngineCreateOffline(in pSampleRate as Integer, in pChannels as Integer) returns Integer`

Creates an engine with no device, whose mix is read as samples.

- pSampleRate: The sample rate in hertz, 8000 to 192000.
- pChannels: The channel count, 1 to 8.

Returns: The engine's handle, or 0 if it was refused.

Nothing is heard. `auEngineRender` mixes the next stretch of sound and returns it, as fast as the computer can work: for saving a mix to a file, for drawing a waveform, and for tests. Everything else about the engine is the same as one with a device.

```
put auEngineCreateOffline(44100, 2) into tEngine
put auSoundLoad(tEngine, tPath, false) into tSound
auSoundStart tSound
put auEngineRender(tEngine, 44100, "s16") into tOneSecond
put auWAVEncode(tOneSecond, "s16", 44100, 2) into url ("binfile:" & tOut)
auEngineFree tEngine
```

### `auEngineFree`

`auEngineFree(in pEngine as Integer) returns nothing`

Closes an engine and frees every sound and group made on it.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

The device is closed. Handles of the engine and of its sounds and groups become stale, which is harmless: calls on them do nothing.

### `auEngineIsValid`

`auEngineIsValid(in pEngine as Integer) returns Boolean`

Reports whether a handle is an open engine.

- pEngine: The handle to ask about.

Returns: True for an engine that has not been freed.

### `auEngineIsOffline`

`auEngineIsOffline(in pEngine as Integer) returns Boolean`

Reports whether an engine was made by `auEngineCreateOffline`.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: True for an offline engine; false for one playing into a device, and for a stale handle.

### `auEngineStart`

`auEngineStart(in pEngine as Integer) returns nothing`

Resumes an engine that `auEngineStop` paused.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Sounds carry on from where they were.

### `auEngineStop`

`auEngineStop(in pEngine as Integer) returns nothing`

Pauses an engine: nothing is heard and its clock stands still.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Sounds keep their places and carry on after `auEngineStart`. An engine is running when it is created. Pause it while a stack is hidden to use no processor time.

### `auEngineSetVolume`

`auEngineSetVolume(in pEngine as Integer, in pVolume as Number) returns nothing`

Sets the master volume of an engine.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pVolume: The volume: 0 is silent, 1 unchanged, up to 100.

Applied to everything the engine plays, on top of each sound's and group's own volume.

### `auEngineVolume`

`auEngineVolume(in pEngine as Integer) returns Number`

Returns the master volume of an engine.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The volume; 1 is unchanged. 0 for a stale handle.

### `auEngineSampleRate`

`auEngineSampleRate(in pEngine as Integer) returns Integer`

Returns the sample rate an engine mixes at.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The sample rate in hertz, or 0 for a stale handle.

### `auEngineChannels`

`auEngineChannels(in pEngine as Integer) returns Integer`

Returns the channel count an engine mixes to.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The channel count (2 is stereo), or 0 for a stale handle.

### `auEngineTime`

`auEngineTime(in pEngine as Integer) returns Number`

Returns an engine's clock: the seconds of sound it has mixed since it was created.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The time in seconds.

`auSoundStartAt` and `auSoundStopAt` are measured against this clock, which counts samples and so does not drift from the sound. It stands still while the engine is paused.

```
-- four clicks, exactly half a second apart, starting a tenth of a second from now
put auEngineTime(sEngine) + 0.1 into tWhen
repeat with i = 0 to 3
auSoundStartAt auSoundClone(sClick), tWhen + i * 0.5
end repeat
```

### `auEngineSoundCount`

`auEngineSoundCount(in pEngine as Integer) returns Integer`

Returns how many sounds an engine holds.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The number of sounds loaded or made on the engine and not yet freed.

### `auEngineDeviceName`

`auEngineDeviceName(in pEngine as Integer) returns String`

Returns the name of the device an engine plays into.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The device's name; empty for an offline engine and for a stale handle.

### `auEngineStopAll`

`auEngineStopAll(in pEngine as Integer) returns nothing`

Stops every sound of an engine where it is.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Each sound keeps its place, as after `auSoundStop`.

### `auEnginePeak`

`auEnginePeak(in pEngine as Integer) returns String`

Returns the loudest level an engine has played since the last call, for a level meter.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: Text "left,right", each 0 to 1; a value above 1 means the output is clipping.

Reading resets it, so call it once per screen update. A mono engine gives the same value twice.

```
put auEnginePeak(sEngine) into tPeak
set the thumbPosition of scrollbar "left" to item 1 of tPeak * 100
set the thumbPosition of scrollbar "right" to item 2 of tPeak * 100
```

### `auEngineWaveform`

`auEngineWaveform(in pEngine as Integer, in pPoints as Integer) returns String`

Returns the newest sound an engine mixed as a list of points, for an oscilloscope display.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pPoints: How many points to return, 1 to 2048.

Returns: Comma-separated numbers from -1 to 1, oldest first; empty if refused.

The points are spread evenly over the newest 2048 frames, left and right averaged.

### `auEngineRender`

`auEngineRender(in pEngine as Integer, in pFrames as Integer, in pFormat as String) returns Data`

Mixes the next stretch of sound of an offline engine and returns its samples.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pFrames: How many frames to mix. A frame is one sample for every channel.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".

Returns: The samples, as binary data of pFrames frames in pFormat; empty if refused.

Only for an engine made by `auEngineCreateOffline`. Each call carries on where the last one stopped and moves the engine's clock on. Wrap the result with `auWAVEncode` to make a sound file. The five sample formats are "u8" (8-bit unsigned), "s16", "s24" and "s32" (signed, little-endian) and "f32" (32-bit floating point, -1 to 1). Samples of several channels are interleaved (left, right, left, right).

## The listener

### `auEngineSetListenerPosition`

`auEngineSetListenerPosition(in pEngine as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets where the listener is, for sounds that have a place in 3D.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pX: The x coordinate.
- pY: The y coordinate.
- pZ: The z coordinate.

Only sounds turned on with `auSoundSetSpatial` are affected. Distances are in whatever unit the stack uses; metres work well with the default settings. The listener starts at 0,0,0.

### `auEngineListenerPosition`

`auEngineListenerPosition(in pEngine as Integer) returns String`

Returns where the listener is.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: Text "x,y,z".

### `auEngineSetListenerDirection`

`auEngineSetListenerDirection(in pEngine as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets the way the listener faces.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pX: The x part of the direction.
- pY: The y part of the direction.
- pZ: The z part of the direction.

The default is 0,0,-1: looking along the negative z axis, with x to the right. The three numbers cannot all be 0.

### `auEngineListenerDirection`

`auEngineListenerDirection(in pEngine as Integer) returns String`

Returns the way the listener faces.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: Text "x,y,z".

### `auEngineSetListenerUp`

`auEngineSetListenerUp(in pEngine as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets which way is up for the listener.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pX: The x part of the direction.
- pY: The y part of the direction.
- pZ: The z part of the direction.

The default is 0,1,0. The three numbers cannot all be 0.

### `auEngineSetListenerVelocity`

`auEngineSetListenerVelocity(in pEngine as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets the listener's velocity, for the Doppler effect.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pX: The x part of the velocity, in units per second.
- pY: The y part of the velocity.
- pZ: The z part of the velocity.

It changes the pitch of sounds moving towards or away from the listener, and moves nothing: the position is still set with `auEngineSetListenerPosition`.

## Sounds: loading and making

### `auSoundLoad`

`auSoundLoad(in pEngine as Integer, in pPath as String, in pStream as Boolean) returns Integer`

Loads a sound file: WAV, FLAC or MP3.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pPath: The full path of the file.
- pStream: True to decode while playing (music); false to decode it whole now (effects).

Returns: The sound's handle, or 0 if the file could not be loaded (`auLastError` says why).

A sound loaded whole is decoded into memory at once: right for short effects that must start instantly and are played often, and it can be cloned with `auSoundClone`. A streamed sound is decoded a little at a time while it plays and uses little memory: right for music. The sound does not play until `auSoundStart`.

```
put auSoundLoad(sEngine, tFolder & "/theme.mp3", true) into sMusic
auSoundSetLooping sMusic, true
auSoundStart sMusic
```

### `auSoundLoadData`

`auSoundLoadData(in pEngine as Integer, in pData as Data, in pStream as Boolean) returns Integer`

Loads a sound from the bytes of a sound file: WAV, FLAC or MP3.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pData: The whole contents of a sound file, as binary data.
- pStream: True to decode while playing; false to decode it whole now.

Returns: The sound's handle, or 0 if the data is not a sound file the library can read.

For a sound kept in a custom property, read from a binfile: URL or downloaded. The bytes are copied, so the variable can be reused. At most 256 MB.

```
put auSoundLoadData(sEngine, the uClick of this stack, false) into sClick
```

### `auSoundFromPCM`

`auSoundFromPCM(in pEngine as Integer, in pData as Data, in pFormat as String, in pSampleRate as Integer, in pChannels as Integer) returns Integer`

Makes a sound from raw samples.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pData: The samples, as binary data.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".
- pSampleRate: The sample rate of the samples in hertz, 8000 to 192000.
- pChannels: How many channels the samples have, 1 to 8.

Returns: The sound's handle, or 0 if it was refused.

For sound a script computed, recorded with `auCaptureRead` or decoded with `auDecodeFile`. The samples are copied; bytes that do not make a whole frame at the end are ignored. The five sample formats are "u8" (8-bit unsigned), "s16", "s24" and "s32" (signed, little-endian) and "f32" (32-bit floating point, -1 to 1). Samples of several channels are interleaved (left, right, left, right).

### `auSoundTone`

`auSoundTone(in pEngine as Integer, in pShape as String, in pHertz as Number, in pAmplitude as Number) returns Integer`

Makes a tone that plays until it is stopped.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pShape: The waveform: "sine", "square", "triangle" or "sawtooth".
- pHertz: The frequency in hertz, 1 to 96000. Middle A is 440.
- pAmplitude: How loud, 0 to 1. 0.2 is a comfortable level.

Returns: The sound's handle, or 0 if it was refused.

`auSoundSetFrequency` changes the frequency while it plays.

```
put auSoundTone(sEngine, "sine", 440, 0.2) into tBeep
auSoundStart tBeep
auSoundStopAt tBeep, auEngineTime(sEngine) + 0.25
```

### `auSoundNoise`

`auSoundNoise(in pEngine as Integer, in pColor as String, in pAmplitude as Number) returns Integer`

Makes noise that plays until it is stopped.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.
- pColor: The kind of noise: "white" (a hiss) or "pink" (softer, like rain).
- pAmplitude: How loud, 0 to 1.

Returns: The sound's handle, or 0 if it was refused.

### `auSoundClone`

`auSoundClone(in pSound as Integer) returns Integer`

Makes another sound over the same samples, so one loaded effect can play many times at once.

- pSound: The sound to clone.

Returns: The new sound's handle, or 0 if the sound cannot be cloned.

The clone has its own volume, pan, pitch, place and playing state, and uses no more memory for the samples. Only a sound that was loaded whole or made from samples can be cloned; a stream, a tone or noise cannot.

```
-- every shot is its own sound, freed when it ends
put auSoundClone(sShot) into tShot
auSoundSetAutoFree tShot, true
auSoundStart tShot
```

### `auSoundFree`

`auSoundFree(in pSound as Integer) returns nothing`

Frees a sound.

- pSound: A sound.

It stops if it is playing. Clones of it are not affected. Freeing an engine frees its sounds too.

### `auSoundIsValid`

`auSoundIsValid(in pSound as Integer) returns Boolean`

Reports whether a handle is a sound that has not been freed.

- pSound: The handle to ask about.

Returns: True for a live sound.

### `auSoundEngine`

`auSoundEngine(in pSound as Integer) returns Integer`

Returns the engine a sound belongs to.

- pSound: A sound.

Returns: The engine's handle, or 0 for a stale sound.

## Sounds: playing

### `auSoundStart`

`auSoundStart(in pSound as Integer) returns nothing`

Plays a sound.

- pSound: A sound.

It plays from where it is: from the start the first time, from where `auSoundStop` left it, or from the start again if it had reached its end. Starting a sound that is playing changes nothing; to play one effect several times at once, use `auSoundClone`.

### `auSoundStartAt`

`auSoundStartAt(in pSound as Integer, in pSeconds as Number) returns nothing`

Starts a sound at an exact time on its engine's clock.

- pSound: A sound.
- pSeconds: The time on the engine's clock, as `auEngineTime` reports it.

The sound begins on the exact sample, however busy the script is in between: how notes are placed on a beat.

### `auSoundStop`

`auSoundStop(in pSound as Integer) returns nothing`

Stops a sound where it is.

- pSound: A sound.

`auSoundStart` carries on from there. To go back to the start, call `auSoundSeek` with 0.

### `auSoundStopAt`

`auSoundStopAt(in pSound as Integer, in pSeconds as Number) returns nothing`

Stops a sound at an exact time on its engine's clock.

- pSound: A sound.
- pSeconds: The time on the engine's clock, as `auEngineTime` reports it.

### `auSoundStopWithFade`

`auSoundStopWithFade(in pSound as Integer, in pSeconds as Number) returns nothing`

Fades a sound out and then stops it.

- pSound: A sound.
- pSeconds: How long the fade takes, 0 to 3600 seconds.

### `auSoundFade`

`auSoundFade(in pSound as Integer, in pFrom as Number, in pTo as Number, in pSeconds as Number) returns nothing`

Moves a sound's volume smoothly from one level to another.

- pSound: A sound.
- pFrom: The level to start from, 0 to 100, or -1 for the level the fade is at now.
- pTo: The level to end at, 0 to 100.
- pSeconds: How long the fade takes, 0 to 3600 seconds.

The fade starts now. It multiplies the sound's own volume (`auSoundSetVolume`) and does not replace it.

```
-- fade the music in over two seconds
auSoundFade sMusic, 0, 1, 2
auSoundStart sMusic
```

### `auSoundIsPlaying`

`auSoundIsPlaying(in pSound as Integer) returns Boolean`

Reports whether a sound is playing.

- pSound: A sound.

Returns: True while it plays; false once it is stopped or has reached its end.

### `auSoundAtEnd`

`auSoundAtEnd(in pSound as Integer) returns Boolean`

Reports whether a sound has reached its end.

- pSound: A sound.

Returns: True once it has played to its end and has not been started again.

### `auSoundSeek`

`auSoundSeek(in pSound as Integer, in pSeconds as Number) returns nothing`

Moves the playing position of a sound.

- pSound: A sound.
- pSeconds: The position in seconds from the start of the sound.

Not for a tone or noise, which have no length.

### `auSoundPosition`

`auSoundPosition(in pSound as Integer) returns Number`

Returns the playing position of a sound.

- pSound: A sound.

Returns: The position in seconds from the start of the sound.

### `auSoundLength`

`auSoundLength(in pSound as Integer) returns Number`

Returns the length of a sound.

- pSound: A sound.

Returns: The length in seconds; 0 for a tone or noise, which have no end.

## Sounds: volume, pan, pitch and loops

### `auSoundSetVolume`

`auSoundSetVolume(in pSound as Integer, in pVolume as Number) returns nothing`

Sets the volume of a sound.

- pSound: A sound.
- pVolume: The volume: 0 is silent, 1 unchanged, up to 100.

### `auSoundVolume`

`auSoundVolume(in pSound as Integer) returns Number`

Returns the volume of a sound.

- pSound: A sound.

Returns: The volume; 1 is unchanged.

### `auSoundSetPan`

`auSoundSetPan(in pSound as Integer, in pPan as Number) returns nothing`

Sets where a sound sits between the left and right speakers.

- pSound: A sound.
- pPan: The pan: -1 is all the way left, 0 the middle, 1 all the way right.

### `auSoundPan`

`auSoundPan(in pSound as Integer) returns Number`

Returns the pan of a sound.

- pSound: A sound.

Returns: The pan, -1 (left) to 1 (right).

### `auSoundSetPitch`

`auSoundSetPitch(in pSound as Integer, in pPitch as Number) returns nothing`

Sets the pitch of a sound.

- pSound: A sound.
- pPitch: The pitch: 1 is unchanged, 2 an octave up, 0.5 an octave down (0.01 to 100).

Raising the pitch also makes the sound play faster, like a record at the wrong speed.

### `auSoundPitch`

`auSoundPitch(in pSound as Integer) returns Number`

Returns the pitch of a sound.

- pSound: A sound.

Returns: The pitch; 1 is unchanged.

### `auSoundSetLooping`

`auSoundSetLooping(in pSound as Integer, in pFlag as Boolean) returns nothing`

Sets whether a sound starts again when it reaches its end.

- pSound: A sound.
- pFlag: True to loop.

A looping sound never ends, so `auPollEnded` never reports it.

### `auSoundIsLooping`

`auSoundIsLooping(in pSound as Integer) returns Boolean`

Reports whether a sound loops.

- pSound: A sound.

Returns: True if it loops.

### `auSoundSetLoopRange`

`auSoundSetLoopRange(in pSound as Integer, in pStartSeconds as Number, in pEndSeconds as Number) returns nothing`

Sets the part of a sound that a loop repeats.

- pSound: A sound.
- pStartSeconds: Where the repeated part begins, in seconds from the start of the sound.
- pEndSeconds: Where it ends, or 0 for the end of the sound.

For music with an introduction: the sound plays from its start, and each repeat goes back to the start of the range. Looping itself is turned on with `auSoundSetLooping`. Not for a tone or noise.

### `auSoundSetFrequency`

`auSoundSetFrequency(in pSound as Integer, in pHertz as Number) returns nothing`

Changes the frequency of a tone while it plays.

- pSound: A sound made by `auSoundTone`.
- pHertz: The frequency in hertz, 1 to 96000.

### `auSoundSetAutoFree`

`auSoundSetAutoFree(in pSound as Integer, in pFlag as Boolean) returns nothing`

Sets whether a sound is freed when it ends.

- pSound: A sound.
- pFlag: True to free the sound at its end.

Play it and forget it: the `auPollEnded` that reports the sound's end frees it. A stack that uses this must call `auPollEnded` now and then.

### `auSoundSetGroup`

`auSoundSetGroup(in pSound as Integer, in pGroup as Integer) returns nothing`

Routes a sound through a group.

- pSound: A sound.
- pGroup: A group, from `auGroupCreate`, or 0 to play straight to the engine's output again.

The group's volume, pan and pitch then apply to the sound as well as its own. The sound and the group must belong to the same engine.

### `auSoundGroup`

`auSoundGroup(in pSound as Integer) returns Integer`

Returns the group a sound plays through.

- pSound: A sound.

Returns: The group's handle, or 0 if it plays straight to the engine's output.

## Sounds: a place in 3D

### `auSoundSetSpatial`

`auSoundSetSpatial(in pSound as Integer, in pFlag as Boolean) returns nothing`

Sets whether a sound has a place in 3D.

- pSound: A sound.
- pFlag: True to give the sound a place.

A sound with a place gets quieter with distance from the listener and is heard from its direction. Sounds start without one, which is right for music and interface sounds.

```
auSoundSetSpatial sBee, true
auSoundSetPosition sBee, 3, 0, -1
```

### `auSoundIsSpatial`

`auSoundIsSpatial(in pSound as Integer) returns Boolean`

Reports whether a sound has a place in 3D.

- pSound: A sound.

Returns: True if it has.

### `auSoundSetPosition`

`auSoundSetPosition(in pSound as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets where a sound is.

- pSound: A sound.
- pX: The x coordinate.
- pY: The y coordinate.
- pZ: The z coordinate.

It has an effect once `auSoundSetSpatial` has turned the sound's place on. The listener is placed with `auEngineSetListenerPosition`.

### `auSoundPositionXYZ`

`auSoundPositionXYZ(in pSound as Integer) returns String`

Returns where a sound is.

- pSound: A sound.

Returns: Text "x,y,z".

### `auSoundSetVelocity`

`auSoundSetVelocity(in pSound as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets a sound's velocity, for the Doppler effect.

- pSound: A sound.
- pX: The x part of the velocity, in units per second.
- pY: The y part of the velocity.
- pZ: The z part of the velocity.

It changes the pitch of a sound moving towards or away from the listener, and moves nothing.

### `auSoundSetDistanceRange`

`auSoundSetDistanceRange(in pSound as Integer, in pNearest as Number, in pFarthest as Number) returns nothing`

Sets the distances between which a sound fades.

- pSound: A sound.
- pNearest: Nearer than this, the sound is at full volume. 0.001 or more; the default is 1.
- pFarthest: Beyond this, the sound gets no quieter. Not less than pNearest.

### `auSoundSetRolloff`

`auSoundSetRolloff(in pSound as Integer, in pRolloff as Number) returns nothing`

Sets how fast a sound fades with distance.

- pSound: A sound.
- pRolloff: 1 is natural, 0 does not fade at all, larger fades faster (0 to 100).

### `auSoundSetDoppler`

`auSoundSetDoppler(in pSound as Integer, in pFactor as Number) returns nothing`

Sets how strong the Doppler effect is for a sound.

- pSound: A sound.
- pFactor: 1 is natural, 0 turns it off (0 to 100).

## Groups

### `auGroupCreate`

`auGroupCreate(in pEngine as Integer) returns Integer`

Creates a group: one volume, pan and pitch for many sounds.

- pEngine: An engine, from `auEngineCreate` or `auEngineCreateOffline`.

Returns: The group's handle, or 0 if it was refused.

Typically one group for music and one for effects, each with its own volume slider. Sounds join with `auSoundSetGroup`. Up to 1024 groups.

```
put auGroupCreate(sEngine) into sEffects
auSoundSetGroup sClick, sEffects
auGroupSetVolume sEffects, 0.5   -- the effects slider
```

### `auGroupFree`

`auGroupFree(in pGroup as Integer) returns nothing`

Frees a group.

- pGroup: A group, from `auGroupCreate`.

Its sounds are not freed: they play straight to the engine's output again.

### `auGroupIsValid`

`auGroupIsValid(in pGroup as Integer) returns Boolean`

Reports whether a handle is a group that has not been freed.

- pGroup: The handle to ask about.

Returns: True for a live group.

### `auGroupSetVolume`

`auGroupSetVolume(in pGroup as Integer, in pVolume as Number) returns nothing`

Sets the volume of a group.

- pGroup: A group, from `auGroupCreate`.
- pVolume: The volume: 0 is silent, 1 unchanged, up to 100.

### `auGroupVolume`

`auGroupVolume(in pGroup as Integer) returns Number`

Returns the volume of a group.

- pGroup: A group, from `auGroupCreate`.

Returns: The volume; 1 is unchanged.

### `auGroupSetPan`

`auGroupSetPan(in pGroup as Integer, in pPan as Number) returns nothing`

Sets the pan of a group.

- pGroup: A group, from `auGroupCreate`.
- pPan: The pan: -1 is all the way left, 0 the middle, 1 all the way right.

### `auGroupPan`

`auGroupPan(in pGroup as Integer) returns Number`

Returns the pan of a group.

- pGroup: A group, from `auGroupCreate`.

Returns: The pan, -1 (left) to 1 (right).

### `auGroupSetPitch`

`auGroupSetPitch(in pGroup as Integer, in pPitch as Number) returns nothing`

Sets the pitch of a group.

- pGroup: A group, from `auGroupCreate`.
- pPitch: The pitch: 1 is unchanged, 2 an octave up, 0.5 an octave down (0.01 to 100).

### `auGroupPitch`

`auGroupPitch(in pGroup as Integer) returns Number`

Returns the pitch of a group.

- pGroup: A group, from `auGroupCreate`.

Returns: The pitch; 1 is unchanged.

### `auGroupStart`

`auGroupStart(in pGroup as Integer) returns nothing`

Lets a group's sounds be heard again after `auGroupStop`.

- pGroup: A group, from `auGroupCreate`.

### `auGroupStop`

`auGroupStop(in pGroup as Integer) returns nothing`

Silences a group.

- pGroup: A group, from `auGroupCreate`.

Its sounds keep their own playing state and are heard again after `auGroupStart`.

## Sounds that ended

### `auPollEnded`

`auPollEnded() returns Integer`

Finds the sounds that reached their end since the last call.

Returns: How many sounds ended.

The library never sends a message: a stack that wants to know when sounds end asks, on a timer. Read each one with `auEndedSound`. Sounds marked with `auSoundSetAutoFree` are freed by this call. A looping sound never ends, and a stopped sound has not ended.

```
on checkSounds
repeat with i = 1 to auPollEnded()
if auEndedSound(i) is sMusic then playNextSong
end repeat
send "checkSounds" to me in 100 milliseconds
end checkSounds
```

### `auEndedSound`

`auEndedSound(in pIndex as Integer) returns Integer`

Returns one of the sounds the last `auPollEnded` found.

- pIndex: Which one, from 1 to the number `auPollEnded` returned.

Returns: The sound's handle, or 0 if there is no such entry.

A sound that was freed at its end is still listed, so a script can tell which one it was; its handle is no longer valid.

## The microphone

### `auCaptureOpen`

`auCaptureOpen(in pDevice as Integer, in pFormat as String, in pSampleRate as Integer, in pChannels as Integer, in pBufferSeconds as Number) returns Integer`

Opens a microphone or another input device.

- pDevice: The device: 0 for the system's default, 1 or more for a capture device of the last `auDeviceScan`, -1 for the silent test device.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".
- pSampleRate: The sample rate in hertz, 8000 to 192000. 16000 suits speech, 44100 or 48000 music.
- pChannels: The channel count, 1 to 8. 1 is mono.
- pBufferSeconds: How many seconds of sound are kept for a script that has not read yet, 0.1 to 600.

Returns: The capture's handle, or 0 if the device could not be opened (`auLastError` says why).

The samples arrive in exactly the format, sample rate and channel count asked for, whatever the device itself uses. Nothing is recorded until `auCaptureStart`. Read what has arrived with `auCaptureRead`, or write it straight to a file with `auCaptureRecordStart`. Up to 16 captures can be open.

```
put auCaptureOpen(0, "s16", 16000, 1, 5) into sMic
if auCaptureStart(sMic) then
send "readMic" to me in 100 milliseconds
end if
```

### `auCaptureClose`

`auCaptureClose(in pCapture as Integer) returns nothing`

Closes a capture.

- pCapture: A capture, from `auCaptureOpen`.

A WAV file being recorded is finished and closed first.

### `auCaptureIsValid`

`auCaptureIsValid(in pCapture as Integer) returns Boolean`

Reports whether a handle is an open capture.

- pCapture: The handle to ask about.

Returns: True for a capture that has not been closed.

### `auCaptureStart`

`auCaptureStart(in pCapture as Integer) returns Boolean`

Starts listening.

- pCapture: A capture, from `auCaptureOpen`.

Returns: True if the device is now running; false if it could not be started.

### `auCaptureStop`

`auCaptureStop(in pCapture as Integer) returns nothing`

Stops listening.

- pCapture: A capture, from `auCaptureOpen`.

What has arrived can still be read, and `auCaptureStart` starts again.

### `auCaptureIsRunning`

`auCaptureIsRunning(in pCapture as Integer) returns Boolean`

Reports whether a capture is listening.

- pCapture: A capture, from `auCaptureOpen`.

Returns: True while it is.

### `auCaptureAvailable`

`auCaptureAvailable(in pCapture as Integer) returns Integer`

Returns how much sound is waiting to be read.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The number of bytes `auCaptureRead` would return now.

### `auCaptureRead`

`auCaptureRead(in pCapture as Integer) returns Data`

Returns the sound that has arrived since the last read.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The samples as binary data in the capture's format, or empty when nothing has arrived.

Call it on a timer, more often than the buffer length given to `auCaptureOpen`; sound that arrives while the buffer is full is dropped and counted by `auCaptureDropped`. `auWAVEncode` turns what was read into a sound file, and `auSoundFromPCM` into a sound to play.

```
on readMic
put auCaptureRead(sMic) after sRecording
send "readMic" to me in 100 milliseconds
end readMic
```

### `auCaptureFormat`

`auCaptureFormat(in pCapture as Integer) returns String`

Returns the sample format of a capture.

- pCapture: A capture, from `auCaptureOpen`.

Returns: "u8", "s16", "s24", "s32" or "f32"; empty for a stale handle.

### `auCaptureSampleRate`

`auCaptureSampleRate(in pCapture as Integer) returns Integer`

Returns the sample rate of a capture.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The sample rate in hertz.

### `auCaptureChannels`

`auCaptureChannels(in pCapture as Integer) returns Integer`

Returns the channel count of a capture.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The channel count.

### `auCaptureDeviceLabel`

`auCaptureDeviceLabel(in pCapture as Integer) returns String`

Returns the name of the device a capture listens to.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The device's name, or empty for a stale handle.

### `auCaptureDropped`

`auCaptureDropped(in pCapture as Integer) returns Integer`

Returns how much sound a capture has had to drop.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The number of frames dropped since the capture was opened, because its buffer was full.

### `auCapturePeak`

`auCapturePeak(in pCapture as Integer) returns Number`

Returns the loudest level a capture has heard since the last call, for an input meter.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The level, 0 to 1.

Reading resets it.

### `auCaptureRecordStart`

`auCaptureRecordStart(in pCapture as Integer, in pSavePath as String) returns Boolean`

Starts writing everything a capture hears to a WAV file.

- pCapture: A capture, from `auCaptureOpen`.
- pSavePath: The full path of the WAV file to write.

Returns: True if the file was created; false if not (`auLastError` says why).

The file is written as the sound arrives, in the capture's own format, with no script in between, so nothing is dropped however busy the stack is. It goes on until `auCaptureRecordStop` or `auCaptureClose`. `auCaptureRead` works beside it. An existing file of that name is replaced.

```
put auCaptureOpen(0, "s16", 44100, 1, 1) into sMic
if auCaptureStart(sMic) and auCaptureRecordStart(sMic, tFolder & "/memo.wav") then
-- ... later
put auCaptureRecordStop(sMic) into tSeconds
end if
```

### `auCaptureRecordStop`

`auCaptureRecordStop(in pCapture as Integer) returns Number`

Finishes the WAV file a capture is recording.

- pCapture: A capture, from `auCaptureOpen`.

Returns: The length of the recording in seconds; 0 if nothing was being recorded.

### `auCaptureIsRecording`

`auCaptureIsRecording(in pCapture as Integer) returns Boolean`

Reports whether a capture is writing a WAV file.

- pCapture: A capture, from `auCaptureOpen`.

Returns: True while it is.

## Decoding and encoding

### `auDecodeFile`

`auDecodeFile(in pPath as String, in pFormat as String, in pSampleRate as Integer, in pChannels as Integer) returns Data`

Decodes a whole sound file (WAV, FLAC or MP3) into raw samples.

- pPath: The full path of the file.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".
- pSampleRate: The sample rate to convert to, or 0 to keep the file's own.
- pChannels: The channel count to convert to, or 0 to keep the file's own.

Returns: The samples as binary data, or empty if the file could not be decoded.

For a script that wants the samples themselves: to draw a waveform, analyse a sound or convert a file. `auOutSampleRate` and `auOutChannels` then say what was returned. At most 256 MB of samples. The five sample formats are "u8" (8-bit unsigned), "s16", "s24" and "s32" (signed, little-endian) and "f32" (32-bit floating point, -1 to 1). Samples of several channels are interleaved (left, right, left, right).

```
put auDecodeFile(tPath, "s16", 0, 1) into tSamples
put auOutSampleRate() into tRate
put the number of bytes in tSamples / 2 / tRate into tSeconds
```

### `auDecodeData`

`auDecodeData(in pData as Data, in pFormat as String, in pSampleRate as Integer, in pChannels as Integer) returns Data`

Decodes the bytes of a sound file (WAV, FLAC or MP3) into raw samples.

- pData: The whole contents of a sound file, as binary data.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".
- pSampleRate: The sample rate to convert to, or 0 to keep the file's own.
- pChannels: The channel count to convert to, or 0 to keep the file's own.

Returns: The samples as binary data, or empty if the data could not be decoded.

The same as `auDecodeFile`, for a sound file held in a variable or a custom property.

### `auWAVEncode`

`auWAVEncode(in pData as Data, in pFormat as String, in pSampleRate as Integer, in pChannels as Integer) returns Data`

Wraps raw samples as a WAV file.

- pData: The samples, as binary data.
- pFormat: The sample format: "u8", "s16", "s24", "s32" or "f32".
- pSampleRate: The sample rate of the samples in hertz, 8000 to 192000.
- pChannels: How many channels the samples have, 1 to 8.

Returns: The contents of a WAV file as binary data, or empty if refused.

What a script writes to disk to save a recording or a rendered mix.

```
put auWAVEncode(sRecording, "s16", 16000, 1) into url ("binfile:" & tPath)
```

## Shutting down

### `auShutDown`

`auShutDown() returns nothing`

Closes every capture and engine and lets the audio system go.

Every sound and group is freed with its engine, and every handle becomes stale. Safe to call twice. The library works again afterwards; the next call that needs a device opens the audio system afresh.

```
on closeStack
auShutDown
end closeStack
```
