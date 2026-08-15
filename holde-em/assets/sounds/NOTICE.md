# Table sounds -- Kenney "Casino Audio" (CC0)

The 11 `.wav` files here are from the **Kenney Casino Audio** pack (54 sounds:
23 card handling, 19 chip handling, 12 dice), curated down to what a hold'em
table actually uses, for the stack's sound effects (v0.16.0).

- **Author:** Kenney (kenney.nl)
- **License:** **CC0 1.0 Universal** (public domain dedication) -- no attribution
  required, but credited here anyway. See https://creativecommons.org/publicdomain/zero/1.0/
- **Source:** https://kenney.nl/assets/casino-audio
- **Local change:** the upstream files are OGG/Vorbis, which the engine's
  `play`/`import audioClip` path does not decode; each was converted to
  **16-bit PCM WAV, mono** (stereo averaged), sample rate untouched (44100 Hz),
  peak-normalised only if it clipped (none did). No other edits.

| file | used for |
|---|---|
| cardSlide1/2.wav | hole cards dealt (alternating takes) |
| cardPlace1/2.wav | flop / turn / river landing (alternating) |
| cardShove1.wav | fold |
| chipLay1.wav | check (and the Sounds-toggle confirmation) |
| chipsHandle1/2.wav | call / bet / raise (alternating) |
| chipsCollide1.wav | all-in |
| chipsStack1.wav | pot settled to the winner |
| cardShuffle.wav | vendored + mapped, wired in the deal-animation increment |

## Where to put this folder (OXT)

Same rule as `assets/cards/`: the whole `assets/sounds/` folder sits **next to the
saved stack file**. `heSndTryInit` derives the path from the stack's own folder;
an explicit `uHeSoundsPath` custom property (pointing at the folder) overrides it.
Sounds import once as audioClips and then **persist inside the saved stack**, so
after one save the folder is only needed to re-import (`heSndReload`).

Run **`heProbeSounds`** in the message box to see what resolved: the folder, and
per file whether it exists on disk, is imported as a clip, and is playable. The
Settings panel's "Sounds: On/Off" button toggles playback (`gCfg["sounds"]`).

`tools/sounds-kat.py` pins in CI that every file listed in the stack's
`kHeSoundFiles` exists here, is engine-friendly (PCM16 mono 44100), and is
reachable from a sound kind -- and that nothing vendored drifts unlisted.
