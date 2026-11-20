# render3dxt API reference

The 121 public handlers, from the doc blocks in `src/render3dxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the units, the limits every
call is held to, and the handful of rules that decide whether a scene works.

## The public handlers, in the shim's order

### `r3ABIVersion`

`r3ABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `r3LibraryVersion`

`r3LibraryVersion() returns String`

Returns the version of the native library and of the file readers built into it.

Returns: A text such as "render3dxt 0.1.0 ABI 1; stb_image 2.34; fast_obj 1.3".

The first call that reaches the native library. It throws if the library beside the engine is from another release than this binding.

```
put r3LibraryVersion()
```

### `r3LastError`

`r3LastError() returns String`

Returns why the last call was refused.

Returns: A short text, or empty if the last call was not refused.

A refused call returns 0 or empty and never throws, so a frame loop cannot be stopped by a bad number. Ask this straight after the call you are unsure of.

### `r3LiveCounts`

`r3LiveCounts() returns String`

Returns how many objects of each kind are alive.

Returns: Six numbers as text, "scenes,nodes,meshes,materials,textures,lights".

For finding a leak: the counts should return to where they were once a stack has destroyed what it made.

### `r3TextureLoad`

`r3TextureLoad(in pPath as String) returns Integer`

Loads a picture file as a texture.

- pPath: The file's full path.

Returns: A texture handle, or 0 if the file could not be read.

PNG, JPEG, BMP and TGA files are read, up to 8192 pixels each way. A PNG's transparency is kept, for `r3MaterialSetCutout`. Free it with `r3TextureDestroy`.

```
put r3TextureLoad(specialFolderPath("resources") & "/crate.png") into sCrate
```

### `r3TextureDecode`

`r3TextureDecode(in pBytes as Data) returns Integer`

Makes a texture from the bytes of a picture file.

- pBytes: The whole contents of a PNG, JPEG, BMP or TGA file.

Returns: A texture handle, or 0 if the bytes are not a picture.

For a picture that is not a file on disk: one kept in a custom property, or fetched from a URL. The same formats as `r3TextureLoad`.

```
put r3TextureDecode(url ("binfile:" & tPath)) into sCrate
```

### `r3TextureFromImageData`

`r3TextureFromImageData(in pBytes as Data, in pWidth as Integer, in pHeight as Integer) returns Integer`

Makes a texture from the imageData of an image.

- pBytes: The imageData: four bytes a pixel.
- pWidth: The image's width in pixels.
- pHeight: The image's height in pixels.

Returns: A texture handle, or 0 if the data is too short.

Any image the engine can show can be a texture this way. The texture is opaque: imageData carries no transparency.

```
put r3TextureFromImageData(the imageData of image "Crate", the width of image "Crate", the height of image "Crate") into sCrate
```

### `r3TextureChecker`

`r3TextureChecker(in pSize as Integer, in pCells as Integer, in pR1 as Number, in pG1 as Number, in pB1 as Number, in pR2 as Number, in pG2 as Number, in pB2 as Number) returns Integer`

Makes a checkerboard texture.

- pSize: The texture's width and height in pixels, 2 to 2048.
- pCells: How many squares across, 1 to pSize.
- pR1: The first colour's red, 0 to 255.
- pG1: The first colour's green, 0 to 255.
- pB1: The first colour's blue, 0 to 255.
- pR2: The second colour's red, 0 to 255.
- pG2: The second colour's green, 0 to 255.
- pB2: The second colour's blue, 0 to 255.

Returns: A texture handle, or 0 if an argument was refused.

A texture for a scene that has no picture files: a floor, or a way to see an object turn.

```
put r3TextureChecker(256, 8, 240, 240, 240, 60, 90, 160) into sFloorTexture
```

### `r3TextureDestroy`

`r3TextureDestroy(in pTexture as Integer) returns nothing`

Frees a texture.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

A material that used it draws untextured from then on.

### `r3TextureIsValid`

`r3TextureIsValid(in pTexture as Integer) returns Boolean`

Reports whether a texture handle is alive.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

Returns: True if it is.

### `r3TextureWidth`

`r3TextureWidth(in pTexture as Integer) returns Integer`

Returns the width of a texture.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

Returns: The width in pixels, or 0.

### `r3TextureHeight`

`r3TextureHeight(in pTexture as Integer) returns Integer`

Returns the height of a texture.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

Returns: The height in pixels, or 0.

### `r3TextureSetSmooth`

`r3TextureSetSmooth(in pTexture as Integer, in pFlag as Boolean) returns nothing`

Chooses smooth or blocky drawing of a texture.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.
- pFlag: True for smooth, false for blocky.

Smooth (the default) blends neighbouring pixels of the texture; off shows each as a sharp square, the look pixel art wants.

### `r3TextureIsSmooth`

`r3TextureIsSmooth(in pTexture as Integer) returns Boolean`

Reports whether a texture is drawn smooth.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

Returns: True if it is.

### `r3TextureSetRepeat`

`r3TextureSetRepeat(in pTexture as Integer, in pFlag as Boolean) returns nothing`

Chooses whether a texture repeats beyond its edges.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.
- pFlag: True to repeat, false to stop at the edge.

Repeating (the default) tiles the texture where texture coordinates leave 0 to 1; off stretches its edge pixels instead.

### `r3TextureIsRepeat`

`r3TextureIsRepeat(in pTexture as Integer) returns Boolean`

Reports whether a texture repeats.

- pTexture: A texture handle, from `r3TextureLoad` or another of the r3Texture makers.

Returns: True if it does.

### `r3MaterialCreate`

`r3MaterialCreate(in pR as Number, in pG as Number, in pB as Number) returns Integer`

Makes a material of a colour.

- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.

Returns: A material handle, or 0 if a number was refused.

A material says how a surface looks: its colour, its texture, how shiny it is. Give it to a node with `r3NodeSetMaterial` or to a slot of a mesh with `r3MeshSetSlotMaterial`.

```
put r3MaterialCreate(200, 60, 40) into sBrick
```

### `r3MaterialDestroy`

`r3MaterialDestroy(in pMaterial as Integer) returns nothing`

Frees a material.

- pMaterial: A material handle from `r3MaterialCreate`.

Whatever used it is drawn plain white from then on.

### `r3MaterialIsValid`

`r3MaterialIsValid(in pMaterial as Integer) returns Boolean`

Reports whether a material handle is alive.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: True if it is.

### `r3MaterialSetColor`

`r3MaterialSetColor(in pMaterial as Integer, in pR as Number, in pG as Number, in pB as Number) returns nothing`

Sets the colour of a material.

- pMaterial: A material handle from `r3MaterialCreate`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.

With a texture, the colour tints it; white shows the texture as it is.

### `r3MaterialColor`

`r3MaterialColor(in pMaterial as Integer) returns String`

Returns the colour of a material.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: Three numbers as text, "r,g,b", each 0 to 255.

### `r3MaterialSetTexture`

`r3MaterialSetTexture(in pMaterial as Integer, in pTexture as Integer) returns nothing`

Gives a material a texture.

- pMaterial: A material handle from `r3MaterialCreate`.
- pTexture: A texture handle, or 0 for none.

The texture is laid over the mesh by the mesh's texture coordinates and multiplied by the material's colour.

```
r3MaterialSetTexture sBrick, r3TextureLoad(tPath)
```

### `r3MaterialTexture`

`r3MaterialTexture(in pMaterial as Integer) returns Integer`

Returns the texture of a material.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: The texture handle, or 0 if it has none.

### `r3MaterialSetSpecular`

`r3MaterialSetSpecular(in pMaterial as Integer, in pStrength as Number, in pShininess as Number) returns nothing`

Sets how shiny a material is.

- pMaterial: A material handle from `r3MaterialCreate`.
- pStrength: How bright the highlight is, 0 (none) to 1.
- pShininess: How tight it is, 1 (broad) to 1000 (a pinpoint).

A highlight appears where a light reflects towards the camera. A new material has none.

### `r3MaterialSpecular`

`r3MaterialSpecular(in pMaterial as Integer) returns String`

Returns how shiny a material is.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: Two numbers as text, "strength,shininess".

### `r3MaterialSetEmissive`

`r3MaterialSetEmissive(in pMaterial as Integer, in pR as Number, in pG as Number, in pB as Number) returns nothing`

Sets the light a material gives off by itself.

- pMaterial: A material handle from `r3MaterialCreate`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.

Added to the surface whatever the lights do: a lamp, a screen, a glowing sign.

### `r3MaterialSetUnlit`

`r3MaterialSetUnlit(in pMaterial as Integer, in pFlag as Boolean) returns nothing`

Draws a material at its full colour, ignoring the lights.

- pMaterial: A material handle from `r3MaterialCreate`.
- pFlag: True to turn it on, false to turn it off.

For a sky, a sign, or a flat drawing style.

### `r3MaterialIsUnlit`

`r3MaterialIsUnlit(in pMaterial as Integer) returns Boolean`

Reports whether a material ignores the lights.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: True if it does.

### `r3MaterialSetDoubleSided`

`r3MaterialSetDoubleSided(in pMaterial as Integer, in pFlag as Boolean) returns nothing`

Draws both faces of a material's triangles.

- pMaterial: A material handle from `r3MaterialCreate`.
- pFlag: True to turn it on, false to turn it off.

Normally a triangle seen from behind is skipped, which is right for a closed object. Turn this on for a sheet seen from both sides: a leaf, a flag, a single wall.

### `r3MaterialIsDoubleSided`

`r3MaterialIsDoubleSided(in pMaterial as Integer) returns Boolean`

Reports whether both faces are drawn.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: True if they are.

### `r3MaterialSetFlat`

`r3MaterialSetFlat(in pMaterial as Integer, in pFlag as Boolean) returns nothing`

Lights each triangle as one flat facet.

- pMaterial: A material handle from `r3MaterialCreate`.
- pFlag: True to turn it on, false to turn it off.

Normally light is blended across a triangle so a sphere looks round. Flat shows the facets: the low-polygon look.

### `r3MaterialIsFlat`

`r3MaterialIsFlat(in pMaterial as Integer) returns Boolean`

Reports whether a material is lit in flat facets.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: True if it is.

### `r3MaterialSetCutout`

`r3MaterialSetCutout(in pMaterial as Integer, in pFlag as Boolean) returns nothing`

Leaves holes where a material's texture is transparent.

- pMaterial: A material handle from `r3MaterialCreate`.
- pFlag: True to turn it on, false to turn it off.

A pixel of the texture that is more than half transparent is not drawn at all: fences, leaves, a grating.

### `r3MaterialIsCutout`

`r3MaterialIsCutout(in pMaterial as Integer) returns Boolean`

Reports whether transparent texture pixels are left out.

- pMaterial: A material handle from `r3MaterialCreate`.

Returns: True if they are.

### `r3MeshDestroy`

`r3MeshDestroy(in pMesh as Integer) returns nothing`

Frees a mesh.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

A node that used it draws nothing from then on. A mesh loaded from a model file takes the materials and textures the file made with it.

### `r3MeshIsValid`

`r3MeshIsValid(in pMesh as Integer) returns Boolean`

Reports whether a mesh handle is alive.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Returns: True if it is.

### `r3MeshVertexCount`

`r3MeshVertexCount(in pMesh as Integer) returns Integer`

Returns how many vertices a mesh has.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Returns: The count.

### `r3MeshTriangleCount`

`r3MeshTriangleCount(in pMesh as Integer) returns Integer`

Returns how many triangles a mesh has.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Returns: The count.

### `r3MeshBounds`

`r3MeshBounds(in pMesh as Integer) returns String`

Returns the box that just holds a mesh.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Returns: Six numbers as text, "minX,minY,minZ,maxX,maxY,maxZ", in the mesh's own frame.

Use it to place a camera so a loaded model fits the picture.

### `r3MeshCreate`

`r3MeshCreate() returns Integer`

Makes an empty mesh to fill from script.

Returns: A mesh handle.

Add corners with `r3MeshAddVertex` and faces with `r3MeshAddTriangle`.

```
put r3MeshCreate() into tMesh
get r3MeshAddVertex(tMesh, -1, 0, 0, 0, 0, 1, 0, 1)
get r3MeshAddVertex(tMesh, 1, 0, 0, 0, 0, 1, 1, 1)
get r3MeshAddVertex(tMesh, 0, 2, 0, 0, 0, 1, 0.5, 0)
get r3MeshAddTriangle(tMesh, 1, 2, 3, 1)
```

### `r3MeshAddVertex`

`r3MeshAddVertex(in pMesh as Integer, in pX as Number, in pY as Number, in pZ as Number, in pNx as Number, in pNy as Number, in pNz as Number, in pU as Number, in pV as Number) returns Integer`

Adds a corner to a mesh.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.
- pNx: The normal's x.
- pNy: The normal's y.
- pNz: The normal's z.
- pU: The texture coordinate across, 0 at the left edge of the texture.
- pV: The texture coordinate down, 0 at the top edge of the texture.

Returns: The new vertex's number, counted from 1, or 0 if refused.

The normal is the direction the surface faces at this corner, used for lighting; `r3MeshComputeNormals` can work them out. Texture coordinate 0,0 is the top-left corner of the texture and 1,1 the bottom-right.

### `r3MeshAddTriangle`

`r3MeshAddTriangle(in pMesh as Integer, in pA as Integer, in pB as Integer, in pC as Integer, in pSlot as Integer) returns Integer`

Adds a triangle to a mesh.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pA: The first corner, a vertex number from `r3MeshAddVertex`.
- pB: The second corner.
- pC: The third corner.
- pSlot: The material slot the triangle uses, 1 to 1024.

Returns: The mesh's triangle count, or 0 if refused.

Name the corners counter-clockwise as seen from the side that should be visible.

### `r3MeshComputeNormals`

`r3MeshComputeNormals(in pMesh as Integer) returns nothing`

Works out smooth normals for a mesh from its triangles.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Each corner gets the average direction of the triangles that share it. Call it after the last `r3MeshAddTriangle`.

### `r3MeshSlotCount`

`r3MeshSlotCount(in pMesh as Integer) returns Integer`

Returns how many material slots a mesh has.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.

Returns: The count; 1 for a simple mesh.

A model file with several materials has one slot for each, in the order of its material file.

### `r3MeshSlotMaterial`

`r3MeshSlotMaterial(in pMesh as Integer, in pSlot as Integer) returns Integer`

Returns the material of one slot of a mesh.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pSlot: The material slot, counted from 1.

Returns: The material handle, or 0 if the slot has none.

A model's own materials can be changed through this handle, for example to give one a texture.

### `r3MeshSetSlotMaterial`

`r3MeshSetSlotMaterial(in pMesh as Integer, in pSlot as Integer, in pMaterial as Integer) returns nothing`

Gives one slot of a mesh a material.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pSlot: The material slot, counted from 1.
- pMaterial: A material handle, or 0 for plain white.

Every node that draws the mesh shows it, unless the node has a material of its own.

### `r3MeshSlotName`

`r3MeshSlotName(in pMesh as Integer, in pSlot as Integer) returns String`

Returns the name a model file gave a material slot.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pSlot: The material slot, counted from 1.

Returns: The name, or empty.

### `r3MeshSlotTextureName`

`r3MeshSlotTextureName(in pMesh as Integer, in pSlot as Integer) returns String`

Returns the picture file a model's material asked for.

- pMesh: A mesh handle, from `r3MeshBox`, `r3MeshLoadObj` or another of the r3Mesh makers.
- pSlot: The material slot, counted from 1.

Returns: The file name as the material file wrote it, or empty.

After `r3MeshParseObj`, which reads no files, this says which picture to load for each slot.

### `r3MeshBox`

`r3MeshBox(in pHx as Number, in pHy as Number, in pHz as Number) returns Integer`

Makes a box.

- pHx: Half the width, in metres.
- pHy: Half the height, in metres.
- pHz: Half the depth, in metres.

Returns: A mesh handle, or 0 if a size was refused.

Centred on its origin, like a box shape in box3dxt, so a node at a body's transform covers the body. Each face shows the whole texture.

```
put r3MeshBox(0.5, 0.5, 0.5) into sCube
```

### `r3MeshPlane`

`r3MeshPlane(in pHx as Number, in pHz as Number, in pURepeat as Number, in pVRepeat as Number) returns Integer`

Makes a flat rectangle facing up.

- pHx: Half the width, in metres.
- pHz: Half the depth, in metres.
- pURepeat: How many times the texture repeats across the width.
- pVRepeat: How many times it repeats across the depth.

Returns: A mesh handle, or 0 if an argument was refused.

A floor. The texture repeats across it as many times as asked.

```
put r3MeshPlane(20, 20, 10, 10) into sFloor
```

### `r3MeshSphere`

`r3MeshSphere(in pRadius as Number, in pSlices as Integer, in pStacks as Integer) returns Integer`

Makes a sphere.

- pRadius: The radius, in metres.
- pSlices: How many segments go round the y axis, 3 to 256.
- pStacks: How many segments go from pole to pole, 2 to 256.

Returns: A mesh handle, or 0 if an argument was refused.

More slices and stacks make it rounder and slower to draw; 24 and 12 look round at most sizes.

```
put r3MeshSphere(0.5, 24, 12) into sBall
```

### `r3MeshCylinder`

`r3MeshCylinder(in pRadius as Number, in pHalfHeight as Number, in pSlices as Integer) returns Integer`

Makes a cylinder standing along the y axis.

- pRadius: The radius, in metres.
- pHalfHeight: Half the height, in metres.
- pSlices: How many segments go round the y axis, 3 to 256.

Returns: A mesh handle, or 0 if an argument was refused.

Closed at both ends.

### `r3MeshCapsule`

`r3MeshCapsule(in pRadius as Number, in pHalfHeight as Number, in pSlices as Integer, in pStacks as Integer) returns Integer`

Makes a capsule standing along the y axis.

- pRadius: The radius, in metres.
- pHalfHeight: Half the distance between the centres of the two end spheres, in metres.
- pSlices: How many segments go round the y axis, 3 to 256.
- pStacks: How many segments each end has from its pole to its rim, 2 to 256.

Returns: A mesh handle, or 0 if an argument was refused.

A cylinder with a half sphere on each end: box3dxt's capsule with its two centres at plus and minus pHalfHeight on the y axis.

### `r3MeshFromTrianglesText`

`r3MeshFromTrianglesText(in pText as String) returns Integer`

Makes a mesh from a list of triangles as text.

- pText: One line per triangle, nine numbers: "x1,y1,z1,x2,y2,z2,x3,y3,z3", counter-clockwise seen from outside.

Returns: A mesh handle, or 0 if a line was refused.

The text box3dxt gives for a shape, so that what is drawn is exactly what is simulated. Lighting is flat, and a texture repeats once a metre.

### `r3MeshLoadObj`

`r3MeshLoadObj(in pPath as String) returns Integer`

Loads a model from a Wavefront OBJ file.

- pPath: The file's full path.

Returns: A mesh handle, or 0 if the file could not be read.

The material file the model names (MTL) is read too, and the pictures it names are loaded as textures, so a textured model arrives ready to draw. Faces of any number of corners are accepted. Check `r3LastError` if it returns 0.

```
put r3MeshLoadObj(specialFolderPath("resources") & "/teapot.obj") into sTeapot
put r3NodeCreate(sScene, sTeapot) into sTeapotNode
```

### `r3MeshParseObj`

`r3MeshParseObj(in pObjText as String, in pMtlText as String) returns Integer`

Makes a model from the text of an OBJ file.

- pObjText: The contents of the OBJ file.
- pMtlText: The contents of its material file, or empty.

Returns: A mesh handle, or 0 if the text is not a model.

Nothing is read from disk, so this works where there are no files, such as the web. Textures are not loaded: ask `r3MeshSlotTextureName` which picture each slot wants and set it with `r3MeshSlotMaterial` and `r3MaterialSetTexture`.

### `r3LightCreateDirectional`

`r3LightCreateDirectional(in pScene as Integer, in pDx as Number, in pDy as Number, in pDz as Number, in pR as Number, in pG as Number, in pB as Number, in pIntensity as Number) returns Integer`

Adds a light that shines from far away, like the sun.

- pScene: A scene handle from `r3SceneCreate`.
- pDx: The x of the direction the light travels.
- pDy: The y of the direction the light travels (negative is downward).
- pDz: The z of the direction the light travels.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.
- pIntensity: The brightness, 0 to 100; 1 is full.

Returns: A light handle, or 0 if refused.

Every surface is lit from the same direction. A scene holds at most 8 lights, and starts with one of these.

```
put r3LightCreateDirectional(sScene, -1, -2, -1, 255, 244, 230, 1) into sSun
```

### `r3SceneCreate`

`r3SceneCreate() returns Integer`

Makes a scene.

Returns: A scene handle.

A scene holds nodes (the things drawn), lights and a camera, and draws itself with `r3SceneRender`. It starts with a dim ambient light, one directional light and a camera at 0,2,8 looking at the origin. Free it with `r3SceneDestroy`.

```
put r3SceneCreate() into sScene
```

### `r3SceneDestroy`

`r3SceneDestroy(in pScene as Integer) returns nothing`

Frees a scene with its nodes and lights.

- pScene: A scene handle from `r3SceneCreate`.

Meshes, materials and textures are not the scene's and stay.

### `r3SceneIsValid`

`r3SceneIsValid(in pScene as Integer) returns Boolean`

Reports whether a scene handle is alive.

- pScene: A scene handle from `r3SceneCreate`.

Returns: True if it is.

### `r3SceneSetBackground`

`r3SceneSetBackground(in pScene as Integer, in pR as Number, in pG as Number, in pB as Number) returns nothing`

Sets the colour drawn where nothing is.

- pScene: A scene handle from `r3SceneCreate`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.

### `r3SceneBackground`

`r3SceneBackground(in pScene as Integer) returns String`

Returns the background colour.

- pScene: A scene handle from `r3SceneCreate`.

Returns: Three numbers as text, "r,g,b".

### `r3SceneSetAmbient`

`r3SceneSetAmbient(in pScene as Integer, in pR as Number, in pG as Number, in pB as Number) returns nothing`

Sets the light that reaches every surface from everywhere.

- pScene: A scene handle from `r3SceneCreate`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.

It keeps the sides that face away from every light from going black. The default is 64,64,64.

### `r3SceneAmbient`

`r3SceneAmbient(in pScene as Integer) returns String`

Returns the ambient light.

- pScene: A scene handle from `r3SceneCreate`.

Returns: Three numbers as text, "r,g,b".

### `r3SceneSetFog`

`r3SceneSetFog(in pScene as Integer, in pR as Number, in pG as Number, in pB as Number, in pFogNear as Number, in pFogFar as Number) returns nothing`

Fades distant things into a colour.

- pScene: A scene handle from `r3SceneCreate`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.
- pFogNear: The distance in metres where fog starts.
- pFogFar: The distance where everything is fog, or 0 for no fog.

Usually the background colour, so the far edge of a floor melts away. A pFogFar of 0 turns fog off.

```
r3SceneSetFog sScene, 31, 33, 41, 10, 40
```

### `r3SceneSetSupersample`

`r3SceneSetSupersample(in pScene as Integer, in pN as Integer) returns nothing`

Sets how smooth edges are drawn.

- pScene: A scene handle from `r3SceneCreate`.
- pN: 1 to 4.

Each pixel becomes the average of pN by pN samples. 1 is fastest and has jagged edges; 2 is a good balance; 4 is smoothest and sixteen times the work.

### `r3SceneSupersample`

`r3SceneSupersample(in pScene as Integer) returns Integer`

Returns the supersampling of a scene.

- pScene: A scene handle from `r3SceneCreate`.

Returns: 1 to 4.

### `r3SceneSetCamera`

`r3SceneSetCamera(in pScene as Integer, in pEx as Number, in pEy as Number, in pEz as Number, in pTx as Number, in pTy as Number, in pTz as Number, in pFov as Number) returns nothing`

Places the camera.

- pScene: A scene handle from `r3SceneCreate`.
- pEx: The eye's x, in metres.
- pEy: The eye's y.
- pEz: The eye's z.
- pTx: The x of the point looked at.
- pTy: Its y.
- pTz: Its z.
- pFov: The vertical field of view in degrees, 5 to 150.

The same camera box3dxt's renderer has, so one set of numbers serves both. Up is the world's y axis; looking straight down, the top of the picture is the world's -z.

```
r3SceneSetCamera sScene, 0, 3, 10, 0, 1, 0, 50
```

### `r3SceneSetCameraText`

`r3SceneSetCameraText(in pScene as Integer, in pText as String) returns nothing`

Places the camera from one text.

- pScene: A scene handle from `r3SceneCreate`.
- pText: Seven numbers, "eyeX,eyeY,eyeZ,targetX,targetY,targetZ,fov".

Takes what `r3SceneCamera` returns, or box3dxt's b3RenderCamera().

### `r3SceneCamera`

`r3SceneCamera(in pScene as Integer) returns String`

Returns the camera.

- pScene: A scene handle from `r3SceneCreate`.

Returns: Seven numbers as text, "eyeX,eyeY,eyeZ,targetX,targetY,targetZ,fov".

### `r3SceneSetClip`

`r3SceneSetClip(in pScene as Integer, in pNearZ as Number, in pFarZ as Number) returns nothing`

Sets the nearest and farthest distances drawn.

- pScene: A scene handle from `r3SceneCreate`.
- pNearZ: The near distance in metres, at least 0.001.
- pFarZ: The far distance in metres, or 0 for none.

Nothing nearer than the near distance is drawn (the default is 0.05). A far distance of 0, the default, draws everything.

### `r3SceneClip`

`r3SceneClip(in pScene as Integer) returns String`

Returns the nearest and farthest distances drawn.

- pScene: A scene handle from `r3SceneCreate`.

Returns: Two numbers as text, "near,far".

### `r3SceneProject`

`r3SceneProject(in pScene as Integer, in pW as Integer, in pH as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Finds where a point in the world lands in the picture.

- pScene: A scene handle from `r3SceneCreate`.
- pW: The picture's width in pixels, 1 to 4096.
- pH: The picture's height in pixels, 1 to 4096.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.

Returns: Three numbers as text, "px,py,depth", or empty if the point is behind the camera. Depth is metres in front of the camera.

For placing a label or a control over something in the scene.

```
put r3SceneProject(sScene, 640, 480, 0, 1, 0) into tSpot
set the loc of field "Label" to (the left of image "View" + item 1 of tSpot), (the top of image "View" + item 2 of tSpot)
```

### `r3SceneRay`

`r3SceneRay(in pScene as Integer, in pW as Integer, in pH as Integer, in pPx as Number, in pPy as Number) returns String`

Returns the ray from the camera through a point of the picture.

- pScene: A scene handle from `r3SceneCreate`.
- pW: The picture's width in pixels, 1 to 4096.
- pH: The picture's height in pixels, 1 to 4096.
- pPx: The picture x, in pixels from the left edge; a pixel's centre is at +0.5.
- pPy: The picture y, in pixels from the top edge; a pixel's centre is at +0.5.

Returns: Six numbers as text, "originX,originY,originZ,dirX,dirY,dirZ"; the direction has length 1.

The same ray box3dxt's b3RenderRay gives, for casting into a physics world from a mouse click.

### `r3LightCreatePoint`

`r3LightCreatePoint(in pScene as Integer, in pX as Number, in pY as Number, in pZ as Number, in pR as Number, in pG as Number, in pB as Number, in pIntensity as Number, in pRange as Number) returns Integer`

Adds a light that shines from a point, like a lamp.

- pScene: A scene handle from `r3SceneCreate`.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.
- pIntensity: The brightness, 0 to 100; 1 is full.
- pRange: The distance in metres where its light ends, or 0 for no end.

Returns: A light handle, or 0 if refused.

Things near it are brighter. A scene holds at most 8 lights.

```
put r3LightCreatePoint(sScene, 0, 3, 0, 255, 200, 120, 2, 12) into sLamp
```

### `r3LightDestroy`

`r3LightDestroy(in pLight as Integer) returns nothing`

Removes a light from its scene.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

### `r3LightIsValid`

`r3LightIsValid(in pLight as Integer) returns Boolean`

Reports whether a light handle is alive.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

Returns: True if it is.

### `r3SceneLightCount`

`r3SceneLightCount(in pScene as Integer) returns Integer`

Returns how many lights a scene has.

- pScene: A scene handle from `r3SceneCreate`.

Returns: The count, 0 to 8.

### `r3SceneLight`

`r3SceneLight(in pScene as Integer, in pIndex as Integer) returns Integer`

Returns one of a scene's lights.

- pScene: A scene handle from `r3SceneCreate`.
- pIndex: Which item, counted from 1.

Returns: A light handle, or 0.

Light 1 of a new scene is the directional light it starts with.

### `r3LightSetColor`

`r3LightSetColor(in pLight as Integer, in pR as Number, in pG as Number, in pB as Number, in pIntensity as Number) returns nothing`

Sets the colour and brightness of a light.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.
- pR: Red, 0 to 255.
- pG: Green, 0 to 255.
- pB: Blue, 0 to 255.
- pIntensity: The brightness, 0 to 100; 1 is full.

### `r3LightColor`

`r3LightColor(in pLight as Integer) returns String`

Returns the colour and brightness of a light.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

Returns: Four numbers as text, "r,g,b,intensity".

### `r3LightSetDirection`

`r3LightSetDirection(in pLight as Integer, in pDx as Number, in pDy as Number, in pDz as Number) returns nothing`

Turns a directional light.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.
- pDx: The x of the direction the light travels.
- pDy: The y of the direction the light travels.
- pDz: The z of the direction the light travels.

Refused for a point light.

### `r3LightSetPosition`

`r3LightSetPosition(in pLight as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Moves a point light.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.

Refused for a directional light.

### `r3LightVector`

`r3LightVector(in pLight as Integer) returns String`

Returns the direction of a directional light or the position of a point light.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

Returns: Three numbers as text, "x,y,z".

### `r3LightKind`

`r3LightKind(in pLight as Integer) returns Integer`

Returns what kind a light is.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

Returns: 1 for directional, 2 for point, 0 for a handle that is not alive.

### `r3LightSetEnabled`

`r3LightSetEnabled(in pLight as Integer, in pFlag as Boolean) returns nothing`

Turns a light on or off.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.
- pFlag: True to turn it on, false to turn it off.

### `r3LightIsEnabled`

`r3LightIsEnabled(in pLight as Integer) returns Boolean`

Reports whether a light is on.

- pLight: A light handle, from `r3LightCreateDirectional` or `r3LightCreatePoint`.

Returns: True if it is.

### `r3NodeCreate`

`r3NodeCreate(in pScene as Integer, in pMesh as Integer) returns Integer`

Places a mesh in a scene.

- pScene: A scene handle from `r3SceneCreate`.
- pMesh: A mesh handle, or 0 for a node that draws nothing yet.

Returns: A node handle, or 0 if refused.

A node is one thing drawn: a mesh at a position, with a rotation and a size. Many nodes can share one mesh. Destroying the scene destroys its nodes.

```
put r3NodeCreate(sScene, sCube) into tNode
r3NodeSetPosition tNode, 0, 2, 0
```

### `r3NodeDestroy`

`r3NodeDestroy(in pNode as Integer) returns nothing`

Removes a node from its scene.

- pNode: A node handle from `r3NodeCreate`.

### `r3NodeIsValid`

`r3NodeIsValid(in pNode as Integer) returns Boolean`

Reports whether a node handle is alive.

- pNode: A node handle from `r3NodeCreate`.

Returns: True if it is.

### `r3NodeScene`

`r3NodeScene(in pNode as Integer) returns Integer`

Returns the scene a node is in.

- pNode: A node handle from `r3NodeCreate`.

Returns: The scene handle, or 0.

### `r3SceneNodeCount`

`r3SceneNodeCount(in pScene as Integer) returns Integer`

Returns how many nodes a scene has.

- pScene: A scene handle from `r3SceneCreate`.

Returns: The count.

### `r3SceneNode`

`r3SceneNode(in pScene as Integer, in pIndex as Integer) returns Integer`

Returns one of a scene's nodes.

- pScene: A scene handle from `r3SceneCreate`.
- pIndex: Which item, counted from 1.

Returns: A node handle, or 0.

The order changes when a node is destroyed, so read the whole list again after that.

### `r3NodeSetMesh`

`r3NodeSetMesh(in pNode as Integer, in pMesh as Integer) returns nothing`

Changes the mesh a node draws.

- pNode: A node handle from `r3NodeCreate`.
- pMesh: A mesh handle, or 0 to draw nothing.

### `r3NodeMesh`

`r3NodeMesh(in pNode as Integer) returns Integer`

Returns the mesh a node draws.

- pNode: A node handle from `r3NodeCreate`.

Returns: The mesh handle, or 0.

### `r3NodeSetMaterial`

`r3NodeSetMaterial(in pNode as Integer, in pMaterial as Integer) returns nothing`

Gives a node a material of its own.

- pNode: A node handle from `r3NodeCreate`.
- pMaterial: A material handle, or 0 to go back to the mesh's own materials.

It replaces every material of the mesh for this node alone, so many nodes can share a mesh and differ in colour.

### `r3NodeMaterial`

`r3NodeMaterial(in pNode as Integer) returns Integer`

Returns a node's own material.

- pNode: A node handle from `r3NodeCreate`.

Returns: The material handle, or 0 if it uses the mesh's.

### `r3NodeSetPosition`

`r3NodeSetPosition(in pNode as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Moves a node.

- pNode: A node handle from `r3NodeCreate`.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.

### `r3NodeSetRotation`

`r3NodeSetRotation(in pNode as Integer, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Turns a node.

- pNode: A node handle from `r3NodeCreate`.
- pQx: The quaternion's x.
- pQy: The quaternion's y.
- pQz: The quaternion's z.
- pQw: The quaternion's w.

The rotation is a quaternion, as box3dxt gives; it need not be exactly unit length.

### `r3NodeSetTransform`

`r3NodeSetTransform(in pNode as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Moves and turns a node at once.

- pNode: A node handle from `r3NodeCreate`.
- pX: The x coordinate, in metres.
- pY: The y coordinate, in metres (y is up).
- pZ: The z coordinate, in metres.
- pQx: The quaternion's x.
- pQy: The quaternion's y.
- pQz: The quaternion's z.
- pQw: The quaternion's w.

### `r3NodeSetTransformText`

`r3NodeSetTransformText(in pNode as Integer, in pText as String) returns nothing`

Moves and turns a node from one text.

- pNode: A node handle from `r3NodeCreate`.
- pText: Seven numbers, "x,y,z,qx,qy,qz,qw".

Takes what box3dxt's b3BodyTransform returns, so a body's node follows it in one line.

```
r3NodeSetTransformText tNode, b3BodyTransform(tBody)
```

### `r3NodeSetScale`

`r3NodeSetScale(in pNode as Integer, in pSx as Number, in pSy as Number, in pSz as Number) returns nothing`

Sets the size of a node.

- pNode: A node handle from `r3NodeCreate`.
- pSx: The scale along the mesh's x.
- pSy: The scale along its y.
- pSz: The scale along its z.

1 is the mesh's own size. A negative number mirrors the mesh.

### `r3NodePosition`

`r3NodePosition(in pNode as Integer) returns String`

Returns where a node is.

- pNode: A node handle from `r3NodeCreate`.

Returns: Three numbers as text, "x,y,z".

### `r3NodeRotation`

`r3NodeRotation(in pNode as Integer) returns String`

Returns the rotation of a node.

- pNode: A node handle from `r3NodeCreate`.

Returns: Four numbers as text, "qx,qy,qz,qw".

### `r3NodeScale`

`r3NodeScale(in pNode as Integer) returns String`

Returns the size of a node.

- pNode: A node handle from `r3NodeCreate`.

Returns: Three numbers as text, "sx,sy,sz".

### `r3NodeTransform`

`r3NodeTransform(in pNode as Integer) returns String`

Returns the position and rotation of a node.

- pNode: A node handle from `r3NodeCreate`.

Returns: Seven numbers as text, "x,y,z,qx,qy,qz,qw".

### `r3NodeSetVisible`

`r3NodeSetVisible(in pNode as Integer, in pFlag as Boolean) returns nothing`

Shows or hides a node.

- pNode: A node handle from `r3NodeCreate`.
- pFlag: True to show it, false to hide it.

A hidden node is not drawn and not found by `r3ScenePick`.

### `r3NodeIsVisible`

`r3NodeIsVisible(in pNode as Integer) returns Boolean`

Reports whether a node is shown.

- pNode: A node handle from `r3NodeCreate`.

Returns: True if it is.

### `r3NodeSetTag`

`r3NodeSetTag(in pNode as Integer, in pTag as Integer) returns nothing`

Gives a node a number of your choosing.

- pNode: A node handle from `r3NodeCreate`.
- pTag: A whole number; 0 means no tag.

Normally the box3dxt body the node draws: `r3SceneApplyMoves` moves the nodes whose tag is a body that moved.

```
r3NodeSetTag tNode, tBody
```

### `r3NodeTag`

`r3NodeTag(in pNode as Integer) returns Integer`

Returns the tag of a node.

- pNode: A node handle from `r3NodeCreate`.

Returns: The number, or 0.

### `r3SceneNodeByTag`

`r3SceneNodeByTag(in pScene as Integer, in pTag as Integer) returns Integer`

Finds the node with a tag.

- pScene: A scene handle from `r3SceneCreate`.
- pTag: The number given to `r3NodeSetTag`.

Returns: The first such node's handle, or 0.

### `r3SceneApplyMoves`

`r3SceneApplyMoves(in pScene as Integer, in pText as String) returns Integer`

Moves every node whose body moved, from box3dxt's move list.

- pScene: A scene handle from `r3SceneCreate`.
- pText: What b3MovesText() returns: one line per body, "body,x,y,z,qx,qy,qz,qw,fellAsleep".

Returns: How many nodes were moved.

One call a frame carries a whole physics step to the picture: each line of the text moves the nodes tagged with that body (`r3NodeSetTag`). Bodies with no node are skipped.

```
b3WorldStep sWorld, 1/60, 4
get b3WorldUpdateMoves(sWorld)
get r3SceneApplyMoves(sScene, b3MovesText())
set the imageData of image "View" to r3SceneRender(sScene, 640, 480)
```

### `r3SetThreadCount`

`r3SetThreadCount(in pN as Integer) returns nothing`

Sets how many processor threads draw a picture.

- pN: 1 to 16.

The picture is the same whatever the number; more threads draw a large picture faster. The default is the number of processor cores, up to 8.

### `r3ThreadCount`

`r3ThreadCount() returns Integer`

Returns how many threads draw a picture.

Returns: 1 to 16.

### `r3SceneRender`

`r3SceneRender(in pScene as Integer, in pW as Integer, in pH as Integer) returns Data`

Draws a scene and returns the picture.

- pScene: A scene handle from `r3SceneCreate`.
- pW: The picture's width in pixels, 1 to 4096.
- pH: The picture's height in pixels, 1 to 4096.

Returns: The picture as imageData, pW by pH pixels, or empty if the call was refused.

Set it as the imageData of an image of the same width and height. The whole picture is drawn inside the library, so thousands of triangles cost a few milliseconds.

```
set the imageData of image "View" to r3SceneRender(sScene, the width of image "View", the height of image "View")
```

### `r3SceneFrame`

`r3SceneFrame(in pScene as Integer) returns Data`

Returns the last picture drawn of a scene again.

- pScene: A scene handle from `r3SceneCreate`.

Returns: The picture as imageData, or empty if none was drawn.

### `r3SceneFrameLength`

`r3SceneFrameLength(in pScene as Integer) returns Integer`

Returns the size of the last picture drawn of a scene.

- pScene: A scene handle from `r3SceneCreate`.

Returns: The byte count, width times height times 4, or 0.

### `r3SceneStats`

`r3SceneStats(in pScene as Integer) returns String`

Returns how much work the last picture was.

- pScene: A scene handle from `r3SceneCreate`.

Returns: Three numbers as text, "triangles,pixels,milliseconds": triangles drawn, pixels written, and the time taken.

For tuning a scene: show item 3 in a field while you change it.

### `r3ScenePick`

`r3ScenePick(in pScene as Integer, in pW as Integer, in pH as Integer, in pPx as Number, in pPy as Number) returns Integer`

Finds the node under a point of the picture.

- pScene: A scene handle from `r3SceneCreate`.
- pW: The picture's width in pixels, 1 to 4096.
- pH: The picture's height in pixels, 1 to 4096.
- pPx: The picture x, in pixels from the left edge; a pixel's centre is at +0.5.
- pPy: The picture y, in pixels from the top edge; a pixel's centre is at +0.5.

Returns: The node handle, or 0 if nothing is there.

For clicking on things. `r3HitText` then says where it was hit.

```
on mouseDown
put r3ScenePick(sScene, the width of me, the height of me, the mouseH - the left of me, the mouseV - the top of me) into tNode
end mouseDown
```

### `r3SceneRayCast`

`r3SceneRayCast(in pScene as Integer, in pOx as Number, in pOy as Number, in pOz as Number, in pDx as Number, in pDy as Number, in pDz as Number) returns Integer`

Finds the first node a ray meets.

- pScene: A scene handle from `r3SceneCreate`.
- pOx: The x of the ray's start.
- pOy: The y of the ray's start.
- pOz: The z of the ray's start.
- pDx: The x of the ray's direction.
- pDy: The y of the ray's direction.
- pDz: The z of the ray's direction.

Returns: The node handle, or 0.

`r3HitText` then says where.

### `r3HitText`

`r3HitText() returns String`

Returns where the last pick or ray cast hit.

Returns: Five numbers as text, "x,y,z,distance,triangle", or empty if it hit nothing.
