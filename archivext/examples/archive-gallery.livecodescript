script "ArchiveGallery"

-- ==========================================================================
-- ArchiveXT gallery - archive.org as PICTURES, in one paste-and-run stack.
--
-- WHY THIS EXISTS BESIDE archivext-demo.livecodescript
--    The explorer demo is a form: three text columns, a results list and a
--    track table. It proves the library. It does not show what the library
--    is FOR, because everything archive.org holds arrives at a reader as a
--    picture first - a film's poster frame, a concert's cover, a book's
--    plate, a photograph. This stack is the same library driven the other
--    way round: a GRID of ten thumbnails, each one a real engine IMAGE
--    object fed from the item image service, and a viewer that puts the
--    engine's own PLAYER object on a dark stage for a film or a concert
--    and the engine's own IMAGE object there for a photograph.
--
--    So the two demos divide by question, not by feature. "What can I ask
--    archive.org?" is the explorer's. "What does it look like, and can I
--    watch it here?" is this one's.
--
-- THE TWO ENGINE OBJECTS THIS STACK IS ABOUT, and what each one costs
--    An IMAGE takes its content from `set the text of image X to <bytes>`.
--    It does not throw on bytes it cannot decode and it does not complain:
--    it stays empty, which reads exactly like a network failure. The only
--    reliable tell is to ASK THE CONTROL afterwards - a width under two
--    pixels means the data was refused - which is the idiom box2dxt's
--    b2kSheetSourceFromFile and the coinxt wallet's QR panel already use
--    and the reason every picture here goes through agImageData.
--
--    A PLAYER handed a URL it cannot open is the same silence one layer
--    out (archivext/CLAUDE.md gotcha 19, from the 2026-09-16 report "the
--    player is still not working" with no error anywhere). So Play reads
--    the synchronous verdict `set the filename` leaves in `the result`,
--    then checks six seconds later whether a duration ever appeared, and
--    falls back to downloading the file and playing it from disk. That is
--    the explorer's machinery, carried here deliberately rather than
--    rewritten: it is the only part of this tree that has a story.
--
-- WHAT IS NEW HERE, AS A CLAIM ABOUT THE LIBRARY
--    Nothing in archivext changed for this stack. The grid is axSearch
--    with rows fixed at the tile count; a thumbnail is axFetchUrl against
--    axThumbnailUrl and the body arrives through the ordinary "raw" kind;
--    a picture in the viewer is one playlist entry's datanode URL through
--    the same call. The one thing the gallery adds is a FIFTH family -
--    `mediatype:(image)` - because none of the three source apps had a
--    picture app and the library's family table is theirs. The playlist
--    engine already knew an "images" kind, so the scope is the whole
--    addition and it lives in agFamilyFor, not in the library.
--
-- LATE REPLIES ARE THE HAZARD A GRID HAS AND A LIST DOES NOT
--    Ten thumbnails are ten requests in flight at once, and a reader who
--    presses Next before they land would otherwise see the previous page's
--    pictures under the new page's captions - a wrong answer that looks
--    like a right one. Every thumbnail carries the search SERIAL in its
--    tag and a reply whose serial is not the current one is dropped. The
--    serial is bumped by the search that starts, not by the reply that
--    arrives, so a cancelled search can never resurrect itself.
--
-- HONESTY
--    Verified statically and by the member's headless fixtures. Nothing in
--    this file has run on an engine: not the grid, not the image objects,
--    not the player, not one live thumbnail. archivext/CLAUDE.md carries
--    what the library itself has been through.
-- ==========================================================================

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- archivext/src/archivext.livecodescript ----
-- archivext.livecodescript - the ArchiveXT library: archive.org from xTalk.
--
-- ArchiveXT is an Internet Archive (archive.org) client layer for OpenXTalk
-- / the xTalk family, in pure LiveCodeScript. It gives an app the four public
-- archive.org surfaces every archive.org web app is built from - the
-- advanced search API (advancedsearch.php), the item metadata API
-- (/metadata/<identifier>), the file download/streaming path
-- (/download/<identifier>/<file>) and the item image service
-- (/services/img/<identifier>) - plus everything three shipped web apps
-- learned to do ON TOP of them: a Lucene query grammar with a sanitizer for
-- user text, preset catalogues (the Live Music Archive's band collections,
-- LibriVox's audiobook categories, the Moving Image Archive's film
-- collections), and the rules that turn an item's raw file list into
-- something playable - a concert's track list, an audiobook's chapters, a
-- film's episodes with their quality variants.
--
-- THE THREE APPS THIS FOLDS TOGETHER, and what each contributed:
--   Grateful-Dead-Tape-Finder  the etree (Live Music Archive) grammar, the
--                              band preset table, SBD/AUD/matrix/top-rated
--                              quick filters, d1t01-style track titles
--   AudioBooks (LibriVox)      the query SANITIZER (the only user-input
--                              safety layer any of the three had), the
--                              category table, chapter grouping by original
--                              file, format ranking, natural ordering,
--                              duration parsing, the exact search-URL bytes
--   Archive-Film-Club          the video scope (mediatype OR collection
--                              identifiers), the 26-collection table, the
--                              sort menu, episode identity across encodes
--                              (normalizeBaseName), MP4-first quality
--                              selection, quality labels, sentinel filters
-- Where two apps disagreed (the tape finder's inverted MP3-dedup, the film
-- club ignoring file titles), the rule taken here is the one that reads as
-- the intent, and docs/03-items-files-and-playlists.md records each choice.
--
-- TWO LAYERS IN ONE FILE, and the split is the point:
--   ax* PURE COMPUTE   everything from axVersion to axPlaylistTable: URL and
--                      query builders, the preset tables, the owned JSON
--                      reader, the response parsers, the playlist engine.
--                      No I/O, no engine-only calls, no timers - so the
--                      whole layer runs HEADLESSLY on every build through
--                      the family interpreter (tools/check-script-vectors.py)
--                      against tools/archive_reference.py, an independent
--                      python implementation of the same rules.
--   ax* FETCH          the tail of the file, from axInit on: the asynchronous
--                      `load URL ... with message` layer that hands a parsed
--                      search result or item back through a callback, with
--                      request correlation, a body cap, a watchdog and a
--                      late-reply drop. Engine only.
-- Both halves use the SAME error convention (the riptide / nostrxt-core
-- shape): no handler here ever throws. Functions return empty (or false) on
-- refusal and record the reason for axLastError(); commands that yield a
-- handle return the integer or empty. Every engine call that can throw sits
-- inside a try. Read the return, then axLastError(), in that order.
--
-- STATUS: verified statically; needs an OXT pass + a live archive.org pass.
-- The pure layer is EXECUTED headlessly on every build against synthetic
-- fixtures (tests/fixtures/*.json - archive.org is unreachable from the
-- build sandbox, so the fixtures are SHAPED from the three apps' own mocked
-- responses and the documented API; they are not recordings). Nothing in
-- this file has run on a real OXT engine or against the live site yet, and
-- the fetch layer's TLS question is the suite's open one (root
-- docs/OXT-ENGINE-NOTES.md 6.8: `open secure socket` worked once against a
-- good certificate; libURL's https has no record here at all).
--
-- PORTABILITY DISCIPLINES (the coinxt set, carried whole - see that file's
-- header for the parser each one was paid for on):
--   1. No `^`, `div`, `mod` or bitwise operators anywhere: axIntDiv /
--      axIntMod are trunc-based helpers.
--   2. Case-significant comparisons never go through `is`, which folds case:
--      JSON object keys are looked up through an array index (exact), and
--      byte values are compared as numbers.
--   3. `the itemDelimiter` is assumed to be its default comma and every
--      other delimiter use is saved, set and restored around the narrowest
--      span that needs it.
--   4. Multi-valued fields cross this API as LINES: a doc's "creator" with
--      two values is two lines. axFirst() and axJoin() are the two spellings
--      an app needs (the AudioBooks asList/firstValue/joinValues trio).
--   5. Every script-level declaration sits at the top of this file, because
--      OXT resolves them by lexical position (root CLAUDE.md, the
--      106-declaration fold).
--
-- Conventions: public API axPascalCase; private helpers are `private` and
-- also ax-prefixed (the cross-library gate holds every handler name in the
-- suite unique, private or not); locals t..., params p..., script-locals
-- sAx..., constants kAx...; ASCII only; no em-dashes.

-- ==========================================================================
-- Constants (literals only - an xTalk constant cannot hold an expression).
-- ==========================================================================

constant kAxVersion = "ArchiveXT 0.1.0"
constant kAxDefaultBase = "https://archive.org"
constant kAxHexDigits = "0123456789ABCDEF"
-- The characters encodeURIComponent leaves alone besides letters and digits
-- (RFC 3986 unreserved plus the five it historically spares); the download
-- and metadata paths are built with these so they match the apps byte for
-- byte.
constant kAxKeepUri = "-_.!~*'()"
-- The characters URLSearchParams leaves alone besides letters and digits
-- (application/x-www-form-urlencoded); the search query string is built
-- with these, space becoming "+".
constant kAxKeepForm = "*-._"
constant kAxIdentifierExtra = "_.-"
constant kAxIdentifierMax = 100
constant kAxJsonMaxDepth = 64
constant kAxNaturalPad = 12
constant kAxMaxBodyDefault = 16777216
constant kAxTimeoutDefault = 60
constant kAxCallbackDefault = "onArchive"
-- The Lucene words the sanitizer treats as operators. Upper-case only, on
-- purpose: "Pride and Prejudice" is a phrase, "Pride AND Prejudice" a query.
constant kAxOps = "AND,OR,NOT"
-- The video scope mediatypes (the film club's "videoQuery" half).
constant kAxVideoMediatypes = "movies OR video OR television"
-- The film club's public-domain licence clause is built by
-- axPublicDomainClause(): it carries double quotes, which an xTalk literal
-- cannot hold (there are no string escapes in this dialect).

-- ==========================================================================
-- Script-level state. The pure layer keeps ONLY the error slot, the base
-- URL and the JSON document table; the fetch layer owns the rest.
-- ==========================================================================

local sAxError              -- the reason the most recent failing call recorded
local sAxBase               -- the base URL (empty means kAxDefaultBase)
local sAxCaps               -- the cached capability array (empty until probed)

-- The JSON reader's document table: sAxDocs[h] is one parsed document.
--   ["n"]        node count
--   ["t"][i]     node type: o / a / s / n / b / z
--   ["v"][i]     scalar value (strings decoded, numbers as text, booleans as
--                "true"/"false", null empty)
--   ["c"][i]     child count of a container
--   ["x"][i][j]  j-th child node index (1-based)
--   ["k"][i][j]  j-th key of an object. A key lookup SCANS this list with
--                a byte-exact compare (axJsonFindKey): the first version
--                indexed children by key in an array, and the engine folded
--                the case - tA["A"] and tA["a"] are one element on OXT
--                (OBSERVED 2026-09-15, docs/OXT-ENGINE-NOTES.md 2.7), so
--                "Title" answered for "title". An array is never an exact
--                string index in this file.
--   ["b1"][i], ["b2"][i]  the node's first and last byte in the source
local sAxDocs
local sAxDocNext            -- the next document handle to hand out
-- The parser's cursor state, live only inside axJsonParse.
local sAxJsonBytes, sAxJsonPos, sAxJsonLen, sAxJsonDepth, sAxJsonErr
local sAxJsonN, sAxJsonT, sAxJsonV, sAxJsonC, sAxJsonX, sAxJsonK
local sAxJsonB1, sAxJsonB2

-- The fetch layer.
local sAxOwner              -- long id the callbacks dispatch to (empty: the topStack)
local sAxCallback           -- the handler name dispatched (default onArchive)
local sAxTimeout            -- seconds before a request is reported as timed out
local sAxMaxBody            -- the largest body the layer will parse
local sAxReqNext            -- the next request handle
local sAxReqs               -- sAxReqs[h] = the request record (kind, url, tag, ...)
local sAxReqByUrl           -- sAxReqByUrl[url] = h, the correlation index
local sAxStatusHooked       -- true once libURLSetStatusCallback points at axUrlStatus

-- ==========================================================================
-- Version, errors, capabilities, base URL.
-- ==========================================================================

function axVersion
   return kAxVersion
end axVersion

function axLastError
   return sAxError
end axLastError

private command axSetError pText
   put pText into sAxError
end axSetError

function axBaseUrl
   -- The base every URL builder prepends. Configurable (the tape finder made
   -- it a server setting) so a mirror or a local proxy can stand in; the
   -- default is the public site.
   if sAxBase is empty then
      return kAxDefaultBase
   end if
   return sAxBase
end axBaseUrl

function axSetBaseUrl pUrl
   -- Accepts an http(s) URL with no trailing slash and no path; empty
   -- restores the default. Returns true on success.
   local tUrl
   put pUrl into tUrl
   if tUrl is empty then
      put empty into sAxBase
      return true
   end if
   if not axIsHttpUrl(tUrl) then
      axSetError "axSetBaseUrl: the base must start with http:// or https://"
      return false
   end if
   if char -1 of tUrl is "/" then
      put char 1 to -2 of tUrl into tUrl
   end if
   put tUrl into sAxBase
   return true
end axSetBaseUrl

function axProbeCapabilities
   -- What this engine can do for the fetch layer, probed once and cached:
   --   hasUrlLib   the Internet library answers (libURLVersion in a try)
   --   version     this library's version string
   -- The probe is a real call, not a version sniff; on a build without the
   -- Internet library the fetch handlers still refuse cleanly, this just
   -- lets an app say so up front. Nothing here is a claim about https: the
   -- engine's TLS behaviour is unmeasured (docs/04-fetch-layer.md).
   local tCaps, tError, tVersionText
   if sAxCaps is an array then
      return sAxCaps
   end if
   put kAxVersion into tCaps["version"]
   put false into tCaps["hasUrlLib"]
   put empty into tCaps["urlLibVersion"]
   try
      put libURLVersion() into tVersionText
      if tVersionText is not empty then
         put true into tCaps["hasUrlLib"]
         put tVersionText into tCaps["urlLibVersion"]
      end if
   catch tError
      put false into tCaps["hasUrlLib"]
   end try
   put tCaps into sAxCaps
   return tCaps
end axProbeCapabilities

-- ==========================================================================
-- Small arithmetic and byte helpers (the coinxt disciplines).
-- ==========================================================================

private function axIntDiv pA, pB
   -- Integer division, floor, for the non-negative operands every caller
   -- here uses. trunc() rather than `div`.
   return trunc(pA / pB)
end axIntDiv

private function axIntMod pA, pB
   return pA - pB * axIntDiv(pA, pB)
end axIntMod

private function axIsDigitByte pByte
   if pByte < 48 then
      return false
   end if
   if pByte > 57 then
      return false
   end if
   return true
end axIsDigitByte

private function axIsAlphaByte pByte
   if pByte >= 65 then
      if pByte <= 90 then
         return true
      end if
   end if
   if pByte >= 97 then
      if pByte <= 122 then
         return true
      end if
   end if
   return false
end axIsAlphaByte

private function axIsDigits pText
   -- True for one or more ASCII digits and nothing else. The strict test
   -- this file uses instead of `is an integer`, which folds "1e3" and " 7 ".
   local tI, tCount
   put the number of chars of pText into tCount
   if tCount is 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      if not axIsDigitByte(byteToNum(char tI of pText)) then
         return false
      end if
   end repeat
   return true
end axIsDigits

function axLowerAscii pText
   -- ASCII lowercase; every other byte passes through untouched. Every
   -- case-insensitive rule in this file (format names, extensions, stems)
   -- goes through here rather than through the engine's toLower, so the
   -- headless model and the engine agree byte for byte.
   local tBytes, tOut, tI, tCount, tByte
   put textEncode(pText, "UTF-8") into tBytes
   put the number of bytes of tBytes into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of tBytes) into tByte
      if tByte >= 65 then
         if tByte <= 90 then
            add 32 to tByte
         end if
      end if
      put numToByte(tByte) after tOut
   end repeat
   return textDecode(tOut, "UTF-8")
end axLowerAscii

function axUpperFirst pText
   -- The first byte upper-cased when it is an ASCII letter (the AudioBooks
   -- subject-tag capitalisation); the rest untouched.
   local tByte
   if pText is empty then
      return empty
   end if
   put byteToNum(char 1 of pText) into tByte
   if tByte >= 97 then
      if tByte <= 122 then
         return numToChar(tByte - 32) & char 2 to -1 of pText
      end if
   end if
   return pText
end axUpperFirst

function axTrim pText
   -- ASCII whitespace (space, tab, cr, lf) off both ends.
   local tText, tByte, tDone
   put pText into tText
   put false into tDone
   repeat while not tDone
      if tText is empty then
         put true into tDone
      else
         put byteToNum(char 1 of tText) into tByte
         if axIsSpaceByte(tByte) then
            put char 2 to -1 of tText into tText
         else
            put true into tDone
         end if
      end if
   end repeat
   put false into tDone
   repeat while not tDone
      if tText is empty then
         put true into tDone
      else
         put byteToNum(char -1 of tText) into tByte
         if axIsSpaceByte(tByte) then
            put char 1 to -2 of tText into tText
         else
            put true into tDone
         end if
      end if
   end repeat
   return tText
end axTrim

private function axIsSpaceByte pByte
   if pByte is 32 then
      return true
   end if
   if pByte is 9 then
      return true
   end if
   if pByte is 10 then
      return true
   end if
   if pByte is 13 then
      return true
   end if
   return false
end axIsSpaceByte

function axCollapseSpaces pText
   -- Runs of ASCII whitespace become one space; the ends are trimmed. The
   -- `\s+` -> " " step every title cleaner in the three apps ends with.
   local tI, tCount, tByte, tOut, tPending
   put empty into tOut
   put false into tPending
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if axIsSpaceByte(tByte) then
         put true into tPending
      else
         if tPending then
            if tOut is not empty then
               put space after tOut
            end if
            put false into tPending
         end if
         put char tI of pText after tOut
      end if
   end repeat
   return tOut
end axCollapseSpaces

private function axCharIn pChar, pSet
   -- Byte-exact membership of a single character in a set of characters.
   -- `contains` folds case, and the sets this file keeps ("-_.!~*'()") are
   -- punctuation, but the discipline is the same one coinxt's alphabet
   -- lookup pays for: compare byte values, never text.
   local tI, tCount, tByte
   put byteToNum(pChar) into tByte
   put the number of chars of pSet into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of pSet) is tByte then
         return true
      end if
   end repeat
   return false
end axCharIn

private function axPercentByte pByte
   -- "%XX" for one byte, upper-case hex (what both encodeURIComponent and
   -- URLSearchParams emit).
   return "%" & char (axIntDiv(pByte, 16) + 1) of kAxHexDigits \
         & char (axIntMod(pByte, 16) + 1) of kAxHexDigits
end axPercentByte

function axUrlEncode pText
   -- encodeURIComponent, byte for byte: letters, digits and "-_.!~*'()"
   -- pass; every other UTF-8 byte becomes %XX. Used for path segments (the
   -- download path, the metadata path) and for anything an app wants to
   -- put in a URL by hand.
   local tBytes, tI, tCount, tByte, tOut, tChar
   put textEncode(pText, "UTF-8") into tBytes
   put the number of bytes of tBytes into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of tBytes) into tByte
      put byte tI of tBytes into tChar
      if axIsAlphaByte(tByte) then
         put tChar after tOut
      else if axIsDigitByte(tByte) then
         put tChar after tOut
      else if axCharIn(tChar, kAxKeepUri) then
         put tChar after tOut
      else
         put axPercentByte(tByte) after tOut
      end if
   end repeat
   return tOut
end axUrlEncode

function axUrlEncodePath pPath
   -- A file path with its "/" separators kept and every SEGMENT encoded -
   -- the AudioBooks downloadUrl rule, because archive.org items keep files
   -- in subdirectories and the separator must survive while a "#" or a
   -- space inside a name must not.
   local tOut, tSeg, tSavedDelim, tCount, tI
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "/"
   put the number of items of pPath into tCount
   -- the engine eats ONE trailing delimiter when counting items (engine
   -- notes 2.2); a path never ends in "/" here, but count what is there
   put empty into tOut
   repeat with tI = 1 to tCount
      put item tI of pPath into tSeg
      if tI > 1 then
         put "/" after tOut
      end if
      put axUrlEncode(tSeg) after tOut
   end repeat
   set the itemDelimiter to tSavedDelim
   return tOut
end axUrlEncodePath

function axQueryEncode pText
   -- application/x-www-form-urlencoded (URLSearchParams): letters, digits
   -- and "*-._" pass, space becomes "+", everything else %XX. The search
   -- query string is built with this so the URL matches the AudioBooks
   -- app's exact bytes, which its own tests pin.
   local tBytes, tI, tCount, tByte, tOut, tChar
   put textEncode(pText, "UTF-8") into tBytes
   put the number of bytes of tBytes into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of tBytes) into tByte
      put byte tI of tBytes into tChar
      if tByte is 32 then
         put "+" after tOut
      else if axIsAlphaByte(tByte) then
         put tChar after tOut
      else if axIsDigitByte(tByte) then
         put tChar after tOut
      else if axCharIn(tChar, kAxKeepForm) then
         put tChar after tOut
      else
         put axPercentByte(tByte) after tOut
      end if
   end repeat
   return tOut
end axQueryEncode

function axIsHttpUrl pText
   -- Byte-exact "http://" or "https://" prefix, at least one character of
   -- host after it.
   local tLower
   put axLowerAscii(pText) into tLower
   if tLower begins with "http://" then
      return (the number of chars of pText > 7)
   end if
   if tLower begins with "https://" then
      return (the number of chars of pText > 8)
   end if
   return false
end axIsHttpUrl

-- ==========================================================================
-- Identifiers, years, durations, sizes, natural order, multi-values.
-- ==========================================================================

function axIdentifierIsValid pText
   -- archive.org's own identifier shape: a letter or digit first, then up to
   -- 99 of letters, digits, "_", "." and "-" (the AudioBooks guard; the
   -- tape finder and the film club allow a leading "." or "-", which the
   -- site itself does not mint). Every URL builder refuses anything else,
   -- so a path-traversal string can never reach a URL.
   local tI, tCount, tByte, tChar
   put the number of chars of pText into tCount
   if tCount is 0 then
      return false
   end if
   if tCount > kAxIdentifierMax then
      return false
   end if
   repeat with tI = 1 to tCount
      put char tI of pText into tChar
      put byteToNum(tChar) into tByte
      if axIsAlphaByte(tByte) then
         next repeat
      end if
      if axIsDigitByte(tByte) then
         next repeat
      end if
      if tI is 1 then
         return false
      end if
      if not axCharIn(tChar, kAxIdentifierExtra) then
         return false
      end if
   end repeat
   return true
end axIdentifierIsValid

function axYearOf pText
   -- The first run of exactly four digits anywhere in the text, or empty:
   -- the tape finder's `/(\d{4})/` over a date such as "1977-05-08T00:00:00Z"
   -- (a "1977-05-08" and a "05/08/1977" both answer 1977; "77-05-08" answers
   -- nothing). A longer digit run is not a year.
   local tI, tCount, tByte, tRun, tStart
   put the number of chars of pText into tCount
   put 0 into tRun
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if axIsDigitByte(tByte) then
         add 1 to tRun
      else
         if tRun is 4 then
            return char (tI - 4) to (tI - 1) of pText
         end if
         put 0 into tRun
      end if
   end repeat
   if tRun is 4 then
      return char (tCount - 3) to tCount of pText
   end if
   return empty
end axYearOf

function axNormalizeYear pText
   -- A trimmed four-digit year in 1000..9999, or empty (the AudioBooks
   -- normalizeYear). Only a value this accepts ever reaches a year clause.
   local tText
   put axTrim(pText) into tText
   if the number of chars of tText is not 4 then
      return empty
   end if
   if not axIsDigits(tText) then
      return empty
   end if
   if tText < 1000 then
      return empty
   end if
   return tText
end axNormalizeYear

function axDurationSeconds pLength
   -- archive.org's per-file "length" in seconds, or empty when it cannot be
   -- read. Two shapes arrive: plain seconds, possibly fractional
   -- ("600.12"), and colon forms ("12:34", "1:02:03", even "1:02:03.5"),
   -- folded left as total * 60 + part - the AudioBooks parseLength. Any
   -- non-numeric component voids the whole value ("n/a" is empty, not 0).
   local tText, tSavedDelim, tCount, tI, tPart, tTotal
   put axTrim(pLength) into tText
   if tText is empty then
      return empty
   end if
   if tText contains ":" then
      put the itemDelimiter into tSavedDelim
      set the itemDelimiter to ":"
      put the number of items of tText into tCount
      put 0 into tTotal
      repeat with tI = 1 to tCount
         put axTrim(item tI of tText) into tPart
         if not axIsDecimal(tPart) then
            set the itemDelimiter to tSavedDelim
            return empty
         end if
         put tTotal * 60 + tPart into tTotal
      end repeat
      set the itemDelimiter to tSavedDelim
      return tTotal
   end if
   if not axIsDecimal(tText) then
      return empty
   end if
   return tText + 0
end axDurationSeconds

private function axIsDecimal pText
   -- Digits with at most one "." and at least one digit: the number shapes
   -- a length field can carry. No sign, no exponent (a "1e3" length is not
   -- a length).
   local tI, tCount, tByte, tDots, tDigits
   put the number of chars of pText into tCount
   if tCount is 0 then
      return false
   end if
   put 0 into tDots
   put 0 into tDigits
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if axIsDigitByte(tByte) then
         add 1 to tDigits
      else if tByte is 46 then
         add 1 to tDots
      else
         return false
      end if
   end repeat
   if tDots > 1 then
      return false
   end if
   return tDigits > 0
end axIsDecimal

function axFormatTime pSeconds
   -- "m:ss" under an hour, "h:mm:ss" from an hour up, "0:00" for anything
   -- that is not a non-negative number (the AudioBooks formatTime, whose
   -- tests pin 3599.9 -> "59:59" and 45296 -> "12:34:56"). Whole seconds
   -- only: the fraction is floored, never rounded up.
   local tWhole, tHours, tMins, tSecs, tRest
   if pSeconds is not a number then
      return "0:00"
   end if
   if pSeconds < 0 then
      return "0:00"
   end if
   put trunc(pSeconds) into tWhole
   put axIntDiv(tWhole, 3600) into tHours
   put axIntMod(tWhole, 3600) into tRest
   put axIntDiv(tRest, 60) into tMins
   put axIntMod(tRest, 60) into tSecs
   if tHours > 0 then
      return tHours & ":" & axPad2(tMins) & ":" & axPad2(tSecs)
   end if
   return tMins & ":" & axPad2(tSecs)
end axFormatTime

private function axPad2 pNumber
   if pNumber < 10 then
      return "0" & pNumber
   end if
   return pNumber
end axPad2

function axFormatBytes pBytes
   -- "76.29 MB" from 80000000, "1 KB" from 1024, empty for zero, negative or
   -- non-numeric (the film club's formatFileSize: two decimals at most,
   -- trailing zeros dropped, units B..TB).
   local tValue, tUnit, tUnits, tScaled, tRounded, tText
   if pBytes is not a number then
      return empty
   end if
   if pBytes <= 0 then
      return empty
   end if
   put "B,KB,MB,GB,TB" into tUnits
   put pBytes into tScaled
   put 1 into tUnit
   repeat while tScaled >= 1024
      if tUnit is 5 then
         exit repeat
      end if
      put tScaled / 1024 into tScaled
      add 1 to tUnit
   end repeat
   -- round half up to two decimals, then strip the trailing zeros the way
   -- javascript's number-to-string does
   put trunc(tScaled * 100 + 0.5) into tRounded
   put axIntDiv(tRounded, 100) into tValue
   put axIntMod(tRounded, 100) into tText
   if tText is 0 then
      return tValue & " " & item tUnit of tUnits
   end if
   if axIntMod(tText, 10) is 0 then
      return tValue & "." & axIntDiv(tText, 10) & " " & item tUnit of tUnits
   end if
   return tValue & "." & axPad2(tText) & " " & item tUnit of tUnits
end axFormatBytes

function axNaturalKey pText
   -- A sort key that orders "part2" before "part10": ASCII-lowercased, with
   -- every digit run left-padded with zeros to kAxNaturalPad. Two names
   -- that differ only in case or in digit padding get the same key, which
   -- is what a numeric-aware, case-insensitive compare means.
   local tLower, tI, tCount, tByte, tOut, tRun
   put axLowerAscii(pText) into tLower
   put the number of chars of tLower into tCount
   put empty into tOut
   put empty into tRun
   repeat with tI = 1 to tCount
      put byteToNum(char tI of tLower) into tByte
      if axIsDigitByte(tByte) then
         put char tI of tLower after tRun
      else
         if tRun is not empty then
            put axPadRun(tRun) after tOut
            put empty into tRun
         end if
         put char tI of tLower after tOut
      end if
   end repeat
   if tRun is not empty then
      put axPadRun(tRun) after tOut
   end if
   return tOut
end axNaturalKey

private function axPadRun pDigits
   -- Left-pad a digit run to kAxNaturalPad; a run longer than that is kept
   -- whole (it still sorts after every shorter run of the same prefix).
   local tOut
   put pDigits into tOut
   repeat while the number of chars of tOut < kAxNaturalPad
      put "0" before tOut
   end repeat
   return tOut
end axPadRun

function axNaturalSort pLines
   -- The lines of pLines in natural order (numeric-aware, case-insensitive),
   -- ties kept in input order. Built as "key TAB index" lines, sorted with
   -- the engine's text sort, then read back through the index - so a
   -- key collision can never reorder equal names.
   local tCount, tI, tKeyed, tLine, tIndex, tOut
   put the number of lines of pLines into tCount
   if tCount < 2 then
      return pLines
   end if
   put empty into tKeyed
   repeat with tI = 1 to tCount
      put axNaturalKey(line tI of pLines) & tab & axPadRun(tI) & return after tKeyed
   end repeat
   put axChompLine(tKeyed) into tKeyed
   sort lines of tKeyed
   put empty into tOut
   repeat with tI = 1 to tCount
      put line tI of tKeyed into tLine
      put char (offset(tab, tLine) + 1) to -1 of tLine into tIndex
      put line (tIndex + 0) of pLines & return after tOut
   end repeat
   return axChompLine(tOut)
end axNaturalSort

function axFirst pValue
   -- The first of a multi-valued field (lines), or the scalar itself.
   return line 1 of pValue
end axFirst

function axJoin pValue, pSeparator
   -- A multi-valued field joined for display ("A, B"); the scalar itself
   -- when there is one value; empty when empty.
   local tCount, tI, tOut, tSep
   put pSeparator into tSep
   if tSep is empty then
      put ", " into tSep
   end if
   put the number of lines of pValue into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      if tI > 1 then
         put tSep after tOut
      end if
      put line tI of pValue after tOut
   end repeat
   return tOut
end axJoin

function axTrackNumber pText
   -- The first digit run of a file's "track" field as a number ("01" -> 1,
   -- "3/12" -> 3, 7 -> 7), or empty when there is none ("n/a").
   local tI, tCount, tByte, tRun
   put the number of chars of pText into tCount
   put empty into tRun
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if axIsDigitByte(tByte) then
         put char tI of pText after tRun
      else
         if tRun is not empty then
            return tRun + 0
         end if
      end if
   end repeat
   if tRun is empty then
      return empty
   end if
   return tRun + 0
end axTrackNumber

-- ==========================================================================
-- The query grammar. archive.org's advanced search speaks Lucene, and every
-- one of the three apps built its `q` by string concatenation: a scope
-- (`mediatype:(etree)`, `collection:(librivoxaudio)`, the film club's
-- video OR-list), an optional preset clause, the user's text, a year range,
-- and the quick-filter clauses, joined with " AND ". This section is that
-- grammar as functions, plus the one thing only the AudioBooks app had: a
-- sanitizer that keeps user text from becoming a Lucene parse error (the
-- site answers those with HTTP 200 and a top-level "error", so an unguarded
-- app shows the user a stack trace from Solr).
-- ==========================================================================

function axQuerySanitize pText, pAllowFieldSyntax
   -- User text made safe to splice into a Lucene query. Two modes:
   --   plain (pAllowFieldSyntax not true): no field syntax ("Dracula:
   --     Chapter 1" would query a field named Dracula), no ranges, fuzzy or
   --     boost operators, and the prefix operators + - ! only when attached
   --     to a term ("Title - Subtitle" must not exclude a term);
   --   field syntax (true): colons, ranges, ~ and ^ survive; only UNBALANCED
   --     brackets and braces are blanked.
   -- Then, in both modes: an odd number of quotes blanks every quote,
   -- unbalanced parentheses blank every parenthesis, and a fixed-point pass
   -- removes empty groups and dangling boolean operators (upper-case only:
   -- "Pride and Prejudice" is a phrase). The rule is the AudioBooks
   -- sanitizeUserQuery, restated over TOKENS - whitespace-separated words
   -- with "(" and ")" split off as their own tokens - which is what makes
   -- it expressible without regular expressions; the published vectors from
   -- that app's tests pin every case in tools/archive-kat.py.
   local tQ, tTokens, tCount, tI, tTok, tOut, tPrev
   put axTrim(pText) into tQ
   if tQ is empty then
      return empty
   end if
   put axBlankChars(tQ, "\/") into tQ
   if pAllowFieldSyntax is true then
      if not axIsBalanced(tQ, "[", "]") then
         put axBlankChars(tQ, "[]") into tQ
      end if
      if not axIsBalanced(tQ, "{", "}") then
         put axBlankChars(tQ, "{}") into tQ
      end if
   else
      put axBlankChars(tQ, "{}[]^~:") into tQ
      replace "&&" with space in tQ
      replace "||" with space in tQ
      put axDropBareOperators(tQ) into tQ
   end if
   if axIntMod(axCountChar(tQ, quote), 2) is 1 then
      put axBlankChars(tQ, quote) into tQ
   end if
   if not axIsBalanced(tQ, "(", ")") then
      put axBlankChars(tQ, "()") into tQ
   end if
   put axQueryTokens(tQ) into tTokens
   put axQueryTidy(tTokens) into tTokens
   put the number of lines of tTokens into tCount
   if tCount is 0 then
      return empty
   end if
   if tCount is 1 then
      if axIsOperator(line 1 of tTokens) then
         return empty
      end if
   end if
   -- join: no space after an open token, none before a close token
   put empty into tOut
   put empty into tPrev
   repeat with tI = 1 to tCount
      put line tI of tTokens into tTok
      if tI > 1 then
         if not axIsOpenToken(tPrev) then
            if not axIsCloseToken(tTok) then
               put space after tOut
            end if
         end if
      end if
      put tTok after tOut
      put tTok into tPrev
   end repeat
   return tOut
end axQuerySanitize

private function axBlankChars pText, pSet
   -- Every character of pSet in pText becomes a space (byte-exact).
   local tI, tCount, tOut, tChar
   put the number of chars of pText into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put char tI of pText into tChar
      if axCharIn(tChar, pSet) then
         put space after tOut
      else
         put tChar after tOut
      end if
   end repeat
   return tOut
end axBlankChars

private function axCountChar pText, pChar
   local tI, tCount, tN, tByte
   put byteToNum(pChar) into tByte
   put the number of chars of pText into tCount
   put 0 into tN
   repeat with tI = 1 to tCount
      if byteToNum(char tI of pText) is tByte then
         add 1 to tN
      end if
   end repeat
   return tN
end axCountChar

private function axIsBalanced pText, pOpen, pClose
   -- Every pClose has a pOpen before it and the depth ends at zero.
   local tI, tCount, tDepth, tByte, tOpenByte, tCloseByte
   put byteToNum(pOpen) into tOpenByte
   put byteToNum(pClose) into tCloseByte
   put the number of chars of pText into tCount
   put 0 into tDepth
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if tByte is tOpenByte then
         add 1 to tDepth
      else if tByte is tCloseByte then
         subtract 1 from tDepth
         if tDepth < 0 then
            return false
         end if
      end if
   end repeat
   return tDepth is 0
end axIsBalanced

private function axDropBareOperators pText
   -- A whitespace-delimited word made only of + - ! is dropped; attached
   -- ones ("-austen") stay. The whitespace tokens are rejoined with single
   -- spaces, which the final collapse would have done anyway.
   local tWords, tCount, tI, tWord, tOut
   put axSplitSpaces(pText) into tWords
   put the number of lines of tWords into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put line tI of tWords into tWord
      if axOnlyPrefixOps(tWord) then
         next repeat
      end if
      if tOut is not empty then
         put space after tOut
      end if
      put tWord after tOut
   end repeat
   return tOut
end axDropBareOperators

private function axOnlyPrefixOps pWord
   local tI, tCount
   put the number of chars of pWord into tCount
   if tCount is 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      if not axCharIn(char tI of pWord, "+-!") then
         return false
      end if
   end repeat
   return true
end axOnlyPrefixOps

private function axSplitSpaces pText
   -- Whitespace-separated words, one per line, empties dropped.
   local tI, tCount, tByte, tWord, tOut
   put the number of chars of pText into tCount
   put empty into tWord
   put empty into tOut
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if axIsSpaceByte(tByte) then
         if tWord is not empty then
            put tWord & return after tOut
            put empty into tWord
         end if
      else
         put char tI of pText after tWord
      end if
   end repeat
   if tWord is not empty then
      put tWord & return after tOut
   end if
   return axChompLine(tOut)
end axSplitSpaces

private function axQueryTokens pText
   -- The sanitizer's token list, one per line: words, OPEN tokens (a word
   -- ending in "(" - a prefix operator stays attached, so "-(" is one
   -- token) and CLOSE tokens (a word starting with ")" - a boost stays
   -- attached, so ")^2" is one token).
   local tWords, tCount, tI, tWord, tOut, tPiece, tJ, tLen, tChar, tByte
   put axSplitSpaces(pText) into tWords
   put the number of lines of tWords into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put line tI of tWords into tWord
      put empty into tPiece
      put the number of chars of tWord into tLen
      repeat with tJ = 1 to tLen
         put char tJ of tWord into tChar
         put byteToNum(tChar) into tByte
         if tByte is 40 then
            put tChar after tPiece
            put tPiece & return after tOut
            put empty into tPiece
         else if tByte is 41 then
            if tPiece is not empty then
               if not axIsCloseToken(tPiece) then
                  put tPiece & return after tOut
                  put empty into tPiece
               end if
            end if
            put tChar after tPiece
         else
            put tChar after tPiece
         end if
      end repeat
      if tPiece is not empty then
         put tPiece & return after tOut
      end if
   end repeat
   return axChompLine(tOut)
end axQueryTokens

private function axIsOpenToken pTok
   if pTok is empty then
      return false
   end if
   return byteToNum(char -1 of pTok) is 40
end axIsOpenToken

private function axIsCloseToken pTok
   if pTok is empty then
      return false
   end if
   return byteToNum(char 1 of pTok) is 41
end axIsCloseToken

private function axIsOperator pTok
   -- Byte-exact: `is` would accept "and", which is a word in a phrase.
   local tI, tCount
   put the number of items of kAxOps into tCount
   repeat with tI = 1 to tCount
      if axStrEq(pTok, item tI of kAxOps) then
         return true
      end if
   end repeat
   return false
end axIsOperator

private function axIsAndOr pTok
   if axStrEq(pTok, "AND") then
      return true
   end if
   return axStrEq(pTok, "OR")
end axIsAndOr

function axStrEq pA, pB
   -- Byte-exact string equality. `is` folds case in this dialect, and
   -- Lucene's operators, JSON's literals and archive.org's format names all
   -- care about case somewhere, so every comparison that must not fold
   -- goes through here.
   local tA, tB, tCount, tI
   put textEncode(pA, "UTF-8") into tA
   put textEncode(pB, "UTF-8") into tB
   put the number of bytes of tA into tCount
   if the number of bytes of tB is not tCount then
      return false
   end if
   repeat with tI = 1 to tCount
      if byteToNum(byte tI of tA) is not byteToNum(byte tI of tB) then
         return false
      end if
   end repeat
   return true
end axStrEq

private function axQueryTidy pTokens
   -- The fixed-point pass over the token lines: empty groups, runs of
   -- operators, a leading AND/OR, a trailing operator, an operator right
   -- after an open token or right before a close token. Loops until a pass
   -- changes nothing.
   local tTokens, tPrev, tOut, tCount, tI, tTok, tNext, tLast
   put pTokens into tTokens
   repeat forever
      put tTokens into tPrev
      -- a. empty groups
      put empty into tOut
      put the number of lines of tTokens into tCount
      put 1 into tI
      repeat while tI <= tCount
         put line tI of tTokens into tTok
         if tI < tCount then
            if axIsOpenToken(tTok) then
               if axIsCloseToken(line (tI + 1) of tTokens) then
                  add 2 to tI
                  next repeat
               end if
            end if
         end if
         put tTok & return after tOut
         add 1 to tI
      end repeat
      put axChompLine(tOut) into tTokens
      -- b. runs of operators keep the last
      put empty into tOut
      put the number of lines of tTokens into tCount
      repeat with tI = 1 to tCount
         put line tI of tTokens into tTok
         if axIsOperator(tTok) then
            if tI < tCount then
               if axIsOperator(line (tI + 1) of tTokens) then
                  next repeat
               end if
            end if
         end if
         put tTok & return after tOut
      end repeat
      put axChompLine(tOut) into tTokens
      -- c. a leading AND/OR, a trailing operator
      put the number of lines of tTokens into tCount
      if tCount > 1 then
         if axIsAndOr(line 1 of tTokens) then
            put line 2 to -1 of tTokens into tTokens
            put tCount - 1 into tCount
         end if
      end if
      if tCount > 1 then
         if axIsOperator(line -1 of tTokens) then
            put line 1 to -2 of tTokens into tTokens
            put tCount - 1 into tCount
         end if
      end if
      -- d. AND/OR right after an open token; any operator right before a
      --    close token
      put empty into tOut
      put the number of lines of tTokens into tCount
      repeat with tI = 1 to tCount
         put line tI of tTokens into tTok
         if axIsOperator(tTok) then
            if tI > 1 then
               if axIsOpenToken(line (tI - 1) of tTokens) then
                  if axIsAndOr(tTok) then
                     next repeat
                  end if
               end if
            end if
            if tI < tCount then
               if axIsCloseToken(line (tI + 1) of tTokens) then
                  next repeat
               end if
            end if
         end if
         put tTok & return after tOut
      end repeat
      put axChompLine(tOut) into tTokens
      if axStrEq(tTokens, tPrev) then
         exit repeat
      end if
   end repeat
   return tTokens
end axQueryTidy

private function axChompLine pText
   if pText is empty then
      return empty
   end if
   if char -1 of pText is return then
      return char 1 to -2 of pText
   end if
   return pText
end axChompLine

function axQueryClause pField, pValue
   -- `field:(value)`; empty when either side is empty. The value is used
   -- as given (sanitize user text first).
   if pField is empty then
      return empty
   end if
   if axTrim(pValue) is empty then
      return empty
   end if
   return pField & ":(" & axTrim(pValue) & ")"
end axQueryClause

function axQueryPhrase pField, pText
   -- `field:("phrase")`, with any quotes inside the phrase removed so the
   -- phrase always closes. Empty when either side is empty.
   local tText
   put axCollapseSpaces(axBlankChars(pText, quote)) into tText
   if pField is empty then
      return empty
   end if
   if tText is empty then
      return empty
   end if
   return pField & ":(" & quote & tText & quote & ")"
end axQueryPhrase

function axQueryRange pField, pFrom, pTo
   -- `field:[from TO to]` with "*" for an open end; empty when both ends
   -- are empty. Numeric ends that arrive reversed are swapped.
   local tFrom, tTo, tSwap
   put axTrim(pFrom) into tFrom
   put axTrim(pTo) into tTo
   if pField is empty then
      return empty
   end if
   if tFrom is empty then
      if tTo is empty then
         return empty
      end if
   end if
   if tFrom is a number then
      if tTo is a number then
         if tFrom > tTo then
            put tFrom into tSwap
            put tTo into tFrom
            put tSwap into tTo
         end if
      end if
   end if
   if tFrom is empty then
      put "*" into tFrom
   end if
   if tTo is empty then
      put "*" into tTo
   end if
   return pField & ":[" & tFrom & " TO " & tTo & "]"
end axQueryRange

function axQueryYears pFrom, pTo
   -- The year clause the apps append: `year:[from TO to]`, each end a
   -- normalised four-digit year or "*", empty when neither is a year (a
   -- default range would silently drop every item without a year field).
   local tFrom, tTo
   put axNormalizeYear(pFrom) into tFrom
   put axNormalizeYear(pTo) into tTo
   return axQueryRange("year", tFrom, tTo)
end axQueryYears

function axQueryBuild pSpec
   -- The whole `q` from one array:
   --   base        the scope or preset query this search starts from
   --   text        the user's text (sanitized here)
   --   textField   empty: appended as ` AND (text)`; a field name:
   --               appended as ` AND field:(text)` (the author/title/
   --               collection search modes)
   --   fieldSyntax true lets the text carry field syntax (the Custom modes)
   --   yearFrom, yearTo   the year range (see axQueryYears)
   --   filters     ready clauses, one per line, each appended with AND
   --   plainText   true: the film club rule instead of the sanitizer -
   --               strip : " ( ) and wrap in parentheses
   -- Empty (with the reason) when nothing at all is left to search for.
   local tQ, tText, tYears, tCount, tI, tClause
   put axTrim(pSpec["base"]) into tQ
   if pSpec["plainText"] is true then
      put axCollapseSpaces(axBlankChars(pSpec["text"], ":" & quote & "()")) into tText
   else
      put axQuerySanitize(pSpec["text"], pSpec["fieldSyntax"] is true) into tText
   end if
   if tText is not empty then
      if pSpec["textField"] is not empty then
         put axAppendAnd(tQ, pSpec["textField"] & ":(" & tText & ")") into tQ
      else
         put axAppendAnd(tQ, "(" & tText & ")") into tQ
      end if
   end if
   put axQueryYears(pSpec["yearFrom"], pSpec["yearTo"]) into tYears
   if tYears is not empty then
      put axAppendAnd(tQ, tYears) into tQ
   end if
   put the number of lines of pSpec["filters"] into tCount
   repeat with tI = 1 to tCount
      put axTrim(line tI of pSpec["filters"]) into tClause
      if tClause is not empty then
         put axAppendAnd(tQ, tClause) into tQ
      end if
   end repeat
   if tQ is empty then
      axSetError "axQueryBuild: nothing to search for (no base, no text)"
      return empty
   end if
   return tQ
end axQueryBuild

private function axAppendAnd pQuery, pClause
   if pQuery is empty then
      return pClause
   end if
   if pClause is empty then
      return pQuery
   end if
   return pQuery & " AND " & pClause
end axAppendAnd

function axPublicDomainClause
   -- The film club's licence filter: the three licenseurl spellings that
   -- mean public domain.
   return "(licenseurl:" & quote & "http://creativecommons.org/publicdomain/mark/1.0/" & quote \
         & " OR licenseurl:" & quote & "https://creativecommons.org/publicdomain/mark/1.0/" & quote \
         & " OR licenseurl:" & quote & "http://creativecommons.org/publicdomain/" & quote & ")"
end axPublicDomainClause

-- ==========================================================================
-- Families, presets, quick filters, sorts, fields. The three apps' catalogues
-- as DATA: one row per line, "|"-separated, with "#" standing for a double
-- quote inside a query (an xTalk literal cannot hold one; the table
-- functions swap it for `quote` before returning). Nothing here is
-- computed from the site - a preset is a query somebody chose, and the
-- collections it names can go stale the way any bookmark does.
--
-- A FAMILY is one of the three apps' worlds plus a generic one:
--   etree     the Live Music Archive (the tape finder)
--   librivox  LibriVox audiobooks (the AudioBooks app)
--   movies    the Moving Image Archive (the film club)
--   any       everything on archive.org, by mediatype
-- axFamilyInfo(id) answers scope, default rows, fields, sort and the
-- playlist kind an item of that family wants.
--
-- A PRESET row is id|title|group|query|mode|yearFrom|yearTo:
--   query   the full Lucene query for a fixed preset (scope included)
--   mode    empty for a fixed preset; "collection", "creator", "title" for
--           the search modes that put the user's text into THAT field over
--           the family scope; "custom" for the modes that let the text
--           carry field syntax
--   years   a default year range some presets carry (the tape finder's
--           Grateful Dead 1965-1995)
-- ==========================================================================

function axFamilyList
   -- id|title|kind, one family per line.
   return "etree|Live music (etree)|audio-tracks" & return \
         & "librivox|Audiobooks (LibriVox)|audio-chapters" & return \
         & "movies|Films and video|video" & return \
         & "any|Everything on archive.org|auto"
end axFamilyList

function axFamilyInfo pFamily
   -- The family's array: id, title, kind, scope (the clause every search
   -- in it carries), rows (the page size its app used), fields (the
   -- comma list its app asked for), sort (its default). Empty (with the
   -- reason) for an unknown family.
   local tInfo
   if pFamily is "etree" then
      put "etree" into tInfo["id"]
      put "Live music (etree)" into tInfo["title"]
      put "audio-tracks" into tInfo["kind"]
      put "mediatype:(etree)" into tInfo["scope"]
      put 10 into tInfo["rows"]
      put "identifier,title,creator,date,year,venue,coverage,source,avg_rating,downloads" into tInfo["fields"]
      put "downloads desc" into tInfo["sort"]
      return tInfo
   end if
   if pFamily is "librivox" then
      put "librivox" into tInfo["id"]
      put "Audiobooks (LibriVox)" into tInfo["title"]
      put "audio-chapters" into tInfo["kind"]
      put "collection:(librivoxaudio)" into tInfo["scope"]
      put 24 into tInfo["rows"]
      put "identifier,title,year,creator,date,language,runtime,subject" into tInfo["fields"]
      put "downloads desc" into tInfo["sort"]
      return tInfo
   end if
   if pFamily is "movies" then
      put "movies" into tInfo["id"]
      put "Films and video" into tInfo["title"]
      put "video" into tInfo["kind"]
      -- the CHEAP scope, not the film club's full OR-list: on the live site
      -- (2026-09-15) the full scope's search did not answer inside 30 s
      -- while a collection-scoped search answered at once (gotcha 18);
      -- axVideoScope() keeps the app's full form for callers who want the
      -- collection docs among the results and can wait for them
      put "mediatype:(" & kAxVideoMediatypes & ")" into tInfo["scope"]
      put 24 into tInfo["rows"]
      put "identifier,title,description,date,downloads,creator,runtime,licenseurl,subject,mediatype,num_items" into tInfo["fields"]
      put "downloads desc" into tInfo["sort"]
      return tInfo
   end if
   if pFamily is "any" then
      put "any" into tInfo["id"]
      put "Everything on archive.org" into tInfo["title"]
      put "auto" into tInfo["kind"]
      put empty into tInfo["scope"]
      put 24 into tInfo["rows"]
      put "identifier,title,creator,date,year,mediatype,collection,downloads,avg_rating,num_reviews" into tInfo["fields"]
      put "downloads desc" into tInfo["sort"]
      return tInfo
   end if
   axSetError "axFamilyInfo: unknown family " & pFamily
   return empty
end axFamilyInfo

function axFamilyScope pFamily
   local tInfo
   put axFamilyInfo(pFamily) into tInfo
   if tInfo is empty then
      return empty
   end if
   return tInfo["scope"]
end axFamilyScope

function axVideoCollections
   -- The film club's 26 collections as id|title lines, in the app's own
   -- order (the OR-list below is built from this order too). all_videos is
   -- the "no collection filter" sentinel.
   return "all_videos|All Videos" & return \
         & "feature_films|Feature Films" & return \
         & "adviews|AdViews" & return \
         & "academic_films|Academic Films" & return \
         & "animationandcartoons|Animation & Cartoons" & return \
         & "artsandmusicvideos|Arts & Music" & return \
         & "classic_tv|Classic TV" & return \
         & "Comedy_Films|Comedy Films" & return \
         & "educationalfilms|Educational Films" & return \
         & "ephemera|Ephemeral Films" & return \
         & "FedFlix|FedFlix" & return \
         & "Film_Noir|Film Noir" & return \
         & "gamevideos|Game Videos" & return \
         & "home_movies|Home Movies" & return \
         & "movie_trailers|Movie Trailers" & return \
         & "movies|Moving Image Archive" & return \
         & "nasa|NASA Archive" & return \
         & "newsandpublicaffairs|News & Public Affairs" & return \
         & "opensource_movies|Open Source Movies" & return \
         & "prelinger|Prelinger Archives" & return \
         & "short_films|Short Format Films" & return \
         & "silent_films|Silent Films" & return \
         & "SciFi_Horror|Sci-Fi / Horror Films" & return \
         & "sports|Sports" & return \
         & "tvarchive|Television Archive" & return \
         & "television|Television"
end axVideoCollections

function axVideoScope
   -- The film club's video scope: anything whose mediatype is a video type,
   -- OR one of the known video collections themselves (so a collection
   -- shows up as an openable card). Verbatim shape:
   --   (mediatype:(movies OR video OR television) OR (mediatype:collection
   --    AND identifier:(feature_films OR ... OR television)))
   local tRows, tCount, tI, tId, tList, tSavedDelim
   put axVideoCollections() into tRows
   put the number of lines of tRows into tCount
   put empty into tList
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   repeat with tI = 1 to tCount
      put item 1 of line tI of tRows into tId
      if tId is "all_videos" then
         next repeat
      end if
      if tList is not empty then
         put " OR " after tList
      end if
      put tId after tList
   end repeat
   set the itemDelimiter to tSavedDelim
   return "(mediatype:(" & kAxVideoMediatypes & ") OR (mediatype:collection AND identifier:(" & tList & ")))"
end axVideoScope

function axPresetTable pFamily
   -- Every preset of one family, one row per line (see the header of this
   -- section for the columns). Empty for an unknown family.
   local tT, tRows, tCount, tI, tId, tTitle, tSavedDelim, tQuote
   put quote into tQuote
   put empty into tT
   if pFamily is "etree" then
      -- the tape finder's bandConfig.js, group by group
      put "AllArchive|All Archive.org live music|Quick options|mediatype:(etree)||1900|" & return after tT
      put "Collection_Search|Search by collection name|Quick options||collection||" & return after tT
      put "Custom|Custom advanced search|Quick options||custom||" & return after tT
      put "GratefulDead|Grateful Dead|Dead family|collection:(GratefulDead) AND mediatype:(etree) AND creator:(Grateful Dead)||1965|1995" & return after tT
      put "DeadAndCompany|Dead & Company|Dead family|collection:(etree) AND creator:(#Dead and Company# OR #Dead & Company#)|||" & return after tT
      put "PhilLesh|Phil Lesh & Friends|Dead family|collection:(PhilLeshandFriends) AND mediatype:(etree)|||" & return after tT
      put "JerryGarciaBand|Jerry Garcia Band|Dead family|collection:(etree) AND creator:(#Jerry Garcia Band# OR #JGB#)|||" & return after tT
      put "RatDog|Ratdog|Dead family|collection:(etree) AND creator:(#Ratdog# OR #Bob Weir and Ratdog#)|||" & return after tT
      put "BobWeir|Bob Weir|Dead family|collection:(etree) AND creator:(#Bob Weir#) -creator:(#Bob Weir and Ratdog#)|||" & return after tT
      put "Furthur|Furthur|Dead family|collection:(Furthur) AND mediatype:(etree)|||" & return after tT
      put "DarkStar|Dark Star Orchestra|Dead family|collection:(DarkStarOrchestra) AND mediatype:(etree)|||" & return after tT
      put "JRAD|Joe Russo's Almost Dead|Dead family|collection:(JoeRussosAlmostDead) AND mediatype:(etree)|||" & return after tT
      put "WidespreadPanic|Widespread Panic|Jam bands|collection:(WidespreadPanic) AND mediatype:(etree)|||" & return after tT
      put "StringCheese|String Cheese Incident|Jam bands|collection:(StringCheeseIncident) AND mediatype:(etree)|||" & return after tT
      put "UmphreysMcGee|Umphrey's McGee|Jam bands|collection:(UmphreysMcGee) AND mediatype:(etree)|||" & return after tT
      put "moe|moe.|Jam bands|collection:(moe) AND mediatype:(etree)|||" & return after tT
      put "DiscoBiscuits|Disco Biscuits|Jam bands|collection:(DiscoBiscuits) AND mediatype:(etree)|||" & return after tT
      put "STS9|STS9|Jam bands|collection:(SoundTribeSector9) AND mediatype:(etree)|||" & return after tT
      put "Goose|Goose|Jam bands|collection:(GooseBand) AND mediatype:(etree)|||" & return after tT
      put "Lotus|Lotus|Jam bands|collection:(Lotus) AND mediatype:(etree)|||" & return after tT
      put "Twiddle|Twiddle|Jam bands|collection:(Twiddle) AND mediatype:(etree)|||" & return after tT
      put "Dopapod|Dopapod|Jam bands|collection:(Dopapod) AND mediatype:(etree)|||" & return after tT
      put "PigeonsPPP|Pigeons Playing Ping Pong|Jam bands|collection:(PigeonsPlayingPingPong) AND mediatype:(etree)|||" & return after tT
      put "Spafford|Spafford|Jam bands|collection:(Spafford) AND mediatype:(etree)|||" & return after tT
      put "BillyStrings|Billy Strings|Bluegrass and acoustic|collection:(BillyStrings) AND mediatype:(etree)|||" & return after tT
      put "GreenskyBluegrass|Greensky Bluegrass|Bluegrass and acoustic|collection:(GreenskyBluegrass) AND mediatype:(etree)|||" & return after tT
      put "YonderMountain|Yonder Mountain String Band|Bluegrass and acoustic|collection:(YonderMountainStringBand) AND mediatype:(etree)|||" & return after tT
      put "LeftoverSalmon|Leftover Salmon|Bluegrass and acoustic|collection:(LeftoverSalmon) AND mediatype:(etree)|||" & return after tT
      put "KitchenDwellers|Kitchen Dwellers|Bluegrass and acoustic|collection:(KitchenDwellers) AND mediatype:(etree)|||" & return after tT
      put "InfamousStringdusters|Infamous Stringdusters|Bluegrass and acoustic|collection:(InfamousStringdusters) AND mediatype:(etree)|||" & return after tT
      put "Lettuce|Lettuce|Funk and soul|collection:(Lettuce) AND mediatype:(etree)|||" & return after tT
      put "Soulive|Soulive|Funk and soul|collection:(Soulive) AND mediatype:(etree)|||" & return after tT
      put "GalacticFunk|Galactic|Funk and soul|collection:(GalacticFunk) AND mediatype:(etree)|||" & return after tT
      put "Dumpstaphunk|Dumpstaphunk|Funk and soul|collection:(Dumpstaphunk) AND mediatype:(etree)|||" & return after tT
      put "TheMotet|The Motet|Funk and soul|collection:(TheMotet) AND mediatype:(etree)|||" & return after tT
      put "Vulfpeck|Vulfpeck|Funk and soul|collection:(Vulfpeck) AND mediatype:(etree)|||" & return after tT
      put "Ween|Ween|Rock and indie|collection:(Ween) AND mediatype:(etree)|||" & return after tT
      put "Wilco|Wilco|Rock and indie|collection:(Wilco) AND mediatype:(etree)|||" & return after tT
      put "MyMorningJacket|My Morning Jacket|Rock and indie|collection:(MyMorningJacket) AND mediatype:(etree)|||" & return after tT
      put "KingGizzard|King Gizzard & The Lizard Wizard|Rock and indie|collection:(KingGizzardAndTheLizardWizard) AND mediatype:(etree)|||" & return after tT
      put "DrDog|Dr. Dog|Rock and indie|collection:(DrDog) AND mediatype:(etree)|||" & return after tT
      put "TenaciousD|Tenacious D|Rock and indie|collection:(TenaciousD) AND mediatype:(etree)|||" & return after tT
      put "Tipper|Tipper|Electronic|collection:(Tipper) AND mediatype:(etree)|||" & return after tT
      put "Papadosio|Papadosio|Electronic|collection:(Papadosio) AND mediatype:(etree)|||" & return after tT
      put "Shpongle|Shpongle|Electronic|collection:(Shpongle) AND mediatype:(etree)|||" & return after tT
      put "EOTO|EOTO|Electronic|collection:(EOTO) AND mediatype:(etree)|||" & return after tT
      put "Matisyahu|Matisyahu|Reggae and world|collection:(Matisyahu) AND mediatype:(etree)|||" & return after tT
      put "RebelutionMusic|Rebelution|Reggae and world|collection:(RebelutionMusic) AND mediatype:(etree)|||" & return after tT
      put "StickFigure|Stick Figure|Reggae and world|collection:(StickFigure) AND mediatype:(etree)|||" & return after tT
   else if pFamily is "librivox" then
      -- the AudioBooks categoryConfig.js, in its dropdown groups
      put "AllLibriVox|All audiobooks|Browse|collection:(librivoxaudio)|||" & return after tT
      put "Author_Search|Search by author|Browse||creator||" & return after tT
      put "Title_Search|Search by title|Browse||title||" & return after tT
      put "Custom|Advanced search|Browse||custom||" & return after tT
      put "ClassicLiterature|Classic literature|Fiction|collection:(librivoxaudio) AND subject:(fiction) AND (subject:(classic) OR subject:(literature))|||" & return after tT
      put "Romance|Romance|Fiction|collection:(librivoxaudio) AND subject:(romance)|||" & return after tT
      put "Mystery|Mystery & detective|Fiction|collection:(librivoxaudio) AND (subject:(mystery) OR subject:(detective))|||" & return after tT
      put "ScienceFiction|Science fiction|Fiction|collection:(librivoxaudio) AND subject:(#science fiction#)|||" & return after tT
      put "Fantasy|Fantasy|Fiction|collection:(librivoxaudio) AND subject:(fantasy)|||" & return after tT
      put "Adventure|Adventure|Fiction|collection:(librivoxaudio) AND subject:(adventure)|||" & return after tT
      put "Horror|Horror & gothic|Fiction|collection:(librivoxaudio) AND (subject:(horror) OR subject:(ghost))|||" & return after tT
      put "ShortStories|Short stories|Fiction|collection:(librivoxaudio) AND subject:(#short stories#)|||" & return after tT
      put "Humor|Humor & satire|Fiction|collection:(librivoxaudio) AND (subject:(humor) OR subject:(humorous))|||" & return after tT
      put "History|History|Non-fiction|collection:(librivoxaudio) AND subject:(history)|||" & return after tT
      put "Biography|Biography & memoir|Non-fiction|collection:(librivoxaudio) AND (subject:(biography) OR subject:(autobiography))|||" & return after tT
      put "Philosophy|Philosophy|Non-fiction|collection:(librivoxaudio) AND subject:(philosophy)|||" & return after tT
      put "Science|Science & nature|Non-fiction|collection:(librivoxaudio) AND subject:(science) -subject:(fiction)|||" & return after tT
      put "Religion|Religion & spirituality|Non-fiction|collection:(librivoxaudio) AND (subject:(religion) OR subject:(theology))|||" & return after tT
      put "Travel|Travel & exploration|Non-fiction|collection:(librivoxaudio) AND subject:(travel)|||" & return after tT
      put "Essays|Essays & letters|Non-fiction|collection:(librivoxaudio) AND subject:(essays)|||" & return after tT
      put "Poetry|Poetry|Poetry and drama|collection:(librivoxaudio) AND subject:(poetry)|||" & return after tT
      put "Drama|Drama & plays|Poetry and drama|collection:(librivoxaudio) AND (subject:(drama) OR subject:(plays))|||" & return after tT
      put "Shakespeare|Shakespeare|Poetry and drama|collection:(librivoxaudio) AND creator:(Shakespeare)|||" & return after tT
      put "Childrens|Children's literature|Children's books|collection:(librivoxaudio) AND subject:(#children's literature#)|||" & return after tT
      put "FairyTales|Fairy tales & folklore|Children's books|collection:(librivoxaudio) AND (subject:(#fairy tales#) OR subject:(folklore))|||" & return after tT
      put "JaneAusten|Jane Austen|Popular authors|collection:(librivoxaudio) AND creator:(#Jane Austen#)|||" & return after tT
      put "CharlesDickens|Charles Dickens|Popular authors|collection:(librivoxaudio) AND creator:(#Charles Dickens#)|||" & return after tT
      put "MarkTwain|Mark Twain|Popular authors|collection:(librivoxaudio) AND creator:(#Mark Twain#)|||" & return after tT
      put "ArthurConanDoyle|Arthur Conan Doyle|Popular authors|collection:(librivoxaudio) AND creator:(#Arthur Conan Doyle#)|||" & return after tT
      put "EdgarAllanPoe|Edgar Allan Poe|Popular authors|collection:(librivoxaudio) AND creator:(#Edgar Allan Poe#)|||" & return after tT
      put "HGWells|H.G. Wells|Popular authors|collection:(librivoxaudio) AND creator:(#H. G. Wells#)|||" & return after tT
      put "JulesVerne|Jules Verne|Popular authors|collection:(librivoxaudio) AND creator:(#Jules Verne#)|||" & return after tT
      put "LouisaMayAlcott|Louisa May Alcott|Popular authors|collection:(librivoxaudio) AND creator:(#Louisa May Alcott#)|||" & return after tT
      put "OscarWilde|Oscar Wilde|Popular authors|collection:(librivoxaudio) AND creator:(#Oscar Wilde#)|||" & return after tT
      put "LFrankBaum|L. Frank Baum (Oz)|Popular authors|collection:(librivoxaudio) AND creator:(#L. Frank Baum#)|||" & return after tT
      put "French|French audiobooks|By language|collection:(librivoxaudio) AND language:(French)|||" & return after tT
      put "German|German audiobooks|By language|collection:(librivoxaudio) AND language:(German)|||" & return after tT
      put "Spanish|Spanish audiobooks|By language|collection:(librivoxaudio) AND language:(Spanish)|||" & return after tT
      put "Italian|Italian audiobooks|By language|collection:(librivoxaudio) AND language:(Italian)|||" & return after tT
      put "Russian|Russian audiobooks|By language|collection:(librivoxaudio) AND language:(Russian)|||" & return after tT
   else if pFamily is "movies" then
      -- the film club's collections: the scope alone, or the scope AND one
      -- collection; the film club never had a field-search mode (its text
      -- rule is the plain strip-and-wrap, axQueryBuild's plainText)
      put axVideoCollections() into tRows
      put the number of lines of tRows into tCount
      put the itemDelimiter into tSavedDelim
      set the itemDelimiter to "|"
      repeat with tI = 1 to tCount
         put item 1 of line tI of tRows into tId
         put item 2 of line tI of tRows into tTitle
         -- the cheap scope in both rows (gotcha 18): a collection clause is
         -- what narrows the search, the mediatype clause keeps out the
         -- collection's own sidecars and texts
         if tId is "all_videos" then
            put tId & "|" & tTitle & "|Collections|mediatype:(" & kAxVideoMediatypes & ")|||" & return after tT
         else
            put tId & "|" & tTitle & "|Collections|collection:(" & tId & ") AND mediatype:(" & kAxVideoMediatypes & ")|||" & return after tT
         end if
      end repeat
      set the itemDelimiter to tSavedDelim
   else if pFamily is "any" then
      put "all|Everything|Media types||||" & return after tT
      put "texts|Texts (books, documents)|Media types|mediatype:(texts)|||" & return after tT
      put "audio|Audio|Media types|mediatype:(audio)|||" & return after tT
      put "movies|Moving images|Media types|mediatype:(movies)|||" & return after tT
      put "image|Images|Media types|mediatype:(image)|||" & return after tT
      put "software|Software|Media types|mediatype:(software)|||" & return after tT
      put "etree|Live music|Media types|mediatype:(etree)|||" & return after tT
      put "data|Data sets|Media types|mediatype:(data)|||" & return after tT
      put "collection|Collections|Media types|mediatype:(collection)|||" & return after tT
      put "Custom|Advanced search (field syntax)|Media types||custom||" & return after tT
   else
      axSetError "axPresetTable: unknown family " & pFamily
      return empty
   end if
   replace "#" with tQuote in tT
   return axChompLine(tT)
end axPresetTable

function axPresetList pFamily
   -- id|title|group lines, for a menu.
   local tRows, tCount, tI, tOut, tSavedDelim, tLine
   put axPresetTable(pFamily) into tRows
   if tRows is empty then
      return empty
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put the number of lines of tRows into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      put item 1 of tLine & "|" & item 2 of tLine & "|" & item 3 of tLine & return after tOut
   end repeat
   set the itemDelimiter to tSavedDelim
   return axChompLine(tOut)
end axPresetList

function axPresetInfo pFamily, pId
   -- One preset's array: id, title, group, query, mode, yearFrom, yearTo,
   -- family. Ids compare byte-exactly ("moe" is not "Moe"). Empty, with
   -- the reason, when the family or the id is unknown.
   local tRows, tCount, tI, tLine, tInfo, tSavedDelim
   put axPresetTable(pFamily) into tRows
   if tRows is empty then
      return empty
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put the number of lines of tRows into tCount
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      if axStrEq(item 1 of tLine, pId) then
         put item 1 of tLine into tInfo["id"]
         put item 2 of tLine into tInfo["title"]
         put item 3 of tLine into tInfo["group"]
         put item 4 of tLine into tInfo["query"]
         put item 5 of tLine into tInfo["mode"]
         put item 6 of tLine into tInfo["yearFrom"]
         put item 7 of tLine into tInfo["yearTo"]
         put pFamily into tInfo["family"]
         set the itemDelimiter to tSavedDelim
         return tInfo
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   axSetError "axPresetInfo: unknown preset " & pId & " in family " & pFamily
   return empty
end axPresetInfo

function axPresetQuery pFamily, pId
   -- The fixed query of a preset, or the family scope for a search-mode
   -- preset (its text goes into a field, over the scope). Empty for an
   -- unknown preset.
   local tInfo
   put axPresetInfo(pFamily, pId) into tInfo
   if tInfo is empty then
      return empty
   end if
   if tInfo["mode"] is empty then
      return tInfo["query"]
   end if
   return axFamilyScope(pFamily)
end axPresetQuery

function axPresetSpec pFamily, pId, pText, pYearFrom, pYearTo, pFilters
   -- The axQueryBuild spec for "this preset, this text, these years, these
   -- filters" - the whole of each app's search-box logic in one call:
   --   fixed preset     base = its query; text appended as ` AND (text)`
   --   collection/creator/title mode   base = the family scope; text goes
   --                    into that field (the Collection_Search /
   --                    Author_Search / Title_Search modes)
   --   custom mode      base = the scope; text may carry field syntax
   --   movies family    the film club's plain strip-and-wrap text rule
   -- A preset's default year range applies only when the caller gave no
   -- year at all (the tape finder fills its year boxes from it, so a user
   -- who cleared them searched every year).
   local tInfo, tSpec, tMode
   put axPresetInfo(pFamily, pId) into tInfo
   if tInfo is empty then
      return empty
   end if
   put tInfo["mode"] into tMode
   put pText into tSpec["text"]
   put pFilters into tSpec["filters"]
   put pYearFrom into tSpec["yearFrom"]
   put pYearTo into tSpec["yearTo"]
   if axNormalizeYear(pYearFrom) is empty then
      if axNormalizeYear(pYearTo) is empty then
         put tInfo["yearFrom"] into tSpec["yearFrom"]
         put tInfo["yearTo"] into tSpec["yearTo"]
      end if
   end if
   if tMode is empty then
      put tInfo["query"] into tSpec["base"]
   else if tMode is "custom" then
      put axFamilyScope(pFamily) into tSpec["base"]
      put true into tSpec["fieldSyntax"]
   else
      put axFamilyScope(pFamily) into tSpec["base"]
      put tMode into tSpec["textField"]
   end if
   if pFamily is "movies" then
      put true into tSpec["plainText"]
   end if
   return tSpec
end axPresetSpec

function axFilterList pFamily
   -- The family's quick filters as id|label|clause lines (the tape
   -- finder's four, the AudioBooks three, the film club's public-domain
   -- switch); empty for a family with none.
   local tT, tQuote
   put quote into tQuote
   put empty into tT
   if pFamily is "etree" then
      put "soundboard|Soundboard (SBD)|source:(soundboard OR sbd OR #sbd#)" & return after tT
      put "aud|Audience (AUD)|source:(audience OR aud OR #aud#)" & return after tT
      put "matrix|Matrix|source:(matrix OR #matrix#)" & return after tT
      put "five-star|Top rated|avg_rating:[4.5 TO 5]" & return after tT
   else if pFamily is "librivox" then
      put "solo|Solo reader|subject:(solo)" & return after tT
      put "complete|Complete works|subject:(complete)" & return after tT
      put "english|English only|language:(English)" & return after tT
   else if pFamily is "movies" then
      put "publicdomain|Public domain only|" & axPublicDomainClause() & return after tT
   end if
   replace "#" with tQuote in tT
   return axChompLine(tT)
end axFilterList

function axFilterClause pFamily, pId
   -- The clause of one quick filter, or empty for an unknown id (an unknown
   -- filter is silently ignored, the AudioBooks rule).
   local tRows, tCount, tI, tLine, tSavedDelim, tClause
   put axFilterList(pFamily) into tRows
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put the number of lines of tRows into tCount
   put empty into tClause
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      if axStrEq(item 1 of tLine, pId) then
         put item 3 of tLine into tClause
         exit repeat
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   return tClause
end axFilterClause

function axFilterClauses pFamily, pIds
   -- The clauses for a comma list of filter ids, one per line, ready for a
   -- spec's "filters"; unknown ids dropped.
   local tOut, tClause, tId
   put empty into tOut
   repeat for each item tId in pIds
      put axFilterClause(pFamily, axTrim(tId)) into tClause
      if tClause is not empty then
         put tClause & return after tOut
      end if
   end repeat
   return axChompLine(tOut)
end axFilterClauses

function axSortList
   -- id|label|clause lines: the film club's sort menu plus the plain date
   -- sort its server used. "relevance" is an empty clause, which
   -- axSearchUrl turns into no sort parameter at all.
   return "downloads|Most downloaded|downloads desc" & return \
         & "date|Newest added|publicdate desc" & return \
         & "dateDesc|Date, newest first|date desc" & return \
         & "dateAsc|Date, oldest first|date asc" & return \
         & "title|Title A-Z|titleSorter asc" & return \
         & "creator|Creator A-Z|creatorSorter asc" & return \
         & "relevance|Relevance|"
end axSortList

function axSortClause pId
   -- The sort clause for a menu id. An id that is not in the menu but reads
   -- as a clause itself ("year asc") passes through; anything else
   -- answers the default, downloads desc.
   local tRows, tCount, tI, tLine, tSavedDelim, tClause, tFound
   put axSortList() into tRows
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put the number of lines of tRows into tCount
   put false into tFound
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      if axStrEq(item 1 of tLine, pId) then
         put item 3 of tLine into tClause
         put true into tFound
         exit repeat
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   if tFound then
      return tClause
   end if
   if pId ends with " asc" then
      return pId
   end if
   if pId ends with " desc" then
      return pId
   end if
   return "downloads desc"
end axSortClause

-- ==========================================================================
-- URL builders. Every one validates its identifier and prefixes
-- axBaseUrl(); the search URL's bytes match the AudioBooks app's exactly
-- (its tests pin them), which is also the form the site documents.
-- ==========================================================================

function axSearchUrl pQuery, pFields, pSort, pRows, pPage
   -- advancedsearch.php: q, one fl[] per field (comma list), sort[] when a
   -- sort is given, rows, page (1-based), output=json. Refuses an empty
   -- query, a non-numeric rows or page, and a page below 1.
   local tUrl, tRows, tPage, tField
   if axTrim(pQuery) is empty then
      axSetError "axSearchUrl: the query is empty"
      return empty
   end if
   put pRows into tRows
   if tRows is empty then
      put 24 into tRows
   end if
   put pPage into tPage
   if tPage is empty then
      put 1 into tPage
   end if
   if not axIsDigits(tRows) then
      axSetError "axSearchUrl: rows must be a whole number"
      return empty
   end if
   if not axIsDigits(tPage) then
      axSetError "axSearchUrl: page must be a whole number"
      return empty
   end if
   if tRows < 1 then
      axSetError "axSearchUrl: rows must be at least 1"
      return empty
   end if
   if tPage < 1 then
      axSetError "axSearchUrl: page must be at least 1"
      return empty
   end if
   put axBaseUrl() & "/advancedsearch.php?q=" & axQueryEncode(pQuery) into tUrl
   repeat for each item tField in pFields
      put axTrim(tField) into tField
      if tField is not empty then
         put "&fl%5B%5D=" & axQueryEncode(tField) after tUrl
      end if
   end repeat
   if axTrim(pSort) is not empty then
      put "&sort%5B%5D=" & axQueryEncode(axTrim(pSort)) after tUrl
   end if
   put "&rows=" & (tRows + 0) & "&page=" & (tPage + 0) & "&output=json" after tUrl
   return tUrl
end axSearchUrl

function axScrapeUrl pQuery, pFields, pCount, pCursor
   -- services/search/v1/scrape: the deep-paging API (advancedsearch.php
   -- stops paging past the first 10,000 hits). q, fields as one comma
   -- list, count, and the cursor a previous page returned. None of the
   -- three apps used it; it is here for a walk over a whole collection.
   -- Untested against the site: needs a live pass.
   local tUrl, tCount
   if axTrim(pQuery) is empty then
      axSetError "axScrapeUrl: the query is empty"
      return empty
   end if
   put pCount into tCount
   if tCount is empty then
      put 100 into tCount
   end if
   if not axIsDigits(tCount) then
      axSetError "axScrapeUrl: count must be a whole number"
      return empty
   end if
   put axBaseUrl() & "/services/search/v1/scrape?q=" & axQueryEncode(pQuery) into tUrl
   if axTrim(pFields) is not empty then
      put "&fields=" & axQueryEncode(axTrim(pFields)) after tUrl
   end if
   put "&count=" & (tCount + 0) after tUrl
   if pCursor is not empty then
      put "&cursor=" & axQueryEncode(pCursor) after tUrl
   end if
   return tUrl
end axScrapeUrl

function axMetadataUrl pIdentifier
   if not axIdentifierIsValid(pIdentifier) then
      axSetError "axMetadataUrl: not an archive.org identifier: " & pIdentifier
      return empty
   end if
   return axBaseUrl() & "/metadata/" & axUrlEncode(pIdentifier)
end axMetadataUrl

function axDownloadUrl pIdentifier, pFileName
   -- The streaming/download URL of one file, or the item's file listing
   -- when pFileName is empty. Segments of the file path are encoded, its
   -- "/" separators kept.
   if not axIdentifierIsValid(pIdentifier) then
      axSetError "axDownloadUrl: not an archive.org identifier: " & pIdentifier
      return empty
   end if
   if pFileName is empty then
      return axBaseUrl() & "/download/" & axUrlEncode(pIdentifier)
   end if
   return axBaseUrl() & "/download/" & axUrlEncode(pIdentifier) & "/" & axUrlEncodePath(pFileName)
end axDownloadUrl

function axDirectUrl pItem, pFileName
   -- The DATANODE URL of one file of an axItemParse item: the host and
   -- directory the metadata answer names (`server`, `dir`), which is where
   -- `/download/` redirects to. The site's own player streams from here;
   -- a player object handed the `/download/` form has to follow a 302 it
   -- may not follow, and archive.org's download URL is also the one that
   -- serves the "you are being redirected" page to clients that ask for
   -- it wrongly. Falls back to axDownloadUrl when the item carries no
   -- server (a hand-built array, an item parsed from a partial answer).
   local tServer, tDir
   if pFileName is empty then
      axSetError "axDirectUrl: no file name"
      return empty
   end if
   put pItem["server"] into tServer
   put pItem["dir"] into tDir
   if tServer is empty or tDir is empty then
      return axDownloadUrl(pItem["identifier"], pFileName)
   end if
   if tServer contains "/" then
      return axDownloadUrl(pItem["identifier"], pFileName)
   end if
   if tServer contains " " then
      return axDownloadUrl(pItem["identifier"], pFileName)
   end if
   if not (tServer contains ".") then
      return axDownloadUrl(pItem["identifier"], pFileName)
   end if
   if char 1 of tDir is not "/" then
      put "/" before tDir
   end if
   if char -1 of tDir is "/" then
      put char 1 to -2 of tDir into tDir
   end if
   return "https://" & tServer & axUrlEncodePath(tDir) & "/" & axUrlEncodePath(pFileName)
end axDirectUrl

function axThumbnailUrl pIdentifier
   -- The item image service: a JPEG the site derives for every item. The
   -- only thumbnail rule any of the three apps had.
   if not axIdentifierIsValid(pIdentifier) then
      axSetError "axThumbnailUrl: not an archive.org identifier: " & pIdentifier
      return empty
   end if
   return axBaseUrl() & "/services/img/" & axUrlEncode(pIdentifier)
end axThumbnailUrl

function axDetailsUrl pIdentifier
   -- The item's page on the site, for a browser.
   if not axIdentifierIsValid(pIdentifier) then
      axSetError "axDetailsUrl: not an archive.org identifier: " & pIdentifier
      return empty
   end if
   return axBaseUrl() & "/details/" & axUrlEncode(pIdentifier)
end axDetailsUrl

function axEmbedUrl pIdentifier
   -- The site's embeddable player page (the film club's fallback when a
   -- native video element would not play).
   if not axIdentifierIsValid(pIdentifier) then
      axSetError "axEmbedUrl: not an archive.org identifier: " & pIdentifier
      return empty
   end if
   return axBaseUrl() & "/embed/" & axUrlEncode(pIdentifier)
end axEmbedUrl

-- ==========================================================================
-- The JSON reader. Owned, because the engine's JSONToArray is not in every
-- build (nocloud probes for it and fails closed), because a reader that
-- runs headlessly has to be script, and because the two things archive.org
-- responses need - exact (case-sensitive) key lookup, and scalar-or-array
-- fields read as lines - are easier to guarantee in a parser this file
-- controls; a duplicate object key keeps its FIRST value; a number is
-- stored as its text and never converted. Refusals (empty handle, reason
-- in axLastError): a truncated document, an unterminated string, an
-- unknown escape, a lone surrogate, trailing bytes after the root,
-- mixed-case literals (tRUE is not true), and a number outside the RFC
-- 8259 grammar (a leading zero, a bare sign, an empty exponent).
-- ==========================================================================

function axJsonParse pJson
   -- Parse a whole document. Returns a document handle (an integer from
   -- 1) to hand to the axJson* readers and to axJsonFree, or empty with
   -- the reason recorded.
   local tRoot, tHandle
   put textEncode(pJson, "UTF-8") into sAxJsonBytes
   put 1 into sAxJsonPos
   put the number of bytes of sAxJsonBytes into sAxJsonLen
   put 0 into sAxJsonN
   put 0 into sAxJsonDepth
   put empty into sAxJsonErr
   put empty into sAxJsonT
   put empty into sAxJsonV
   put empty into sAxJsonC
   put empty into sAxJsonX
   put empty into sAxJsonK
   put empty into sAxJsonB1
   put empty into sAxJsonB2
   put axJsonParseValue() into tRoot
   if sAxJsonErr is empty then
      axJsonSkipWs
      if sAxJsonPos <= sAxJsonLen then
         put "trailing bytes after the document at byte " & sAxJsonPos into sAxJsonErr
      end if
   end if
   if sAxJsonErr is not empty then
      axSetError "axJsonParse: " & sAxJsonErr
      axJsonClearParseState
      return empty
   end if
   if sAxDocNext is empty then
      put 0 into sAxDocNext
   end if
   add 1 to sAxDocNext
   put sAxDocNext into tHandle
   put sAxJsonN into sAxDocs[tHandle]["n"]
   put sAxJsonT into sAxDocs[tHandle]["t"]
   put sAxJsonV into sAxDocs[tHandle]["v"]
   put sAxJsonC into sAxDocs[tHandle]["c"]
   put sAxJsonX into sAxDocs[tHandle]["x"]
   put sAxJsonK into sAxDocs[tHandle]["k"]
   put sAxJsonB1 into sAxDocs[tHandle]["b1"]
   put sAxJsonB2 into sAxDocs[tHandle]["b2"]
   put sAxJsonBytes into sAxDocs[tHandle]["src"]
   axJsonClearParseState
   return tHandle
end axJsonParse

private command axJsonClearParseState
   put empty into sAxJsonBytes
   put empty into sAxJsonT
   put empty into sAxJsonV
   put empty into sAxJsonC
   put empty into sAxJsonX
   put empty into sAxJsonK
   put empty into sAxJsonB1
   put empty into sAxJsonB2
end axJsonClearParseState

command axJsonFree pHandle
   -- Forget a parsed document. A stale or unknown handle is a clean no-op.
   if pHandle is among the keys of sAxDocs then
      put empty into sAxDocs[pHandle]
   end if
end axJsonFree

command axJsonFreeAll
   put empty into sAxDocs
end axJsonFreeAll

function axJsonHandleIsLive pHandle
   -- True while pHandle names a parsed document (a freed handle answers
   -- false, so a caller can tell a miss from a stale handle).
   if not (pHandle is among the keys of sAxDocs) then
      return false
   end if
   return sAxDocs[pHandle] is an array
end axJsonHandleIsLive

private function axJsonNewNode pType
   add 1 to sAxJsonN
   put pType into sAxJsonT[sAxJsonN]
   put empty into sAxJsonV[sAxJsonN]
   put 0 into sAxJsonC[sAxJsonN]
   return sAxJsonN
end axJsonNewNode

private command axJsonSkipWs
   local tByte
   repeat while sAxJsonPos <= sAxJsonLen
      put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
      if axIsSpaceByte(tByte) then
         add 1 to sAxJsonPos
      else
         exit repeat
      end if
   end repeat
end axJsonSkipWs

private function axJsonParseValue
   local tByte, tNode, tStart
   axJsonSkipWs
   if sAxJsonPos > sAxJsonLen then
      put "unexpected end of document" into sAxJsonErr
      return 0
   end if
   add 1 to sAxJsonDepth
   if sAxJsonDepth > kAxJsonMaxDepth then
      put "nesting deeper than " & kAxJsonMaxDepth into sAxJsonErr
      return 0
   end if
   put sAxJsonPos into tStart
   put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
   if tByte is 123 then
      put axJsonParseObject() into tNode
   else if tByte is 91 then
      put axJsonParseArray() into tNode
   else if tByte is 34 then
      put axJsonNewNode("s") into tNode
      put axJsonParseString() into sAxJsonV[tNode]
   else if tByte is 116 then
      put axJsonParseLiteral("true", "b", "true") into tNode
   else if tByte is 102 then
      put axJsonParseLiteral("false", "b", "false") into tNode
   else if tByte is 110 then
      put axJsonParseLiteral("null", "z", empty) into tNode
   else
      put axJsonParseNumber() into tNode
   end if
   if sAxJsonErr is not empty then
      return 0
   end if
   subtract 1 from sAxJsonDepth
   put tStart into sAxJsonB1[tNode]
   put sAxJsonPos - 1 into sAxJsonB2[tNode]
   return tNode
end axJsonParseValue

private function axJsonParseLiteral pWord, pType, pValue
   -- true / false / null, byte-exact (a mixed-case literal is refused).
   local tLen, tNode
   put the number of chars of pWord into tLen
   if sAxJsonPos + tLen - 1 > sAxJsonLen then
      put "truncated literal at byte " & sAxJsonPos into sAxJsonErr
      return 0
   end if
   if not axStrEq(byte sAxJsonPos to (sAxJsonPos + tLen - 1) of sAxJsonBytes, pWord) then
      put "unexpected token at byte " & sAxJsonPos into sAxJsonErr
      return 0
   end if
   put axJsonNewNode(pType) into tNode
   put pValue into sAxJsonV[tNode]
   add tLen to sAxJsonPos
   return tNode
end axJsonParseLiteral

private function axJsonParseNumber
   -- The JSON number grammar, checked loosely: an optional minus, digits,
   -- an optional fraction, an optional exponent; stored as TEXT (a number
   -- that reaches script arithmetic is converted at its use site, so an
   -- id that happens to be numeric keeps its leading zeros).
   local tStart, tByte, tText, tNode, tDigits
   put sAxJsonPos into tStart
   put 0 into tDigits
   repeat while sAxJsonPos <= sAxJsonLen
      put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
      if axIsDigitByte(tByte) then
         add 1 to tDigits
         add 1 to sAxJsonPos
      else if tByte is 45 then
         add 1 to sAxJsonPos
      else if tByte is 43 then
         add 1 to sAxJsonPos
      else if tByte is 46 then
         add 1 to sAxJsonPos
      else if tByte is 101 then
         add 1 to sAxJsonPos
      else if tByte is 69 then
         add 1 to sAxJsonPos
      else
         exit repeat
      end if
   end repeat
   if tDigits is 0 then
      put "unexpected token at byte " & tStart into sAxJsonErr
      return 0
   end if
   put byte tStart to (sAxJsonPos - 1) of sAxJsonBytes into tText
   if not axJsonNumberOk(tText) then
      put "malformed number at byte " & tStart into sAxJsonErr
      return 0
   end if
   put axJsonNewNode("n") into tNode
   put tText into sAxJsonV[tNode]
   return tNode
end axJsonParseNumber

private function axJsonNumberOk pText
   -- The RFC 8259 number grammar: an optional minus, an integer part that
   -- is "0" or starts with 1-9 (a leading zero is refused - "01" is not a
   -- JSON number), an optional fraction with at least one digit, an
   -- optional exponent with an optional sign and at least one digit.
   local tPos, tCount, tByte, tDigits
   put the number of chars of pText into tCount
   put 1 into tPos
   if tPos <= tCount then
      if byteToNum(char tPos of pText) is 45 then
         add 1 to tPos
      end if
   end if
   if tPos > tCount then
      return false
   end if
   put byteToNum(char tPos of pText) into tByte
   if tByte is 48 then
      add 1 to tPos
   else
      if not axIsDigitByte(tByte) then
         return false
      end if
      repeat while tPos <= tCount
         if axIsDigitByte(byteToNum(char tPos of pText)) then
            add 1 to tPos
         else
            exit repeat
         end if
      end repeat
   end if
   if tPos <= tCount then
      if byteToNum(char tPos of pText) is 46 then
         add 1 to tPos
         put 0 into tDigits
         repeat while tPos <= tCount
            if axIsDigitByte(byteToNum(char tPos of pText)) then
               add 1 to tDigits
               add 1 to tPos
            else
               exit repeat
            end if
         end repeat
         if tDigits is 0 then
            return false
         end if
      end if
   end if
   if tPos <= tCount then
      put byteToNum(char tPos of pText) into tByte
      if tByte is 101 then
         add 1 to tPos
      else if tByte is 69 then
         add 1 to tPos
      else
         return false
      end if
      if tPos <= tCount then
         put byteToNum(char tPos of pText) into tByte
         if tByte is 43 then
            add 1 to tPos
         else if tByte is 45 then
            add 1 to tPos
         end if
      end if
      put 0 into tDigits
      repeat while tPos <= tCount
         if axIsDigitByte(byteToNum(char tPos of pText)) then
            add 1 to tDigits
            add 1 to tPos
         else
            exit repeat
         end if
      end repeat
      if tDigits is 0 then
         return false
      end if
   end if
   return tPos > tCount
end axJsonNumberOk

private function axJsonParseString
   -- From the opening quote to the closing one, escapes decoded, the value
   -- as text. Jumps with byteOffset: the next quote and the next backslash
   -- are found natively, and only the bytes between them are copied.
   local tOut, tQ, tBs, tSkip, tByte, tCode, tLow, tHexText
   add 1 to sAxJsonPos
   put empty into tOut
   repeat forever
      put sAxJsonPos - 1 into tSkip
      put byteOffset(numToByte(34), sAxJsonBytes, tSkip) into tQ
      if tQ is 0 then
         put "unterminated string" into sAxJsonErr
         return empty
      end if
      put byteOffset(numToByte(92), sAxJsonBytes, tSkip) into tBs
      if tBs is 0 then
         put tQ + 1 into tBs
      end if
      if tBs > tQ then
         if tQ > 1 then
            put byte sAxJsonPos to (tSkip + tQ - 1) of sAxJsonBytes after tOut
         end if
         put tSkip + tQ + 1 into sAxJsonPos
         exit repeat
      end if
      if tBs > 1 then
         put byte sAxJsonPos to (tSkip + tBs - 1) of sAxJsonBytes after tOut
      end if
      put tSkip + tBs + 1 into sAxJsonPos
      if sAxJsonPos > sAxJsonLen then
         put "unterminated escape" into sAxJsonErr
         return empty
      end if
      put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
      if tByte is 34 then
         put numToByte(34) after tOut
      else if tByte is 92 then
         put numToByte(92) after tOut
      else if tByte is 47 then
         put numToByte(47) after tOut
      else if tByte is 98 then
         put numToByte(8) after tOut
      else if tByte is 102 then
         put numToByte(12) after tOut
      else if tByte is 110 then
         put numToByte(10) after tOut
      else if tByte is 114 then
         put numToByte(13) after tOut
      else if tByte is 116 then
         put numToByte(9) after tOut
      else if tByte is 117 then
         put axJsonHex4(sAxJsonPos + 1) into tCode
         if tCode is empty then
            put "bad \u escape at byte " & sAxJsonPos into sAxJsonErr
            return empty
         end if
         add 4 to sAxJsonPos
         if tCode >= 55296 then
            if tCode <= 56319 then
               -- a high surrogate: the low one must follow as \uDC00..DFFF
               if sAxJsonPos + 6 > sAxJsonLen then
                  put "lone high surrogate at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               if byteToNum(byte (sAxJsonPos + 1) of sAxJsonBytes) is not 92 then
                  put "lone high surrogate at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               if byteToNum(byte (sAxJsonPos + 2) of sAxJsonBytes) is not 117 then
                  put "lone high surrogate at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               put axJsonHex4(sAxJsonPos + 3) into tLow
               if tLow is empty then
                  put "bad \u escape at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               if tLow < 56320 then
                  put "lone high surrogate at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               if tLow > 57343 then
                  put "lone high surrogate at byte " & sAxJsonPos into sAxJsonErr
                  return empty
               end if
               put 65536 + (tCode - 55296) * 1024 + (tLow - 56320) into tCode
               add 6 to sAxJsonPos
            else if tCode <= 57343 then
               put "lone low surrogate at byte " & sAxJsonPos into sAxJsonErr
               return empty
            end if
         end if
         put axUtf8Bytes(tCode) after tOut
      else
         put "unknown escape at byte " & sAxJsonPos into sAxJsonErr
         return empty
      end if
      add 1 to sAxJsonPos
   end repeat
   return textDecode(tOut, "UTF-8")
end axJsonParseString

private function axJsonHex4 pPos
   -- The value of the four hex digits at pPos, or empty.
   local tI, tByte, tValue
   if pPos + 3 > sAxJsonLen then
      return empty
   end if
   put 0 into tValue
   repeat with tI = 0 to 3
      put byteToNum(byte (pPos + tI) of sAxJsonBytes) into tByte
      if axIsDigitByte(tByte) then
         put tValue * 16 + (tByte - 48) into tValue
      else if tByte >= 97 then
         if tByte <= 102 then
            put tValue * 16 + (tByte - 87) into tValue
         else
            return empty
         end if
      else if tByte >= 65 then
         if tByte <= 70 then
            put tValue * 16 + (tByte - 55) into tValue
         else
            return empty
         end if
      else
         return empty
      end if
   end repeat
   return tValue
end axJsonHex4

function axUtf8Bytes pCode
   -- The UTF-8 encoding of one code point, as bytes.
   local tOut
   if pCode < 128 then
      return numToByte(pCode)
   end if
   if pCode < 2048 then
      put numToByte(192 + axIntDiv(pCode, 64)) into tOut
      put numToByte(128 + axIntMod(pCode, 64)) after tOut
      return tOut
   end if
   if pCode < 65536 then
      put numToByte(224 + axIntDiv(pCode, 4096)) into tOut
      put numToByte(128 + axIntMod(axIntDiv(pCode, 64), 64)) after tOut
      put numToByte(128 + axIntMod(pCode, 64)) after tOut
      return tOut
   end if
   put numToByte(240 + axIntDiv(pCode, 262144)) into tOut
   put numToByte(128 + axIntMod(axIntDiv(pCode, 4096), 64)) after tOut
   put numToByte(128 + axIntMod(axIntDiv(pCode, 64), 64)) after tOut
   put numToByte(128 + axIntMod(pCode, 64)) after tOut
   return tOut
end axUtf8Bytes

private function axJsonParseObject
   local tNode, tByte, tKey, tChild, tCount
   put axJsonNewNode("o") into tNode
   add 1 to sAxJsonPos
   axJsonSkipWs
   if sAxJsonPos > sAxJsonLen then
      put "unterminated object" into sAxJsonErr
      return 0
   end if
   if byteToNum(byte sAxJsonPos of sAxJsonBytes) is 125 then
      add 1 to sAxJsonPos
      return tNode
   end if
   put 0 into tCount
   repeat forever
      axJsonSkipWs
      if sAxJsonPos > sAxJsonLen then
         put "unterminated object" into sAxJsonErr
         return 0
      end if
      if byteToNum(byte sAxJsonPos of sAxJsonBytes) is not 34 then
         put "expected a string key at byte " & sAxJsonPos into sAxJsonErr
         return 0
      end if
      put axJsonParseString() into tKey
      if sAxJsonErr is not empty then
         return 0
      end if
      axJsonSkipWs
      if sAxJsonPos > sAxJsonLen then
         put "unterminated object" into sAxJsonErr
         return 0
      end if
      if byteToNum(byte sAxJsonPos of sAxJsonBytes) is not 58 then
         put "expected a colon at byte " & sAxJsonPos into sAxJsonErr
         return 0
      end if
      add 1 to sAxJsonPos
      put axJsonParseValue() into tChild
      if sAxJsonErr is not empty then
         return 0
      end if
      add 1 to tCount
      put tKey into sAxJsonK[tNode][tCount]
      put tChild into sAxJsonX[tNode][tCount]
      -- a duplicate key is kept here in document order; axJsonFindKey
      -- answers the FIRST exact match, which is the "first value wins" rule
      axJsonSkipWs
      if sAxJsonPos > sAxJsonLen then
         put "unterminated object" into sAxJsonErr
         return 0
      end if
      put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
      add 1 to sAxJsonPos
      if tByte is 125 then
         exit repeat
      end if
      if tByte is not 44 then
         put "expected a comma or a closing brace at byte " & (sAxJsonPos - 1) into sAxJsonErr
         return 0
      end if
   end repeat
   put tCount into sAxJsonC[tNode]
   return tNode
end axJsonParseObject

private function axJsonParseArray
   local tNode, tByte, tChild, tCount
   put axJsonNewNode("a") into tNode
   add 1 to sAxJsonPos
   axJsonSkipWs
   if sAxJsonPos > sAxJsonLen then
      put "unterminated array" into sAxJsonErr
      return 0
   end if
   if byteToNum(byte sAxJsonPos of sAxJsonBytes) is 93 then
      add 1 to sAxJsonPos
      return tNode
   end if
   put 0 into tCount
   repeat forever
      put axJsonParseValue() into tChild
      if sAxJsonErr is not empty then
         return 0
      end if
      add 1 to tCount
      put tChild into sAxJsonX[tNode][tCount]
      axJsonSkipWs
      if sAxJsonPos > sAxJsonLen then
         put "unterminated array" into sAxJsonErr
         return 0
      end if
      put byteToNum(byte sAxJsonPos of sAxJsonBytes) into tByte
      add 1 to sAxJsonPos
      if tByte is 93 then
         exit repeat
      end if
      if tByte is not 44 then
         put "expected a comma or a closing bracket at byte " & (sAxJsonPos - 1) into sAxJsonErr
         return 0
      end if
   end repeat
   put tCount into sAxJsonC[tNode]
   return tNode
end axJsonParseArray

private function axJsonFindKey pHandle, pNode, pKey
   -- The child of object pNode whose key is BYTE-EXACTLY pKey, first in
   -- document order, or 0. A scan over the key list, deliberately not an
   -- array lookup: the first version kept an index keyed by the JSON key
   -- and the engine answered the "a" node for "A" - array keys fold case on
   -- OXT (OBSERVED 2026-09-15, the member's first engine contact;
   -- docs/OXT-ENGINE-NOTES.md 2.7). Objects here are small (a file record
   -- has a dozen keys), so the scan costs nothing a caller can see.
   local tCount, tI
   put sAxDocs[pHandle]["c"][pNode] into tCount
   if not axIsDigits(tCount) then
      return 0
   end if
   repeat with tI = 1 to tCount
      if axStrEq(sAxDocs[pHandle]["k"][pNode][tI], pKey) then
         return sAxDocs[pHandle]["x"][pNode][tI]
      end if
   end repeat
   return 0
end axJsonFindKey

private function axJsonNode pHandle, pPath
   -- The node index at pPath ("response/docs/3/identifier": object keys
   -- exact, array indices 1-based digit runs), 1 for the root when pPath
   -- is empty, 0 for a miss. A miss is not an error - an absent field is
   -- the normal shape of an archive.org record - but an unknown handle is.
   local tNode, tSavedDelim, tCount, tI, tStep, tType, tIndex
   if not axJsonHandleIsLive(pHandle) then
      axSetError "axJson: not a live document handle: " & pHandle
      return 0
   end if
   put 1 into tNode
   if pPath is empty then
      return tNode
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "/"
   put the number of items of pPath into tCount
   repeat with tI = 1 to tCount
      put item tI of pPath into tStep
      put sAxDocs[pHandle]["t"][tNode] into tType
      if tType is "o" then
         put axJsonFindKey(pHandle, tNode, tStep) into tNode
         if tNode is 0 then
            set the itemDelimiter to tSavedDelim
            return 0
         end if
      else if tType is "a" then
         if not axIsDigits(tStep) then
            set the itemDelimiter to tSavedDelim
            return 0
         end if
         put tStep + 0 into tIndex
         if tIndex < 1 then
            set the itemDelimiter to tSavedDelim
            return 0
         end if
         if tIndex > sAxDocs[pHandle]["c"][tNode] then
            set the itemDelimiter to tSavedDelim
            return 0
         end if
         put sAxDocs[pHandle]["x"][tNode][tIndex] into tNode
      else
         set the itemDelimiter to tSavedDelim
         return 0
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   return tNode
end axJsonNode

function axJsonType pHandle, pPath
   -- "object", "array", "string", "number", "boolean", "null", or
   -- "missing" when the path does not resolve.
   local tNode, tKind
   put axJsonNode(pHandle, pPath) into tNode
   if tNode is 0 then
      return "missing"
   end if
   put sAxDocs[pHandle]["t"][tNode] into tKind
   if tKind is "o" then
      return "object"
   end if
   if tKind is "a" then
      return "array"
   end if
   if tKind is "s" then
      return "string"
   end if
   if tKind is "n" then
      return "number"
   end if
   if tKind is "b" then
      return "boolean"
   end if
   return "null"
end axJsonType

function axJsonGet pHandle, pPath
   -- The scalar at pPath: strings decoded, numbers as their text, booleans
   -- "true"/"false", null and a miss both empty (axJsonType tells them
   -- apart). A container answers its VERBATIM source slice, so a caller can
   -- hand a sub-document on or re-parse it.
   local tNode, tKind
   put axJsonNode(pHandle, pPath) into tNode
   if tNode is 0 then
      return empty
   end if
   put sAxDocs[pHandle]["t"][tNode] into tKind
   if tKind is "o" then
      return textDecode(byte sAxDocs[pHandle]["b1"][tNode] to sAxDocs[pHandle]["b2"][tNode] of sAxDocs[pHandle]["src"], "UTF-8")
   end if
   if tKind is "a" then
      return textDecode(byte sAxDocs[pHandle]["b1"][tNode] to sAxDocs[pHandle]["b2"][tNode] of sAxDocs[pHandle]["src"], "UTF-8")
   end if
   return sAxDocs[pHandle]["v"][tNode]
end axJsonGet

function axJsonCount pHandle, pPath
   -- The element count of the array, or member count of the object, at
   -- pPath; empty for a scalar or a miss.
   local tNode, tKind
   put axJsonNode(pHandle, pPath) into tNode
   if tNode is 0 then
      return empty
   end if
   put sAxDocs[pHandle]["t"][tNode] into tKind
   if tKind is "o" then
      return sAxDocs[pHandle]["c"][tNode]
   end if
   if tKind is "a" then
      return sAxDocs[pHandle]["c"][tNode]
   end if
   return empty
end axJsonCount

function axJsonKeys pHandle, pPath
   -- The keys of the object at pPath, one per line, in document order;
   -- empty for anything else.
   local tNode, tCount, tI, tOut
   put axJsonNode(pHandle, pPath) into tNode
   if tNode is 0 then
      return empty
   end if
   if sAxDocs[pHandle]["t"][tNode] is not "o" then
      return empty
   end if
   put sAxDocs[pHandle]["c"][tNode] into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put sAxDocs[pHandle]["k"][tNode][tI] & return after tOut
   end repeat
   return axChompLine(tOut)
end axJsonKeys

function axJsonValues pHandle, pPath
   -- The scalar-or-array rule archive.org fields need: a scalar at pPath
   -- answers its value as one line; an array answers its SCALAR elements
   -- one per line (nested containers are skipped); an object or a miss
   -- answers empty. This is how a "creator" that is sometimes a string and
   -- sometimes a list becomes lines either way.
   local tNode, tKind, tCount, tI, tChild, tOut
   put axJsonNode(pHandle, pPath) into tNode
   if tNode is 0 then
      return empty
   end if
   put sAxDocs[pHandle]["t"][tNode] into tKind
   if tKind is "o" then
      return empty
   end if
   if tKind is not "a" then
      return sAxDocs[pHandle]["v"][tNode]
   end if
   put sAxDocs[pHandle]["c"][tNode] into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      put sAxDocs[pHandle]["x"][tNode][tI] into tChild
      put sAxDocs[pHandle]["t"][tChild] into tKind
      if tKind is "o" then
         next repeat
      end if
      if tKind is "a" then
         next repeat
      end if
      put sAxDocs[pHandle]["v"][tChild] & return after tOut
   end repeat
   return axChompLine(tOut)
end axJsonValues

-- ==========================================================================
-- Response parsers: the two documents archive.org answers with, turned into
-- xTalk arrays with every scalar-or-array field read as LINES.
-- ==========================================================================

function axSearchParse pJson
   -- An advancedsearch.php response as an array:
   --   numFound   the site's total (it OVER-REPORTS: it will not page out
   --              everything it counts, so a page shorter than rows is the
   --              end - the AudioBooks lesson)
   --   start      the 0-based offset of this page
   --   count      docs on this page
   --   docs[i][field]   each field as lines
   -- Empty, with the reason, for a malformed body - and for the site's own
   -- error shape: a malformed query comes back HTTP 200 with a top-level
   -- "error" string, which is the only way to tell.
   local tDoc, tResult, tCount, tI, tKeys, tKeyCount, tJ, tKey, tPath, tNum
   put axJsonParse(pJson) into tDoc
   if tDoc is empty then
      return empty
   end if
   if axJsonType(tDoc, "error") is "string" then
      axSetError "Archive.org rejected the query: " & axJsonGet(tDoc, "error")
      axJsonFree tDoc
      return empty
   end if
   if axJsonType(tDoc, "response/docs") is not "array" then
      axSetError "axSearchParse: unexpected response (no response.docs array)"
      axJsonFree tDoc
      return empty
   end if
   put axJsonCount(tDoc, "response/docs") into tCount
   put axJsonGet(tDoc, "response/numFound") into tNum
   if not axIsDigits(tNum) then
      put tCount into tNum
   end if
   put tNum + 0 into tResult["numFound"]
   put axJsonGet(tDoc, "response/start") into tNum
   if not axIsDigits(tNum) then
      put 0 into tNum
   end if
   put tNum + 0 into tResult["start"]
   put tCount into tResult["count"]
   repeat with tI = 1 to tCount
      put "response/docs/" & tI into tPath
      put axJsonKeys(tDoc, tPath) into tKeys
      put the number of lines of tKeys into tKeyCount
      repeat with tJ = 1 to tKeyCount
         put line tJ of tKeys into tKey
         put axJsonValues(tDoc, tPath & "/" & tKey) into tResult["docs"][tI][tKey]
      end repeat
      if tKeyCount is 0 then
         put empty into tResult["docs"][tI]["identifier"]
      end if
   end repeat
   axJsonFree tDoc
   return tResult
end axSearchParse

function axScrapeParse pJson
   -- A services/search/v1/scrape response as an array, the deep-paging
   -- API's shape from its documentation (no source app used it; the
   -- demo's Live probe leg 9 is its first live reading):
   --   count      items on this page
   --   total      the site's total for the query (when it sends one)
   --   cursor     the token for the next page; EMPTY on the last page,
   --              which is how a walk knows to stop
   --   items[i][field]   each field as lines
   -- Empty, with the reason, for a malformed body and for the API's own
   -- top-level "error" string.
   local tDoc, tResult, tCount, tI, tKeys, tKeyCount, tJ, tKey, tPath, tNum
   put axJsonParse(pJson) into tDoc
   if tDoc is empty then
      return empty
   end if
   if axJsonType(tDoc, "error") is "string" then
      axSetError "Archive.org rejected the scrape: " & axJsonGet(tDoc, "error")
      axJsonFree tDoc
      return empty
   end if
   if axJsonType(tDoc, "items") is not "array" then
      axSetError "axScrapeParse: unexpected response (no items array)"
      axJsonFree tDoc
      return empty
   end if
   put axJsonCount(tDoc, "items") into tCount
   put tCount into tResult["count"]
   put axJsonGet(tDoc, "total") into tNum
   if not axIsDigits(tNum) then
      put empty into tNum
   end if
   put tNum into tResult["total"]
   if axJsonType(tDoc, "cursor") is "string" then
      put axJsonGet(tDoc, "cursor") into tResult["cursor"]
   else
      put empty into tResult["cursor"]
   end if
   repeat with tI = 1 to tCount
      put "items/" & tI into tPath
      put axJsonKeys(tDoc, tPath) into tKeys
      put the number of lines of tKeys into tKeyCount
      repeat with tJ = 1 to tKeyCount
         put line tJ of tKeys into tKey
         put axJsonValues(tDoc, tPath & "/" & tKey) into tResult["items"][tI][tKey]
      end repeat
      if tKeyCount is 0 then
         put empty into tResult["items"][tI]["identifier"]
      end if
   end repeat
   axJsonFree tDoc
   return tResult
end axScrapeParse

function axItemParse pJson
   -- A /metadata/<identifier> response as an array:
   --   identifier          from the metadata block
   --   metadata[field]     every metadata field, as lines
   --   files[i][field]     every file's fields (name, format, size, length,
   --                       title, track, source, original, md5, ...)
   --   filesCount, itemSize, server, dir
   -- A missing item is an EMPTY body ({}) with HTTP 200 - the metadata
   -- block's absence is the only signal, and it answers empty with a
   -- "not found" reason.
   local tDoc, tItem, tKeys, tKeyCount, tJ, tKey, tCount, tI, tPath
   put axJsonParse(pJson) into tDoc
   if tDoc is empty then
      return empty
   end if
   if axJsonType(tDoc, "metadata") is not "object" then
      axSetError "axItemParse: the item could not be found on Archive.org (no metadata block)"
      axJsonFree tDoc
      return empty
   end if
   put axJsonKeys(tDoc, "metadata") into tKeys
   put the number of lines of tKeys into tKeyCount
   repeat with tJ = 1 to tKeyCount
      put line tJ of tKeys into tKey
      put axJsonValues(tDoc, "metadata/" & tKey) into tItem["metadata"][tKey]
   end repeat
   put axFirst(tItem["metadata"]["identifier"]) into tItem["identifier"]
   put 0 into tCount
   if axJsonType(tDoc, "files") is "array" then
      put axJsonCount(tDoc, "files") into tCount
   end if
   repeat with tI = 1 to tCount
      put "files/" & tI into tPath
      put axJsonKeys(tDoc, tPath) into tKeys
      put the number of lines of tKeys into tKeyCount
      repeat with tJ = 1 to tKeyCount
         put line tJ of tKeys into tKey
         put axJsonValues(tDoc, tPath & "/" & tKey) into tItem["files"][tI][tKey]
      end repeat
      if tKeyCount is 0 then
         put empty into tItem["files"][tI]["name"]
      end if
   end repeat
   put tCount into tItem["filesCount"]
   put axJsonGet(tDoc, "item_size") into tItem["itemSize"]
   put axJsonGet(tDoc, "server") into tItem["server"]
   put axJsonGet(tDoc, "dir") into tItem["dir"]
   axJsonFree tDoc
   return tItem
end axItemParse

function axDocsTable pResult, pFields
   -- A search result as tab-separated lines for a table field: one line
   -- per doc, the comma-listed fields in order, first value of each, any
   -- tab or line break inside a value replaced by a space.
   local tCount, tI, tField, tOut, tLine, tValue
   put pResult["count"] into tCount
   if not axIsDigits(tCount) then
      return empty
   end if
   put empty into tOut
   repeat with tI = 1 to tCount
      put empty into tLine
      repeat for each item tField in pFields
         put axFirst(pResult["docs"][tI][axTrim(tField)]) into tValue
         put axBlankChars(tValue, tab) into tValue
         if tLine is not empty then
            put tab after tLine
         end if
         put tValue after tLine
      end repeat
      put tLine & return after tOut
   end repeat
   return axChompLine(tOut)
end axDocsTable

-- ==========================================================================
-- Files to playlists. An archive.org item's file list mixes originals,
-- derivatives (the site's own re-encodes of each original), thumbnails,
-- spectrograms, metadata sidecars and torrents. The three apps each wrote a
-- rule that turns that list into the thing a player wants, and the rules
-- share one shape: ACCEPT the files of the right kind, GROUP the encodes
-- of one thing together, RANK inside the group to pick what to play,
-- DERIVE a title, a track number and a length, then ORDER the groups. The
-- engine below is that shape once, with the kind deciding each step:
--   audio-chapters   LibriVox: group by the original a derivative names,
--                    prefer an original MP3, then 64k, then VBR (Safari
--                    cannot play Ogg); title from the file's own title
--   audio-tracks     etree: group by stem, prefer VBR MP3 for streaming
--                    over 128k, 64k, Ogg, then lossless; titles cleaned of
--                    the d1t01 prefix
--   video            the film club: group by normalizeBaseName, MP4 first
--                    and the largest encode wins; every encode kept as a
--                    quality variant
--   documents        texts: one entry per readable file, PDF listed
--                    first, then EPUB, DjVu, plain text
--   images           one entry per image file
--   files            everything that is not a sidecar, one per file
-- Every entry carries name, title, track, length (seconds), format, size,
-- url (the download URL), stem, and for video quality + variants.
-- ==========================================================================

function axFileExtension pName
   -- The lower-cased extension of a file name (after the last "."), or
   -- empty when there is none or the name ends in a "/".
   local tLower, tI, tCount, tByte
   put axLowerAscii(pName) into tLower
   put the number of chars of tLower into tCount
   repeat with tI = tCount down to 1
      put byteToNum(char tI of tLower) into tByte
      if tByte is 46 then
         if tI is tCount then
            return empty
         end if
         return char (tI + 1) to tCount of tLower
      end if
      if tByte is 47 then
         return empty
      end if
   end repeat
   return empty
end axFileExtension

private function axStripExtension pName
   -- The name without its final extension (any run of non-dot characters
   -- after the last dot), or the name itself when there is none.
   local tI, tCount, tByte
   put the number of chars of pName into tCount
   repeat with tI = tCount down to 1
      put byteToNum(char tI of pName) into tByte
      if tByte is 46 then
         if tI is 1 then
            return pName
         end if
         return char 1 to (tI - 1) of pName
      end if
      if tByte is 47 then
         return pName
      end if
   end repeat
   return pName
end axStripExtension

private function axEndsWithAny pText, pSuffixes
   -- Byte-exact ends-with over a comma list of suffixes (call with both
   -- sides lower-cased).
   local tSuffix, tLen, tCount
   put the number of chars of pText into tCount
   repeat for each item tSuffix in pSuffixes
      put the number of chars of tSuffix into tLen
      if tLen is 0 then
         next repeat
      end if
      if tCount < tLen then
         next repeat
      end if
      if axStrEq(char (tCount - tLen + 1) to tCount of pText, tSuffix) then
         return true
      end if
   end repeat
   return false
end axEndsWithAny

private function axContainsAny pText, pNeedles
   -- Byte-exact substring test over a comma list (both sides lower-cased
   -- by the caller): `contains` would fold case on the engine and not in
   -- the headless model, so neither is used on raw text.
   local tNeedle
   repeat for each item tNeedle in pNeedles
      if tNeedle is empty then
         next repeat
      end if
      if offset(tNeedle, pText) > 0 then
         return true
      end if
   end repeat
   return false
end axContainsAny

private function axHasItem pList, pItem
   -- Byte-exact membership in a comma list.
   local tItem
   repeat for each item tItem in pList
      if axStrEq(tItem, pItem) then
         return true
      end if
   end repeat
   return false
end axHasItem

function axFileIsAudio pFile
   -- The AudioBooks isAudioFile: the name must carry an audio extension,
   -- the format must not name a non-audio derivative (a ZIP of MP3s, a
   -- spectrogram, a playlist, a sidecar), and the format must be empty or
   -- name an audio codec. A file with no name is never audio.
   local tExtn, tFormat
   if pFile["name"] is empty then
      return false
   end if
   put axFileExtension(pFile["name"]) into tExtn
   if not axHasItem("mp3,ogg,oga,opus,m4a,m4b,flac,wav", tExtn) then
      return false
   end if
   put axLowerAscii(pFile["format"]) into tFormat
   if axContainsAny(tFormat, "zip,m3u,spectrogram,png,jpeg,jpg,peaks,metadata,torrent,text,xml") then
      return false
   end if
   if tFormat is empty then
      return true
   end if
   return axContainsAny(tFormat, "mp3,ogg,vorbis,mpeg,audio,flac,wave,opus,aac")
end axFileIsAudio

function axFileIsVideo pFile
   -- The film club's getVideoFiles filter: sidecars and the site's own
   -- auxiliary files rejected by name, non-video formats rejected by
   -- format hint, then a playable or tolerated extension OR a video format
   -- hint required, and anything under 100 KB dropped as a placeholder.
   local tName, tExtn, tFormat, tSize, tOk
   if pFile["name"] is empty then
      return false
   end if
   put axLowerAscii(pFile["name"]) into tName
   put axFileExtension(tName) into tExtn
   if axEndsWithAny(tName, "_meta.xml,_meta.sqlite,_meta.json,_files.xml,_files.json,_reviews.xml,_reviews.json") then
      return false
   end if
   if axContainsAny(tName, "_itemimage.,__ia_thumb.") then
      return false
   end if
   if axEndsWithAny(tName, "_thumb.jpg,_thumb.jpeg,_thumb.png,_thumb.gif,_thumb.webp") then
      return false
   end if
   if axHasItem("torrent,srt,vtt,ass,ssa,json,xml,txt,pdf,doc,docx,sqlite,gz,zip,nfo,md5,asr,cue,ia", tExtn) then
      return false
   end if
   put axLowerAscii(pFile["format"]) into tFormat
   if axContainsAny(tFormat, "metadata,text,image,thumbnail,archive bittorrent,json,item tile,subtitles") then
      return false
   end if
   put false into tOk
   if axHasItem("mp4,m4v,webm,ogv,ogg,mov,mpg,mpeg", tExtn) then
      put true into tOk
   end if
   if axHasItem("avi,flv,mkv,wmv", tExtn) then
      put true into tOk
   end if
   if axContainsAny(tFormat, "mp4,mpeg,video,h.264,h264,webm,ogv,ogg video,matroska,quicktime") then
      put true into tOk
   end if
   if not tOk then
      return false
   end if
   put pFile["size"] into tSize
   if axIsDigits(tSize) then
      if tSize > 0 then
         if tSize < 102400 then
            return false
         end if
      end if
   end if
   return true
end axFileIsVideo

function axFileIsDocument pFile
   -- A readable text derivative: PDF, EPUB, DjVu, plain text, the ebook
   -- containers; sidecars and OCR working files refused.
   local tName, tExtn, tFormat
   if pFile["name"] is empty then
      return false
   end if
   put axLowerAscii(pFile["name"]) into tName
   put axFileExtension(tName) into tExtn
   if axEndsWithAny(tName, "_meta.xml,_files.xml,_reviews.xml,_meta.sqlite,_abbyy.gz,_djvu.xml,_scandata.xml,_hocr.html") then
      return false
   end if
   put axLowerAscii(pFile["format"]) into tFormat
   if axContainsAny(tFormat, "metadata,archive bittorrent,item tile,abbyy,scandata,hocr") then
      return false
   end if
   if axHasItem("pdf,epub,djvu,txt,mobi,azw3,cbz,cbr,rtf,html,htm", tExtn) then
      return true
   end if
   return axContainsAny(tFormat, "pdf,epub,djvu,kindle,daisy,full text,plain text")
end axFileIsDocument

function axFileIsImage pFile
   local tName, tExtn, tFormat
   if pFile["name"] is empty then
      return false
   end if
   put axLowerAscii(pFile["name"]) into tName
   put axFileExtension(tName) into tExtn
   if axContainsAny(tName, "__ia_thumb.,_itemimage.") then
      return false
   end if
   if axEndsWithAny(tName, "_thumb.jpg,_thumb.jpeg,_thumb.png,_thumb.gif,_thumb.webp") then
      return false
   end if
   put axLowerAscii(pFile["format"]) into tFormat
   if axContainsAny(tFormat, "thumb,item tile,metadata,spectrogram") then
      return false
   end if
   return axHasItem("jpg,jpeg,png,gif,tif,tiff,webp,bmp,jp2", tExtn)
end axFileIsImage

function axFileIsContent pFile
   -- Anything that is not one of the site's own sidecars: the "files"
   -- kind's accept test.
   local tName, tExtn, tFormat
   if pFile["name"] is empty then
      return false
   end if
   put axLowerAscii(pFile["name"]) into tName
   put axFileExtension(tName) into tExtn
   if axEndsWithAny(tName, "_meta.xml,_files.xml,_reviews.xml,_meta.sqlite") then
      return false
   end if
   if axContainsAny(tName, "__ia_thumb.") then
      return false
   end if
   if tExtn is "torrent" then
      return false
   end if
   put axLowerAscii(pFile["format"]) into tFormat
   return not axContainsAny(tFormat, "metadata,archive bittorrent,item tile")
end axFileIsContent

function axFileStem pName
   -- Chapter identity shared by an original and its derivatives (the
   -- AudioBooks chapterStem): lower-cased, extension off, then one of the
   -- derivative suffixes _<1-3 digits>kb / _vbr / _orig / _original off.
   local tStem, tI, tCount, tByte, tLen
   put axStripExtension(axLowerAscii(pName)) into tStem
   put the number of chars of tStem into tCount
   if axEndsWithAny(tStem, "_vbr,_orig,_original") then
      repeat with tI = tCount down to 1
         if byteToNum(char tI of tStem) is 95 then
            return char 1 to (tI - 1) of tStem
         end if
      end repeat
   end if
   if axEndsWithAny(tStem, "kb") then
      -- _<1-3 digits>kb
      put 0 into tLen
      repeat with tI = (tCount - 2) down to 1
         put byteToNum(char tI of tStem) into tByte
         if axIsDigitByte(tByte) then
            add 1 to tLen
            if tLen > 3 then
               exit repeat
            end if
         else
            if tByte is 95 then
               if tLen > 0 then
                  return char 1 to (tI - 1) of tStem
               end if
            end if
            exit repeat
         end if
      end repeat
   end if
   return tStem
end axFileStem

function axVideoStem pName
   -- Episode identity across encodes (the film club's normalizeBaseName):
   -- the final extension off, then stacked derivative suffixes stripped
   -- until nothing changes - a video extension, a resolution tag
   -- (_1080p, .720p), one of _archive / _512kb / _h264 / _h.264 / _hd /
   -- _sd - lower-cased and trimmed.
   local tStem, tPrev, tCount, tI, tByte, tRun, tSep
   put axLowerAscii(axStripExtension(pName)) into tStem
   repeat forever
      put tStem into tPrev
      put axStripSuffixAfterDot(tStem, "mp4,m4v,webm,ogv,ogg,avi,mov,mkv,flv,wmv,mpg,mpeg,ia") into tStem
      -- [_.-]\d{3,4}p$
      put the number of chars of tStem into tCount
      if tCount > 4 then
         if byteToNum(char tCount of tStem) is 112 then
            put 0 into tRun
            repeat with tI = (tCount - 1) down to 1
               put byteToNum(char tI of tStem) into tByte
               if axIsDigitByte(tByte) then
                  add 1 to tRun
               else
                  exit repeat
               end if
            end repeat
            if tRun >= 3 then
               if tRun <= 4 then
                  put tCount - tRun - 1 into tI
                  if tI >= 1 then
                     put byteToNum(char tI of tStem) into tSep
                     if axCharIn(numToChar(tSep), "_.-") then
                        put char 1 to (tI - 1) of tStem into tStem
                     end if
                  end if
               end if
            end if
         end if
      end if
      put axStripSuffixAfterSep(tStem, "archive,512kb,h264,h.264,hd,sd") into tStem
      if axStrEq(tStem, tPrev) then
         exit repeat
      end if
   end repeat
   return axTrim(tStem)
end axVideoStem

private function axStripSuffixAfterDot pText, pSuffixes
   -- pText without a trailing ".<suffix>" for the first matching suffix.
   local tSuffix, tLen, tCount
   put the number of chars of pText into tCount
   repeat for each item tSuffix in pSuffixes
      put the number of chars of tSuffix + 1 into tLen
      if tCount <= tLen then
         next repeat
      end if
      if axStrEq(char (tCount - tLen + 1) to tCount of pText, "." & tSuffix) then
         return char 1 to (tCount - tLen) of pText
      end if
   end repeat
   return pText
end axStripSuffixAfterDot

private function axStripSuffixAfterSep pText, pSuffixes
   -- pText without a trailing "<_ . or ->< suffix>" for the first match.
   local tSuffix, tLen, tSep, tCount
   put the number of chars of pText into tCount
   repeat for each item tSuffix in pSuffixes
      put the number of chars of tSuffix + 1 into tLen
      if tCount <= tLen then
         next repeat
      end if
      if axStrEq(char (tCount - tLen + 2) to tCount of pText, tSuffix) then
         put char (tCount - tLen + 1) of pText into tSep
         if axCharIn(tSep, "_.-") then
            return char 1 to (tCount - tLen) of pText
         end if
      end if
   end repeat
   return pText
end axStripSuffixAfterSep

function axPrettyName pName
   -- A readable fallback title from a file name (the AudioBooks
   -- prettifyFileName): the directory off, the extension off, a trailing
   -- _<1-3 digits>kb or _vbr off, underscores to spaces, whitespace
   -- collapsed; the whole name when that leaves nothing.
   local tStem, tI, tCount, tByte, tLen, tOut
   put pName into tStem
   put the number of chars of tStem into tCount
   repeat with tI = tCount down to 1
      if byteToNum(char tI of tStem) is 47 then
         put char (tI + 1) to tCount of tStem into tStem
         exit repeat
      end if
   end repeat
   put axStripExtension(tStem) into tStem
   put axLowerAscii(tStem) into tOut
   put the number of chars of tStem into tCount
   if axEndsWithAny(tOut, "_vbr") then
      put char 1 to (tCount - 4) of tStem into tStem
   else if axEndsWithAny(tOut, "kb") then
      put 0 into tLen
      repeat with tI = (tCount - 2) down to 1
         put byteToNum(char tI of tStem) into tByte
         if axIsDigitByte(tByte) then
            add 1 to tLen
            if tLen > 3 then
               exit repeat
            end if
         else
            if tByte is 95 then
               if tLen > 0 then
                  put char 1 to (tI - 1) of tStem into tStem
               end if
            end if
            exit repeat
         end if
      end repeat
   end if
   put axCollapseSpaces(axBlankChars(tStem, "_")) into tOut
   if tOut is empty then
      return pName
   end if
   return tOut
end axPrettyName

function axTrackTitleClean pTitle
   -- The tape finder's title cleaner: a leading d1t01-style prefix off
   -- (optional "d" + digits, then "t" + digits, then any run of space,
   -- ".", "_" or "-"), case-insensitive; then "_" and "-" to spaces and
   -- the whitespace collapsed. Empty in, empty out.
   local tText, tCount, tI, tByte, tPos, tDigits
   put pTitle into tText
   put the number of chars of tText into tCount
   put 1 into tPos
   -- optional d<digits>
   if tCount >= 2 then
      put byteToNum(char 1 of axLowerAscii(char 1 of tText)) into tByte
      if tByte is 100 then
         put 0 into tDigits
         put 2 into tI
         repeat while tI <= tCount
            if axIsDigitByte(byteToNum(char tI of tText)) then
               add 1 to tDigits
               add 1 to tI
            else
               exit repeat
            end if
         end repeat
         if tDigits > 0 then
            put tI into tPos
         end if
      end if
   end if
   -- required t<digits>
   if tPos <= tCount then
      put byteToNum(char 1 of axLowerAscii(char tPos of tText)) into tByte
      if tByte is 116 then
         put 0 into tDigits
         put tPos + 1 into tI
         repeat while tI <= tCount
            if axIsDigitByte(byteToNum(char tI of tText)) then
               add 1 to tDigits
               add 1 to tI
            else
               exit repeat
            end if
         end repeat
         if tDigits > 0 then
            repeat while tI <= tCount
               put byteToNum(char tI of tText) into tByte
               if axIsSpaceByte(tByte) then
                  add 1 to tI
               else if axCharIn(numToChar(tByte), "._-") then
                  add 1 to tI
               else
                  exit repeat
               end if
            end repeat
            put char tI to tCount of tText into tText
         end if
      end if
   end if
   return axCollapseSpaces(axBlankChars(tText, "_-"))
end axTrackTitleClean

function axCleanTitle pName, pItemTitle
   -- The film club's episode title: extension off; a leading copy of the
   -- item title (compared with everything but letters and digits removed,
   -- lower-cased) dropped; leading and trailing "-", "_" and whitespace
   -- trimmed; "-" and "_" to spaces; whitespace collapsed; "Untitled" when
   -- nothing is left.
   local tTitle, tId, tLower, tLen, tI, tCount, tByte, tChar
   if pName is empty then
      return "Untitled"
   end if
   put axStripExtension(pName) into tTitle
   put empty into tId
   put axLowerAscii(pItemTitle) into tLower
   put the number of chars of tLower into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of tLower) into tByte
      if axIsDigitByte(tByte) then
         put char tI of tLower after tId
      else if tByte >= 97 then
         if tByte <= 122 then
            put char tI of tLower after tId
         end if
      end if
   end repeat
   put the number of chars of tId into tLen
   if tLen > 0 then
      if axLowerAscii(tTitle) begins with tId then
         put char (tLen + 1) to -1 of tTitle into tTitle
      end if
   end if
   -- trim the edges of - _ and whitespace
   put axTrim(axBlankChars(tTitle, "-_")) into tTitle
   put axCollapseSpaces(tTitle) into tTitle
   if tTitle is empty then
      return "Untitled"
   end if
   return tTitle
end axCleanTitle

function axQualityLabel pName
   -- The film club's quality tier from an encode's name: a resolution tag
   -- when the name carries one, then the site's derivative markers, then
   -- "Auto".
   local tLower
   put axLowerAscii(pName) into tLower
   if axContainsAny(tLower, "1080p,1920x1080") then
      return "1080p"
   end if
   if axContainsAny(tLower, "720p,1280x720") then
      return "720p"
   end if
   if axContainsAny(tLower, "480p,854x480") then
      return "480p"
   end if
   if axContainsAny(tLower, "360p,640x360") then
      return "360p"
   end if
   if axContainsAny(tLower, "_h264") then
      return "H.264"
   end if
   if axContainsAny(tLower, "_512kb") then
      return "SD"
   end if
   if axContainsAny(tLower, "_archive") then
      return "Archive"
   end if
   return "Auto"
end axQualityLabel

function axSubjectTags pSubject, pMax
   -- Up to pMax (default 2) short subject tags from a subject field: each
   -- line split again on ";" and "|", trimmed, dropped when empty, twenty
   -- characters or longer, or one of the noise words (librivox, audiobook,
   -- audiobooks, audio, literature), de-duplicated case-insensitively,
   -- first letter upper-cased. The AudioBooks subjectTags.
   local tMax, tCount, tI, tLine, tPieces, tPieceCount, tJ, tTag, tKey, tSeen, tOut, tN
   put pMax into tMax
   if not axIsDigits(tMax) then
      put 2 into tMax
   end if
   put the number of lines of pSubject into tCount
   put empty into tOut
   put 0 into tN
   repeat with tI = 1 to tCount
      put line tI of pSubject into tLine
      replace "|" with ";" in tLine
      put axSplitOn(tLine, ";") into tPieces
      put the number of lines of tPieces into tPieceCount
      repeat with tJ = 1 to tPieceCount
         put axTrim(line tJ of tPieces) into tTag
         if tTag is empty then
            next repeat
         end if
         if the number of chars of tTag >= 20 then
            next repeat
         end if
         put axLowerAscii(tTag) into tKey
         if axHasItem("librivox,audiobook,audiobooks,audio books,audio book,audio,literature", tKey) then
            next repeat
         end if
         if tKey is among the keys of tSeen then
            next repeat
         end if
         put true into tSeen[tKey]
         put axUpperFirst(tTag) & return after tOut
         add 1 to tN
         if tN >= tMax then
            return axChompLine(tOut)
         end if
      end repeat
   end repeat
   return axChompLine(tOut)
end axSubjectTags

private function axSplitOn pText, pChar
   -- pText split at every pChar, one piece per line (the caller turns a
   -- "|" into a ";" first, so pipes and semicolons both split a subject
   -- the way the app's /[;|]/ did).
   local tOut, tI, tCount, tByte, tSplit, tPiece
   put byteToNum(pChar) into tSplit
   put the number of chars of pText into tCount
   put empty into tOut
   put empty into tPiece
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tByte
      if tByte is tSplit then
         put tPiece & return after tOut
         put empty into tPiece
      else
         put char tI of pText after tPiece
      end if
   end repeat
   put tPiece & return after tOut
   return axChompLine(tOut)
end axSplitOn

function axPlaylistKindFor pFamily, pMediatype
   -- Which playlist kind an item wants: the family decides when it is one
   -- of the three apps' worlds; for "any" (or an unknown family) the
   -- item's own mediatype does.
   local tType
   if pFamily is "etree" then
      return "audio-tracks"
   end if
   if pFamily is "librivox" then
      return "audio-chapters"
   end if
   if pFamily is "movies" then
      return "video"
   end if
   put axLowerAscii(axFirst(pMediatype)) into tType
   if tType is "etree" then
      return "audio-tracks"
   end if
   if tType is "audio" then
      return "audio-tracks"
   end if
   if tType is "movies" then
      return "video"
   end if
   if tType is "texts" then
      return "documents"
   end if
   if tType is "image" then
      return "images"
   end if
   return "files"
end axPlaylistKindFor

private function axFileAccepted pFile, pKind
   if pKind is "audio-chapters" then
      return axFileIsAudio(pFile)
   end if
   if pKind is "audio-tracks" then
      return axFileIsAudio(pFile)
   end if
   if pKind is "video" then
      return axFileIsVideo(pFile)
   end if
   if pKind is "documents" then
      return axFileIsDocument(pFile)
   end if
   if pKind is "images" then
      return axFileIsImage(pFile)
   end if
   return axFileIsContent(pFile)
end axFileAccepted

private function axGroupStem pFile, pKind
   -- The group key of a file for a kind: the audio kinds key a derivative
   -- to the ORIGINAL it names (so a derivative whose original is absent
   -- still forms its own chapter), video keys by episode identity, and
   -- documents, images and plain files never group (one entry per file).
   local tSource
   if pKind is "audio-chapters" then
      put axLowerAscii(pFile["source"]) into tSource
      if tSource is "derivative" then
         if pFile["original"] is not empty then
            return axFileStem(pFile["original"])
         end if
      end if
      return axFileStem(pFile["name"])
   end if
   if pKind is "audio-tracks" then
      put axLowerAscii(pFile["source"]) into tSource
      if tSource is "derivative" then
         if pFile["original"] is not empty then
            return axFileStem(pFile["original"])
         end if
      end if
      return axFileStem(pFile["name"])
   end if
   if pKind is "video" then
      return axVideoStem(pFile["name"])
   end if
   -- documents, images and plain files never group: a reader chooses
   -- between the PDF and the EPUB of a book, so both stay listed
   return "file:" & pFile["name"]
end axGroupStem

private function axRankKey pFile, pKind
   -- The sort key that ranks the encodes of one group, lower first:
   -- the rank digit, then the tie-breaker the kind wants (video: bigger
   -- first; everything else: natural name order).
   local tRank, tFormat, tName, tExtn, tSize, tSource
   put axLowerAscii(pFile["format"]) into tFormat
   put axLowerAscii(pFile["name"]) into tName
   put axFileExtension(tName) into tExtn
   put axLowerAscii(pFile["source"]) into tSource
   put 6 into tRank
   if pKind is "audio-chapters" then
      -- original MP3 0, 64k derivative 1, VBR 2, other MP3 3, AAC 4, Ogg 5
      if axContainsAny(tFormat, "mp3") then
         put 3 into tRank
      else if tExtn is "mp3" then
         put 3 into tRank
      end if
      if tRank is 3 then
         if tSource is "original" then
            put 0 into tRank
         else if axContainsAny(tFormat, "64kbps") then
            put 1 into tRank
         else if axContainsAny(tFormat, "vbr") then
            put 2 into tRank
         end if
      else if axHasItem("m4a,m4b", tExtn) then
         put 4 into tRank
      else if axContainsAny(tFormat, "aac") then
         put 4 into tRank
      else if axContainsAny(tFormat, "ogg,vorbis") then
         put 5 into tRank
      else if axHasItem("ogg,oga", tExtn) then
         put 5 into tRank
      end if
   else if pKind is "audio-tracks" then
      -- VBR MP3 0, other MP3 1, 64k MP3 2, Ogg 3, lossless 4, else 5
      put 5 into tRank
      if axContainsAny(tFormat, "mp3") then
         put 1 into tRank
         if axContainsAny(tFormat, "vbr") then
            put 0 into tRank
         else if axContainsAny(tFormat, "64kbps") then
            put 2 into tRank
         else if axContainsAny(tName, "_64kb") then
            put 2 into tRank
         end if
      else if tExtn is "mp3" then
         put 1 into tRank
         if axContainsAny(tName, "_vbr") then
            put 0 into tRank
         else if axContainsAny(tName, "_64kb") then
            put 2 into tRank
         end if
      else if axContainsAny(tFormat, "ogg,vorbis,opus,aac") then
         put 3 into tRank
      else if axHasItem("ogg,oga,opus,m4a", tExtn) then
         put 3 into tRank
      else if axContainsAny(tFormat, "flac,wave") then
         put 4 into tRank
      else if axHasItem("flac,wav", tExtn) then
         put 4 into tRank
      end if
   else if pKind is "video" then
      if tExtn is "mp4" then
         put 0 into tRank
      else
         put 1 into tRank
      end if
   else if pKind is "documents" then
      put 5 into tRank
      if axContainsAny(tFormat, "text pdf") then
         put 0 into tRank
      else if tExtn is "pdf" then
         put 1 into tRank
      else if tExtn is "epub" then
         put 2 into tRank
      else if tExtn is "djvu" then
         put 3 into tRank
      else if tExtn is "txt" then
         put 4 into tRank
      end if
   else if pKind is "images" then
      if tSource is "original" then
         put 0 into tRank
      else
         put 1 into tRank
      end if
   else
      put 0 into tRank
   end if
   if pKind is "video" then
      put pFile["size"] into tSize
      if not axIsDigits(tSize) then
         put 0 into tSize
      end if
      if tSize > 999999999999 then
         put 999999999999 into tSize
      end if
      return tRank & "|" & axPadRun(999999999999 - tSize) & "|" & axBlankChars(axNaturalKey(tName), tab)
   end if
   return tRank & "|" & axBlankChars(axNaturalKey(tName), tab)
end axRankKey

function axPlaylist pItem, pKind
   -- The playable list of an item (an axItemParse array) for a kind:
   --   count        entries
   --   kind         the kind used
   --   entries[i]   name, title, track, length, format, size, url, stem,
   --                index (the file's position in the item), and for
   --                video: quality (the chosen encode's label) and
   --                variants (name|label|size|format lines, best first)
   -- Groups with a track number come first in track order; the rest follow
   -- in natural name order. Empty (with the reason) when the item has no
   -- file of that kind - which is a normal outcome for a text item asked
   -- for audio, so read the reason before reporting it as an error.
   local tKind, tCount, tI, tFile, tStem, tGroupCount, tG, tIndex, tLines
   local tKeys, tKey, tBest, tEntry, tEntries, tJ, tLine, tIdx, tValue
   local tOrder, tOut, tIdentifier, tItemTitle, tN, tTitle, tVariants
   local tSavedDelim, tGroupLines, tGroupStems
   put pKind into tKind
   if tKind is empty then
      put "files" into tKind
   end if
   if tKind is "auto" then
      put axPlaylistKindFor(empty, pItem["metadata"]["mediatype"]) into tKind
   end if
   put pItem["identifier"] into tIdentifier
   put axFirst(pItem["metadata"]["title"]) into tItemTitle
   put pItem["filesCount"] into tCount
   if not axIsDigits(tCount) then
      put 0 into tCount
   end if
   -- pass 1: accept and group
   put 0 into tGroupCount
   repeat with tI = 1 to tCount
      put pItem["files"][tI] into tFile
      if not axFileAccepted(tFile, tKind) then
         next repeat
      end if
      put axGroupStem(tFile, tKind) into tStem
      if tStem is among the keys of tKeys then
         put tKeys[tStem] into tG
      else
         add 1 to tGroupCount
         put tGroupCount into tG
         put tG into tKeys[tStem]
         put tStem into tGroupStems[tG]
      end if
      put axRankKey(tFile, tKind) & tab & tI & return after tGroupLines[tG]
   end repeat
   if tGroupCount is 0 then
      axSetError "axPlaylist: no " & tKind & " file in this item"
      return empty
   end if
   -- pass 2: rank inside each group, derive the entry
   put empty into tOrder
   repeat with tG = 1 to tGroupCount
      put axChompLine(tGroupLines[tG]) into tLines
      sort lines of tLines
      put line 1 of tLines into tLine
      put char (offset(tab, tLine) + 1) to -1 of tLine into tBest
      put tBest + 0 into tBest
      put pItem["files"][tBest] into tFile
      put tFile["name"] into tEntry["name"]
      put tFile["format"] into tEntry["format"]
      put tFile["size"] into tEntry["size"]
      put axDownloadUrl(tIdentifier, tFile["name"]) into tEntry["url"]
      put axDirectUrl(pItem, tFile["name"]) into tEntry["direct"]
      put tGroupStems[tG] into tEntry["stem"]
      put tBest into tEntry["index"]
      put empty into tEntry["title"]
      put empty into tEntry["track"]
      put empty into tEntry["length"]
      put empty into tEntry["quality"]
      put empty into tEntry["variants"]
      put empty into tVariants
      put the number of lines of tLines into tN
      repeat with tJ = 1 to tN
         put line tJ of tLines into tLine
         put char (offset(tab, tLine) + 1) to -1 of tLine into tIdx
         put tIdx + 0 into tIdx
         put pItem["files"][tIdx] into tFile
         if tEntry["title"] is empty then
            put axTrim(axFirst(tFile["title"])) into tTitle
            if tTitle is not empty then
               if tKind is "audio-tracks" then
                  put axTrackTitleClean(tTitle) into tTitle
               end if
               put tTitle into tEntry["title"]
            end if
         end if
         if tEntry["track"] is empty then
            put axTrackNumber(axFirst(tFile["track"])) into tEntry["track"]
         end if
         if tEntry["length"] is empty then
            put axDurationSeconds(axFirst(tFile["length"])) into tEntry["length"]
         end if
         if tKind is "video" then
            put tFile["name"] & "|" & axQualityLabel(tFile["name"]) & "|" & tFile["size"] & "|" & tFile["format"] & return after tVariants
         end if
      end repeat
      if tEntry["title"] is empty then
         put axFallbackTitle(tEntry["name"], tKind, tItemTitle) into tEntry["title"]
      end if
      if tKind is "video" then
         put axQualityLabel(tEntry["name"]) into tEntry["quality"]
         put axChompLine(tVariants) into tEntry["variants"]
      end if
      put tEntry into tEntries[tG]
      -- THE ORDER KEY, by kind. A concert's per-file "track" restarts on
      -- every disc (d1t01, d2t01 ...), so audio-tracks order by natural
      -- NAME alone - the tape finder's strnatcasecmp rule, which the
      -- dNtNN names were made for. Documents order by rank (PDF before
      -- EPUB before DjVu) then name. Everything else puts the entries that
      -- carry a track number first, in track order, then the rest by name.
      if tKind is "audio-tracks" then
         put "1|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder
      else if tKind is "documents" then
         put "1|" & char 1 of line 1 of tLines & "|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder
      else if tEntry["track"] is empty then
         put "1|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder
      else
         put "0|" & axPadRun(tEntry["track"]) & "|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder
      end if
   end repeat
   -- pass 3: the playlist order
   put axChompLine(tOrder) into tOrder
   sort lines of tOrder
   put tKind into tOut["kind"]
   put tGroupCount into tOut["count"]
   repeat with tI = 1 to tGroupCount
      put line tI of tOrder into tLine
      put char (offset(tab, tLine) + 1) to -1 of tLine into tG
      put tEntries[tG + 0] into tOut["entries"][tI]
   end repeat
   return tOut
end axPlaylist

private function axFallbackTitle pName, pKind, pItemTitle
   local tTitle
   if pKind is "audio-tracks" then
      put axTrackTitleClean(axPrettyName(pName)) into tTitle
      if tTitle is empty then
         return axPrettyName(pName)
      end if
      return tTitle
   end if
   if pKind is "video" then
      return axCleanTitle(pName, pItemTitle)
   end if
   return axPrettyName(pName)
end axFallbackTitle

function axPlaylistTable pPlaylist
   -- Tab-separated lines for a table field: number, title, duration
   -- (m:ss or blank), format, size (human), quality for video.
   local tCount, tI, tEntry, tOut, tLine, tLen
   put pPlaylist["count"] into tCount
   if not axIsDigits(tCount) then
      return empty
   end if
   put empty into tOut
   repeat with tI = 1 to tCount
      put pPlaylist["entries"][tI] into tEntry
      put tI & tab & axBlankChars(tEntry["title"], tab) into tLine
      put tEntry["length"] into tLen
      if tLen is a number then
         put tab & axFormatTime(tLen) after tLine
      else
         put tab after tLine
      end if
      put tab & axBlankChars(tEntry["format"], tab) after tLine
      put tab & axFormatBytes(tEntry["size"]) after tLine
      if pPlaylist["kind"] is "video" then
         put tab & tEntry["quality"] after tLine
      end if
      put tLine & return after tOut
   end repeat
   return axChompLine(tOut)
end axPlaylistTable

-- ==========================================================================
-- THE FETCH LAYER. Engine only, from here to the end of the file.
--
-- `put URL x` blocks the one interpreter thread, which on a slow or
-- unreachable host freezes the whole window (the coin-wallet lesson), so
-- every request here is `load URL ... with message "axUrlDone"` and the
-- answer comes back through the message path. What the layer adds over a
-- bare `load URL`, each paid for by one of the shipped apps:
--   CORRELATION   a request is a handle; the reply is matched to it by the
--                 URL the engine hands back, and a reply nobody is waiting
--                 for (a cancelled or timed-out request; the engine cannot
--                 cancel a load) is unloaded and dropped, never applied to
--                 whatever is in flight now.
--   A WATCHDOG    `load URL` has no deadline of its own; a per-request
--                 `send ... in` reports "timeout" and forgets the handle.
--   A BODY CAP    the whole body is read before this layer sees it, so the
--                 cap stops the parse, not the read; it still keeps a
--                 wrong-shaped reply out of a 300 KB parse.
--   UNLOAD ALWAYS the URL cache grows without limit otherwise.
-- The callback contract (default handler onArchive, set by axSetCallback,
-- dispatched to the owner set by axInit, else the topStack):
--   onArchive pHandle, "search", tResult, pTag    an axSearchParse array
--   onArchive pHandle, "item",   tItem,   pTag    an axItemParse array
--   onArchive pHandle, "raw",    tBody,   pTag    the body of axFetchUrl
--   onArchive pHandle, "error",  tReason, pTag    anything that went wrong
-- Exactly one callback per handle. The handler is reached from an ENGINE
-- callback or a timer, so an app that touches its own controls in it pins
-- the defaultStack first (root docs/OXT-ENGINE-NOTES.md 5.3).
--
-- HONESTY (2026-09-15): the refusal paths ran on a real OXT engine in the
-- member harness (zero skips: libURLVersion answered), and the demo made
-- the suite's first live `load URL` to https://archive.org the same day -
-- the request reached the site over https and the callback delivered the
-- site's answer through the "error" kind, which was 400 Bad Request. The
-- one thing that request did that a plain `load URL` does not was replace
-- the Internet library's default headers with a custom User-Agent
-- (libURLSetCustomHTTPHeaders); that is gone, and the next run says
-- whether it was the cause (docs/04-fetch-layer.md, docs/07 item 5).
-- Whether libURL verifies the certificate is still unmeasured (root
-- docs/OXT-ENGINE-NOTES.md 6.8); that it speaks https at all is now
-- observed.
-- ==========================================================================

command axInit pOwner
   -- The object callbacks dispatch to (the long id of a stack or card);
   -- empty means the topStack at delivery time. Resets nothing else, so
   -- an app may call it again to move the callbacks.
   put pOwner into sAxOwner
   if sAxCallback is empty then
      put kAxCallbackDefault into sAxCallback
   end if
   if sAxTimeout is empty then
      put kAxTimeoutDefault into sAxTimeout
   end if
   if sAxMaxBody is empty then
      put kAxMaxBodyDefault into sAxMaxBody
   end if
end axInit

private command axHookStatus
   -- Point the Internet library's status callback at axUrlStatus, once,
   -- so a download can report progress and re-arm its watchdog. The
   -- callback is GLOBAL to libURL (one per process), which is why the
   -- library takes it only when a download starts and gives it back in
   -- axShutdown (axUnhookStatus): a stack that closes while still named
   -- as the target would be sent every later status of every URL in the
   -- process. Every status the library does not recognise is ignored.
   -- `me` is the object whose script holds this handler - the library
   -- stack when it is `start using`d, the carrying stack when it is
   -- embedded - and both define axUrlStatus. Without the Internet library
   -- the setter throws, and a download simply reports no progress.
   local tError
   if sAxStatusHooked is true then
      exit axHookStatus
   end if
   try
      libURLSetStatusCallback "axUrlStatus", the long id of me
      put true into sAxStatusHooked
   catch tError
      put empty into sAxStatusHooked
   end try
end axHookStatus

private command axUnhookStatus
   local tError
   if sAxStatusHooked is not true then
      exit axUnhookStatus
   end if
   try
      libURLSetStatusCallback empty, empty
   catch tError
   end try
   put empty into sAxStatusHooked
end axUnhookStatus

command axSetCallback pHandlerName
   -- The handler dispatched for every outcome (default onArchive). Empty
   -- restores the default.
   if pHandlerName is empty then
      put kAxCallbackDefault into sAxCallback
   else
      put pHandlerName into sAxCallback
   end if
end axSetCallback

command axSetTimeout pSeconds
   -- Seconds before an outstanding request is reported as "timeout" and
   -- forgotten (default 60; the live site took over 30 s on a broad search). A non-number or a value under 1 keeps the
   -- current setting.
   if pSeconds is not a number then
      exit axSetTimeout
   end if
   if pSeconds < 1 then
      exit axSetTimeout
   end if
   put trunc(pSeconds) into sAxTimeout
end axSetTimeout

command axSetMaxBody pBytes
   -- The largest reply this layer will parse (default 16 MB). Under 1024
   -- keeps the current setting.
   if pBytes is not a number then
      exit axSetMaxBody
   end if
   if pBytes < 1024 then
      exit axSetMaxBody
   end if
   put trunc(pBytes) into sAxMaxBody
end axSetMaxBody

function axPending
   -- How many requests are in flight.
   local tCount, tKey
   put 0 into tCount
   if sAxReqs is not an array then
      return 0
   end if
   repeat for each line tKey in the keys of sAxReqs
      if sAxReqs[tKey] is an array then
         add 1 to tCount
      end if
   end repeat
   return tCount
end axPending

private function axCallbackTarget
   if sAxOwner is not empty then
      return sAxOwner
   end if
   return the topStack
end axCallbackTarget

private command axDispatch pHandle, pKind, pArgOne, pTag
   -- Deliver one callback, try-guarded: a throwing app handler must not
   -- take the layer down with it, and a missing handler is a clean miss
   -- (the nostrxt / onionxt dispatch shape).
   local tError
   if sAxCallback is empty then
      put kAxCallbackDefault into sAxCallback
   end if
   try
      dispatch sAxCallback to axCallbackTarget() with pHandle, pKind, pArgOne, pTag
   catch tError
      -- Swallowed on purpose: the app broke, the transport must not.
   end try
end axDispatch

private function axStartRequest pKind, pUrl, pTag
   -- Register a request and start its load. Returns the handle, or empty
   -- with the reason. A URL already in flight is refused rather than
   -- shared: the engine reports one reply per URL and the layer keeps one
   -- record per URL, so two requests for one URL would race for it.
   local tHandle, tError, tReq, tDelay
   if sAxReqNext is empty then
      put 0 into sAxReqNext
   end if
   if sAxTimeout is empty then
      put kAxTimeoutDefault into sAxTimeout
   end if
   if sAxMaxBody is empty then
      put kAxMaxBodyDefault into sAxMaxBody
   end if
   if not axIsHttpUrl(pUrl) then
      axSetError "axFetch: not an http(s) URL: " & pUrl
      return empty
   end if
   if pUrl is among the keys of sAxReqByUrl then
      if sAxReqByUrl[pUrl] is not empty then
         axSetError "axFetch: that URL is already in flight (handle " & sAxReqByUrl[pUrl] & ")"
         return empty
      end if
   end if
   add 1 to sAxReqNext
   put sAxReqNext into tHandle
   put pKind into tReq["kind"]
   put pUrl into tReq["url"]
   put pTag into tReq["tag"]
   put the seconds into tReq["started"]
   put tReq into sAxReqs[tHandle]
   put tHandle into sAxReqByUrl[pUrl]
   -- No custom headers. The first live request (2026-09-15) set a
   -- User-Agent through libURLSetCustomHTTPHeaders and archive.org answered
   -- 400 Bad Request; that setter REPLACES the Internet library's default
   -- header set for every later request, and it was the one thing this
   -- path did that a plain `load URL` does not. The library's defaults are
   -- what every other stack in this suite sends.
   -- nothing of ours is in flight for this URL (checked above), so a load
   -- the library still has running for it is an orphan - a timed-out request's
   -- - and libURL would refuse a second load with "URL is currently loading"
   try
      unload URL pUrl
   catch tError
   end try
   try
      load URL pUrl with message "axUrlDone"
   catch tError
      put empty into sAxReqs[tHandle]
      put empty into sAxReqByUrl[pUrl]
      axSetError "axFetch: load URL failed to start: " & tError
      return empty
   end try
   put sAxTimeout * 1000 into tDelay
   send ("axDeadline" && tHandle) to me in tDelay milliseconds
   return tHandle
end axStartRequest

function axSearch pQuery, pOptions
   -- Start a search. pOptions is an optional array: fields (comma list),
   -- sort (a clause), rows, page, tag (echoed back untouched). Returns the
   -- request handle; the result arrives as onArchive h, "search", tResult,
   -- tag. Empty (with the reason) when the URL cannot be built.
   local tUrl, tFields, tSort, tRows, tPage
   put pOptions["fields"] into tFields
   if tFields is empty then
      put "identifier,title,creator,date,year,mediatype,downloads" into tFields
   end if
   put pOptions["sort"] into tSort
   put pOptions["rows"] into tRows
   put pOptions["page"] into tPage
   put axSearchUrl(pQuery, tFields, tSort, tRows, tPage) into tUrl
   if tUrl is empty then
      return empty
   end if
   return axStartRequest("search", tUrl, pOptions["tag"])
end axSearch

function axFetchItem pIdentifier, pTag
   -- Start a metadata fetch; the item arrives as onArchive h, "item",
   -- tItem, pTag.
   local tUrl
   put axMetadataUrl(pIdentifier) into tUrl
   if tUrl is empty then
      return empty
   end if
   return axStartRequest("item", tUrl, pTag)
end axFetchItem

function axFetchUrl pUrl, pTag
   -- Start a raw fetch of any http(s) URL (a scrape page, a thumbnail, a
   -- small file); the body arrives as onArchive h, "raw", tBody, pTag.
   return axStartRequest("raw", pUrl, pTag)
end axFetchUrl

function axDownload pUrl, pPath, pTag
   -- Start a download of any http(s) URL STRAIGHT TO A FILE, through the
   -- Internet library's libURLDownloadToFile, so the body never sits in
   -- memory and the body cap does not apply (an 18 MB chapter, a 700 MB
   -- film). Progress arrives as onArchive h, "progress", "received,total",
   -- pTag (as often as libURL reports it); the finished file as onArchive
   -- h, "file", pPath, pTag; any failure as "error". The watchdog is a
   -- STALL watchdog here: every progress report re-arms it, so a slow
   -- download that is still moving never times out and a stalled one does
   -- after axSetTimeout seconds of silence. Returns the handle, or empty
   -- with the reason. The folder must exist; the file is overwritten.
   local tHandle, tError, tReq, tDelay
   if sAxReqNext is empty then
      put 0 into sAxReqNext
   end if
   if sAxTimeout is empty then
      put kAxTimeoutDefault into sAxTimeout
   end if
   if not axIsHttpUrl(pUrl) then
      axSetError "axDownload: not an http(s) URL: " & pUrl
      return empty
   end if
   if pPath is empty then
      axSetError "axDownload: no file path to write to"
      return empty
   end if
   if pUrl is among the keys of sAxReqByUrl then
      if sAxReqByUrl[pUrl] is not empty then
         axSetError "axDownload: that URL is already in flight (handle " & sAxReqByUrl[pUrl] & ")"
         return empty
      end if
   end if
   axHookStatus
   add 1 to sAxReqNext
   put sAxReqNext into tHandle
   put "download" into tReq["kind"]
   put pUrl into tReq["url"]
   put pPath into tReq["path"]
   put pTag into tReq["tag"]
   put the seconds into tReq["started"]
   put the seconds into tReq["lastSeen"]
   put tReq into sAxReqs[tHandle]
   put tHandle into sAxReqByUrl[pUrl]
   try
      unload URL pUrl
   catch tError
   end try
   try
      libURLDownloadToFile pUrl, pPath, "axDownloadDone"
   catch tError
      put empty into sAxReqs[tHandle]
      put empty into sAxReqByUrl[pUrl]
      axSetError "axDownload: libURLDownloadToFile failed to start: " & tError
      return empty
   end try
   put sAxTimeout * 1000 into tDelay
   send ("axDeadline" && tHandle) to me in tDelay milliseconds
   return tHandle
end axDownload

command axCancel pHandle
   -- Forget a request and ask the Internet library to drop its load
   -- (`unload URL`, the same cancel axDeadline sends). A reply that
   -- arrives anyway is dropped as a late reply. A stale or unknown handle
   -- is a clean no-op. The unload matters most for a download: a stack
   -- that closes mid-transfer must not leave libURLDownloadToFile writing
   -- the file and then calling back into a closed stack.
   local tUrl, tError
   if sAxReqs[pHandle] is not an array then
      exit axCancel
   end if
   put sAxReqs[pHandle]["url"] into tUrl
   put empty into sAxReqs[pHandle]
   if tUrl is not empty then
      put empty into sAxReqByUrl[tUrl]
      try
         unload URL tUrl
      catch tError
      end try
   end if
end axCancel

command axCancelAll
   local tKey
   if sAxReqs is an array then
      repeat for each line tKey in the keys of sAxReqs
         axCancel tKey
      end repeat
   end if
   put empty into sAxReqs
   put empty into sAxReqByUrl
end axCancelAll

command axShutdown
   -- Forget everything in flight, give the Internet library's status
   -- callback back, and drop the owner. Safe to call twice.
   axCancelAll
   axUnhookStatus
   put empty into sAxOwner
end axShutdown

on axUrlDone pUrl, pStatus
   -- The engine's URL callback: pStatus is "cached" on success and
   -- anything else on failure. The entry is unloaded on EVERY path.
   local tHandle, tReq, tBody, tError, tKind, tTag, tParsed, tDetail, tHeaders
   put empty into tHandle
   if pUrl is among the keys of sAxReqByUrl then
      put sAxReqByUrl[pUrl] into tHandle
   end if
   if tHandle is empty then
      -- nobody is waiting: a cancelled or timed-out request's late reply
      try
         unload URL pUrl
      catch tError
      end try
      exit axUrlDone
   end if
   if sAxReqs[tHandle] is not an array then
      try
         unload URL pUrl
      catch tError
      end try
      put empty into sAxReqByUrl[pUrl]
      exit axUrlDone
   end if
   put sAxReqs[tHandle] into tReq
   put tReq["kind"] into tKind
   put tReq["tag"] into tTag
   -- forget FIRST, tell the app AFTER: the callback runs app code, and an
   -- app that starts the next request from inside it must find the table
   -- clean (the nostrxt teardown ordering)
   put empty into sAxReqs[tHandle]
   put empty into sAxReqByUrl[pUrl]
   if pStatus is not "cached" then
      put empty into tDetail
      try
         put libURLErrorData(pUrl) into tDetail
      catch tError
         put empty into tDetail
      end try
      try
         unload URL pUrl
      catch tError
      end try
      if tDetail is empty then
         put "the URL library said " & pStatus & " for " & pUrl into tDetail
      else
         put "the URL library said " & pStatus & " for " & pUrl & ": " & tDetail into tDetail
      -- the site's response headers travel with the reason (2026-09-15: a
      -- bare "400 Bad Request" said nothing about WHICH server refused, or why)
      put empty into tHeaders
      try
         put libURLLastRHHeaders() into tHeaders
      catch tError
         put empty into tHeaders
      end try
      if tHeaders is not empty then
         replace return with " | " in tHeaders
         put " [headers: " & tHeaders & "]" after tDetail
      end if
      end if
      axDispatch tHandle, "error", tDetail, tTag
      exit axUrlDone
   end if
   put empty into tBody
   try
      put URL pUrl into tBody
   catch tError
      put empty into tBody
   end try
   try
      unload URL pUrl
   catch tError
   end try
   if the number of bytes of tBody > sAxMaxBody then
      axDispatch tHandle, "error", "the reply is larger than " & sAxMaxBody & " bytes, which no answer this layer asked for should be", tTag
      exit axUrlDone
   end if
   if tKind is "search" then
      put axSearchParse(tBody) into tParsed
      if tParsed is empty then
         axDispatch tHandle, "error", axLastError(), tTag
      else
         axDispatch tHandle, "search", tParsed, tTag
      end if
      exit axUrlDone
   end if
   if tKind is "item" then
      put axItemParse(tBody) into tParsed
      if tParsed is empty then
         axDispatch tHandle, "error", axLastError(), tTag
      else
         axDispatch tHandle, "item", tParsed, tTag
      end if
      exit axUrlDone
   end if
   axDispatch tHandle, "raw", tBody, tTag
end axUrlDone

command axDeadline pHandle
   -- The per-request watchdog: a request still in flight when it fires is
   -- reported as a timeout and forgotten, so its eventual reply is dropped.
   -- For a DOWNLOAD it is a stall watchdog: progress seen inside the window
   -- re-arms it for the remainder instead of failing a transfer that is
   -- merely long (an 18 MB chapter at a slow link outlives 60 seconds).
   local tReq, tUrl, tError, tQuiet, tDelay
   if sAxReqs[pHandle] is not an array then
      exit axDeadline
   end if
   put sAxReqs[pHandle] into tReq
   put tReq["url"] into tUrl
   if tReq["kind"] is "download" then
      put the seconds - tReq["lastSeen"] into tQuiet
      if tQuiet < sAxTimeout then
         put (sAxTimeout - tQuiet) * 1000 into tDelay
         if tDelay < 1000 then
            put 1000 into tDelay
         end if
         send ("axDeadline" && pHandle) to me in tDelay milliseconds
         exit axDeadline
      end if
   end if
   put empty into sAxReqs[pHandle]
   if tUrl is not empty then
      put empty into sAxReqByUrl[tUrl]
      -- cancel the library's load as well: left running, the next request
      -- for the same URL is refused by libURL with "URL is currently
      -- loading" (2026-09-15, the live probe after a timed-out search)
      try
         unload URL tUrl
      catch tError
      end try
   end if
   axDispatch pHandle, "error", "timeout after " & sAxTimeout & " seconds: " & tUrl, tReq["tag"]
end axDeadline

private function axDownloadHandleFor pUrl
   -- The download a libURL callback is about: by the URL it hands back,
   -- or - when that spelling is not in the table, which a redirect or a
   -- normalisation inside the library could produce - the ONE download in
   -- flight, if there is exactly one. Empty otherwise.
   local tHandle, tKey, tFound, tCount
   put empty into tHandle
   if pUrl is among the keys of sAxReqByUrl then
      put sAxReqByUrl[pUrl] into tHandle
   end if
   if tHandle is not empty then
      if sAxReqs[tHandle] is an array then
         if sAxReqs[tHandle]["kind"] is "download" then
            return tHandle
         end if
      end if
      return empty
   end if
   put 0 into tCount
   put empty into tFound
   if sAxReqs is an array then
      repeat for each key tKey in sAxReqs
         if sAxReqs[tKey] is an array then
            if sAxReqs[tKey]["kind"] is "download" then
               add 1 to tCount
               put tKey into tFound
            end if
         end if
      end repeat
   end if
   if tCount is 1 then
      return tFound
   end if
   return empty
end axDownloadHandleFor

on axUrlStatus pUrl, pStatus
   -- The Internet library's status callback (registered by axHookStatus,
   -- one per process). A download in this layer's table gets its
   -- "loading,received,total" reports forwarded as the progress kind and
   -- its stall clock reset; every other status, and every URL that is not
   -- a download of ours (the searches load through the same library and
   -- report here too), is ignored.
   local tHandle, tReq
   put axDownloadHandleFor(pUrl) into tHandle
   if tHandle is empty then
      exit axUrlStatus
   end if
   put sAxReqs[tHandle] into tReq
   if item 1 of pStatus is not "loading" then
      exit axUrlStatus
   end if
   put the seconds into sAxReqs[tHandle]["lastSeen"]
   axDispatch tHandle, "progress", item 2 of pStatus & comma & item 3 of pStatus, tReq["tag"]
end axUrlStatus

on axDownloadDone pUrl, pStatus
   -- libURLDownloadToFile's completion callback: pStatus is "downloaded"
   -- when the file is whole, anything else on failure. The file on disk is
   -- the final arbiter either way - a "downloaded" with no file is a
   -- failure, and the app is told which.
   local tHandle, tReq, tPath, tDetail, tError
   put axDownloadHandleFor(pUrl) into tHandle
   if tHandle is empty then
      exit axDownloadDone
   end if
   put sAxReqs[tHandle] into tReq
   put tReq["path"] into tPath
   put empty into sAxReqs[tHandle]
   put empty into sAxReqByUrl[tReq["url"]]
   if pUrl is among the keys of sAxReqByUrl then
      put empty into sAxReqByUrl[pUrl]
   end if
   if pStatus is "downloaded" or pStatus is "cached" then
      if there is a file tPath then
         axDispatch tHandle, "file", tPath, tReq["tag"]
         exit axDownloadDone
      end if
      axDispatch tHandle, "error", "the download reported " & pStatus & " but no file is at " & tPath, tReq["tag"]
      exit axDownloadDone
   end if
   put empty into tDetail
   try
      put libURLErrorData(pUrl) into tDetail
   catch tError
      put empty into tDetail
   end try
   if tDetail is empty then
      put "the download failed: " & pStatus & " for " & pUrl into tDetail
   else
      put "the download failed: " & pStatus & " for " & pUrl & ": " & tDetail into tDetail
   end if
   axDispatch tHandle, "error", tDetail, tReq["tag"]
end axDownloadDone

-- ---- the blocking conveniences ------------------------------------------
-- For the message box and for scripts that have nothing else to do while
-- they wait. Each one BLOCKS the interpreter thread until the site answers
-- or the URL library gives up, so a window that calls one freezes for that
-- long; the asynchronous handlers above are the shape for anything with
-- a user in front of it.

function axGetSync pUrl
   -- The body of an http(s) URL, or empty with the reason. The Internet
   -- library reports a failure through `the result`, and a body can be
   -- legitimately empty, so both are read.
   local tBody, tError, tWhy
   if not axIsHttpUrl(pUrl) then
      axSetError "axGetSync: not an http(s) URL: " & pUrl
      return empty
   end if
   try
      put URL pUrl into tBody
      put the result into tWhy
   catch tError
      axSetError "axGetSync: " & tError
      return empty
   end try
   if tWhy is not empty then
      axSetError "axGetSync: the URL library said " & tWhy & " for " & pUrl
      return empty
   end if
   return tBody
end axGetSync

function axSearchSync pQuery, pOptions
   -- axSearch, blocking: the axSearchParse array, or empty with the reason.
   local tUrl, tFields, tBody
   put pOptions["fields"] into tFields
   if tFields is empty then
      put "identifier,title,creator,date,year,mediatype,downloads" into tFields
   end if
   put axSearchUrl(pQuery, tFields, pOptions["sort"], pOptions["rows"], pOptions["page"]) into tUrl
   if tUrl is empty then
      return empty
   end if
   put axGetSync(tUrl) into tBody
   if tBody is empty then
      return empty
   end if
   return axSearchParse(tBody)
end axSearchSync

function axFetchItemSync pIdentifier
   -- axFetchItem, blocking: the axItemParse array, or empty with the reason.
   local tUrl, tBody
   put axMetadataUrl(pIdentifier) into tUrl
   if tUrl is empty then
      return empty
   end if
   put axGetSync(tUrl) into tBody
   if tBody is empty then
      return empty
   end if
   return axItemParse(tBody)
end axFetchItemSync

function axDownloadSync pUrl, pPath
   -- axDownload, blocking: the whole body of an http(s) URL written to a
   -- file. Returns pPath, or empty with the reason. The body passes
   -- through memory here (it is `put URL x into URL "binfile:..."`), so
   -- this is for the message box and for files a machine can hold.
   local tError, tWhy, tBody
   if not axIsHttpUrl(pUrl) then
      axSetError "axDownloadSync: not an http(s) URL: " & pUrl
      return empty
   end if
   if pPath is empty then
      axSetError "axDownloadSync: no file path to write to"
      return empty
   end if
   -- GET first and judge it, THEN write: `put URL x into URL "binfile:.."`
   -- in one statement writes whatever the GET produced - an empty body on
   -- a failed request - and the file write is what sets `the result` last,
   -- so a failed download would come back as a 0-byte success.
   try
      put URL pUrl into tBody
      put the result into tWhy
   catch tError
      axSetError "axDownloadSync: " & tError
      return empty
   end try
   if tWhy is not empty then
      axSetError "axDownloadSync: the URL library said " & tWhy & " for " & pUrl
      return empty
   end if
   if tBody is empty then
      axSetError "axDownloadSync: the site answered with an empty body for " & pUrl
      return empty
   end if
   try
      put tBody into URL ("binfile:" & pPath)
      put the result into tWhy
   catch tError
      axSetError "axDownloadSync: could not write " & pPath & ": " & tError
      return empty
   end try
   if tWhy is not empty then
      axSetError "axDownloadSync: could not write " & pPath & ": " & tWhy
      return empty
   end if
   if there is not a file pPath then
      axSetError "axDownloadSync: nothing was written to " & pPath
      return empty
   end if
   return pPath
end axDownloadSync

-- ---- archivext/examples/archivext-tests.livecodescript ----
-- archivext-tests.livecodescript - the ArchiveXT member self-test.
--
-- One OFFLINE, deterministic harness for the whole ax* surface: the pure
-- layer against the pinned vectors and the synthetic fixtures, and the
-- fetch layer's refusal paths (no request is ever started - every fetch
-- handler is driven with an input it must refuse). It runs three ways and
-- behaves identically in each: standalone beside the library (`start
-- using stack "archivext"`), embedded in the demo (which carries library
-- and harness between sync-demo-embeds sentinels), and folded into the
-- suite paste (tests/suite-selftest.livecodescript, prefix ax1).
--
-- STATUS: verified statically; needs an OXT pass. Every pinned constant
-- below is DERIVED by tools/archive-kat.py from tools/archive_reference.py
-- (the independent oracle, anchored at import to the three source apps'
-- own test vectors) and the fixtures under tests/fixtures/, and
-- tools/check-selftest-vectors.py re-derives each one BY NAME on every
-- build - never hand-edit a vector here; edit the fixture or the oracle
-- and re-paste. The fixtures are SYNTHETIC (archive.org is unreachable
-- from the build sandbox), so a green run here says the script agrees
-- with the oracle about those bytes, not that the live site still answers
-- in that shape.
--
-- Entry point: axSelfTest() - a FUNCTION returning the report. The first
-- line honours the suite's summary-line contract, "N passed, M failed, K
-- skipped" (every word a number or passed/failed/skipped, exactly one such
-- line per report); the suite core parses it via stMergeReturned.
--
-- SKIP is a counted outcome, used for exactly one thing here: the
-- Internet-library probe, whose answer is an environment fact (a build
-- without libURL is not a defect in this member).
--
-- Deliberately NO live network anywhere: a synchronous harness cannot
-- await an async callback without blocking the interpreter thread, and
-- the live legs live in the demo and the runbook.

-- ==========================================================================
-- Pinned vectors - GENERATED by `python3 tools/archive-kat.py`, re-derived
-- by name by tools/check-selftest-vectors.py. Values that carry a double
-- quote, a line break or a non-ASCII byte are pinned as the hex of their
-- UTF-8 bytes (an xTalk literal has no escapes) and decoded by axtHex.
-- ==========================================================================

-- >>> KAT CONSTANTS BEGIN >>>
constant kAxVecFixLibrivoxSearchHex = "7b0a2022726573706f6e7365486561646572223a207b0a202022737461747573223a20302c0a2020225154696d65223a2031322c0a202022706172616d73223a207b0a202020227175657279223a2022636f6c6c656374696f6e3a286c69627269766f78617564696f29222c0a20202022726f7773223a202235222c0a202020227374617274223a20300a20207d0a207d2c0a2022726573706f6e7365223a207b0a2020226e756d466f756e64223a2036302c0a2020227374617274223a20302c0a202022646f6373223a205b0a2020207b0a20202020226964656e746966696572223a202270726964655f7072656a75646963655f74657374222c0a20202020227469746c65223a2022507269646520616e64205c225072656a75646963655c222026204f7468657273222c0a202020202263726561746f72223a205b0a2020202020224a616e652041757374656e222c0a2020202020224b6172656e20536176616765220a202020205d2c0a202020202279656172223a202232303036222c0a202020202264617465223a2022323030362d30312d30325430303a30303a30305a222c0a20202020226c616e6775616765223a205b0a202020202022456e676c697368222c0a2020202020224672656e6368220a202020205d2c0a202020202272756e74696d65223a2022313a31323a3334222c0a20202020227375626a656374223a205b0a202020202022526f6d616e6365222c0a202020202022417564696f626f6f6b222c0a202020202022412076657279206c6f6e67207375626a656374206e616d6520746861742065786365656473207477656e74792063686172616374657273220a202020205d0a2020207d2c0a2020207b0a20202020226964656e746966696572223a2022626f6f6b5f32222c0a20202020227469746c65223a20224576696c203c696d67207372633d78206f6e6572726f723d5c2277696e646f772e5f5f7873735469746c653d315c223e20426f6f6b222c0a202020202263726561746f72223a20224d616c6c6f7279203c623e426f6c643c2f623e222c0a202020202279656172223a202232303037222c0a202020202264617465223a2022323030372d30312d30335430303a30303a30305a222c0a20202020226c616e6775616765223a2022456e676c697368222c0a202020202272756e74696d65223a2022323a31323a3334222c0a20202020227375626a656374223a205b0a20202020202246696374696f6e5c223e3c696d67207372633d78206f6e6572726f723d5c2277696e646f772e5f5f7873735375626a6563743d315c223e220a202020205d0a2020207d2c0a2020207b0a20202020226964656e746966696572223a2022626f6f6b5f33222c0a20202020227469746c65223a2022426f6f6b2033222c0a20202020226c616e6775616765223a2022456e676c697368222c0a20202020227375626a656374223a202273696e676c6520737472696e67207375626a656374220a2020207d2c0a2020207b0a20202020226964656e746966696572223a2022626f6f6b5f34222c0a20202020227469746c65223a2022426f6f6b2034222c0a202020202263726561746f72223a2022417574686f722034222c0a202020202279656172223a202232303039222c0a202020202264617465223a2022323030392d30312d30355430303a30303a30305a222c0a20202020226c616e6775616765223a2022456e676c697368222c0a202020202272756e74696d65223a2022343a31323a3334222c0a20202020227375626a656374223a205b0a202020202022506f65747279222c0a202020202022417564696f626f6f6b222c0a202020202022412076657279206c6f6e67207375626a656374206e616d6520746861742065786365656473207477656e74792063686172616374657273220a202020205d0a2020207d2c0a2020207b0a20202020226964656e746966696572223a2022626f6f6b5f35222c0a20202020227469746c65223a2022426f6f6b2035222c0a202020202263726561746f72223a2022417574686f722035222c0a202020202279656172223a202232303130222c0a202020202264617465223a2022323031302d30312d30365430303a30303a30305a222c0a20202020226c616e6775616765223a2022456e676c697368222c0a202020202272756e74696d65223a2022353a31323a3334222c0a20202020227375626a656374223a205b0a202020202022536369656e63652066696374696f6e222c0a202020202022417564696f626f6f6b222c0a202020202022412076657279206c6f6e67207375626a656374206e616d6520746861742065786365656473207477656e74792063686172616374657273220a202020205d0a2020207d0a20205d0a207d0a7d0a"
constant kAxVecFixLibrivoxItemHex = "7b0a202263726561746564223a20313730303030303030302c0a20226431223a202269613830303030302e75732e617263686976652e6f7267222c0a2022646972223a20222f312f6974656d732f70726964655f7072656a75646963655f74657374222c0a202266696c6573223a205b0a20207b0a202020226e616d65223a202270705f30335f61757374656e5f36346b622e6d7033222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a20223033202d20436861707465722033203c623e626f6c643c2f623e2026205c2271756f7465645c22222c0a20202022747261636b223a202233222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234383030303030222c0a202020226d6435223a20223030303030303030303030303030303030303030303030303030303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30335f61757374656e2e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30335f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30335f61757374656e5f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30335f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30335f61757374656e2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30335f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022504e47222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30335f61757374656e2e6166706b222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30335f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022436f6c756d626961205065616b73222c0a2020202273697a65223a202231303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30315f61757374656e5f36346b622e6d7033222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a20223031202d20436861707465722031222c0a20202022747261636b223a202231222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234383030303030222c0a202020226d6435223a20223030303030303030303030303030303030303030303030303030303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30315f61757374656e2e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30315f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30315f61757374656e5f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30315f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30315f61757374656e2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30315f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022504e47222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30315f61757374656e2e6166706b222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30315f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022436f6c756d626961205065616b73222c0a2020202273697a65223a202231303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20223132384b627073204d5033222c0a202020227469746c65223a20223035202d20436861707465722035222c0a20202022747261636b223a202235222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202239363030303030222c0a202020226d6435223a20223030303030303030303030303030303030303030303030303030303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e5f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234383030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e2e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e5f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a2022504e47222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30355f61757374656e2e6166706b222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30355f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a2022436f6c756d626961205065616b73222c0a2020202273697a65223a202231303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30325f61757374656e5f36346b622e6d7033222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a20223032202d20436861707465722032222c0a20202022747261636b223a202232222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234383030303030222c0a202020226d6435223a20223030303030303030303030303030303030303030303030303030303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30325f61757374656e2e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30325f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30325f61757374656e5f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30325f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30325f61757374656e2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30325f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022504e47222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30325f61757374656e2e6166706b222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30325f61757374656e5f36346b622e6d7033222c0a20202022666f726d6174223a2022436f6c756d626961205065616b73222c0a2020202273697a65223a202231303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20223132384b627073204d5033222c0a202020227469746c65223a20223034202d20436861707465722034222c0a20202022747261636b223a2022342f35222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202239363030303030222c0a202020226d6435223a20223030303030303030303030303030303030303030303030303030303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e5f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234383030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e2e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020226c656e677468223a20223630302e3132222c0a2020202273697a65223a202234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e5f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a2022504e47222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202270705f30345f61757374656e2e6166706b222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202270705f30345f61757374656e5f3132386b622e6d7033222c0a20202022666f726d6174223a2022436f6c756d626961205065616b73222c0a2020202273697a65223a202231303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f6d6574612e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202232303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f66696c65732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202232303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f726576696577732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a2022323030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f617263686976652e746f7272656e74222c0a20202022736f75726365223a20226d65746164617461222c0a20202022666f726d6174223a20224172636869766520426974546f7272656e74222c0a2020202273697a65223a202235303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f36346b622e6d3375222c0a20202022736f75726365223a202264657269766174697665222c0a20202022666f726d6174223a202236344b627073204d3355222c0a2020202273697a65223a2022333030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f36346b625f6d70332e7a6970222c0a20202022736f75726365223a202264657269766174697665222c0a20202022666f726d6174223a202236344b627073204d5033205a4950222c0a2020202273697a65223a20223234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573745f7662725f6d70332e7a6970222c0a20202022736f75726365223a202264657269766174697665222c0a20202022666f726d6174223a2022564252204d5033205a4950222c0a2020202273697a65223a20223234303030303030220a20207d2c0a20207b0a202020226e616d65223a202270726964655f7072656a75646963655f746573742e6a7067222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224a504547222c0a2020202273697a65223a20223530303030220a20207d2c0a20207b0a202020226e616d65223a20225f5f69615f7468756d622e6a7067222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224974656d2054696c65222c0a2020202273697a65223a202235303030220a20207d0a205d2c0a202266696c65735f636f756e74223a2033362c0a20226974656d5f73697a65223a203130303030303030302c0a20226d65746164617461223a207b0a2020226964656e746966696572223a202270726964655f7072656a75646963655f74657374222c0a2020227469746c65223a2022507269646520616e64205072656a7564696365222c0a20202263726561746f72223a205b0a202020224a616e652041757374656e222c0a202020224b6172656e20536176616765220a20205d2c0a202022726561646572223a20224b6172656e20536176616765222c0a2020226465736372697074696f6e223a20223c703e507269646520616e64205072656a75646963652069732061206e6f76656c206279203c623e4a616e652041757374656e3c2f623e2e2052656164206d6f7265206174203c6120687265663d5c2268747470733a2f2f6c69627269766f782e6f72672f70726964652d616e642d7072656a75646963655c223e4c69627269566f783c2f613e2e2053756d6d6172792062792057696b6970656469612e3c2f703e222c0a2020226e6f746573223a20224e6f74652077697468203c693e6d61726b75703c2f693e20616e64205c2271756f7465735c22222c0a2020226c616e6775616765223a205b0a20202022456e676c697368222c0a202020224672656e6368220a20205d2c0a20202264617465223a2022323031302d30352d3033222c0a20202279656172223a202232303130222c0a20202272756e74696d65223a202231313a33353a3232222c0a2020227375626a656374223a205b0a2020202246696374696f6e222c0a20202022526f6d616e6365222c0a202020226c69627269766f78222c0a20202022617564696f626f6f6b220a20205d2c0a2020226c6963656e736575726c223a2022687474703a2f2f6372656174697665636f6d6d6f6e732e6f72672f7075626c6963646f6d61696e2f7a65726f2f312e302f222c0a2020226d6564696174797065223a2022617564696f222c0a202022636f6c6c656374696f6e223a205b0a202020226c69627269766f78617564696f222c0a202020226c69627269766f78220a20205d0a207d2c0a2022736572766572223a202269613830303030302e75732e617263686976652e6f7267222c0a2022756e6971223a20312c0a2022776f726b61626c655f73657276657273223a205b0a20202269613830303030302e75732e617263686976652e6f7267220a205d0a7d0a"
constant kAxVecFixEtreeSearchHex = "7b0a2022726573706f6e7365486561646572223a207b0a202022737461747573223a20302c0a2020225154696d65223a2033302c0a202022706172616d73223a207b0a202020227175657279223a2022636f6c6c656374696f6e3a28477261746566756c446561642920414e44206d65646961747970653a2865747265652920414e4420796561723a5b3139373720544f20313937375d222c0a20202022726f7773223a202233222c0a202020227374617274223a20300a20207d0a207d2c0a2022726573706f6e7365223a207b0a2020226e756d466f756e64223a203231342c0a2020227374617274223a20302c0a202022646f6373223a205b0a2020207b0a20202020226964656e746966696572223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e66222c0a20202020227469746c65223a2022477261746566756c2044656164204c69766520617420426172746f6e2048616c6c2c20436f726e656c6c20556e6976657273697479206f6e20313937372d30352d3038222c0a202020202263726561746f72223a2022477261746566756c2044656164222c0a202020202264617465223a2022313937372d30352d30385430303a30303a30305a222c0a202020202279656172223a20313937372c0a202020202276656e7565223a2022426172746f6e2048616c6c2c20436f726e656c6c20556e6976657273697479222c0a2020202022636f766572616765223a20224974686163612c204e59222c0a2020202022736f75726365223a2022536f756e64626f617264222c0a20202020226176675f726174696e67223a20342e382c0a2020202022646f776e6c6f616473223a20313233343536370a2020207d2c0a2020207b0a20202020226964656e746966696572223a2022676437372d30352d30372e6175642e7665726e6f6e2e31323334352e7362656f6b2e666c61633136222c0a20202020227469746c65223a2022477261746566756c2044656164204c69766520617420426f73746f6e2047617264656e206f6e20313937372d30352d3037222c0a202020202263726561746f72223a205b0a202020202022477261746566756c2044656164220a202020205d2c0a202020202264617465223a2022313937372d30352d30375430303a30303a30305a222c0a202020202279656172223a202231393737222c0a202020202276656e7565223a2022426f73746f6e2047617264656e222c0a2020202022636f766572616765223a2022426f73746f6e2c204d41222c0a2020202022736f75726365223a202241756469656e6365222c0a20202020226176675f726174696e67223a2022342e3230222c0a2020202022646f776e6c6f616473223a20223534333231220a2020207d2c0a2020207b0a20202020226964656e746966696572223a20226764313937372d30352d30392e6d74782e7365616d6f6e732e33313839332e666c61633136222c0a20202020227469746c65223a2022477261746566756c2044656164204c69766520617420576172204d656d6f7269616c2041756469746f7269756d206f6e20313937372d30352d3039222c0a202020202263726561746f72223a2022477261746566756c2044656164222c0a202020202264617465223a2022313937372d30352d30395430303a30303a30305a222c0a202020202279656172223a20313937372c0a2020202022736f75726365223a20224d6174726978222c0a2020202022646f776e6c6f616473223a20393837360a2020207d0a20205d0a207d0a7d0a"
constant kAxVecFixEtreeItemHex = "7b0a202263726561746564223a20313730303030303030312c0a20226431223a202269613830303330302e75732e617263686976652e6f7267222c0a2022646972223a20222f31322f6974656d732f6764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e66222c0a202266696c6573223a205b0a20207b0a202020226e616d65223a2022676437372d30352d303864317430312e666c6163222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c6163222c0a202020227469746c65223a2022536361726c6574204265676f6e696173222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a20223338322e3335222c0a2020202273697a65223a20223435303030303030222c0a202020226d6435223a20223131313131313131313131313131313131313131313131313131313131313131220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430315f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430312e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020227469746c65223a2022536361726c6574204265676f6e696173222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a20223338322e3335222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430315f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430312e666c6163222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a2022536361726c6574204265676f6e696173222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a20223338322e3335222c0a2020202273697a65223a202233303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430312e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430312e666c6163222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020227469746c65223a2022536361726c6574204265676f6e696173222c0a202020226c656e677468223a20223338322e3335222c0a2020202273697a65223a202236303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430315f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430312e666c6163222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223430303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430322e666c6163222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c6163222c0a202020227469746c65223a202246697265204f6e20546865204d6f756e7461696e222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a202231303a3135222c0a2020202273697a65223a20223435303030303030222c0a202020226d6435223a20223131313131313131313131313131313131313131313131313131313131313131220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430325f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430322e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020227469746c65223a202246697265204f6e20546865204d6f756e7461696e222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a202231303a3135222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430325f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430322e666c6163222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a202246697265204f6e20546865204d6f756e7461696e222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a202231303a3135222c0a2020202273697a65223a202233303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430322e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430322e666c6163222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020227469746c65223a202246697265204f6e20546865204d6f756e7461696e222c0a202020226c656e677468223a202231303a3135222c0a2020202273697a65223a202236303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317430325f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317430322e666c6163222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223430303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317431302e666c6163222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c6163222c0a202020227469746c65223a202244616e63696e6720496e2054686520537472656574222c0a20202022747261636b223a20223130222c0a202020226c656e677468223a2022313a30333a3435222c0a2020202273697a65223a20223435303030303030222c0a202020226d6435223a20223131313131313131313131313131313131313131313131313131313131313131220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317431305f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317431302e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020227469746c65223a202244616e63696e6720496e2054686520537472656574222c0a20202022747261636b223a20223130222c0a202020226c656e677468223a2022313a30333a3435222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317431305f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317431302e666c6163222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a202244616e63696e6720496e2054686520537472656574222c0a20202022747261636b223a20223130222c0a202020226c656e677468223a2022313a30333a3435222c0a2020202273697a65223a202233303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317431302e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317431302e666c6163222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020227469746c65223a202244616e63696e6720496e2054686520537472656574222c0a202020226c656e677468223a2022313a30333a3435222c0a2020202273697a65223a202236303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864317431305f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864317431302e666c6163222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223430303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430312e666c6163222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c6163222c0a202020227469746c65223a20224e6f7420466164652041776179222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a202231323a3037222c0a2020202273697a65223a20223435303030303030222c0a202020226d6435223a20223131313131313131313131313131313131313131313131313131313131313131220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430315f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430312e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020227469746c65223a20224e6f7420466164652041776179222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a202231323a3037222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430315f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430312e666c6163222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a20224e6f7420466164652041776179222c0a20202022747261636b223a20223031222c0a202020226c656e677468223a202231323a3037222c0a2020202273697a65223a202233303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430312e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430312e666c6163222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020227469746c65223a20224e6f7420466164652041776179222c0a202020226c656e677468223a202231323a3037222c0a2020202273697a65223a202236303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430315f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430312e666c6163222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223430303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430322e666c6163222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c6163222c0a202020227469746c65223a20224d6f726e696e6720446577222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a20223734322e3530222c0a2020202273697a65223a20223435303030303030222c0a202020226d6435223a20223131313131313131313131313131313131313131313131313131313131313131220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430325f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430322e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020227469746c65223a20224d6f726e696e6720446577222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a20223734322e3530222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430325f36346b622e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430322e666c6163222c0a20202022666f726d6174223a202236344b627073204d5033222c0a202020227469746c65223a20224d6f726e696e6720446577222c0a20202022747261636b223a20223032222c0a202020226c656e677468223a20223734322e3530222c0a2020202273697a65223a202233303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430322e6f6767222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430322e666c6163222c0a20202022666f726d6174223a20224f676720566f72626973222c0a202020227469746c65223a20224d6f726e696e6720446577222c0a202020226c656e677468223a20223734322e3530222c0a2020202273697a65223a202236303030303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430325f7370656374726f6772616d2e706e67222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430322e666c6163222c0a20202022666f726d6174223a20225370656374726f6772616d222c0a2020202273697a65223a20223430303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d303864327430395f7662722e6d7033222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a2022676437372d30352d303864327430392e666c6163222c0a20202022666f726d6174223a2022564252204d5033222c0a202020226c656e677468223a202230353a3535222c0a2020202273697a65223a202238303030303030220a20207d2c0a20207b0a202020226e616d65223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e665f6d6574612e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202233303030220a20207d2c0a20207b0a202020226e616d65223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e665f66696c65732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202236303030220a20207d2c0a20207b0a202020226e616d65223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e665f726576696577732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202239303030220a20207d2c0a20207b0a202020226e616d65223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e665f617263686976652e746f7272656e74222c0a20202022736f75726365223a20226d65746164617461222c0a20202022666f726d6174223a20224172636869766520426974546f7272656e74222c0a2020202273697a65223a20223132303030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e662e6d6435222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022436865636b73756d73222c0a2020202273697a65223a2022353030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e662e747874222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a202254657874222c0a2020202273697a65223a202232353030220a20207d2c0a20207b0a202020226e616d65223a2022676437372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e662e666670222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022466c61632046696e6765725072696e74222c0a2020202273697a65223a2022383030220a20207d2c0a20207b0a202020226e616d65223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e665f7662722e6d3375222c0a20202022736f75726365223a202264657269766174697665222c0a20202022666f726d6174223a2022564252204d3355222c0a2020202273697a65223a2022343030220a20207d0a205d2c0a202266696c65735f636f756e74223a2033342c0a20226974656d5f73697a65223a203335303030303030302c0a20226d65746164617461223a207b0a2020226964656e746966696572223a20226764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e66222c0a2020227469746c65223a2022477261746566756c2044656164204c69766520617420426172746f6e2048616c6c2c20436f726e656c6c20556e6976657273697479206f6e20313937372d30352d3038222c0a20202263726561746f72223a2022477261746566756c2044656164222c0a2020226d6564696174797065223a20226574726565222c0a202022636f6c6c656374696f6e223a205b0a20202022477261746566756c44656164222c0a202020226574726565220a20205d2c0a20202264617465223a2022313937372d30352d3038222c0a20202279656172223a202231393737222c0a20202276656e7565223a2022426172746f6e2048616c6c2c20436f726e656c6c20556e6976657273697479222c0a202022636f766572616765223a20224974686163612c204e59222c0a202022736f75726365223a2022536f756e64626f6172643a2042657474792043616e746f72204d6173746572205265656c73222c0a2020226c696e65616765223a2022426574747920426f61726473203e204361737365747465203e20444154203e204344203e20454143203e20464c4143222c0a2020227461706572223a202242657474792043616e746f72222c0a2020227472616e736665726572223a2022436861726c6965204d696c6c6572222c0a2020226465736372697074696f6e223a202253657420313a20536361726c6574204265676f6e6961732c2046697265204f6e20546865204d6f756e7461696e202e2e2e2053657420323a204e6f74204661646520417761792c204d6f726e696e6720446577222c0a2020226e6f746573223a205b0a2020202244697363203120697320736574206f6e652e222c0a20202022446973632032206973207365742074776f2e220a20205d2c0a2020227365746c697374223a205b0a202020225365742031222c0a20202022536361726c6574204265676f6e696173222c0a2020202246697265204f6e20546865204d6f756e7461696e222c0a202020225365742032222c0a202020224e6f7420466164652041776179222c0a202020224d6f726e696e6720446577220a20205d2c0a202022646f776e6c6f616473223a202231323334353637222c0a2020226176675f726174696e67223a2022342e38222c0a2020226e756d5f72657669657773223a2022333132222c0a2020226c6963656e736575726c223a2022687474703a2f2f6372656174697665636f6d6d6f6e732e6f72672f6c6963656e7365732f62792d6e632d6e642f322e302f220a207d2c0a2022736572766572223a202269613830303330302e75732e617263686976652e6f7267222c0a2022756e6971223a20322c0a2022776f726b61626c655f73657276657273223a205b0a20202269613830303330302e75732e617263686976652e6f7267220a205d0a7d0a"
constant kAxVecFixMoviesSearchHex = "7b0a2022726573706f6e7365486561646572223a207b0a202022737461747573223a20302c0a2020225154696d65223a2032302c0a202022706172616d73223a207b0a202020227175657279223a2022286d65646961747970653a286d6f76696573204f5220766964656f204f522074656c65766973696f6e29202e2e2e29222c0a20202022726f7773223a202233222c0a202020227374617274223a20300a20207d0a207d2c0a2022726573706f6e7365223a207b0a2020226e756d466f756e64223a20343032312c0a2020227374617274223a20302c0a202022646f6373223a205b0a2020207b0a20202020226964656e746966696572223a20226e696768745f6f665f7468655f6c6976696e675f64656164222c0a20202020227469746c65223a20224e69676874206f6620746865204c6976696e672044656164222c0a202020202263726561746f72223a202247656f72676520412e20526f6d65726f222c0a20202020226465736372697074696f6e223a20225075626c696320646f6d61696e20686f72726f7220636c61737369632e222c0a202020202264617465223a2022313936382d31302d30315430303a30303a30305a222c0a2020202022646f776e6c6f616473223a203938373635342c0a202020202272756e74696d65223a2022313a33353a3030222c0a20202020226c6963656e736575726c223a2022687474703a2f2f6372656174697665636f6d6d6f6e732e6f72672f7075626c6963646f6d61696e2f6d61726b2f312e302f222c0a20202020227375626a656374223a205b0a202020202022486f72726f72222c0a2020202020225a6f6d62696573222c0a2020202020225075626c696320446f6d61696e220a202020205d2c0a20202020226d6564696174797065223a20226d6f76696573220a2020207d2c0a2020207b0a20202020226964656e746966696572223a20227072656c696e676572222c0a20202020227469746c65223a20225072656c696e676572204172636869766573222c0a20202020226465736372697074696f6e223a2022457068656d6572616c2066696c6d732e222c0a20202020226d6564696174797065223a2022636f6c6c656374696f6e222c0a20202020226e756d5f6974656d73223a20383030302c0a2020202022646f776e6c6f616473223a20350a2020207d2c0a2020207b0a20202020226964656e746966696572223a202253686f775f5365726965735f31393535222c0a20202020227469746c65223a202253686f77222c0a202020202263726561746f72223a202253747564696f222c0a202020202264617465223a2022313935352d30312d3031222c0a2020202022646f776e6c6f616473223a2034322c0a20202020226d6564696174797065223a20226d6f76696573222c0a20202020227375626a656374223a202274657374220a2020207d0a20205d0a207d0a7d0a"
constant kAxVecFixMoviesItemHex = "7b0a202263726561746564223a20313730303030303030322c0a20226431223a202269613830303230302e75732e617263686976652e6f7267222c0a2022646972223a20222f352f6974656d732f53686f775f5365726965735f31393535222c0a202266696c6573223a205b0a20207b0a202020226e616d65223a202253686f775f4530315f3531326b622e6d7034222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530312e6d7034222c0a20202022666f726d6174223a20223531324b62204d50454734222c0a2020202273697a65223a20223230303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530312e6d7034222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022682e323634222c0a2020202273697a65223a20223830303030303030222c0a202020226c656e677468223a2022363030222c0a202020226d6435223a20223232323232323232323232323232323232323232323232323232323232323232220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530312e6f6776222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530312e6d7034222c0a20202022666f726d6174223a20224f676720566964656f222c0a2020202273697a65223a20223330303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530312e676966222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530312e6d7034222c0a20202022666f726d6174223a2022416e696d6174656420474946222c0a2020202273697a65223a2022393030303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530312e7468756d62732f53686f775f4530315f3030303030312e6a7067222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530312e6d7034222c0a20202022666f726d6174223a20225468756d626e61696c222c0a2020202273697a65223a202235303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530325f3531326b622e6d7034222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530322e6d7034222c0a20202022666f726d6174223a20223531324b62204d50454734222c0a2020202273697a65223a20223230303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530322e6d7034222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022682e323634222c0a2020202273697a65223a20223830303030303030222c0a202020226c656e677468223a2022363030222c0a202020226d6435223a20223232323232323232323232323232323232323232323232323232323232323232220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530322e6f6776222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530322e6d7034222c0a20202022666f726d6174223a20224f676720566964656f222c0a2020202273697a65223a20223330303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530322e676966222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530322e6d7034222c0a20202022666f726d6174223a2022416e696d6174656420474946222c0a2020202273697a65223a2022393030303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530322e7468756d62732f53686f775f4530325f3030303030312e6a7067222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530322e6d7034222c0a20202022666f726d6174223a20225468756d626e61696c222c0a2020202273697a65223a202235303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530335f3531326b622e6d7034222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530332e6d7034222c0a20202022666f726d6174223a20223531324b62204d50454734222c0a2020202273697a65223a20223230303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530332e6d7034222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022682e323634222c0a2020202273697a65223a20223830303030303030222c0a202020226c656e677468223a2022363030222c0a202020226d6435223a20223232323232323232323232323232323232323232323232323232323232323232220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530332e6f6776222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530332e6d7034222c0a20202022666f726d6174223a20224f676720566964656f222c0a2020202273697a65223a20223330303030303030222c0a202020226c656e677468223a2022363030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530332e676966222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530332e6d7034222c0a20202022666f726d6174223a2022416e696d6174656420474946222c0a2020202273697a65223a2022393030303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530332e7468756d62732f53686f775f4530335f3030303030312e6a7067222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530332e6d7034222c0a20202022666f726d6174223a20225468756d626e61696c222c0a2020202273697a65223a202235303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f5365726965735f313935355f6d6574612e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202231323030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f5365726965735f313935355f66696c65732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202234303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f5365726965735f313935355f617263686976652e746f7272656e74222c0a20202022736f75726365223a20226d65746164617461222c0a20202022666f726d6174223a20224172636869766520426974546f7272656e74222c0a2020202273697a65223a202238303030220a20207d2c0a20207b0a202020226e616d65223a20225f5f69615f7468756d622e6a7067222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224974656d2054696c65222c0a2020202273697a65223a202239303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530312e656e2e767474222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022576562565454222c0a2020202273697a65223a20223230303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f6d616e69666573742e6a736f6e222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224a534f4e222c0a2020202273697a65223a2022323030303030220a20207d2c0a20207b0a202020226e616d65223a202253686f775f4530322e6d70342e6961222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a202253686f775f4530322e6d7034222c0a20202022666f726d6174223a2022682e323634204941222c0a2020202273697a65223a2022313530303030220a20207d2c0a20207b0a202020226e616d65223a202274696e795f706c616365686f6c6465722e6d7034222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a2022682e323634222c0a2020202273697a65223a20223530303030220a20207d0a205d2c0a202266696c65735f636f756e74223a2032332c0a20226974656d5f73697a65223a203430303030303030302c0a20226d65746164617461223a207b0a2020226964656e746966696572223a202253686f775f5365726965735f31393535222c0a2020227469746c65223a202253686f77222c0a20202263726561746f72223a202253747564696f222c0a2020226465736372697074696f6e223a205b0a202020223c703e50617261677261706820312e204c6f72656d20697073756d2e3c2f703e222c0a202020223c703e50617261677261706820322e3c2f703e220a20205d2c0a20202264617465223a2022313935352d30312d3031222c0a2020227375626a656374223a205b0a2020202274657374220a20205d2c0a2020226d6564696174797065223a20226d6f76696573222c0a202022636f6c6c656374696f6e223a205b0a20202022636c61737369635f7476222c0a202020226d6f76696573220a20205d2c0a20202272756e74696d65223a202233303a3030222c0a202022646f776e6c6f616473223a20223432222c0a2020226176675f726174696e67223a2022332e35222c0a2020226e756d5f72657669657773223a202232222c0a2020226c616e6775616765223a2022656e67220a207d2c0a2022736572766572223a202269613830303230302e75732e617263686976652e6f7267222c0a2022756e6971223a20332c0a2022776f726b61626c655f73657276657273223a205b0a20202269613830303230302e75732e617263686976652e6f7267220a205d0a7d0a"
constant kAxVecFixTextsItemHex = "7b0a202263726561746564223a20313730303030303030332c0a20226431223a202269613830303130302e75732e617263686976652e6f7267222c0a2022646972223a20222f332f6974656d732f7072696465616e647072656a7564696365303061757374222c0a202266696c6573223a205b0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573742e706466222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f6a70322e7a6970222c0a20202022666f726d6174223a20225465787420504446222c0a2020202273697a65223a20223132303030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f62772e706466222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f6a70322e7a6970222c0a20202022666f726d6174223a20224164646974696f6e616c205465787420504446222c0a2020202273697a65223a202239303030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573742e65707562222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f61626279792e677a222c0a20202022666f726d6174223a202245505542222c0a2020202273697a65223a2022363030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f646a76752e747874222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f646a76752e786d6c222c0a20202022666f726d6174223a2022446a5675545854222c0a2020202273697a65223a2022373030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f646a76752e786d6c222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f61626279792e677a222c0a20202022666f726d6174223a2022446a767520584d4c222c0a2020202273697a65223a202235303030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f61626279792e677a222c0a20202022736f75726365223a202264657269766174697665222c0a202020226f726967696e616c223a20227072696465616e647072656a75646963653030617573745f6a70322e7a6970222c0a20202022666f726d6174223a2022416262797920475a222c0a2020202273697a65223a202238303030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f6a70322e7a6970222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a202253696e676c6520506167652050726f636573736564204a5032205a4950222c0a2020202273697a65223a2022333030303030303030222c0a202020226d6435223a20223333333333333333333333333333333333333333333333333333333333333333220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f7363616e646174612e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20225363616e64617461222c0a2020202273697a65223a2022313030303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f6d6574612e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202231353030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f66696c65732e786d6c222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224d65746164617461222c0a2020202273697a65223a202233303030220a20207d2c0a20207b0a202020226e616d65223a20227072696465616e647072656a75646963653030617573745f617263686976652e746f7272656e74222c0a20202022736f75726365223a20226d65746164617461222c0a20202022666f726d6174223a20224172636869766520426974546f7272656e74222c0a2020202273697a65223a20223330303030220a20207d2c0a20207b0a202020226e616d65223a20225f5f69615f7468756d622e6a7067222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224974656d2054696c65222c0a2020202273697a65223a202238303030220a20207d2c0a20207b0a202020226e616d65223a2022636f7665722e6a7067222c0a20202022736f75726365223a20226f726967696e616c222c0a20202022666f726d6174223a20224a504547222c0a2020202273697a65223a2022323530303030220a20207d0a205d2c0a202266696c65735f636f756e74223a2031332c0a20226974656d5f73697a65223a203333363030303030302c0a20226d65746164617461223a207b0a2020226964656e746966696572223a20227072696465616e647072656a7564696365303061757374222c0a2020227469746c65223a2022507269646520616e64207072656a7564696365222c0a20202263726561746f72223a202241757374656e2c204a616e652c20313737352d31383137222c0a2020226d6564696174797065223a20227465787473222c0a202022636f6c6c656374696f6e223a205b0a20202022616d65726963616e61222c0a2020202263646c220a20205d2c0a20202264617465223a202231393030222c0a20202279656172223a202231393030222c0a2020226c616e6775616765223a2022656e67222c0a2020227375626a656374223a205b0a2020202246696374696f6e222c0a20202022456e676c616e64202d2d20536f6369616c206c69666520616e6420637573746f6d73202d2d20313974682063656e74757279202d2d2046696374696f6e220a20205d2c0a2020227075626c6973686572223a20224c6f6e646f6e3a204d61636d696c6c616e222c0a202022646f776e6c6f616473223a202233323130220a207d2c0a2022736572766572223a202269613830303130302e75732e617263686976652e6f7267222c0a2022756e6971223a20342c0a2022776f726b61626c655f73657276657273223a205b0a20202269613830303130302e75732e617263686976652e6f7267220a205d0a7d0a"
constant kAxVecFixSearchErrorHex = "7b0a20226572726f72223a20226f72672e6170616368652e6c7563656e652e71756572795061727365722e5061727365457863657074696f6e3a2043616e6e6f742070617273652027636f6c6c656374696f6e3a286c69627269766f78617564696f2920414e44202828273a20456e636f756e7465726564205c223c454f463e5c22220a7d0a"
constant kAxVecFixMissingItemHex = "7b7d0a"
constant kAxVecUrlSearch = "https://archive.org/advancedsearch.php?q=collection%3A%28librivoxaudio%29+AND+%28a+%22b%22%29&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=year&fl%5B%5D=creator&fl%5B%5D=date&fl%5B%5D=language&fl%5B%5D=runtime&fl%5B%5D=subject&sort%5B%5D=downloads+desc&rows=24&page=2&output=json"
constant kAxVecUrlScrape = "https://archive.org/services/search/v1/scrape?q=collection%3A%28GratefulDead%29&fields=identifier%2Ctitle&count=100&cursor=W3siaWRlbnRpZmllciI6ImdkNzcifV0%3D"
constant kAxVecUrlDownload = "https://archive.org/download/abc/a%20b%231.mp3"
constant kAxVecUrlDownloadDir = "https://archive.org/download/abc/dir/one%20two.mp3"
constant kAxVecLibrivoxDocIds = "pride_prejudice_test|book_2|book_3|book_4|book_5"
constant kAxVecLibrivoxDocOneCreator = "Jane Austen|Karen Savage"
constant kAxVecLibrivoxNumFound = "60"
constant kAxVecEtreeDocsTableHex = "6764313937372d30352d30382e7362642e6869636b732e343938322e7362656f6b2e73686e6609477261746566756c204465616409313937372d30352d30385430303a30303a30305a09536f756e64626f61726409313233343536370a676437372d30352d30372e6175642e7665726e6f6e2e31323334352e7362656f6b2e666c6163313609477261746566756c204465616409313937372d30352d30375430303a30303a30305a0941756469656e63650935343332310a6764313937372d30352d30392e6d74782e7365616d6f6e732e33313839332e666c6163313609477261746566756c204465616409313937372d30352d30395430303a30303a30305a094d61747269780939383736"
constant kAxVecMoviesDocTypes = "movies|collection|movies"
constant kAxVecLibrivoxCreator = "Jane Austen|Karen Savage"
constant kAxVecLibrivoxFilesCount = "36"
constant kAxVecLibrivoxChapterNames = "pp_01_austen_64kb.mp3|pp_02_austen_64kb.mp3|pp_03_austen_64kb.mp3|pp_04_austen_128kb.mp3|pp_05_austen_128kb.mp3"
constant kAxVecLibrivoxChapterTitlesHex = "3031202d204368617074657220317c3032202d204368617074657220327c3033202d20436861707465722033203c623e626f6c643c2f623e2026202271756f746564227c3034202d204368617074657220347c3035202d20436861707465722035"
constant kAxVecLibrivoxChapterTracks = "1|2|3|4|5"
constant kAxVecLibrivoxChapterLengths = "600.12|600.12|600.12|600.12|600.12"
constant kAxVecEtreeSetlist = "Set 1|Scarlet Begonias|Fire On The Mountain|Set 2|Not Fade Away|Morning Dew"
constant kAxVecEtreeYear = "1977"
constant kAxVecEtreeTrackNames = "gd77-05-08d1t01_vbr.mp3|gd77-05-08d1t02_vbr.mp3|gd77-05-08d1t10_vbr.mp3|gd77-05-08d2t01_vbr.mp3|gd77-05-08d2t02_vbr.mp3|gd77-05-08d2t09_vbr.mp3"
constant kAxVecEtreeTrackTitles = "Scarlet Begonias|Fire On The Mountain|Dancing In The Street|Not Fade Away|Morning Dew|gd77 05 08d2t09"
constant kAxVecEtreeTrackLengths = "382.35|615|3825|727|742.5|355"
constant kAxVecEtreeTrackFormats = "VBR MP3|VBR MP3|VBR MP3|VBR MP3|VBR MP3|VBR MP3"
constant kAxVecEtreeTrackOneUrl = "https://archive.org/download/gd1977-05-08.sbd.hicks.4982.sbeok.shnf/gd77-05-08d1t01_vbr.mp3"
constant kAxVecMoviesEpisodeNames = "Show_E01.mp4|Show_E02.mp4|Show_E03.mp4"
constant kAxVecMoviesEpisodeTitles = "E01|E02|E03"
constant kAxVecMoviesEpisodeQuality = "Auto|Auto|Auto"
constant kAxVecMoviesVariantsOne = "Show_E01.mp4|Auto|80000000|h.264;Show_E01_512kb.mp4|SD|20000000|512Kb MPEG4;Show_E01.ogv|Auto|30000000|Ogg Video"
constant kAxVecMoviesAutoKind = "video"
constant kAxVecTextsAutoKind = "documents"
constant kAxVecTextsDocNames = "prideandprejudice00aust.pdf|prideandprejudice00aust_bw.pdf|prideandprejudice00aust.epub|prideandprejudice00aust_djvu.txt"
constant kAxVecTextsImageNames = "cover.jpg"
constant kAxVecTextsFilesCount = "9"
constant kAxVecPresetCounts = "etree:49,librivox:40,movies:26,any:10"
constant kAxVecVideoScope = "(mediatype:(movies OR video OR television) OR (mediatype:collection AND identifier:(feature_films OR adviews OR academic_films OR animationandcartoons OR artsandmusicvideos OR classic_tv OR Comedy_Films OR educationalfilms OR ephemera OR FedFlix OR Film_Noir OR gamevideos OR home_movies OR movie_trailers OR movies OR nasa OR newsandpublicaffairs OR opensource_movies OR prelinger OR short_films OR silent_films OR SciFi_Horror OR sports OR tvarchive OR television)))"
constant kAxVecPresetRomance = "collection:(librivoxaudio) AND subject:(romance) AND (emma) AND subject:(solo) AND language:(English)"
constant kAxVecPresetDeadYears = "collection:(GratefulDead) AND mediatype:(etree) AND creator:(Grateful Dead) AND year:[1965 TO 1995]"
constant kAxVecPresetBobWeirHex = "636f6c6c656374696f6e3a2865747265652920414e442063726561746f723a2822426f6220576569722229202d63726561746f723a2822426f62205765697220616e6420526174646f672229"
constant kAxVecPresetPrelingerHex = "636f6c6c656374696f6e3a287072656c696e6765722920414e44206d65646961747970653a286d6f76696573204f5220766964656f204f522074656c65766973696f6e2920414e4420286d6f6f6e20726f636b657420746573742920414e4420286c6963656e736575726c3a22687474703a2f2f6372656174697665636f6d6d6f6e732e6f72672f7075626c6963646f6d61696e2f6d61726b2f312e302f22204f52206c6963656e736575726c3a2268747470733a2f2f6372656174697665636f6d6d6f6e732e6f72672f7075626c6963646f6d61696e2f6d61726b2f312e302f22204f52206c6963656e736575726c3a22687474703a2f2f6372656174697665636f6d6d6f6e732e6f72672f7075626c6963646f6d61696e2f2229"
constant kAxVecPresetAuthor = "collection:(librivoxaudio) AND creator:(Jane Austen)"
constant kAxVecPresetCollectionHex = "6d65646961747970653a2865747265652920414e4420636f6c6c656374696f6e3a2850686973682920414e4420796561723a5b3139393720544f20313939395d20414e4420736f757263653a28736f756e64626f617264204f5220736264204f5220227362642229"
-- <<< KAT CONSTANTS END <<<

-- ==========================================================================
-- Counters and per-run state.
-- ==========================================================================

local sAxtLog
local sAxtPass
local sAxtFail
local sAxtSkip

-- ==========================================================================
-- Entry point and plumbing.
-- ==========================================================================

function axSelfTest
   local tSummary
   put empty into sAxtLog
   put 0 into sAxtPass
   put 0 into sAxtFail
   put 0 into sAxtSkip
   axtTestVersionAndBase
   axtTestEncoders
   axtTestScalars
   axtTestSanitizer
   axtTestQueryBuilders
   axtTestFamiliesAndPresets
   axtTestUrls
   axtTestJsonReader
   axtTestResponses
   axtTestFileRules
   axtTestPlaylists
   axtTestFetchLayerOffline
   axJsonFreeAll
   put sAxtPass & " passed, " & sAxtFail & " failed, " & sAxtSkip & " skipped" into tSummary
   return tSummary & return & "----------------------------------------" & return & sAxtLog
end axSelfTest

private command axtCheck pCondition, pLabel
   if pCondition is true then
      add 1 to sAxtPass
      put "  ok   " & pLabel & return after sAxtLog
   else
      add 1 to sAxtFail
      put "  FAIL " & pLabel & return after sAxtLog
   end if
end axtCheck

private command axtSection pTitle
   put "-- " & pTitle & " --" & return after sAxtLog
end axtSection

private command axtSkip pReason
   add 1 to sAxtSkip
   put "  --   (skipped: " & pReason & ")" & return after sAxtLog
end axtSkip

private function axtHex pHex
   -- The text whose UTF-8 bytes pHex spells: how a pinned fixture or a
   -- quote-bearing expectation gets back into a value.
   local tI, tCount, tOut, tHi, tLo
   put the number of chars of pHex into tCount
   put empty into tOut
   put 1 into tI
   repeat while tI < tCount
      put axtNibble(char tI of pHex) into tHi
      put axtNibble(char (tI + 1) of pHex) into tLo
      put numToByte(tHi * 16 + tLo) after tOut
      add 2 to tI
   end repeat
   return textDecode(tOut, "UTF-8")
end axtHex

private function axtNibble pChar
   local tByte
   put byteToNum(pChar) into tByte
   if tByte >= 97 then
      return tByte - 87
   end if
   if tByte >= 65 then
      return tByte - 55
   end if
   return tByte - 48
end axtNibble

private function axtJoinLines pLines, pSep
   -- Lines joined with pSep, the way the KAT joins a list into one
   -- constant.
   local tOut, tI, tCount
   put the number of lines of pLines into tCount
   put empty into tOut
   repeat with tI = 1 to tCount
      if tI > 1 then
         put pSep after tOut
      end if
      put line tI of pLines after tOut
   end repeat
   return tOut
end axtJoinLines

private function axtEntryField pPlaylist, pField
   -- One field of every playlist entry, "|"-joined.
   local tOut, tI, tCount
   put pPlaylist["count"] into tCount
   put empty into tOut
   if tCount is not a number then
      return empty
   end if
   repeat with tI = 1 to tCount
      if tI > 1 then
         put "|" after tOut
      end if
      put pPlaylist["entries"][tI][pField] after tOut
   end repeat
   return tOut
end axtEntryField

private function axtSampleFile pName, pFormat, pSource, pSize
   local tFile
   put pName into tFile["name"]
   put pFormat into tFile["format"]
   put pSource into tFile["source"]
   put pSize into tFile["size"]
   return tFile
end axtSampleFile

-- ==========================================================================
-- 1. Version, errors, base URL, capabilities.
-- ==========================================================================

private command axtTestVersionAndBase
   local tCaps
   axtSection "version, errors, base url, capabilities"
   axtCheck axVersion() begins with "ArchiveXT", "axVersion reports the member name"
   axtCheck axBaseUrl() is "https://archive.org", "the default base is the public site"
   axtCheck axSetBaseUrl("http://mirror.test/") is true, "axSetBaseUrl accepts an http base"
   axtCheck axBaseUrl() is "http://mirror.test", "the trailing slash is dropped"
   axtCheck axMetadataUrl("abc") is "http://mirror.test/metadata/abc", "builders use the base"
   axtCheck axSetBaseUrl("ftp://nope") is false, "a non-http base refuses"
   axtCheck axLastError() contains "http://", "axLastError carries the refusal"
   axtCheck axSetBaseUrl(empty) is true, "empty restores the default"
   axtCheck axBaseUrl() is "https://archive.org", "the default is back"
   put axProbeCapabilities() into tCaps
   axtCheck tCaps is an array, "axProbeCapabilities returns an array"
   axtCheck tCaps["version"] is axVersion(), "the capability array carries the version"
   if tCaps["hasUrlLib"] is true then
      axtCheck tCaps["urlLibVersion"] is not empty, "the Internet library reports a version"
   else
      axtSkip "no Internet library on this engine (libURLVersion did not answer); the fetch layer would refuse"
   end if
end axtTestVersionAndBase

-- ==========================================================================
-- 2. The two URL encoders and the small text helpers.
-- ==========================================================================

private command axtTestEncoders
   axtSection "encoders and text helpers"
   axtCheck axUrlEncode("a b#1.mp3") is "a%20b%231.mp3", "axUrlEncode is encodeURIComponent (space, hash)"
   axtCheck axUrlEncode("-_.!~*'()") is "-_.!~*'()", "axUrlEncode spares the nine characters"
   axtCheck axUrlEncode("/") is "%2F", "axUrlEncode encodes a slash"
   axtCheck axUrlEncodePath("dir/one two.mp3") is "dir/one%20two.mp3", "axUrlEncodePath keeps the separators"
   axtCheck axQueryEncode("a b") is "a+b", "axQueryEncode spells a space as plus"
   axtCheck axQueryEncode("(x:y)") is "%28x%3Ay%29", "axQueryEncode encodes parentheses and colons"
   axtCheck axQueryEncode("*-._") is "*-._", "axQueryEncode spares the four"
   axtCheck axLowerAscii("MiXeD 123 Ab") is "mixed 123 ab", "axLowerAscii lowers ASCII only"
   axtCheck axUpperFirst("ghost stories") is "Ghost stories", "axUpperFirst"
   axtCheck axUpperFirst(empty) is empty, "axUpperFirst of empty"
   axtCheck axTrim("  a b " & tab) is "a b", "axTrim strips both ends"
   axtCheck axCollapseSpaces("  a   b " & tab & "c ") is "a b c", "axCollapseSpaces"
   axtCheck axIsHttpUrl("https://archive.org") is true, "axIsHttpUrl accepts https"
   axtCheck axIsHttpUrl("HTTP://x") is true, "axIsHttpUrl folds the scheme's case"
   axtCheck axIsHttpUrl("http://") is false, "axIsHttpUrl wants a host"
   axtCheck axIsHttpUrl("ftp://x") is false, "axIsHttpUrl refuses ftp"
   axtCheck axStrEq("AND", "AND") is true, "axStrEq equal"
   axtCheck axStrEq("AND", "and") is false, "axStrEq is byte-exact (is would fold)"
   axtCheck axUtf8Bytes(65) is "A", "axUtf8Bytes one byte"
   axtCheck the number of bytes of axUtf8Bytes(233) is 2, "axUtf8Bytes two bytes"
   axtCheck the number of bytes of axUtf8Bytes(8364) is 3, "axUtf8Bytes three bytes"
   axtCheck the number of bytes of axUtf8Bytes(128156) is 4, "axUtf8Bytes four bytes"
end axtTestEncoders

-- ==========================================================================
-- 3. Identifiers, years, durations, sizes, natural order, multi-values.
-- ==========================================================================

private command axtTestScalars
   local tLines
   axtSection "identifiers, years, durations, sizes, natural order"
   axtCheck axIdentifierIsValid("pride_and_prejudice_librivox") is true, "identifier: a real one"
   axtCheck axIdentifierIsValid("a.b-c_1") is true, "identifier: dots and dashes"
   axtCheck axIdentifierIsValid(empty) is false, "identifier: empty refuses"
   axtCheck axIdentifierIsValid("../etc") is false, "identifier: traversal refuses"
   axtCheck axIdentifierIsValid("x y") is false, "identifier: a space refuses"
   axtCheck axIdentifierIsValid("<script>") is false, "identifier: markup refuses"
   axtCheck axIdentifierIsValid("-lead") is false, "identifier: must start with a letter or digit"
   axtCheck axYearOf("1977-05-08T00:00:00Z") is "1977", "axYearOf a date"
   axtCheck axYearOf("05/08/1977") is "1977", "axYearOf finds the run anywhere"
   axtCheck axYearOf("77-05-08") is empty, "axYearOf: two digits are not a year"
   axtCheck axYearOf("12345") is empty, "axYearOf: five digits are not a year"
   axtCheck axNormalizeYear(" 2024 ") is "2024", "axNormalizeYear trims"
   axtCheck axNormalizeYear("19") is empty, "axNormalizeYear refuses two digits"
   axtCheck axNormalizeYear("abcd") is empty, "axNormalizeYear refuses letters"
   axtCheck axNormalizeYear("0999") is empty, "axNormalizeYear refuses below 1000"
   axtCheck axDurationSeconds("600.12") is 600.12, "duration: seconds"
   axtCheck axDurationSeconds("12:34") is 754, "duration: mm:ss"
   axtCheck axDurationSeconds("1:02:03") is 3723, "duration: h:mm:ss"
   axtCheck axDurationSeconds("1:02:03.5") is 3723.5, "duration: fractional seconds survive"
   axtCheck axDurationSeconds(empty) is empty, "duration: empty is empty"
   axtCheck axDurationSeconds("n/a") is empty, "duration: n/a is empty, not zero"
   axtCheck axDurationSeconds("1:xx") is empty, "duration: a bad component voids the value"
   axtCheck axFormatTime(0) is "0:00", "axFormatTime 0"
   axtCheck axFormatTime(65) is "1:05", "axFormatTime 65"
   axtCheck axFormatTime(3599.9) is "59:59", "axFormatTime floors"
   axtCheck axFormatTime(3600) is "1:00:00", "axFormatTime an hour"
   axtCheck axFormatTime(45296) is "12:34:56", "axFormatTime 45296"
   axtCheck axFormatTime(-5) is "0:00", "axFormatTime negative"
   axtCheck axFormatTime("abc") is "0:00", "axFormatTime non-numeric"
   axtCheck axFormatBytes(80000000) is "76.29 MB", "axFormatBytes 80000000"
   axtCheck axFormatBytes(20000000) is "19.07 MB", "axFormatBytes 20000000"
   axtCheck axFormatBytes(1024) is "1 KB", "axFormatBytes 1024"
   axtCheck axFormatBytes(1536) is "1.5 KB", "axFormatBytes drops a trailing zero"
   axtCheck axFormatBytes(0) is empty, "axFormatBytes zero is empty"
   axtCheck axFormatBytes("x") is empty, "axFormatBytes non-numeric is empty"
   axtCheck axNaturalKey("Part10") is "part000000000010", "axNaturalKey pads digit runs"
   put "b_part2.ogg" & return & "b_part10.ogg" & return & "b_part1.ogg" into tLines
   axtCheck axNaturalSort(tLines) is "b_part1.ogg" & return & "b_part2.ogg" & return & "b_part10.ogg", "axNaturalSort orders numerically"
   axtCheck axNaturalSort("one") is "one", "axNaturalSort of one line"
   axtCheck axFirst("Jane Austen" & return & "Karen Savage") is "Jane Austen", "axFirst"
   axtCheck axJoin("English" & return & "French", empty) is "English, French", "axJoin default separator"
   axtCheck axJoin("2010", " / ") is "2010", "axJoin of a scalar"
   axtCheck axTrackNumber("01") is 1, "axTrackNumber 01"
   axtCheck axTrackNumber("4/5") is 4, "axTrackNumber 4/5"
   axtCheck axTrackNumber(7) is 7, "axTrackNumber 7"
   axtCheck axTrackNumber("n/a") is empty, "axTrackNumber n/a"
   axtCheck axTrackNumber(empty) is empty, "axTrackNumber empty"
end axtTestScalars

-- ==========================================================================
-- 4. The sanitizer (the AudioBooks vectors, both modes).
-- ==========================================================================

private command axtTestSanitizer
   axtSection "query sanitizer"
   axtCheck axQuerySanitize("Title - Subtitle", false) is "Title Subtitle", "a bare dash is dropped"
   axtCheck axQuerySanitize("austen -", false) is "austen", "a trailing bare dash is dropped"
   axtCheck axQuerySanitize("+", false) is empty, "a lone plus is nothing"
   axtCheck axQuerySanitize("!", false) is empty, "a lone bang is nothing"
   axtCheck axQuerySanitize("a &&", false) is "a", "&& is blanked"
   axtCheck axQuerySanitize("a || b", false) is "a b", "|| is blanked"
   axtCheck axQuerySanitize("-austen", false) is "-austen", "an attached minus stays"
   axtCheck axQuerySanitize("austen AND AND dickens", false) is "austen AND dickens", "a run of operators keeps the last"
   axtCheck axQuerySanitize("(austen AND)", false) is "(austen)", "an operator before a close paren goes"
   axtCheck axQuerySanitize("()", false) is empty, "an empty group is nothing"
   axtCheck axQuerySanitize("austen AND OR", false) is "austen", "trailing operators go"
   axtCheck axQuerySanitize("NOT austen", false) is "NOT austen", "a leading NOT stays"
   axtCheck axQuerySanitize("austen AND NOT dickens", false) is "austen NOT dickens", "AND NOT keeps NOT"
   axtCheck axQuerySanitize("AND OR NOT", false) is empty, "only operators is nothing"
   axtCheck axQuerySanitize("year:[1800 TO 1850]", true) is "year:[1800 TO 1850]", "field syntax: a range survives"
   axtCheck axQuerySanitize("year:[1800 TO", true) is "year: 1800 TO", "field syntax: an unbalanced range is blanked"
   axtCheck axQuerySanitize("title:emma~2 dickens^3", true) is "title:emma~2 dickens^3", "field syntax: fuzzy and boost survive"
   axtCheck axQuerySanitize("austen ((", false) is "austen", "unbalanced parens are blanked"
   axtCheck axQuerySanitize(quote & "Pride and Prejudice", false) is "Pride and Prejudice", "an odd quote is blanked"
   axtCheck axQuerySanitize(quote & "Pride and Prejudice" & quote, false) is quote & "Pride and Prejudice" & quote, "balanced quotes stay"
   axtCheck axQuerySanitize("(austen OR dickens)", false) is "(austen OR dickens)", "a balanced group stays"
   axtCheck axQuerySanitize("austen AND", false) is "austen", "a trailing AND goes"
   axtCheck axQuerySanitize("AND", false) is empty, "a lone AND is nothing"
   axtCheck axQuerySanitize("Pride and", false) is "Pride and", "a lower-case and is a word"
   axtCheck axQuerySanitize("a[b]{c}\d^e~f/g", false) is "a b c d e f g", "plain mode blanks the special characters"
   axtCheck axQuerySanitize("   ", false) is empty, "whitespace is nothing"
   axtCheck axQuerySanitize("Dracula: Chapter 1", false) is "Dracula Chapter 1", "plain mode blanks a colon"
   axtCheck axQuerySanitize("Dracula: Chapter 1", true) is "Dracula: Chapter 1", "field syntax keeps a colon"
   axtCheck axQuerySanitize("-(austen OR dickens)", false) is "-(austen OR dickens)", "a prefix operator stays attached to its group"
end axtTestSanitizer

-- ==========================================================================
-- 5. Clause and query builders.
-- ==========================================================================

private command axtTestQueryBuilders
   local tSpec
   axtSection "query builders"
   axtCheck axQueryClause("collection", "Phish") is "collection:(Phish)", "axQueryClause"
   axtCheck axQueryClause("collection", "  ") is empty, "axQueryClause of blank is empty"
   axtCheck axQueryPhrase("creator", "Jane " & quote & "Austen") is "creator:(" & quote & "Jane Austen" & quote & ")", "axQueryPhrase drops inner quotes"
   axtCheck axQueryPhrase(empty, "x") is empty, "axQueryPhrase needs a field"
   axtCheck axQueryRange("year", "1965", "1995") is "year:[1965 TO 1995]", "axQueryRange"
   axtCheck axQueryRange("year", "1995", "1965") is "year:[1965 TO 1995]", "axQueryRange swaps reversed ends"
   axtCheck axQueryRange("year", empty, "1950") is "year:[* TO 1950]", "axQueryRange open start"
   axtCheck axQueryRange("year", empty, empty) is empty, "axQueryRange of nothing is empty"
   axtCheck axQueryYears("1900", empty) is "year:[1900 TO *]", "axQueryYears from"
   axtCheck axQueryYears("19", "abcd") is empty, "axQueryYears ignores non-years"
   put "collection:(librivoxaudio)" into tSpec["base"]
   put "Dracula: Chapter 1" into tSpec["text"]
   put "title" into tSpec["textField"]
   axtCheck axQueryBuild(tSpec) is "collection:(librivoxaudio) AND title:(Dracula Chapter 1)", "axQueryBuild: a field mode"
   put empty into tSpec
   put "collection:(librivoxaudio)" into tSpec["base"]
   put "creator:austen AND title:emma" into tSpec["text"]
   put true into tSpec["fieldSyntax"]
   axtCheck axQueryBuild(tSpec) is "collection:(librivoxaudio) AND (creator:austen AND title:emma)", "axQueryBuild: field syntax"
   put empty into tSpec
   put "collection:(librivoxaudio)" into tSpec["base"]
   put "1950" into tSpec["yearFrom"]
   put "1900" into tSpec["yearTo"]
   axtCheck axQueryBuild(tSpec) is "collection:(librivoxaudio) AND year:[1900 TO 1950]", "axQueryBuild: years swapped"
   put empty into tSpec
   put "collection:(librivoxaudio) AND subject:(romance)" into tSpec["base"]
   put "emma" into tSpec["text"]
   put "subject:(solo)" & return & "language:(English)" into tSpec["filters"]
   axtCheck axQueryBuild(tSpec) is kAxVecPresetRomance, "axQueryBuild: text and filters (the AudioBooks vector)"
   put empty into tSpec
   put "moon: rocket (test)" into tSpec["text"]
   put true into tSpec["plainText"]
   put "collection:(prelinger)" into tSpec["base"]
   axtCheck axQueryBuild(tSpec) is "collection:(prelinger) AND (moon rocket test)", "axQueryBuild: the film club's plain rule"
   put empty into tSpec
   axtCheck axQueryBuild(tSpec) is empty, "axQueryBuild of nothing refuses"
   axtCheck axLastError() contains "nothing to search", "and says why"
   axtCheck axPublicDomainClause() begins with "(licenseurl:" & quote, "axPublicDomainClause carries its quotes"
end axtTestQueryBuilders

-- ==========================================================================
-- 6. Families, presets, filters, sorts.
-- ==========================================================================

private command axtTestFamiliesAndPresets
   local tInfo, tRows, tSpec, tSavedDelim, tCounts, tExpected
   axtSection "families, presets, filters, sorts"
   axtCheck the number of lines of axFamilyList() is 4, "four families"
   put axFamilyInfo("etree") into tInfo
   axtCheck tInfo["kind"] is "audio-tracks", "etree wants audio-tracks"
   axtCheck tInfo["rows"] is 10, "the tape finder paged by 10"
   axtCheck tInfo["fields"] contains "venue", "etree asks for the venue"
   axtCheck axFamilyInfo("nope") is empty, "an unknown family refuses"
   axtCheck axFamilyScope("librivox") is "collection:(librivoxaudio)", "librivox scope"
   axtCheck axFamilyScope("movies") is "mediatype:(movies OR video OR television)", "the movies family scope is the cheap mediatype clause (the full OR-list timed out live, 2026-09-15)"
   put axFamilyInfo("any") into tInfo
   axtCheck tInfo["scope"] is empty, "the any family has no scope"
   axtCheck the number of lines of axVideoCollections() is 26, "26 film collections"
   axtCheck axVideoScope() is kAxVecVideoScope, "axVideoScope"
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to ","
   put "etree:" & the number of lines of axPresetTable("etree") into tCounts
   put tCounts & ",librivox:" & the number of lines of axPresetTable("librivox") into tCounts
   put tCounts & ",movies:" & the number of lines of axPresetTable("movies") into tCounts
   put tCounts & ",any:" & the number of lines of axPresetTable("any") into tCounts
   set the itemDelimiter to tSavedDelim
   axtCheck tCounts is kAxVecPresetCounts, "preset counts per family (" & tCounts & ")"
   axtCheck axPresetTable("nope") is empty, "an unknown family's table is empty"
   axtCheck the number of lines of axPresetList("librivox") is 40, "axPresetList lists every row"
   put axPresetInfo("etree", "GratefulDead") into tInfo
   axtCheck tInfo["yearFrom"] is "1965", "the Dead preset carries its year range"
   axtCheck tInfo["group"] is "Dead family", "and its group"
   axtCheck axPresetInfo("etree", "gratefuldead") is empty, "preset ids are byte-exact"
   axtCheck axPresetQuery("etree", "BobWeir") is axtHex(kAxVecPresetBobWeirHex), "a preset query with a negated clause"
   axtCheck axPresetQuery("librivox", "Custom") is "collection:(librivoxaudio)", "a search-mode preset answers the scope"
   axtCheck axPresetQuery("movies", "all_videos") is axFamilyScope("movies"), "all_videos is the family scope alone"
   axtCheck axPresetQuery("movies", "prelinger") begins with "collection:(prelinger) AND ", "a film collection leads with its clause"
   put axPresetSpec("librivox", "Romance", "emma", empty, empty, axFilterClauses("librivox", "solo,english,bogus")) into tSpec
   axtCheck axQueryBuild(tSpec) is kAxVecPresetRomance, "axPresetSpec: the Romance vector"
   put axPresetSpec("etree", "GratefulDead", empty, empty, empty, empty) into tSpec
   axtCheck axQueryBuild(tSpec) is kAxVecPresetDeadYears, "axPresetSpec: a default year range applies"
   put axPresetSpec("etree", "GratefulDead", empty, "1977", empty, empty) into tSpec
   axtCheck axQueryBuild(tSpec) ends with "year:[1977 TO *]", "axPresetSpec: a given year overrides the default"
   put axPresetSpec("movies", "prelinger", "moon: rocket (test)", empty, empty, axFilterClauses("movies", "publicdomain")) into tSpec
   axtCheck axQueryBuild(tSpec) is axtHex(kAxVecPresetPrelingerHex), "axPresetSpec: the film club's plain rule and licence filter"
   put axPresetSpec("librivox", "Author_Search", "Jane Austen", empty, empty, empty) into tSpec
   axtCheck axQueryBuild(tSpec) is kAxVecPresetAuthor, "axPresetSpec: an author search"
   put axPresetSpec("etree", "Collection_Search", "Phish", "1997", "1999", axFilterClauses("etree", "soundboard")) into tSpec
   axtCheck axQueryBuild(tSpec) is axtHex(kAxVecPresetCollectionHex), "axPresetSpec: a collection search with years and a filter"
   axtCheck axPresetSpec("etree", "nope", empty, empty, empty, empty) is empty, "axPresetSpec of an unknown preset refuses"
   axtCheck the number of lines of axFilterList("etree") is 4, "four etree filters"
   axtCheck the number of lines of axFilterList("librivox") is 3, "three librivox filters"
   axtCheck axFilterList("any") is empty, "no any filters"
   axtCheck axFilterClause("etree", "five-star") is "avg_rating:[4.5 TO 5]", "axFilterClause"
   axtCheck axFilterClause("etree", "nope") is empty, "an unknown filter is empty"
   axtCheck axFilterClauses("librivox", "solo, english") is "subject:(solo)" & return & "language:(English)", "axFilterClauses trims and joins"
   axtCheck the number of lines of axSortList() is 7, "seven sorts"
   axtCheck axSortClause("date") is "publicdate desc", "axSortClause date"
   axtCheck axSortClause("relevance") is empty, "relevance is no sort"
   axtCheck axSortClause("year asc") is "year asc", "a clause passes through"
   axtCheck axSortClause("nope") is "downloads desc", "unknown sorts fall back to downloads"
end axtTestFamiliesAndPresets

-- ==========================================================================
-- 7. URL builders.
-- ==========================================================================

private command axtTestUrls
   local tItem, tBare
   axtSection "url builders"
   axtCheck axSearchUrl("collection:(librivoxaudio) AND (a " & quote & "b" & quote & ")", "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2) is kAxVecUrlSearch, "axSearchUrl matches the AudioBooks bytes"
   axtCheck axSearchUrl("x", "identifier", empty, empty, empty) is "https://archive.org/advancedsearch.php?q=x&fl%5B%5D=identifier&rows=24&page=1&output=json", "axSearchUrl defaults and no sort"
   axtCheck axSearchUrl(empty, "identifier", empty, 10, 1) is empty, "axSearchUrl refuses an empty query"
   axtCheck axSearchUrl("x", "identifier", empty, "ten", 1) is empty, "axSearchUrl refuses non-numeric rows"
   axtCheck axSearchUrl("x", "identifier", empty, 10, 0) is empty, "axSearchUrl refuses page 0"
   axtCheck axScrapeUrl("collection:(GratefulDead)", "identifier,title", 100, "W3siaWRlbnRpZmllciI6ImdkNzcifV0=") is kAxVecUrlScrape, "axScrapeUrl with a cursor"
   axtCheck axScrapeUrl("x", empty, empty, empty) is "https://archive.org/services/search/v1/scrape?q=x&count=100", "axScrapeUrl defaults"
   axtCheck axScrapeUrl(empty, "identifier", 10, empty) is empty, "axScrapeUrl refuses an empty query"
   axtCheck axMetadataUrl("abc") is "https://archive.org/metadata/abc", "axMetadataUrl"
   axtCheck axMetadataUrl("../etc") is empty, "axMetadataUrl refuses a bad identifier"
   axtCheck axDownloadUrl("abc", "a b#1.mp3") is kAxVecUrlDownload, "axDownloadUrl encodes the name"
   axtCheck axDownloadUrl("abc", "dir/one two.mp3") is kAxVecUrlDownloadDir, "axDownloadUrl keeps a directory separator"
   axtCheck axDownloadUrl("abc", empty) is "https://archive.org/download/abc", "axDownloadUrl of the listing"
   axtCheck axDownloadUrl("x y", "f") is empty, "axDownloadUrl refuses a bad identifier"
   axtCheck axThumbnailUrl("abc") is "https://archive.org/services/img/abc", "axThumbnailUrl"
   axtCheck axDetailsUrl("abc") is "https://archive.org/details/abc", "axDetailsUrl"
   axtCheck axEmbedUrl("abc") is "https://archive.org/embed/abc", "axEmbedUrl"
   axtCheck axEmbedUrl(empty) is empty, "axEmbedUrl refuses empty"
   put axItemParse(axtHex(kAxVecFixLibrivoxItemHex)) into tItem
   axtCheck axDirectUrl(tItem, "pp_01_austen_64kb.mp3") is "https://ia800000.us.archive.org/1/items/pride_prejudice_test/pp_01_austen_64kb.mp3", "axDirectUrl is the datanode host and directory"
   axtCheck axDirectUrl(tItem, "a b#1.mp3") is "https://ia800000.us.archive.org/1/items/pride_prejudice_test/a%20b%231.mp3", "axDirectUrl encodes the name"
   axtCheck axDirectUrl(tItem, empty) is empty, "axDirectUrl refuses an empty name"
   put "abc" into tBare["identifier"]
   axtCheck axDirectUrl(tBare, "f.mp3") is "https://archive.org/download/abc/f.mp3", "axDirectUrl falls back to /download/ without a server"
   put "bad host" into tBare["server"]
   put "/1/items/abc" into tBare["dir"]
   axtCheck axDirectUrl(tBare, "f.mp3") is "https://archive.org/download/abc/f.mp3", "axDirectUrl falls back on a server that is not a host"
end axtTestUrls

-- ==========================================================================
-- 8. The JSON reader.
-- ==========================================================================

private command axtTestJsonReader
   local tJson, tDoc, tDeep, tI, tDoc2
   axtSection "json reader"
   put "{" & quote & "a" & quote & ":[1,2,{" & quote & "b" & quote & ":" & quote & "x" & quote & "}],  " & quote & "c" & quote & ":true," & quote & "d" & quote & ":null," & quote & "e" & quote & ":[" & quote & "p" & quote & "," & quote & "q" & quote & "]}" into tJson
   put axJsonParse(tJson) into tDoc
   axtCheck tDoc is not empty, "a document parses to a handle"
   axtCheck axJsonHandleIsLive(tDoc) is true, "the handle is live"
   axtCheck axJsonType(tDoc, empty) is "object", "root object types"
   axtCheck axJsonType(tDoc, "a") is "array", "array member types"
   axtCheck axJsonCount(tDoc, "a") is 3, "array count"
   axtCheck axJsonCount(tDoc, empty) is 4, "object member count"
   axtCheck axJsonGet(tDoc, "a/2") is "2", "array element by index"
   axtCheck axJsonGet(tDoc, "a/3/b") is "x", "nested object member"
   axtCheck axJsonType(tDoc, "c") is "boolean", "boolean types"
   axtCheck axJsonGet(tDoc, "c") is "true", "boolean value"
   axtCheck axJsonType(tDoc, "d") is "null", "null types"
   axtCheck axJsonGet(tDoc, "d") is empty, "null is empty"
   axtCheck axJsonType(tDoc, "missing") is "missing", "an absent key is missing"
   axtCheck axJsonType(tDoc, "A") is "missing", "keys are case-sensitive"
   -- the engine folds ARRAY keys (2026-09-15: this line was red while the
   -- reader indexed children by key in an array); the reader scans its key
   -- list byte-exactly now, so two keys differing only in case both answer
   put axJsonParse("{" & quote & "a" & quote & ":1," & quote & "A" & quote & ":2}") into tDoc2
   axtCheck axJsonGet(tDoc2, "a") is "1", "a lower-case key answers its own value beside its upper-case twin"
   axtCheck axJsonGet(tDoc2, "A") is "2", "and the upper-case key answers its own"
   axtCheck axJsonCount(tDoc2, empty) is 2, "both keys are members"
   axJsonFree tDoc2
   axtCheck axJsonType(tDoc, "a/4") is "missing", "an index past the end is missing"
   axtCheck axJsonType(tDoc, "a/0") is "missing", "index 0 is missing"
   axtCheck axJsonType(tDoc, "a/1/x") is "missing", "a path into a scalar is missing"
   axtCheck axJsonGet(tDoc, "a/3") is "{" & quote & "b" & quote & ":" & quote & "x" & quote & "}", "a container answers its verbatim slice"
   axtCheck axJsonKeys(tDoc, empty) is "a" & return & "c" & return & "d" & return & "e", "keys in document order"
   axtCheck axJsonKeys(tDoc, "a") is empty, "keys of an array is empty"
   axtCheck axJsonValues(tDoc, "e") is "p" & return & "q", "values of an array of scalars"
   axtCheck axJsonValues(tDoc, "c") is "true", "values of a scalar is one line"
   axtCheck axJsonValues(tDoc, "a") is "1" & return & "2", "values skip nested containers"
   axtCheck axJsonValues(tDoc, "a/3") is empty, "values of an object is empty"
   axJsonFree tDoc
   axtCheck axJsonHandleIsLive(tDoc) is false, "a freed handle is not live"
   axtCheck axJsonType(tDoc, empty) is "missing", "a freed handle answers missing"
   axJsonFree tDoc
   axtCheck true, "freeing twice is a clean no-op"
   axtCheck axJsonType(999, empty) is "missing", "an unknown handle answers missing"
   -- string escapes, including \u and a surrogate pair
   put "[" & quote & "A\n\t\" & quote & quote & "," & quote & "\ud83d\udc9c" & quote & "," & quote & "\u00e9" & quote & "]" into tJson
   put axJsonParse(tJson) into tDoc
   axtCheck the number of bytes of textEncode(axJsonGet(tDoc, "1"), "UTF-8") is 4, "the simple escapes decode to one byte each"
   axtCheck the number of bytes of textEncode(axJsonGet(tDoc, "2"), "UTF-8") is 4, "a surrogate pair becomes four UTF-8 bytes"
   axtCheck the number of bytes of textEncode(axJsonGet(tDoc, "3"), "UTF-8") is 2, "a two-byte code point"
   axJsonFree tDoc
   -- refusals
   axtCheck axJsonParse("[1,2] trailing") is empty, "trailing bytes refuse"
   axtCheck axJsonParse("[tRUE]") is empty, "a mixed-case literal refuses"
   axtCheck axJsonParse("[" & quote & "unterminated") is empty, "an unterminated string refuses"
   axtCheck axJsonParse("[" & quote & "\ud83d" & quote & "]") is empty, "a lone high surrogate refuses"
   axtCheck axJsonParse("[" & quote & "\q" & quote & "]") is empty, "an unknown escape refuses"
   axtCheck axJsonParse("{" & quote & "a" & quote & " 1}") is empty, "a missing colon refuses"
   axtCheck axJsonParse("[1 2]") is empty, "a missing comma refuses"
   axtCheck axJsonParse("[-]") is empty, "a sign without digits refuses"
   axtCheck axJsonParse(empty) is empty, "an empty document refuses"
   axtCheck axLastError() contains "unexpected end", "and says why"
   put empty into tDeep
   repeat with tI = 1 to 70
      put "[" after tDeep
   end repeat
   put "1" after tDeep
   repeat with tI = 1 to 70
      put "]" after tDeep
   end repeat
   axtCheck axJsonParse(tDeep) is empty, "nesting deeper than the cap refuses"
   put axJsonParse("{" & quote & "k" & quote & ":1," & quote & "k" & quote & ":2}") into tDoc
   axtCheck axJsonGet(tDoc, "k") is "1", "a duplicate key keeps its first value"
   axJsonFree tDoc
   put axJsonParse("  12.5e1  ") into tDoc
   axtCheck axJsonGet(tDoc, empty) is "12.5e1", "a number keeps its text"
   axtCheck axJsonType(tDoc, empty) is "number", "a scalar root"
   axJsonFreeAll
   axtCheck axJsonHandleIsLive(tDoc) is false, "axJsonFreeAll frees everything"
end axtTestJsonReader

-- ==========================================================================
-- 9. The two response parsers over the fixtures.
-- ==========================================================================

private command axtTestResponses
   local tResult, tItem, tIds, tI, tTable
   local tScrape
   axtSection "response parsers (synthetic fixtures)"
   put axSearchParse(axtHex(kAxVecFixLibrivoxSearchHex)) into tResult
   axtCheck tResult is an array, "the librivox search fixture parses"
   axtCheck tResult["numFound"] is kAxVecLibrivoxNumFound, "numFound"
   axtCheck tResult["count"] is 5, "five docs on the page"
   axtCheck tResult["start"] is 0, "start"
   put empty into tIds
   repeat with tI = 1 to tResult["count"]
      if tI > 1 then
         put "|" after tIds
      end if
      put axFirst(tResult["docs"][tI]["identifier"]) after tIds
   end repeat
   axtCheck tIds is kAxVecLibrivoxDocIds, "every doc's identifier, in order"
   axtCheck axtJoinLines(tResult["docs"][1]["creator"], "|") is kAxVecLibrivoxDocOneCreator, "a multi-valued creator is lines"
   -- THE SCRAPE BLOCK KEEPS ITS OWN VARIABLE, and the reason is a real
   -- engine failure. It was written with tResult, which the two lines
   -- below it still expect to hold the librivox SEARCH fixture - so the
   -- 2026-09-20 run reported `a scalar subject is one line` FAILED
   -- against an array that had no docs in it at all, and the line after
   -- it ("an absent field is empty") had quietly become a check that
   -- could not fail for any input. A block inserted between a setup and
   -- its assertions has to bring its own name.
   put axScrapeParse("{" & quote & "items" & quote & ":[{" & quote & "identifier" & quote & ":" & quote & "a" & quote & "," & quote & "subject" & quote & ":[" & quote & "x" & quote & "," & quote & "y" & quote & "]},{" & quote & "identifier" & quote & ":" & quote & "b" & quote & "}]," & quote & "count" & quote & ":2," & quote & "cursor" & quote & ":" & quote & "W3siaWQiOjF9XQ==" & quote & "," & quote & "total" & quote & ":17}") into tScrape
   axtCheck tScrape is an array, "a scrape page parses"
   axtCheck tScrape["count"] is 2, "scrape: count"
   axtCheck tScrape["total"] is 17, "scrape: total"
   axtCheck tScrape["cursor"] is "W3siaWQiOjF9XQ==", "scrape: the cursor"
   axtCheck axFirst(tScrape["items"][2]["identifier"]) is "b", "scrape: items in order"
   axtCheck axtJoinLines(tScrape["items"][1]["subject"], "|") is "x|y", "scrape: a multi-valued field is lines"
   put axScrapeParse("{" & quote & "items" & quote & ":[]," & quote & "count" & quote & ":0}") into tScrape
   axtCheck tScrape["cursor"] is empty, "scrape: the last page has no cursor"
   axtCheck axScrapeParse("{" & quote & "error" & quote & ":" & quote & "bad" & quote & "}") is empty, "scrape: the error shape refuses"
   axtCheck axScrapeParse("[]") is empty, "scrape: a body without items refuses"
   axtCheck tResult["docs"][3]["subject"] is "single string subject", "a scalar subject is one line"
   axtCheck tResult["docs"][3]["creator"] is empty, "an absent field is empty"
   put axSearchParse(axtHex(kAxVecFixEtreeSearchHex)) into tResult
   put axDocsTable(tResult, "identifier,creator,date,source,downloads") into tTable
   axtCheck tTable is axtHex(kAxVecEtreeDocsTableHex), "axDocsTable lays the etree docs out"
   axtCheck the number of lines of tTable is 3, "three rows"
   put axSearchParse(axtHex(kAxVecFixMoviesSearchHex)) into tResult
   axtCheck axtEntryFieldOfDocs(tResult, "mediatype") is kAxVecMoviesDocTypes, "a collection doc is a doc like any other"
   axtCheck axSearchParse(axtHex(kAxVecFixSearchErrorHex)) is empty, "the site's error shape refuses"
   axtCheck axLastError() begins with "Archive.org rejected the query", "and quotes the site"
   axtCheck axSearchParse("{}") is empty, "a body without response.docs refuses"
   axtCheck axSearchParse("not json") is empty, "a non-JSON body refuses"
   put axItemParse(axtHex(kAxVecFixLibrivoxItemHex)) into tItem
   axtCheck tItem is an array, "the librivox item fixture parses"
   axtCheck tItem["identifier"] is "pride_prejudice_test", "identifier"
   axtCheck axtJoinLines(tItem["metadata"]["creator"], "|") is kAxVecLibrivoxCreator, "metadata creator lines"
   axtCheck tItem["filesCount"] is kAxVecLibrivoxFilesCount, "filesCount"
   axtCheck tItem["files"][1]["name"] is "pp_03_austen_64kb.mp3", "the first file (the fixture is out of order on purpose)"
   axtCheck tItem["server"] is "ia800000.us.archive.org", "server"
   axtCheck tItem["itemSize"] is "100000000", "itemSize"
   put axItemParse(axtHex(kAxVecFixEtreeItemHex)) into tItem
   axtCheck axtJoinLines(tItem["metadata"]["setlist"], "|") is kAxVecEtreeSetlist, "an array setlist is lines"
   axtCheck axYearOf(tItem["metadata"]["date"]) is kAxVecEtreeYear, "the year of the show"
   axtCheck axItemParse(axtHex(kAxVecFixMissingItemHex)) is empty, "a missing item ({}) refuses"
   axtCheck axLastError() contains "could not be found", "and says so"
end axtTestResponses

private function axtEntryFieldOfDocs pResult, pField
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pResult["count"]
      if tI > 1 then
         put "|" after tOut
      end if
      put axFirst(pResult["docs"][tI][pField]) after tOut
   end repeat
   return tOut
end axtEntryFieldOfDocs

-- ==========================================================================
-- 10. File rules: accept tests, stems, titles, labels, tags.
-- ==========================================================================

private command axtTestFileRules
   local tFile
   axtSection "file rules"
   axtCheck axFileExtension("A/B.Tar.GZ") is "gz", "axFileExtension is the last, lowered"
   axtCheck axFileExtension("noext") is empty, "axFileExtension of none"
   axtCheck axFileIsAudio(axtSampleFile("a_64kb.mp3", "64Kbps MP3", empty, empty)) is true, "audio: a 64k mp3"
   axtCheck axFileIsAudio(axtSampleFile("a.ogg", "Ogg Vorbis", empty, empty)) is true, "audio: ogg"
   axtCheck axFileIsAudio(axtSampleFile("a.mp3", empty, empty, empty)) is true, "audio: a missing format is accepted"
   axtCheck axFileIsAudio(axtSampleFile("a_64kb_mp3.zip", "64Kbps MP3 ZIP", empty, empty)) is false, "audio: a zip of mp3s is not"
   axtCheck axFileIsAudio(axtSampleFile("a_64kb.m3u", "64Kbps M3U", empty, empty)) is false, "audio: a playlist is not"
   axtCheck axFileIsAudio(axtSampleFile("a_spectrogram.png", "Spectrogram", empty, empty)) is false, "audio: a spectrogram is not"
   axtCheck axFileIsAudio(axtSampleFile("a.mp3", "Metadata", empty, empty)) is false, "audio: the format veto beats the extension"
   axtCheck axFileIsAudio(axtSampleFile(empty, "VBR MP3", empty, empty)) is false, "audio: no name is not"
   axtCheck axFileIsVideo(axtSampleFile("Show_E01.mp4", "h.264", empty, "80000000")) is true, "video: an mp4"
   axtCheck axFileIsVideo(axtSampleFile("clip.avi", empty, empty, "5000000")) is true, "video: a tolerated extension"
   axtCheck axFileIsVideo(axtSampleFile("Show_E01.en.vtt", "WebVTT", empty, "20000")) is false, "video: captions are not"
   axtCheck axFileIsVideo(axtSampleFile("Show_E02.mp4.ia", "h.264 IA", empty, "150000")) is false, "video: a .ia placeholder is not"
   axtCheck axFileIsVideo(axtSampleFile("tiny.mp4", "h.264", empty, "50000")) is false, "video: under 100 KB is a placeholder"
   axtCheck axFileIsVideo(axtSampleFile("__ia_thumb.jpg", "Item Tile", empty, "9000")) is false, "video: the item tile is not"
   axtCheck axFileIsVideo(axtSampleFile("x_files.xml", "Metadata", empty, "4000")) is false, "video: a sidecar is not"
   axtCheck axFileIsDocument(axtSampleFile("book.pdf", "Text PDF", empty, empty)) is true, "document: a pdf"
   axtCheck axFileIsDocument(axtSampleFile("book_djvu.txt", "DjVuTXT", empty, empty)) is true, "document: the OCR text"
   axtCheck axFileIsDocument(axtSampleFile("book_abbyy.gz", "Abbyy GZ", empty, empty)) is false, "document: the OCR working file is not"
   axtCheck axFileIsImage(axtSampleFile("cover.jpg", "JPEG", "original", empty)) is true, "image: a jpeg"
   axtCheck axFileIsImage(axtSampleFile("__ia_thumb.jpg", "Item Tile", empty, empty)) is false, "image: the item tile is not"
   axtCheck axFileIsContent(axtSampleFile("anything.bin", "Unknown", empty, empty)) is true, "content: anything not a sidecar"
   axtCheck axFileIsContent(axtSampleFile("x_meta.xml", "Metadata", empty, empty)) is false, "content: a sidecar is not"
   axtCheck axFileIsContent(axtSampleFile("x_archive.torrent", "Archive BitTorrent", empty, empty)) is false, "content: a torrent is not"
   axtCheck axFileStem("pp_01_austen_64kb.mp3") is "pp_01_austen", "axFileStem strips _64kb"
   axtCheck axFileStem("pp_01_austen.ogg") is "pp_01_austen", "axFileStem strips the extension"
   axtCheck axFileStem("PP_01_austen_VBR.mp3") is "pp_01_austen", "axFileStem lowers and strips _vbr"
   axtCheck axFileStem("song_original.flac") is "song", "axFileStem strips _original"
   axtCheck axFileStem("song_12345kb.mp3") is "song_12345kb", "axFileStem keeps a long digit run"
   axtCheck axVideoStem("episode_archive_h264.mp4") is "episode", "axVideoStem strips stacked suffixes"
   axtCheck axVideoStem("Show_E01_512kb.mp4") is axVideoStem("Show_E01.mp4"), "axVideoStem unites the encodes"
   axtCheck axVideoStem("film.1080p.webm") is "film", "axVideoStem strips a resolution tag"
   axtCheck axPrettyName("pp_01_austen_64kb.mp3") is "pp 01 austen", "axPrettyName"
   axtCheck axPrettyName("dir/sub_ch_01_vbr.mp3") is "sub ch 01", "axPrettyName drops the directory"
   axtCheck axPrettyName("___.mp3") is "___.mp3", "axPrettyName falls back to the name"
   axtCheck axTrackTitleClean("d1t01 Scarlet_Begonias") is "Scarlet Begonias", "axTrackTitleClean strips d1t01"
   axtCheck axTrackTitleClean("T03-Fire_On_The_Mountain") is "Fire On The Mountain", "axTrackTitleClean strips t03 and a dash"
   axtCheck axTrackTitleClean("Plain Title") is "Plain Title", "axTrackTitleClean leaves a plain title"
   axtCheck axTrackTitleClean(empty) is empty, "axTrackTitleClean of empty"
   axtCheck axCleanTitle("Show_E01.mp4", "Show") is "E01", "axCleanTitle drops the item title"
   axtCheck axCleanTitle("nightofthelivingdead.mp4", "Night of the Living Dead") is "Untitled", "axCleanTitle: nothing left is Untitled"
   -- the film club's prefix test compares the item title's letters and digits
   -- against the file name as written, so a separator in the name defeats it
   -- and the name survives as the title. The first engine run (2026-09-15)
   -- caught this line expecting Untitled for the underscored name; the
   -- expectation was wrong, not the library (the oracle agrees).
   axtCheck axCleanTitle("night_of_the_living_dead.mp4", "Night of the Living Dead") is "night of the living dead", "axCleanTitle: a separator in the name defeats the prefix test"
   axtCheck axCleanTitle("reel-2_part-b.ogv", empty) is "reel 2 part b", "axCleanTitle without an item title"
   axtCheck axQualityLabel("Show_E01_512kb.mp4") is "SD", "axQualityLabel 512kb"
   axtCheck axQualityLabel("film_1080p.mp4") is "1080p", "axQualityLabel 1080p"
   axtCheck axQualityLabel("film_h264.mp4") is "H.264", "axQualityLabel h264"
   axtCheck axQualityLabel("film.mp4") is "Auto", "axQualityLabel default"
   axtCheck axSubjectTags("librivox; audiobooks; literature; ghost stories", 2) is "Ghost stories", "axSubjectTags drops the noise"
   axtCheck axSubjectTags("fiction" & return & "Fiction" & return & "poetry", 2) is "Fiction" & return & "Poetry", "axSubjectTags de-duplicates"
   axtCheck axSubjectTags("Fiction" & return & "Romance" & return & "Audiobook" & return & "A very long subject name that exceeds twenty characters", 2) is "Fiction" & return & "Romance", "axSubjectTags caps at two"
   axtCheck axSubjectTags(empty, 2) is empty, "axSubjectTags of empty"
   axtCheck axSubjectTags("xxxxxxxxxxxxxxxxxxxx", 2) is empty, "axSubjectTags: twenty characters is too long"
   axtCheck axSubjectTags("a|b", 3) is "A" & return & "B", "axSubjectTags splits on a pipe"
end axtTestFileRules

-- ==========================================================================
-- 11. Playlists over the fixtures.
-- ==========================================================================

private command axtTestPlaylists
   local tItem, tPlaylist, tTable
   axtSection "playlists (synthetic fixtures)"
   axtCheck axPlaylistKindFor("etree", empty) is "audio-tracks", "kind for etree"
   axtCheck axPlaylistKindFor("librivox", empty) is "audio-chapters", "kind for librivox"
   axtCheck axPlaylistKindFor("movies", empty) is "video", "kind for movies"
   axtCheck axPlaylistKindFor("any", "texts") is "documents", "kind for a texts item"
   axtCheck axPlaylistKindFor("any", "image") is "images", "kind for an image item"
   axtCheck axPlaylistKindFor("any", "software") is "files", "kind for software"
   put axItemParse(axtHex(kAxVecFixLibrivoxItemHex)) into tItem
   put axPlaylist(tItem, "audio-chapters") into tPlaylist
   axtCheck tPlaylist["count"] is 5, "five chapters from thirty-six files"
   axtCheck axtEntryField(tPlaylist, "name") is kAxVecLibrivoxChapterNames, "chapters: the chosen encodes, in track order"
   axtCheck axtEntryField(tPlaylist, "title") is axtHex(kAxVecLibrivoxChapterTitlesHex), "chapters: titles from the originals"
   axtCheck axtEntryField(tPlaylist, "track") is kAxVecLibrivoxChapterTracks, "chapters: track numbers (4/5 reads as 4)"
   axtCheck axtEntryField(tPlaylist, "length") is kAxVecLibrivoxChapterLengths, "chapters: lengths"
   axtCheck tPlaylist["entries"][1]["url"] is "https://archive.org/download/pride_prejudice_test/pp_01_austen_64kb.mp3", "chapters: the stream url"
   axtCheck tPlaylist["entries"][1]["direct"] is "https://ia800000.us.archive.org/1/items/pride_prejudice_test/pp_01_austen_64kb.mp3", "chapters: the datanode url"
   put axPlaylistTable(tPlaylist) into tTable
   axtCheck the number of lines of tTable is 5, "axPlaylistTable: one line per chapter"
   axtCheck line 1 of tTable begins with "1" & tab & "01 - Chapter 1" & tab & "10:00" & tab, "axPlaylistTable: number, title, duration"
   put axItemParse(axtHex(kAxVecFixEtreeItemHex)) into tItem
   put axPlaylist(tItem, "audio-tracks") into tPlaylist
   axtCheck tPlaylist["count"] is 6, "six tracks across two discs"
   axtCheck axtEntryField(tPlaylist, "name") is kAxVecEtreeTrackNames, "tracks: VBR MP3 chosen, disc order kept"
   axtCheck axtEntryField(tPlaylist, "title") is kAxVecEtreeTrackTitles, "tracks: titles, the derivative-only one prettified"
   axtCheck axtEntryField(tPlaylist, "length") is kAxVecEtreeTrackLengths, "tracks: every length form parsed"
   axtCheck axtEntryField(tPlaylist, "format") is kAxVecEtreeTrackFormats, "tracks: formats"
   axtCheck tPlaylist["entries"][1]["url"] is kAxVecEtreeTrackOneUrl, "tracks: the stream url"
   put axPlaylist(tItem, "auto") into tPlaylist
   axtCheck tPlaylist["kind"] is "audio-tracks", "auto picks audio-tracks for an etree item"
   put axItemParse(axtHex(kAxVecFixMoviesItemHex)) into tItem
   put axPlaylist(tItem, "video") into tPlaylist
   axtCheck tPlaylist["count"] is 3, "three episodes from the encodes"
   axtCheck axtEntryField(tPlaylist, "name") is kAxVecMoviesEpisodeNames, "episodes: the largest mp4 wins"
   axtCheck axtEntryField(tPlaylist, "title") is kAxVecMoviesEpisodeTitles, "episodes: titles"
   axtCheck axtEntryField(tPlaylist, "quality") is kAxVecMoviesEpisodeQuality, "episodes: quality labels"
   axtCheck axtJoinLines(tPlaylist["entries"][1]["variants"], ";") is kAxVecMoviesVariantsOne, "episodes: every encode as a variant, best first"
   put axPlaylistTable(tPlaylist) into tTable
   axtCheck line 1 of tTable ends with tab & "Auto", "axPlaylistTable carries the quality for video"
   put axPlaylist(tItem, "auto") into tPlaylist
   axtCheck tPlaylist["kind"] is kAxVecMoviesAutoKind, "auto picks video for a movies item"
   put axItemParse(axtHex(kAxVecFixTextsItemHex)) into tItem
   put axPlaylist(tItem, "auto") into tPlaylist
   axtCheck tPlaylist["kind"] is kAxVecTextsAutoKind, "auto picks documents for a texts item"
   axtCheck axtEntryField(tPlaylist, "name") is kAxVecTextsDocNames, "documents: pdf first, then epub, then text"
   put axPlaylist(tItem, "images") into tPlaylist
   axtCheck axtEntryField(tPlaylist, "name") is kAxVecTextsImageNames, "images: the cover, not the tile"
   put axPlaylist(tItem, "files") into tPlaylist
   axtCheck tPlaylist["count"] is kAxVecTextsFilesCount, "files: everything but the sidecars"
   axtCheck axPlaylist(tItem, "audio-tracks") is empty, "no audio in a texts item"
   axtCheck axLastError() contains "no audio-tracks file", "and says so"
   axtCheck axPlaylistTable(empty) is empty, "axPlaylistTable of nothing"
end axtTestPlaylists

-- ==========================================================================
-- 12. The fetch layer, offline: every handler driven with an input it
-- must refuse, so nothing is ever loaded.
-- ==========================================================================

private command axtTestFetchLayerOffline
   local tOptions, tError, tPendingBefore
   axtSection "fetch layer, offline refusals"
   -- The host may have a request in flight (the demo runs this harness from
   -- a button, mid-search on 2026-09-15), so every pending check is a DELTA
   -- against the count on entry, not an absolute zero. axShutdown at the end
   -- still forgets the host's requests - their late replies are dropped.
   put axPending() into tPendingBefore
   axInit the long id of me
   axtCheck true, "axInit accepts an owner"
   axSetCallback "onArchive"
   axSetTimeout 45
   axSetTimeout "soon"
   axSetMaxBody 65536
   axSetMaxBody 12
   axtCheck axPending() is tPendingBefore, "nothing new is pending"
   axtCheck axSearch(empty, tOptions) is empty, "axSearch refuses an empty query before loading"
   axtCheck axLastError() contains "empty", "and says why"
   put "ten" into tOptions["rows"]
   axtCheck axSearch("x", tOptions) is empty, "axSearch refuses bad rows before loading"
   axtCheck axFetchItem("../etc", empty) is empty, "axFetchItem refuses a bad identifier before loading"
   axtCheck axFetchUrl("ftp://x", empty) is empty, "axFetchUrl refuses a non-http url"
   axtCheck axLastError() contains "http", "and says why"
   axtCheck axPending() is tPendingBefore, "still nothing new is pending"
   axCancel 999
   axCancel empty
   axtCheck true, "axCancel of an unknown handle is a clean no-op"
   put empty into tError
   try
      axUrlDone "https://nobody.invalid/late", "cached"
   catch tError
   end try
   axtCheck tError is empty, "a late reply for nobody is dropped without a throw"
   axDeadline 999
   axtCheck true, "axDeadline of an unknown handle is a clean no-op"
   axtCheck axDownload("ftp://x", "somewhere", empty) is empty, "axDownload refuses a non-http url before loading"
   axtCheck axDownload("https://nobody.invalid/f", empty, empty) is empty, "axDownload refuses an empty path before loading"
   axtCheck axLastError() contains "path", "and says why"
   axtCheck axPending() is tPendingBefore, "no download was started"
   put empty into tError
   try
      axUrlStatus "https://nobody.invalid/f", "loading,1,2"
      axDownloadDone "https://nobody.invalid/f", "downloaded"
   catch tError
   end try
   axtCheck tError is empty, "a status and a completion for nobody are dropped without a throw"
   axtCheck axDownloadSync("not a url", "somewhere") is empty, "axDownloadSync refuses a non-url"
   axtCheck axDownloadSync("https://nobody.invalid/f", empty) is empty, "axDownloadSync refuses an empty path"
   axtCheck axGetSync("not a url") is empty, "axGetSync refuses a non-url"
   axtCheck axSearchSync(empty, tOptions) is empty, "axSearchSync refuses an empty query"
   axtCheck axFetchItemSync("x y") is empty, "axFetchItemSync refuses a bad identifier"
   axCancelAll
   axShutdown
   axShutdown
   axtCheck axPending() is 0, "axShutdown twice leaves nothing pending"
end axtTestFetchLayerOffline

-- <<< END EMBEDDED LIBRARIES <<<

-- ==========================================================================
-- Gallery constants and state.
-- ==========================================================================

-- Bumped whenever the generated UI changes so a saved stack rebuilds.
-- agBuild rebuilds only when the stack's stored version differs, so a
-- control added without touching this line is never created on a stack
-- somebody already opened once (the explorer shipped exactly that bug on
-- 2026-09-15 and the boot self-check is what caught it).
constant kAgUiVersion = "archive-gallery-kit2-1"
constant kAgWinW = 1180
constant kAgWinH = 630

-- THE GRID, RESIZED 2026-09-20 AFTER THE FIRST ENGINE RUN. It was five
-- across and two down, because ten tiles at 212x150 read well - and ten
-- was also, wrongly, the SEARCH page size, so a query answering 29,281
-- hits showed ten of them and offered Next. "Some results could be
-- hundreds of items" is the report that followed, and it is two separate
-- limits wearing one number.
--
-- The tile size is now measured rather than chosen: the item image
-- service answered 180x124 on that run, so a cell near 130x96 shows the
-- site's own derivative at roughly 1:1 with no upscaling, and eight
-- across by three down fits the same panel. Twenty-four tiles, and the
-- SEARCH page is no longer tied to them at all (kAgPageSize below).
--
-- Every rect in the build comes out of these, so moving the grid stays an
-- arithmetic change and not an editing pass.
constant kAgCols = 8
constant kAgGridRows = 3
constant kAgTiles = 24
constant kAgTileW = 130
constant kAgTileH = 96
constant kAgCapH = 30
constant kAgColStep = 142
constant kAgRowStep = 132
constant kAgCol0 = 28
constant kAgRow0 = 96

-- HOW MANY RESULTS ONE REQUEST BRINGS BACK, which is a different question
-- from how many tiles there are. A page of 96 is four screens of 24 held
-- in memory, so Prev and Next walk them with no network at all and the
-- site is asked once per four screens. archive.org's advancedsearch has
-- no small cap here - axSearchUrl passes rows straight through - and the
-- three source apps used 10 and 24 only because their own pages did.
constant kAgPageSize = 96

-- The site's own paging wall: advancedsearch.php will not page past the
-- first 10,000 hits whatever rows and page say. A search with more hits
-- than that is not truncated data, it is a deep-paging limit, and the
-- page label says so rather than offering a Next that would come back
-- empty. axScrapeUrl is the cursor API that walks further; the gallery
-- does not use it yet (archivext/docs/07-open-questions.md).
constant kAgDeepWall = 10000

-- The pane rect both panels share. Named because the boot self-check
-- bounds the bottom row's captions against it, and a bound spelled twice
-- is a bound that goes stale on one side (this file's own CLAUDE.md keeps
-- a list of hand-copied numbers that did).
constant kAgPaneL = 16
constant kAgPaneT = 88
constant kAgPaneR = 1164
constant kAgPaneB = 500

-- The viewer's dark stage: the one rect the player and the big image
-- share, inset by four pixels so the stage reads as a frame around both.
constant kAgStageL = 32
constant kAgStageT = 100
constant kAgStageR = 716
constant kAgStageB = 458

-- The player is named through a constant ON PURPOSE. The boot self-check
-- derives its control list from every literal control name in this script
-- (tools/check-demo-control-lists.py), and the player is created on demand
-- inside a try - an engine with no media support simply never makes one -
-- so a literal would put a name in the list that boot can legitimately not
-- find. The big image is the other way round: it is built by agBuild on
-- every engine, so it IS named literally and IS checked at boot.
constant kAgPlayerName = "agPlayer"

-- HOW LOUD, and why this is a constant rather than a default.
--
-- The 2026-09-20 engine run opened three MP3 streams: the player reported
-- a duration, playStarted fired, and currentTime had advanced six seconds
-- when the check looked - and the reader heard nothing. A player that is
-- demonstrably running and silent is the shape of a LOUDNESS problem, and
-- this stack had never set one: it took whatever the engine's own
-- `the playLoudness` happened to be, which is global state another stack
-- or the IDE can have left at 0.
--
-- docs/OXT-ENGINE-NOTES.md 5.4 is the standing rule for this property and
-- it is narrow: playLoudness is a REQUEST, not a register - Linux reads
-- it back as a constant 0 whatever was written. So the gallery SETS it,
-- on the player and on the engine, and REPORTS what it reads back
-- without ever deciding anything from the answer.
constant kAgLoudness = 100

-- The two tag words a raw reply can carry. A tag is
-- "<word> <serial> <index>": which picture, which search, which slot.
constant kAgThumbTag = "thumb"
constant kAgBigTag = "big"

-- ITEM METADATA COMES BACK AS RAW BYTES, not through the library's
-- `item` kind, and the reason is the cache: the `item` kind delivers a
-- PARSED array and the raw JSON is gone by then, so there is nothing to
-- write to disk. axItemParse is public, the demo calls it itself, and the
-- bytes go in the cache on the way past. (The async `item` kind is not
-- left unexercised by this: the explorer demo drives it, and this stack
-- drove it on 2026-09-20 before the cache existed.)
constant kAgMetaTag = "meta"

-- A picture the viewer will not pull into memory, RAISED 2026-09-20 with
-- the grid. The first engine run pulled a 1,180,947-byte JPEG into an
-- image object without trouble, and archive.org's scans routinely run to
-- tens of megabytes, so the old 12 MB was refusing pictures this engine
-- can plainly show. The library's own body cap is raised to sit ABOVE
-- this one in agStart, so the thing that refuses a picture is always this
-- constant with its own sentence, never the transport with a sentence
-- about a reply being too large.
constant kAgBigMax = 33554432
constant kAgBodyMax = 50331648

-- THE THUMBNAIL QUEUE. Twenty-four tiles is twenty-four requests, and the
-- only concurrency this suite has ever measured is the ten the first
-- engine run happened to fire (docs/OXT-ENGINE-NOTES.md 6.9 records what
-- libURL does with one URL, not with twenty-four). So the grid asks for a
-- few at a time and starts the next when one lands: a screen still fills
-- in a second or two, and nothing here is betting on an unmeasured number.
constant kAgFetchMax = 6

-- WHAT THIS STACK REMEMBERS, AND WHERE.
--
-- archive.org is a public service run on donations, and a gallery is the
-- shape of client most likely to abuse it: a screen of twenty-four
-- thumbnails, a reader stepping back and forth, an identifier opened
-- twice. So nothing here is asked for twice if it can be helped, on two
-- tiers.
--
--   MEMORY   thumbnails by identifier, item metadata by identifier, and
--            search pages by their exact request URL. Gone when the stack
--            closes, which is correct for the third: result order and
--            counts move under you, so a search page is a thing to reuse
--            for a minute, not for a week.
--   DISK     thumbnails and item metadata, under the same
--            Documents/ArchiveXT folder Download writes to, so reopening
--            the stack tomorrow costs the site nothing for anything it
--            already answered. Search pages are deliberately NOT written
--            there, for the reason above.
--
-- A thumbnail is named by its identifier and cannot go stale, so it has
-- no expiry; metadata can gain files, so a cached item is re-fetched
-- after kAgMetaTtl seconds. The stamp is written INTO the file rather
-- than read from its modification date, because date formats are the
-- engine's and this needs no engine pass to be right.
constant kAgCacheMax = 12000000
constant kAgMetaMax = 8000000
constant kAgSearchKeep = 12
constant kAgMetaTtl = 604800

local sAgFamily              -- the family id in play (movies / etree / librivox / images / any)
local sAgPage                -- the search page shown
local sAgSerial              -- bumped by every search STARTED; a thumbnail carrying an older one is dropped
local sAgViewSerial          -- the same idea for the VIEWER's picture, which a search does not invalidate but an item open does
local sAgResult              -- the last axSearchParse array
local sAgTileIds             -- one identifier per line, in tile order ("" for an empty tile)
local sAgOffset              -- the index into the loaded page of the first tile shown
local sAgOffsetWanted        -- the offset to land on when the page being fetched arrives
local sAgQueue               -- thumbnails waiting to be asked for: "<tile> <url>" per line
local sAgInFlight            -- how many thumbnail requests are out right now
local sAgCache               -- sAgCache[identifier] is that thumbnail's bytes
local sAgCacheKeys           -- the identifiers in arrival order, for eviction
local sAgCacheBytes          -- what the thumbnail cache is holding
local sAgMeta                -- sAgMeta[identifier] is that item's raw metadata JSON
local sAgMetaKeys            -- the identifiers in arrival order, for eviction
local sAgMetaBytes           -- what the metadata cache is holding
local sAgSearch              -- sAgSearch[url] is that request's parsed result
local sAgSearchKeys          -- the urls in arrival order, for eviction
local sAgDisk                -- the disk cache folder, or empty when there is none
local sAgHits                -- answers served without asking the site
local sAgMisses              -- answers that cost a request
local sAgSaved               -- bytes the site did not have to send
local sAgTilePics            -- sAgTilePics[i] is "true" once tile i holds a real picture
local sAgItem                -- the last axItemParse array
local sAgPlaylist            -- that item's playlist
local sAgKind                -- the playlist kind in play
local sAgPane                -- "grid" or "viewer"
local sAgSearchHandle        -- the search in flight, or empty
local sAgSearchUrl           -- the URL that search went to, which is the cache's key
local sAgItemHandle          -- the metadata fetch in flight, or empty
local sAgThumbHandles        -- the thumbnail requests in flight, comma list
local sAgBigHandle           -- the viewer picture in flight, or empty
local sAgLastPicUrl          -- the last full picture shown, kept so stepping back costs nothing
local sAgLastPicData
local sAgDownloadHandle      -- the download in flight, or empty
local sAgDownloadPath        -- where that download is being written
local sAgPlayAfter           -- true when the finished download should play
local sAgPlayUrl             -- the URL or path the player was last handed (empty after Stop)
local sAgPlayIsFile          -- true when that was a LOCAL file, which is what stops the ladder
local sAgPlayRetried         -- true once the http retry below has been spent on this entry
local sAgLoudness            -- what the volume buttons have asked for
local sAgHaveUrlLib          -- the boot probe's answer

-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

-- ==========================================================================
-- Lifecycle and the click router.
-- ==========================================================================

on openStack
   agBuild
   agStart
   agScRun
end openStack

on closeStack
   agStop
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   -- The tiles first: every tile control is named "agTile<Part><index>",
   -- and all three parts are nine characters, so one test covers the
   -- picture, the caption and the frame a reader might click.
   if tName begins with "agTile" then
      agOpenTile agTileIndexOf(tName)
   else if tName is "agFamMovies" then
      agSetFamily "movies"
   else if tName is "agFamEtree" then
      agSetFamily "etree"
   else if tName is "agFamLibrivox" then
      agSetFamily "librivox"
   else if tName is "agFamImages" then
      agSetFamily "images"
   else if tName is "agFamAny" then
      agSetFamily "any"
   else if tName is "agSearch" then
      agDoSearch 1
   else if tName is "agPrev" then
      agStepScreen -1
   else if tName is "agNext" then
      agStepScreen 1
   else if tName is "agBack" then
      agShowPane "grid"
   else if tName is "agLouder" then
      agSetLoudness 20
   else if tName is "agQuieter" then
      agSetLoudness -20
   else if tName is "agTracks" then
      agSelectTrack
   else if tName is "agPlay" then
      agDoPlay
   else if tName is "agStopPlay" then
      agDoStopPlay
   else if tName is "agDownload" then
      agDoDownload false
   else if tName is "agOpenPage" then
      agDoOpenPage
   else if tName is "agCopyUrl" then
      agDoCopyUrl
   else if tName is "agTests" then
      agDoSelfTest
   else if tName is "agProbe" then
      agDoProbe
   else
      pass mouseUp
   end if
end mouseUp

function agTileIndexOf pName
   -- "agTileImg7" -> 7. Zero for anything that is not a tile control, so
   -- a click on a name that merely starts the same way is a no-op rather
   -- than an index nobody meant.
   local tIndex
   put char 10 to -1 of pName into tIndex
   if tIndex is not an integer then
      return 0
   end if
   if tIndex < 1 then
      return 0
   end if
   if tIndex > kAgTiles then
      return 0
   end if
   return tIndex
end agTileIndexOf

-- ==========================================================================
-- Build: the whole window, in script, kit look, inside the 720p budget.
-- One card carrying TWO panes at the same rect - the grid and the viewer -
-- because the engine has no reparenting and a name prefix is what a screen
-- is here (the coin wallet's ten-screen sweep, one demo smaller).
-- ==========================================================================

command agBuild
   local tI, tName, tRect
   if the uAgUiVersion of this stack is kAgUiVersion and there is a field "agLog" then
      exit agBuild
   end if
   lock screen
   agClearGeneratedUI
   uiChrome "ArchiveXT gallery - archive.org as pictures", kAgWinW, kAgWinH
   -- The control bar: one row, always visible, both panes under it.
   uiButton "agFamMovies", "Films + video", "16,58,132,82"
   uiButton "agFamEtree", "Live music", "136,58,236,82"
   uiButton "agFamLibrivox", "Audiobooks", "240,58,344,82"
   uiButton "agFamImages", "Images", "348,58,426,82"
   uiButton "agFamAny", "Everything", "430,58,524,82"
   uiInput "agQuery", "532,58,806,82"
   uiButton "agSearch", "Search", "812,58,886,82"
   uiButton "agPrev", "Prev", "890,58,942,82"
   uiButton "agNext", "Next", "946,58,998,82"
   uiLabel "agPageInfo", "no search yet", "1004,62,1164,80", 10
   set the foregroundColor of field "agPageInfo" to kUiMuted
   -- BOTH panels before any control on either: a kit panel is chrome and
   -- has to stay behind what sits on it, and building them together is
   -- what keeps the two panes' z-order from depending on build order.
   put kAgPaneL & comma & kAgPaneT & comma & kAgPaneR & comma & kAgPaneB into tRect
   uiPanel "agGridPanel", tRect
   uiPanel "agViewPanel", tRect
   -- The grid. Names are COMPUTED, so the derived control list does not
   -- carry them and the boot self-check asks about them in its own line.
   repeat with tI = 1 to kAgTiles
      put agTileRect(tI) into tRect
      put "agTileBox" & tI into tName
      uiGfx tName, tRect
      set the roundRadius of graphic tName to 8
      set the filled of graphic tName to true
      set the backgroundColor of graphic tName to kUiCodeBg
      set the lineSize of graphic tName to 1
      set the foregroundColor of graphic tName to kUiCodeLine
      put "agTileImg" & tI into tName
      if there is no image tName then
         create image
         set the name of the last image to tName
      end if
      set the lockLocation of image tName to true
      set the rect of image tName to tRect
      set the visible of image tName to false
      uiCap ("agTileCap" & tI), empty, agCapRect(tI)
      set the foregroundColor of field ("agTileCap" & tI) to kUiInkSoft
      -- one size down from the kit's caption, because the cell is 130
      -- wide now rather than 212 and two lines have to fit in kAgCapH
      set the textSize of field ("agTileCap" & tI) to 9
   end repeat
   -- The viewer's stage, and the two objects that take turns on it.
   uiGfx "agStage", "28,96,720,462"
   set the roundRadius of graphic "agStage" to 8
   set the filled of graphic "agStage" to true
   set the backgroundColor of graphic "agStage" to "26,30,38"
   set the lineSize of graphic "agStage" to 0
   uiLabel "agStageNote", "select something and press Play", "36,266,712,292", 11
   set the foregroundColor of field "agStageNote" to kUiAccentSub
   set the textAlign of field "agStageNote" to "center"
   if there is no image "agBigImage" then
      create image
      set the name of the last image to "agBigImage"
   end if
   set the lockLocation of image "agBigImage" to true
   set the rect of image "agBigImage" to (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)
   set the visible of image "agBigImage" to false
   uiButton "agPlay", "Play", "28,470,100,494"
   uiButton "agStopPlay", "Stop", "104,470,176,494"
   uiButton "agDownload", "Download", "180,470,276,494"
   uiButton "agOpenPage", "Open page", "280,470,380,494"
   uiButton "agCopyUrl", "Copy URL", "384,470,470,494"
   uiButton "agBack", "Back to the gallery", "474,470,620,494"
   uiButton "agQuieter", "Vol -", "624,470,676,494"
   uiButton "agLouder", "Vol +", "680,470,732,494"
   -- The viewer's right column.
   uiWrap "agItemTitle", "nothing open yet", "730,96,1152,136", 13
   uiArea "agItemMeta", "730,140,1152,254"
   uiLabel "agTracksHead", "#" & tab & "title" & tab & "length" & tab & "format", "730,260,1152,276", 10
   set the tabStops of field "agTracksHead" to "30,300,350"
   set the foregroundColor of field "agTracksHead" to kUiMuted
   uiTable "agTracks", "730,278,1152,430", "30,300,350"
   uiCap "agViewNote", "Play puts a film or a concert in the stack's own player and a photograph in the stack's own image object; Download saves to Documents/ArchiveXT.", "730,436,1152,464"
   -- The log strip, shared by both panes.
   uiSection "agLogCap", "Log", "16,506,200,524"
   uiButton "agProbe", "Live probe", "930,504,1046,526"
   uiButton "agTests", "Run axSelfTest", "1050,504,1164,526"
   uiArea "agLog", "16,530,1164,580"
   uiFooter "This stack demonstrates ArchiveXT as a picture gallery: ten thumbnails per search in real engine image objects, then a film or a concert in the engine's own player and a photograph in an image object, all from archive.org's public APIs. It stores nothing and fetches only what you ask for. Verified statically + headless fixtures; needs an OXT pass + a live archive.org pass.", "16,586,1164,626"
   set the uAgUiVersion of this stack to kAgUiVersion
   unlock screen
end agBuild

command agClearGeneratedUI
   -- Rebuild-proof: drop every control this script generates, then let
   -- agBuild remake them.
   repeat while the number of controls of this card > 0
      delete control 1 of this card
   end repeat
end agClearGeneratedUI

function agTileRect pIndex
   -- The picture cell of tile N, row-major. Derived from the grid
   -- constants so nothing in the build hardcodes a tile rect, and written
   -- as a subtract loop rather than div/mod because this member's whole
   -- pure layer stays inside the family interpreter's subset and the
   -- habit is cheaper to keep than to remember.
   local tCol, tRow, tX, tY
   put pIndex - 1 into tCol
   put 0 into tRow
   repeat while tCol >= kAgCols
      add 1 to tRow
      subtract kAgCols from tCol
   end repeat
   put kAgCol0 + tCol * kAgColStep into tX
   put kAgRow0 + tRow * kAgRowStep into tY
   return tX & comma & tY & comma & (tX + kAgTileW) & comma & (tY + kAgTileH)
end agTileRect

function agCapRect pIndex
   -- The caption strip under that cell.
   local tRect, tSaved, tX, tY
   put agTileRect(pIndex) into tRect
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put item 1 of tRect into tX
   put item 4 of tRect into tY
   set the itemDelimiter to tSaved
   return tX & comma & (tY + 2) & comma & (tX + kAgTileW) & comma & (tY + 2 + kAgCapH)
end agCapRect

-- ==========================================================================
-- Start, stop, and the two panes.
-- ==========================================================================

command agStart
   local tCaps
   set the defaultStack to the short name of this stack
   axInit the long id of me
   axSetCallback "onArchive"
   -- ABOVE kAgBigMax ON PURPOSE. The gallery refuses a picture it thinks
   -- is too big to hold, with a sentence naming its size and pointing at
   -- Download; the transport's cap must never get there first, because
   -- its sentence is about a reply rather than about a picture.
   axSetMaxBody kAgBodyMax
   put empty into sAgResult
   put empty into sAgItem
   put empty into sAgPlaylist
   put empty into sAgKind
   put empty into sAgTileIds
   put 0 into sAgOffset
   put empty into sAgOffsetWanted
   put empty into sAgQueue
   put 0 into sAgInFlight
   put empty into sAgCache
   put empty into sAgCacheKeys
   put 0 into sAgCacheBytes
   put empty into sAgMeta
   put empty into sAgMetaKeys
   put 0 into sAgMetaBytes
   put empty into sAgSearch
   put empty into sAgSearchKeys
   put 0 into sAgHits
   put 0 into sAgMisses
   put 0 into sAgSaved
   agCacheInit
   put empty into sAgSearchHandle
   put empty into sAgSearchUrl
   put empty into sAgItemHandle
   put empty into sAgThumbHandles
   put empty into sAgBigHandle
   put empty into sAgLastPicUrl
   put empty into sAgLastPicData
   put empty into sAgDownloadHandle
   put empty into sAgDownloadPath
   put empty into sAgPlayAfter
   put empty into sAgPlayUrl
   put empty into sAgPlayIsFile
   put empty into sAgPlayRetried
   put kAgLoudness into sAgLoudness
   put 0 into sAgSerial
   put 0 into sAgViewSerial
   put 1 into sAgPage
   put axProbeCapabilities() into tCaps
   put tCaps["hasUrlLib"] is true into sAgHaveUrlLib
   agClearTiles
   agShowPane "grid"
   agSetFamily "movies"
   if sAgHaveUrlLib is true then
      uiStatus "Ready - " & axVersion() & " over " & tCaps["urlLibVersion"] & " - pick a family and press Search", "ok"
   else
      agLog "The Internet library (libURL) did not answer: searches will refuse. A standalone needs the Internet inclusion."
      uiStatus "Ready, but no Internet library on this engine - searches will refuse (fail closed)", "warn"
   end if
end agStart

command agStop
   -- Guarded teardown: every request in flight is forgotten (a late reply
   -- is dropped by the layer), the download among them, and the player is
   -- stopped if this engine ever made one.
   local tError
   try
      agCancelThumbs
   catch tError
   end try
   try
      if sAgDownloadHandle is not empty then
         axCancel sAgDownloadHandle
      end if
   catch tError
   end try
   put empty into sAgDownloadHandle
   try
      axShutdown
   catch tError
   end try
   try
      agDoStopPlay
   catch tError
   end try
end agStop

function agGridControls
   -- The grid pane, as "<type> <name>" lines. Built rather than listed
   -- because the tiles are, and a hand-kept twin of a generated set is the
   -- thing this tree keeps learning not to write.
   local tOut, tI
   put "graphic agGridPanel" & return into tOut
   repeat with tI = 1 to kAgTiles
      put "graphic agTileBox" & tI & return after tOut
      put "field agTileCap" & tI & return after tOut
   end repeat
   return tOut
end agGridControls

function agViewControls
   -- The viewer pane, same shape. The tile IMAGES and the big image are
   -- deliberately absent from both lists: an image is shown only when it
   -- holds a picture, which is a question about content and not about
   -- which pane is up.
   return "graphic agViewPanel" & return \
         & "graphic agStage" & return \
         & "field agStageNote" & return \
         & "field agItemTitle" & return \
         & "field agItemMeta" & return \
         & "field agTracksHead" & return \
         & "field agTracks" & return \
         & "field agViewNote" & return \
         & "button agPlay" & return \
         & "button agStopPlay" & return \
         & "button agDownload" & return \
         & "button agOpenPage" & return \
         & "button agCopyUrl" & return \
         & "button agBack"
end agViewControls

command agSetVisible pList, pVisible
   -- Show or hide a "<type> <name>" list, guarded per control: a pane
   -- swept before its build finished must not throw, because the sweep is
   -- what the boot self-check runs through.
   local tLine, tType, tName
   repeat for each line tLine in pList
      put word 1 of tLine into tType
      put word 2 of tLine into tName
      if tType is "field" then
         if there is a field tName then
            set the visible of field tName to pVisible
         end if
      else if tType is "button" then
         if there is a button tName then
            set the visible of button tName to pVisible
         end if
      else if tType is "graphic" then
         if there is a graphic tName then
            set the visible of graphic tName to pVisible
         end if
      else if tType is "image" then
         if there is an image tName then
            set the visible of image tName to pVisible
         end if
      end if
   end repeat
end agSetVisible

command agShowPane pWhich
   -- One card, two panes. Nothing is created or destroyed here: the sweep
   -- is visibility only, so a pane can be swept away and back with every
   -- picture it holds still in place.
   local tI, tGrid, tShow
   set the defaultStack to the short name of this stack
   put pWhich into sAgPane
   put (pWhich is "grid") into tGrid
   agSetVisible agGridControls(), tGrid
   agSetVisible agViewControls(), (not tGrid)
   repeat with tI = 1 to kAgTiles
      put false into tShow
      if tGrid is true then
         if sAgTilePics[tI] is "true" then
            put true into tShow
         end if
      end if
      if there is an image ("agTileImg" & tI) then
         set the visible of image ("agTileImg" & tI) to tShow
      end if
   end repeat
   if tGrid is true then
      -- LEAVING THE VIEWER ENDS PLAYBACK, and hiding the player is not
      -- ending it. `stop player` leaves the filename loaded, so the
      -- six-second check's two guards both still pass and it would fire
      -- over a grid the reader is now looking at: a stream that had not
      -- opened would start a download nobody asked for, and a stream that
      -- HAD opened would paint "playing" over a stack where nothing is.
      -- agDoStopPlay establishes this invariant; Back is the one path a
      -- reader actually takes, so it has to keep it too.
      agCancelPlayCheck
      put empty into sAgPlayUrl
      put empty into sAgPlayIsFile
      agHidePlayer
      -- and the picture in flight is for a stage nobody is looking at
      agVoidPicture
      if there is an image "agBigImage" then
         set the visible of image "agBigImage" to false
      end if
   end if
end agShowPane

command agVoidPicture
   -- Every transition that changes WHAT THE STAGE IS ABOUT comes through
   -- here: leaving the viewer, opening another item, asking for another
   -- track. It cancels the fetch AND bumps the viewer serial, because
   -- either alone is not enough - axCancel drops a reply still in flight,
   -- and the serial drops one already sitting in the message queue.
   add 1 to sAgViewSerial
   if sAgBigHandle is not empty then
      axCancel sAgBigHandle
      put empty into sAgBigHandle
   end if
end agVoidPicture

command agStagePrompt pText
   -- The stage with neither object on it: the player hidden, the picture
   -- hidden, one line of text in the middle.
   set the defaultStack to the short name of this stack
   agHidePlayer
   if there is an image "agBigImage" then
      set the visible of image "agBigImage" to false
   end if
   if there is a field "agStageNote" then
      put pText into field "agStageNote"
      set the visible of field "agStageNote" to (sAgPane is "viewer")
   end if
end agStagePrompt

-- ==========================================================================
-- Families, the search, and the grid it fills.
-- ==========================================================================

function agFamilyFor pFamily
   -- The library's four families, plus the gallery's own fifth.
   --
   -- archivext has no `image` family because none of the three apps the
   -- library was written from had a picture app, and that table is theirs.
   -- The site has the mediatype and axPlaylist already knows an "images"
   -- kind, so the whole addition is a scope clause and it belongs to this
   -- demo rather than to the library: widening a member's public table for
   -- one stack is how a member stops describing the thing it was written
   -- from.
   local tInfo
   if pFamily is "images" then
      put "images" into tInfo["id"]
      put "Images" into tInfo["title"]
      put "images" into tInfo["kind"]
      put "mediatype:(image)" into tInfo["scope"]
      put kAgTiles into tInfo["rows"]
      put "identifier,title,creator,date,year,subject,downloads" into tInfo["fields"]
      put "downloads desc" into tInfo["sort"]
      return tInfo
   end if
   return axFamilyInfo(pFamily)
end agFamilyFor

function agPlaylistKindOf pFamily, pMediatype
   if pFamily is "images" then
      return "images"
   end if
   return axPlaylistKindFor(pFamily, pMediatype)
end agPlaylistKindOf

command agSetFamily pFamily
   local tInfo
   set the defaultStack to the short name of this stack
   put agFamilyFor(pFamily) into tInfo
   if tInfo is empty then
      uiStatus "unknown family " & pFamily & ": " & axLastError(), "bad"
      exit agSetFamily
   end if
   put pFamily into sAgFamily
   agPaintFamily
   agShowPane "grid"
   uiStatus tInfo["title"] & " - type something and press Search, or press Search for the family's own top page", "ok"
end agSetFamily

command agPaintFamily
   -- A segmented control made of ordinary buttons, which is the coin
   -- wallet's waPaintChoice shape and the only one this tree has an engine
   -- record for: there is no reparenting here, so the group is a naming
   -- convention plus this handler. Painted from ONE place, all five every
   -- time, rather than a clear-the-old-one pass that can leave two lit -
   -- the wallet's own 2026-09-01 audit found a backend that could never
   -- show as selected because one name was missing from one literal.
   if there is a button "agFamMovies" then
      set the hilite of button "agFamMovies" to (sAgFamily is "movies")
   end if
   if there is a button "agFamEtree" then
      set the hilite of button "agFamEtree" to (sAgFamily is "etree")
   end if
   if there is a button "agFamLibrivox" then
      set the hilite of button "agFamLibrivox" to (sAgFamily is "librivox")
   end if
   if there is a button "agFamImages" then
      set the hilite of button "agFamImages" to (sAgFamily is "images")
   end if
   if there is a button "agFamAny" then
      set the hilite of button "agFamAny" to (sAgFamily is "any")
   end if
end agPaintFamily

command agDoSearch pPage
   local tPage, tSpec, tQuery, tInfo, tOptions, tHandle, tUrl, tCached
   set the defaultStack to the short name of this stack
   put pPage into tPage
   if tPage is not an integer then
      put 1 into tPage
   end if
   if tPage < 1 then
      put 1 into tPage
   end if
   if sAgHaveUrlLib is not true then
      uiStatus "no Internet library on this engine - cannot search", "bad"
      exit agDoSearch
   end if
   put agFamilyFor(sAgFamily) into tInfo
   if tInfo is empty then
      uiStatus "no family is selected: " & axLastError(), "bad"
      exit agDoSearch
   end if
   put tInfo["scope"] into tSpec["base"]
   put field "agQuery" into tSpec["text"]
   put axQueryBuild(tSpec) into tQuery
   if tQuery is empty then
      uiStatus "nothing to search for - pick a family or type something (" & axLastError() & ")", "warn"
      exit agDoSearch
   end if
   put tInfo["fields"] into tOptions["fields"]
   put tInfo["sort"] into tOptions["sort"]
   -- ROWS IS THE PAGE SIZE, NOT THE TILE COUNT, and the two were the same
   -- number until 2026-09-20. They are different questions: how many
   -- results one request brings back, and how many of them fit on screen.
   -- Tying them made a 29,281-hit search fetch ten items and offer Next.
   put kAgPageSize into tOptions["rows"]
   put tPage into tOptions["page"]
   put "gallery" into tOptions["tag"]
   -- ALREADY ANSWERED? A reader stepping back over a page boundary asks
   -- for the same URL again, and the site should not have to answer it
   -- twice in one sitting.
   put axSearchUrl(tQuery, tOptions["fields"], tOptions["sort"], kAgPageSize, tPage) into tUrl
   put agCachedSearch(tUrl) into tCached
   if tCached is an array then
      put tPage into sAgPage
      -- the key travels with the result, or agShowResults would re-cache
      -- this page under the PREVIOUS request's URL
      put tUrl into sAgSearchUrl
      agShowPane "grid"
      agNoteHit 0
      agLog "cache: page " & tPage & " served without asking the site"
      agShowResults tCached
      exit agDoSearch
   end if
   agCancelThumbs
   if sAgSearchHandle is not empty then
      axCancel sAgSearchHandle
      put empty into sAgSearchHandle
      agLog "cancelled the previous search (its late reply will be dropped)"
   end if
   put axSearch(tQuery, tOptions) into tHandle
   if tHandle is empty then
      uiStatus "search refused: " & axLastError(), "bad"
      agLog "axSearch: " & axLastError()
      exit agDoSearch
   end if
   -- The serial is bumped by the search that STARTS, never by the reply
   -- that arrives: ten thumbnails are in flight at once and a reader who
   -- presses Next before they land would otherwise get the old page's
   -- pictures under the new page's captions.
   add 1 to sAgSerial
   put tHandle into sAgSearchHandle
   put tUrl into sAgSearchUrl
   put tPage into sAgPage
   agShowPane "grid"
   agClearTiles
   agNoteMiss
   agLog "q = " & tQuery
   agLog "GET " & tUrl
   uiStatus "searching (request " & tHandle & ")...", "warn"
end agDoSearch

command agShowResults pResult
   -- A PAGE ARRIVED. The page is not the screen: kAgPageSize results are
   -- held here and kAgTiles of them are drawn, so Prev and Next walk the
   -- loaded page with no network at all and the site is asked once every
   -- four screens.
   local tCount, tWant, tUrl
   put pResult into sAgResult
   put pResult["count"] into tCount
   put sAgOffsetWanted into tWant
   put empty into sAgOffsetWanted
   if tWant is not an integer then
      put 0 into tWant
   end if
   -- landing on the LAST screen of a page is how Prev crosses a page
   -- boundary backwards, and the page it lands on may be short
   repeat while tWant >= tCount
      subtract kAgTiles from tWant
   end repeat
   if tWant < 0 then
      put 0 into tWant
   end if
   put tWant into sAgOffset
   -- keyed by the URL THE REQUEST WENT TO, remembered when it was made:
   -- rebuilding it here would be a second spelling of the same thing, and
   -- a cache keyed by a rebuilt key is a cache that misses the day the
   -- two spellings drift
   put sAgSearchUrl into tUrl
   agCacheSearch tUrl, pResult
   agLog "results: " & tCount & " of " & pResult["numFound"] & " (page " & sAgPage & ", " & kAgPageSize & " per request)"
   agPaintScreen
   if tCount is 0 then
      uiStatus "no results - try another family, or fewer words", "warn"
   end if
end agShowResults

command agPaintScreen
   -- Draw the kAgTiles tiles from the loaded page, starting at sAgOffset.
   -- EVERY REPAINT BUMPS THE SERIAL, because a thumbnail still in flight
   -- for tile 7 is a thumbnail for whatever tile 7 used to be: the grid's
   -- serial is about what the TILES are showing, not about which search
   -- asked, and a screen step changes that as completely as a new search
   -- does.
   local tI, tDoc, tId, tTitle, tSub, tIds, tCount, tShown, tBase
   set the defaultStack to the short name of this stack
   add 1 to sAgSerial
   agCancelThumbs
   put empty into sAgQueue
   if sAgResult is not an array then
      agClearTiles
      exit agPaintScreen
   end if
   put sAgResult["count"] into tCount
   if tCount is not an integer then
      put 0 into tCount
   end if
   put empty into tIds
   put 0 into tShown
   repeat with tI = 1 to kAgTiles
      if (sAgOffset + tI) > tCount then
         agTileEmpty tI
         put return after tIds
         next repeat
      end if
      put sAgResult["docs"][sAgOffset + tI] into tDoc
      put axFirst(tDoc["identifier"]) into tId
      put tId & return after tIds
      add 1 to tShown
      put axCollapseSpaces(axFirst(tDoc["title"])) into tTitle
      if tTitle is empty then
         put tId into tTitle
      end if
      put axCollapseSpaces(axJoin(tDoc["creator"], ", ")) into tSub
      if tSub is empty then
         put char 1 to 10 of axFirst(tDoc["date"]) into tSub
      end if
      agTileCaption tI, tTitle, tSub
      agWantThumb tI, tId
   end repeat
   put tIds into sAgTileIds
   agPumpThumbs
   put (sAgPage - 1) * kAgPageSize + sAgOffset into tBase
   agPaintPageInfo tBase, tShown
   if tShown > 0 then
      uiStatus tShown & " of " & sAgResult["numFound"] & " - the pictures are loading; click one to open it", "ok"
   end if
end agPaintScreen

command agPaintPageInfo pBase, pShown
   -- WHICH RESULTS THESE ARE, not which page they came on. "showing 25-48
   -- of 29,281" is the sentence the first engine run's "page 1 of 2929"
   -- should have been: a reader wants to know where they are in the
   -- answer, and the request's own page size is bookkeeping.
   local tFound, tText, tEnd
   put sAgResult["numFound"] into tFound
   if tFound is not an integer then
      put 0 into tFound
   end if
   put pBase + pShown into tEnd
   if pShown < 1 then
      put "nothing on this screen" into tText
   else
      put "showing " & (pBase + 1) & "-" & tEnd & " of " & tFound into tText
   end if
   if tFound > kAgDeepWall then
      put tText & " (the site pages only the first " & kAgDeepWall & ")" into tText
   end if
   put tText into field "agPageInfo"
   set the enabled of button "agPrev" to (pBase > 0)
   set the enabled of button "agNext" to agHasMore(pBase, pShown)
end agPaintPageInfo

function agHasMore pBase, pShown
   -- Is there a next screen to go to? Two walls, and only one of them is
   -- the answer's size: the site refuses to page past kAgDeepWall however
   -- many hits it reports, so offering Next past that is offering a
   -- button that comes back empty.
   local tFound, tEnd
   put sAgResult["numFound"] into tFound
   if tFound is not an integer then
      return false
   end if
   put pBase + pShown into tEnd
   if tEnd >= tFound then
      return false
   end if
   if tEnd >= kAgDeepWall then
      return false
   end if
   return true
end agHasMore

command agStepScreen pDelta
   -- Prev and Next move one SCREEN. Inside the loaded page that costs
   -- nothing; off either end it asks the site for the next page and says
   -- which screen of it to land on.
   local tWant, tCount, tBase
   set the defaultStack to the short name of this stack
   if sAgResult is not an array then
      exit agStepScreen
   end if
   put sAgResult["count"] into tCount
   if tCount is not an integer then
      put 0 into tCount
   end if
   put sAgOffset + pDelta * kAgTiles into tWant
   if tWant >= 0 then
      if tWant < tCount then
         put tWant into sAgOffset
         agPaintScreen
         exit agStepScreen
      end if
   end if
   if tWant < 0 then
      if sAgPage <= 1 then
         exit agStepScreen
      end if
      -- land on the LAST screen of the previous page, which is where a
      -- reader stepping backwards expects to arrive
      put kAgPageSize into sAgOffsetWanted
      agDoSearch sAgPage - 1
      exit agStepScreen
   end if
   put (sAgPage - 1) * kAgPageSize + sAgOffset into tBase
   if not agHasMore(tBase, tCount - sAgOffset) then
      exit agStepScreen
   end if
   put 0 into sAgOffsetWanted
   agDoSearch sAgPage + 1
end agStepScreen

-- ==========================================================================
-- The thumbnail queue and its cache.
--
-- Twenty-four tiles is twenty-four requests, and firing them together
-- would be this stack betting on a concurrency nobody has measured. So a
-- screen QUEUES its thumbnails, kAgFetchMax are in flight at a time, and
-- the next starts when one lands. What a screen has already seen is kept,
-- so walking back is free and a reader paging through hundreds of items
-- pays for each picture once.
-- ==========================================================================

command agWantThumb pIndex, pId
   -- Cached: paint it now. Not cached: queue it. Nothing fetches here.
   local tData
   if not axIdentifierIsValid(pId) then
      exit agWantThumb
   end if
   put agCachedThumb(pId) into tData
   if tData is not empty then
      agTilePicture pIndex, tData
      agNoteHit the number of bytes of tData
      exit agWantThumb
   end if
   agNoteMiss
   put pIndex && axThumbnailUrl(pId) & return after sAgQueue
end agWantThumb

command agPumpThumbs
   -- Start as many as the cap allows. Reached from a screen repaint and
   -- from every reply, so the queue drains without a timer.
   local tLine, tIndex, tUrl, tHandle
   set the defaultStack to the short name of this stack
   repeat while sAgInFlight < kAgFetchMax
      put line 1 of sAgQueue into tLine
      if tLine is empty then
         exit repeat
      end if
      delete line 1 of sAgQueue
      put word 1 of tLine into tIndex
      put word 2 of tLine into tUrl
      put axFetchUrl(tUrl, kAgThumbTag && sAgSerial && tIndex) into tHandle
      if tHandle is empty then
         agLog "thumbnail refused: " & axLastError()
      else
         put tHandle & comma after sAgThumbHandles
         add 1 to sAgInFlight
      end if
   end repeat
end agPumpThumbs

command agThumbSettled
   -- One thumbnail request is over, whichever way. The counter is the
   -- queue's whole safety: it is decremented HERE, on one path, so a
   -- reply and a failure cannot disagree about how many are out.
   if sAgInFlight > 0 then
      subtract 1 from sAgInFlight
   end if
   agPumpThumbs
end agThumbSettled

-- ==========================================================================
-- The cache, two tiers, and the counters that prove it is working.
-- ==========================================================================

command agCacheInit
   -- Where the disk tier lives, decided once. Empty when there is nowhere
   -- writable, and then everything below quietly stays memory-only: a
   -- cache that cannot be written is a slower gallery, never a broken one.
   local tRoot, tError, tPath
   put empty into sAgDisk
   put empty into tRoot
   try
      put specialFolderPath("documents") into tRoot
   catch tError
      put empty into tRoot
   end try
   if tRoot is empty then
      try
         put specialFolderPath("temporary") into tRoot
      catch tError
         put empty into tRoot
      end try
   end if
   if tRoot is empty then
      exit agCacheInit
   end if
   if there is not a folder (tRoot & "/ArchiveXT") then
      create folder (tRoot & "/ArchiveXT")
   end if
   put tRoot & "/ArchiveXT/cache" into tPath
   if there is not a folder tPath then
      create folder tPath
   end if
   if there is not a folder tPath then
      exit agCacheInit
   end if
   if there is not a folder (tPath & "/thumb") then
      create folder (tPath & "/thumb")
   end if
   if there is not a folder (tPath & "/meta") then
      create folder (tPath & "/meta")
   end if
   if there is not a folder (tPath & "/thumb") then
      exit agCacheInit
   end if
   put tPath into sAgDisk
end agCacheInit

function agDiskPath pKind, pId
   -- Only ever called with an identifier axIdentifierIsValid has passed,
   -- which is already a safe file name (letters, digits, dot, dash,
   -- underscore) - so there is no escaping to get wrong here, and the
   -- guard is the thing that makes that true rather than a comment
   -- claiming it.
   if sAgDisk is empty then
      return empty
   end if
   if not axIdentifierIsValid(pId) then
      return empty
   end if
   return sAgDisk & "/" & pKind & "/" & pId
end agDiskPath

function agDiskRead pKind, pId
   -- The bytes, or empty. A metadata file carries its stamp on its first
   -- line and is treated as absent once it is older than kAgMetaTtl.
   local tPath, tData, tError, tWhy, tStamp
   put agDiskPath(pKind, pId) into tPath
   if tPath is empty then
      return empty
   end if
   if there is no file tPath then
      return empty
   end if
   put empty into tData
   try
      put URL ("binfile:" & tPath) into tData
      put the result into tWhy
   catch tError
      return empty
   end try
   if tWhy is not empty then
      return empty
   end if
   if tData is empty then
      return empty
   end if
   if pKind is not "meta" then
      return tData
   end if
   put line 1 of tData into tStamp
   if not axIsDigits(tStamp) then
      return empty
   end if
   if (the seconds - tStamp) > kAgMetaTtl then
      return empty
   end if
   return char (the number of chars of line 1 of tData + 2) to -1 of tData
end agDiskRead

command agDiskWrite pKind, pId, pData
   -- Best effort, and silent about it. A cache write that fails costs a
   -- request next time and nothing else, so it must never reach the
   -- reader - but `the result` IS read, because an unchecked write is
   -- this tree's own recorded way of believing a file exists.
   local tPath, tError, tWhy, tOut
   put agDiskPath(pKind, pId) into tPath
   if tPath is empty then
      exit agDiskWrite
   end if
   if pData is empty then
      exit agDiskWrite
   end if
   put pData into tOut
   if pKind is "meta" then
      put the seconds & return & pData into tOut
   end if
   try
      put tOut into URL ("binfile:" & tPath)
      put the result into tWhy
   catch tError
      exit agDiskWrite
   end try
   if tWhy is not empty then
      agLog "cache: could not write " & tPath & " (" & tWhy & ")"
   end if
end agDiskWrite

command agNoteHit pBytes
   add 1 to sAgHits
   if pBytes is a number then
      add pBytes to sAgSaved
   end if
   agPaintCache
end agNoteHit

command agNoteMiss
   add 1 to sAgMisses
   agPaintCache
end agNoteMiss

command agPaintCache
   -- The counters on screen, because a cache nobody can see is a claim
   -- rather than a feature. Painted here only; every other handler
   -- reports through agNoteHit / agNoteMiss so the two cannot disagree.
   local tText
   if there is no field "agCacheInfo" then
      exit agPaintCache
   end if
   put sAgHits & " served from cache (" & axFormatBytes(sAgSaved) & " not fetched), " & sAgMisses & " asked of the site" into tText
   if sAgDisk is empty then
      put tText & " - memory only, no writable cache folder" into tText
   end if
   put tText into field "agCacheInfo"
end agPaintCache

command agClearCache
   -- Memory always; disk when there is one. The files are removed one by
   -- one out of the two folders this stack owns, never by deleting a
   -- folder, so a wrong sAgDisk can only fail to find things.
   local tKind, tName, tSaved, tCount, tError
   set the defaultStack to the short name of this stack
   put empty into sAgCache
   put empty into sAgCacheKeys
   put 0 into sAgCacheBytes
   put empty into sAgMeta
   put empty into sAgMetaKeys
   put 0 into sAgMetaBytes
   put empty into sAgSearch
   put empty into sAgSearchKeys
   put 0 into tCount
   if sAgDisk is not empty then
      repeat for each line tKind in ("thumb" & return & "meta")
         put the defaultFolder into tSaved
         try
            set the defaultFolder to (sAgDisk & "/" & tKind)
            repeat for each line tName in the files
               delete file (sAgDisk & "/" & tKind & "/" & tName)
               add 1 to tCount
            end repeat
         catch tError
         end try
         set the defaultFolder to tSaved
      end repeat
   end if
   put 0 into sAgHits
   put 0 into sAgMisses
   put 0 into sAgSaved
   agPaintCache
   agLog "cache cleared: " & tCount & " file(s) removed from " & sAgDisk
   uiStatus "cache cleared", "ok"
end agClearCache

command agCacheThumb pId, pData
   -- Keep it in memory and on disk, and drop the oldest in memory until
   -- the cache is inside its bound. A thumbnail is named by its
   -- identifier and can never be stale, so nothing here expires; it only
   -- runs out of room.
   local tSize, tOld
   if pId is empty then
      exit agCacheThumb
   end if
   if pId is among the keys of sAgCache then
      exit agCacheThumb
   end if
   put the number of bytes of pData into tSize
   put pData into sAgCache[pId]
   put pId & return after sAgCacheKeys
   add tSize to sAgCacheBytes
   agDiskWrite "thumb", pId, pData
   repeat while sAgCacheBytes > kAgCacheMax
      put line 1 of sAgCacheKeys into tOld
      if tOld is empty then
         exit repeat
      end if
      delete line 1 of sAgCacheKeys
      subtract the number of bytes of sAgCache[tOld] from sAgCacheBytes
      delete variable sAgCache[tOld]
   end repeat
   if sAgCacheBytes < 0 then
      put 0 into sAgCacheBytes
   end if
end agCacheThumb

function agCachedThumb pId
   -- Memory, then disk, then nothing. A disk hit is promoted into memory
   -- so a second screen does not read it again.
   local tData
   if pId is empty then
      return empty
   end if
   if pId is among the keys of sAgCache then
      return sAgCache[pId]
   end if
   put agDiskRead("thumb", pId) into tData
   if tData is empty then
      return empty
   end if
   put tData into sAgCache[pId]
   put pId & return after sAgCacheKeys
   add the number of bytes of tData to sAgCacheBytes
   return tData
end agCachedThumb

command agCacheMeta pId, pJson
   local tSize, tOld
   if pId is empty then
      exit agCacheMeta
   end if
   if pJson is empty then
      exit agCacheMeta
   end if
   put the number of bytes of pJson into tSize
   if pId is not among the keys of sAgMeta then
      put pId & return after sAgMetaKeys
      add tSize to sAgMetaBytes
   end if
   put pJson into sAgMeta[pId]
   agDiskWrite "meta", pId, pJson
   repeat while sAgMetaBytes > kAgMetaMax
      put line 1 of sAgMetaKeys into tOld
      if tOld is empty then
         exit repeat
      end if
      delete line 1 of sAgMetaKeys
      subtract the number of bytes of sAgMeta[tOld] from sAgMetaBytes
      delete variable sAgMeta[tOld]
   end repeat
   if sAgMetaBytes < 0 then
      put 0 into sAgMetaBytes
   end if
end agCacheMeta

function agCachedMeta pId
   local tData
   if pId is empty then
      return empty
   end if
   if pId is among the keys of sAgMeta then
      return sAgMeta[pId]
   end if
   put agDiskRead("meta", pId) into tData
   if tData is empty then
      return empty
   end if
   put tData into sAgMeta[pId]
   put pId & return after sAgMetaKeys
   add the number of bytes of tData to sAgMetaBytes
   return tData
end agCachedMeta

command agCacheSearch pUrl, pResult
   -- MEMORY ONLY, on purpose. The site's default result order is not
   -- stable and its counts move, so a search page is a thing to reuse
   -- while a reader is stepping back and forth and NOT a thing to hand
   -- back tomorrow as if it were the answer.
   local tOld
   if pUrl is empty then
      exit agCacheSearch
   end if
   if pUrl is not among the keys of sAgSearch then
      put pUrl & return after sAgSearchKeys
   end if
   put pResult into sAgSearch[pUrl]
   repeat while the number of lines of sAgSearchKeys > kAgSearchKeep
      put line 1 of sAgSearchKeys into tOld
      if tOld is empty then
         exit repeat
      end if
      delete line 1 of sAgSearchKeys
      delete variable sAgSearch[tOld]
   end repeat
end agCacheSearch

function agCachedSearch pUrl
   if pUrl is empty then
      return empty
   end if
   if pUrl is among the keys of sAgSearch then
      return sAgSearch[pUrl]
   end if
   return empty
end agCachedSearch

-- ==========================================================================
-- Pictures: the one place in this stack that talks to an image object.
--
-- An image does not report a refusal. Hand it bytes it cannot decode and
-- it stays empty, with no throw and no message - the same silence the
-- player gives a stream it cannot open (gotcha 19), one object over. So
-- every picture in this gallery goes through agSetPicture, which sets the
-- content with the location UNLOCKED (the control then snaps to the
-- picture's natural size, which is what makes `the width` a measurement
-- rather than the rect we already chose), asks the control how big it
-- became, and treats a width under two pixels as a refusal. That is
-- box2dxt's b2kSheetSourceFromFile idiom and the coinxt wallet's QR
-- idiom, unchanged, because it is the only one in this tree an engine has
-- ever agreed with.
-- ==========================================================================

function agSetPicture pName, pData, pBox
   -- Put bytes into image pName and fit them inside pBox ("l,t,r,b").
   -- Answers the natural size as "WxH" when the picture was taken, and
   -- EMPTY when it was refused - so every caller has to decide what to
   -- show instead, rather than assuming a picture appeared.
   local tError, tW, tH, tSaved, tL, tT, tR, tB
   if there is no image pName then
      return empty
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put item 1 of pBox into tL
   put item 2 of pBox into tT
   put item 3 of pBox into tR
   put item 4 of pBox into tB
   set the itemDelimiter to tSaved
   try
      -- a pure enhancement: an engine without it just scales the default
      -- way, which is why this is not allowed to take the picture down
      set the resizeQuality of image pName to "good"
   catch tError
   end try
   -- COLLAPSE BEFORE YOU MEASURE, and the first engine run is why. The
   -- tell below - a width under two pixels means the bytes were refused -
   -- is box2dxt's, and it works there because b2kSheetSourceFromFile puts
   -- its bytes into a control it has just CREATED, which has no rect yet.
   -- Here the control already carries one, and a refusal left it exactly
   -- as it was: the boot check read back 684x358, which is the stage rect
   -- this stack had set, and reported a refusal as a picture 684 pixels
   -- wide. Clearing the content and forcing the control to one pixel
   -- makes the measurement mean something again - a refusal cannot answer
   -- 2 or more, and every real picture does.
   set the lockLocation of image pName to true
   set the text of image pName to empty
   set the rect of image pName to (tL & comma & tT & comma & (tL + 1) & comma & (tT + 1))
   set the lockLocation of image pName to false
   put 0 into tW
   put 0 into tH
   try
      set the text of image pName to pData
      put the width of image pName into tW
      put the height of image pName into tH
   catch tError
      put 0 into tW
      put 0 into tH
   end try
   if tW is not a number then
      put 0 into tW
   end if
   if tH is not a number then
      put 0 into tH
   end if
   set the lockLocation of image pName to true
   if tW < 2 then
      set the text of image pName to empty
      set the rect of image pName to pBox
      set the visible of image pName to false
      return empty
   end if
   set the rect of image pName to agFitRect(tW, tH, tL, tT, tR, tB)
   return tW & "x" & tH
end agSetPicture

function agFitRect pW, pH, pL, pT, pR, pB
   -- The picture's rect inside a box: scaled down to fit, never up, and
   -- centred. Shrink-only is deliberate - an upscaled 180-pixel thumbnail
   -- looks worse than a small picture sitting in the middle of its cell,
   -- and the cell's own frame is what makes the grid read as a grid.
   local tBoxW, tBoxH, tW, tH, tX, tY
   put pR - pL into tBoxW
   put pB - pT into tBoxH
   put pW into tW
   put pH into tH
   if tW < 1 then
      return pL & comma & pT & comma & pR & comma & pB
   end if
   if tH < 1 then
      return pL & comma & pT & comma & pR & comma & pB
   end if
   if tW > tBoxW then
      put trunc(tH * tBoxW / tW) into tH
      put tBoxW into tW
   end if
   if tH > tBoxH then
      put trunc(tW * tBoxH / tH) into tW
      put tBoxH into tH
   end if
   if tW < 1 then
      put 1 into tW
   end if
   if tH < 1 then
      put 1 into tH
   end if
   put pL + ((tBoxW - tW) div 2) into tX
   put pT + ((tBoxH - tH) div 2) into tY
   return tX & comma & tY & comma & (tX + tW) & comma & (tY + tH)
end agFitRect

command agTileCaption pIndex, pTitle, pSub
   local tText, tName
   put "agTileCap" & pIndex into tName
   if there is no field tName then
      exit agTileCaption
   end if
   -- the character budget is the CELL's, and the cell shrank with the
   -- grid: about 26 characters fit across 130 pixels at textSize 9
   put agEllipsis(pTitle, 26) into tText
   if pSub is not empty then
      put return & agEllipsis(pSub, 26) after tText
   end if
   put tText into field tName
end agTileCaption

function agHexBytes pHex
   -- The BYTES pHex spells, and nothing else.
   --
   -- The boot self-check used the harness's axtHex for this and the first
   -- engine run failed on it: axtHex ends in `textDecode(tOut, "UTF-8")`,
   -- because every other thing it decodes is a JSON fixture and has to
   -- come back as text. A PNG is not UTF-8, so the decode replaced the
   -- bytes that were not valid sequences and handed the image object
   -- something that was no longer a picture. The right fix is not to
   -- widen axtHex - its callers all want text - but to stop asking it for
   -- bytes.
   local tI, tCount, tOut, tHi, tLo
   put the number of chars of pHex into tCount
   put empty into tOut
   put 1 into tI
   repeat while tI < tCount
      put agHexNibble(char tI of pHex) into tHi
      put agHexNibble(char (tI + 1) of pHex) into tLo
      if tHi < 0 then
         return empty
      end if
      if tLo < 0 then
         return empty
      end if
      put numToByte(tHi * 16 + tLo) after tOut
      add 2 to tI
   end repeat
   return tOut
end agHexBytes

function agHexNibble pChar
   -- By BYTE VALUE, not by offset() in a lookup string: offset honours
   -- the caseSensitive, which defaults to false, and "a" and "A" are the
   -- same nibble here only by luck of the alphabet. Negative for anything
   -- that is not a hex digit, so agHexBytes can refuse rather than encode
   -- a wrong byte.
   local tByte
   put byteToNum(pChar) into tByte
   if tByte >= 48 then
      if tByte <= 57 then
         return tByte - 48
      end if
   end if
   if tByte >= 97 then
      if tByte <= 102 then
         return tByte - 87
      end if
   end if
   if tByte >= 65 then
      if tByte <= 70 then
         return tByte - 55
      end if
   end if
   return -1
end agHexNibble

function agLocalCopy pEntry, pFile
   -- The path of an already-downloaded copy of this entry, at the size
   -- the metadata promised, or empty. The size check is what makes a
   -- half-finished download a miss rather than a broken file: the
   -- download path writes straight to its final name, so an interrupted
   -- one leaves exactly that.
   local tFolder, tName, tPath
   if sAgItem is not an array then
      return empty
   end if
   put agDownloadFolder(sAgItem["identifier"]) into tFolder
   if tFolder is empty then
      return empty
   end if
   put agSafeFileName(pFile) into tName
   if tName is empty then
      put agSafeFileName(pEntry["name"]) into tName
   end if
   put tFolder & "/" & tName into tPath
   if there is no file tPath then
      return empty
   end if
   if agFileSize(tFolder, tName) is pEntry["size"] then
      return tPath
   end if
   return empty
end agLocalCopy

function agOneLine pText
   -- A multi-line value as one log line. agLog writes a line at a time,
   -- so a raw variants list would arrive as four unlabelled lines.
   local tOut
   put pText into tOut
   replace return with "; " in tOut
   return tOut
end agOneLine

function agEllipsis pText, pMax
   local tOut
   if the length of pText <= pMax then
      return pText
   end if
   put char 1 to (pMax - 3) of pText into tOut
   return tOut & "..."
end agEllipsis

command agTileEmpty pIndex
   local tName
   put "false" into sAgTilePics[pIndex]
   put "agTileImg" & pIndex into tName
   if there is an image tName then
      set the text of image tName to empty
      set the lockLocation of image tName to true
      set the rect of image tName to agTileRect(pIndex)
      set the visible of image tName to false
   end if
   put "agTileCap" & pIndex into tName
   if there is a field tName then
      put empty into field tName
   end if
end agTileEmpty

command agClearTiles
   local tI
   repeat with tI = 1 to kAgTiles
      agTileEmpty tI
   end repeat
end agClearTiles

command agTilePicture pIndex, pData
   -- One thumbnail landing. A refusal is not an error here: archive.org
   -- has no derived image for every item, and a tile that keeps its
   -- caption over an empty frame is the honest picture of that.
   local tName, tSize
   if pIndex is not an integer then
      exit agTilePicture
   end if
   if pIndex < 1 then
      exit agTilePicture
   end if
   if pIndex > kAgTiles then
      exit agTilePicture
   end if
   put "agTileImg" & pIndex into tName
   put agSetPicture(tName, pData, agTileRect(pIndex)) into tSize
   if tSize is empty then
      put "false" into sAgTilePics[pIndex]
      agLog "tile " & pIndex & ": the image object refused those bytes (" & the number of bytes of pData & " received)"
      exit agTilePicture
   end if
   put "true" into sAgTilePics[pIndex]
   set the visible of image tName to (sAgPane is "grid")
end agTilePicture

command agCancelThumbs
   -- Every thumbnail still in flight, forgotten. The layer drops their
   -- late replies; the serial drops any that were already delivered into
   -- the message queue.
   local tHandle, tSaved, tList
   -- COLLECT, RESTORE, THEN CALL. axCancel is another layer's handler and
   -- this one has borrowed the delimiter; box2dxt's fireEmitter records
   -- what happens when an outward call is made from inside a borrowed-
   -- delimiter loop, and a restore at the end reads as a fix while
   -- leaving the bug in place.
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put empty into tList
   repeat for each item tHandle in sAgThumbHandles
      if tHandle is not empty then
         put tHandle & return after tList
      end if
   end repeat
   set the itemDelimiter to tSaved
   put empty into sAgThumbHandles
   put empty into sAgQueue
   put 0 into sAgInFlight
   repeat for each line tHandle in tList
      axCancel tHandle
   end repeat
   -- THE VIEWER'S PICTURE IS NOT THIS HANDLER'S. It used to be cancelled
   -- here too, which meant a grid repaint reached into the stage without
   -- bumping the viewer's serial - two handlers owning one thing, which
   -- is how the stage came to be painted over the grid in the first
   -- place. agVoidPicture owns it now, and agStop's axShutdown ends
   -- anything either of them missed.
end agCancelThumbs

command agForgetThumb pHandle
   -- One handle off the in-flight list. Rebuilt rather than spliced: a
   -- chunk edit on a comma list is where an off-by-one leaves a handle
   -- nobody can cancel.
   local tOut, tItem, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put empty into tOut
   repeat for each item tItem in sAgThumbHandles
      if tItem is not empty then
         if tItem is not pHandle then
            put tItem & comma after tOut
         end if
      end if
   end repeat
   set the itemDelimiter to tSaved
   put tOut into sAgThumbHandles
end agForgetThumb

-- ==========================================================================
-- The viewer: one item, its files, and whichever object can show them.
-- ==========================================================================

command agOpenTile pIndex
   local tId, tHandle, tJson, tItem
   set the defaultStack to the short name of this stack
   if pIndex < 1 then
      exit agOpenTile
   end if
   put line pIndex of sAgTileIds into tId
   if tId is empty then
      exit agOpenTile
   end if
   if not axIdentifierIsValid(tId) then
      uiStatus "that tile has no usable identifier", "bad"
      exit agOpenTile
   end if
   if sAgItemHandle is not empty then
      axCancel sAgItemHandle
      put empty into sAgItemHandle
   end if
   -- the stage is about to be about a different item, so whatever it was
   -- loading is not wanted whether or not it has left the wire yet
   agVoidPicture
   -- ALREADY HELD? An item opened twice in one sitting, or yesterday, is
   -- an item the site does not have to describe again. 196 KB was a real
   -- metadata reply on the first engine run; twenty of those is four
   -- megabytes this stack would otherwise ask for twice.
   put agCachedMeta(tId) into tJson
   if tJson is not empty then
      put axItemParse(tJson) into tItem
      if tItem is an array then
         agNoteHit the number of bytes of tJson
         agLog "cache: " & tId & " opened from the cache (" & axFormatBytes(the number of bytes of tJson) & ")"
         agShowItem tItem
         exit agOpenTile
      end if
   end if
   put axFetchUrl(axMetadataUrl(tId), kAgMetaTag && sAgViewSerial && tId) into tHandle
   if tHandle is empty then
      uiStatus "could not open that item: " & axLastError(), "bad"
      agLog "axFetchUrl: " & axLastError()
      exit agOpenTile
   end if
   put tHandle into sAgItemHandle
   agNoteMiss
   agLog "GET " & axMetadataUrl(tId)
   uiStatus "opening " & tId & "...", "warn"
end agOpenTile

command agShowItem pItem
   local tKind, tPlaylist, tTitle, tTable, tEntry
   set the defaultStack to the short name of this stack
   put pItem into sAgItem
   put agPlaylistKindOf(sAgFamily, axFirst(pItem["metadata"]["mediatype"])) into tKind
   put tKind into sAgKind
   put axPlaylist(pItem, tKind) into tPlaylist
   put tPlaylist into sAgPlaylist
   put axCollapseSpaces(axFirst(pItem["metadata"]["title"])) into tTitle
   if tTitle is empty then
      put pItem["identifier"] into tTitle
   end if
   put tTitle into field "agItemTitle"
   agFillMeta pItem, tKind, tPlaylist
   if tPlaylist is an array then
      put axPlaylistTable(tPlaylist) into tTable
      put tTable into field "agTracks"
      if the number of lines of field "agTracks" > 0 then
         set the hilitedLine of field "agTracks" to 1
      end if
   else
      put "no " & tKind & " file in this item (" & axLastError() & ")" into field "agTracks"
   end if
   agShowPane "viewer"
   -- A PICTURE ITEM OPENS AS A PICTURE. Everything else opens with the
   -- stage empty and waits to be told to play, because a film starting on
   -- its own the moment a tile is clicked is a demo nobody can read.
   if tKind is "images" then
      if tPlaylist is an array then
         agLoadPicture 1
      else
         agStagePrompt "this item has no picture file"
      end if
   else if tPlaylist is an array then
      put tPlaylist["entries"][1] into tEntry
      agStagePrompt "press Play to open " & agEllipsis(tEntry["title"], 60)
   else
      agStagePrompt "nothing here this stack knows how to open"
   end if
   uiStatus "open: " & agEllipsis(tTitle, 70), "ok"
end agShowItem

command agFillMeta pItem, pKind, pPlaylist
   -- The item's own record, in the order a reader asks for it. Everything
   -- here comes out of the metadata the site returned; nothing is derived
   -- from the identifier or guessed at.
   local tOut, tMeta, tValue, tCount
   put pItem["metadata"] into tMeta
   put "identifier  " & pItem["identifier"] & return into tOut
   put "mediatype   " & axFirst(tMeta["mediatype"]) & return after tOut
   put axJoin(tMeta["creator"], ", ") into tValue
   if tValue is not empty then
      put "creator     " & axCollapseSpaces(tValue) & return after tOut
   end if
   put axFirst(tMeta["date"]) into tValue
   if tValue is empty then
      put axFirst(tMeta["year"]) into tValue
   end if
   if tValue is not empty then
      put "date        " & char 1 to 10 of tValue & return after tOut
   end if
   put axSubjectTags(tMeta["subject"], 8) into tValue
   if tValue is not empty then
      put "subjects    " & tValue & return after tOut
   end if
   put pItem["filesCount"] into tValue
   put "files       " & tValue & return after tOut
   put 0 into tCount
   if pPlaylist is an array then
      put pPlaylist["count"] into tCount
   end if
   put "playlist    " & tCount & " " & pKind & " entr" & agPlural(tCount) & return after tOut
   put pItem["server"] into tValue
   if tValue is not empty then
      put "datanode    " & tValue & return after tOut
   end if
   put tOut into field "agItemMeta"
end agFillMeta

function agPlural pCount
   if pCount is 1 then
      return "y"
   end if
   return "ies"
end agPlural

function agSelectedIndex
   -- Which playlist entry the tracks table is pointing at. One is the
   -- answer when nothing is selected, because the viewer always opens
   -- with the first entry hilited and a Play that does nothing because a
   -- click was missed is worse than a Play that opens the obvious thing.
   local tLine
   if sAgPlaylist is not an array then
      return 0
   end if
   put the hilitedLine of field "agTracks" into tLine
   if tLine is not an integer then
      return 1
   end if
   if tLine < 1 then
      return 1
   end if
   if tLine > sAgPlaylist["count"] then
      return 1
   end if
   return tLine
end agSelectedIndex

function agSelectedEntry
   local tIndex
   put agSelectedIndex() into tIndex
   if tIndex < 1 then
      return empty
   end if
   return sAgPlaylist["entries"][tIndex]
end agSelectedEntry

command agSelectTrack
   -- A click in the tracks table. A picture item shows the picture at
   -- once (that IS opening it); everything else waits for Play.
   local tEntry
   set the defaultStack to the short name of this stack
   put agSelectedEntry() into tEntry
   if tEntry is not an array then
      exit agSelectTrack
   end if
   if sAgKind is "images" then
      agLoadPicture agSelectedIndex()
   else
      agStagePrompt "press Play to open " & agEllipsis(tEntry["title"], 60)
   end if
end agSelectTrack

-- ==========================================================================
-- The stage: a picture in an image object, or a stream in a player.
-- ==========================================================================

command agLoadPicture pIndex
   -- Fetch one playlist entry's picture into the big image. The DATANODE
   -- URL, like every other byte this stack asks for: the /download/ form
   -- answers with a 302 to exactly this host and directory, and a
   -- redirect between the request and the reply is a URL the fetch layer
   -- did not register (archivext/CLAUDE.md, the 2026-09-16 pass).
   local tEntry, tUrl, tHandle, tSize
   set the defaultStack to the short name of this stack
   if sAgPlaylist is not an array then
      exit agLoadPicture
   end if
   put sAgPlaylist["entries"][pIndex] into tEntry
   if tEntry is not an array then
      exit agLoadPicture
   end if
   -- VOID FIRST, BRANCH AFTER. The refusal below is an exit, and an exit
   -- above the cancel would leave the PREVIOUS picture in flight to land
   -- on a stage the reader has just been told is showing something else.
   agVoidPicture
   put tEntry["size"] into tSize
   if tSize is a number then
      if tSize > kAgBigMax then
         agStagePrompt "that picture is " & axFormatBytes(tSize) & " - too big to hold in memory; press Download instead"
         agLog "picture skipped: " & tEntry["name"] & " is " & axFormatBytes(tSize)
         exit agLoadPicture
      end if
   end if
   put tEntry["direct"] into tUrl
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   -- ONE PICTURE, KEPT. A full picture is megabytes, so this is not a
   -- cache with a policy: it is the last one, held so that a reader
   -- stepping between two images in an item does not pay for both twice.
   -- The disk tier deliberately stops at thumbnails and metadata; the
   -- Download button is where a picture goes to be kept.
   if tUrl is sAgLastPicUrl then
      if sAgLastPicData is not empty then
         agNoteHit the number of bytes of sAgLastPicData
         agLog "cache: that picture was already held"
         agBigPicture pIndex, sAgLastPicData
         exit agLoadPicture
      end if
   end if
   put axFetchUrl(tUrl, kAgBigTag && sAgViewSerial && pIndex) into tHandle
   if tHandle is empty then
      agStagePrompt "that picture was refused: " & axLastError()
      agLog "picture refused: " & axLastError()
      exit agLoadPicture
   end if
   put tHandle into sAgBigHandle
   put tUrl into sAgLastPicUrl
   put empty into sAgLastPicData
   agNoteMiss
   agStagePrompt "loading " & agEllipsis(tEntry["title"], 48) & " (" & axFormatBytes(tSize) & ")..."
   agLog "picture " & tHandle & ": " & tUrl
end agLoadPicture

command agBigPicture pIndex, pData
   local tSize, tEntry, tBox
   set the defaultStack to the short name of this stack
   put kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB into tBox
   put agSetPicture("agBigImage", pData, tBox) into tSize
   if tSize is empty then
      agStagePrompt "the image object refused those bytes - press Download, or Open page to see it in a browser"
      agLog "picture " & pIndex & ": refused by the image object (" & the number of bytes of pData & " received)"
      exit agBigPicture
   end if
   agHidePlayer
   -- THE PANE DECIDES, as it does for every tile (agTilePicture) and for
   -- this picture's own FAILURE path (agStagePrompt). Without it a photograph
   -- that lands after Back is pressed paints itself over the grid.
   set the visible of image "agBigImage" to (sAgPane is "viewer")
   set the visible of field "agStageNote" to false
   put sAgPlaylist["entries"][pIndex] into tEntry
   agLog "picture " & pIndex & ": " & tSize & " pixels, " & the number of bytes of pData & " bytes, " & tEntry["format"]
   uiStatus "showing " & agEllipsis(tEntry["title"], 60) & " (" & tSize & ")", "ok"
end agBigPicture

function agStreamPick pEntry
   -- WHICH ENCODE TO HAND THE PLAYER, which is the question the
   -- 2026-09-16 report turned into ("be more specific about file types
   -- perhaps"). archive.org lists an item's video derivatives with the
   -- ogv often first, and neither Windows' DirectShow nor macOS'
   -- AVFoundation has a stock Theora decoder - so the playlist's own best
   -- entry can be the one encode the platform cannot open, which is
   -- exactly gotcha 19's silent controller over silence.
   --
   -- axPlaylist hands video entries a `variants` list of
   -- name|label|size|format lines, best first, so the choice is already
   -- there to be made. MP4 / h.264 is the pair both platforms decode
   -- natively, so it wins when the item has one; otherwise the entry's
   -- own choice stands and the log says what it is.
   local tLine, tName, tFormat, tSaved, tOut, tPairs
   put pEntry["name"] into tOut
   if pEntry["variants"] is empty then
      return tOut
   end if
   -- PARSE FIRST, SCAN AFTER. The scan calls into the library
   -- (axLowerAscii, axFileExtension) and this handler has borrowed the
   -- delimiter to read the variants; cutting the two apart is the same
   -- discipline agCancelThumbs keeps one handler up.
   put the itemDelimiter into tSaved
   set the itemDelimiter to "|"
   put empty into tPairs
   repeat for each line tLine in pEntry["variants"]
      put item 1 of tLine & tab & item 4 of tLine & return after tPairs
   end repeat
   set the itemDelimiter to tSaved
   repeat for each line tLine in tPairs
      put char 1 to (offset(tab, tLine) - 1) of tLine into tName
      put axLowerAscii(char (offset(tab, tLine) + 1) to -1 of tLine) into tFormat
      if tFormat contains "h.264" then
         put tName into tOut
         exit repeat
      end if
      if tFormat contains "mpeg4" then
         put tName into tOut
         exit repeat
      end if
      if axFileExtension(tName) is "mp4" then
         put tName into tOut
         exit repeat
      end if
   end repeat
   return tOut
end agStreamPick

command agDoPlay
   -- STREAM the selected entry into the stack's OWN player, on the stage.
   -- Four signals now, in the order they can arrive:
   --   1. `the result` after `set the filename` - the synchronous verdict
   --      the platforms that type media up front give for free;
   --   2. `playStarted`, which a player sends when it really begins;
   --   3. six seconds later, a duration and a currentTime;
   --   4. everything the player will say about itself, logged at both
   --      moments - because the 2026-09-20 run proved signals 1 to 3 can
   --      all come back GOOD over a player nobody can hear, and none of
   --      them distinguishes a silent player from a working one.
   -- A failure downloads the file and plays it from disk, which is the
   -- path every platform's media stack can take.
   local tEntry, tUrl, tFile, tLocal
   set the defaultStack to the short name of this stack
   put agSelectedEntry() into tEntry
   if tEntry is not an array then
      uiStatus "open an item and select a track first", "warn"
      exit agDoPlay
   end if
   if sAgKind is "images" then
      agLoadPicture agSelectedIndex()
      exit agDoPlay
   end if
   put agStreamPick(tEntry) into tFile
   put axDirectUrl(sAgItem, tFile) into tUrl
   if tUrl is empty then
      put tEntry["direct"] into tUrl
   end if
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   put empty into sAgPlayRetried
   -- ALREADY ON DISK? Download writes to Documents/ArchiveXT/<identifier>
   -- and the file is named by the entry, so a track played once has been
   -- kept. Playing the local copy is both the cheaper thing and the more
   -- reliable one: a local file is the case every platform's media stack
   -- handles, and it is the only way to tell a stream problem from a
   -- playback problem without guessing.
   put agLocalCopy(tEntry, tFile) into tLocal
   if tLocal is not empty then
      agNoteHit tEntry["size"]
      agLog "play: " & tLocal
      agLog "      (already downloaded, so nothing is asked of the site)"
      uiStatus "playing the copy already on disk (" & agEllipsis(tEntry["title"], 46) & ")", "ok"
      agPlayUrl tLocal, true
      exit agDoPlay
   end if
   agLog "play: " & tUrl
   agLog "      (" & tEntry["format"] & ", " & axFormatBytes(tEntry["size"]) & ", chose " & tFile & ") on " & the platform & " " & the systemVersion
   if tEntry["variants"] is not empty then
      -- WHAT WAS ON OFFER, so a stream that will not open can be read
      -- against the encodes the item actually had. "chose X" alone cannot
      -- say whether the item had an MP4 to choose.
      agLog "      encodes: " & agOneLine(tEntry["variants"])
   end if
   uiStatus "opening the stream in the stack's own player (" & agEllipsis(tEntry["title"], 50) & ")...", "warn"
   agPlayUrl tUrl, false
end agDoPlay

command agPlayUrl pUrl, pIsFile
   -- HAND ONE URL OR PATH TO THE PLAYER. Its own handler because the
   -- six-second check retries the same entry over http, and a retry that
   -- re-implemented this would be a second spelling of the sequence that
   -- matters most in the stack.
   local tError, tName, tWhy
   set the defaultStack to the short name of this stack
   put kAgPlayerName into tName
   try
      if there is no player tName then
         create player
         set the name of the last player to tName
      end if
      set the visible of image "agBigImage" to false
      set the visible of field "agStageNote" to false
      set the rect of player tName to (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)
      set the showController of player tName to true
      set the visible of player tName to true
      agPlayerPrepare tName
      -- THE STATE GOES UP BEFORE THE PLAYER IS TOLD ANYTHING, and the
      -- first engine run is why. `on playStarted` exits when sAgPlayUrl
      -- is empty (it has to: a player another stack owns must not be
      -- reported as ours), and the first Play of a session set sAgPlayUrl
      -- AFTER `start player` - so the one message this stack added, the
      -- only POSITIVE signal it has, was thrown away exactly once per
      -- session and nobody could tell from the log. The second and third
      -- plays printed it only because the first had left the variable
      -- set. Cleared again on every path that gives up below.
      put pUrl into sAgPlayUrl
      put (pIsFile is true) into sAgPlayIsFile
      set the filename of player tName to pUrl
      put the result into tWhy
      if tWhy is not empty then
         agLog "the player refused it at once: " & tWhy
         set the visible of player tName to false
         put empty into sAgPlayUrl
         put empty into sAgPlayIsFile
         if pIsFile is true then
            agStagePrompt "this engine's player will not open that file - opening it outside"
            agOpenOutside pUrl
         else
            agLog "downloading the file and playing it from disk instead"
            agDoDownload true
         end if
         exit agPlayUrl
      end if
      start player tName
      -- `start player` is the verb; the paused property is set as well
      -- because a stream that loads paused shows a controller, reports a
      -- duration and plays nothing, which is one of the two shapes the
      -- 2026-09-20 report could have been.
      try
         set the paused of player tName to false
      catch tError
      end try
      agPlayerReport tName, "just started"
      agArmPlayCheck
   catch tError
      agLog "player failed: " & tError
      put empty into sAgPlayUrl
      put empty into sAgPlayIsFile
      if pIsFile is true then
         agStagePrompt "this engine's player will not open that file - opening it outside"
         agOpenOutside pUrl
      else
         agStagePrompt "the player would not take that stream; downloading it"
         agDoDownload true
      end if
   end try
end agPlayUrl

on playStarted
   -- THE POSITIVE SIGNAL, and the reason this stack is not just the
   -- explorer's six-second guess again: a player that really begins says
   -- so. Nothing in this tree had used it before, so it is wired as an
   -- ADDITION to the check rather than a replacement for it - if no
   -- engine sends it, the six-second check still decides.
   set the defaultStack to the short name of this stack
   if sAgPlayUrl is empty then
      pass playStarted
   end if
   agCancelPlayCheck
   agLog "playStarted: the player opened the stream"
   uiStatus "playing in the stack's own player", "ok"
end playStarted

on playStopped
   set the defaultStack to the short name of this stack
   if sAgPlayUrl is empty then
      pass playStopped
   end if
   agLog "playStopped"
end playStopped

command agArmPlayCheck
   -- One pending check at a time: a second Play inside the six seconds
   -- would otherwise leave the first check to judge the second stream.
   agCancelPlayCheck
   send "agPlayCheck" to me in 6 seconds
end agArmPlayCheck

command agCancelPlayCheck
   -- `the pendingMessages` is a COMMA record per line, so the delimiter is
   -- set here rather than assumed (box2dxt gotcha 5; holde-em's own sweep
   -- carries the same line for the same reason). It matters more here than
   -- it looks: this handler is reached from closeStack, which inherits
   -- whatever the IDE or another stack left set, and under a foreign
   -- delimiter `item 3` is the whole record, nothing matches, and the
   -- one-check-at-a-time contract fails SILENTLY.
   --
   -- COLLECT, RESTORE, THEN CANCEL, the discipline agCancelThumbs keeps:
   -- `cancel` is an engine command run from inside a borrowed-delimiter
   -- loop otherwise.
   local tLine, tSaved, tIds, tId
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put empty into tIds
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine begins with "agPlayCheck" then
         put item 1 of tLine & return after tIds
      end if
   end repeat
   set the itemDelimiter to tSaved
   repeat for each line tId in tIds
      cancel tId
   end repeat
end agCancelPlayCheck

command agPlayCheck
   -- Six seconds after Play: a player that opened its stream reports a
   -- duration (and, if it is playing, a moving currentTime); one that
   -- could not open it reports 0 for both and NO error. Only the second
   -- case falls back, and only if the reader has not moved on.
   local tName, tDuration, tTime, tError, tUrl, tIsFile, tScale, tSecs, tRest
   set the defaultStack to the short name of this stack
   put kAgPlayerName into tName
   put sAgPlayUrl into tUrl
   put sAgPlayIsFile is true into tIsFile
   if tUrl is empty then
      exit agPlayCheck
   end if
   if there is no player tName then
      exit agPlayCheck
   end if
   if the filename of player tName is not tUrl then
      exit agPlayCheck
   end if
   put 0 into tDuration
   put 0 into tTime
   try
      put the duration of player tName into tDuration
      put the currentTime of player tName into tTime
   catch tError
      put 0 into tDuration
   end try
   if tDuration is not a number then
      put 0 into tDuration
   end if
   if tTime is not a number then
      put 0 into tTime
   end if
   put 0 into tScale
   try
      put the timeScale of player tName into tScale
   catch tError
      put 0 into tScale
   end try
   if tScale is not a number then
      put 0 into tScale
   end if
   put empty into tSecs
   if tScale > 0 then
      put " (" & trunc(tDuration / tScale) & "s long, " & trunc(tTime / tScale) & "s in, timeScale " & tScale & ")" into tSecs
   end if
   agLog "play check: duration " & tDuration & ", currentTime " & tTime & tSecs
   agPlayerReport tName, "six seconds in"
   if tDuration > 0 then
      -- OPEN AND RUNNING IS NOT AUDIBLE, and the 2026-09-20 report is why
      -- this line says what it says. The check can prove the stream
      -- opened and the clock moved; it cannot hear anything. So it says
      -- so, and points at the control that is the usual answer.
      if tTime > 0 then
         uiStatus "playing - volume " & sAgLoudness & " of 100; use Vol + if you hear nothing", "ok"
      else
         uiStatus "open, but the clock has not moved - press the controller's play", "warn"
      end if
      exit agPlayCheck
   end if
   -- ONE http RETRY BEFORE GIVING UP ON THE STREAM. The platform players
   -- read a URL through the operating system's own source filter, and on
   -- Windows that is DirectShow, which handles http and is not known to
   -- handle https. That is the cheapest discriminator anyone can run and
   -- nothing in this suite has ever run it, so the gallery runs it: the
   -- same datanode URL, one scheme down, once per entry. If it opens,
   -- the answer to "why will video not play" is a scheme.
   if not tIsFile then
      if sAgPlayRetried is not true then
         if tUrl begins with "https://" then
            put true into sAgPlayRetried
            put char 9 to -1 of tUrl into tRest
            agLog "no duration over https - retrying the same URL over http, which is the one test that separates the scheme from the container"
            agPlayUrl ("http://" & tRest), false
            exit agPlayCheck
         end if
      end if
   end if
   set the visible of player tName to false
   put empty into sAgPlayUrl
   put empty into sAgPlayIsFile
   -- THE LADDER HAS TO KNOW WHICH RUNG IT IS ON. A stream that never
   -- opened goes to a download; a downloaded FILE that never opened goes
   -- to the system, never to another download. The explorer demo's
   -- pre-pass review found exactly this loop before an engine ever saw it
   -- (archivext/CLAUDE.md, 2026-09-16): Linux builds have no working
   -- player at all, so a file failure there would have downloaded and
   -- replayed forever, six seconds at a time.
   if tIsFile then
      agLog "six seconds in and the player reports no duration for the LOCAL file - handing it to the system instead"
      agStagePrompt "this engine's player will not open that file - opening it outside"
      agOpenOutside tUrl
      exit agPlayCheck
   end if
   agLog "six seconds in and the player reports no duration - downloading the file and playing it from disk instead"
   agDoDownload true
end agPlayCheck

command agPlayerPrepare pName
   -- Everything that can silence a player, set before it is handed a
   -- stream. Each in its own try: these are properties this suite has
   -- never measured, and an engine that does not know one of them must
   -- not take Play down with it.
   local tError
   try
      set the dontUseQT to true
   catch tError
   end try
   try
      set the playLoudness to kAgLoudness
   catch tError
   end try
   try
      set the playLoudness of player pName to kAgLoudness
   catch tError
   end try
end agPlayerPrepare

function agPlayerProp pName, pProp
   -- One property, read defensively, rendered for a log line. Answers
   -- "(n/a)" for anything this engine does not have, so a report can ask
   -- about properties that may not exist without a guard per line.
   local tValue, tError
   put "(n/a)" into tValue
   try
      switch pProp
         case "duration"
            put the duration of player pName into tValue
            break
         case "currentTime"
            put the currentTime of player pName into tValue
            break
         case "timeScale"
            put the timeScale of player pName into tValue
            break
         case "playLoudness"
            put the playLoudness of player pName into tValue
            break
         case "paused"
            put the paused of player pName into tValue
            break
         case "playRate"
            put the playRate of player pName into tValue
            break
         case "status"
            put the status of player pName into tValue
            break
         case "mediaTypes"
            put the mediaTypes of player pName into tValue
            break
         case "tracks"
            put the tracks of player pName into tValue
            break
         default
            put "(unknown property)" into tValue
      end switch
   catch tError
      put "(n/a)" into tValue
   end try
   if tValue is empty then
      return "(empty)"
   end if
   replace return with " / " in tValue
   return tValue
end agPlayerProp

command agPlayerReport pName, pWhen
   -- WHAT THE PLAYER SAYS ABOUT ITSELF, in one block, at two moments.
   -- Nothing here decides anything; it exists so the next engine log can
   -- answer "it opened and ran and was silent" with the properties that
   -- distinguish the reasons, rather than with another guess. `the
   -- tracks` is the line that matters most: it says whether an audio
   -- track was found at all.
   if there is no player pName then
      exit agPlayerReport
   end if
   agLog "player (" & pWhen & "): loudness " & agPlayerProp(pName, "playLoudness") \
         & ", paused " & agPlayerProp(pName, "paused") \
         & ", rate " & agPlayerProp(pName, "playRate") \
         & ", status " & agPlayerProp(pName, "status")
   agLog "         duration " & agPlayerProp(pName, "duration") \
         & ", currentTime " & agPlayerProp(pName, "currentTime") \
         & ", timeScale " & agPlayerProp(pName, "timeScale")
   agLog "         mediaTypes " & agPlayerProp(pName, "mediaTypes") \
         & "; tracks " & agPlayerProp(pName, "tracks")
end agPlayerReport

command agSetLoudness pDelta
   -- A volume a reader can reach, because the first thing anyone does
   -- with a silent player is look for one. The engine's own global moves
   -- with the player's: on a machine where the global was the thing at
   -- zero, moving only the player's would change nothing and look like
   -- the control was broken.
   local tNow, tError, tBeepError
   set the defaultStack to the short name of this stack
   put sAgLoudness into tNow
   if tNow is not a number then
      put kAgLoudness into tNow
   end if
   add pDelta to tNow
   if tNow > 100 then
      put 100 into tNow
   end if
   if tNow < 0 then
      put 0 into tNow
   end if
   put tNow into sAgLoudness
   try
      set the playLoudness to tNow
   catch tError
   end try
   try
      if there is a player kAgPlayerName then
         set the playLoudness of player kAgPlayerName to tNow
      end if
   catch tError
   end try
   -- AND A NOISE THE PLAYER HAS NOTHING TO DO WITH. `beep` is the
   -- engine's own alert sound, so it separates the two questions a silent
   -- player raises and that no property of the player can: if this is
   -- audible, the machine and the engine can make sound and the silence
   -- belongs to the player or its stream; if it is not, nothing here was
   -- ever going to be heard. One word of code, and the only test in this
   -- stack that does not go through a player object at all.
   try
      beep
      agLog "beep: the engine's own alert sound just played - if you did NOT hear it, the silence is the machine's or the engine's, not the player's"
   catch tBeepError
      agLog "beep: this engine refused to make a sound at all (" & tBeepError & ")"
   end try
   agLog "loudness asked for " & tNow & "; the engine reads back " & agPlayerProp(kAgPlayerName, "playLoudness")
   uiStatus "volume " & tNow & " of 100 (a beep just played - did you hear it?)", "ok"
end agSetLoudness

command agHidePlayer
   local tName, tError
   put kAgPlayerName into tName
   try
      if there is a player tName then
         stop player tName
         set the visible of player tName to false
      end if
   catch tError
   end try
end agHidePlayer

command agDoStopPlay
   set the defaultStack to the short name of this stack
   put empty into sAgPlayUrl
   put empty into sAgPlayIsFile
   agCancelPlayCheck
   agHidePlayer
   if sAgPane is "viewer" then
      agStagePrompt "stopped"
   end if
end agDoStopPlay

-- ==========================================================================
-- Download, the page, the URL - the three things a gallery owes a reader
-- who wants the file itself.
-- ==========================================================================

command agDoDownload pPlayAfter
   -- Save the selected entry to Documents/ArchiveXT/<identifier>/ (the
   -- temporary folder when Documents is not writable) through axDownload,
   -- which writes straight to disk with progress and a stall watchdog, so
   -- a 700 MB film never sits in memory. pPlayAfter true plays the file
   -- when it lands. A file already there at the size the metadata
   -- promised is reused rather than fetched again.
   local tEntry, tFolder, tPath, tName, tHandle, tUrl
   set the defaultStack to the short name of this stack
   put agSelectedEntry() into tEntry
   if tEntry is not an array then
      uiStatus "open an item and select a track first", "warn"
      exit agDoDownload
   end if
   if sAgDownloadHandle is not empty then
      uiStatus "a download is already running (" & sAgDownloadPath & ")", "warn"
      -- A REFUSAL ON THE PLAY LADDER HAS TO REACH THE STAGE. agPlayCheck
      -- hides the player and clears its state before falling back here, so
      -- a silent exit leaves a black rectangle and a status line about a
      -- file the reader did not ask about.
      if pPlayAfter is true then
         agStagePrompt "the player did not open that stream, and a download is already running - try again when it finishes"
      end if
      exit agDoDownload
   end if
   put agDownloadFolder(sAgItem["identifier"]) into tFolder
   if tFolder is empty then
      uiStatus "no writable folder for downloads (Documents and temporary both refused)", "bad"
      exit agDoDownload
   end if
   -- THE FILE THE PICKER CHOSE, not the playlist's own best entry. Play
   -- may have picked an h.264 encode over an ogv, and a Download that
   -- saved the other one would mean Play could never find its own copy
   -- on disk again (agLocalCopy) and the reader would get a file they did
   -- not hear.
   put agSafeFileName(agStreamPick(tEntry)) into tName
   if tName is empty then
      put agSafeFileName(tEntry["name"]) into tName
   end if
   put tFolder & "/" & tName into tPath
   put pPlayAfter is true into sAgPlayAfter
   if there is a file tPath then
      if agFileSize(tFolder, tName) is tEntry["size"] then
         agLog "already downloaded: " & tPath
         agDownloadFinished tPath
         exit agDoDownload
      end if
   end if
   put axDirectUrl(sAgItem, agStreamPick(tEntry)) into tUrl
   if tUrl is empty then
      put tEntry["direct"] into tUrl
   end if
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   put axDownload(tUrl, tPath, "download") into tHandle
   if tHandle is empty then
      agLog "download refused: " & axLastError()
      uiStatus "download refused - see the log", "bad"
      put empty into sAgPlayAfter
      exit agDoDownload
   end if
   put tHandle into sAgDownloadHandle
   put tPath into sAgDownloadPath
   agLog "download " & tHandle & ": " & tUrl & " -> " & tPath & " (" & axFormatBytes(tEntry["size"]) & ")"
   uiStatus "downloading " & tName & " (" & axFormatBytes(tEntry["size"]) & ")...", "warn"
end agDoDownload

command agShowProgress pReceivedTotal
   local tReceived, tTotal, tPercent, tSaved
   set the defaultStack to the short name of this stack
   -- the layer reports progress as "received,total", so the delimiter is
   -- SET here rather than assumed: this handler is reached from a libURL
   -- callback and has no idea what the last thing to run left behind
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put item 1 of pReceivedTotal into tReceived
   put item 2 of pReceivedTotal into tTotal
   set the itemDelimiter to tSaved
   if tReceived is not a number then
      exit agShowProgress
   end if
   if tTotal is not a number then
      uiStatus "downloading: " & axFormatBytes(tReceived) & " so far", "warn"
      exit agShowProgress
   end if
   if tTotal < 1 then
      uiStatus "downloading: " & axFormatBytes(tReceived) & " so far", "warn"
      exit agShowProgress
   end if
   put trunc(tReceived * 100 / tTotal) into tPercent
   uiStatus "downloading: " & axFormatBytes(tReceived) & " of " & axFormatBytes(tTotal) & " (" & tPercent & "%)", "warn"
end agShowProgress

command agDownloadFinished pPath
   -- The file landed. A picture goes straight onto the stage from disk; a
   -- film or a concert goes to the player if Play asked for it, and to
   -- the system's own player if this engine's player will not have it
   -- either. There is no second download from here, ever: the file is
   -- already on the disk, so another fetch could only loop.
   local tPlay, tError, tData
   set the defaultStack to the short name of this stack
   put sAgPlayAfter is true into tPlay
   put empty into sAgPlayAfter
   put empty into sAgDownloadPath
   agLog "downloaded: " & pPath
   if not tPlay then
      uiStatus "saved to " & pPath, "ok"
      exit agDownloadFinished
   end if
   if sAgKind is "images" then
      put empty into tData
      try
         put URL ("binfile:" & pPath) into tData
      catch tError
         put empty into tData
      end try
      if agSetPicture("agBigImage", tData, (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)) is not empty then
         agHidePlayer
         set the visible of image "agBigImage" to (sAgPane is "viewer")
         set the visible of field "agStageNote" to false
         uiStatus "showing the downloaded picture", "ok"
         exit agDownloadFinished
      end if
      agStagePrompt "the image object refused the downloaded file too - opening it outside"
      agOpenOutside pPath
      exit agDownloadFinished
   end if
   -- THE SAME ONE HANDLER as the stream path, so the ladder's last rung
   -- cannot drift from its first: agPlayUrl knows a file from a stream
   -- and ends a file that will not open in launch document.
   set the visible of image "agBigImage" to false
   set the visible of field "agStageNote" to false
   agPlayUrl pPath, true
end agDownloadFinished

command agOpenOutside pPath
   -- The last rung of the ladder, and the only one with an engine record
   -- behind it in this tree: riptide plays fetched media by handing it to
   -- the system (2026-08-15, two machines). Linux has no working player
   -- object at all in this engine line, so on that platform this is the
   -- rung that matters.
   local tError
   try
      launch document pPath
      agLog "handed to the system's own player: " & pPath
   catch tError
      agLog "could not hand it to the system either: " & tError
      uiStatus "saved to " & pPath & " - open it yourself", "warn"
   end try
end agOpenOutside

command agDoOpenPage
   -- The item's own page, in the reader's browser. For a film the site's
   -- embed player is the honest fallback when this engine's player will
   -- not take the stream, so the log names it beside the page.
   local tId, tError
   set the defaultStack to the short name of this stack
   if sAgItem is not an array then
      uiStatus "open an item first", "warn"
      exit agDoOpenPage
   end if
   put sAgItem["identifier"] into tId
   agLog "details: " & axDetailsUrl(tId)
   agLog "embed:   " & axEmbedUrl(tId)
   try
      launch url axDetailsUrl(tId)
   catch tError
      agLog "could not open a browser: " & tError
      uiStatus "the page URL is in the log", "warn"
   end try
end agDoOpenPage

command agDoCopyUrl
   local tEntry, tUrl
   set the defaultStack to the short name of this stack
   put agSelectedEntry() into tEntry
   if tEntry is not an array then
      uiStatus "open an item and select a track first", "warn"
      exit agDoCopyUrl
   end if
   put tEntry["direct"] into tUrl
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   set the clipboardData["text"] to tUrl
   uiCopyFlash "agCopyUrl"
   agLog "copied: " & tUrl
   uiStatus "the stream URL is on the clipboard", "ok"
end agDoCopyUrl

function agDownloadFolder pIdentifier
   -- Documents/ArchiveXT/<identifier>, created on demand; the temporary
   -- folder when Documents refuses (the torrent demos' fallback order,
   -- and the explorer demo's own). Empty when neither can be made, which
   -- is a refusal rather than a download into a folder nobody can find.
   local tBase, tFolder, tName
   put agSafeFileName(pIdentifier) into tName
   put specialFolderPath("documents") into tBase
   if tBase is empty then
      put specialFolderPath("temporary") into tBase
   end if
   if tBase is empty then
      return empty
   end if
   put tBase & "/ArchiveXT/" & tName into tFolder
   if there is not a folder (tBase & "/ArchiveXT") then
      create folder (tBase & "/ArchiveXT")
   end if
   if there is not a folder tFolder then
      create folder tFolder
   end if
   if there is a folder tFolder then
      return tFolder
   end if
   put specialFolderPath("temporary") & "/ArchiveXT/" & tName into tFolder
   if there is not a folder (specialFolderPath("temporary") & "/ArchiveXT") then
      create folder (specialFolderPath("temporary") & "/ArchiveXT")
   end if
   if there is not a folder tFolder then
      create folder tFolder
   end if
   if there is a folder tFolder then
      return tFolder
   end if
   return empty
end agDownloadFolder

function agFileSize pFolder, pName
   -- The size of one file from `the detailed files` of its folder,
   -- WITHOUT reading it: a 700 MB film is not a thing to pull into memory
   -- to ask how big it is. Empty when the file is not there.
   local tSaved, tLines, tLine, tSize, tDelim
   put empty into tSize
   put the defaultFolder into tSaved
   set the defaultFolder to pFolder
   put the detailed files into tLines
   set the defaultFolder to tSaved
   -- `the detailed files` is a COMMA record per line, so the delimiter is
   -- set here rather than assumed: box2dxt's own gotcha 5, and the demo
   -- this handler came from reads the same record without setting it.
   put the itemDelimiter into tDelim
   set the itemDelimiter to comma
   repeat for each line tLine in tLines
      if urlDecode(item 1 of tLine) is pName then
         put item 2 of tLine into tSize
         exit repeat
      end if
   end repeat
   set the itemDelimiter to tDelim
   return tSize
end agFileSize

function agSafeFileName pName
   -- The last path segment of an archive.org file name, with the
   -- characters no platform's file system takes replaced.
   local tName, tBad, tI, tChar
   put pName into tName
   if "/" is in tName then
      put char (the length of tName - offset("/", agReverse(tName)) + 2) to -1 of tName into tName
   end if
   put ":*?" & quote & "<>|\" into tBad
   repeat with tI = 1 to the length of tBad
      put char tI of tBad into tChar
      replace tChar with "_" in tName
   end repeat
   if tName is empty then
      put "download.bin" into tName
   end if
   return tName
end agSafeFileName

function agReverse pText
   local tOut, tI
   put empty into tOut
   repeat with tI = the length of pText down to 1
      put char tI of pText after tOut
   end repeat
   return tOut
end agReverse

-- ==========================================================================
-- The fetch-layer callback: the whole contract in one handler. Reached
-- from the engine's URL callback or the layer's watchdog, so the
-- defaultStack is pinned FIRST (engine notes 5.3).
-- ==========================================================================

on onArchive pHandle, pKind, pArgOne, pTag
   set the defaultStack to the short name of this stack
   if pKind is "search" then
      if pHandle is sAgSearchHandle then
         put empty into sAgSearchHandle
      end if
      agShowResults pArgOne
   else if pKind is "item" then
      if pHandle is sAgItemHandle then
         put empty into sAgItemHandle
      end if
      agShowItem pArgOne
   else if pKind is "raw" then
      agRawReply pHandle, pArgOne, pTag
   else if pKind is "progress" then
      agShowProgress pArgOne
   else if pKind is "file" then
      if pHandle is sAgDownloadHandle then
         put empty into sAgDownloadHandle
      end if
      agDownloadFinished pArgOne
   else if pKind is "error" then
      agFailure pHandle, pArgOne, pTag
   else
      agLog "unknown callback kind " & pKind & " for request " & pHandle
   end if
end onArchive

command agRawReply pHandle, pBody, pTag
   -- Every picture arrives here. The TAG decides what it is and which
   -- search it belongs to: "thumb <serial> <tile>" or "big <serial>
   -- <entry>". A reply whose serial is not the current one is dropped,
   -- because ten thumbnails are in flight at once and a reader who
   -- pressed Next would otherwise get the last page's pictures under this
   -- page's captions.
   local tWhat, tSerial, tIndex
   set the defaultStack to the short name of this stack
   agForgetThumb pHandle
   put word 1 of pTag into tWhat
   put word 2 of pTag into tSerial
   put word 3 of pTag into tIndex
   if tWhat is kAgThumbTag then
      -- SETTLED FIRST, WHATEVER HAPPENS NEXT. A stale thumbnail still
      -- occupied a slot in the in-flight count, and a return that skipped
      -- the decrement would wedge the queue at the cap with nothing out.
      agThumbSettled
      if tSerial is not sAgSerial then
         exit agRawReply
      end if
      agCacheThumb (line tIndex of sAgTileIds), pBody
      agTilePicture tIndex, pBody
      exit agRawReply
   end if
   if tWhat is kAgMetaTag then
      if pHandle is sAgItemHandle then
         put empty into sAgItemHandle
      end if
      agMetaArrived tIndex, pBody
      exit agRawReply
   end if
   if tWhat is kAgBigTag then
      if pHandle is sAgBigHandle then
         put empty into sAgBigHandle
      end if
      -- THE VIEWER HAS ITS OWN SERIAL, and it has to. A search does not
      -- invalidate the picture on the stage, and an item open does not
      -- invalidate the grid's thumbnails - so one counter for both would
      -- be wrong in whichever direction it was bumped.
      if tSerial is not sAgViewSerial then
         agLog "dropped a picture the stage has moved past (" & tSerial & " of " & sAgViewSerial & ")"
         exit agRawReply
      end if
      agBigPicture tIndex, pBody
      exit agRawReply
   end if
   agLog "raw reply " & pHandle & " (" & pTag & "): " & the number of bytes of pBody & " bytes"
end agRawReply

command agMetaArrived pId, pJson
   -- The metadata of one item, as bytes. Parsed here rather than by the
   -- library's `item` kind so the RAW JSON exists to be cached, and the
   -- refusal shapes the parser already knows (a missing item answers
   -- "{}") still come through axItemParse.
   local tItem
   set the defaultStack to the short name of this stack
   put axItemParse(pJson) into tItem
   if tItem is not an array then
      agLog "could not read that item: " & axLastError()
      uiStatus "that item could not be read - see the log", "bad"
      exit agMetaArrived
   end if
   agCacheMeta pId, pJson
   agShowItem tItem
end agMetaArrived

command agFailure pHandle, pReason, pTag
   -- One place for every failure, because a grid has three kinds at once
   -- and only one of them is worth a red status line. A thumbnail that
   -- did not arrive is a tile without a picture, not a broken stack.
   local tWhat, tSerial, tIndex, tWasSearch
   set the defaultStack to the short name of this stack
   agForgetThumb pHandle
   put word 1 of pTag into tWhat
   put word 2 of pTag into tSerial
   put word 3 of pTag into tIndex
   -- ASKED BEFORE IT IS CLEARED. The first draft tested the handle against
   -- sAgSearchHandle again at the bottom, after the line above had emptied
   -- it, so the branch could never run - a check that cannot fire, which
   -- is this tree's own worst gate shape written into an app.
   put (pHandle is sAgSearchHandle) into tWasSearch
   if tWasSearch then
      put empty into sAgSearchHandle
   end if
   if pHandle is sAgItemHandle then
      put empty into sAgItemHandle
   end if
   if pHandle is sAgBigHandle then
      put empty into sAgBigHandle
   end if
   if pHandle is sAgDownloadHandle then
      put empty into sAgDownloadHandle
      put empty into sAgDownloadPath
      put empty into sAgPlayAfter
   end if
   agLog "request " & pHandle & " (" & pTag & ") failed: " & pReason
   if tWhat is kAgThumbTag then
      agThumbSettled
      if tSerial is sAgSerial then
         agTileEmpty tIndex
      end if
      exit agFailure
   end if
   if tWhat is kAgBigTag then
      if tSerial is sAgViewSerial then
         agStagePrompt "that picture did not arrive - press Download, or Open page"
      end if
      exit agFailure
   end if
   if tWasSearch then
      -- the page label still names the page this search asked for, and
      -- there is now no page: say so rather than leaving a number that
      -- disagrees with what the grid is showing
      put "search failed" into field "agPageInfo"
   end if
   uiStatus "request failed - see the log", "bad"
end agFailure

command agLog pText
   -- Guarded like the kit's uiStatus, and for the kit's reason: this is
   -- reached from a libURL callback, which can arrive while the window is
   -- being rebuilt or after it has gone.
   set the defaultStack to the short name of this stack
   if there is no field "agLog" then
      exit agLog
   end if
   put pText & return after field "agLog"
   set the vScroll of field "agLog" to the formattedHeight of field "agLog"
end agLog

-- ==========================================================================
-- The member self-test and a live probe, into the log.
-- ==========================================================================

command agDoSelfTest
   local tReport
   set the defaultStack to the short name of this stack
   uiStatus "running axSelfTest...", "warn"
   put axSelfTest() into tReport
   agLog "== axSelfTest =="
   agLog tReport
   uiStatus "self-test: " & line 1 of tReport, "ok"
end agDoSelfTest

command agDoProbe
   -- FOUR blocking requests, aimed at the one question this stack adds to
   -- the explorer's ten-leg probe: do archive.org's bytes become a
   -- picture in an engine image object? Nothing here is inferred - each
   -- leg reports what the control answered afterwards, because an image
   -- that refuses its content says nothing at all (agSetPicture).
   local tOptions, tQuery, tResult, tId, tUrl, tBody, tItem, tPlaylist
   local tEntry, tSize
   set the defaultStack to the short name of this stack
   uiStatus "live probe running (four blocking requests)...", "warn"
   agLog "== live probe =="
   put "identifier,title" into tOptions["fields"]
   put 3 into tOptions["rows"]
   put "mediatype:(image)" into tQuery
   agLog "1. axSearchSync " & tQuery
   put axSearchSync(tQuery, tOptions) into tResult
   put empty into tId
   if tResult is an array then
      put axFirst(tResult["docs"][1]["identifier"]) into tId
      agLog "   ok: numFound " & tResult["numFound"] & ", first " & tId
   else
      agLog "   FAILED: " & axLastError()
   end if
   if tId is empty then
      agLog "   (no identifier to carry forward - the remaining legs are skipped)"
      uiStatus "live probe: the first leg failed - see the log", "bad"
      exit agDoProbe
   end if
   put axThumbnailUrl(tId) into tUrl
   agLog "2. GET " & tUrl & " (the item image service)"
   put axGetSync(tUrl) into tBody
   if tBody is empty then
      agLog "   FAILED: " & axLastError()
   else
      agLog "   ok: " & the number of bytes of tBody & " bytes"
      put agSetPicture("agBigImage", tBody, (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)) into tSize
      if tSize is empty then
         agLog "   THE IMAGE OBJECT REFUSED THOSE BYTES - this engine will not decode that thumbnail"
      else
         agLog "   the image object took them: " & tSize & " pixels"
      end if
   end if
   agLog "3. axFetchItemSync " & tId & " (then its images playlist)"
   put axFetchItemSync(tId) into tItem
   put empty into tEntry
   if tItem is an array then
      agLog "   ok: " & tItem["filesCount"] & " files, mediatype " & axFirst(tItem["metadata"]["mediatype"]) & ", server " & tItem["server"]
      put axPlaylist(tItem, "images") into tPlaylist
      if tPlaylist is an array then
         put tPlaylist["entries"][1] into tEntry
         agLog "   playlist (images): " & tPlaylist["count"] & " entries; first " & tEntry["name"] & " (" & tEntry["format"] & ", " & axFormatBytes(tEntry["size"]) & ")"
      else
         agLog "   playlist FAILED: " & axLastError()
      end if
   else
      agLog "   FAILED: " & axLastError()
   end if
   if tEntry is not an array then
      uiStatus "live probe: three legs reported - see the log", "warn"
      exit agDoProbe
   end if
   agLog "4. GET " & tEntry["direct"] & " (the full picture, datanode URL)"
   put axGetSync(tEntry["direct"]) into tBody
   if tBody is empty then
      agLog "   FAILED: " & axLastError()
      uiStatus "live probe finished - see the log", "warn"
      exit agDoProbe
   end if
   agLog "   ok: " & the number of bytes of tBody & " bytes"
   put agSetPicture("agBigImage", tBody, (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)) into tSize
   if tSize is empty then
      agLog "   THE IMAGE OBJECT REFUSED THOSE BYTES - " & tEntry["format"] & " is a format this engine does not decode"
      uiStatus "live probe finished - the full picture was refused, see the log", "warn"
      exit agDoProbe
   end if
   agLog "   the image object took them: " & tSize & " pixels"
   agHidePlayer
   set the visible of image "agBigImage" to (sAgPane is "viewer")
   set the visible of field "agStageNote" to false
   uiStatus "live probe: all four legs green - the picture is on the stage", "ok"
end agDoProbe

-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing, tC, tFound
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL FOUR CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      --
      -- AND IMAGES (2026-08-31), for the same reason one step further out. A
      -- demo may build a control the KIT does not: coinxt's wallet paints a
      -- QR into an image, which is the only way a BMP this family builds
      -- becomes something a phone can read. Registered and built, it reported
      -- as missing - found by coinxt/tools/check-wallet-boot.py, which boots
      -- the stack headlessly, so this one cost no engine time. The lesson is
      -- the one this block already carries twice: the list of types a demo
      -- can build is not the list of types the KIT builds.
      --
      -- AND EVERY CARD (2026-08-29). Unqualified `there is a field X` answers
      -- for the CURRENT card only (engine notes 5.6) - OBSERVED when
      -- riptide's five-card boot reported all 63 off-card controls missing
      -- from a stack where every one existed. A single-card demo walks its
      -- one card here, exactly the old behaviour.
      put false into tFound
      repeat with tC = 1 to the number of cards of this stack
         if there is a field tName of card tC \
               or there is a button tName of card tC \
               or there is a graphic tName of card tC \
               or there is an image tName of card tC then
            put true into tFound
            exit repeat
         end if
      end repeat
      if not tFound then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- ==========================================================================
-- The boot self-check: what this gallery asserts about itself on open.
-- Every control this script names (the list is DERIVED by
-- tools/check-demo-control-lists.py), the thirty tile controls it builds
-- in a loop, the state agStart establishes, the grid's own arithmetic,
-- two pinned vectors through the embedded library, and - the one this
-- stack exists to ask - whether an image object on this engine takes a
-- picture at all. Nothing here hosts, connects, binds or fetches.
-- ==========================================================================

constant kAgScControls = "agBack,agBigImage,agCacheInfo,agCopyUrl,agDownload,agFamAny,agFamEtree,agFamImages,agFamLibrivox,agFamMovies,agGridPanel,agItemMeta,agItemTitle,agLog,agLogCap,agLouder,agNext,agOpenPage,agPageInfo,agPlay,agPrev,agProbe,agQuery,agQuieter,agSearch,agStage,agStageNote,agStopPlay,agTests,agTracks,agTracksHead,agViewNote,agViewPanel,uiFooter,uiStatus,uiTitle"

-- A 98-byte four-pixel PNG, carried in hex so the boot check needs no
-- network and no file. docs/OXT-ENGINE-NOTES.md section 5 has no entry
-- about image objects, because until this stack nothing in the tree put
-- bytes into one from a script and then asked what happened - so the
-- first thing this gallery does on open is settle it offline, on a
-- picture it brought with it.
constant kAgScPngHex = "89504e470d0a1a0a0000000d494844520000000400000004080200000026930929000000294944415478da0dc7310100000cc23084551867452170cb9724121b1713048be353a9adeb67323b370fa7631341061a2b550000000049454e44ae426082"

command agScRun
   local tMissing, tTiles, tI, tCaps, tPlaylist, tInfo, tRect, tSaved, tEdge, tSize
   local tLit, tWhich, tName, tNames, tCount
   scBegin "agLog"
   put scMissing(kAgScControls) into tMissing
   scAssert "all 36 controls this script names exist (missing: " & scShow(tMissing) & ")", tMissing is empty
   -- The tiles are built in a LOOP, so their names are computed and the
   -- derived list above cannot see them. They get their own line rather
   -- than a hand-kept entry in that constant, because a hand-kept twin of
   -- a generated set is what this tree keeps learning not to write.
   put empty into tTiles
   repeat with tI = 1 to kAgTiles
      put "agTileBox" & tI & comma & "agTileCap" & tI & comma & "agTileImg" & tI & comma after tTiles
   end repeat
   put char 1 to -2 of tTiles into tTiles
   put scMissing(tTiles) into tMissing
   put kAgTiles * 3 into tCount
   scAssert "all " & tCount & " tile controls exist (missing: " & scShow(tMissing) & ")", tMissing is empty
   scAssert "the grid is " & kAgCols & " by " & kAgGridRows & " and that is " & kAgTiles & " tiles", kAgCols * kAgGridRows is kAgTiles
   -- THE PAGE IS NOT THE SCREEN, and the two were one number until the
   -- first engine run showed ten of 29,281 hits. A page that is not a
   -- whole number of screens would leave a short last screen inside every
   -- page, which is not wrong but is not what agStepScreen's arithmetic
   -- was written for.
   scAssert "a request brings back " & kAgPageSize & ", which is " & (kAgPageSize / kAgTiles) & " whole screens", kAgPageSize >= kAgTiles and (kAgPageSize / kAgTiles) is an integer
   scAssert "axVersion reports the member", axVersion() begins with "ArchiveXT"
   scAssert "the movies family is in play at boot", sAgFamily is "movies"
   put 0 into tLit
   put empty into tWhich
   -- LINES, NOT ITEMS. A `repeat for each item` here would read the
   -- ambient itemDelimiter, which is the one thing this file sets and
   -- restores everywhere else; lines cost nothing and depend on nothing.
   put "agFamMovies" & return & "agFamEtree" & return & "agFamLibrivox" & return & "agFamImages" & return & "agFamAny" into tNames
   repeat for each line tName in tNames
      if there is a button tName then
         if the hilite of button tName then
            add 1 to tLit
            put tName into tWhich
         end if
      end if
   end repeat
   scAssert "exactly one family button is lit, and it is the movies one (" & scShow(tWhich) & ")", tLit is 1 and tWhich is "agFamMovies"
   scAssert "the grid pane is up at boot", sAgPane is "grid"
   scAssert "no tile holds a picture at boot", sAgTilePics[1] is "false"
   put agFamilyFor("images") into tInfo
   scAssert "the gallery's own fifth family carries the image mediatype", tInfo["scope"] is "mediatype:(image)"
   scAssert "an image item plays as pictures", agPlaylistKindOf("any", "image") is "images"
   scAssert "the thumbnail URL is the item image service", axThumbnailUrl("nasa") is "https://archive.org/services/img/nasa"
   -- The grid's arithmetic, so a moved constant cannot quietly push the
   -- bottom row's captions off the panel they are drawn on.
   put agCapRect(kAgTiles) into tRect
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put item 4 of tRect into tEdge
   set the itemDelimiter to tSaved
   scAssert "the last tile's caption ends inside the grid panel (" & scShow(tEdge) & " of " & kAgPaneB & ")", tEdge <= kAgPaneB
   put axPlaylist(axItemParse(axtHex(kAxVecFixEtreeItemHex)), "audio-tracks") into tPlaylist
   scAssert "the etree fixture plays as six tracks", tPlaylist["count"] is 6
   scAssert "every playlist entry carries a stream URL and a datanode URL", tPlaylist["entries"][1]["url"] is not empty and tPlaylist["entries"][1]["direct"] is not empty
   -- THE QUESTION THIS DEMO IS ABOUT. agSetPicture answers empty when the
   -- control refused the bytes, so a FAIL here says the gallery will show
   -- captions over empty frames on this engine and says it in the first
   -- second, rather than after ten thumbnails have been fetched.
   -- the bytes BEFORE the picture, because the first engine run failed
   -- here on a decoder rather than on an image object
   scAssert "the carried PNG decodes to 98 bytes", the number of bytes of agHexBytes(kAgScPngHex) is 98
   scAssert "and a hex string with a non-hex character is refused", agHexBytes("47zz") is empty
   put agSetPicture("agBigImage", agHexBytes(kAgScPngHex), "0,0,4,4") into tSize
   scAssert "an image object takes a picture this stack carries (" & scShow(tSize) & ")", tSize is "4x4"
   -- AND THE OTHER DIRECTION, which is the half that was missing when the
   -- first engine run reported a refusal as a 684-pixel picture. A
   -- positive vector cannot catch a check that is not being made: this
   -- one feeds bytes that are certainly not an image and requires
   -- agSetPicture to ANSWER EMPTY, so what a refusal looks like on this
   -- engine is measured on every open rather than assumed once.
   put agSetPicture("agBigImage", "this is not a picture", "0,0,4,4") into tSize
   scAssert "and refuses bytes that are not a picture (" & scShow(tSize) & ")", tSize is empty
   set the text of image "agBigImage" to empty
   set the lockLocation of image "agBigImage" to true
   set the rect of image "agBigImage" to (kAgStageL & comma & kAgStageT & comma & kAgStageR & comma & kAgStageB)
   set the visible of image "agBigImage" to false
   scAssert "nothing is in flight at boot", axPending() is 0
   scAssert "no thumbnail is queued or out at boot", sAgQueue is empty and sAgInFlight is 0
   scAssert "the cache starts empty and has asked the site for nothing", sAgHits is 0 and sAgMisses is 0
   if sAgDisk is empty then
      scSkip "the disk cache has a folder", "neither Documents nor the temporary folder was writable"
   else
      scAssert "the disk cache has a folder (" & scShow(sAgDisk) & ")", there is a folder sAgDisk
   end if
   put axProbeCapabilities() into tCaps
   if tCaps["hasUrlLib"] is true then
      scAssert "the Internet library answers (" & scShow(tCaps["urlLibVersion"]) & ")", true
   else
      scSkip "the Internet library answers", "libURLVersion did not answer on this engine"
   end if
   scArmProbe
end agScRun
