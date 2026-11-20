# Getting started with box3dxt

box3dxt gives a stack a 3D physics world: you describe bodies and shapes, step the world a
slice of time, and read back where everything is. This page is what to know before the
[API reference](api-reference.md).

## The conventions

- **Metres, kilograms, seconds, radians.** y is up when gravity is `0, -10, 0`. Box3D is tuned
  for things between about 10 cm and 10 m: a 0.5 m ball, not a 500-pixel one. Scale when you
  draw, not when you simulate.
- **Handles are integers.** A world, body, shape or joint is a number; 0 is "none". A handle
  to something destroyed is refused by every call, harmlessly: getters answer 0 or empty,
  actions do nothing. Destroying a world destroys everything in it.
- **Several numbers come back as text.** `b3BodyPosition` returns `"x,y,z"`, a rotation is a
  quaternion `"x,y,z,w"`, a transform is seven items. The decimal point is `.` in every
  locale. `b3BodyX`, `b3BodyY` and `b3BodyZ` exist for when one number is all you want.
- **Every parameter is typed.** A number parameter must be given a number: empty is an
  engine error at the call, before box3dxt sees it. Pass 0, not empty.
- **Nothing throws.** A call with a bad argument does nothing, returns 0 or empty, and
  `b3LastError()` says why. The one exception is a native library from a different release
  than the binding: the first call throws and names the ABI it needs.

## A frame loop

```livecodescript
local sWorld

on physicsStart
   put b3WorldCreate(0, -10, 0, 1) into sWorld
   -- ... create bodies and shapes ...
   send "physicsFrame" to me in 16 milliseconds
end physicsStart

on physicsFrame
   local tCount, tIndex
   b3WorldStep sWorld, 1/60, 4
   put b3WorldUpdateMoves(sWorld) into tCount       -- the bodies that moved this step
   repeat with tIndex = 1 to tCount
      drawBody b3MoveBody(tIndex), b3MoveTransform(tIndex)
   end repeat
   send "physicsFrame" to me in 16 milliseconds
end physicsFrame

on closeStack
   b3WorldDestroy sWorld
end closeStack
```

Step with a FIXED slice (1/60 s and 4 sub-steps suits most scenes), not with the time since
the last frame: a physics step is stable when its size does not change. A step of 0 seconds or
of more than 1 is ignored.

## Bodies and shapes

A body has a type: 0 static (never moves), 1 kinematic (moves as you tell it, pushed by
nothing), 2 dynamic (moved by forces). A body does nothing until it has a shape, and a
dynamic body's mass comes from its shapes' density.

```livecodescript
put b3BodyCreate(sWorld, 2, 0, 4, 0) into tCrate
get b3ShapeAddBox(tCrate, 0.5, 0.5, 0.5, 1, 0.6, 0)     -- half-sizes, density, friction, bounce
```

Hulls, meshes and height fields are built from points you add first:

```livecodescript
b3GeometryBegin
get b3GeometryAddPoint(0, 0, 0)       -- returns the number of the point
get b3GeometryAddPoint(1, 0, 0)
get b3GeometryAddPoint(0, 1, 0)
get b3GeometryAddPoint(0, 0, 1)
get b3ShapeAddHull(tBody, 1, 0.6, 0)
```

A mesh or a height field goes on a static body only.

## Five rules that decide whether a scene works

1. **Events are off until you ask.** A shape reports nothing by default. Call
   `b3ShapeOptionsSetEvents true, true, true` (contact, hit, sensor) BEFORE adding the shapes
   that should report, or switch a shape on afterwards with `b3ShapeEnableContactEvents` and
   its two siblings. A sensor sees a visitor only when both have sensor events on.
2. **Events are read by polling.** After a step, `b3WorldUpdateContactEvents(sWorld)` copies
   that step's events; then read them by index (`b3ContactBeginCount()`,
   `b3ContactBeginShapeA(1)`, ...). The next update replaces them.
3. **A dynamic body needs mass.** A dynamic body with no shape, or with density 0, has no
   mass; joined to others it can make the solver produce numbers that are not numbers. See
   "The net" below.
4. **A shape's category starts as every bit.** `b3QuerySetFilter` and `b3ShapeSetFilter` only
   separate things once you have given shapes categories of their own.
5. **A body cannot be put to sleep in the frame something was enabled.** After
   `b3BodyEnable` or `b3BodySetType` on any body of a world, `b3BodySetAwake tBody, false`
   in that world is refused until the world has been stepped once (`b3LastError()` says so).
   Waking is always allowed.

## The limits every call is held to

Box3D works in single precision and, in a release build, trusts its caller. The shim does
not: an argument outside these limits is refused before Box3D sees it.

| What | Limit |
|---|---|
| Any number | finite, within 1,000,000,000 either side of 0 |
| A size (radius, half-size, height, length) | 0.001 to 10,000 |
| A point inside a body (shape offset, joint anchor, hull point) | within 10,000 of the body |
| Density | 0 to 1,000,000 |
| A spring's frequency (hertz) | 0 to 10,000 |
| A damping ratio | 0 to 1,000 |
| A step | above 0 and at most 1 second (sub-steps are held to 1 to 64) |
| A cone | both radii above 0; 4 to 32 sides (a cylinder: 3 to 32) |
| A revolute target angle | -pi to pi |
| A spherical cone limit | 0 to pi/2 |
| Worlds at once | 128 |
| A dynamic body's mass | what its shapes weigh, at most 10,000,000,000 kg |

A shape that would make a dynamic body heavier than the last row is refused, and a static
body that heavy cannot be made dynamic.

## The net

A simulation can still go wrong inside a step: a chain of massless bodies, a joint asked for
the impossible. Box3D then produces a position or a velocity that is not a number, and a body
in that state corrupts the world for every other body. After every step the shim looks at
each body that moved; one whose position is not a number, or whose velocity has run away past
the limit above, is destroyed with its shapes and joints. `b3UnstableCount()` counts them
since the library loaded and `b3LastError()` says it happened. Its handle is dead like any
destroyed body's. If your count rises, a body in the scene has no mass or a joint is fighting
another.

`b3AssertCount()` and `b3AssertText()` report Box3D's own internal checks when the library was
built with them (a debug build); in a release build they stay at 0.

## Performance notes

- `b3WorldCreate`'s last argument is the number of worker threads Box3D may use for a step
  (1 is right for small scenes; the web build always uses 1). The threads never call script.
- `b3WorldUpdateMoves` plus `b3MoveTransform` reads every moved body in one pass;
  `b3MovesText()` returns them all as one text, one line a body, for a single parse.
- Bodies at rest fall asleep and cost nothing; `b3WorldAwakeBodyCount` shows how many are not.
