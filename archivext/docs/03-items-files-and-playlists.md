# 03 - Items, files and playlists

> **Status: the playlist and file-rule sections ran green on a real OXT
> engine 2026-09-15 (the member harness's first engine contact, 357/359
> overall; the one red in this area was a wrong hand-written expectation,
> corrected); still needs a live archive.org pass.** The playlist engine is executed on every build over the synthetic
> fixtures for every kind, and its outputs are pinned by the KAT; the file-
> name rules have direct vectors against the oracle since 2026-09-15 (the
> mutation drive found that the fixtures alone could not see a stem rule
> break, because a fixture groups by `original`). What a fixture cannot say
> is whether a real item's file list still looks like the apps' mocks; the
> live pass is what settles that.

## An item

`axItemParse(pJson)` turns a `/metadata/<identifier>` body into:

| Key | Holds |
|---|---|
| `identifier` | from the metadata block |
| `metadata[field]` | every metadata field, as LINES (title, creator, date, year, mediatype, collection, subject, description, runtime, licenseurl, ...) |
| `files[i][field]` | every file's fields as lines: name, format, size, length, title, track, source (`original` / `derivative` / `metadata`), original, md5, ... |
| `filesCount`, `itemSize`, `server`, `dir` | the rest of the envelope |

A body of `{}` is the site's "no such item" and answers empty with a
"could not be found" reason. `axSearchParse` is the sibling for a search
body (`numFound`, `start`, `count`, `docs[i][field]` as lines), and
`axDocsTable(tResult, "identifier,title,year")` renders any result as
tab-separated lines for a table field, first value of each field.

## The file list, and the engine over it

An archive.org file list mixes originals, the site's derivatives of each
original, thumbnails, spectrograms, metadata sidecars, torrents and
placeholders. Each of the three apps wrote a rule that turns that list into
the thing a player wants, and the rules share one shape:

```
ACCEPT   the files of the right kind          axFileIsAudio / Video / Document / Image / Content
GROUP    the encodes of one thing together    axFileStem (audio), axVideoStem (video)
RANK     inside the group, to pick what to play
DERIVE   a title, a track number, a length    axTrackTitleClean, axPrettyName, axCleanTitle, axTrackNumber
ORDER    the groups
```

`axPlaylist(pItem, pKind)` is that shape once, with the KIND deciding each
step:

| Kind | Family | Accept | Group | Rank | Order |
|---|---|---|---|---|---|
| `audio-chapters` | librivox | audio files | by the original a derivative names (the AudioBooks `chapterStem`) | original MP3, then `_64kb`, then `_vbr`, then Ogg | track number, then natural name |
| `audio-tracks` | etree | audio files | by stem | VBR MP3 first for streaming, then 128k, 64k, Ogg, then lossless (FLAC / SHN) | natural name only |
| `video` | movies | video files minus the sentinels | by `normalizeBaseName` (`axVideoStem`) | MP4 first, then the largest encode; every encode kept as a variant | track number, then natural name |
| `documents` | texts | pdf, epub, djvu, txt, ... | none (one entry per file) | PDF listed first, then EPUB, DjVu, plain text | rank, then name |
| `images` | image | image files | none | none | natural name |
| `files` | anything | everything that is not a sidecar | none | none | natural name |

`axPlaylistKindFor(pFamily, pMediatype)` picks the kind: a family's own kind
when the family is known, else by the item's mediatype (`etree` and `audio`
to tracks, `movies` to video, `texts` to documents, `image` to images,
everything else to files). Passing `auto` to `axPlaylist` does the same
from the item itself.

Every entry carries `name`, `title`, `track`, `length` (seconds), `format`,
`size`, `url` (the download URL), `stem`, `index` (the file's position in
the item), and for video `quality` (the chosen encode's label) and
`variants` (`name|label|size|format` lines, best first). `axPlaylistTable`
renders a playlist as tab-separated lines: number, title, duration, format,
human size, and quality for video.

An item with no file of the asked kind answers empty with a reason - a
normal outcome for a text item asked for audio, so read the reason before
reporting it as an error.

## The name rules, one per app

- **`axFileStem`** (AudioBooks `chapterStem`): lower-case, drop the
  extension, drop a trailing `_64kb` / `_vbr` / `_orig` / `_original`, so
  every derivative of `pp_01_austen.mp3` shares a stem.
- **`axVideoStem`** (film club `normalizeBaseName`): drop the extension,
  then repeatedly strip a trailing video extension, a `_720p`-style
  resolution, and `_archive` / `_512kb` / `_h264` / `_hd` / `_sd`, until
  nothing changes; lower-case. `Show_E01_512kb.mp4` and `Show_E01.ogv` are
  one episode.
- **`axPrettyName`** (AudioBooks `prettifyFileName`): the file's own name
  as a title when it carries none - the stem with underscores as spaces.
- **`axTrackTitleClean`** (the tape finder's PHP): strip a leading
  `d1t01` / `t05` prefix and its separators, underscores and hyphens to
  spaces, whitespace collapsed (the collapse is ArchiveXT's one cosmetic
  addition).
- **`axCleanTitle`** (film club `getCleanTitle`): the file name minus its
  extension, minus the item title's letters-and-digits skeleton when the
  name starts with it, separators to spaces, `Untitled` when nothing is
  left.
- **`axQualityLabel`**: `1080p` / `720p` / `480p` / `360p` from a resolution
  in the name, `H.264`, `SD` (`_512kb`), `Archive`, else `Auto`.
- **`axSubjectTags`**: the AudioBooks tag chips - split on `;` and `|`,
  drop the noise words (librivox, audiobooks, audio, literature), drop
  anything 20 characters or longer, de-duplicate case-insensitively,
  capitalise, take the first N.

## Where the apps disagreed, and what ArchiveXT took

Each of these is recorded in the oracle's docstring too, because the oracle
had to pick the same side to agree with the script:

1. **The tape finder's MP3 dedup was inverted.** Its PHP kept the SECOND MP3
   of a repeated title and dropped a first-seen FLAC's later MP3. ArchiveXT
   ranks inside a group instead (VBR MP3 first), which is what the code
   reads as intending.
2. **The film club ignored file titles.** It keyed episode titles off the
   file NAME even when the file carried a `title`. ArchiveXT prefers a file
   title when present (the AudioBooks rule) and falls back to the film
   club's cleaner.
3. **Interleaved discs.** Ordering etree tracks track-number-first put
   `d1t01, d2t01, d1t02, ...` next to each other, because a track number
   restarts per disc. Tracks order by natural NAME only, which keeps the
   site's own `d1t01 ... d2t09` order; chapters and episodes, whose track
   numbers run through the whole item, still order by track first.
4. **The year.** The first run of EXACTLY four digits (`axYearOf`), where
   the PHP `/(\d{4})/` would take the first four of a longer run.
5. **Sentinels.** The film club's list of names that are never episodes
   (`__ia_thumb`, `_meta`, `_files`, `.ia` placeholders, the tiny
   `_archive.torrent`) is applied for every kind, not only video.

## Sizes and times

`axFormatBytes` is the film club's `formatFileSize` (B / KB / MB / GB / TB,
one decimal above KB, refusing non-numbers with empty); `axFormatTime` is
the tape finder's `m:ss` / `h:mm:ss`; `axDurationSeconds` reads the three
spellings of `length`. `axNaturalKey` / `axNaturalSort` are the natural
ordering under every list above: each digit run zero-padded to twelve
places, letters folded to lower case, so `part2` sorts before `part10`.
