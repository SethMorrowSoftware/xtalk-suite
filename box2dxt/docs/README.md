# Box2Dxt documentation

Box2Dxt is Box2D v3 physics for xTalk, plus the **b2k Kit** - a pure-script game
toolkit layered over it. Those are two surfaces with two audiences, and this
index is organised that way.

**Most people want the Kit.** Start at [getting-started.md](getting-started.md),
then [kit-guide.md](kit-guide.md).

| Document | What it is |
|---|---|
| **Start here** | |
| [getting-started.md](getting-started.md) | From nothing to a running, draggable physics scene. Assumes no prior physics knowledge. Read this first. |
| [kit-guide.md](kit-guide.md) | The complete guide to the b2k Kit: sprites, input, the player controller, the camera, audio. Written for xTalk users, start to finish. The longest doc here and the one most readers actually need. |
| [kit-reference.md](kit-reference.md) | The `b2k*` reference for `src/box2dxt-kit.livecodescript`. You work in pixels, screen coordinates and degrees; the Kit converts. |
| **The raw binding** | |
| [api-reference.md](api-reference.md) | The low-level `b2*` binding exposed by `src/box2dxt.lcb`, mirroring the Box2D v3 surface. **Incomplete: it documents roughly 231 of 376 public handlers.** The undocumented remainder is mostly joint accessors (`b2Distance*`, `b2Joint*` anchors, `b2Chain*` friction/restitution) and the AABB upper/lower pairs. Measured 2026-08-26; this member is the only one in the suite below 100 percent. |
| [architecture.md](architecture.md) | How the three layers fit, why the shim exists, and how to extend the binding. |
| [building.md](building.md) | Building a fresh native library, or porting to a new platform. Most users can skip it: the per-platform binaries are committed. |
| **Plans and records** | |
| [archive/asset-expansion-plan.md](archive/asset-expansion-plan.md) | ARCHIVED, and FROZEN before that. Phases A-G shipped and the demo grew from 5 to seven polished levels. Forward feature development stopped for a polish pass. |
| [platformer-polish-plan.md](platformer-polish-plan.md) | The polish pass that asset expansion stopped for. Feature development on the platformer is frozen. |
| [archive/game-engine-spec.md](archive/game-engine-spec.md) | ARCHIVED. The pre-implementation design spec for the Kit modules. They all shipped; kept for the reasoning. |
| [archive/expansion-prep.md](archive/expansion-prep.md) | ARCHIVED. The pre-implementation intake plan for the asset pack and the Wave 0-8 content phases. Those waves shipped. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
