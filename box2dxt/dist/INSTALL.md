# Box2Dxt Platformer — Install & Run

Everything needed to run the **Box2Dxt** physics platformer is in this package —
no C compiler, no internet, and **no separate library files to download, rename,
or copy into system folders**. You just need **OpenXTalk (OXT)** installed (the
demo is an OXT `.oxtstack`; the extension is also compatible with **LiveCode
9.6.3+**).

## What's in this package

```
NewPlateformerDemo.oxtstack    ← the platformer stack (you open this)
box2dxt.lce                    ← the Box2Dxt extension, ready to install
                                  (only if the packager included a prebuilt one)
extension/                     ← the same extension as source, ready to (re)build
├── box2dxt.lcb                ← the b2… physics API
└── code/                      ← the native physics library, bundled per platform
    ├── x86_64-linux/box2dxt.so
    ├── x86-linux/box2dxt.so
    ├── x86_64-win32/box2dxt.dll
    ├── x86-win32/box2dxt.dll
    └── universal-mac/box2dxt.dylib
source/                        ← box2d_lc.c, box2dxt-kit.livecodescript (reference)
spritesheets/                  ← the demo's art (point the stack here on first run)
```

The native physics library lives **inside the extension** (the `code/` folder).
When you install the extension, the engine loads the correct library for your OS
automatically — **nothing to place in `/usr/lib`, rename, or drop beside the
stack, on any platform.** This is the whole point of the new packaging.

---

## Step 1 · Install the Box2Dxt extension

**If this package includes `box2dxt.lce`:**

1. Launch **OXT**.
2. **Tools → Extension Manager → + (Install)**, choose **`box2dxt.lce`**, install.

**Otherwise, build it from `extension/` (a few clicks):**

1. **Tools → Extension Builder**.
2. Open **`extension/box2dxt.lcb`**, click **Package** — this rolls the `code/`
   libraries into a `.lce` — then install it. (Or click **Test** to compile and
   load it in place.)

Either way the matching native library for your platform is bundled in and loads
automatically — Windows, macOS, and Linux alike, on OXT or LiveCode 9.6.3+.

**Confirm it worked:** open the Message Box (Ctrl/Cmd-M), type `put b2Version()`,
press Enter. You should see **`4`**. If not, see *Troubleshooting*.

---

## Step 2 · Open the platformer

Open **`NewPlateformerDemo.oxtstack`** (File → Open Stack…, or double-click it).
The game builds itself and starts immediately.

- **First run** asks you to locate a spritesheet folder — choose the
  **`spritesheets/`** folder in this package. After you **save** the stack the
  art is remembered (and cached), so it loads instantly every time after.
- **Controls:** **arrows / WASD** move · **Space** jump (press again in mid-air
  to **double-jump**, or off a wall to **wall-jump**) · **SHIFT / X** dash ·
  **↓** duck · **R** restart · **M** mute. Grab every coin (the flag turns gold)
  and touch the flag to advance — there are seven levels (and **1–5** picks your
  hero skin).

That's it. Enjoy the physics.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `b2Version()` errors, or "handler not found" | The extension isn't installed/loaded. Redo **Step 1** (install the `.lce`, or Package `extension/box2dxt.lcb`). It loads per IDE session. |
| First physics call says **"unable to load foreign library"** | The extension was loaded *without* its bundled library. Make sure you installed the `.lce` (or Packaged **`extension/box2dxt.lcb`** — which must keep its `code/` folder right beside it). *Quick fallback:* drop `box2dxt.{dll,dylib,so}` next to your **saved** stack and reopen — the Kit will point the engine at it. |
| `b2Version()` returns a number **other than 4** | Your extension and library are from different builds. Reinstall the extension from **this** package. |
| The level loads with plain placeholder shapes (no art) | On first run, point the spritesheet prompt at this package's **`spritesheets/`** folder, then **save** the stack. (Hold **Shift** while pressing **R** to re-pick the folder.) |

---

*Box2Dxt is the Box2D v3 physics engine packaged for OpenXTalk and the xTalk
language family. The platformer is one of several example games. The native
library ships inside the extension (`code/<platform>/`), so installing the
extension is the only setup step — no system-folder copies, no `sudo`. For the
complete toolkit and documentation, see the project repository.*
