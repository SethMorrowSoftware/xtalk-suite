# Card art — Kenney "Playing Cards Pack" (CC0)

`playingCards.png` + `playingCards.xml` are the 52-card face spritesheet, and
`playingCardBacks.png` + `playingCardBacks.xml` are the card-back spritesheet (15
designs: blue/green/red x5), both from the **Kenney Playing Cards Pack**, used for
the OXT (Box2Dxt "kit" mode) card rendering. The stack draws face-down cards with
one chosen back (`kHeCardBackFrame`, default `cardBack_red2`).

Kenney's card/boardgame collection contains cards, card backs, jokers and dice, but
**no poker chips** — chips are drawn procedurally (a colored disc), or a dedicated
CC0 chip pack can be added later if photographic chips are wanted.

- **Author:** Kenney (kenney.nl)
- **License:** **CC0 1.0 Universal** (public domain dedication) — no attribution
  required, but credited here anyway. See https://creativecommons.org/publicdomain/zero/1.0/
- **Source:** https://kenney.nl/assets/playing-cards-pack
- **Format:** a Starling/TextureAtlas XML (`<TextureAtlas>` / `<SubTexture>`) over a
  1024x2048 RGBA sheet; each card is 140x190. Frame names are `card<Suit><Rank>.png`
  (e.g. `cardSpades10.png`, `cardHeartsA.png`), plus one `cardJoker.png`. There is no
  card-back frame in this face sheet — the backs are the separate `playingCardBacks`
  sheet vendored alongside it.

The only local change from the upstream files is each atlas's `imagePath`, repointed
from `sheet.png` to the vendored PNG filename so a loader that resolves the image
relative to the XML finds it.

## How the stack uses it

The stack maps its internal card ids to these frame names in `heKenneyFrame`
(`src/holdem.livecodescript`), and `tools/atlas-kat.py` pins in CI that all 52 cards
resolve to frames that actually exist in this atlas.

## Where to put this folder (OXT)

Put the whole `assets/cards/` folder **next to the saved stack file** — i.e. so the
layout on disk is:

```
holdem.livecode            <- your saved stack
assets/
  cards/
    playingCards.png
    playingCards.xml
    playingCardBacks.png
    playingCardBacks.xml
```

`heKitTryInit` derives the atlas path from the stack's own folder
(`heStackFolder` -> `<that folder>/assets/cards/...`), so with the Box2Dxt Kit
installed it is found automatically — nothing to configure.

Two caveats: (1) the stack must be **saved to a file** for this to work; a stack
pasted into the message box and never saved has no folder to be relative to, so set
`uHeAtlasPath` / `uHeBacksPath` by hand (or just save the stack once). (2) To keep
the assets somewhere else, set those two custom properties to the explicit file
paths and they override the default. `b2kSheetLoadAtlas` takes the **`.png`** (its
sibling `.xml` is found automatically), so point them at the PNG — a `.xml` value is
also accepted and swapped to its `.png`.

Run **`heProbeKit`** in the message box to see exactly what the stack resolved: Kit
presence, the atlas path and whether it exists, loaded frame counts, and the pooled
sprite count.
