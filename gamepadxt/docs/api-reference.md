# gamepadxt API reference

The 54 public handlers, from the doc blocks in `src/gamepadxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the poll loop, the button
names and what each platform can and cannot do.

## The library

### `gpABIVersion`

`gpABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: An integer. This binding needs 1.

The binding checks this number itself before `gpStart` does anything, and throws if the library beside the engine is from another version. Call it to see which library was found.

```
put gpABIVersion()
```

### `gpLibraryVersion`

`gpLibraryVersion() returns String`

Returns the name and version of the library underneath.

Returns: Text such as "SDL 3.4.20".

gamepadxt reads controllers through SDL (Simple DirectMedia Layer), built into the library. Calling this is also the quickest way to see that the extension and its native library are installed.

```
put gpLibraryVersion()
```

### `gpLastError`

`gpLastError() returns String`

Says why the last call was refused.

Returns: A sentence, or empty if the last call was not refused.

Nothing in this library throws (bar the version check): a call that cannot be carried out returns false, 0 or empty and leaves its reason here. The next call replaces it.

```
if not gpStart() then answer gpLastError()
```

### `gpAssertCount`

`gpAssertCount() returns Integer`

Returns how many internal checks of the underlying library have failed.

Returns: An integer, 0 in every released build.

A diagnostic for the library's own tests, which run a build with those checks compiled in. A released library has none, so this is 0.

```
put gpAssertCount()
```

## Starting and stopping

### `gpStart`

`gpStart() returns Boolean`

Starts reading game controllers.

Returns: True if controllers can now be read, false if the system refused (`gpLastError` says why).

Call this once before anything else, then call `gpPoll` from a timer. Every controller already plugged in is opened at once; on Windows and macOS some are found a moment later and appear at a later `gpPoll`.

```
on openCard
if gpStart() then send "readPads" to me in 16 milliseconds
end openCard
```

### `gpStop`

`gpStop() returns nothing`

Stops reading game controllers.

Gives back one `gpStart`. At the last one every pad is closed, every pad handle stops working and waiting events are thrown away. Call it when the stack closes: the engine does not do it for you. A stop with nothing started does nothing.

```
on closeCard
gpStop
end closeCard
```

### `gpIsStarted`

`gpIsStarted() returns Boolean`

Tells whether controllers are being read.

Returns: True between a `gpStart` and its `gpStop`.

```
if not gpIsStarted() then get gpStart()
```

## Polling and events

### `gpPoll`

`gpPoll() returns Integer`

Reads every controller once.

Returns: The number of events waiting for `gpEvents`.

Nothing changes between two polls: this call is what notices a controller being plugged in or pulled out, and what updates the buttons and sticks the other handlers report. Call it from a timer, every 16 to 33 milliseconds for a game. It never waits.

```
on readPads
get gpPoll()
repeat for each line tEvent in gpEvents()
if item 1 of tEvent is "button" and item 4 of tEvent is "down" then
buttonPressed item 2 of tEvent, item 3 of tEvent
end if
end repeat
send "readPads" to me in 16 milliseconds
end readPads
```

### `gpEventCount`

`gpEventCount() returns Integer`

Returns the number of events waiting.

Returns: An integer, as of the last `gpPoll`.

```
if gpEventCount() > 0 then handleEvents gpEvents()
```

### `gpEvents`

`gpEvents() returns String`

Returns every waiting event and empties the queue.

Returns: One event a line, oldest first; empty if none are waiting. Each line is comma-separated: "connected,pad", "disconnected,pad", "button,pad,name,down", "button,pad,name,up", and, once `gpSetAxisEvents` has turned them on, "axis,pad,name,value".

Events are for things that happen once: a button going down, a pad arriving. A quick tap between two polls is still two events, so nothing is missed. For things that are held (a stick, a trigger, a button kept down) read the state instead, with `gpPadAxes`, `gpPadStick` or `gpPadButton`.

```
repeat for each line tEvent in gpEvents()
if item 1 of tEvent is "connected" then put item 2 of tEvent into sPad
end repeat
```

### `gpDroppedEvents`

`gpDroppedEvents() returns Integer`

Returns how many events were thrown away unread.

Returns: An integer, counted since the library was loaded.

At most 4096 events wait for `gpEvents`. A stack that polls and never reads them loses the oldest, and this counts each one. A stack that reads its events after every poll always sees 0.

```
put gpDroppedEvents()
```

### `gpSetAxisEvents`

`gpSetAxisEvents(in pStep as Number) returns nothing`

Turns events for sticks and triggers on or off.

- pStep: 0 for no axis events (how it starts), or 0.01 to 1: how far an axis must move, as a part of its full travel, before it is reported again.

Stick and trigger events are off to begin with, because a stick in motion would queue an event at every poll and most stacks read sticks with `gpPadStick` instead. With a step set, an axis is reported in `gpEvents` when it has moved at least that far since its last report, and always when it comes to rest at 0 or at an end. A value out of range is refused.

```
gpSetAxisEvents 0.1
```

### `gpAxisEvents`

`gpAxisEvents() returns Number`

Returns the step set by `gpSetAxisEvents`.

Returns: A number, 0 if axis events are off.

```
put gpAxisEvents()
```

## Pads

### `gpPadCount`

`gpPadCount() returns Integer`

Returns the number of pads connected.

Returns: An integer, as of the last `gpPoll`.

```
if gpPadCount() is 0 then put "Plug in a controller" into field "status"
```

### `gpPadAt`

`gpPadAt(in pIndex as Integer) returns Integer`

Returns the handle of one connected pad, by position.

- pIndex: Which pad, from 1 to `gpPadCount`.

Returns: A pad handle, or 0 if there is no pad at that position.

A pad handle is a number that names one connected controller. It stops working when that controller is unplugged, and the same controller plugged in again gets a new one, so a stack that cares who is who should follow the "connected" and "disconnected" events of `gpEvents`.

```
put gpPadAt(1) into sPad
```

### `gpPads`

`gpPads() returns String`

Returns the handles of every connected pad.

Returns: Pad handles, comma-separated; empty if no pad is connected.

```
repeat for each item tPad in gpPads()
put gpPadName(tPad) & return after tNames
end repeat
```

### `gpPadIsConnected`

`gpPadIsConnected(in pPad as Integer) returns Boolean`

Tells whether a pad handle still names a connected pad.

- pPad: A pad handle.

Returns: True while the pad is plugged in.

```
if not gpPadIsConnected(sPad) then put gpPadAt(1) into sPad
```

### `gpPadName`

`gpPadName(in pPad as Integer) returns String`

Returns a pad's name.

- pPad: A pad handle.

Returns: Text such as "Xbox Series X Controller"; empty for a handle that no longer works.

```
put gpPadName(sPad) into field "controller"
```

### `gpPadType`

`gpPadType(in pPad as Integer) returns String`

Returns what kind of pad this is.

- pPad: A pad handle.

Returns: One of unknown, standard, xbox360, xboxone, ps3, ps4, ps5, switchpro, joyconleft, joyconright, joyconpair, gamecube or steam; empty for a handle that no longer works.

Use it to choose which button pictures to show. For the letter or symbol printed on one button, `gpPadButtonLabel` is more direct.

```
if gpPadType(sPad) begins with "ps" then showPlayStationPrompts
```

### `gpPadVendor`

`gpPadVendor(in pPad as Integer) returns Integer`

Returns the USB vendor number of a pad.

- pPad: A pad handle.

Returns: An integer, 0 if the system does not report one.

```
put gpPadVendor(sPad)
```

### `gpPadProduct`

`gpPadProduct(in pPad as Integer) returns Integer`

Returns the USB product number of a pad.

- pPad: A pad handle.

Returns: An integer, 0 if the system does not report one.

```
put gpPadProduct(sPad)
```

### `gpPadGUID`

`gpPadGUID(in pPad as Integer) returns String`

Returns the identifier the mapping database knows a pad's model by.

- pPad: A pad handle.

Returns: 32 hexadecimal digits; empty for a handle that no longer works.

It is the first field of a mapping line (see `gpAddMapping`). Two pads of the same model have the same one.

```
put gpPadGUID(sPad)
```

### `gpPadPlayer`

`gpPadPlayer(in pPad as Integer) returns Integer`

Returns the player number a pad shows on its lights.

- pPad: A pad handle.

Returns: An integer, 0 for the first player, or -1 if the pad has none.

```
put gpPadPlayer(sPad) + 1 into field "player"
```

### `gpPadSetPlayer`

`gpPadSetPlayer(in pPad as Integer, in pPlayer as Integer) returns Boolean`

Sets the player number a pad shows on its lights.

- pPad: A pad handle.
- pPlayer: The player number, 0 to 15 (0 is the first player), or -1 for none.

Returns: True if the pad took it.

```
get gpPadSetPlayer(sPad, 0)
```

### `gpPadIsVirtual`

`gpPadIsVirtual(in pPad as Integer) returns Boolean`

Tells whether a pad was made by `gpVirtualAttach`.

- pPad: A pad handle.

Returns: True for a virtual pad, false for a real one or a handle that no longer works.

```
if gpPadIsVirtual(sPad) then put "on-screen controls" into field "input"
```

### `gpPadBattery`

`gpPadBattery(in pPad as Integer) returns Integer`

Returns how full a pad's battery is.

- pPad: A pad handle.

Returns: A percentage, 0 to 100, or -1 if the pad does not report one.

```
if gpPadBattery(sPad) is not -1 and gpPadBattery(sPad) < 15 then warnLowBattery
```

### `gpPadPower`

`gpPadPower(in pPad as Integer) returns String`

Returns how a pad is powered.

- pPad: A pad handle.

Returns: One of unknown, onbattery, nobattery (it is wired), charging, charged or error; empty for a handle that no longer works.

```
put gpPadPower(sPad)
```

### `gpPadMapping`

`gpPadMapping(in pPad as Integer) returns String`

Returns the mapping line in use for a pad.

- pPad: A pad handle.

Returns: A line in the format `gpAddMapping` takes; empty if the pad has none or the handle no longer works.

```
put gpPadMapping(sPad) into field "mapping"
```

## Buttons, sticks and triggers

### `gpButtonNames`

`gpButtonNames() returns String`

Lists the button names this library uses.

Returns: south, east, west, north, back, guide, start, leftstick, rightstick, leftshoulder, rightshoulder, dpup, dpdown, dpleft, dpright, misc1, rightpaddle1, leftpaddle1, rightpaddle2, leftpaddle2, touchpad and misc2 to misc6, comma-separated.

The four face buttons are named by where they are, not by what is printed on them: south is the bottom one (A on an Xbox pad, Cross on a PlayStation pad, B on a Nintendo pad). So a game that jumps on "south" feels the same on every controller. Where a button name is asked for, the Xbox letters a, b, x and y are also accepted, as the places they have on an Xbox pad. leftstick and rightstick are the clicks of the sticks.

```
repeat for each item tButton in gpButtonNames()
if gpPadHasButton(sPad, tButton) then put tButton & return after tList
end repeat
```

### `gpAxisNames`

`gpAxisNames() returns String`

Lists the axis names this library uses.

Returns: leftx, lefty, rightx, righty, lefttrigger and righttrigger, comma-separated.

```
put gpAxisNames()
```

### `gpPadButton`

`gpPadButton(in pPad as Integer, in pButton as String) returns Boolean`

Tells whether a button is held down.

- pPad: A pad handle.
- pButton: A button name, such as "south" (see `gpButtonNames`).

Returns: True while the button is down, as of the last `gpPoll`. False for a name that is not a button or a handle that no longer works.

This reads what is held now. To act once when a button goes down, use the "button" events of `gpEvents`.

```
if gpPadButton(sPad, "south") then jump
```

### `gpPadHasButton`

`gpPadHasButton(in pPad as Integer, in pButton as String) returns Boolean`

Tells whether a pad has a certain button.

- pPad: A pad handle.
- pButton: A button name (see `gpButtonNames`).

Returns: True if the pad has it.

```
if not gpPadHasButton(sPad, "guide") then hide button "Home"
```

### `gpPadButtons`

`gpPadButtons(in pPad as Integer) returns String`

Returns every button that is held down.

- pPad: A pad handle.

Returns: Button names, comma-separated; empty if none is held.

```
if "start" is among the items of gpPadButtons(sPad) then pauseGame
```

### `gpPadButtonLabel`

`gpPadButtonLabel(in pPad as Integer, in pButton as String) returns String`

Returns what is printed on one of a pad's face buttons.

- pPad: A pad handle.
- pButton: A button name (see `gpButtonNames`).

Returns: One of a, b, x, y, cross, circle, square or triangle; empty for a button that is not one of the four face buttons.

```
put "Press " & gpPadButtonLabel(sPad, "south") & " to jump" into field "hint"
```

### `gpPadAxis`

`gpPadAxis(in pPad as Integer, in pAxis as String) returns Number`

Returns one axis of a stick, or a trigger.

- pPad: A pad handle.
- pAxis: An axis name (see `gpAxisNames`).

Returns: A stick axis from -1 to 1 (left and up are negative), a trigger from 0 to 1. 0 for a name that is not an axis or a handle that no longer works.

The value is as the pad reports it. A stick at rest rarely reads exactly 0, so for sticks prefer `gpPadStick`, which removes that.

```
put gpPadAxis(sPad, "righttrigger") into tThrottle
```

### `gpPadHasAxis`

`gpPadHasAxis(in pPad as Integer, in pAxis as String) returns Boolean`

Tells whether a pad has a certain axis.

- pPad: A pad handle.
- pAxis: An axis name (see `gpAxisNames`).

Returns: True if the pad has it.

```
if gpPadHasAxis(sPad, "rightx") then enableCameraStick
```

### `gpPadAxes`

`gpPadAxes(in pPad as Integer) returns String`

Returns all six axes of a pad in one call.

- pPad: A pad handle.

Returns: leftx, lefty, rightx, righty, lefttrigger and righttrigger, comma-separated, each as `gpPadAxis` gives it; empty for a handle that no longer works.

```
put gpPadAxes(sPad) into tAxes
put item 5 of tAxes into tBrake
```

### `gpPadStick`

`gpPadStick(in pPad as Integer, in pSide as String) returns String`

Returns where a stick is, ready to use for movement.

- pPad: A pad handle.
- pSide: "left" or "right".

Returns: "x,y", each from -1 to 1 (left and up are negative); empty for a handle that no longer works.

A stick at rest does not read exactly 0, so a small region around the centre, the dead zone, is treated as 0 (see `gpSetDeadZone`). Outside it the reading is rescaled, so movement still starts gently at the edge of the zone and reaches 1 at full tilt, in every direction.

```
put gpPadStick(sPad, "left") into tStick
add item 1 of tStick * 6 to sPlayerX
add item 2 of tStick * 6 to sPlayerY
```

### `gpSetDeadZone`

`gpSetDeadZone(in pZone as Number) returns nothing`

Sets the dead zone `gpPadStick` removes.

- pZone: How much of a stick's travel around its centre reads as 0, from 0 to 0.9. It starts at 0.15.

Raise it if a character drifts with the stick untouched (an old or worn pad); lower it for finer control. It applies to every pad. A value out of range is refused.

```
gpSetDeadZone 0.2
```

### `gpDeadZone`

`gpDeadZone() returns Number`

Returns the dead zone set by `gpSetDeadZone`.

Returns: A number from 0 to 0.9.

```
put gpDeadZone()
```

## Rumble and lights

### `gpPadHasRumble`

`gpPadHasRumble(in pPad as Integer) returns Boolean`

Tells whether a pad can rumble.

- pPad: A pad handle.

Returns: True if it can.

```
if gpPadHasRumble(sPad) then get gpPadRumble(sPad, 0.5, 0.5, 200)
```

### `gpPadRumble`

`gpPadRumble(in pPad as Integer, in pLow as Number, in pHigh as Number, in pMilliseconds as Integer) returns Boolean`

Makes a pad rumble.

- pPad: A pad handle.
- pLow: The strength of the heavy, slow motor, 0 to 1.
- pHigh: The strength of the light, fast motor, 0 to 1.
- pMilliseconds: How long to rumble, 0 to 60000.

Returns: True if the pad took it; false if it cannot rumble or a value was out of range.

A new call replaces the one before it, and strengths of 0 stop the rumble. The rumble ends by itself after the time given, as long as `gpPoll` keeps being called.

```
get gpPadRumble(sPad, 1, 0.3, 250)
```

### `gpPadHasTriggerRumble`

`gpPadHasTriggerRumble(in pPad as Integer) returns Boolean`

Tells whether a pad has motors in its triggers.

- pPad: A pad handle.

Returns: True if it has (Xbox One and later pads).

```
if gpPadHasTriggerRumble(sPad) then get gpPadRumbleTriggers(sPad, 0, 1, 100)
```

### `gpPadRumbleTriggers`

`gpPadRumbleTriggers(in pPad as Integer, in pLeft as Number, in pRight as Number, in pMilliseconds as Integer) returns Boolean`

Makes a pad's triggers rumble.

- pPad: A pad handle.
- pLeft: The strength of the left trigger's motor, 0 to 1.
- pRight: The strength of the right trigger's motor, 0 to 1.
- pMilliseconds: How long to rumble, 0 to 60000.

Returns: True if the pad took it; false if it has no trigger motors or a value was out of range.

```
get gpPadRumbleTriggers(sPad, 0, 0.8, 120)
```

### `gpPadHasLED`

`gpPadHasLED(in pPad as Integer) returns Boolean`

Tells whether a pad has a light whose colour can be set.

- pPad: A pad handle.

Returns: True if it has (PlayStation 4 and 5 pads).

```
if gpPadHasLED(sPad) then get gpPadSetLED(sPad, 0, 128, 255)
```

### `gpPadSetLED`

`gpPadSetLED(in pPad as Integer, in pRed as Integer, in pGreen as Integer, in pBlue as Integer) returns Boolean`

Sets the colour of a pad's light.

- pPad: A pad handle.
- pRed: Red, 0 to 255.
- pGreen: Green, 0 to 255.
- pBlue: Blue, 0 to 255.

Returns: True if the pad took it; false if it has no such light or a value was out of range.

```
get gpPadSetLED(sPad, 255, 0, 0)
```

## Mappings

### `gpAddMapping`

`gpAddMapping(in pMapping as String) returns Integer`

Teaches the library a pad it does not know, or corrects one.

- pMapping: One mapping line, at most 8192 bytes.

Returns: 1 if the mapping was added, 0 if it replaced an existing one, -1 if it was refused (`gpLastError` says why).

A mapping says which of a device's raw buttons is "south", which axis is "leftx", and so on. Several thousand come built in. The line is in the format of the community's SDL_GameControllerDB (its gamecontrollerdb.txt): an identifier (see `gpPadGUID`), a name, then pairs such as a:b0. Add mappings after `gpStart`.

```
get gpAddMapping(field "mapping")
```

### `gpAddMappingsFromFile`

`gpAddMappingsFromFile(in pPath as String) returns Integer`

Loads a whole file of mappings.

- pPath: The path of a text file of mapping lines, such as a downloaded gamecontrollerdb.txt.

Returns: The number of mappings added, or -1 if the file could not be read (`gpLastError` says why).

Only lines that name this operating system in a "platform:" field are taken (as every line of gamecontrollerdb.txt does); a line for another system, or one that names none, is skipped. See `gpAddMapping` for what a mapping is.

```
get gpAddMappingsFromFile(specialFolderPath("resources") & "/gamecontrollerdb.txt")
```

## Virtual pads

### `gpVirtualAttach`

`gpVirtualAttach(in pName as String) returns Integer`

Makes a pad that exists only in software.

- pName: A name for the pad, at most 64 bytes; empty for "Virtual Gamepad".

Returns: The handle of the new pad, or 0 if it could not be made.

A virtual pad has every button and all six axes, and is a pad in every other way: it is in `gpPads`, it sends events and it answers every handler. Drive it with `gpVirtualSetButton` and `gpVirtualSetAxis`. Use one to give a game on-screen controls without a second code path, to replay recorded input, or to test a game with no controller in the room.

```
put gpVirtualAttach("Touch controls") into sTouchPad
```

### `gpVirtualDetach`

`gpVirtualDetach(in pPad as Integer) returns nothing`

Removes a virtual pad.

- pPad: The handle of a virtual pad.

Its "disconnected" event is queued and its handle stops working. A real pad is left alone.

```
gpVirtualDetach sTouchPad
```

### `gpVirtualSetButton`

`gpVirtualSetButton(in pPad as Integer, in pButton as String, in pDown as Boolean) returns Boolean`

Presses or releases a button of a virtual pad.

- pPad: The handle of a virtual pad.
- pButton: A button name (see `gpButtonNames`).
- pDown: True to press the button, false to release it.

Returns: True if the pad took it.

Like a real press, it shows at the next `gpPoll`.

```
on mouseDown
get gpVirtualSetButton(sTouchPad, "south", true)
end mouseDown
```

### `gpVirtualSetAxis`

`gpVirtualSetAxis(in pPad as Integer, in pAxis as String, in pValue as Number) returns Boolean`

Moves a stick or a trigger of a virtual pad.

- pPad: The handle of a virtual pad.
- pAxis: An axis name (see `gpAxisNames`).
- pValue: A stick axis from -1 to 1, a trigger from 0 to 1.

Returns: True if the pad took it; false if the value was out of range.

Like a real movement, it shows at the next `gpPoll`.

```
get gpVirtualSetAxis(sTouchPad, "leftx", -1)
```

### `gpVirtualRumble`

`gpVirtualRumble(in pPad as Integer) returns String`

Returns what a virtual pad was last told to rumble at.

- pPad: The handle of a virtual pad.

Returns: "low,high,left,right", each 0 to 1: the two motors of `gpPadRumble`, then the two triggers of `gpPadRumbleTriggers`. Empty for a pad that is not virtual.

A virtual pad has no motors, so this is how a stack sees the rumble a game asked for: to shake the screen instead, or to test it.

```
if item 1 of gpVirtualRumble(sTouchPad) > 0 then shakeScreen
```

### `gpVirtualLED`

`gpVirtualLED(in pPad as Integer) returns String`

Returns the colour a virtual pad's light was last set to.

- pPad: The handle of a virtual pad.

Returns: "red,green,blue", each 0 to 255. Empty for a pad that is not virtual.

```
put gpVirtualLED(sTouchPad)
```
