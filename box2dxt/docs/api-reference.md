# Box2Dxt API Reference (`b2...`)

This is the low-level binding exposed by `src/box2dxt.lcb`. It mirrors the
Box2D v3 surface closely, and this page names every one of its 376 public
`b2...` handlers (completed 2026-09-24; `tools/check-reference-docs.py`, in this
member's `tools/run-gates.sh`, fails when a public handler is missing from it).
Related handlers share a row, and every name is spelled out in full so a search
finds it. `src/box2dxt.lcb` is the source of truth for exact parameter types. For
everyday work, the higher-level [Kit (`b2k...`)](kit-reference.md) is usually
easier - reach for these handlers when you need something the Kit doesn't expose.

**Conventions**

- Handles are integers; **`0` is invalid**. Every handler tolerates a stale or
  `0` handle (getters return `0`, actions do nothing) - the C shim validates ids.
- Distances are **metres**, angles are **radians**. Convert to pixels/degrees at
  draw time.
- Body type codes: `0` static, `1` kinematic, `2` dynamic.
- `b2Version()` → int returns the shim ABI version (currently `4`) - call it once
  as a load/version check that the extension and native library are in sync.

- [Loading and version](#loading-and-version)
- [World](#world)
- [Bodies](#bodies)
- [Shapes](#shapes)
- [Joints](#joints)
- [World queries](#world-queries)
- [Contact events](#contact-events)
- [Shape-def builder](#shape-def-builder-sensors-filtering-event-flags)
- [World tuning & info](#world-tuning--info)
- [Body - transforms, mass, enumeration](#body---transforms-mass-enumeration)
- [Shape - filter, geometry, material, queries](#shape---filter-geometry-material-queries)
- [Chains](#chains-smooth-terrain)
- [Joints - generic, motor, filter](#joints---generic-motor-filter)
- [Joints - revolute](#joints---revolute) · [prismatic](#joints---prismatic) ·
  [distance](#joints---distance) · [weld](#joints---weld) ·
  [wheel](#joints---wheel) · [mouse](#joints---mouse)
- [World queries (overlap / ray-cast-all / shape-cast)](#world-queries-overlap--ray-cast-all--shape-cast)
- [Events - hit, sensor, body-move](#events---hit-sensor-body-move)
- [Notes and gotchas](#notes-and-gotchas)

---

## Loading and version

| Handler | Purpose |
|---------|---------|
| `b2Version()` → int | The shim's ABI version, currently `4`. `b2NewWorld` and `b2NewThreadedWorld` check it and throw `box2dxt: incompatible native library (binding needs ABI 4)` when the loaded library disagrees. |
| `b2LoadNativeLib(path)` → `1` / `0` | **Linux only.** Preload the native library by absolute path (`dlopen` with `RTLD_NOW` \| `RTLD_GLOBAL`), so the engine's later bare-name load finds the copy already in the process. `0` on failure. Glibc matches the resident copy by SONAME, so this only works for a library built with `-DBOX2DXT_BARE_SONAME=ON` (soname `box2dxt.so`); the committed `src/code/*-linux/` libraries carry `libbox2dxt.so` (measured 2026-09-24), so they need the Kit's `revLibraryMapping` route instead (`b2kEnsureNativeLib`). The preload path itself has not been confirmed on an engine: `CMakeLists.txt` keeps `BOX2DXT_BARE_SONAME` OFF until it is. It binds to the POSIX loader, so never call it on Windows or macOS. |
| `b2LoadNativeLibError()` → string | The loader's last error (`dlerror`), empty if none: why `b2LoadNativeLib` returned `0`. Linux only, like it. |
| `b2LoadNativeLibHere()` → `1` / `0` | **Linux only.** Preload `box2dxt.so` from the running engine's own folder (found through `/proc/self/exe`), with the same soname requirement. Nothing calls it automatically. |

## World

| Handler | Purpose |
|---------|---------|
| `b2NewWorld(gx, gy, allowSleep, continuous)` → world | Create a single-threaded world with a gravity vector. |
| `b2NewThreadedWorld(gx, gy, allowSleep, continuous, workers)` → world | Create a world whose native `b2Step` can use a Box2D worker pool on supported platforms. OXT/LC script remains single-threaded; the C shim waits before returning. |
| `b2WorldThreadCount(world)` → count | Return the active native Box2D worker count for a world (`1` means serial or unsupported platform). |
| `b2DestroyWorld(world)` | Destroy a world and everything in it. |
| `b2SetGravity(world, gx, gy)` | Change gravity. |
| `b2EnableSleeping(world, flag)` / `b2EnableContinuous(world, flag)` | Toggle sleeping / CCD. |
| `b2Step(world, dt, subSteps)` | Advance the simulation by `dt` seconds (`subSteps` ≈ 4). |

## Bodies

| Handler | Purpose |
|---------|---------|
| `b2NewBody(world, type, x, y, angle, bullet, fixedRotation)` → body | Full body constructor. |
| `b2NewStaticBody` / `b2NewKinematicBody` / `b2NewDynamicBody (world, x, y)` → body | Convenience constructors. |
| `b2DestroyBody(body)` | Destroy a body (its shapes/joints go too). |
| `b2BodyX(body)` / `b2BodyY(body)` / `b2BodyAngle(body)` | Read world transform. |
| `b2BodyWorldCenterX(body)` / `b2BodyWorldCenterY(body)` | Read centre of mass (world). |
| `b2BodyVX` / `b2BodyVY` / `b2BodyAngularVelocity` / `b2BodyMass` / `b2BodyIsAwake` | Read state. |
| `b2BodyType` / `b2BodyIsBullet` / `b2BodyIsEnabled` | Read flags. |
| `b2BodyLinearDamping` / `b2BodyAngularDamping` / `b2BodyGravityScale` | Read damping / gravity scale. |
| `b2SetTransform(body, x, y, angle)` | Teleport a body. |
| `b2SetVelocity(body, vx, vy)` / `b2SetAngularVelocity(body, w)` | Set velocities. |
| `b2ApplyForce(body, fx, fy, wake)` / `b2ApplyImpulse(body, ix, iy, wake)` | Apply linear force / impulse at the centre. |
| `b2ApplyTorque(body, t, wake)` / `b2ApplyAngularImpulse(body, imp, wake)` | Apply angular force / impulse. |
| `b2SetBullet` / `b2SetAwake` / `b2SetFixedRotation` / `b2SetBodyType` | Per-body flags. |
| `b2SetLinearDamping` / `b2SetAngularDamping` / `b2SetGravityScale` / `b2SetSleepThreshold` | Tune motion. |
| `b2EnableBody(body)` / `b2DisableBody(body)` | Remove from / return to the simulation. |

## Shapes

Attach to a body; return a shape handle. Contact events are enabled on every
shape, so `b2ContactsUpdate` works out of the box.

| Handler | Purpose |
|---------|---------|
| `b2AddBox(body, halfW, halfH, density, friction, restitution)` | Box fixture. |
| `b2AddCircle(body, cx, cy, radius, density, friction, restitution)` | Circle fixture. |
| `b2AddCapsule(body, x1, y1, x2, y2, radius, density, friction, restitution)` | Capsule fixture. |
| `b2AddSegment(body, x1, y1, x2, y2, friction, restitution)` | Line edge (best on static bodies). **Two-sided** - bodies collide with it from either side regardless of point order (confirmed empirically in the Game Kit's 2026-06-10 OXT spike). For one-sided platforms/terrain use a **chain**: chain segments are the one-sided primitive. |
| `b2PolyBegin()` → `b2PolyAddPoint(x, y)` ... → `b2AddPolygon(body, density, friction, restitution)` | Build a convex polygon (≤ 8 points) without marshalling arrays. |
| `b2DestroyShape(shape)` | Remove a shape. |
| `b2SetShapeFriction` / `b2SetShapeRestitution` / `b2SetShapeDensity` | Edit material at runtime. |
| `b2ShapeBody(shape)` → body | The body a shape belongs to. |
| `b2ShapeTestPoint(shape, x, y)` → bool | Is a world point inside this shape? |

## Joints

| Handler | Purpose |
|---------|---------|
| `b2RevoluteJoint(world, bodyA, bodyB, ax, ay, bx, by, collide)` → joint | Pin two bodies (local anchors A and B). |
| `b2RevoluteEnableLimit(joint, enable, lowerRad, upperRad)` / `b2RevoluteEnableMotor(joint, enable, speed, maxTorque)` | Limits / motor. |
| `b2RevoluteAngle(joint)` → radians | Current joint angle. |
| `b2DistanceJoint(world, bodyA, bodyB, ax, ay, bx, by, length, collide)` → joint | Fixed-length link. |
| `b2DistanceSetLength` / `b2DistanceSetLengthRange` / `b2DistanceEnableSpring(joint, enable, hertz, damping)` | Length / spring control. |
| `b2DistanceLength(joint)` → metres | The rest length (what `b2DistanceSetLength` sets); `b2DistanceCurrentLength` is the live separation. |
| `b2WeldJoint(world, bodyA, bodyB, ax, ay, bx, by, refAngle, collide)` → joint | Rigidly glue two bodies. |
| `b2WeldSetStiffness(joint, linHertz, linDamping, angHertz, angDamping)` | Make the weld springy (0 hertz = rigid). |
| `b2PrismaticJoint(world, bodyA, bodyB, ax, ay, bx, by, axisX, axisY, refAngle, collide)` → joint | Slide bodyB along an axis. |
| `b2PrismaticEnableLimit(joint, enable, lower, upper)` / `b2PrismaticEnableMotor(joint, enable, speed, maxForce)` | Limits / motor. |
| `b2PrismaticTranslation(joint)` → metres | Current translation. |
| `b2WheelJoint(world, bodyA, bodyB, ax, ay, bx, by, axisX, axisY, collide)` → joint | Sprung sliding axis + free spin (vehicle wheels). |
| `b2WheelEnableSpring(joint, enable, hertz, damping)` / `b2WheelEnableMotor(joint, enable, speed, maxTorque)` | Suspension / drive. |
| `b2MouseJoint(world, bodyA, bodyB, tx, ty, hertz, damping, maxForce)` → joint | Drag bodyB toward a target (bodyA is a static reference). |
| `b2MouseSetTarget(joint, tx, ty)` | Move the drag target each frame. |
| `b2DestroyJoint(joint)` | Remove a joint. |

## World queries

| Handler | Purpose |
|---------|---------|
| `b2CastRayClosest(world, x1, y1, x2, y2)` → bool | Cast a ray; returns true on hit. Then read the result: |
| `b2RayBody()` → body / `b2RayShape()` → shape | What was hit. |
| `b2RayX()` / `b2RayY()` / `b2RayNormalX()` / `b2RayNormalY()` / `b2RayFraction()` | Hit point, surface normal, and fraction along the ray. |
| `b2BodyAtPoint(world, x, y)` → body | The body whose shape covers a world point (`0` if none) - handy for click-picking. |

## Contact events

Call `b2ContactsUpdate(world)` once after each `b2Step`. It returns the number of
*begin-touch* events and snapshots both begin- and end-touch events; then read
the two body handles for each (indices are **1-based**).

| Handler | Purpose |
|---------|---------|
| `b2ContactsUpdate(world)` → beginCount | Snapshot this step's contact events. |
| `b2ContactBeginCount()` / `b2ContactEndCount()` → int | How many began / ended touching. |
| `b2ContactBeginBodyA(i)` / `b2ContactBeginBodyB(i)` → body | The pair that started touching. |
| `b2ContactEndBodyA(i)` / `b2ContactEndBodyB(i)` → body | The pair that stopped touching. |

## Shape-def builder (sensors, filtering, event flags)

Set any of these **before** creating a shape (`b2AddBox`/`Circle`/`Capsule`/
`Polygon`/`b2CreateChain`); they apply to the **next** shape only, then reset -
just like the polygon vertex builder. This adds sensors, collision filters, and
per-event flags to every existing creator without new variants.

| Handler | Purpose |
|---------|---------|
| `b2ShapeDefSensor(flag)` | Make the next shape a non-solid **sensor** (overlap events, no collision). |
| `b2ShapeDefFilter(category, mask, group)` | Collision filter for the next shape (category/mask up to 2^53-1; an out-of-range value makes the shim ignore the call). |
| `b2ShapeDefEnableContactEvents(flag)` / `b2ShapeDefEnableSensorEvents(flag)` / `b2ShapeDefEnableHitEvents(flag)` / `b2ShapeDefEnablePreSolveEvents(flag)` | Per-event flags for the next shape. |
| `b2ShapeDefMaterialId(id)` | User material id for the next shape. |
| `b2ShapeDefReset()` | Clear any pending options explicitly. |

## World tuning & info

| Handler | Purpose |
|---------|---------|
| `b2WorldGravityX(world)` / `b2WorldGravityY(world)` → m/s² | Read the gravity vector. |
| `b2SetRestitutionThreshold(world, value)` / `b2RestitutionThreshold(world)` → m/s | Speed below which collisions stop bouncing. |
| `b2SetHitEventThreshold(world, value)` / `b2HitEventThreshold(world)` → m/s | Approach speed above which a contact reports a hit event. |
| `b2SetContactTuning(world, hertz, damping, pushSpeed)` / `b2SetJointTuning(world, hertz, damping)` | Solver softness. |
| `b2SetMaximumLinearSpeed(world, value)` / `b2MaximumLinearSpeed(world)` → m/s | Clamp body speed. |
| `b2EnableWarmStarting(world, flag)` / `b2IsWarmStartingEnabled(world)` · `b2EnableSpeculative(world, flag)` · `b2IsSleepingEnabled(world)` / `b2IsContinuousEnabled(world)` | World toggles. Sleeping and continuous collision are switched by `b2EnableSleeping` / `b2EnableContinuous` (see [World](#world)); speculative collision has no getter. |
| `b2AwakeBodyCount(world)` → int | Number of awake bodies. |
| `b2WorldExplode(world, x, y, radius, falloff, impulsePerLength)` | Native radial impulse, shape-perimeter aware. |
| `b2WorldProfileUpdate(world)`, then `b2WorldProfileStep()` / `b2WorldProfilePairs()` / `b2WorldProfileCollide()` / `b2WorldProfileSolve()` / `b2WorldProfileRefit()` / `b2WorldProfileSensors()` → ms | Snapshot the last step's timings, then read them (milliseconds). A stale world handle zeroes the snapshot. |
| `b2WorldCountersUpdate(world)`, then `b2WorldBodyCount()` / `b2WorldShapeCount()` / `b2WorldContactCount()` / `b2WorldJointCount()` / `b2WorldIslandCount()` → int | Snapshot, then read the world's object counts. A stale world handle zeroes the snapshot. |

## Body - transforms, mass, enumeration

| Handler | Purpose |
|---------|---------|
| `b2BodyWorldPointX(body, localX, localY)` / `b2BodyWorldPointY(body, localX, localY)` → metres | A body-local point in world coordinates. |
| `b2BodyLocalPointX(body, worldX, worldY)` / `b2BodyLocalPointY(body, worldX, worldY)` → metres | A world point in the body's local frame. |
| `b2BodyWorldVectorX(body, localX, localY)` / `b2BodyWorldVectorY(body, localX, localY)` | Rotate a local vector into the world frame (no translation). |
| `b2BodyLocalVectorX(body, worldX, worldY)` / `b2BodyLocalVectorY(body, worldX, worldY)` | Rotate a world vector into the body frame. |
| `b2BodyWorldPointVelocityX(body, worldX, worldY)` / `b2BodyWorldPointVelocityY(body, worldX, worldY)` → m/s | Velocity of the body at a WORLD point (linear plus the spin's contribution). |
| `b2BodyLocalPointVelocityX(body, localX, localY)` / `b2BodyLocalPointVelocityY(body, localX, localY)` → m/s | The same for a body-LOCAL point. |
| `b2ApplyForceAt(body, fx, fy, px, py, wake)` / `b2ApplyImpulseAt(body, ix, iy, px, py, wake)` | Force / impulse at a world point (adds torque). |
| `b2BodyRotationalInertia(body)` → kg·m² · `b2BodyLocalCenterX(body)` / `b2BodyLocalCenterY(body)` → metres | Rotational inertia, and the centre of mass in the body frame. |
| `b2BodyMassDataUpdate(body)`, then `b2MassDataMass()` → kg / `b2MassDataCenterX()` / `b2MassDataCenterY()` → local metres / `b2MassDataInertia()` → kg·m² | Snapshot a body's mass data, then read it. `b2ShapeMassDataUpdate(shape)` fills the same four readers for one shape. |
| `b2SetMassData(body, mass, cx, cy, inertia)` / `b2ApplyMassFromShapes(body)` | Override / recompute mass. |
| `b2SetTargetTransform(body, x, y, angle, timeStep)` | Drive a kinematic body to a pose. |
| `b2EnableSleep(body, flag)` / `b2BodyIsSleepEnabled(body)` · `b2BodyIsFixedRotation(body)` · `b2BodyEnableContactEvents(body, flag)` / `b2BodyEnableHitEvents(body, flag)` | Per-body flags. |
| `b2BodyAABBUpdate(body)`, then `b2AABBLowerX()` / `b2AABBLowerY()` / `b2AABBUpperX()` / `b2AABBUpperY()` → metres | Snapshot a body's bounding box, then read its corners. `b2ShapeAABBUpdate(shape)` fills the same four readers for one shape. |
| `b2BodyShapeCount(body)`, then `b2BodyShapeAt(i)` → shape · `b2BodyJointCount(body)`, then `b2BodyJointAt(i)` → joint | Enumerate a body's shapes / joints (1-based). |

## Shape - filter, geometry, material, queries

| Handler | Purpose |
|---------|---------|
| `b2ShapeType(shape)` → code | `0` circle, `1` capsule, `2` segment, `3` polygon, `4` chain segment. A stale handle also reads `0`. |
| `b2ShapeIsSensor(shape)` → bool | Is it a sensor? |
| `b2ShapeDensity(shape)` / `b2ShapeFriction(shape)` / `b2ShapeRestitution(shape)` | Read the material (set it with `b2SetShapeDensity` / `b2SetShapeFriction` / `b2SetShapeRestitution`). |
| `b2ShapeMaterialId(shape)` / `b2SetShapeMaterialId(shape, id)` | User material id. |
| `b2SetShapeFilter(shape, category, mask, group)` | Collision filtering. The setter accepts bits up to 2^53-1 and ignores the whole call otherwise; a default mask reads back as 2^64-1, so clamp before writing it back (xTalk's `bitAnd`/`bitOr` are 32-bit anyway). |
| `b2ShapeFilterCategory(shape)` / `b2ShapeFilterMask(shape)` → number · `b2ShapeFilterGroup(shape)` → int | Read the filter. The bits come back as a Number, not an Integer, because they are 64-bit in Box2D. |
| `b2ShapeEnableSensorEvents(shape, flag)` / `b2ShapeSensorEventsEnabled(shape)` | Sensor-event flag (both a sensor and its visitor need it). |
| `b2ShapeEnableContactEvents(shape, flag)` / `b2ShapeContactEventsEnabled(shape)` | Begin/end contact-event flag. |
| `b2ShapeEnableHitEvents(shape, flag)` / `b2ShapeHitEventsEnabled(shape)` | Hit-event flag. |
| `b2ShapeEnablePreSolveEvents(shape, flag)` | Pre-solve flag. It has no getter, and the binding exposes no pre-solve callback (see the notes below). |
| `b2ShapeCircleUpdate(shape)`, then `b2ShapeCircleX()` / `b2ShapeCircleY()` / `b2ShapeCircleRadius()` → metres | Snapshot a circle's local centre and radius. A shape of another type, or a stale handle, reads all zeros. |
| `b2ShapeCapsuleUpdate(shape)`, then `b2ShapeCapsuleX1()` / `b2ShapeCapsuleY1()` / `b2ShapeCapsuleX2()` / `b2ShapeCapsuleY2()` / `b2ShapeCapsuleRadius()` → metres | A capsule's two local centres and radius; zeros for another type. |
| `b2ShapeSegmentUpdate(shape)`, then `b2ShapeSegmentX1()` / `b2ShapeSegmentY1()` / `b2ShapeSegmentX2()` / `b2ShapeSegmentY2()` → metres | A segment's two local end points; zeros for another type. |
| `b2ShapePolygonUpdate(shape)` → vertex count, then `b2ShapePolygonCount()` / `b2ShapePolygonVertexX(i)` / `b2ShapePolygonVertexY(i)` / `b2ShapePolygonRadius()` | A polygon's local vertices (1-based; out of range reads `0`) and its rounding radius. A non-polygon or stale handle gives a count of `0`, but does NOT reset the radius: read `b2ShapePolygonRadius()` only after an update that returned a count above `0`. |
| `b2SetShapeCircle(shape, cx, cy, radius)` | Replace a shape's geometry in place (its type follows the write). Ignored unless the handle is live, the numbers finite and the radius positive. |
| `b2SetShapeCapsule(shape, x1, y1, x2, y2, radius)` | The same for a capsule; also ignored when the two centres coincide. |
| `b2SetShapeSegment(shape, x1, y1, x2, y2)` | The same for a segment; ignored when the end points coincide. |
| `b2SetShapePolygon(shape)` | The same for a polygon, from the vertex builder (`b2PolyBegin` / `b2PolyAddPoint`); ignored under three points or when the hull degenerates. |
| `b2ShapeRayCast(shape, x1, y1, x2, y2)` → bool, then `b2ShapeRayX()` / `b2ShapeRayY()` / `b2ShapeRayNormalX()` / `b2ShapeRayNormalY()` / `b2ShapeRayFraction()` | Cast from (x1, y1) to (x2, y2) against ONE shape; the readers hold the hit point, surface normal and fraction, all zeros on a miss. |
| `b2ShapeClosestPointX(shape, targetX, targetY)` / `b2ShapeClosestPointY(shape, targetX, targetY)` → metres | The point on the shape nearest a world target. |
| `b2ShapeAABBUpdate(shape)` (→ `b2AABB...` above) · `b2ShapeMassDataUpdate(shape)` (→ `b2MassData...` above) | One shape's bounds / mass data. |
| `b2ShapeSensorCapacity(shape)` · `b2ShapeSensorOverlapsUpdate(shape)` → count, then `b2ShapeSensorOverlapCount()` / `b2ShapeSensorOverlapAt(i)` → shape | Poll the shapes overlapping a sensor (1-based). |

## Chains (smooth terrain)

| Handler | Purpose |
|---------|---------|
| `b2ChainBegin()` → `b2ChainAddPoint(x, y)` ... → `b2CreateChain(body, loop, friction, restitution)` → chain | Build a chain (≥ 4 points; loop closes it). A non-loop chain's first & last points are ghost vertices (n points → n-3 collidable segments). |
| `b2DestroyChain(chain)` · `b2ChainIsValid(chain)` → bool | Lifetime. |
| `b2SetChainFriction(chain, friction)` / `b2ChainFriction(chain)` · `b2SetChainRestitution(chain, restitution)` / `b2ChainRestitution(chain)` | The material of every segment. |
| `b2ChainSegmentCount(chain)`, then `b2ChainSegmentAt(i)` → shape | Enumerate the segment shapes (1-based). |

## Joints - generic, motor, filter

| Handler | Purpose |
|---------|---------|
| `b2JointType(joint)` → code | `0` distance, `1` filter, `2` motor, `3` mouse, `4` prismatic, `5` revolute, `6` weld, `7` wheel (each asserted by `tests/smoke_test.c`). A stale handle ALSO reads `0`, so this cannot tell a distance joint from a dead one. |
| `b2JointBodyA(joint)` / `b2JointBodyB(joint)` → body | The two bodies. |
| `b2JointLocalAnchorAX(joint)` / `b2JointLocalAnchorAY(joint)` / `b2JointLocalAnchorBX(joint)` / `b2JointLocalAnchorBY(joint)` → metres | The anchors, each in its own body's local frame. |
| `b2JointCollideConnected(joint)` / `b2SetJointCollideConnected(joint, flag)` | Do the two joined bodies collide with each other? |
| `b2JointConstraintForceX(joint)` / `b2JointConstraintForceY(joint)` → N · `b2JointConstraintTorque(joint)` → N·m | What the joint applied on the last step; compare against a threshold for a breakable joint. |
| `b2JointWakeBodies(joint)` | Wake both bodies. |
| `b2MotorJoint(world, bodyA, bodyB, offsetX, offsetY, angularOffset, maxForce, maxTorque, correctionFactor, collide)` → joint | **Motor joint**: drive bodyB toward a pose offset from bodyA (offset in metres in bodyA's frame, angle in radians). |
| `b2MotorSetLinearOffset(joint, x, y)` / `b2MotorLinearOffsetX(joint)` / `b2MotorLinearOffsetY(joint)` → metres | The target offset. |
| `b2MotorSetAngularOffset(joint, angle)` / `b2MotorAngularOffset(joint)` → radians | The target angle. |
| `b2MotorSetMaxForce(joint, force)` / `b2MotorMaxForce(joint)` → N · `b2MotorSetMaxTorque(joint, torque)` / `b2MotorMaxTorque(joint)` → N·m | How hard it may push; a negative value is ignored. |
| `b2MotorSetCorrectionFactor(joint, factor)` / `b2MotorCorrectionFactor(joint)` | Position correction (Box2D expects 0 to 1). |
| `b2FilterJoint(world, bodyA, bodyB)` → joint | **Filter joint**: disable collision between exactly these two bodies. |

**The per-type accessors below check that the joint handle is live, not that
it names a joint of that type.** Hand a revolute reader a prismatic joint and
the shim passes it to Box2D anyway; it is not a guarded no-op. Check
`b2JointType` when you do not know a handle's type. Throughout, a setter
ignores a non-finite value, and a spring rate, damping ratio, force or torque
below zero; a getter on a stale handle returns `0` (`false` for the `Is...`
readers).

## Joints - revolute

Created by `b2RevoluteJoint`; limit and motor are switched on together with
their values by `b2RevoluteEnableLimit` / `b2RevoluteEnableMotor` (see
[Joints](#joints)).

| Handler | Purpose |
|---------|---------|
| `b2RevoluteEnableSpring(joint, flag)` / `b2RevoluteIsSpringEnabled(joint)` | A rotational spring on the hinge. |
| `b2RevoluteSetSpringHertz(joint, hertz)` / `b2RevoluteSpringHertz(joint)` · `b2RevoluteSetSpringDamping(joint, ratio)` / `b2RevoluteSpringDamping(joint)` | Spring stiffness (Hz) and damping ratio. |
| `b2RevoluteIsLimitEnabled(joint)` · `b2RevoluteLowerLimit(joint)` / `b2RevoluteUpperLimit(joint)` → radians | Read the limit. `b2RevoluteEnableLimit` clamps both ends into ±0.95π, as Box2D requires. |
| `b2RevoluteIsMotorEnabled(joint)` · `b2RevoluteSetMotorSpeed(joint, speed)` / `b2RevoluteMotorSpeed(joint)` → rad/s | Motor state and target speed. |
| `b2RevoluteSetMaxMotorTorque(joint, torque)` / `b2RevoluteMaxMotorTorque(joint)` · `b2RevoluteMotorTorque(joint)` → N·m | The motor's cap, and the torque it applied on the last step. |

## Joints - prismatic

Created by `b2PrismaticJoint`; limit and motor via `b2PrismaticEnableLimit` /
`b2PrismaticEnableMotor`.

| Handler | Purpose |
|---------|---------|
| `b2PrismaticEnableSpring(joint, flag)` / `b2PrismaticIsSpringEnabled(joint)` | A spring along the axis. |
| `b2PrismaticSetSpringHertz(joint, hertz)` / `b2PrismaticSpringHertz(joint)` · `b2PrismaticSetSpringDamping(joint, ratio)` / `b2PrismaticSpringDamping(joint)` | Spring stiffness (Hz) and damping ratio. |
| `b2PrismaticIsLimitEnabled(joint)` · `b2PrismaticLowerLimit(joint)` / `b2PrismaticUpperLimit(joint)` → metres | Read the limit. |
| `b2PrismaticIsMotorEnabled(joint)` · `b2PrismaticSetMotorSpeed(joint, speed)` / `b2PrismaticMotorSpeed(joint)` → m/s | Motor state and target speed. |
| `b2PrismaticMaxMotorForce(joint)` · `b2PrismaticMotorForce(joint)` → N | The cap (set by `b2PrismaticEnableMotor`; there is no separate setter), and the force applied on the last step. |
| `b2PrismaticSpeed(joint)` → m/s | The current sliding speed; `b2PrismaticTranslation` is the position. |

## Joints - distance

Created by `b2DistanceJoint`; spring via `b2DistanceEnableSpring`, range via
`b2DistanceSetLengthRange` (which also switches the limit on).

| Handler | Purpose |
|---------|---------|
| `b2DistanceIsSpringEnabled(joint)` · `b2DistanceSpringHertz(joint)` / `b2DistanceSpringDamping(joint)` | Spring state. |
| `b2DistanceIsLimitEnabled(joint)` · `b2DistanceMinLength(joint)` / `b2DistanceMaxLength(joint)` → metres | The range. |
| `b2DistanceCurrentLength(joint)` → metres | The separation right now; `b2DistanceLength` is the rest length. |
| `b2DistanceEnableMotor(joint, flag)` / `b2DistanceIsMotorEnabled(joint)` · `b2DistanceSetMotorSpeed(joint, speed)` / `b2DistanceMotorSpeed(joint)` → m/s | A motor along the link. Box2D v3.1 solves it only in spring mode, so enable the spring first; at speed `0` it holds the CURRENT separation, not the rest length (both measured by the smoke test's fixtures). |
| `b2DistanceSetMaxMotorForce(joint, force)` / `b2DistanceMaxMotorForce(joint)` · `b2DistanceMotorForce(joint)` → N | The motor's cap, and the force applied on the last step. |

## Joints - weld

Created by `b2WeldJoint`; stiffness via `b2WeldSetStiffness`.

| Handler | Purpose |
|---------|---------|
| `b2WeldReferenceAngle(joint)` / `b2WeldSetReferenceAngle(joint, angle)` → radians | The locked relative angle of bodyB to bodyA. |
| `b2WeldLinearHertz(joint)` / `b2WeldLinearDamping(joint)` · `b2WeldAngularHertz(joint)` / `b2WeldAngularDamping(joint)` | Read the stiffness `b2WeldSetStiffness` set (`0` Hz = rigid). |

## Joints - wheel

Created by `b2WheelJoint`; suspension and drive via `b2WheelEnableSpring` /
`b2WheelEnableMotor`.

| Handler | Purpose |
|---------|---------|
| `b2WheelIsSpringEnabled(joint)` · `b2WheelSpringHertz(joint)` / `b2WheelSpringDamping(joint)` | Suspension state. |
| `b2WheelEnableLimit(joint, flag)` / `b2WheelIsLimitEnabled(joint)` | Limit the suspension travel. |
| `b2WheelSetLimits(joint, lower, upper)` / `b2WheelLowerLimit(joint)` / `b2WheelUpperLimit(joint)` → metres | The travel range along the axis. The setter ignores lower > upper and does not switch the limit on. |
| `b2WheelIsMotorEnabled(joint)` · `b2WheelMotorSpeed(joint)` → rad/s | Drive state and target spin. |
| `b2WheelMaxMotorTorque(joint)` · `b2WheelMotorTorque(joint)` → N·m | The drive's cap, and the torque applied on the last step. |

## Joints - mouse

Created by `b2MouseJoint`; the target moves with `b2MouseSetTarget`.

| Handler | Purpose |
|---------|---------|
| `b2MouseTargetX(joint)` / `b2MouseTargetY(joint)` → metres | The current world target. |
| `b2MouseSetSpringHertz(joint, hertz)` / `b2MouseSpringHertz(joint)` · `b2MouseSetSpringDamping(joint, ratio)` / `b2MouseSpringDamping(joint)` | How softly the body follows. |
| `b2MouseSetMaxForce(joint, force)` / `b2MouseMaxForce(joint)` → N | How hard it may pull. |

## World queries (overlap / ray-cast-all / shape-cast)

Each query runs, stashes its hits in one shared buffer, and returns the count;
then read rows **1-based**. (`b2CastRayClosest` / `b2BodyAtPoint` above remain for
single-result use.)

| Handler | Purpose |
|---------|---------|
| `b2OverlapAABB(world, x1, y1, x2, y2)` · `b2OverlapPoint(world, x, y)` · `b2OverlapCircle(world, cx, cy, r)` · `b2OverlapShape(world, radius)` (uses the vertex builder) | Find shapes overlapping a region. |
| `b2RayCastAll(world, x1, y1, x2, y2)` | Every shape along a ray, sorted near→far. |
| `b2ShapeCast(world, radius, dx, dy)` | Sweep a proxy (built from the vertex builder) and gather hits. |
| `b2QueryCount()` · `b2QueryBody(i)` / `b2QueryShape(i)` | The rows, and each row's body and shape. |
| `b2QueryX(i)` / `b2QueryY(i)` → metres · `b2QueryNormalX(i)` / `b2QueryNormalY(i)` · `b2QueryFraction(i)` | Each row's point, normal and fraction. The ray and shape casts fill all five; `b2OverlapPoint` fills the point only; the other overlaps leave them `0`. |

## Events - hit, sensor, body-move

All three read buffers indexed **1-based**; an index out of range reads `0`.

| Handler | Purpose |
|---------|---------|
| `b2ContactHitCount()` · `b2ContactHitBodyA(i)` / `b2ContactHitBodyB(i)` | **Hit** events (snapshotted by `b2ContactsUpdate`; needs hit events enabled): how many, and each pair. |
| `b2ContactHitX(i)` / `b2ContactHitY(i)` → metres · `b2ContactHitNormalX(i)` / `b2ContactHitNormalY(i)` · `b2ContactHitSpeed(i)` → m/s | Each hit's point, normal and approach speed. |
| `b2SensorsUpdate(world)` → begin count, then `b2SensorBeginCount()` / `b2SensorEndCount()` | **Sensor** events (both shapes need sensor events). |
| `b2SensorBeginSensorShape(i)` / `b2SensorBeginVisitorShape(i)` · `b2SensorEndSensorShape(i)` / `b2SensorEndVisitorShape(i)` → shape | Which sensor, and which visitor, began or ended overlapping. |
| `b2BodiesUpdate(world)` → move count, then `b2BodyMoveCount()` · `b2BodyMoveBody(i)` | **Body-move** events: every body that moved this step, in one call (efficient bulk sync). |
| `b2BodyMoveX(i)` / `b2BodyMoveY(i)` → metres · `b2BodyMoveAngle(i)` → radians · `b2BodyMoveFellAsleep(i)` → bool | Each moved body's new transform, and whether it fell asleep. |

## Notes and gotchas

**Units.** Box2D is tuned for **MKS units**; keep moving objects roughly
0.1-10 m and apply a pixels-per-metre scale only at draw time (the demo uses 40
and flips Y, since the sim's Y points up while the screen's points down).

**Fixed timestep.** Drive `b2Step` from a **fixed timestep** (the demo
accumulates real elapsed time and steps in 1/60 s chunks). Variable steps make
the solver jittery and non-deterministic.

**Handle lifetime.** A handle is only valid until you destroy it. Reading a
destroyed handle is safe (the shim validates ids and returns `0`), and handles
are *generation-tagged*: when a table slot is recycled by a new object, stale
handles to its previous occupant stay dead rather than addressing the new one.
Treat handles as opaque, and drop references when you destroy something.

**Rendering at scale.** For **many hundreds of bodies** the physics keeps up
easily, but updating that many individual OpenXTalk graphics each frame can become
the bottleneck. At that scale, draw into a single image/graphic, or move
rendering into an LCB widget canvas, rather than one control per body.

**Extending the binding.** See [architecture.md](architecture.md#extending-the-binding)
for the step-by-step recipe. As of ABI `3` the binding
covers the full Box2D v3.1 **live-object** surface (chains, sensors, filtering,
hit & body-move events, shape casts, motor/filter joints, world tuning, mass
data, ...). What's intentionally **not** wrapped: pre-solve / custom-filter
callbacks (no safe way to call back into xTalk mid-step) and Box2D's standalone
math/geometry/TOI helpers (they operate on raw structs, not world objects).
