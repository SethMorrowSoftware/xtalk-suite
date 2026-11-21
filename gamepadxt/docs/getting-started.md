# Getting started with gamepadxt

gamepadxt lets a stack read game controllers: which buttons are held, where the sticks are,
and what was pressed since you last asked. This page is what to know before the
[API reference](api-reference.md).

## The conventions

- **Start, poll, stop.** `gpStart()` once, `gpPoll()` from a timer, `gpStop` when the stack
  closes. Nothing changes between two polls, and no handler of yours is ever called by the
  library: you ask, it answers.
- **A pad is an integer.** Each connected controller has a handle; 0 is "none". When a
  controller is unplugged its handle stops working, and using it is harmless: getters answer
  0, false or empty, actions do nothing. Plugged back in, it gets a NEW handle.
- **Buttons and axes are named by text**, and buttons by where they are, not what is
  printed on them (the table below). Names are not case-sensitive.
- **Several values come back as text.** `gpPadStick` returns `"x,y"`, `gpPadAxes` six items,
  `gpPads` a list of handles, `gpEvents` one event a line. The decimal point is `.` in every
  locale.
- **Every parameter is typed.** A number parameter must be given a number: empty is an
  engine error at the call, before gamepadxt sees it. Pass 0, not empty.
- **Nothing throws.** A call with a bad argument does nothing, returns 0, false or empty,
  and `gpLastError()` says why. The one exception is a native library from a different
  release than the binding: the first call throws and names the ABI it needs.

## A frame loop

```livecodescript
local sPad

on openCard
   if not gpStart() then
      answer "No controller support here:" && gpLastError()
      exit openCard
   end if
   send "padFrame" to me in 16 milliseconds
end openCard

on padFrame
   local tEvent, tStick
   get gpPoll()
   repeat for each line tEvent in gpEvents()
      switch item 1 of tEvent
         case "connected"
            if sPad is 0 or sPad is empty then put item 2 of tEvent into sPad
            break
         case "disconnected"
            if item 2 of tEvent is sPad then put gpPadAt(1) into sPad     -- 0 if none is left
            break
         case "button"
            if item 4 of tEvent is "down" then padPressed item 2 of tEvent, item 3 of tEvent
            break
      end switch
   end repeat
   put gpPadStick(sPad, "left") into tStick          -- empty while no pad is connected
   if tStick is not empty then movePlayer item 1 of tStick, item 2 of tStick
   send "padFrame" to me in 16 milliseconds
end padFrame

on closeCard
   gpStop
end closeCard
```

Poll every 16 to 33 milliseconds for a game. A slower poll loses nothing (events wait, up to
4096 of them; `gpDroppedEvents()` counts any that were pushed out), it only reacts later.

## The buttons

| Name | Where it is | Xbox | PlayStation | Switch |
|---|---|---|---|---|
| `south` | bottom face button | A | Cross | B |
| `east` | right face button | B | Circle | A |
| `west` | left face button | X | Square | Y |
| `north` | top face button | Y | Triangle | X |
| `back` | left of centre | View / Back | Share / Create | Minus |
| `guide` | centre | Xbox | PS | Home |
| `start` | right of centre | Menu / Start | Options | Plus |
| `leftstick`, `rightstick` | pressing a stick in | LS, RS | L3, R3 | |
| `leftshoulder`, `rightshoulder` | the bumpers | LB, RB | L1, R1 | L, R |
| `dpup`, `dpdown`, `dpleft`, `dpright` | the direction pad | | | |
| `touchpad` | pressing the touchpad | | touchpad | |
| `misc1` | an extra button | Share | microphone | Capture |
| `rightpaddle1`, `leftpaddle1`, `rightpaddle2`, `leftpaddle2` | back paddles | Elite paddles | | |
| `misc2` to `misc6` | further extras | | | |

`gpPadButton(tPad, "south")` is true while it is held. `a`, `b`, `x` and `y` are accepted as
other spellings of `south`, `east`, `west` and `north` (their Xbox positions), but nothing
the library returns uses them. To show a prompt, `gpPadButtonLabel(tPad, "south")` gives the
letter or symbol printed on THIS pad (`a`, `cross`, `b`, ...), and `gpPadHasButton` says
whether the pad has the button at all.

The triggers are axes, not buttons: `lefttrigger` and `righttrigger`.

## The axes

| Name | Range |
|---|---|
| `leftx`, `rightx` | -1 (left) to 1 (right) |
| `lefty`, `righty` | -1 (up) to 1 (down) |
| `lefttrigger`, `righttrigger` | 0 (released) to 1 (fully pulled) |

`gpPadAxis` gives one raw value and `gpPadAxes` all six, in the order above. A stick at rest
never reads exactly 0, so for movement use `gpPadStick(tPad, "left")`: it returns `"x,y"`
with a round dead zone taken out and the rest rescaled, so movement starts gently at the
zone's edge and reaches 1 at full tilt. `gpSetDeadZone` changes the zone (0 to 0.9; it
starts at 0.15).

## Events

`gpEvents()` returns what happened since it was last called, oldest first, and empties the
list:

```
connected,<pad>
disconnected,<pad>
button,<pad>,<name>,down
button,<pad>,<name>,up
axis,<pad>,<name>,<value>
```

Axis events are OFF to begin with, because a stick sends hundreds of tiny changes a second.
`gpSetAxisEvents 0.1` turns them on: an axis then reports each time it has moved 0.1 from the
value it last reported, and always when it comes to rest at the centre or an end.
`gpSetAxisEvents 0` turns them off again. Most games read the sticks with `gpPadStick` every
frame and use events for buttons only.

Use events for things that happen once (jump, pause, a menu step) and state for things that
are held (run, aim): an event is never missed between two frames, a state read can be.

## Rumble and lights

```livecodescript
if gpPadHasRumble(sPad) then get gpPadRumble(sPad, 0.8, 0.3, 200)   -- heavy, light, milliseconds
if gpPadHasLED(sPad) then get gpPadSetLED(sPad, 0, 120, 255)        -- red, green, blue, 0 to 255
```

A rumble ends by itself after its time, as long as `gpPoll` keeps being called. Strengths of
0 stop it early.

## Virtual pads

`gpVirtualAttach("Touch controls")` makes a pad that exists only in software. It is in
`gpPads()`, sends events and answers every handler; you drive it with `gpVirtualSetButton`
and `gpVirtualSetAxis`. Three uses:

- **On-screen controls.** Buttons on a card set the virtual pad, and the game reads pads the
  one way it already does.
- **Testing** a game with no controller attached.
- **Replaying** recorded input.

`gpVirtualRumble` and `gpVirtualLED` read back what the game asked the pad to do, so
on-screen controls can shake or light up too.

## A pad SDL does not know

Almost every pad is recognised. One that is not shows up with the wrong buttons, or not at
all. The community file `gamecontrollerdb.txt` knows many more:

```livecodescript
get gpAddMappingsFromFile(specialFolderPath("resources") & "/gamecontrollerdb.txt")
```

Only the lines for the system the stack is running on are taken. `gpAddMapping` adds one
line of the same format, and `gpPadMapping(tPad)` shows the line a pad is using.

## What differs between platforms

- **Windows, macOS, Linux.** Controllers are read whether or not the stack's window is in
  front. On Linux the user must be allowed to read the device, which desktop distributions
  set up for known pads; an unusual pad may need a udev rule.
- **The web.** A browser shows a controller to a page only after a button on it has been
  pressed, so "press any button" is the way to begin. Rumble and lights depend on the
  browser.
- **The guide button** (Xbox, PS, Home) is often taken by the system, and its `up` event
  arrives a quarter of a second after its `down`, however briefly it was pressed.
  `gpPadButton` reads the true state at once.
- **Android and iOS** are not supported.

## What has been checked

Everything on this page has run in the member's tests against virtual pads, natively and on
OXT-Beyond's headless Linux engine. Part of it has run on Windows and in a browser, again
on virtual pads, on 2026-11-21: in the IDE on Windows, `gpStart`, a pad's buttons and their
events (the demo's first showcase); in Chromium, Firefox and WebKit, a pad attached, a
button and a stick read, rumble and the light. Reading a real controller, the rest on
Windows and the web, and everything on macOS, is verified statically; needs an OXT pass.
