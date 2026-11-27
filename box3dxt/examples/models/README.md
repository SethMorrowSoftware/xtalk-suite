# Orb Island's models

The game's character, checkpoint flags, platforms, gate, clouds, trees,
grass, round isles, lift pads, vault walls, terraces, slabs, flying
enemies, fountain and coin blocks are built from these models
by [Kenney](https://kenney.nl), from three of his starter kits:

| Kit | Commit |
|---|---|
| [Starter Kit 3D Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) | 3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0 |
| [Starter Kit City Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder) | 4535092b740b378b700efd9df9e27a631815b84a |
| [Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS) | 185fd2326d74a5cf858cffc616f87cf9696f9cc0 |

Each kit's README says its 3D models are licensed
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public
domain). The kits' code is MIT; none of their code is used here.

| File | Used as |
|---|---|
| `character.glb` | the player |
| `flag.glb` | the checkpoint flags |
| `platform.glb` | the moving and turning platforms, and the pressure plates |
| `platform-falling.glb` | the crumbling platforms |
| `cloud.glb` | the clouds |
| `brick.glb` | the gate the plates open |
| `grass-trees-tall.glb`, `grass-trees.glb` | the stands of trees (City Builder; their square of ground left out) |
| `grass.glb` | the grass tufts |
| `platform-grass-large-round.glb` | the sky isle, the east islet and the floating platform |
| `platform-medium.glb` | the two lifts |
| `wall-high.glb` | the vault's walls (FPS) |
| `platform-large-grass.glb` | the two terraces of the second level (FPS) |
| `platform-large.glb` | the slabs of the west stair, the bridge and the climb to the summit |
| `enemy-flying.glb` | the two flying enemies (FPS) |
| `pavement-fountain.glb` | the fountain on the summit (City Builder) |
| `block-coin.glb` | the coin blocks |
| `grass-small.glb` | the small tufts on the upper levels |
| `colormap.png` | the palette the Platformer and City Builder models take their colours from (the two kits share it) |
| `colormap-fps.png` | the FPS kit's palette, renamed from its `colormap.png` |

The game is one paste-and-run file that also plays in a web page, so it
cannot load these files. `tools/build-game-models.py` turns them into OBJ
text with flat colours and writes that text into the game between the
`GAME MODELS` markers. If you change a file here, run the tool again; its
`--check` is one of the member's gates.
