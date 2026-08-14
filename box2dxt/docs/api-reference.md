# Box2Dxt API Reference (`b2…`)

This is the full, low-level binding exposed by `src/box2dxt.lcb`. It mirrors the
Box2D v3 surface closely. For everyday work, the higher-level
[Kit (`b2k…`)](kit-reference.md) is usually easier — reach for these handlers
when you need something the Kit doesn't expose.

**Conventions**

- Handles are integers; **`0` is invalid**. Every handler tolerates a stale or
  `0` handle (getters return `0`, actions do nothing) — the C shim validates ids.
- Distances are **metres**, angles are **radians**. Convert to pixels/degrees at
  draw time.
- Body type codes: `0` static, `1` kinematic, `2` dynamic.
- `b2Version()` → int returns the shim ABI version (currently `4`) — call it once
  as a load/version check that the extension and native library are in sync.

- [World](#world)
- [Bodies](#bodies)
- [Shapes](#shapes)
- [Joints](#joints)
- [World queries](#world-queries)
- [Contact events](#contact-events)
- [Notes and gotchas](#notes-and-gotchas)

---

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
| `b2AddSegment(body, x1, y1, x2, y2, friction, restitution)` | Line edge (best on static bodies). **Two-sided** — bodies collide with it from either side regardless of point order (confirmed empirically, Game Kit Phase 0 spike). For one-sided platforms/terrain use a **chain**: chain segments are the one-sided primitive. |
| `b2PolyBegin()` → `b2PolyAddPoint(x, y)` … → `b2AddPolygon(body, density, friction, restitution)` | Build a convex polygon (≤ 8 points) without marshalling arrays. |
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
| `b2DistanceLength(joint)` → metres | Current length. |
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
| `b2BodyAtPoint(world, x, y)` → body | The body whose shape covers a world point (`0` if none) — handy for click-picking. |

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
`Polygon`/`b2CreateChain`); they apply to the **next** shape only, then reset —
just like the polygon vertex builder. This adds sensors, collision filters, and
per-event flags to every existing creator without new variants.

| Handler | Purpose |
|---------|---------|
| `b2ShapeDefSensor(flag)` | Make the next shape a non-solid **sensor** (overlap events, no collision). |
| `b2ShapeDefFilter(category, mask, group)` | Collision filter for the next shape (category/mask are 32-bit). |
| `b2ShapeDefEnableContactEvents(flag)` / `b2ShapeDefEnableSensorEvents(flag)` / `b2ShapeDefEnableHitEvents(flag)` / `b2ShapeDefEnablePreSolveEvents(flag)` | Per-event flags for the next shape. |
| `b2ShapeDefMaterialId(id)` | User material id for the next shape. |
| `b2ShapeDefReset()` | Clear any pending options explicitly. |

## World tuning & info

| Handler | Purpose |
|---------|---------|
| `b2WorldGravityX(world)` / `b2WorldGravityY(world)` | Read the gravity vector. |
| `b2SetRestitutionThreshold` / `b2RestitutionThreshold(world)` | Speed below which collisions stop bouncing. |
| `b2SetHitEventThreshold` / `b2HitEventThreshold(world)` | Approach speed above which a contact reports a hit event. |
| `b2SetContactTuning(world, hertz, damping, pushSpeed)` / `b2SetJointTuning(world, hertz, damping)` | Solver softness. |
| `b2SetMaximumLinearSpeed` / `b2MaximumLinearSpeed(world)` | Clamp body speed. |
| `b2EnableWarmStarting` / `b2IsWarmStartingEnabled` · `b2EnableSpeculative` · `b2IsSleepingEnabled` / `b2IsContinuousEnabled` | World toggles. |
| `b2AwakeBodyCount(world)` | Number of awake bodies. |
| `b2WorldExplode(world, x, y, radius, falloff, impulsePerLength)` | Native radial impulse, shape-perimeter aware. |
| `b2WorldProfileUpdate(world)` → `b2WorldProfileStep/Pairs/Collide/Solve/Refit/Sensors()` | Per-step timing (ms). |
| `b2WorldCountersUpdate(world)` → `b2WorldBodyCount/ShapeCount/ContactCount/JointCount/IslandCount()` | World object counts. |

## Body — transforms, mass, enumeration

| Handler | Purpose |
|---------|---------|
| `b2BodyWorldPointX/Y` · `b2BodyLocalPointX/Y` · `b2BodyWorldVectorX/Y` · `b2BodyLocalVectorX/Y` | Local↔world point & vector transforms. |
| `b2BodyWorldPointVelocityX/Y` · `b2BodyLocalPointVelocityX/Y` | Velocity of a point on the body. |
| `b2ApplyForceAt(body, fx, fy, px, py, wake)` / `b2ApplyImpulseAt(...)` | Force / impulse at a world point (adds torque). |
| `b2BodyRotationalInertia` · `b2BodyLocalCenterX/Y` | Inertia and local centre of mass. |
| `b2BodyMassDataUpdate(body)` → `b2MassDataMass/CenterX/CenterY/Inertia()` | Read mass data. |
| `b2SetMassData(body, mass, cx, cy, inertia)` / `b2ApplyMassFromShapes(body)` | Override / recompute mass. |
| `b2SetTargetTransform(body, x, y, angle, timeStep)` | Drive a kinematic body to a pose. |
| `b2EnableSleep` / `b2BodyIsSleepEnabled` · `b2BodyIsFixedRotation` · `b2BodyEnableContactEvents` / `b2BodyEnableHitEvents` | Per-body flags. |
| `b2BodyAABBUpdate(body)` → `b2AABBLowerX/LowerY/UpperX/UpperY()` | Body AABB. |
| `b2BodyShapeCount(body)` → `b2BodyShapeAt(i)` · `b2BodyJointCount(body)` → `b2BodyJointAt(i)` | Enumerate a body's shapes / joints (1-based). |

## Shape — filter, geometry, material, queries

| Handler | Purpose |
|---------|---------|
| `b2ShapeType` · `b2ShapeIsSensor` · `b2ShapeDensity/Friction/Restitution` · `b2ShapeMaterialId` / `b2SetShapeMaterialId` | Read type / material. |
| `b2SetShapeFilter(shape, category, mask, group)` · `b2ShapeFilterCategory/Mask/Group(shape)` | Collision filtering (32-bit bits). |
| `b2ShapeEnableSensorEvents` / `…Contact…` / `…Hit…` / `…PreSolve…` + the matching `…EventsEnabled` getters | Per-shape event flags. |
| `b2ShapeCircleUpdate/Capsule…/Segment…/PolygonUpdate(shape)` + their `…X/Y/Radius/VertexX/VertexY` readers | Read a shape's geometry. |
| `b2SetShapeCircle/Capsule/Segment(shape, …)` · `b2SetShapePolygon(shape)` (uses the vertex builder) | Replace a shape's geometry in place. |
| `b2ShapeRayCast(shape, x1, y1, x2, y2)` → `b2ShapeRayX/Y/NormalX/NormalY/Fraction()` | Ray cast against one shape. |
| `b2ShapeAABBUpdate` (→ `b2AABB…`) · `b2ShapeClosestPointX/Y` · `b2ShapeMassDataUpdate` (→ `b2MassData…`) | Bounds / closest point / mass. |
| `b2ShapeSensorCapacity` · `b2ShapeSensorOverlapsUpdate(shape)` → `b2ShapeSensorOverlapCount()` / `b2ShapeSensorOverlapAt(i)` | Poll shapes overlapping a sensor. |

## Chains (smooth terrain)

| Handler | Purpose |
|---------|---------|
| `b2ChainBegin()` → `b2ChainAddPoint(x, y)` … → `b2CreateChain(body, loop, friction, restitution)` → chain | Build a chain (≥ 4 points; loop closes it). A non-loop chain's first & last points are ghost vertices (n points → n−3 collidable segments). |
| `b2DestroyChain(chain)` · `b2ChainIsValid(chain)` | Lifetime. |
| `b2SetChainFriction/Restitution` + getters · `b2ChainSegmentCount(chain)` → `b2ChainSegmentAt(i)` | Tune / enumerate segments. |

## Joints — generic, new types, full per-joint control

| Handler | Purpose |
|---------|---------|
| `b2JointType` · `b2JointBodyA/B` · `b2JointLocalAnchorAX/AY/BX/BY` · `b2JointCollideConnected` / `b2SetJointCollideConnected` · `b2JointConstraintForceX/Y` · `b2JointConstraintTorque` · `b2JointWakeBodies` | Generic joint surface (constraint force/torque is handy for breakable joints). |
| `b2MotorJoint(world, bodyA, bodyB, offsetX, offsetY, angularOffset, maxForce, maxTorque, correction, collide)` + `b2MotorSet/Get…` | **Motor joint** — drive bodyB to an offset pose from bodyA. |
| `b2FilterJoint(world, bodyA, bodyB)` | **Filter joint** — disable collision between exactly these two bodies. |
| `b2Revolute…` / `b2Prismatic…` / `b2Distance…` / `b2Weld…` / `b2Wheel…` / `b2Mouse…` | The **complete** per-joint get/set surface for all six existing joint types: spring enable/hertz/damping, limit enable/lower/upper, motor enable/speed/force\|torque, and readouts (angle, translation, speed, current length, reference angle, target). |

## World queries (overlap / ray-cast-all / shape-cast)

Each query runs, stashes its hits in one shared buffer, and returns the count;
then read rows **1-based**. (`b2CastRayClosest` / `b2BodyAtPoint` above remain for
single-result use.)

| Handler | Purpose |
|---------|---------|
| `b2OverlapAABB(world, x1, y1, x2, y2)` · `b2OverlapPoint(world, x, y)` · `b2OverlapCircle(world, cx, cy, r)` · `b2OverlapShape(world, radius)` (uses the vertex builder) | Find shapes overlapping a region. |
| `b2RayCastAll(world, x1, y1, x2, y2)` | Every shape along a ray, sorted near→far. |
| `b2ShapeCast(world, radius, dx, dy)` | Sweep a proxy (built from the vertex builder) and gather hits. |
| `b2QueryCount()` · `b2QueryBody(i)` / `b2QueryShape(i)` · `b2QueryX/Y(i)` · `b2QueryNormalX/Y(i)` · `b2QueryFraction(i)` | Read the shared result rows. |

## Events — hit, sensor, body-move

| Handler | Purpose |
|---------|---------|
| `b2ContactHitCount()` · `b2ContactHitBodyA/B(i)` · `b2ContactHitX/Y(i)` · `b2ContactHitNormalX/Y(i)` · `b2ContactHitSpeed(i)` | **Hit** events (snapshotted by `b2ContactsUpdate`; needs hit events enabled). |
| `b2SensorsUpdate(world)` → `b2SensorBeginCount/EndCount()` · `b2SensorBeginSensorShape/VisitorShape(i)` · `b2SensorEndSensorShape/VisitorShape(i)` | **Sensor** events (shape handles; both shapes need sensor events). |
| `b2BodiesUpdate(world)` → `b2BodyMoveCount()` · `b2BodyMoveBody(i)` · `b2BodyMoveX/Y/Angle(i)` · `b2BodyMoveFellAsleep(i)` | **Body-move** events — read every moved transform in one call (efficient bulk sync). |

## Notes and gotchas

**Units.** Box2D is tuned for **MKS units**; keep moving objects roughly
0.1–10 m and apply a pixels-per-metre scale only at draw time (the demo uses 40
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
for the step-by-step recipe (add a `b2lc_*` C function, a `foreign handler`, and
a public wrapper; bump `LC_ABI_VERSION`; rebuild). As of ABI `3` the binding
covers the full Box2D v3.1 **live-object** surface (chains, sensors, filtering,
hit & body-move events, shape casts, motor/filter joints, world tuning, mass
data, …). What's intentionally **not** wrapped: pre-solve / custom-filter
callbacks (no safe way to call back into xTalk mid-step) and Box2D's standalone
math/geometry/TOI helpers (they operate on raw structs, not world objects).
