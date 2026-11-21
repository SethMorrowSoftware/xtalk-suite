# Getting started with render3dxt

render3dxt turns a description of a 3D scene into a picture. You make meshes, give them
materials, place them as nodes in a scene, aim a camera, and ask for the picture; it comes
back as `imageData` for an ordinary image control. This page is what to know before the
[API reference](api-reference.md).

## The conventions

- **Metres, y up, right-handed.** The same world as box3dxt: +x is right, +y is up, and a
  camera at +z looking at the origin sees +x on its right. A rotation is a quaternion
  `"x,y,z,w"`; a transform is seven items, `"x,y,z,qx,qy,qz,qw"`.
- **Handles are integers.** A scene, node, mesh, material, texture or light is a number; 0
  is "none". A handle to something destroyed is refused by every call, harmlessly: getters
  answer 0 or empty, actions do nothing.
- **Who owns what.** A scene owns its nodes and lights and frees them when it is destroyed.
  Meshes, materials and textures belong to the script: they can be shared between nodes and
  scenes, and they stay until you destroy them. A mesh loaded from a model file owns the
  materials and textures the file made, and takes them with it.
- **Colours are 0 to 255**, as everywhere in xTalk. A light's brightness is a separate
  number, 1 for full.
- **Several numbers come back as text.** `r3NodePosition` returns `"x,y,z"`, a colour
  `"r,g,b"`. The decimal point is `.` in every locale.
- **Every parameter is typed.** A number parameter must be given a number: empty is an
  engine error at the call, before render3dxt sees it. Pass 0, not empty. A yes-or-no
  parameter takes `true` or `false`.
- **Nothing throws.** A call with a bad argument does nothing, returns 0 or empty, and
  `r3LastError()` says why. The one exception is a native library from a different release
  than the binding: the first call throws and names the ABI it needs.
- **The picture is `imageData`**: four bytes a pixel (0, red, green, blue), rows from the
  top. The image control must be exactly as wide and as high as the picture you ask for,
  because `imageData` is not scaled.

## A first picture

```livecodescript
local sScene, sBox, sWood, sCrate

on showCrate
   put r3SceneCreate() into sScene
   put r3MeshBox(0.5, 0.5, 0.5) into sBox                  -- half-sizes: a 1 m cube
   put r3MaterialCreate(200, 150, 90) into sWood
   r3MaterialSetTexture sWood, r3TextureChecker(64, 4, 255, 255, 255, 190, 190, 190)
   put r3NodeCreate(sScene, sBox) into sCrate
   r3NodeSetMaterial sCrate, sWood
   r3SceneSetCamera sScene, 2, 2, 4,  0, 0, 0,  50
   set the imageData of image "View" to r3SceneRender(sScene, the width of image "View", the height of image "View")
end showCrate

on closeStack
   r3SceneDestroy sScene
   r3MeshDestroy sBox
   r3MaterialDestroy sWood
end closeStack
```

A new scene already has a camera (at `0,2,8`, looking at the origin), one sun-like light
from above and behind the camera's right shoulder, grey ambient light and a dark background,
so the first thing you add can be seen.

## A frame loop with box3dxt

box3dxt moves bodies; render3dxt draws nodes. Tag each node with its body's handle, and one
call a frame moves every node whose body moved:

```livecodescript
local sWorld, sScene

command addCrate pX, pY, pZ
   local tBody, tNode
   put b3BodyCreate(sWorld, 2, pX, pY, pZ) into tBody
   get b3ShapeAddBox(tBody, 0.5, 0.5, 0.5, 1, 0.6, 0.1)
   put r3NodeCreate(sScene, sBox) into tNode
   r3NodeSetTransformText tNode, b3BodyTransform(tBody)   -- where the body starts
   r3NodeSetTag tNode, tBody                              -- the whole link between them
end addCrate

on frame
   set the defaultStack to the short name of this stack
   showPicture r3SceneFrame(sScene)                 -- the picture begun last frame
   b3WorldStep sWorld, 1/60, 4
   get b3WorldUpdateMoves(sWorld)
   get r3SceneApplyMoves(sScene, b3MovesText())
   get r3SceneRenderBegin(sScene, 640, 480)         -- drawn while the engine goes on
   send "frame" to me in 16 milliseconds
end frame

command showPicture pPicture
   local tWas
   if pPicture is empty then exit showPicture
   put the paintCompression into tWas
   set the paintCompression to "rle"
   set the imageData of image "View" to pPicture
   set the paintCompression to tWas
end showPicture
```

Two things in that loop are about the engine, not about 3D, and they decide the frame rate:

- **The engine runs script on one thread.** `r3SceneRender` draws the picture inside the
  call, and nothing else happens until it returns. `r3SceneRenderBegin` reads the scene,
  hands the drawing to the library's own threads and returns; the picture is drawn while
  the engine redraws the window and waits for the timer, and `r3SceneFrame` takes it a
  frame later (waiting only if it is not finished). Any call that names a scene, node,
  mesh, material, texture or light waits for a picture that is still drawing, so the order
  above (take, change, begin) is the one that never waits.
- **`set the imageData` compresses the picture** the way `the paintCompression` says, and
  a desktop engine starts with "png". Encoding a PNG of every frame took 36.6 ms of a
  49 ms frame in the demo (OXT-Beyond 0.2.8-dp.2, 2026-11-20), three times what drawing
  it did; with "rle" the same step took 6.5 ms. The property is global and the paint tools
  read it, so set it around the one line and put it back.

A game also steps its physics by the clock rather than once a frame, so a slow machine shows
fewer pictures instead of slower motion, and draws nothing when nothing moved: the demo's
`rdFrame` does both.

The sizes agree by design: `r3MeshBox` takes half-sizes like `b3ShapeAddBox`, and a box, a
sphere, a cylinder and a capsule are all centred on their origin, so a node at a body's
transform covers the body. A click leads back the other way:

```livecodescript
put r3ScenePick(sScene, 640, 480, the mouseH - the left of image "View", the mouseV - the top of image "View") into tNode
if tNode is not 0 then
   put r3NodeTag(tNode) into tBody          -- the body under the mouse
   put r3HitText() into tWhere              -- "x,y,z,distance,triangle"
end if
```

`examples/render3d-physics-demo.livecodescript` is this, whole.

## Models and textures

```livecodescript
put r3MeshLoadObj(specialFolderPath("resources") & "/teapot.obj") into sTeapot
if sTeapot is 0 then answer r3LastError()
```

`r3MeshLoadObj` reads the model, the material file it names (MTL) and the pictures that
names, so a textured model arrives ready to draw. Faces of any number of corners are
accepted. Where there are no files (the web, or a model kept in a custom property),
`r3MeshParseObj` takes the two files' text and reads nothing from disk; ask
`r3MeshSlotTextureName` which picture each material wanted and supply it yourself with
`r3TextureDecode`.

A model's materials are its **slots**, counted from 1 in the order of its material file.
`r3MeshSlotMaterial` returns one so that you can change it; `r3NodeSetMaterial` replaces all
of them for one node.

Textures come from a file (`r3TextureLoad`: PNG, JPEG, BMP, TGA), from bytes
(`r3TextureDecode`), from an image control (`r3TextureFromImageData` with its `imageData`,
width and height) or from nowhere (`r3TextureChecker`). A texture's coordinate (0,0) is its
top-left corner. New textures are smooth and repeat; `r3TextureSetSmooth` and
`r3TextureSetRepeat` change that.

## The camera, and going between the picture and the world

`r3SceneSetCamera` takes an eye, a target and a vertical field of view in degrees (5 to
150). Up is +y; looking straight up or down, the top of the picture is world -z.

- `r3SceneProject(scene, width, height, x, y, z)` returns `"px,py,depth"`: where that point
  of the world is in a picture of that size, and how far in front of the camera. It is empty
  for a point behind the camera. Use it to put a field or a label over a 3D thing.
- `r3SceneRay(scene, width, height, px, py)` returns `"ox,oy,oz,dx,dy,dz"`: the ray from the
  camera through that point of the picture.

Picture coordinates count from the top-left corner, in pixels, and a pixel's centre is at
+0.5. These are the numbers box3dxt uses for its own camera, so a camera text from one can
be given to the other (`r3SceneSetCameraText`).

## Five rules that decide whether a scene works

1. **The image must be the picture's size.** Ask for the width and height of the image
   control, as the first example does.
2. **Triangles face one way.** A triangle is drawn only from the side where its corners run
   counter-clockwise. A model that looks inside-out, or a plane seen from below, needs
   `r3MaterialSetDoubleSided`.
3. **Draw from a timer, not from a loop.** One picture a frame, from a `send ... in`
   handler; a `repeat` that draws never lets the screen update.
4. **Destroy what you made.** Scenes, meshes, materials and textures live until destroyed,
   beyond the stack that made them. `r3LiveCounts()` shows what is alive.
5. **Pin the stack in the frame handler** (`set the defaultStack to the short name of this
   stack`): a delayed handler's `image "View"` otherwise means the frontmost stack's.

## The limits every call is held to

| What | Limit |
|---|---|
| Any coordinate | finite, within 10,000,000 either side of 0 |
| A picture | 1 to 4096 pixels each way |
| Smooth edges | 1 to 4 samples each way; the picture times the samples at most 4096 x 4096 |
| A texture | 1 to 8192 pixels each way |
| A mesh | at most 4,000,000 vertices and 4,000,000 triangles |
| A model file | at most 1,333,333 triangles |
| Material slots of a mesh | 1024 |
| Lights in a scene | 8 |
| A size (radius, half-size) | 0.0001 to 100,000 |
| Slices and stacks of a round shape | 3 to 256 (stacks from 2) |
| The field of view | 5 to 150 degrees |
| The near distance | at least 0.001; the default is 0.05 |
| Threads | 1 to 16; the default is the processor's cores, up to 8 |

## Performance notes

- The cost of a picture is mostly its pixels. Halving the image's width and height makes it
  four times cheaper; smooth edges at 2 make it four times dearer.
- `r3SceneStats(scene)` returns `"triangles,pixels,milliseconds"` for the last picture. Show
  it in a field while you tune.
- A smooth texture costs more than a sharp one, and a repeating texture is fastest when its
  width and height are powers of two (64, 256, 1024).
- Lighting is worked out at the corners of triangles and blended across them, so more lights
  cost little, and a large flat floor shows a lamp's pool of light only if it is made of
  several triangles.
- In a frame loop, begin the picture and take it a frame later (`r3SceneRenderBegin`,
  above), and set "rle" as the paintCompression around `set the imageData`: those two
  decide the frame rate more than anything in the scene.
- The picture is the same whatever the thread count. On the web the library draws on one
  thread.
- Moving a thousand nodes one call at a time from script costs more than drawing them:
  `r3SceneApplyMoves` moves them all in one call.
