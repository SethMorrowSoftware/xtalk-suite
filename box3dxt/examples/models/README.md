# Orb Island's models

The game's character, checkpoint flag, platforms, crumbling platforms,
pressure plates, gate and clouds are built from these models by
[Kenney](https://kenney.nl). They are from his
[Starter Kit 3D Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)
(commit 3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0). The kit's README says
its 3D models are licensed
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public
domain). The kit's code is MIT; none of its code is used here.

| File | Used as |
|---|---|
| `character.glb` | the player |
| `flag.glb` | the checkpoint flags |
| `platform.glb` | the moving and turning platforms, and the pressure plates |
| `platform-falling.glb` | the crumbling platforms |
| `cloud.glb` | the clouds |
| `brick.glb` | the gate the plates open |
| `colormap.png` | the palette every model takes its colours from |

The game is one paste-and-run file that also plays in a web page, so it
cannot load these files. `tools/build-game-models.py` turns them into OBJ
text with flat colours and writes that text into the game between the
`GAME MODELS` markers. If you change a file here, run the tool again; its
`--check` is one of the member's gates.
