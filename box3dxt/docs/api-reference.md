# box3dxt API reference

The 398 public handlers, from the doc blocks in `src/box3dxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the units, the limits every
call is held to, and the handful of rules that decide whether a scene works.

## The library

### `b3ABIVersion`

`b3ABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 2.

### `b3LibraryVersion`

`b3LibraryVersion() returns String`

Returns the versions of the native library and of Box3D inside it.

Returns: Text such as "box3dxt ABI 2; Box3D 0.2.0".

The first call that reaches the native library. It throws if the library on disk has a different ABI from this binding, which means the two come from different releases.

```
put b3LibraryVersion() into field "status"
```

### `b3LastError`

`b3LastError() returns String`

Returns why the last refused call was refused.

Returns: A short sentence, or empty if nothing has been refused since the last successful create.

A call given a bad argument does nothing and returns 0 or empty; it never throws. This says what was wrong. Creators (worlds, bodies, shapes, joints) set it; a successful create clears it.

### `b3AssertCount`

`b3AssertCount() returns Integer`

Returns how many of Box3D's internal checks have failed since the library loaded.

Returns: The count. Always 0 with a released library, which is built without those checks.

For people who build the native library themselves with Box3D's asserts on. A failed check is counted and the call carries on; it never stops the host.

### `b3AssertText`

`b3AssertText() returns String`

Returns the last Box3D internal check that failed.

Returns: Text "condition (file:line)", or empty.

### `b3HasAVX2`

`b3HasAVX2() returns Boolean`

Reports whether the solver is using AVX2 on this computer.

Returns: True on an x86-64 processor with AVX2; false elsewhere (the solver then uses SSE2, NEON or plain code).

### `b3UnstableCount`

`b3UnstableCount() returns Integer`

Returns how many bodies have been removed because their motion stopped being a number.

Returns: The count since the library loaded.

A scene can drive the solver to NaN: most often a joint between bodies that have no shapes, and so no mass. After every step the binding removes such a body, with its shapes and joints, because leaving it would crash the host later. A script that sees this number grow should look at `b3LastError` and at how the bodies it lost were built.

## Worlds

### `b3WorldCreate`

`b3WorldCreate(in pGx as Number, in pGy as Number, in pGz as Number, in pWorkers as Integer) returns Integer`

Creates a physics world.

- pGx: The x component of gravity in m/s^2.
- pGy: The y component of gravity in m/s^2; y points up, so -10 is down.
- pGz: The z component of gravity in m/s^2.
- pWorkers: How many worker threads the world steps with, 1 to 32. Use 1 unless a scene has thousands of bodies.

Returns: A world handle, or 0 if the arguments were refused or 128 worlds already exist.

Everything else lives in a world. Distances are metres, time is seconds, mass is kilograms and angles are radians; y points up. Advance it with `b3WorldStep` and free it with `b3WorldDestroy`.

```
put b3WorldCreate(0, -10, 0, 1) into sWorld
```

### `b3WorldDestroy`

`b3WorldDestroy(in pWorld as Integer) returns nothing`

Destroys a world and everything in it.

- pWorld: A world handle from `b3WorldCreate`.

Every body, shape and joint of the world is destroyed with it and their handles go dead. A dead or 0 handle is ignored.

### `b3WorldIsValid`

`b3WorldIsValid(in pWorld as Integer) returns Boolean`

Reports whether a handle names a live world.

- pWorld: A world handle from `b3WorldCreate`.

Returns: True for a live world.

### `b3WorldStep`

`b3WorldStep(in pWorld as Integer, in pSeconds as Number, in pSubsteps as Integer) returns nothing`

Advances a world by a slice of time.

- pWorld: A world handle from `b3WorldCreate`.
- pSeconds: The time to advance, in seconds: above 0, at most 1. 1/60 is the usual choice.
- pSubsteps: How many sub-steps the solver takes, 1 to 64. 4 is the usual choice.

Call it at a fixed rate with a fixed step: once per frame with 1/60 and 4 sub-steps suits most scenes. Read positions afterwards (`b3WorldUpdateMoves` gives every body that moved in one call). A step of 0 seconds, or more than 1, is ignored.

```
b3WorldStep sWorld, 1/60, 4
```

### `b3WorldSetGravity`

`b3WorldSetGravity(in pWorld as Integer, in pGx as Number, in pGy as Number, in pGz as Number) returns nothing`

Sets the gravity of a world.

- pWorld: A world handle from `b3WorldCreate`.
- pGx: The x component of gravity in m/s^2.
- pGy: The y component of gravity in m/s^2; y points up, so -10 is down.
- pGz: The z component of gravity in m/s^2.

### `b3WorldGravity`

`b3WorldGravity(in pWorld as Integer) returns String`

Returns the gravity of a world.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The three numbers as text, "x,y,z".

### `b3WorldEnableSleeping`

`b3WorldEnableSleeping(in pWorld as Integer, in pFlag as Boolean) returns nothing`

Lets resting bodies go to sleep, or keeps every body awake.

- pWorld: A world handle from `b3WorldCreate`.
- pFlag: True to turn it on, false to turn it off.

Sleeping is on by default and is what makes a large resting scene cheap.

### `b3WorldIsSleepingEnabled`

`b3WorldIsSleepingEnabled(in pWorld as Integer) returns Boolean`

Reports whether bodies in a world may sleep.

- pWorld: A world handle from `b3WorldCreate`.

Returns: True if sleeping is on.

### `b3WorldEnableContinuous`

`b3WorldEnableContinuous(in pWorld as Integer, in pFlag as Boolean) returns nothing`

Turns continuous collision on or off.

- pWorld: A world handle from `b3WorldCreate`.
- pFlag: True to turn it on, false to turn it off.

On by default: it stops fast bodies tunnelling through static geometry.

### `b3WorldIsContinuousEnabled`

`b3WorldIsContinuousEnabled(in pWorld as Integer) returns Boolean`

Reports whether continuous collision is on.

- pWorld: A world handle from `b3WorldCreate`.

Returns: True if it is on.

### `b3WorldSetRestitutionThreshold`

`b3WorldSetRestitutionThreshold(in pWorld as Integer, in pValue as Number) returns nothing`

Sets the impact speed below which nothing bounces.

- pWorld: A world handle from `b3WorldCreate`.
- pValue: The speed in m/s, 0 or more.

### `b3WorldRestitutionThreshold`

`b3WorldRestitutionThreshold(in pWorld as Integer) returns Number`

Returns the impact speed below which nothing bounces.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The speed in m/s.

### `b3WorldSetHitEventThreshold`

`b3WorldSetHitEventThreshold(in pWorld as Integer, in pValue as Number) returns nothing`

Sets the impact speed above which a hit event is reported.

- pWorld: A world handle from `b3WorldCreate`.
- pValue: The speed in m/s, 0 or more.

### `b3WorldHitEventThreshold`

`b3WorldHitEventThreshold(in pWorld as Integer) returns Number`

Returns the impact speed above which a hit event is reported.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The speed in m/s.

### `b3WorldSetContactTuning`

`b3WorldSetContactTuning(in pWorld as Integer, in pHertz as Number, in pDamping as Number, in pSpeed as Number) returns nothing`

Tunes how stiffly overlapping shapes are pushed apart.

- pWorld: A world handle from `b3WorldCreate`.
- pHertz: The contact stiffness in cycles per second, 0 to 10000 (30 is the default).
- pDamping: The contact damping ratio, 0 to 1000 (10 is the default).
- pSpeed: The fastest that overlap is pushed out, in m/s.

Advanced. The defaults suit almost every scene.

### `b3WorldSetMaxLinearSpeed`

`b3WorldSetMaxLinearSpeed(in pWorld as Integer, in pValue as Number) returns nothing`

Sets the fastest any body in a world may move.

- pWorld: A world handle from `b3WorldCreate`.
- pValue: The speed in m/s, above 0.

### `b3WorldMaxLinearSpeed`

`b3WorldMaxLinearSpeed(in pWorld as Integer) returns Number`

Returns the fastest any body in a world may move.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The speed in m/s.

### `b3WorldSetWorkerCount`

`b3WorldSetWorkerCount(in pWorld as Integer, in pWorkers as Integer) returns nothing`

Changes how many worker threads a world steps with.

- pWorld: A world handle from `b3WorldCreate`.
- pWorkers: How many worker threads the world steps with, 1 to 32. Use 1 unless a scene has thousands of bodies.

### `b3WorldWorkerCount`

`b3WorldWorkerCount(in pWorld as Integer) returns Integer`

Returns how many worker threads a world steps with.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count; always 1 in a web build.

### `b3WorldBodyCount`

`b3WorldBodyCount(in pWorld as Integer) returns Integer`

Returns how many bodies a world holds.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count.

### `b3WorldShapeCount`

`b3WorldShapeCount(in pWorld as Integer) returns Integer`

Returns how many shapes a world holds.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count.

### `b3WorldJointCount`

`b3WorldJointCount(in pWorld as Integer) returns Integer`

Returns how many joints a world holds.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count.

### `b3WorldContactCount`

`b3WorldContactCount(in pWorld as Integer) returns Integer`

Returns how many pairs of shapes are being tracked as touching or near.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count.

### `b3WorldAwakeBodyCount`

`b3WorldAwakeBodyCount(in pWorld as Integer) returns Integer`

Returns how many bodies of a world are awake.

- pWorld: A world handle from `b3WorldCreate`.

Returns: The count.

### `b3WorldStepMs`

`b3WorldStepMs(in pWorld as Integer) returns Number`

Returns how long the last step took.

- pWorld: A world handle from `b3WorldCreate`.

Returns: Milliseconds.

### `b3WorldBounds`

`b3WorldBounds(in pWorld as Integer) returns String`

Returns the box that holds everything in a world.

- pWorld: A world handle from `b3WorldCreate`.

Returns: Six numbers as text, "lowerX,lowerY,lowerZ,upperX,upperY,upperZ", or empty for an empty world.

### `b3WorldExplode`

`b3WorldExplode(in pWorld as Integer, in pX as Number, in pY as Number, in pZ as Number, in pRadius as Number, in pFalloff as Number, in pImpulse as Number) returns nothing`

Pushes every body near a point away from it.

- pWorld: A world handle from `b3WorldCreate`.
- pX: The x of the centre of the blast.
- pY: The y of the centre.
- pZ: The z of the centre.
- pRadius: The radius of full strength, in metres.
- pFalloff: How far beyond the radius the push fades to nothing.
- pImpulse: The push per square metre of surface facing the blast. Negative pulls.

## Bodies

### `b3BodyCreate`

`b3BodyCreate(in pWorld as Integer, in pType as Integer, in pX as Number, in pY as Number, in pZ as Number) returns Integer`

Creates a body in a world.

- pWorld: A world handle from `b3WorldCreate`.
- pType: The body type: 0 static, 1 kinematic, 2 dynamic.
- pX: The x of its position, in metres.
- pY: The y of its position.
- pZ: The z of its position.

Returns: A body handle, or 0 if the arguments were refused.

A static body never moves (floors, walls); a kinematic body moves only as it is told; a dynamic body is moved by forces and collisions. A body has no size until it is given shapes with the b3ShapeAdd calls, and a dynamic body has no mass until then: give a body its shapes before joining it to another.

```
put b3BodyCreate(sWorld, 2, 0, 5, 0) into tBall
get b3ShapeAddSphere(tBall, 0, 0, 0, 0.5, 1, 0.6, 0.2)
```

### `b3BodyCreateRotated`

`b3BodyCreateRotated(in pWorld as Integer, in pType as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns Integer`

Creates a body in a world, already turned.

- pWorld: A world handle from `b3WorldCreate`.
- pType: The body type: 0 static, 1 kinematic, 2 dynamic.
- pX: The x of its position, in metres.
- pY: The y of its position.
- pZ: The z of its position.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

Returns: A body handle, or 0 if the arguments were refused.

As `b3BodyCreate`, with a starting rotation. `b3QuatFromAxisAngle` and `b3QuatFromEuler` make the quaternion.

### `b3BodyDestroy`

`b3BodyDestroy(in pBody as Integer) returns nothing`

Destroys a body, its shapes and the joints attached to it.

- pBody: A body handle from `b3BodyCreate`.

### `b3BodyIsValid`

`b3BodyIsValid(in pBody as Integer) returns Boolean`

Reports whether a handle names a live body.

- pBody: A body handle from `b3BodyCreate`.

Returns: True for a live body.

### `b3BodyType`

`b3BodyType(in pBody as Integer) returns Integer`

Returns the type of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: 0 static, 1 kinematic, 2 dynamic; -1 for no body.

### `b3BodySetType`

`b3BodySetType(in pBody as Integer, in pType as Integer) returns nothing`

Changes the type of a body.

- pBody: A body handle from `b3BodyCreate`.
- pType: The body type: 0 static, 1 kinematic, 2 dynamic.

### `b3BodyWorld`

`b3BodyWorld(in pBody as Integer) returns Integer`

Returns the world a body is in.

- pBody: A body handle from `b3BodyCreate`.

Returns: The world handle, or 0.

### `b3BodyPosition`

`b3BodyPosition(in pBody as Integer) returns String`

Returns the position of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: The three numbers as text, "x,y,z".

### `b3BodyX`

`b3BodyX(in pBody as Integer) returns Number`

Returns the x of a body's position.

- pBody: A body handle from `b3BodyCreate`.

Returns: Metres.

### `b3BodyY`

`b3BodyY(in pBody as Integer) returns Number`

Returns the y of a body's position.

- pBody: A body handle from `b3BodyCreate`.

Returns: Metres.

### `b3BodyZ`

`b3BodyZ(in pBody as Integer) returns Number`

Returns the z of a body's position.

- pBody: A body handle from `b3BodyCreate`.

Returns: Metres.

### `b3BodyRotation`

`b3BodyRotation(in pBody as Integer) returns String`

Returns the rotation of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: The quaternion as text, "x,y,z,w".

### `b3BodyTransform`

`b3BodyTransform(in pBody as Integer) returns String`

Returns the position and rotation of a body in one call.

- pBody: A body handle from `b3BodyCreate`.

Returns: Seven numbers as text, "x,y,z,qx,qy,qz,qw".

### `b3BodyMatrix`

`b3BodyMatrix(in pBody as Integer) returns String`

Returns the position and rotation of a body as a matrix.

- pBody: A body handle from `b3BodyCreate`.

Returns: Twelve numbers as text: the three columns of the rotation matrix (x axis, y axis, z axis), then the position.

For renderers that take a matrix: the first nine numbers are where the body's own x, y and z axes point in the world.

### `b3BodySetTransform`

`b3BodySetTransform(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Moves a body to a position and rotation at once.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x coordinate.
- pY: The y coordinate.
- pZ: The z coordinate.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

A teleport: it does not sweep, so it can put a body inside another. To move a kinematic body smoothly, use `b3BodySetTargetTransform` or a velocity.

### `b3BodySetPosition`

`b3BodySetPosition(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Moves a body to a position, keeping its rotation.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x coordinate.
- pY: The y coordinate.
- pZ: The z coordinate.

### `b3BodySetRotation`

`b3BodySetRotation(in pBody as Integer, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Turns a body to a rotation, keeping its position.

- pBody: A body handle from `b3BodyCreate`.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

### `b3BodySetTargetTransform`

`b3BodySetTargetTransform(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number, in pSeconds as Number, in pWake as Boolean) returns nothing`

Gives a body the velocity that will bring it to a position and rotation.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x coordinate.
- pY: The y coordinate.
- pZ: The z coordinate.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.
- pSeconds: How long the move should take, in seconds: the step time, for a move finished next step.
- pWake: True to wake the body if it is asleep.

The way to drive a kinematic body (a lift, a moving platform): it arrives by moving, so it carries and pushes what it meets.

### `b3BodyVelocity`

`b3BodyVelocity(in pBody as Integer) returns String`

Returns the linear velocity of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: The three numbers as text, "x,y,z".

### `b3BodyAngularVelocity`

`b3BodyAngularVelocity(in pBody as Integer) returns String`

Returns the angular velocity of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: Three numbers as text, "x,y,z", in radians per second about each world axis.

### `b3BodySpeed`

`b3BodySpeed(in pBody as Integer) returns Number`

Returns how fast a body is moving.

- pBody: A body handle from `b3BodyCreate`.

Returns: The speed in m/s.

### `b3BodySetVelocity`

`b3BodySetVelocity(in pBody as Integer, in pVx as Number, in pVy as Number, in pVz as Number) returns nothing`

Sets the linear velocity of a body.

- pBody: A body handle from `b3BodyCreate`.
- pVx: The x component, in m/s.
- pVy: The y component, in m/s.
- pVz: The z component, in m/s.

### `b3BodySetAngularVelocity`

`b3BodySetAngularVelocity(in pBody as Integer, in pWx as Number, in pWy as Number, in pWz as Number) returns nothing`

Sets the angular velocity of a body.

- pBody: A body handle from `b3BodyCreate`.
- pWx: The x component, in radians per second.
- pWy: The y component, in radians per second.
- pWz: The z component, in radians per second.

### `b3BodyApplyForce`

`b3BodyApplyForce(in pBody as Integer, in pFx as Number, in pFy as Number, in pFz as Number, in pPx as Number, in pPy as Number, in pPz as Number, in pWake as Boolean) returns nothing`

Pushes a body at a point for the next step.

- pBody: A body handle from `b3BodyCreate`.
- pFx: The x component of the force, in newtons.
- pFy: The y component of the force.
- pFz: The z component of the force.
- pPx: The x of the point, in world coordinates.
- pPy: The y of the point, in world coordinates.
- pPz: The z of the point, in world coordinates.
- pWake: True to wake the body if it is asleep.

A force acts over time: apply it every step while it should last. A force off the centre of mass also turns the body.

### `b3BodyApplyForceToCenter`

`b3BodyApplyForceToCenter(in pBody as Integer, in pFx as Number, in pFy as Number, in pFz as Number, in pWake as Boolean) returns nothing`

Pushes a body at its centre of mass for the next step.

- pBody: A body handle from `b3BodyCreate`.
- pFx: The x component of the force, in newtons.
- pFy: The y component of the force.
- pFz: The z component of the force.
- pWake: True to wake the body if it is asleep.

### `b3BodyApplyTorque`

`b3BodyApplyTorque(in pBody as Integer, in pTx as Number, in pTy as Number, in pTz as Number, in pWake as Boolean) returns nothing`

Twists a body for the next step.

- pBody: A body handle from `b3BodyCreate`.
- pTx: The x component of the torque, in newton metres.
- pTy: The y component of the torque.
- pTz: The z component of the torque.
- pWake: True to wake the body if it is asleep.

### `b3BodyApplyImpulse`

`b3BodyApplyImpulse(in pBody as Integer, in pIx as Number, in pIy as Number, in pIz as Number, in pPx as Number, in pPy as Number, in pPz as Number, in pWake as Boolean) returns nothing`

Kicks a body at a point, changing its velocity at once.

- pBody: A body handle from `b3BodyCreate`.
- pIx: The x component of the impulse.
- pIy: The y component of the impulse.
- pIz: The z component of the impulse.
- pPx: The x of the point, in world coordinates.
- pPy: The y of the point, in world coordinates.
- pPz: The z of the point, in world coordinates.
- pWake: True to wake the body if it is asleep.

An impulse is a one-off: a jump, a hit, a shot.

### `b3BodyApplyImpulseToCenter`

`b3BodyApplyImpulseToCenter(in pBody as Integer, in pIx as Number, in pIy as Number, in pIz as Number, in pWake as Boolean) returns nothing`

Kicks a body at its centre of mass, changing its velocity at once.

- pBody: A body handle from `b3BodyCreate`.
- pIx: The x component of the impulse.
- pIy: The y component of the impulse.
- pIz: The z component of the impulse.
- pWake: True to wake the body if it is asleep.

### `b3BodyApplyAngularImpulse`

`b3BodyApplyAngularImpulse(in pBody as Integer, in pIx as Number, in pIy as Number, in pIz as Number, in pWake as Boolean) returns nothing`

Spins a body, changing its angular velocity at once.

- pBody: A body handle from `b3BodyCreate`.
- pIx: The x component of the impulse.
- pIy: The y component of the impulse.
- pIz: The z component of the impulse.
- pWake: True to wake the body if it is asleep.

### `b3BodyMass`

`b3BodyMass(in pBody as Integer) returns Number`

Returns the mass of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: Kilograms; 0 for a static or kinematic body, or a dynamic one with no shapes.

### `b3BodyApplyMassFromShapes`

`b3BodyApplyMassFromShapes(in pBody as Integer) returns nothing`

Recomputes a body's mass from its shapes.

- pBody: A body handle from `b3BodyCreate`.

Only needed after shapes were added, removed or re-weighed with the update put off.

### `b3BodyLocalCenter`

`b3BodyLocalCenter(in pBody as Integer) returns String`

Returns a body's centre of mass in its own coordinates.

- pBody: A body handle from `b3BodyCreate`.

Returns: The three numbers as text, "x,y,z".

### `b3BodyWorldCenter`

`b3BodyWorldCenter(in pBody as Integer) returns String`

Returns a body's centre of mass in world coordinates.

- pBody: A body handle from `b3BodyCreate`.

Returns: The three numbers as text, "x,y,z".

### `b3BodyLocalPoint`

`b3BodyLocalPoint(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Converts a world point into a body's own coordinates.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x of the world point.
- pY: The y of the world point.
- pZ: The z of the world point.

Returns: The three numbers as text, "x,y,z".

### `b3BodyWorldPoint`

`b3BodyWorldPoint(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Converts a point in a body's own coordinates into a world point.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x of the point, in the body's coordinates.
- pY: The y of the point.
- pZ: The z of the point.

Returns: The three numbers as text, "x,y,z".

### `b3BodyLocalVector`

`b3BodyLocalVector(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Converts a world direction into a body's own coordinates.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x of the world direction.
- pY: The y of the world direction.
- pZ: The z of the world direction.

Returns: The three numbers as text, "x,y,z".

### `b3BodyWorldVector`

`b3BodyWorldVector(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Converts a direction in a body's own coordinates into a world direction.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x of the direction, in the body's coordinates.
- pY: The y of the direction.
- pZ: The z of the direction.

Returns: The three numbers as text, "x,y,z".

### `b3BodyPointVelocity`

`b3BodyPointVelocity(in pBody as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Returns how fast a point of a body is moving.

- pBody: A body handle from `b3BodyCreate`.
- pX: The x of the world point.
- pY: The y of the world point.
- pZ: The z of the world point.

Returns: The three numbers as text, "x,y,z".

### `b3BodySetLinearDamping`

`b3BodySetLinearDamping(in pBody as Integer, in pValue as Number) returns nothing`

Sets how quickly a body's movement dies away.

- pBody: A body handle from `b3BodyCreate`.
- pValue: The damping, 0 (none) or more.

### `b3BodyLinearDamping`

`b3BodyLinearDamping(in pBody as Integer) returns Number`

Returns how quickly a body's movement dies away.

- pBody: A body handle from `b3BodyCreate`.

Returns: The damping.

### `b3BodySetAngularDamping`

`b3BodySetAngularDamping(in pBody as Integer, in pValue as Number) returns nothing`

Sets how quickly a body's spin dies away.

- pBody: A body handle from `b3BodyCreate`.
- pValue: The damping, 0 (none) or more.

### `b3BodyAngularDamping`

`b3BodyAngularDamping(in pBody as Integer) returns Number`

Returns how quickly a body's spin dies away.

- pBody: A body handle from `b3BodyCreate`.

Returns: The damping.

### `b3BodySetGravityScale`

`b3BodySetGravityScale(in pBody as Integer, in pValue as Number) returns nothing`

Sets how strongly gravity pulls on one body.

- pBody: A body handle from `b3BodyCreate`.
- pValue: 1 is normal, 0 floats, a negative number falls upwards.

### `b3BodyGravityScale`

`b3BodyGravityScale(in pBody as Integer) returns Number`

Returns how strongly gravity pulls on a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: The scale.

### `b3BodyIsAwake`

`b3BodyIsAwake(in pBody as Integer) returns Boolean`

Reports whether a body is awake.

- pBody: A body handle from `b3BodyCreate`.

Returns: True if it is awake.

### `b3BodySetAwake`

`b3BodySetAwake(in pBody as Integer, in pFlag as Boolean) returns nothing`

Wakes a body or puts it to sleep.

- pBody: A body handle from `b3BodyCreate`.
- pFlag: True to wake it, false to put it (and everything resting on it) to sleep.

A body cannot be put to sleep in the same frame that any body of its world was enabled (`b3BodyEnable`) or had its type changed (`b3BodySetType`): step the world once first. Until then the call does nothing and `b3LastError` says why.

### `b3BodyEnableSleep`

`b3BodyEnableSleep(in pBody as Integer, in pFlag as Boolean) returns nothing`

Lets one body sleep, or keeps it awake for good.

- pBody: A body handle from `b3BodyCreate`.
- pFlag: True to turn it on, false to turn it off.

### `b3BodyIsSleepEnabled`

`b3BodyIsSleepEnabled(in pBody as Integer) returns Boolean`

Reports whether a body may sleep.

- pBody: A body handle from `b3BodyCreate`.

Returns: True if it may.

### `b3BodySetSleepThreshold`

`b3BodySetSleepThreshold(in pBody as Integer, in pValue as Number) returns nothing`

Sets the speed below which a body may fall asleep.

- pBody: A body handle from `b3BodyCreate`.
- pValue: The speed in m/s, 0 or more.

### `b3BodySleepThreshold`

`b3BodySleepThreshold(in pBody as Integer) returns Number`

Returns the speed below which a body may fall asleep.

- pBody: A body handle from `b3BodyCreate`.

Returns: The speed in m/s.

### `b3BodyIsEnabled`

`b3BodyIsEnabled(in pBody as Integer) returns Boolean`

Reports whether a body takes part in the simulation.

- pBody: A body handle from `b3BodyCreate`.

Returns: True if it does.

### `b3BodyEnable`

`b3BodyEnable(in pBody as Integer) returns nothing`

Puts a disabled body back into the simulation.

- pBody: A body handle from `b3BodyCreate`.

### `b3BodyDisable`

`b3BodyDisable(in pBody as Integer) returns nothing`

Takes a body out of the simulation without destroying it.

- pBody: A body handle from `b3BodyCreate`.

A disabled body does not move, collide or show up in queries. Cheaper than destroying and re-creating it.

### `b3BodySetBullet`

`b3BodySetBullet(in pBody as Integer, in pFlag as Boolean) returns nothing`

Gives a fast, small body continuous collision against other moving bodies.

- pBody: A body handle from `b3BodyCreate`.
- pFlag: True to turn it on, false to turn it off.

Costly: use it for the few bodies that need it. Continuous collision against static geometry is always on.

### `b3BodyIsBullet`

`b3BodyIsBullet(in pBody as Integer) returns Boolean`

Reports whether a body is a bullet.

- pBody: A body handle from `b3BodyCreate`.

Returns: True if it is.

### `b3BodySetMotionLocks`

`b3BodySetMotionLocks(in pBody as Integer, in pLx as Boolean, in pLy as Boolean, in pLz as Boolean, in pAx as Boolean, in pAy as Boolean, in pAz as Boolean) returns nothing`

Locks a body's movement along, or rotation about, chosen world axes.

- pBody: A body handle from `b3BodyCreate`.
- pLx: True to stop movement along x.
- pLy: True to stop movement along y.
- pLz: True to stop movement along z.
- pAx: True to stop rotation about x.
- pAy: True to stop rotation about y.
- pAz: True to stop rotation about z.

Locking z movement and x and y rotation keeps a body in a 2D plane; locking all three rotations keeps a character upright. The body is woken.

### `b3BodyMotionLocks`

`b3BodyMotionLocks(in pBody as Integer) returns String`

Returns which of a body's motions are locked.

- pBody: A body handle from `b3BodyCreate`.

Returns: Six numbers as text, each 0 or 1: "lx,ly,lz,ax,ay,az".

### `b3BodyEnableHitEvents`

`b3BodyEnableHitEvents(in pBody as Integer, in pFlag as Boolean) returns nothing`

Turns hit events on or off for every shape of a body.

- pBody: A body handle from `b3BodyCreate`.
- pFlag: True to turn it on, false to turn it off.

### `b3BodyAABB`

`b3BodyAABB(in pBody as Integer) returns String`

Returns the box that holds a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: Six numbers as text, "lowerX,lowerY,lowerZ,upperX,upperY,upperZ".

### `b3BodyShapeCount`

`b3BodyShapeCount(in pBody as Integer) returns Integer`

Returns how many shapes a body carries.

- pBody: A body handle from `b3BodyCreate`.

Returns: The count.

### `b3BodyJointCount`

`b3BodyJointCount(in pBody as Integer) returns Integer`

Returns how many joints are attached to a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: The count.

## Handle lists

### `b3ListCount`

`b3ListCount() returns Integer`

Returns how many handles the last list call found.

Returns: The count.

The list calls (`b3BodyListShapes`, `b3BodyListJoints`, `b3BodyListTouching`, `b3ShapeListSensorVisitors`, `b3OverlapAABB`, `b3OverlapSphere`) each replace one shared list, read back with `b3ListItem`.

### `b3ListItem`

`b3ListItem(in pIndex as Integer) returns Integer`

Returns one handle of the last list.

- pIndex: Which item, counted from 1.

Returns: The handle, or 0 if the index is out of range.

### `b3BodyListShapes`

`b3BodyListShapes(in pBody as Integer) returns Integer`

Lists the shapes of a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: How many; read them with `b3ListItem`.

### `b3BodyListJoints`

`b3BodyListJoints(in pBody as Integer) returns Integer`

Lists the joints attached to a body.

- pBody: A body handle from `b3BodyCreate`.

Returns: How many; read them with `b3ListItem`.

### `b3BodyListTouching`

`b3BodyListTouching(in pBody as Integer) returns Integer`

Lists the bodies a body is touching right now.

- pBody: A body handle from `b3BodyCreate`.

Returns: How many; read them with `b3ListItem`.

## Shape options and geometry

### `b3ShapeOptionsReset`

`b3ShapeOptionsReset() returns nothing`

Puts the shape options back to Box3D's defaults.

The options (sensor, events, filter, rolling resistance) apply to every shape made after they are set, until this is called. The defaults: a solid shape, no events reported, colliding with everything.

### `b3ShapeOptionsSetSensor`

`b3ShapeOptionsSetSensor(in pFlag as Boolean) returns nothing`

Makes the next shapes sensors, or solid.

- pFlag: True for sensors: shapes that detect overlaps and collide with nothing.

A sensor reports nothing unless sensor events are also on, for it and for the shapes it should notice: see `b3ShapeOptionsSetEvents`.

### `b3ShapeOptionsSetEvents`

`b3ShapeOptionsSetEvents(in pContact as Boolean, in pHit as Boolean, in pSensor as Boolean) returns nothing`

Chooses which events the next shapes report.

- pContact: True to report when the shape starts and stops touching another.
- pHit: True to report hard impacts.
- pSensor: True to let the shape be noticed by sensors (and, on a sensor, to report at all).

All three are off by default: an event costs time, so a shape reports only what it is asked to.

### `b3ShapeOptionsSetFilter`

`b3ShapeOptionsSetFilter(in pCategory as Number, in pMask as Number, in pGroup as Integer) returns nothing`

Sets the collision filter of the next shapes.

- pCategory: The category bits, a whole number from 0 to 2^53 - 1.
- pMask: The mask bits: the categories this one meets.
- pGroup: The group index: shapes sharing a positive group always collide, a negative one never.

Two shapes collide when each one's mask includes the other's category.

### `b3ShapeOptionsSetRollingResistance`

`b3ShapeOptionsSetRollingResistance(in pValue as Number) returns nothing`

Sets the rolling resistance of the next shapes.

- pValue: The resistance, 0 (none) or more. A little makes a ball stop rolling.

### `b3GeometryBegin`

`b3GeometryBegin() returns nothing`

Starts a new set of points, triangles and heights.

`b3ShapeAddHull`, `b3ShapeAddMesh` and `b3ShapeAddHeightField` are built from what is added after this.

### `b3GeometryAddPoint`

`b3GeometryAddPoint(in pX as Number, in pY as Number, in pZ as Number) returns Integer`

Adds a point to the geometry being built.

- pX: The x of the point, within 10000.
- pY: The y of the point.
- pZ: The z of the point.

Returns: The number of the point (1 for the first), or 0 if it was refused.

### `b3GeometryAddTriangle`

`b3GeometryAddTriangle(in pPointA as Integer, in pPointB as Integer, in pPointC as Integer) returns Integer`

Adds a triangle to the geometry being built.

- pPointA: The number of its first point.
- pPointB: The number of its second point.
- pPointC: The number of its third point.

Returns: How many triangles there are now, or 0 if it was refused.

Name the points counter-clockwise as seen from outside: that is the side things collide with.

### `b3GeometryAddHeight`

`b3GeometryAddHeight(in pHeight as Number) returns Integer`

Adds one height to the geometry being built.

- pHeight: The height, within 10000.

Returns: How many heights there are now, or 0 if it was refused.

### `b3GeometryPointCount`

`b3GeometryPointCount() returns Integer`

Returns how many points have been added.

Returns: The count.

## Shapes

### `b3ShapeAddSphere`

`b3ShapeAddSphere(in pBody as Integer, in pCx as Number, in pCy as Number, in pCz as Number, in pRadius as Number, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a sphere to a body.

- pBody: A body handle from `b3BodyCreate`.
- pCx: The x of its centre, in the body's coordinates.
- pCy: The y of its centre.
- pCz: The z of its centre.
- pRadius: The radius in metres, 0.001 to 10000.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

```
get b3ShapeAddSphere(tBall, 0, 0, 0, 0.5, 1, 0.6, 0.2)
```

### `b3ShapeAddCapsule`

`b3ShapeAddCapsule(in pBody as Integer, in pX1 as Number, in pY1 as Number, in pZ1 as Number, in pX2 as Number, in pY2 as Number, in pZ2 as Number, in pRadius as Number, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a capsule (a cylinder with round ends) to a body.

- pBody: A body handle from `b3BodyCreate`.
- pX1: The x of the centre of one end, in the body's coordinates.
- pY1: The y of that end.
- pZ1: The z of that end.
- pX2: The x of the centre of the other end.
- pY2: The y of the other end.
- pZ2: The z of the other end.
- pRadius: The radius in metres, 0.001 to 10000.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3ShapeAddBox`

`b3ShapeAddBox(in pBody as Integer, in pHx as Number, in pHy as Number, in pHz as Number, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a box to a body, centred on it.

- pBody: A body handle from `b3BodyCreate`.
- pHx: Half the width (along x) in metres, 0.001 to 10000.
- pHy: Half the height (along y).
- pHz: Half the depth (along z).
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3ShapeAddBoxAt`

`b3ShapeAddBoxAt(in pBody as Integer, in pHx as Number, in pHy as Number, in pHz as Number, in pOx as Number, in pOy as Number, in pOz as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a box to a body, placed and turned inside it.

- pBody: A body handle from `b3BodyCreate`.
- pHx: Half the width (along x) in metres, 0.001 to 10000.
- pHy: Half the height (along y).
- pHz: Half the depth (along z).
- pOx: The x of the box's centre, in the body's coordinates.
- pOy: The y of its centre.
- pOz: The z of its centre.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3ShapeAddCylinder`

`b3ShapeAddCylinder(in pBody as Integer, in pHeight as Number, in pRadius as Number, in pSides as Integer, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a cylinder to a body, standing along y and centred on it.

- pBody: A body handle from `b3BodyCreate`.
- pHeight: The height (along y) in metres, 0.001 to 10000.
- pRadius: The radius in metres, 0.001 to 10000.
- pSides: How many flat sides approximate the round face, 3 to 32.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3ShapeAddCone`

`b3ShapeAddCone(in pBody as Integer, in pHeight as Number, in pRadius1 as Number, in pRadius2 as Number, in pSides as Integer, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a cone (or a tapered cylinder) to a body, standing along y.

- pBody: A body handle from `b3BodyCreate`.
- pHeight: The height (along y) in metres, 0.001 to 10000.
- pRadius1: The radius at the bottom, 0.001 to 10000.
- pRadius2: The radius at the top. Box3D needs both above 0: use a small one for a point.
- pSides: How many flat sides approximate the round face, 4 to 32.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3ShapeAddHull`

`b3ShapeAddHull(in pBody as Integer, in pDensity as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds the convex hull of the points added since `b3GeometryBegin`.

- pBody: A body handle from `b3BodyCreate`.
- pDensity: The shape's density in kg per cubic metre, 0 to 1000000. 0 gives the shape no mass.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

Needs at least 4 points that are not all in one plane. The hull is the tightest convex solid around them, SIMPLIFIED to what Box3D can hold: at most 128 corners, 128 faces and 128 edges. A boxy shape keeps its corners; the points of a rounded model (thousands are fine) come down to about 40, so the hull lies a little inside the model. A hull is convex: a hollow, a handle or a spout is filled in. For a concave moving object, add several hulls to one body.

### `b3ShapeAddMesh`

`b3ShapeAddMesh(in pBody as Integer, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a triangle mesh built from the points and triangles added since `b3GeometryBegin`.

- pBody: A body handle from `b3BodyCreate`.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

For static scenery only: the body must be static. A mesh may be concave and may hold many thousands of triangles, such as a model read from a file. It is ONE-SIDED: a triangle stops bodies and rays that meet its front, the side from which its three points run counter-clockwise, and lets through whatever comes from behind. Models are normally exported with their fronts facing out; if things fall through one, its triangles are wound the other way, so swap two points of each.

### `b3ShapeAddHeightField`

`b3ShapeAddHeightField(in pBody as Integer, in pCountX as Integer, in pCountZ as Integer, in pSx as Number, in pSy as Number, in pSz as Number, in pFriction as Number, in pRestitution as Number) returns Integer`

Adds a terrain built from the heights added since `b3GeometryBegin`.

- pBody: A body handle from `b3BodyCreate`.
- pCountX: How many heights there are along x, 2 to 4096.
- pCountZ: How many rows there are along z, 2 to 4096.
- pSx: The spacing between heights along x, in metres.
- pSy: What each height is multiplied by.
- pSz: The spacing between rows along z.
- pFriction: The friction coefficient, 0 or more (0.6 is a good default).
- pRestitution: The bounciness, 0 (none) to 1 (full).

Returns: A shape handle, or 0 if the arguments were refused (see `b3LastError`).

For static scenery only: the body must be static. Add countX times countZ heights, row by row.

### `b3ShapeDestroy`

`b3ShapeDestroy(in pShape as Integer, in pUpdateMass as Boolean) returns nothing`

Removes a shape from its body.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pUpdateMass: True to recompute the body's mass now; false to put it off until `b3BodyApplyMassFromShapes`.

### `b3ShapeIsValid`

`b3ShapeIsValid(in pShape as Integer) returns Boolean`

Reports whether a handle names a live shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: True for a live shape.

### `b3ShapeType`

`b3ShapeType(in pShape as Integer) returns Integer`

Returns what kind of shape a handle names.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: 0 capsule, 1 compound, 2 height field, 3 hull (boxes, cylinders and cones are hulls), 4 mesh, 5 sphere; -1 for no shape.

### `b3ShapeBody`

`b3ShapeBody(in pShape as Integer) returns Integer`

Returns the body a shape belongs to.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: The body handle, or 0.

### `b3ShapeIsSensor`

`b3ShapeIsSensor(in pShape as Integer) returns Boolean`

Reports whether a shape is a sensor.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: True if it is.

### `b3ShapeSetDensity`

`b3ShapeSetDensity(in pShape as Integer, in pValue as Number, in pUpdateMass as Boolean) returns nothing`

Changes the density of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pValue: The density in kg per cubic metre, 0 to 1000000.
- pUpdateMass: True to recompute the body's mass now; false to put it off until `b3BodyApplyMassFromShapes`.

### `b3ShapeDensity`

`b3ShapeDensity(in pShape as Integer) returns Number`

Returns the density of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: Kilograms per cubic metre.

### `b3ShapeSetFriction`

`b3ShapeSetFriction(in pShape as Integer, in pValue as Number) returns nothing`

Changes the friction of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pValue: The friction coefficient, 0 or more.

### `b3ShapeFriction`

`b3ShapeFriction(in pShape as Integer) returns Number`

Returns the friction of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: The coefficient.

### `b3ShapeSetRestitution`

`b3ShapeSetRestitution(in pShape as Integer, in pValue as Number) returns nothing`

Changes the bounciness of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pValue: The restitution, 0 (none) to 1 (full).

### `b3ShapeRestitution`

`b3ShapeRestitution(in pShape as Integer) returns Number`

Returns the bounciness of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: The restitution.

### `b3ShapeSetRollingResistance`

`b3ShapeSetRollingResistance(in pShape as Integer, in pValue as Number) returns nothing`

Changes the rolling resistance of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pValue: The resistance, 0 or more.

### `b3ShapeRollingResistance`

`b3ShapeRollingResistance(in pShape as Integer) returns Number`

Returns the rolling resistance of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: The resistance.

### `b3ShapeSetFilter`

`b3ShapeSetFilter(in pShape as Integer, in pCategory as Number, in pMask as Number, in pGroup as Integer) returns nothing`

Changes the collision filter of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pCategory: The category bits, a whole number from 0 to 2^53 - 1.
- pMask: The mask bits: the categories this one meets.
- pGroup: The group index: shapes sharing a positive group always collide, a negative one never.

### `b3ShapeFilter`

`b3ShapeFilter(in pShape as Integer) returns String`

Returns the collision filter of a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: Three numbers as text, "category,mask,group".

### `b3ShapeEnableContactEvents`

`b3ShapeEnableContactEvents(in pShape as Integer, in pFlag as Boolean) returns nothing`

Turns begin and end touch events on or off for a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pFlag: True to turn it on, false to turn it off.

### `b3ShapeAreContactEventsEnabled`

`b3ShapeAreContactEventsEnabled(in pShape as Integer) returns Boolean`

Reports whether a shape reports begin and end touch events.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: True if it does.

### `b3ShapeEnableHitEvents`

`b3ShapeEnableHitEvents(in pShape as Integer, in pFlag as Boolean) returns nothing`

Turns hit events on or off for a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pFlag: True to turn it on, false to turn it off.

### `b3ShapeAreHitEventsEnabled`

`b3ShapeAreHitEventsEnabled(in pShape as Integer) returns Boolean`

Reports whether a shape reports hit events.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: True if it does.

### `b3ShapeEnableSensorEvents`

`b3ShapeEnableSensorEvents(in pShape as Integer, in pFlag as Boolean) returns nothing`

Turns sensor events on or off for a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pFlag: True to turn it on, false to turn it off.

### `b3ShapeAreSensorEventsEnabled`

`b3ShapeAreSensorEventsEnabled(in pShape as Integer) returns Boolean`

Reports whether a shape takes part in sensor events.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: True if it does.

### `b3ShapeAABB`

`b3ShapeAABB(in pShape as Integer) returns String`

Returns the box that holds a shape.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: Six numbers as text, "lowerX,lowerY,lowerZ,upperX,upperY,upperZ".

### `b3ShapeClosestPoint`

`b3ShapeClosestPoint(in pShape as Integer, in pX as Number, in pY as Number, in pZ as Number) returns String`

Returns the point of a shape nearest to a world point.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pX: The x of the world point.
- pY: The y of the world point.
- pZ: The z of the world point.

Returns: The three numbers as text, "x,y,z".

### `b3ShapeListSensorVisitors`

`b3ShapeListSensorVisitors(in pShape as Integer) returns Integer`

Lists the shapes that are inside a sensor right now.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: How many; read them with `b3ListItem`.

## Ray casts and overlap queries

### `b3QuerySetFilter`

`b3QuerySetFilter(in pCategory as Number, in pMask as Number) returns nothing`

Limits the ray casts and overlap queries that follow to some categories.

- pCategory: The category bits, a whole number from 0 to 2^53 - 1.
- pMask: The mask bits: the categories this one meets.

A query sees a shape when the query's mask includes the shape's category and the shape's mask includes the query's category. Stays in force until `b3QueryResetFilter`.

### `b3QueryResetFilter`

`b3QueryResetFilter() returns nothing`

Lets ray casts and overlap queries see every shape again.

### `b3CastRay`

`b3CastRay(in pWorld as Integer, in pOx as Number, in pOy as Number, in pOz as Number, in pDx as Number, in pDy as Number, in pDz as Number) returns Integer`

Casts a ray through a world and collects everything it passes through.

- pWorld: A world handle from `b3WorldCreate`.
- pOx: The x of the start point.
- pOy: The y of the start point.
- pOz: The z of the start point.
- pDx: The x of the travel: how far, not a direction.
- pDy: The y of the travel.
- pDz: The z of the travel.

Returns: How many shapes were hit; read them, nearest first, with `b3HitShape`, `b3HitBody`, `b3HitFraction`, `b3HitPoint` and `b3HitNormal`.

```
if b3CastRay(sWorld, 0, 10, 0, 0, -20, 0) > 0 then
put b3HitBody(1) into tFirstBodyBelow
end if
```

### `b3CastRayClosest`

`b3CastRayClosest(in pWorld as Integer, in pOx as Number, in pOy as Number, in pOz as Number, in pDx as Number, in pDy as Number, in pDz as Number) returns Integer`

Casts a ray through a world and keeps only the first thing it hits.

- pWorld: A world handle from `b3WorldCreate`.
- pOx: The x of the start point.
- pOy: The y of the start point.
- pOz: The z of the start point.
- pDx: The x of the travel: how far, not a direction.
- pDy: The y of the travel.
- pDz: The z of the travel.

Returns: 1 if something was hit (read it as hit 1), else 0.

### `b3CastSphere`

`b3CastSphere(in pWorld as Integer, in pOx as Number, in pOy as Number, in pOz as Number, in pRadius as Number, in pDx as Number, in pDy as Number, in pDz as Number) returns Integer`

Sweeps a sphere through a world and collects everything it touches.

- pWorld: A world handle from `b3WorldCreate`.
- pOx: The x of the start point.
- pOy: The y of the start point.
- pOz: The z of the start point.
- pRadius: The radius of the swept sphere, in metres.
- pDx: The x of the travel: how far, not a direction.
- pDy: The y of the travel.
- pDz: The z of the travel.

Returns: How many shapes were hit; read them, nearest first, with `b3HitShape`, `b3HitBody`, `b3HitFraction`, `b3HitPoint` and `b3HitNormal`.

### `b3HitCount`

`b3HitCount() returns Integer`

Returns how many hits the last cast found.

Returns: The count.

### `b3HitShape`

`b3HitShape(in pIndex as Integer) returns Integer`

Returns the shape of one hit of the last cast.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3HitBody`

`b3HitBody(in pIndex as Integer) returns Integer`

Returns the body of one hit of the last cast.

- pIndex: Which item, counted from 1.

Returns: The body handle, or 0.

### `b3HitFraction`

`b3HitFraction(in pIndex as Integer) returns Number`

Returns how far along the cast one hit was.

- pIndex: Which item, counted from 1.

Returns: 0 at the start of the cast, 1 at its end.

### `b3HitPoint`

`b3HitPoint(in pIndex as Integer) returns String`

Returns where one hit of the last cast was.

- pIndex: Which item, counted from 1.

Returns: The three numbers as text, "x,y,z".

### `b3HitNormal`

`b3HitNormal(in pIndex as Integer) returns String`

Returns which way the surface faces at one hit of the last cast.

- pIndex: Which item, counted from 1.

Returns: A unit direction as text, "x,y,z".

### `b3OverlapAABB`

`b3OverlapAABB(in pWorld as Integer, in pLx as Number, in pLy as Number, in pLz as Number, in pUx as Number, in pUy as Number, in pUz as Number) returns Integer`

Lists the shapes whose boxes overlap a box.

- pWorld: A world handle from `b3WorldCreate`.
- pLx: The lowest x of the box.
- pLy: The lowest y.
- pLz: The lowest z.
- pUx: The highest x of the box.
- pUy: The highest y.
- pUz: The highest z.

Returns: How many; read them with `b3ListItem`.

### `b3OverlapSphere`

`b3OverlapSphere(in pWorld as Integer, in pX as Number, in pY as Number, in pZ as Number, in pRadius as Number) returns Integer`

Lists the shapes that overlap a sphere.

- pWorld: A world handle from `b3WorldCreate`.
- pX: The x of its centre.
- pY: The y of its centre.
- pZ: The z of its centre.
- pRadius: The radius in metres, 0.001 to 10000.

Returns: How many; read them with `b3ListItem`.

## Events

### `b3WorldUpdateContactEvents`

`b3WorldUpdateContactEvents(in pWorld as Integer) returns Integer`

Collects the touch and hit events of the last step.

- pWorld: A world handle from `b3WorldCreate`.

Returns: How many events there are in all.

Call it once after `b3WorldStep`, then read the begin, end and hit lists. Only shapes with those events turned on appear (`b3ShapeOptionsSetEvents`).

### `b3ContactBeginCount`

`b3ContactBeginCount() returns Integer`

Returns how many pairs of shapes started touching in the last step.

Returns: The count.

### `b3ContactBeginShapeA`

`b3ContactBeginShapeA(in pIndex as Integer) returns Integer`

Returns the first shape of a pair that started touching.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3ContactBeginShapeB`

`b3ContactBeginShapeB(in pIndex as Integer) returns Integer`

Returns the second shape of a pair that started touching.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3ContactEndCount`

`b3ContactEndCount() returns Integer`

Returns how many pairs of shapes stopped touching in the last step.

Returns: The count.

### `b3ContactEndShapeA`

`b3ContactEndShapeA(in pIndex as Integer) returns Integer`

Returns the first shape of a pair that stopped touching.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0 (also when the shape has since been destroyed).

### `b3ContactEndShapeB`

`b3ContactEndShapeB(in pIndex as Integer) returns Integer`

Returns the second shape of a pair that stopped touching.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3ContactHitCount`

`b3ContactHitCount() returns Integer`

Returns how many hard impacts the last step had.

Returns: The count.

### `b3ContactHitShapeA`

`b3ContactHitShapeA(in pIndex as Integer) returns Integer`

Returns the first shape of an impact.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3ContactHitShapeB`

`b3ContactHitShapeB(in pIndex as Integer) returns Integer`

Returns the second shape of an impact.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3ContactHitSpeed`

`b3ContactHitSpeed(in pIndex as Integer) returns Number`

Returns how fast two shapes met in an impact.

- pIndex: Which item, counted from 1.

Returns: The approach speed in m/s.

### `b3ContactHitPoint`

`b3ContactHitPoint(in pIndex as Integer) returns String`

Returns where an impact happened.

- pIndex: Which item, counted from 1.

Returns: The three numbers as text, "x,y,z".

### `b3ContactHitNormal`

`b3ContactHitNormal(in pIndex as Integer) returns String`

Returns the direction of an impact, from the first shape to the second.

- pIndex: Which item, counted from 1.

Returns: A unit direction as text, "x,y,z".

### `b3WorldUpdateSensorEvents`

`b3WorldUpdateSensorEvents(in pWorld as Integer) returns Integer`

Collects the sensor events of the last step.

- pWorld: A world handle from `b3WorldCreate`.

Returns: How many events there are in all.

Call it once after `b3WorldStep`, then read the begin and end lists.

### `b3SensorBeginCount`

`b3SensorBeginCount() returns Integer`

Returns how many shapes entered a sensor in the last step.

Returns: The count.

### `b3SensorBeginSensor`

`b3SensorBeginSensor(in pIndex as Integer) returns Integer`

Returns the sensor that something entered.

- pIndex: Which item, counted from 1.

Returns: The sensor shape handle, or 0.

### `b3SensorBeginVisitor`

`b3SensorBeginVisitor(in pIndex as Integer) returns Integer`

Returns the shape that entered a sensor.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3SensorEndCount`

`b3SensorEndCount() returns Integer`

Returns how many shapes left a sensor in the last step.

Returns: The count.

### `b3SensorEndSensor`

`b3SensorEndSensor(in pIndex as Integer) returns Integer`

Returns the sensor that something left.

- pIndex: Which item, counted from 1.

Returns: The sensor shape handle, or 0.

### `b3SensorEndVisitor`

`b3SensorEndVisitor(in pIndex as Integer) returns Integer`

Returns the shape that left a sensor.

- pIndex: Which item, counted from 1.

Returns: The shape handle, or 0.

### `b3WorldUpdateMoves`

`b3WorldUpdateMoves(in pWorld as Integer) returns Integer`

Collects every body that moved in the last step.

- pWorld: A world handle from `b3WorldCreate`.

Returns: How many bodies moved.

The cheap way to draw a scene: bodies that are asleep are not listed, so a resting world costs nothing. Read the list with `b3MoveBody` and `b3MoveTransform`, or all of it at once with `b3MovesText`.

### `b3MoveCount`

`b3MoveCount() returns Integer`

Returns how many bodies the last collected move list holds.

Returns: The count.

### `b3MoveBody`

`b3MoveBody(in pIndex as Integer) returns Integer`

Returns the body of one move.

- pIndex: Which item, counted from 1.

Returns: The body handle, or 0.

### `b3MoveFellAsleep`

`b3MoveFellAsleep(in pIndex as Integer) returns Boolean`

Reports whether a moved body fell asleep at the end of the step.

- pIndex: Which item, counted from 1.

Returns: True if it did.

### `b3MoveTransform`

`b3MoveTransform(in pIndex as Integer) returns String`

Returns where one moved body is now.

- pIndex: Which item, counted from 1.

Returns: Seven numbers as text, "x,y,z,qx,qy,qz,qw".

### `b3MovesText`

`b3MovesText() returns String`

Returns the whole move list as text.

Returns: One line per body: "body,x,y,z,qx,qy,qz,qw,fellAsleep".

One call across the boundary for a whole frame, which is what makes thousands of bodies drawable from script.

```
b3WorldStep sWorld, 1/60, 4
get b3WorldUpdateMoves(sWorld)
repeat for each line tMove in b3MovesText()
-- item 1 is the body, items 2 to 4 its position
end repeat
```

### `b3WorldUpdateJointEvents`

`b3WorldUpdateJointEvents(in pWorld as Integer) returns Integer`

Collects the joints whose force or torque passed its threshold in the last step.

- pWorld: A world handle from `b3WorldCreate`.

Returns: How many joints.

Set the thresholds with `b3JointSetForceThreshold` and `b3JointSetTorqueThreshold`: the way to make a joint breakable.

### `b3JointEventCount`

`b3JointEventCount() returns Integer`

Returns how many joints the last collected joint event list holds.

Returns: The count.

### `b3JointEventJoint`

`b3JointEventJoint(in pIndex as Integer) returns Integer`

Returns one joint that passed its threshold.

- pIndex: Which item, counted from 1.

Returns: The joint handle, or 0.

## Rotations

### `b3QuatFromAxisAngle`

`b3QuatFromAxisAngle(in pAx as Number, in pAy as Number, in pAz as Number, in pRadians as Number) returns String`

Makes the rotation of an angle about an axis.

- pAx: The x of the axis.
- pAy: The y of the axis.
- pAz: The z of the axis.
- pRadians: The angle, in radians.

Returns: The quaternion as text, "x,y,z,w".

```
put b3QuatFromAxisAngle(0, 1, 0, pi / 2) into tQuarterTurn
```

### `b3QuatFromEuler`

`b3QuatFromEuler(in pRx as Number, in pRy as Number, in pRz as Number) returns String`

Makes a rotation from three angles.

- pRx: The angle about x, in radians.
- pRy: The angle about y.
- pRz: The angle about z.

Returns: The quaternion as text, "x,y,z,w".

### `b3QuatMultiply`

`b3QuatMultiply(in pAx as Number, in pAy as Number, in pAz as Number, in pAw as Number, in pBx as Number, in pBy as Number, in pBz as Number, in pBw as Number) returns String`

Combines two rotations.

- pAx: The x of the first rotation.
- pAy: The y of the first rotation.
- pAz: The z of the first rotation.
- pAw: The w of the first rotation.
- pBx: The x of the second rotation.
- pBy: The y of the second.
- pBz: The z of the second.
- pBw: The w of the second.

Returns: The quaternion as text, "x,y,z,w".

The result is the second rotation followed by the first.

### `b3QuatRotate`

`b3QuatRotate(in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number, in pX as Number, in pY as Number, in pZ as Number) returns String`

Turns a direction by a rotation.

- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.
- pX: The x of the direction.
- pY: The y of the direction.
- pZ: The z of the direction.

Returns: The three numbers as text, "x,y,z".

### `b3QuatToAxisAngle`

`b3QuatToAxisAngle(in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns String`

Splits a rotation into an axis and an angle.

- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

Returns: Four numbers as text, "axisX,axisY,axisZ,radians".

## Joints

### `b3JointRevolute`

`b3JointRevolute(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pPx as Number, in pPy as Number, in pPz as Number, in pAx as Number, in pAy as Number, in pAz as Number, in pCollide as Boolean) returns Integer`

Joins two bodies with a hinge.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pPx: The x of the hinge point, in world coordinates.
- pPy: The y of the hinge point.
- pPz: The z of the hinge point.
- pAx: The x of the hinge axis, in world coordinates.
- pAy: The y of the axis.
- pAz: The z of the axis.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

The bodies stay together at the point and turn only about the axis, like a door, a wheel on an axle or an elbow. The b3Revolute calls add limits, a motor and a spring.

### `b3JointPrismatic`

`b3JointPrismatic(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pPx as Number, in pPy as Number, in pPz as Number, in pAx as Number, in pAy as Number, in pAz as Number, in pCollide as Boolean) returns Integer`

Joins two bodies with a slider.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pPx: The x of a point on the slide, in world coordinates.
- pPy: The y of the point.
- pPz: The z of the point.
- pAx: The x of the slide direction, in world coordinates.
- pAy: The y of the direction.
- pAz: The z of the direction.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

The bodies cannot turn against each other and move only along the axis: a piston, a lift, a drawer.

### `b3JointSpherical`

`b3JointSpherical(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pPx as Number, in pPy as Number, in pPz as Number, in pAx as Number, in pAy as Number, in pAz as Number, in pCollide as Boolean) returns Integer`

Joins two bodies with a ball and socket.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pPx: The x of the socket point, in world coordinates.
- pPy: The y of the point.
- pPz: The z of the point.
- pAx: The x of the cone axis, in world coordinates.
- pAy: The y of the axis.
- pAz: The z of the axis.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

The bodies stay together at the point and turn freely about it: a shoulder, a rope link. The axis is what the cone and twist limits are measured from.

### `b3JointWeld`

`b3JointWeld(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pPx as Number, in pPy as Number, in pPz as Number, in pCollide as Boolean) returns Integer`

Glues two bodies together.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pPx: The x of the weld point, in world coordinates.
- pPy: The y of the point.
- pPz: The z of the point.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

Rigid by default. Give it a frequency with the b3Weld calls and it bends like a stiff spring.

### `b3JointDistance`

`b3JointDistance(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pAx as Number, in pAy as Number, in pAz as Number, in pBx as Number, in pBy as Number, in pBz as Number, in pCollide as Boolean) returns Integer`

Keeps two points of two bodies a fixed distance apart.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pAx: The x of the point on the first body, in world coordinates.
- pAy: The y of that point.
- pAz: The z of that point.
- pBx: The x of the point on the second body, in world coordinates.
- pBy: The y of that point.
- pBz: The z of that point.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

A rod, or with the b3Distance calls a spring or a rope with a minimum and maximum length. The starting distance is the length.

### `b3JointWheel`

`b3JointWheel(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pPx as Number, in pPy as Number, in pPz as Number, in pUx as Number, in pUy as Number, in pUz as Number, in pSx as Number, in pSy as Number, in pSz as Number, in pCollide as Boolean) returns Integer`

Joins a wheel to a chassis: it spins, rides a suspension and can steer.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pPx: The x of the wheel centre, in world coordinates.
- pPy: The y of the centre.
- pPz: The z of the centre.
- pUx: The x of the suspension direction (usually up), in world coordinates.
- pUy: The y of that direction.
- pUz: The z of that direction.
- pSx: The x of the axle the wheel spins about, in world coordinates.
- pSy: The y of the axle.
- pSz: The z of the axle.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

The first body is the chassis and the second the wheel. The axle must not point along the suspension.

### `b3JointMotor`

`b3JointMotor(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pCollide as Boolean) returns Integer`

Drives one body relative to another with a force and torque.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

With no settings it does nothing. The b3Motor calls give it a target velocity or a spring: a top-down character, friction against the ground, a conveyor.

### `b3JointParallel`

`b3JointParallel(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer, in pAx as Number, in pAy as Number, in pAz as Number, in pCollide as Boolean) returns Integer`

Keeps an axis of one body parallel to the same axis of another.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.
- pAx: The x of the axis to keep parallel, in world coordinates.
- pAy: The y of the axis.
- pAz: The z of the axis.
- pCollide: True if the two joined bodies should still collide with each other.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

The bodies are free to move and to turn about the axis: keeping something upright.

### `b3JointFilter`

`b3JointFilter(in pWorld as Integer, in pBodyA as Integer, in pBodyB as Integer) returns Integer`

Stops two bodies colliding with each other and does nothing else.

- pWorld: A world handle from `b3WorldCreate`.
- pBodyA: The first body, in the same world.
- pBodyB: The second body, in the same world. It must not be the first.

Returns: A joint handle, or 0 if the arguments were refused (see `b3LastError`).

### `b3JointDestroy`

`b3JointDestroy(in pJoint as Integer, in pWake as Boolean) returns nothing`

Destroys a joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pWake: True to wake the two bodies.

### `b3JointIsValid`

`b3JointIsValid(in pJoint as Integer) returns Boolean`

Reports whether a handle names a live joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True for a live joint.

### `b3JointType`

`b3JointType(in pJoint as Integer) returns Integer`

Returns what kind of joint a handle names.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: 0 parallel, 1 distance, 2 filter, 3 motor, 4 prismatic, 5 revolute, 6 spherical, 7 weld, 8 wheel; -1 for no joint.

### `b3JointBodyA`

`b3JointBodyA(in pJoint as Integer) returns Integer`

Returns the first body of a joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The body handle, or 0.

### `b3JointBodyB`

`b3JointBodyB(in pJoint as Integer) returns Integer`

Returns the second body of a joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The body handle, or 0.

### `b3JointSetCollideConnected`

`b3JointSetCollideConnected(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Chooses whether the two bodies of a joint collide with each other.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3JointCollideConnected`

`b3JointCollideConnected(in pJoint as Integer) returns Boolean`

Reports whether the two bodies of a joint collide with each other.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if they do.

### `b3JointWakeBodies`

`b3JointWakeBodies(in pJoint as Integer) returns nothing`

Wakes the two bodies of a joint.

- pJoint: A joint handle from one of the b3Joint creators.

### `b3JointLocalFrameA`

`b3JointLocalFrameA(in pJoint as Integer) returns String`

Returns where a joint is attached to its first body.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Seven numbers as text, "x,y,z,qx,qy,qz,qw".

### `b3JointLocalFrameB`

`b3JointLocalFrameB(in pJoint as Integer) returns String`

Returns where a joint is attached to its second body.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Seven numbers as text, "x,y,z,qx,qy,qz,qw".

### `b3JointSetLocalFrameA`

`b3JointSetLocalFrameA(in pJoint as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Moves where a joint is attached to its first body.

- pJoint: A joint handle from one of the b3Joint creators.
- pX: The x of the attachment, in the body's coordinates.
- pY: The y of the attachment.
- pZ: The z of the attachment.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

Advanced: the creators place the frames from world points, which is nearly always what is wanted.

### `b3JointSetLocalFrameB`

`b3JointSetLocalFrameB(in pJoint as Integer, in pX as Number, in pY as Number, in pZ as Number, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Moves where a joint is attached to its second body.

- pJoint: A joint handle from one of the b3Joint creators.
- pX: The x of the attachment, in the body's coordinates.
- pY: The y of the attachment.
- pZ: The z of the attachment.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

### `b3JointConstraintForce`

`b3JointConstraintForce(in pJoint as Integer) returns String`

Returns the force a joint is applying to hold its bodies.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3JointConstraintTorque`

`b3JointConstraintTorque(in pJoint as Integer) returns String`

Returns the torque a joint is applying to hold its bodies.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3JointLinearSeparation`

`b3JointLinearSeparation(in pJoint as Integer) returns Number`

Returns how far apart a joint's anchor points have been pulled.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Metres; 0 for a wheel joint, which Box3D does not measure yet.

### `b3JointAngularSeparation`

`b3JointAngularSeparation(in pJoint as Integer) returns Number`

Returns how far a joint has been bent past what it allows.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Radians; 0 for a wheel joint, which Box3D does not measure yet.

### `b3JointSetForceThreshold`

`b3JointSetForceThreshold(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the force above which a joint reports a joint event.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The force in newtons, 0 or more.

### `b3JointForceThreshold`

`b3JointForceThreshold(in pJoint as Integer) returns Number`

Returns the force above which a joint reports a joint event.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Newtons.

### `b3JointSetTorqueThreshold`

`b3JointSetTorqueThreshold(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the torque above which a joint reports a joint event.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The torque in newton metres, 0 or more.

### `b3JointTorqueThreshold`

`b3JointTorqueThreshold(in pJoint as Integer) returns Number`

Returns the torque above which a joint reports a joint event.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: Newton metres.

## Revolute joints

### `b3RevoluteSetLimits`

`b3RevoluteSetLimits(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets how far a revolute joint may turn each way.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The lowest angle, in radians.
- pUpper: The highest angle. It must not be below the lowest.

The limit acts once it is turned on with `b3RevoluteEnableLimit`.

### `b3RevoluteEnableSpring`

`b3RevoluteEnableSpring(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the spring of a revolute joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3RevoluteIsSpringEnabled`

`b3RevoluteIsSpringEnabled(in pJoint as Integer) returns Boolean`

Reports whether the spring of a revolute joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3RevoluteSetSpringHertz`

`b3RevoluteSetSpringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring hertz of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3RevoluteSpringHertz`

`b3RevoluteSpringHertz(in pJoint as Integer) returns Number`

Returns the spring hertz of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3RevoluteSetSpringDampingRatio`

`b3RevoluteSetSpringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring damping ratio of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3RevoluteSpringDampingRatio`

`b3RevoluteSpringDampingRatio(in pJoint as Integer) returns Number`

Returns the spring damping ratio of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3RevoluteSetTargetAngle`

`b3RevoluteSetTargetAngle(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the target angle of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The target angle, in radians.

### `b3RevoluteTargetAngle`

`b3RevoluteTargetAngle(in pJoint as Integer) returns Number`

Returns the target angle of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The target angle, in radians.

### `b3RevoluteAngle`

`b3RevoluteAngle(in pJoint as Integer) returns Number`

Returns the angle of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The angle, in radians.

### `b3RevoluteEnableLimit`

`b3RevoluteEnableLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the limit of a revolute joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3RevoluteIsLimitEnabled`

`b3RevoluteIsLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the limit of a revolute joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3RevoluteLowerLimit`

`b3RevoluteLowerLimit(in pJoint as Integer) returns Number`

Returns the lower limit of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The lower limit, in radians.

### `b3RevoluteUpperLimit`

`b3RevoluteUpperLimit(in pJoint as Integer) returns Number`

Returns the upper limit of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The upper limit, in radians.

### `b3RevoluteEnableMotor`

`b3RevoluteEnableMotor(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the motor of a revolute joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3RevoluteIsMotorEnabled`

`b3RevoluteIsMotorEnabled(in pJoint as Integer) returns Boolean`

Reports whether the motor of a revolute joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3RevoluteSetMotorSpeed`

`b3RevoluteSetMotorSpeed(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the motor speed of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The motor speed, in radians per second.

### `b3RevoluteMotorSpeed`

`b3RevoluteMotorSpeed(in pJoint as Integer) returns Number`

Returns the motor speed of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor speed, in radians per second.

### `b3RevoluteMotorTorque`

`b3RevoluteMotorTorque(in pJoint as Integer) returns Number`

Returns the motor torque of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor torque, in newton metres.

### `b3RevoluteSetMaxMotorTorque`

`b3RevoluteSetMaxMotorTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max motor torque of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max motor torque, in newton metres.

### `b3RevoluteMaxMotorTorque`

`b3RevoluteMaxMotorTorque(in pJoint as Integer) returns Number`

Returns the max motor torque of a revolute joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max motor torque, in newton metres.

## Prismatic joints

### `b3PrismaticSetLimits`

`b3PrismaticSetLimits(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets how far a prismatic joint may slide each way.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The lowest position, in metres.
- pUpper: The highest position. It must not be below the lowest.

The limit acts once it is turned on with `b3PrismaticEnableLimit`.

### `b3PrismaticEnableSpring`

`b3PrismaticEnableSpring(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the spring of a prismatic joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3PrismaticIsSpringEnabled`

`b3PrismaticIsSpringEnabled(in pJoint as Integer) returns Boolean`

Reports whether the spring of a prismatic joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3PrismaticSetSpringHertz`

`b3PrismaticSetSpringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring hertz of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3PrismaticSpringHertz`

`b3PrismaticSpringHertz(in pJoint as Integer) returns Number`

Returns the spring hertz of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3PrismaticSetSpringDampingRatio`

`b3PrismaticSetSpringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring damping ratio of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3PrismaticSpringDampingRatio`

`b3PrismaticSpringDampingRatio(in pJoint as Integer) returns Number`

Returns the spring damping ratio of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3PrismaticSetTargetTranslation`

`b3PrismaticSetTargetTranslation(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the target translation of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The target translation, in metres.

### `b3PrismaticTargetTranslation`

`b3PrismaticTargetTranslation(in pJoint as Integer) returns Number`

Returns the target translation of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The target translation, in metres.

### `b3PrismaticEnableLimit`

`b3PrismaticEnableLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the limit of a prismatic joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3PrismaticIsLimitEnabled`

`b3PrismaticIsLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the limit of a prismatic joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3PrismaticLowerLimit`

`b3PrismaticLowerLimit(in pJoint as Integer) returns Number`

Returns the lower limit of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The lower limit, in radians.

### `b3PrismaticUpperLimit`

`b3PrismaticUpperLimit(in pJoint as Integer) returns Number`

Returns the upper limit of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The upper limit, in radians.

### `b3PrismaticEnableMotor`

`b3PrismaticEnableMotor(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the motor of a prismatic joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3PrismaticIsMotorEnabled`

`b3PrismaticIsMotorEnabled(in pJoint as Integer) returns Boolean`

Reports whether the motor of a prismatic joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3PrismaticSetMotorSpeed`

`b3PrismaticSetMotorSpeed(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the motor speed of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The motor speed, in m/s.

### `b3PrismaticMotorSpeed`

`b3PrismaticMotorSpeed(in pJoint as Integer) returns Number`

Returns the motor speed of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor speed, in m/s.

### `b3PrismaticSetMaxMotorForce`

`b3PrismaticSetMaxMotorForce(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max motor force of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max motor force, in newtons.

### `b3PrismaticMaxMotorForce`

`b3PrismaticMaxMotorForce(in pJoint as Integer) returns Number`

Returns the max motor force of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max motor force, in newtons.

### `b3PrismaticMotorForce`

`b3PrismaticMotorForce(in pJoint as Integer) returns Number`

Returns the motor force of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor force, in newtons.

### `b3PrismaticTranslation`

`b3PrismaticTranslation(in pJoint as Integer) returns Number`

Returns the translation of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The translation, in metres.

### `b3PrismaticSpeed`

`b3PrismaticSpeed(in pJoint as Integer) returns Number`

Returns the speed of a prismatic joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The speed, in m/s.

## Spherical joints

### `b3SphericalSetMotorVelocity`

`b3SphericalSetMotorVelocity(in pJoint as Integer, in pWx as Number, in pWy as Number, in pWz as Number) returns nothing`

Sets the spin the motor of a spherical joint drives at.

- pJoint: A joint handle from one of the b3Joint creators.
- pWx: The x component, in radians per second.
- pWy: The y component, in radians per second.
- pWz: The z component, in radians per second.

### `b3SphericalMotorVelocity`

`b3SphericalMotorVelocity(in pJoint as Integer) returns String`

Returns the spin the motor of a spherical joint drives at.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3SphericalMotorTorque`

`b3SphericalMotorTorque(in pJoint as Integer) returns String`

Returns the torque the motor of a spherical joint is applying.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3SphericalSetTargetRotation`

`b3SphericalSetTargetRotation(in pJoint as Integer, in pQx as Number, in pQy as Number, in pQz as Number, in pQw as Number) returns nothing`

Sets the rotation the spring of a spherical joint pulls towards.

- pJoint: A joint handle from one of the b3Joint creators.
- pQx: The x part of the rotation quaternion.
- pQy: The y part of the rotation quaternion.
- pQz: The z part of the rotation quaternion.
- pQw: The w (scalar) part of the rotation quaternion.

### `b3SphericalTargetRotation`

`b3SphericalTargetRotation(in pJoint as Integer) returns String`

Returns the rotation the spring of a spherical joint pulls towards.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The quaternion as text, "x,y,z,w".

### `b3SphericalSetTwistLimits`

`b3SphericalSetTwistLimits(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets how far a spherical joint may twist about its axis each way.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The lowest twist, in radians.
- pUpper: The highest twist. It must not be below the lowest.

The limit acts once it is turned on with `b3SphericalEnableTwistLimit`.

### `b3SphericalEnableConeLimit`

`b3SphericalEnableConeLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the cone limit of a spherical joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3SphericalIsConeLimitEnabled`

`b3SphericalIsConeLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the cone limit of a spherical joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3SphericalSetConeLimit`

`b3SphericalSetConeLimit(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the cone limit of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The cone limit, in radians.

### `b3SphericalConeLimit`

`b3SphericalConeLimit(in pJoint as Integer) returns Number`

Returns the cone limit of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The cone limit, in radians.

### `b3SphericalConeAngle`

`b3SphericalConeAngle(in pJoint as Integer) returns Number`

Returns the cone angle of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The cone angle, in radians.

### `b3SphericalEnableTwistLimit`

`b3SphericalEnableTwistLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the twist limit of a spherical joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3SphericalIsTwistLimitEnabled`

`b3SphericalIsTwistLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the twist limit of a spherical joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3SphericalLowerTwistLimit`

`b3SphericalLowerTwistLimit(in pJoint as Integer) returns Number`

Returns the lower twist limit of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The lower twist limit, in radians.

### `b3SphericalUpperTwistLimit`

`b3SphericalUpperTwistLimit(in pJoint as Integer) returns Number`

Returns the upper twist limit of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The upper twist limit, in radians.

### `b3SphericalTwistAngle`

`b3SphericalTwistAngle(in pJoint as Integer) returns Number`

Returns the twist angle of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The twist angle, in radians.

### `b3SphericalEnableSpring`

`b3SphericalEnableSpring(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the spring of a spherical joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3SphericalIsSpringEnabled`

`b3SphericalIsSpringEnabled(in pJoint as Integer) returns Boolean`

Reports whether the spring of a spherical joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3SphericalSetSpringHertz`

`b3SphericalSetSpringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring hertz of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3SphericalSpringHertz`

`b3SphericalSpringHertz(in pJoint as Integer) returns Number`

Returns the spring hertz of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3SphericalSetSpringDampingRatio`

`b3SphericalSetSpringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring damping ratio of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3SphericalSpringDampingRatio`

`b3SphericalSpringDampingRatio(in pJoint as Integer) returns Number`

Returns the spring damping ratio of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3SphericalEnableMotor`

`b3SphericalEnableMotor(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the motor of a spherical joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3SphericalIsMotorEnabled`

`b3SphericalIsMotorEnabled(in pJoint as Integer) returns Boolean`

Reports whether the motor of a spherical joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3SphericalSetMaxMotorTorque`

`b3SphericalSetMaxMotorTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max motor torque of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max motor torque, in newton metres.

### `b3SphericalMaxMotorTorque`

`b3SphericalMaxMotorTorque(in pJoint as Integer) returns Number`

Returns the max motor torque of a spherical joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max motor torque, in newton metres.

## Weld joints

### `b3WeldSetLinearHertz`

`b3WeldSetLinearHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the linear hertz of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The linear hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WeldLinearHertz`

`b3WeldLinearHertz(in pJoint as Integer) returns Number`

Returns the linear hertz of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The linear hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WeldSetLinearDampingRatio`

`b3WeldSetLinearDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the linear damping ratio of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The linear damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WeldLinearDampingRatio`

`b3WeldLinearDampingRatio(in pJoint as Integer) returns Number`

Returns the linear damping ratio of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The linear damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WeldSetAngularHertz`

`b3WeldSetAngularHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the angular hertz of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The angular hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WeldAngularHertz`

`b3WeldAngularHertz(in pJoint as Integer) returns Number`

Returns the angular hertz of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The angular hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WeldSetAngularDampingRatio`

`b3WeldSetAngularDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the angular damping ratio of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The angular damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WeldAngularDampingRatio`

`b3WeldAngularDampingRatio(in pJoint as Integer) returns Number`

Returns the angular damping ratio of a weld joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The angular damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

## Distance joints

### `b3DistanceSetLengthRange`

`b3DistanceSetLengthRange(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets the shortest and longest a distance joint may be.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The shortest length, in metres.
- pUpper: The longest length. It must not be below the shortest.

The range acts once it is turned on with `b3DistanceEnableLimit`.

### `b3DistanceSetLength`

`b3DistanceSetLength(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the length of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The length, in metres.

### `b3DistanceLength`

`b3DistanceLength(in pJoint as Integer) returns Number`

Returns the length of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The length, in metres.

### `b3DistanceEnableSpring`

`b3DistanceEnableSpring(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the spring of a distance joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3DistanceIsSpringEnabled`

`b3DistanceIsSpringEnabled(in pJoint as Integer) returns Boolean`

Reports whether the spring of a distance joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3DistanceSetSpringHertz`

`b3DistanceSetSpringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring hertz of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3DistanceSpringHertz`

`b3DistanceSpringHertz(in pJoint as Integer) returns Number`

Returns the spring hertz of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3DistanceSetSpringDampingRatio`

`b3DistanceSetSpringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring damping ratio of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3DistanceSpringDampingRatio`

`b3DistanceSpringDampingRatio(in pJoint as Integer) returns Number`

Returns the spring damping ratio of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3DistanceEnableLimit`

`b3DistanceEnableLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the limit of a distance joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3DistanceIsLimitEnabled`

`b3DistanceIsLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the limit of a distance joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3DistanceMinLength`

`b3DistanceMinLength(in pJoint as Integer) returns Number`

Returns the min length of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The min length, in metres.

### `b3DistanceMaxLength`

`b3DistanceMaxLength(in pJoint as Integer) returns Number`

Returns the max length of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max length, in metres.

### `b3DistanceCurrentLength`

`b3DistanceCurrentLength(in pJoint as Integer) returns Number`

Returns the current length of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The current length, in metres.

### `b3DistanceEnableMotor`

`b3DistanceEnableMotor(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the motor of a distance joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3DistanceIsMotorEnabled`

`b3DistanceIsMotorEnabled(in pJoint as Integer) returns Boolean`

Reports whether the motor of a distance joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3DistanceSetMotorSpeed`

`b3DistanceSetMotorSpeed(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the motor speed of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The motor speed, in m/s.

### `b3DistanceMotorSpeed`

`b3DistanceMotorSpeed(in pJoint as Integer) returns Number`

Returns the motor speed of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor speed, in m/s.

### `b3DistanceSetMaxMotorForce`

`b3DistanceSetMaxMotorForce(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max motor force of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max motor force, in newtons.

### `b3DistanceMaxMotorForce`

`b3DistanceMaxMotorForce(in pJoint as Integer) returns Number`

Returns the max motor force of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max motor force, in newtons.

### `b3DistanceMotorForce`

`b3DistanceMotorForce(in pJoint as Integer) returns Number`

Returns the motor force of a distance joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The motor force, in newtons.

## Wheel joints

### `b3WheelSetSuspensionLimits`

`b3WheelSetSuspensionLimits(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets how far a wheel may travel on its suspension each way.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The lowest position, in metres.
- pUpper: The highest position. It must not be below the lowest.

The limit acts once it is turned on with `b3WheelEnableSuspensionLimit`.

### `b3WheelSetSteeringLimits`

`b3WheelSetSteeringLimits(in pJoint as Integer, in pLower as Number, in pUpper as Number) returns nothing`

Sets how far a wheel may steer each way.

- pJoint: A joint handle from one of the b3Joint creators.
- pLower: The lowest angle, in radians.
- pUpper: The highest angle. It must not be below the lowest.

The limit acts once it is turned on with `b3WheelEnableSteeringLimit`.

### `b3WheelEnableSuspension`

`b3WheelEnableSuspension(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the suspension of a wheel joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3WheelIsSuspensionEnabled`

`b3WheelIsSuspensionEnabled(in pJoint as Integer) returns Boolean`

Reports whether the suspension of a wheel joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3WheelSetSuspensionHertz`

`b3WheelSetSuspensionHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the suspension hertz of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The suspension hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WheelSuspensionHertz`

`b3WheelSuspensionHertz(in pJoint as Integer) returns Number`

Returns the suspension hertz of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The suspension hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WheelSetSuspensionDampingRatio`

`b3WheelSetSuspensionDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the suspension damping ratio of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The suspension damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WheelSuspensionDampingRatio`

`b3WheelSuspensionDampingRatio(in pJoint as Integer) returns Number`

Returns the suspension damping ratio of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The suspension damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WheelEnableSuspensionLimit`

`b3WheelEnableSuspensionLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the suspension limit of a wheel joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3WheelIsSuspensionLimitEnabled`

`b3WheelIsSuspensionLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the suspension limit of a wheel joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3WheelLowerSuspensionLimit`

`b3WheelLowerSuspensionLimit(in pJoint as Integer) returns Number`

Returns the lower suspension limit of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The lower suspension limit, in radians.

### `b3WheelUpperSuspensionLimit`

`b3WheelUpperSuspensionLimit(in pJoint as Integer) returns Number`

Returns the upper suspension limit of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The upper suspension limit, in radians.

### `b3WheelEnableSpinMotor`

`b3WheelEnableSpinMotor(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the spin motor of a wheel joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3WheelIsSpinMotorEnabled`

`b3WheelIsSpinMotorEnabled(in pJoint as Integer) returns Boolean`

Reports whether the spin motor of a wheel joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3WheelSetSpinMotorSpeed`

`b3WheelSetSpinMotorSpeed(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spin motor speed of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spin motor speed, in radians per second.

### `b3WheelSpinMotorSpeed`

`b3WheelSpinMotorSpeed(in pJoint as Integer) returns Number`

Returns the spin motor speed of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spin motor speed, in radians per second.

### `b3WheelSetMaxSpinTorque`

`b3WheelSetMaxSpinTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max spin torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max spin torque, in newton metres.

### `b3WheelMaxSpinTorque`

`b3WheelMaxSpinTorque(in pJoint as Integer) returns Number`

Returns the max spin torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max spin torque, in newton metres.

### `b3WheelSpinSpeed`

`b3WheelSpinSpeed(in pJoint as Integer) returns Number`

Returns the spin speed of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spin speed, in radians per second.

### `b3WheelSpinTorque`

`b3WheelSpinTorque(in pJoint as Integer) returns Number`

Returns the spin torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spin torque, in newton metres.

### `b3WheelEnableSteering`

`b3WheelEnableSteering(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the steering of a wheel joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3WheelIsSteeringEnabled`

`b3WheelIsSteeringEnabled(in pJoint as Integer) returns Boolean`

Reports whether the steering of a wheel joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3WheelSetSteeringHertz`

`b3WheelSetSteeringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the steering hertz of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The steering hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WheelSteeringHertz`

`b3WheelSteeringHertz(in pJoint as Integer) returns Number`

Returns the steering hertz of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The steering hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3WheelSetSteeringDampingRatio`

`b3WheelSetSteeringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the steering damping ratio of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The steering damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WheelSteeringDampingRatio`

`b3WheelSteeringDampingRatio(in pJoint as Integer) returns Number`

Returns the steering damping ratio of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The steering damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3WheelSetMaxSteeringTorque`

`b3WheelSetMaxSteeringTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max steering torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max steering torque, in newton metres.

### `b3WheelMaxSteeringTorque`

`b3WheelMaxSteeringTorque(in pJoint as Integer) returns Number`

Returns the max steering torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max steering torque, in newton metres.

### `b3WheelEnableSteeringLimit`

`b3WheelEnableSteeringLimit(in pJoint as Integer, in pFlag as Boolean) returns nothing`

Turns the steering limit of a wheel joint on or off.

- pJoint: A joint handle from one of the b3Joint creators.
- pFlag: True to turn it on, false to turn it off.

### `b3WheelIsSteeringLimitEnabled`

`b3WheelIsSteeringLimitEnabled(in pJoint as Integer) returns Boolean`

Reports whether the steering limit of a wheel joint is on.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: True if it is on.

### `b3WheelLowerSteeringLimit`

`b3WheelLowerSteeringLimit(in pJoint as Integer) returns Number`

Returns the lower steering limit of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The lower steering limit, in radians.

### `b3WheelUpperSteeringLimit`

`b3WheelUpperSteeringLimit(in pJoint as Integer) returns Number`

Returns the upper steering limit of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The upper steering limit, in radians.

### `b3WheelSetTargetSteeringAngle`

`b3WheelSetTargetSteeringAngle(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the target steering angle of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The target steering angle, in radians.

### `b3WheelTargetSteeringAngle`

`b3WheelTargetSteeringAngle(in pJoint as Integer) returns Number`

Returns the target steering angle of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The target steering angle, in radians.

### `b3WheelSteeringAngle`

`b3WheelSteeringAngle(in pJoint as Integer) returns Number`

Returns the steering angle of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The steering angle, in radians.

### `b3WheelSteeringTorque`

`b3WheelSteeringTorque(in pJoint as Integer) returns Number`

Returns the steering torque of a wheel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The steering torque, in newton metres.

## Motor joints

### `b3MotorSetLinearVelocity`

`b3MotorSetLinearVelocity(in pJoint as Integer, in pVx as Number, in pVy as Number, in pVz as Number) returns nothing`

Sets the velocity a motor joint drives its second body at.

- pJoint: A joint handle from one of the b3Joint creators.
- pVx: The x component, in m/s.
- pVy: The y component, in m/s.
- pVz: The z component, in m/s.

### `b3MotorLinearVelocity`

`b3MotorLinearVelocity(in pJoint as Integer) returns String`

Returns the velocity a motor joint drives at.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3MotorSetAngularVelocity`

`b3MotorSetAngularVelocity(in pJoint as Integer, in pWx as Number, in pWy as Number, in pWz as Number) returns nothing`

Sets the spin a motor joint drives its second body at.

- pJoint: A joint handle from one of the b3Joint creators.
- pWx: The x component, in radians per second.
- pWy: The y component, in radians per second.
- pWz: The z component, in radians per second.

### `b3MotorAngularVelocity`

`b3MotorAngularVelocity(in pJoint as Integer) returns String`

Returns the spin a motor joint drives at.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The three numbers as text, "x,y,z".

### `b3MotorSetMaxVelocityForce`

`b3MotorSetMaxVelocityForce(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max velocity force of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max velocity force, in newtons.

### `b3MotorMaxVelocityForce`

`b3MotorMaxVelocityForce(in pJoint as Integer) returns Number`

Returns the max velocity force of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max velocity force, in newtons.

### `b3MotorSetMaxVelocityTorque`

`b3MotorSetMaxVelocityTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max velocity torque of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max velocity torque, in newton metres.

### `b3MotorMaxVelocityTorque`

`b3MotorMaxVelocityTorque(in pJoint as Integer) returns Number`

Returns the max velocity torque of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max velocity torque, in newton metres.

### `b3MotorSetLinearHertz`

`b3MotorSetLinearHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the linear hertz of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The linear hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3MotorLinearHertz`

`b3MotorLinearHertz(in pJoint as Integer) returns Number`

Returns the linear hertz of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The linear hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3MotorSetLinearDampingRatio`

`b3MotorSetLinearDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the linear damping ratio of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The linear damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3MotorLinearDampingRatio`

`b3MotorLinearDampingRatio(in pJoint as Integer) returns Number`

Returns the linear damping ratio of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The linear damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3MotorSetAngularHertz`

`b3MotorSetAngularHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the angular hertz of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The angular hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3MotorAngularHertz`

`b3MotorAngularHertz(in pJoint as Integer) returns Number`

Returns the angular hertz of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The angular hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3MotorSetAngularDampingRatio`

`b3MotorSetAngularDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the angular damping ratio of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The angular damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3MotorAngularDampingRatio`

`b3MotorAngularDampingRatio(in pJoint as Integer) returns Number`

Returns the angular damping ratio of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The angular damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3MotorSetMaxSpringForce`

`b3MotorSetMaxSpringForce(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max spring force of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max spring force, in newtons.

### `b3MotorMaxSpringForce`

`b3MotorMaxSpringForce(in pJoint as Integer) returns Number`

Returns the max spring force of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max spring force, in newtons.

### `b3MotorSetMaxSpringTorque`

`b3MotorSetMaxSpringTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max spring torque of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max spring torque, in newton metres.

### `b3MotorMaxSpringTorque`

`b3MotorMaxSpringTorque(in pJoint as Integer) returns Number`

Returns the max spring torque of a motor joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max spring torque, in newton metres.

## Parallel joints

### `b3ParallelSetSpringHertz`

`b3ParallelSetSpringHertz(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring hertz of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3ParallelSpringHertz`

`b3ParallelSpringHertz(in pJoint as Integer) returns Number`

Returns the spring hertz of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring hertz, in cycles per second, 0 to 10000 (0 turns the spring off).

### `b3ParallelSetSpringDampingRatio`

`b3ParallelSetSpringDampingRatio(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the spring damping ratio of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3ParallelSpringDampingRatio`

`b3ParallelSpringDampingRatio(in pJoint as Integer) returns Number`

Returns the spring damping ratio of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The spring damping ratio, as a ratio, 0 to 1000 (1 is critical damping).

### `b3ParallelSetMaxTorque`

`b3ParallelSetMaxTorque(in pJoint as Integer, in pValue as Number) returns nothing`

Sets the max torque of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.
- pValue: The max torque, in newton metres.

### `b3ParallelMaxTorque`

`b3ParallelMaxTorque(in pJoint as Integer) returns Number`

Returns the max torque of a parallel joint.

- pJoint: A joint handle from one of the b3Joint creators.

Returns: The max torque, in newton metres.

### `b3RenderSetCamera`

`b3RenderSetCamera(in pEyeX as Number, in pEyeY as Number, in pEyeZ as Number, in pTargetX as Number, in pTargetY as Number, in pTargetZ as Number, in pDegrees as Number) returns nothing`

Places the camera the renderer looks through.

- pEyeX: Where the camera stands, x, in metres.
- pEyeY: Where the camera stands, y (up).
- pEyeZ: Where the camera stands, z.
- pTargetX: The point the camera looks at, x.
- pTargetY: The point the camera looks at, y.
- pTargetZ: The point the camera looks at, z.
- pDegrees: The vertical field of view in degrees, 5 to 150. 50 is a natural lens.

y is up in the picture. The camera stays where it is put until the next call; it starts at 0,4,12 looking at 0,1,0 through 50 degrees. Refused, with a reason in `b3LastError`, if the two points are the same, any number is not finite or the angle is outside 5 to 150; the camera then stays as it was.

```
b3RenderSetCamera 6, 5, 10, 0, 1, 0, 50
```

### `b3RenderCamera`

`b3RenderCamera() returns String`

Returns the renderer's camera.

Returns: Seven numbers as text: "eyeX,eyeY,eyeZ,targetX,targetY,targetZ,degrees".

What `b3RenderSetCamera` last accepted. Another renderer handed these seven numbers looks at the world from the same place.

### `b3RenderSetLight`

`b3RenderSetLight(in pX as Number, in pY as Number, in pZ as Number) returns nothing`

Sets the direction the renderer's one light travels.

- pX: The x of the direction the light travels.
- pY: The y of that direction; -1 is straight down.
- pZ: The z of that direction.

Any length will do; a direction of no length is refused. A surface facing the light is brightest and one facing away keeps a dim ambient shade, so nothing is drawn black.

### `b3RenderSetBackground`

`b3RenderSetBackground(in pRed as Integer, in pGreen as Integer, in pBlue as Integer) returns nothing`

Sets the colour the renderer paints where there is no shape.

- pRed: Red, 0 to 255.
- pGreen: Green, 0 to 255.
- pBlue: Blue, 0 to 255.

A number outside 0 to 255 is refused and the colour stays.

### `b3ShapeSetColor`

`b3ShapeSetColor(in pShape as Integer, in pRed as Integer, in pGreen as Integer, in pBlue as Integer) returns nothing`

Gives a shape its own colour in the renderer.

- pShape: A shape handle from one of the b3ShapeAdd calls.
- pRed: Red, 0 to 255.
- pGreen: Green, 0 to 255.
- pBlue: Blue, 0 to 255.

Without one a shape is drawn in a colour that says what its body is doing: grey-green for static scenery, one of eight colours for a moving body, the same colour dimmed while the body sleeps. The colour goes when the shape does. Nothing in the simulation reads it.

```
b3ShapeSetColor tShape, 230, 120, 40
```

### `b3ShapeClearColor`

`b3ShapeClearColor(in pShape as Integer) returns nothing`

Takes a shape's own colour away, so the renderer chooses again.

- pShape: A shape handle from one of the b3ShapeAdd calls.

### `b3ShapeColor`

`b3ShapeColor(in pShape as Integer) returns String`

Returns the colour a shape was given for the renderer.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: Text "red,green,blue", or empty for a shape with no colour of its own or a handle that is not a shape.

### `b3RenderWorld`

`b3RenderWorld(in pWorld as Integer, in pWidth as Integer, in pHeight as Integer, in pMode as Integer) returns Boolean`

Paints a world into a picture.

- pWorld: A world handle from b3WorldCreate.
- pWidth: The picture's width in pixels, 1 to 2048.
- pHeight: The picture's height in pixels, 1 to 2048.
- pMode: 0 for solid shapes, 1 for a wireframe, 2 for solid shapes with their edges drawn over them.

Returns: True if the picture was painted; false if it was refused, with the reason in `b3LastError`.

Every shape of every enabled body is drawn as the camera of `b3RenderSetCamera` sees it: lit by one light, nearer surfaces hiding farther ones. Take the picture with `b3RenderPixels`; it stays until the next render. Make the image the same size first, or the engine will not take the data. Rendering reads the world and never changes it, so it is safe at any moment between steps. There is one picture for the whole library, not one per world.

```
if b3RenderWorld(sWorld, 640, 400, 0) then
set the imageData of image "view" to b3RenderPixels()
end if
```

### `b3RenderPixels`

`b3RenderPixels() returns Data`

Returns the picture the last render painted.

Returns: Binary data, width times height times 4 bytes: rows from the top, four bytes a pixel (0, red, green, blue), which is the layout of an image's imageData. Empty before the first render.

The image must already have the picture's width and height.

```
set the imageData of image "view" to b3RenderPixels()
```

### `b3RenderByteCount`

`b3RenderByteCount() returns Integer`

Returns the size of the last picture in bytes.

Returns: Width times height times 4; 0 before the first render.

### `b3RenderWidth`

`b3RenderWidth() returns Integer`

Returns the width of the last picture.

Returns: The width in pixels; 0 before the first render.

### `b3RenderHeight`

`b3RenderHeight() returns Integer`

Returns the height of the last picture.

Returns: The height in pixels; 0 before the first render.

### `b3RenderTriangleCount`

`b3RenderTriangleCount() returns Integer`

Returns how many triangles the last render drew from.

Returns: The number of triangles the shapes were turned into, before any was clipped or hidden. A measure of how heavy a scene is to draw.

### `b3RenderPixel`

`b3RenderPixel(in pX as Integer, in pY as Integer) returns Integer`

Returns the colour of one pixel of the last picture.

- pX: Across the picture in pixels; 0 is its left edge.
- pY: Down the picture in pixels; 0 is its top edge.

Returns: Red times 65536 plus green times 256 plus blue; -1 outside the picture.

### `b3RenderShapeAt`

`b3RenderShapeAt(in pX as Integer, in pY as Integer) returns Integer`

Returns the shape drawn at a pixel of the last picture.

- pX: Across the picture in pixels; 0 is its left edge.
- pY: Down the picture in pixels; 0 is its top edge.

Returns: A shape handle, or 0 for the background, a point outside the picture, or a shape destroyed since the render.

The quick way to find what is under the mouse: no ray is cast. `b3ShapeBody` then names the body.

```
put b3RenderShapeAt(the mouseH - the left of image "view", the mouseV - the top of image "view") into tShape
```

### `b3RenderDepth`

`b3RenderDepth(in pX as Integer, in pY as Integer) returns Number`

Returns how far away the surface at a pixel of the last picture is.

- pX: Across the picture in pixels; 0 is its left edge.
- pY: Down the picture in pixels; 0 is its top edge.

Returns: Metres from the camera, measured along the way it looks; 0 for the background or a point outside the picture.

### `b3RenderProject`

`b3RenderProject(in pX as Number, in pY as Number, in pZ as Number) returns String`

Returns where a point of the world lands in the last picture.

- pX: The x of a point of the world, in metres.
- pY: The y of that point.
- pZ: The z of that point.

Returns: Text "x,y,depth": x and y in picture coordinates (they may lie outside the picture) and depth in metres along the camera's view. Empty if the point is behind the camera or nothing has been rendered.

Use it to put a label or a control over a body: project the body's position and add the image's left and top.

### `b3RenderRay`

`b3RenderRay(in pX as Number, in pY as Number) returns String`

Returns the ray from the camera through a point of the last picture.

- pX: Across the picture in pixels; 0 is its left edge, and half a pixel in is the centre of the first one.
- pY: Down the picture in pixels, counted the same way from its top.

Returns: Text "ox,oy,oz,dx,dy,dz": the camera's position and a direction of length 1. Empty if nothing has been rendered.

Multiply the direction by a reach in metres and hand both to `b3CastRayClosest` to find the exact point under the mouse.

### `b3ShapeTrianglesText`

`b3ShapeTrianglesText(in pShape as Integer) returns String`

Returns a shape as a list of triangles.

- pShape: A shape handle from one of the b3ShapeAdd calls.

Returns: One line per triangle, nine numbers "x1,y1,z1,x2,y2,z2,x3,y3,z3" in metres, in the frame of the shape's BODY (the body's position and rotation place them in the world), counter-clockwise seen from outside (a mesh's triangles keep the order they were given in). Empty for a handle that is not a shape.

For drawing a shape with something other than this library's renderer. A hull, a mesh and a height field give the triangles Box3D collides with; a sphere and a capsule are rounded off into the triangles the renderer here draws.
