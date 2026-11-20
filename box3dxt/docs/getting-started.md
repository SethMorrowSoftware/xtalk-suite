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
- **Nothing throws.** A call the library refuses does nothing and returns 0 or empty. A
  CREATE that is refused (a world, body, shape or joint: a size out of range, a body too
  heavy, a dead handle to build on) leaves the reason in `b3LastError()`, and a create that
  succeeds clears it. A getter or an action given a dead handle is refused silently: it
  answers 0 or empty and `b3LastError()` keeps whatever it held (observed 2026-11-20). So
  read `b3LastError()` straight after the create you are asking about, and ask
  `b3BodyIsValid` (or the world, shape or joint form) about a handle. The one exception to
  "nothing throws" is a native library from a different release than the binding: the
  first call throws and names the ABI it needs.

## Trying a built library in the IDE without installing it

An installed extension needs none of this: the IDE maps its library itself. To try a library
you have just built, compile the binding, put the library beside it under
`code/<platform id>/`, and say three lines in the Message Box (the paths are examples):

```
load extension from file "/home/me/b3/module.lcm" with resource path "/home/me/b3"
set the revLibraryMapping["box3dxt"] to "/home/me/b3/code/x86_64-linux/box3dxt"
put b3LibraryVersion()
```

The second line is the one that is easy to miss. Without it the module loads and the first
`b3` call fails with `unable to load foreign library 'box3dxt'`: `load extension` alone does
not tell the engine where the library is (observed on OXT-Beyond's Linux IDE, 2026-11-20).
The mapping is the library's path WITHOUT its extension, and it lasts until the IDE quits.

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

## Seeing the world

The library can paint a world itself. Make an image the size of the picture you want, and in
the frame loop render and hand the picture over:

```livecodescript
on physicsStart
   put b3WorldCreate(0, -10, 0, 1) into sWorld
   -- ... create bodies and shapes ...
   if there is no image "view" then create image "view"
   set the width of image "view" to 640
   set the height of image "view" to 400
   b3RenderSetCamera 9, 7, 14, 0, 1, 0, 50          -- eye x y z, target x y z, degrees
   send "physicsFrame" to me in 16 milliseconds
end physicsStart

on physicsFrame
   b3WorldStep sWorld, 1/60, 4
   if b3RenderWorld(sWorld, 640, 400, 0) then        -- 0 solid, 1 wireframe, 2 solid + outlines
      set the imageData of image "view" to b3RenderPixels()
   end if
   send "physicsFrame" to me in 16 milliseconds
end physicsFrame
```

- **The picture and the image must be the same size.** Handed a picture of another size the
  engine raises no error and shows sheared stripes (observed in OXT-Beyond's Linux IDE,
  2026-11-20). `b3RenderWidth()` and `b3RenderHeight()` say what the picture is.
- **y is up, the camera looks from an eye to a target**, and the angle is the vertical field
  of view (50 is a natural lens). The camera, the light (`b3RenderSetLight`, the direction it
  travels) and the background stay as set until changed.
- **Colours.** A shape with no colour of its own is drawn by what its body is doing: static
  scenery grey-green, a moving body one of eight colours, the same colour dimmed while it
  sleeps, so you can watch a pile settle. `b3ShapeSetColor tShape, 230, 120, 40` gives a shape
  its own.
- **Picture coordinates** run right and DOWN from the picture's top left corner, which is
  0,0. `the mouseH - the left of image "view"` is already one.

What is under the mouse, two ways:

```livecodescript
on mouseDown
   local tX, tY, tShape, tRay
   put the mouseH - the left of image "view" into tX
   put the mouseV - the top of image "view" into tY
   put b3RenderShapeAt(tX, tY) into tShape           -- the shape that pixel shows; 0 for none
   if tShape is 0 then exit mouseDown
   -- the exact point: a ray from the camera through the click, 100 m long
   put b3RenderRay(tX, tY) into tRay
   if b3CastRayClosest(sWorld, item 1 of tRay, item 2 of tRay, item 3 of tRay, \
         100 * item 4 of tRay, 100 * item 5 of tRay, 100 * item 6 of tRay) is 1 then
      -- an impulse is mass times the speed it gives: 6 m/s upward, whatever the body weighs
      b3BodyApplyImpulse b3HitBody(1), 0, 6 * b3BodyMass(b3HitBody(1)), 0, item 1 of b3HitPoint(1), item 2 of b3HitPoint(1), item 3 of b3HitPoint(1), true
   end if
end mouseDown
```

`b3RenderProject(x, y, z)` goes the other way (a world point to a place in the picture, for a
label over a body), and `b3RenderDepth` is how far away a pixel's surface is.

What it is and is not: a software rasteriser, there so a simulation can be SEEN on every
platform with nothing else installed. One light, flat or smooth shading, no textures, no
shadows, one picture for the whole library. The cost is the pixels, and more of it is the
engine's than the library's. Measured in OXT-Beyond's Linux IDE on 2026-11-20 (one desktop
machine; the teapot of `tests/models/`, three small ones and some dozens of spheres), a 640
by 400 picture took about 12 ms to draw solid, 9 ms with outlines and 4 ms as a wireframe,
and `set the imageData` then took 14, 12 and 6 ms: about 30, 36 and 58 frames a second. At
960 by 600 the same scene ran at about 15, 20 and 36. The engine's copy costs more for a
busy picture than for an empty one of the same size. So choose the picture's size first; a
smaller picture is the one setting that buys speed.

A mesh is drawn from both sides, though Box3D collides and casts rays against its front
only: looking past a gap into a model, `b3RenderShapeAt` names the mesh where a ray cast
goes through it. A sphere and a capsule are
drawn as the many-sided solids `b3ShapeTrianglesText` lists, so a silhouette can differ from
a ray cast by part of a pixel. For textures, your own models' looks and anything a game
would want, use the suite's render3dxt: it takes `b3RenderCamera()`'s seven numbers, a
body's transform and a shape's `b3ShapeTrianglesText` as they are, and its pictures and rays
are counted the same way as the ones here.

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

## Loading a 3D model

box3dxt simulates a model; it does not read model files or draw them. Reading one is a few
lines of script. A Wavefront `.obj` file keeps a point on each `v` line and a triangle on
each `f` line, counting points from 1 as `b3GeometryAddTriangle` does:

```
b3GeometryBegin
repeat for each line tLine in url ("binfile:" & tPath)
   if word 1 of tLine is "v" then
      get b3GeometryAddPoint(word 2 of tLine + 0, word 3 of tLine + 0, word 4 of tLine + 0)
   else if word 1 of tLine is "f" then
      get b3GeometryAddTriangle(word 2 of tLine + 0, word 3 of tLine + 0, word 4 of tLine + 0)
   end if
end repeat
put b3ShapeAddMesh(tStaticBody, 0.6, 0) into tMesh
```

(That reads triangles written as plain numbers. A file whose faces are `7/3/2` forms or have
four corners needs its `f` lines split first.) What to know before choosing a shape:

- **A mesh is for scenery.** It needs a static body, and may be concave and large. It is
  one-sided: a triangle stops what meets its front, the side its points run
  counter-clockwise around, and lets through what comes from behind. Exported models face
  outwards, so things land on them; a ray cast from INSIDE a model passes out through it.
- **A hull is for things that move.** `b3ShapeAddHull` uses the points alone and wraps them
  in a convex solid, so a handle or a hollow is filled in. Box3D holds a hull to 128 corners,
  faces and edges, and the points of a rounded model are simplified to about 40: the hull
  lies a few percent inside the model.
- **Scale as you add the points.** Box3D wants metres and objects between about 10 cm and
  10 m; multiply each coordinate if the file is in other units.

Both paths are tested on a real model, the Utah teapot (`tests/models/teapot.obj`, 3644
points and 6320 triangles): natively against a ray-triangle test written for the purpose, and
from script on the server engine (`tests/engine-selftest.lc`).

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
- `b3RenderWorld` costs by the pixel far more than by the triangle: halve the picture's
  sides and it draws four times faster. `b3RenderTriangleCount` says how heavy the scene is.
- Bodies at rest fall asleep and cost nothing; `b3WorldAwakeBodyCount` shows how many are not.
