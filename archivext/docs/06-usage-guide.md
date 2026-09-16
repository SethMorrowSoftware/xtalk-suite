# 06 - Usage guide: from zero to a playing stream

> **Status: the library compiled and its self-test ran on a real OXT engine
> 2026-09-15 (357/359, both reds fixed the same day; 363/363 on the re-run),
> and the first live legs went green the same evening - recipe 1's blocking
> search shape answered from the site, and a real metadata body arrived
> whole. On 2026-09-16 recipe 2's `search` kind arrived through the
> callback (four searches, three families) and recipe 4's playlist was
> built from a live item (58 chapters). Recipe 2's `item` kind and recipe 5
> (streaming) are still owed.** Every
> recipe below is written against the shipped library and the demo that
> carries it; the pure calls in them are executed on every build against
> the oracle. Where a recipe says "prints", that is what the fixtures say it
> prints.

The recipes are in the order an app grows. Each one is complete on its own.

## 0. Get the library into your stack

Nothing to install. Either:

- **Paste the demo.** Copy `examples/archivext-demo.livecodescript` into the
  script of a NEW stack, save, close, reopen. It carries the library and the
  member self-test, builds its window, and prints its boot self-check. Use it
  as the template for everything below (`onArchive` is the whole callback
  contract in one handler; `adDoSearch` is preset + text + filters to query
  to request; `adShowItem` is item to playlist to table).
- **Use the library.** Open `src/archivext.livecodescript` as a stack and
  `start using stack "archivext"`, or paste its contents into your own
  library stack. Check from the message box:

```
put axVersion()          -- ArchiveXT 0.1.0
put axProbeCapabilities()["hasUrlLib"]   -- true when the Internet library answers
```

## 1. A blocking search from the message box

For a script with nothing else to do, the `Sync` handlers are the shortest
path. They freeze the interpreter until the site answers, so keep them out
of anything with a window.

```
put axSearchSync("collection:(GratefulDead) AND year:[1977 TO 1977]", empty) into tResult
if tResult is empty then
   put axLastError()
else
   put tResult["numFound"] && "hits;" && tResult["count"] && "on this page" & return
   put axDocsTable(tResult, "identifier,title,date")
end if
```

`tResult["docs"][1]["title"]` is the first title. Every field is LINES: a
doc with two creators has two lines in `tResult["docs"][1]["creator"]`, and
`axFirst` / `axJoin` are the two spellings you need.

## 2. The asynchronous shape (anything with a window)

```
on openStack
   axInit the long id of this stack
   axSetCallback "onArchive"
   axSetTimeout 30
end openStack

on closeStack
   axShutdown
end closeStack

command startSearch pQuery
   local tOptions, tHandle
   put "identifier,title,creator,date,year" into tOptions["fields"]
   put "downloads desc" into tOptions["sort"]
   put 24 into tOptions["rows"]
   put 1 into tOptions["page"]
   put "results" into tOptions["tag"]
   put axSearch(pQuery, tOptions) into tHandle
   if tHandle is empty then
      answer axLastError()
   end if
end startSearch

on onArchive pHandle, pKind, pValue, pTag
   set the defaultStack to the short name of this stack   -- ALWAYS, first line
   if pKind is "search" then
      set the text of field "results" to axDocsTable(pValue, "identifier,title,date")
   else if pKind is "item" then
      showItem pValue
   else if pKind is "raw" then
      -- pValue is the body of an axFetchUrl
   else if pKind is "error" then
      answer "Archive.org:" && pValue
   end if
end onArchive
```

The first line of `onArchive` is not optional: the handler is reached from
an engine callback or a timer, and without the pin an unqualified `field
"results"` resolves against the defaultStack, not this stack (root
`docs/OXT-ENGINE-NOTES.md` 5.3). The suite's timer-stack-pin gate refuses a
demo that forgets it.

## 3. Presets, text, years and quick filters in one call

Each family's catalogue is data, and `axPresetSpec` is each app's search-box
logic:

```
-- the tape finder: Grateful Dead, soundboards only, 1977
put axPresetSpec("etree", "GratefulDead", empty, 1977, 1977, "soundboard") into tSpec
put axQueryBuild(tSpec) into tQuery
-- collection:(GratefulDead) AND mediatype:(etree) AND creator:(Grateful Dead) AND year:[1977 TO 1977] AND source:(soundboard OR sbd OR "sbd")

-- the AudioBooks app: author search, solo readers, English
put axPresetSpec("librivox", "Author_Search", "Jane Austen", empty, empty, "solo,english") into tSpec
put axQueryBuild(tSpec) into tQuery
-- collection:(librivoxaudio) AND creator:(Jane Austen) AND subject:(solo) AND language:(English)

-- the film club: a collection, the user's text through the plain rule, public domain only
put axPresetSpec("movies", "prelinger", "moon: rocket (test)", empty, empty, "publicdomain") into tSpec
```

To build a menu: `axFamilyList()` for the families, `axPresetList(tFamily)`
for `id|title` lines (`axPresetInfo` for the group heading and the default
years), `axFilterList(tFamily)` for the checkboxes, `axSortList()` for the
sort menu. `axFamilyInfo(tFamily)` answers the fields, rows and sort each
app used, so a search in a family asks for what its app asked for:

```
put axFamilyInfo("librivox") into tInfo
put tInfo["fields"] into tOptions["fields"]
put tInfo["rows"] into tOptions["rows"]
put axSortClause("date") into tOptions["sort"]
```

## 4. Open an item and build its playlist

```
command openItem pIdentifier
   put axFetchItem(pIdentifier, "item") into tHandle   -- arrives as onArchive h, "item", tItem, "item"
end openItem

command showItem pItem
   local tKind, tPlaylist, tI
   put axPlaylistKindFor(sFamily, axFirst(pItem["metadata"]["mediatype"])) into tKind
   put axPlaylist(pItem, tKind) into tPlaylist
   if tPlaylist is empty then
      answer axLastError()        -- "no audio files in this item" is a normal outcome
      exit showItem
   end if
   set the text of field "tracks" to axPlaylistTable(tPlaylist)
   put tPlaylist into sPlaylist
end showItem
```

An etree show comes back as its set list (`Scarlet Begonias`, `Fire On The
Mountain`, ...), each entry a VBR MP3 with its download URL; a LibriVox book
as its chapters in track order, one per original file; a film as its
episodes, MP4 first, with every other encode in `variants`. Pass `"auto"`
as the kind to let the item's mediatype decide.

## 5. Play it, open it, copy it

```
-- the two URLs of the selected entry
put sPlaylist["entries"][tLine]["url"] into tUrl       -- /download/... (redirects to a datanode)
put sPlaylist["entries"][tLine]["direct"] into tDirect -- the datanode itself (axDirectUrl)

-- STREAM: hand the DIRECT url to a player object (created on demand). A
-- player that cannot open a stream throws nothing and plays nothing, so
-- ask it six seconds later: a duration of 0 means it did not open.
if there is not a player "adPlayer" then
   create player "adPlayer"
end if
set the filename of player "adPlayer" to tDirect
start player "adPlayer"
send "checkPlayer" to me in 6 seconds      -- the duration of player "adPlayer" > 0 ?

-- DOWNLOAD: straight to disk, with progress, then play the file
put specialFolderPath("documents") & "/ArchiveXT/" & tIdentifier into tFolder
create folder tFolder                       -- guard with `there is a folder` first
put axDownload(tUrl, tFolder & "/" & tName, "download") into tHandle
--   onArchive h, "progress", "received,total", "download"   (repeatedly)
--   onArchive h, "file", tPath, "download"  -> set the filename of player "adPlayer" to tPath

-- or the browser
launch URL axDetailsUrl(tIdentifier)      -- the item's page
launch URL tUrl                           -- the file itself

-- the clipboard
set the clipboardData["text"] to tUrl
```

`axThumbnailUrl(tIdentifier)` is the item's image for an image object;
`axEmbedUrl` the site's own player for a browser object. The demo does all
of these behind its Play / Download / Open page / Copy URL buttons: Play
streams the datanode URL and, when the six-second check finds the player
never opened it, downloads the file and plays it from disk; Download saves
to Documents/ArchiveXT/<identifier>/ with progress in the status line.

## 6. Paging

```
add 1 to sPage
put sPage into tOptions["page"]
put axSearch(sQuery, tOptions) into tHandle
```

The end of the results is a page shorter than `rows`, not
`start + count >= numFound`: the site over-reports its count. Disable Next
on a short page. For a walk over a whole collection, use `axScrapeUrl` and
`axFetchUrl` with the cursor each page returns (untested against the site;
see `07-open-questions.md`).

## 7. The generic family

```
put axPresetSpec("any", "texts", "pride and prejudice", empty, empty, empty) into tSpec
put axQueryBuild(tSpec) into tQuery
-- mediatype:(texts) AND (pride and prejudice)
```

The `any` family's presets are the mediatypes; an item opened from it gets
its playlist kind from its mediatype (`documents` for a text: PDF first,
then EPUB, DjVu, plain text; `images`; `files` for anything else).

## 8. Errors, and the two things to read

Nothing throws. A function answers empty (or false) and `axLastError()`
carries the reason; read the return first, then the error, because a later
successful call overwrites it. The async layer reports every failure as
`onArchive h, "error", tReason, tag`: the engine's own text for a transport
failure, `timeout` from the watchdog, the site's rejection message for a
malformed query, "could not be found" for a `{}` item, a body over the cap.

`axPending()` says how many requests are in flight; `axCancel tHandle`
forgets one (its reply is dropped when it arrives); `axShutdown` forgets
everything and is safe from `closeStack` twice over.

## 9. Test it

```
start using stack "archivext"
-- then open examples/archivext-tests.livecodescript as a stack and, from the message box:
put axSelfTest()
```

The report ends with `N passed, M failed, K skipped`; the one expected skip
is the Internet-library probe on an engine without it. The demo runs the
same harness behind its Run tests button, and the suite paste
(`tests/suite-selftest.livecodescript`) carries it as `ax1axSelfTest`.

## 10. A mirror or a test server

```
axSetBaseUrl "http://localhost:8080"     -- every builder prefixes it from now on
axSetBaseUrl empty                       -- back to https://archive.org
```

That is also the documented fallback for an engine whose https refuses
(`04-fetch-layer.md`), at the cost of transport integrity.
