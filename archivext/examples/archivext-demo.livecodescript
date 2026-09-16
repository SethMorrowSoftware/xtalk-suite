script "ArchiveExplorer"
-- archivext-demo.livecodescript - the ArchiveXT showcase: three archive.org
-- apps in one paste-and-run stack.
--
-- WHAT THIS IS. One window that does what three shipped web apps do, over
-- the same library: Archive Film Club (the Moving Image Archive's film
-- collections, episode lists with quality variants), the Grateful Dead
-- Tape Finder (the Live Music Archive's band collections with SBD/AUD/
-- matrix/top-rated filters and year ranges, a concert's track list), and
-- the LibriVox AudioBooks app (categories, author and title search, a
-- book's chapters) - plus a fourth, generic family that searches any
-- archive.org media type and lists whatever the item holds (documents,
-- images, files). Pick a family, a preset, type a query, search; open an
-- item to see its playlist; open its page in the browser, copy a stream
-- URL, or hand the stream to a player object. It CARRIES the archivext
-- library and the member harness verbatim between the embed sentinels
-- below (tools/sync-demo-embeds.py owns that region), so there is nothing
-- to `start using` first. It needs no extension at all: ArchiveXT is pure
-- script, and the network calls go through the engine's own Internet
-- library.
--
-- WHAT TO LOOK AT AS A TEMPLATE. onArchive is the whole fetch-layer
-- contract in one handler; adDoSearch is preset + text + filters -> query
-- -> request in four lines; adShowItem is item -> playlist -> table.
--
-- HOW TO USE. Paste into a new stack script, then close and reopen the
-- stack. The window builds itself. Opening this file directly does not
-- build it (docs/OXT-ENGINE-NOTES.md 5.5).
--
-- HONESTY (the suite convention): verified statically + the library's
-- pure layer executed headlessly against synthetic fixtures; needs an OXT
-- pass + a live archive.org pass. Nothing here has run on a real engine.
-- The Internet library's https behaviour on this engine is unmeasured
-- (root docs/OXT-ENGINE-NOTES.md 6.8 records the suite's only TLS
-- observation, and it is a socket, not libURL); the player object's
-- ability to stream a URL is the engine's, per platform, and untested.
--
-- THE LOOK. This stack adopts the suite UI kit v2 verbatim (the marked
-- block below); the kit block is never edited here - a look change edits
-- tools/ui-kit.livecodescript and re-carries.

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
   put axScrapeParse("{" & quote & "items" & quote & ":[{" & quote & "identifier" & quote & ":" & quote & "a" & quote & "," & quote & "subject" & quote & ":[" & quote & "x" & quote & "," & quote & "y" & quote & "]},{" & quote & "identifier" & quote & ":" & quote & "b" & quote & "}]," & quote & "count" & quote & ":2," & quote & "cursor" & quote & ":" & quote & "W3siaWQiOjF9XQ==" & quote & "," & quote & "total" & quote & ":17}") into tResult
   axtCheck tResult is an array, "a scrape page parses"
   axtCheck tResult["count"] is 2, "scrape: count"
   axtCheck tResult["total"] is 17, "scrape: total"
   axtCheck tResult["cursor"] is "W3siaWQiOjF9XQ==", "scrape: the cursor"
   axtCheck axFirst(tResult["items"][2]["identifier"]) is "b", "scrape: items in order"
   axtCheck axtJoinLines(tResult["items"][1]["subject"], "|") is "x|y", "scrape: a multi-valued field is lines"
   put axScrapeParse("{" & quote & "items" & quote & ":[]," & quote & "count" & quote & ":0}") into tResult
   axtCheck tResult["cursor"] is empty, "scrape: the last page has no cursor"
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
-- Demo constants and state.
-- ==========================================================================

-- Bumped whenever the generated UI changes so a saved stack rebuilds.
-- BUMP THIS whenever a control is added, removed or moved: adBuild rebuilds
-- the window only when the stack's stored version differs, so a new button
-- pasted into an already-built stack is otherwise never created (2026-09-15:
-- the Live probe button shipped under the old value and the boot self-check
-- reported it missing on the first open - the self-check is the net, this
-- line is the rule).
constant kAdUiVersion = "archive-explorer-kit2-3"
constant kAdWinW = 1180
constant kAdWinH = 630
constant kAdPlayerName = "adPlayer"

local sAdFamily              -- the family id in play (etree / librivox / movies / any)
local sAdPreset              -- the selected preset id
local sAdPresetIds           -- one preset id per line of the preset table ("" on a group header)
local sAdFilterIds           -- the family's filter ids, comma list, in checkbox order
local sAdFilterOn            -- sAdFilterOn[id] is "true" while that filter is checked
local sAdSort                -- the sort menu id in play
local sAdPage                -- the page shown
local sAdResult              -- the last axSearchParse array
local sAdItem                -- the last axItemParse array
local sAdPlaylist            -- the playlist of that item
local sAdSearchHandle        -- the request in flight for the results table, or empty
local sAdItemHandle          -- the request in flight for the item, or empty
local sAdHaveUrlLib          -- the boot probe's answer
local sAdDownloadHandle      -- the download in flight, or empty
local sAdDownloadPath        -- where that download is being written
local sAdPlayAfter           -- true when the finished download should play
local sAdPlayUrl             -- the URL the player was last handed (empty after Stop)

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
   adBuild
   adStart
   adScRun
end openStack

on closeStack
   adStop
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   if tName is "adFamMovies" then
      adSetFamily "movies"
   else if tName is "adFamEtree" then
      adSetFamily "etree"
   else if tName is "adFamLibrivox" then
      adSetFamily "librivox"
   else if tName is "adFamAny" then
      adSetFamily "any"
   else if tName is "adPresets" then
      adSelectPreset
   else if tName is "adFilter1" then
      adToggleFilter 1
   else if tName is "adFilter2" then
      adToggleFilter 2
   else if tName is "adFilter3" then
      adToggleFilter 3
   else if tName is "adFilter4" then
      adToggleFilter 4
   else if tName is "adSearch" then
      adDoSearch 1
   else if tName is "adPrev" then
      adDoSearch sAdPage - 1
   else if tName is "adNext" then
      adDoSearch sAdPage + 1
   else if tName is "adRandom" then
      adDoRandom
   else if tName is "adSort" then
      adCycleSort
   else if tName is "adResults" then
      adOpenSelected
   else if tName is "adOpenPage" then
      adDoOpenPage
   else if tName is "adCopyUrl" then
      adDoCopyUrl
   else if tName is "adPlay" then
      adDoPlay
   else if tName is "adStopPlay" then
      adDoStopPlay
   else if tName is "adDownload" then
      adDoDownload false
   else if tName is "adTests" then
      adDoSelfTest
   else if tName is "adProbe" then
      adDoProbe
   else
      pass mouseUp
   end if
end mouseUp

-- ==========================================================================
-- Build: the whole window, in script, kit look, inside the 720p budget.
-- Three columns: explore (family, preset, filters, years), search (query,
-- results, paging), item (details, playlist, actions, log).
-- ==========================================================================

command adBuild
   if the uAdUiVersion of this stack is kAdUiVersion and there is a field "adLog" then
      exit adBuild
   end if
   lock screen
   adClearGeneratedUI
   uiChrome "ArchiveXT demo - archive.org from xTalk", kAdWinW, kAdWinH
   -- Panels first, for z-order (the kit rule).
   uiPanel "adExplorePanel", "16,46,300,580"
   uiPanel "adSearchPanel", "310,46,740,580"
   uiPanel "adItemPanel", "750,46,1164,580"
   -- Explore.
   uiSection "adFamilyCap", "1. Family", "28,54,288,72"
   uiButton "adFamMovies", "Films and video", "28,78,288,100"
   uiButton "adFamEtree", "Live music (etree)", "28,104,288,126"
   uiButton "adFamLibrivox", "Audiobooks (LibriVox)", "28,130,288,152"
   uiButton "adFamAny", "Everything (any media type)", "28,156,288,178"
   uiSection "adPresetCap", "2. Preset", "28,186,288,204"
   uiTable "adPresets", "28,208,288,430", empty
   uiSection "adFilterCap", "3. Filters and years", "28,438,288,456"
   uiCheckbox "adFilter1", empty, "28,460,288,478"
   uiCheckbox "adFilter2", empty, "28,480,288,498"
   uiCheckbox "adFilter3", empty, "28,500,288,518"
   uiCheckbox "adFilter4", empty, "28,520,288,538"
   uiCap "adYearCap", "year from / to (four digits; blank for any)", "28,542,288,556"
   uiInput "adYearFrom", "28,558,150,578"
   uiInput "adYearTo", "166,558,288,578"
   -- Search.
   uiSection "adSearchCap", "4. Search", "322,54,728,72"
   uiInput "adQuery", "322,78,640,100"
   uiButton "adSearch", "Search", "646,78,728,100"
   uiCap "adQueryNote", "text is sanitized for Lucene; the exact query and URL land in the log", "322,104,728,118"
   uiLabel "adResultsHead", "title" & tab & "creator" & tab & "date", "322,124,728,140", 10
   set the tabStops of field "adResultsHead" to "230,330"
   set the foregroundColor of field "adResultsHead" to kUiMuted
   uiTable "adResults", "322,142,728,516", "230,330"
   uiLabel "adPageInfo", "no search yet", "322,522,560,544", 10
   uiButton "adPrev", "Prev", "566,522,610,544"
   uiButton "adNext", "Next", "614,522,658,544"
   uiButton "adRandom", "Random", "662,522,728,544"
   uiButton "adSort", "Sort: Most downloaded", "322,550,540,572"
   uiCap "adSortNote", "click a result to open the item", "548,552,728,570"
   -- Item.
   uiSection "adItemCap", "5. Item", "762,54,1152,72"
   uiWrap "adItemTitle", "nothing open yet", "762,78,1152,110", 12
   uiArea "adItemMeta", "762,114,1152,200"
   uiLabel "adTracksHead", "#" & tab & "title" & tab & "length" & tab & "format", "762,206,1152,222", 10
   set the tabStops of field "adTracksHead" to "30,300,350"
   set the foregroundColor of field "adTracksHead" to kUiMuted
   uiTable "adTracks", "762,224,1152,430", "30,300,350"
   uiButton "adOpenPage", "Open page", "762,436,846,458"
   uiButton "adCopyUrl", "Copy URL", "850,436,926,458"
   uiButton "adPlay", "Play", "930,436,994,458"
   uiButton "adStopPlay", "Stop", "998,436,1058,458"
   uiButton "adDownload", "Download", "1062,436,1152,458"
   uiCap "adItemNote", "Play streams the datanode URL in a player (falls back to download-and-play); Download saves to Documents/ArchiveXT", "762,462,1152,476"
   uiSection "adLogCap", "Log", "762,482,950,500"
   uiButton "adTests", "Run axSelfTest", "954,482,1050,500"
   uiButton "adProbe", "Live probe", "1056,482,1152,500"
   uiArea "adLog", "762,504,1152,570"
   uiFooter "This stack demonstrates ArchiveXT: search, metadata and streaming URLs from archive.org, with the three source apps' presets and file rules. It stores nothing and fetches only what you ask for. Verified statically + headless fixtures; needs an OXT pass + a live archive.org pass.", "16,586,1164,626"
   set the uAdUiVersion of this stack to kAdUiVersion
   unlock screen
end adBuild

command adClearGeneratedUI
   -- Rebuild-proof: drop every control this script generates, then let
   -- adBuild remake them.
   repeat while the number of controls of this card > 0
      delete control 1 of this card
   end repeat
end adClearGeneratedUI

command adStart
   local tCaps
   set the defaultStack to the short name of this stack
   axInit the long id of me
   axSetCallback "onArchive"
   put empty into sAdResult
   put empty into sAdItem
   put empty into sAdPlaylist
   put empty into sAdSearchHandle
   put empty into sAdItemHandle
   put empty into sAdDownloadHandle
   put empty into sAdDownloadPath
   put empty into sAdPlayAfter
   put empty into sAdPlayUrl
   put "downloads" into sAdSort
   put 1 into sAdPage
   put axProbeCapabilities() into tCaps
   put tCaps["hasUrlLib"] is true into sAdHaveUrlLib
   adSetFamily "movies"
   if sAdHaveUrlLib is true then
      uiStatus "Ready - " & axVersion() & " over " & tCaps["urlLibVersion"], "ok"
   else
      adLog "The Internet library (libURL) did not answer: searches will refuse. A standalone needs the Internet inclusion."
      uiStatus "Ready, but no Internet library on this engine - searches will refuse (fail closed)", "warn"
   end if
end adStart

command adStop
   -- Guarded teardown: forget every request in flight (a late reply is
   -- dropped by the layer), the download among them, and stop the player
   -- if one was made.
   local tError
   try
      if sAdDownloadHandle is not empty then
         axCancel sAdDownloadHandle
      end if
   catch tError
   end try
   put empty into sAdDownloadHandle
   try
      axShutdown
   catch tError
   end try
   try
      adDoStopPlay
   catch tError
   end try
end adStop

-- ==========================================================================
-- Explore: family, presets, filters.
-- ==========================================================================

command adSetFamily pFamily
   local tRows, tCount, tI, tLine, tSavedDelim, tGroup, tLastGroup, tText, tIds
   local tFilters, tFilterCount, tInfo
   set the defaultStack to the short name of this stack
   put pFamily into sAdFamily
   put axPresetList(pFamily) into tRows
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put the number of lines of tRows into tCount
   put empty into tText
   put empty into tIds
   put empty into tLastGroup
   put empty into sAdPreset
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      put item 3 of tLine into tGroup
      if tGroup is not tLastGroup then
         put axLowerAscii(tGroup) & return after tText
         put return after tIds
         put tGroup into tLastGroup
      end if
      put "   " & item 2 of tLine & return after tText
      put item 1 of tLine & return after tIds
      if sAdPreset is empty then
         put item 1 of tLine into sAdPreset
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   put char 1 to -2 of tText into field "adPresets"
   put char 1 to -2 of tIds into sAdPresetIds
   -- the filters: one checkbox per family filter, the rest hidden
   put axFilterList(pFamily) into tFilters
   put the number of lines of tFilters into tFilterCount
   put empty into sAdFilterIds
   put empty into sAdFilterOn
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   repeat with tI = 1 to 4
      if tI <= tFilterCount then
         put line tI of tFilters into tLine
         set the label of button ("adFilter" & tI) to item 2 of tLine
         set the hilite of button ("adFilter" & tI) to false
         set the visible of button ("adFilter" & tI) to true
         if sAdFilterIds is not empty then
            put "," after sAdFilterIds
         end if
         put item 1 of tLine after sAdFilterIds
      else
         set the label of button ("adFilter" & tI) to empty
         set the hilite of button ("adFilter" & tI) to false
         set the visible of button ("adFilter" & tI) to false
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   put axFamilyInfo(pFamily) into tInfo
   adApplyPresetYears
   put empty into field "adQuery"
   adLog "family: " & tInfo["title"] & " - " & tCount & " presets, " & tFilterCount & " filters, " & tInfo["rows"] & " rows a page, playlist kind " & tInfo["kind"]
   uiStatus tInfo["title"] & " - pick a preset (" & sAdPreset & " is selected), type a query, Search", "ok"
end adSetFamily

command adSelectPreset
   local tLine, tId
   set the defaultStack to the short name of this stack
   put the hilitedLine of field "adPresets" into tLine
   if tLine is not an integer then
      exit adSelectPreset
   end if
   put line tLine of sAdPresetIds into tId
   if tId is empty then
      -- a group header line: nothing to select
      exit adSelectPreset
   end if
   put tId into sAdPreset
   adApplyPresetYears
   adLog "preset: " & tId & " -> " & axPresetQuery(sAdFamily, tId)
   uiStatus "preset " & tId & " - Search when ready", "ok"
end adSelectPreset

command adApplyPresetYears
   -- The tape finder fills its year boxes from the preset (Grateful Dead
   -- 1965-1995); a preset without a range clears them.
   local tInfo
   put axPresetInfo(sAdFamily, sAdPreset) into tInfo
   if tInfo is empty then
      put empty into field "adYearFrom"
      put empty into field "adYearTo"
      exit adApplyPresetYears
   end if
   put tInfo["yearFrom"] into field "adYearFrom"
   put tInfo["yearTo"] into field "adYearTo"
end adApplyPresetYears

command adToggleFilter pIndex
   local tId, tOn
   set the defaultStack to the short name of this stack
   put item pIndex of sAdFilterIds into tId
   if tId is empty then
      exit adToggleFilter
   end if
   put sAdFilterOn[tId] is "true" into tOn
   if tOn then
      put "false" into sAdFilterOn[tId]
   else
      put "true" into sAdFilterOn[tId]
   end if
   -- script-managed hilite: the kit's checkbox has autoHilite off
   set the hilite of button ("adFilter" & pIndex) to (not tOn)
   adLog "filter " & tId & ": " & (not tOn) & " -> " & axFilterClause(sAdFamily, tId)
end adToggleFilter

function adActiveFilterIds
   local tOut, tId
   put empty into tOut
   repeat for each item tId in sAdFilterIds
      if sAdFilterOn[tId] is "true" then
         if tOut is not empty then
            put "," after tOut
         end if
         put tId after tOut
      end if
   end repeat
   return tOut
end adActiveFilterIds

-- ==========================================================================
-- Search.
-- ==========================================================================

command adDoSearch pPage
   local tSpec, tQuery, tInfo, tOptions, tHandle, tPage
   set the defaultStack to the short name of this stack
   put pPage into tPage
   if tPage is not an integer then
      put 1 into tPage
   end if
   if tPage < 1 then
      put 1 into tPage
   end if
   if sAdHaveUrlLib is not true then
      uiStatus "no Internet library on this engine - cannot search", "bad"
      exit adDoSearch
   end if
   put axPresetSpec(sAdFamily, sAdPreset, field "adQuery", field "adYearFrom", field "adYearTo", axFilterClauses(sAdFamily, adActiveFilterIds())) into tSpec
   if tSpec is empty then
      uiStatus "no preset is selected: " & axLastError(), "bad"
      exit adDoSearch
   end if
   put axQueryBuild(tSpec) into tQuery
   if tQuery is empty then
      uiStatus "nothing to search for - pick a preset or type a query (" & axLastError() & ")", "warn"
      exit adDoSearch
   end if
   put axFamilyInfo(sAdFamily) into tInfo
   put tInfo["fields"] into tOptions["fields"]
   put axSortClause(sAdSort) into tOptions["sort"]
   put tInfo["rows"] into tOptions["rows"]
   put tPage into tOptions["page"]
   put "results" into tOptions["tag"]
   if sAdSearchHandle is not empty then
      axCancel sAdSearchHandle
      adLog "cancelled the previous search (its late reply will be dropped)"
   end if
   put axSearch(tQuery, tOptions) into tHandle
   if tHandle is empty then
      uiStatus "search refused: " & axLastError(), "bad"
      adLog "axSearch: " & axLastError()
      exit adDoSearch
   end if
   put tHandle into sAdSearchHandle
   put tPage into sAdPage
   adLog "q = " & tQuery
   adLog "GET " & axSearchUrl(tQuery, tOptions["fields"], tOptions["sort"], tOptions["rows"], tPage)
   uiStatus "searching (request " & tHandle & ")...", "warn"
end adDoSearch

command adShowResults pResult
   local tCount, tI, tDoc, tLines, tTitle, tCreator, tDate, tPages, tRows, tInfo
   put pResult into sAdResult
   put pResult["count"] into tCount
   put empty into tLines
   repeat with tI = 1 to tCount
      put pResult["docs"][tI] into tDoc
      put axFirst(tDoc["title"]) into tTitle
      if tTitle is empty then
         put axFirst(tDoc["identifier"]) into tTitle
      end if
      if axFirst(tDoc["mediatype"]) is "collection" then
         put "[collection] " & tTitle into tTitle
      end if
      put axJoin(tDoc["creator"], ", ") into tCreator
      put axFirst(tDoc["date"]) into tDate
      if tDate is empty then
         put axFirst(tDoc["year"]) into tDate
      end if
      put axCollapseSpaces(tTitle) & tab & axCollapseSpaces(tCreator) & tab & char 1 to 10 of tDate & return after tLines
   end repeat
   put char 1 to -2 of tLines into field "adResults"
   put axFamilyInfo(sAdFamily) into tInfo
   put tInfo["rows"] into tRows
   put trunc((pResult["numFound"] + tRows - 1) / tRows) into tPages
   put "page " & sAdPage & " of " & tPages & " - " & pResult["numFound"] & " found (the site over-reports; a short page is the end)" into field "adPageInfo"
   set the enabled of button "adPrev" to (sAdPage > 1)
   set the enabled of button "adNext" to (tCount >= tRows)
   adLog "results: " & tCount & " of " & pResult["numFound"]
   if tCount is 0 then
      uiStatus "no results - try another preset, fewer filters, or a wider year range", "warn"
   else
      uiStatus tCount & " results on page " & sAdPage & " - click one to open it", "ok"
   end if
end adShowResults

command adOpenSelected
   local tLine, tDoc, tId, tHandle
   set the defaultStack to the short name of this stack
   put the hilitedLine of field "adResults" into tLine
   if tLine is not an integer then
      exit adOpenSelected
   end if
   if sAdResult is not an array then
      exit adOpenSelected
   end if
   put sAdResult["docs"][tLine] into tDoc
   put axFirst(tDoc["identifier"]) into tId
   if not axIdentifierIsValid(tId) then
      uiStatus "that result has no usable identifier", "bad"
      exit adOpenSelected
   end if
   if sAdItemHandle is not empty then
      axCancel sAdItemHandle
   end if
   put axFetchItem(tId, "item") into tHandle
   if tHandle is empty then
      uiStatus "item fetch refused: " & axLastError(), "bad"
      exit adOpenSelected
   end if
   put tHandle into sAdItemHandle
   adLog "GET " & axMetadataUrl(tId)
   uiStatus "fetching " & tId & " (request " & tHandle & ")...", "warn"
end adOpenSelected

command adShowItem pItem
   local tMeta, tKind, tText, tFieldName, tPlaylist, tTitle
   put pItem into sAdItem
   put pItem["metadata"] into tMeta
   put axFirst(tMeta["title"]) into tTitle
   if tTitle is empty then
      put pItem["identifier"] into tTitle
   end if
   put tTitle & " - " & axJoin(tMeta["creator"], ", ") into tText
   if axFirst(tMeta["date"]) is not empty then
      put " (" & axYearOf(axFirst(tMeta["date"])) & ")" after tText
   end if
   put tText into field "adItemTitle"
   put "identifier: " & pItem["identifier"] & return into tText
   put "mediatype: " & axFirst(tMeta["mediatype"]) & "   collection: " & axJoin(tMeta["collection"], ", ") & return after tText
   repeat for each item tFieldName in "venue,coverage,source,lineage,taper,runtime,language,licenseurl,downloads,avg_rating,num_reviews"
      if tMeta[tFieldName] is not empty then
         put tFieldName & ": " & axJoin(tMeta[tFieldName], ", ") & return after tText
      end if
   end repeat
   if tMeta["subject"] is not empty then
      put "subjects: " & axJoin(axSubjectTags(tMeta["subject"], 6), ", ") & return after tText
   end if
   if tMeta["description"] is not empty then
      put return & char 1 to 700 of axCollapseSpaces(axJoin(tMeta["description"], " ")) & return after tText
   end if
   if tMeta["setlist"] is not empty then
      put return & "setlist:" & return & tMeta["setlist"] & return after tText
   end if
   put tText into field "adItemMeta"
   put axPlaylistKindFor(sAdFamily, tMeta["mediatype"]) into tKind
   put axPlaylist(pItem, tKind) into tPlaylist
   put tPlaylist into sAdPlaylist
   if tPlaylist is empty then
      put empty into field "adTracks"
      adLog "no " & tKind & " playlist: " & axLastError()
      uiStatus "opened " & pItem["identifier"] & " - " & pItem["filesCount"] & " files, none of kind " & tKind, "warn"
      exit adShowItem
   end if
   put axPlaylistTable(tPlaylist) into field "adTracks"
   set the hilitedLine of field "adTracks" to 1
   adLog "item " & pItem["identifier"] & ": " & pItem["filesCount"] & " files -> " & tPlaylist["count"] & " " & tKind & " entries"
   uiStatus "opened " & pItem["identifier"] & " - " & tPlaylist["count"] & " entries (" & tKind & "); select one, then Copy or Play", "ok"
end adShowItem

function adSelectedEntry
   local tLine
   if sAdPlaylist is not an array then
      return empty
   end if
   put the hilitedLine of field "adTracks" into tLine
   if tLine is not an integer then
      put 1 into tLine
   end if
   if tLine < 1 then
      return empty
   end if
   if tLine > sAdPlaylist["count"] then
      return empty
   end if
   return sAdPlaylist["entries"][tLine]
end adSelectedEntry

command adDoRandom
   -- The tape finder's rule: a random pick from the page already on
   -- screen. Nothing hits the network.
   local tCount, tPick
   set the defaultStack to the short name of this stack
   if sAdResult is not an array then
      uiStatus "run a search first, then Random picks from its page", "warn"
      exit adDoRandom
   end if
   put sAdResult["count"] into tCount
   if tCount < 1 then
      uiStatus "the page is empty", "warn"
      exit adDoRandom
   end if
   put random(tCount) into tPick
   set the hilitedLine of field "adResults" to tPick
   adOpenSelected
end adDoRandom

command adCycleSort
   local tRows, tCount, tI, tLine, tSavedDelim, tNext
   set the defaultStack to the short name of this stack
   put axSortList() into tRows
   put the number of lines of tRows into tCount
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put line 1 of tRows into tNext
   repeat with tI = 1 to tCount
      put line tI of tRows into tLine
      if item 1 of tLine is sAdSort then
         if tI < tCount then
            put line (tI + 1) of tRows into tNext
         end if
         exit repeat
      end if
   end repeat
   put item 1 of tNext into sAdSort
   set the label of button "adSort" to "Sort: " & item 2 of tNext
   set the itemDelimiter to tSavedDelim
   adLog "sort: " & sAdSort & " -> " & axSortClause(sAdSort) & " (Search again to apply)"
end adCycleSort

-- ==========================================================================
-- Item actions.
-- ==========================================================================

command adDoOpenPage
   local tUrl, tError
   set the defaultStack to the short name of this stack
   if sAdItem is not an array then
      uiStatus "open an item first", "warn"
      exit adDoOpenPage
   end if
   put axDetailsUrl(sAdItem["identifier"]) into tUrl
   if tUrl is empty then
      uiStatus axLastError(), "bad"
      exit adDoOpenPage
   end if
   try
      launch URL tUrl
      adLog "launched " & tUrl
      uiStatus "opened the item's page in the browser", "ok"
   catch tError
      adLog "launch URL failed: " & tError
      uiStatus "could not launch a browser: " & tError, "bad"
   end try
end adDoOpenPage

command adDoCopyUrl
   local tEntry, tError
   set the defaultStack to the short name of this stack
   put adSelectedEntry() into tEntry
   if tEntry is empty then
      uiStatus "open an item and select an entry first", "warn"
      exit adDoCopyUrl
   end if
   try
      set the clipboardData["text"] to tEntry["url"]
      uiCopyFlash "adCopyUrl"
      adLog "copied " & tEntry["url"]
      uiStatus "stream URL copied", "ok"
   catch tError
      uiStatus "could not reach the clipboard: " & tError, "bad"
   end try
end adDoCopyUrl

command adDoPlay
   -- STREAM the selected entry: hand the DATANODE URL (axDirectUrl - the
   -- host and directory the metadata names, where /download/ redirects to)
   -- to a player object drawn over the playlist, and check six seconds
   -- later whether the player actually opened it. The 2026-09-16 report was
   -- "the player is still not working" with no error anywhere: a player
   -- handed a URL it cannot open throws nothing and plays nothing, so the
   -- check is the only way to KNOW, and when it fails the demo downloads
   -- the file and plays it from disk instead - which is the path every
   -- platform's media stack can take. The player is created on demand and
   -- named through a variable ON PURPOSE: the boot self-check derives its
   -- control list from every literal control name in this script, and a
   -- control that exists only after Play would read as missing at boot.
   local tEntry, tError, tName, tUrl, tWhy
   set the defaultStack to the short name of this stack
   put adSelectedEntry() into tEntry
   if tEntry is empty then
      uiStatus "open an item and select an entry first", "warn"
      exit adDoPlay
   end if
   put tEntry["direct"] into tUrl
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   put kAdPlayerName into tName
   try
      if there is no player tName then
         create player
         set the name of the last player to tName
      end if
      set the rect of player tName to the rect of field "adTracks"
      set the showController of player tName to true
      set the visible of field "adTracks" to false
      set the visible of player tName to true
      set the filename of player tName to tUrl
      put the result into tWhy
      adLog "play: " & tUrl & " (" & tEntry["format"] & ", " & axFormatBytes(tEntry["size"]) & ") on " & the platform & " " & the systemVersion
      if tWhy is not empty then
         -- the platform player's SYNCHRONOUS verdict (DirectShow's
         -- RenderFile, AVFoundation's typing) - "could not create movie
         -- reference" is the usual text; no need to wait six seconds
         adLog "the player refused the stream at once: " & tWhy & " - downloading the file and playing it from disk instead"
         set the visible of player tName to false
         set the visible of field "adTracks" to true
         adDoDownload true
         exit adDoPlay
      end if
      start player tName
      put tUrl into sAdPlayUrl
      uiStatus "opening the stream in the engine's player (" & tEntry["title"] & ")...", "warn"
      adArmPlayCheck
   catch tError
      adLog "player failed: " & tError & " - downloading the file instead"
      set the visible of field "adTracks" to true
      adDoDownload true
   end try
end adDoPlay

command adArmPlayCheck
   -- One pending check at a time: a second Play inside the six seconds
   -- would otherwise leave the first check to judge the second stream.
   local tLine
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine begins with "adPlayCheck" then
         cancel item 1 of tLine
      end if
   end repeat
   send "adPlayCheck" to me in 6 seconds
end adArmPlayCheck

command adPlayCheck
   -- Six seconds after Play: a player that opened its stream reports a
   -- duration (and, if it is playing, a moving currentTime); one that
   -- could not open it reports 0 for both and NO error. Only the second
   -- case falls back, and only if the user has not moved on.
   local tName, tDuration, tTime, tError, tUrl
   set the defaultStack to the short name of this stack
   put kAdPlayerName into tName
   put sAdPlayUrl into tUrl
   if tUrl is empty then
      exit adPlayCheck
   end if
   if there is no player tName then
      exit adPlayCheck
   end if
   if the filename of player tName is not tUrl then
      exit adPlayCheck
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
   if tDuration > 0 or tTime > 0 then
      if axIsHttpUrl(tUrl) then
         adLog "the player opened the stream: duration " & tDuration & ", currentTime " & tTime & " (timeScale " & the timeScale of player tName & ")"
         uiStatus "streaming from archive.org in the engine's player; Stop puts the list back", "ok"
      else
         adLog "the player opened the local file: duration " & tDuration & ", currentTime " & tTime & " (timeScale " & the timeScale of player tName & ")"
         uiStatus "playing the downloaded file in the engine's player; Stop puts the list back", "ok"
      end if
      exit adPlayCheck
   end if
   put empty into sAdPlayUrl
   adDoStopPlay
   if axIsHttpUrl(tUrl) then
      adLog "the player reports duration 0 and currentTime 0 six seconds after start on " & the platform & ": it could not open the stream - downloading the file and playing it from disk instead"
      adDoDownload true
      exit adPlayCheck
   end if
   -- a LOCAL file the player could not open either: this engine has no
   -- working player for the format (Linux builds have none at all), so
   -- hand the file to the system player and STOP - never download again
   adLog "the player reports duration 0 six seconds after start on the LOCAL file too, on " & the platform & ": no in-window playback for this format on this engine - opening it with the system player"
   try
      launch document tUrl
      put the result into tError
      if tError is empty then
         uiStatus "no in-window playback on this engine; the file opened in the system player", "warn"
      else
         uiStatus "no in-window playback on this engine, and the system player refused: " & tError, "bad"
      end if
   catch tError
      uiStatus "no in-window playback on this engine, and the system player refused: " & tError, "bad"
   end try
end adPlayCheck

command adDoDownload pPlayAfter
   -- DOWNLOAD the selected entry to Documents/ArchiveXT/<identifier>/ (the
   -- temporary folder when Documents is not writable) through axDownload,
   -- which writes straight to disk with progress and a stall watchdog;
   -- pPlayAfter true plays the file when it lands. A file already there at
   -- the size the metadata promised is reused rather than fetched again.
   local tEntry, tFolder, tPath, tName, tHandle, tError, tUrl
   set the defaultStack to the short name of this stack
   put adSelectedEntry() into tEntry
   if tEntry is empty then
      uiStatus "open an item and select an entry first", "warn"
      exit adDoDownload
   end if
   if sAdDownloadHandle is not empty then
      uiStatus "a download is already running (" & sAdDownloadPath & ")", "warn"
      exit adDoDownload
   end if
   put adDownloadFolder(sAdItem["identifier"]) into tFolder
   if tFolder is empty then
      uiStatus "no writable folder for downloads (Documents and temporary both refused)", "bad"
      exit adDoDownload
   end if
   put adSafeFileName(tEntry["name"]) into tName
   put tFolder & "/" & tName into tPath
   put pPlayAfter is true into sAdPlayAfter
   if there is a file tPath then
      if adFileSize(tFolder, tName) is tEntry["size"] then
         adLog "already downloaded: " & tPath
         adDownloadFinished tPath
         exit adDoDownload
      end if
   end if
   -- the DATANODE URL, as Play uses: no /download/ redirect between the
   -- request and the file, so the URL the library reports progress under
   -- is the URL the layer registered
   put tEntry["direct"] into tUrl
   if tUrl is empty then
      put tEntry["url"] into tUrl
   end if
   put axDownload(tUrl, tPath, "download") into tHandle
   if tHandle is empty then
      adLog "download refused: " & axLastError()
      uiStatus "download refused - see the log", "bad"
      put empty into sAdPlayAfter
      exit adDoDownload
   end if
   put tHandle into sAdDownloadHandle
   put tPath into sAdDownloadPath
   adLog "download " & tHandle & ": " & tUrl & " -> " & tPath & " (" & axFormatBytes(tEntry["size"]) & ")"
   uiStatus "downloading " & tName & " (" & axFormatBytes(tEntry["size"]) & ")...", "warn"
end adDoDownload

command adShowProgress pReceivedTotal
   local tReceived, tTotal, tPercent
   set the defaultStack to the short name of this stack
   put item 1 of pReceivedTotal into tReceived
   put item 2 of pReceivedTotal into tTotal
   if tReceived is not a number then
      exit adShowProgress
   end if
   if tTotal is a number and tTotal > 0 then
      put trunc(tReceived * 100 / tTotal) into tPercent
      uiStatus "downloading: " & axFormatBytes(tReceived) & " of " & axFormatBytes(tTotal) & " (" & tPercent & "%)", "warn"
   else
      uiStatus "downloading: " & axFormatBytes(tReceived) & " so far", "warn"
   end if
end adShowProgress

command adDownloadFinished pPath
   set the defaultStack to the short name of this stack
   put empty into sAdDownloadPath
   adLog "downloaded: " & pPath & " (" & axFormatBytes(adFileSize(adFolderOf(pPath), adSafeFileName(pPath))) & " on disk)"
   if sAdPlayAfter is true then
      put empty into sAdPlayAfter
      adPlayLocal pPath
   else
      uiStatus "saved " & pPath, "ok"
   end if
end adDownloadFinished

command adPlayLocal pPath
   -- Play a file from disk in the same player: the path the engine's
   -- media stack can always open, whatever it thinks of https streams.
   local tName, tError, tWhy
   set the defaultStack to the short name of this stack
   put kAdPlayerName into tName
   try
      if there is no player tName then
         create player
         set the name of the last player to tName
      end if
      set the rect of player tName to the rect of field "adTracks"
      set the showController of player tName to true
      set the visible of field "adTracks" to false
      set the visible of player tName to true
      set the filename of player tName to pPath
      put the result into tWhy
      adLog "play (local): " & pPath
      if tWhy is not empty then
         adLog "the player refused the local file at once: " & tWhy & " - opening it with the system player"
         set the visible of player tName to false
         set the visible of field "adTracks" to true
         launch document pPath
         uiStatus "no in-window playback for this format on this engine; the file opened in the system player", "warn"
         exit adPlayLocal
      end if
      start player tName
      put pPath into sAdPlayUrl
      uiStatus "playing the downloaded file; Stop puts the list back", "ok"
      adArmPlayCheck
   catch tError
      adLog "player failed on the local file: " & tError & " - opening it with the system player"
      set the visible of field "adTracks" to true
      try
         launch document pPath
         uiStatus "no in-window playback on this engine; the file opened in the system player", "warn"
      catch tError
         uiStatus "could not play or open the file: " & tError, "bad"
      end try
   end try
end adPlayLocal

function adDownloadFolder pIdentifier
   -- Documents/ArchiveXT/<identifier>, created on demand; the temporary
   -- folder when Documents refuses (the torrent demos' fallback order).
   local tBase, tFolder, tError
   put specialFolderPath("documents") into tBase
   if tBase is empty then
      put specialFolderPath("temporary") into tBase
   end if
   if tBase is empty then
      return empty
   end if
   put tBase & "/ArchiveXT/" & pIdentifier into tFolder
   if there is not a folder (tBase & "/ArchiveXT") then
      create folder (tBase & "/ArchiveXT")
   end if
   if there is not a folder tFolder then
      create folder tFolder
   end if
   if there is a folder tFolder then
      return tFolder
   end if
   put specialFolderPath("temporary") & "/ArchiveXT/" & pIdentifier into tFolder
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
end adDownloadFolder

function adFileSize pFolder, pName
   -- The size of one file from `the detailed files` of its folder, WITHOUT
   -- reading it: a 700 MB film is not a thing to pull into memory to ask
   -- how big it is. Empty when the file is not there.
   local tSaved, tLines, tLine, tSize
   put empty into tSize
   put the defaultFolder into tSaved
   set the defaultFolder to pFolder
   put the detailed files into tLines
   set the defaultFolder to tSaved
   repeat for each line tLine in tLines
      if urlDecode(item 1 of tLine) is pName then
         put item 2 of tLine into tSize
         exit repeat
      end if
   end repeat
   return tSize
end adFileSize

function adFolderOf pPath
   local tName
   put adSafeFileName(pPath) into tName
   return char 1 to (the length of pPath - the length of tName - 1) of pPath
end adFolderOf

function adSafeFileName pName
   -- The last path segment of an archive.org file name, with the
   -- characters no platform's file system takes replaced.
   local tName, tBad, tI, tChar
   put pName into tName
   if "/" is in tName then
      put char (the length of tName - offset("/", adReverse(tName)) + 2) to -1 of tName into tName
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
end adSafeFileName

function adReverse pText
   local tOut, tI
   put empty into tOut
   repeat with tI = the length of pText down to 1
      put char tI of pText after tOut
   end repeat
   return tOut
end adReverse

command adDoStopPlay
   local tName, tError
   set the defaultStack to the short name of this stack
   put kAdPlayerName into tName
   put empty into sAdPlayUrl
   try
      if there is a player tName then
         stop player tName
         set the visible of player tName to false
      end if
   catch tError
   end try
   if there is a field "adTracks" then
      set the visible of field "adTracks" to true
   end if
end adDoStopPlay

-- ==========================================================================
-- The fetch-layer callback: the whole contract in one handler. Reached
-- from the engine's URL callback or the layer's watchdog, so the
-- defaultStack is pinned FIRST (engine notes 5.3).
-- ==========================================================================

on onArchive pHandle, pKind, pArgOne, pTag
   set the defaultStack to the short name of this stack
   if pKind is "search" then
      if pHandle is sAdSearchHandle then
         put empty into sAdSearchHandle
      end if
      adShowResults pArgOne
   else if pKind is "item" then
      if pHandle is sAdItemHandle then
         put empty into sAdItemHandle
      end if
      adShowItem pArgOne
   else if pKind is "raw" then
      adLog "raw reply for request " & pHandle & " (" & pTag & "): " & the number of bytes of pArgOne & " bytes"
   else if pKind is "progress" then
      adShowProgress pArgOne
   else if pKind is "file" then
      if pHandle is sAdDownloadHandle then
         put empty into sAdDownloadHandle
      end if
      adDownloadFinished pArgOne
   else if pKind is "error" then
      if pHandle is sAdSearchHandle then
         put empty into sAdSearchHandle
      end if
      if pHandle is sAdItemHandle then
         put empty into sAdItemHandle
      end if
      if pHandle is sAdDownloadHandle then
         put empty into sAdDownloadHandle
         put empty into sAdPlayAfter
      end if
      adLog "request " & pHandle & " (" & pTag & ") failed: " & pArgOne
      uiStatus "request failed - see the log", "bad"
   else
      adLog "unknown callback kind " & pKind & " for request " & pHandle
   end if
end onArchive

-- ==========================================================================
-- The member self-test, into the log.
-- ==========================================================================

command adDoSelfTest
   local tReport
   set the defaultStack to the short name of this stack
   uiStatus "running axSelfTest...", "warn"
   put axSelfTest() into tReport
   adLog "== axSelfTest =="
   adLog tReport
   uiStatus "self-test: " & line 1 of tReport, "ok"
end adDoSelfTest

command adDoProbe
   -- Ten BLOCKING requests, each logged with the site's answer and the
   -- response headers, so a live failure can be read from the log rather
   -- than reconstructed from the message box (the 2026-09-15 400 needed
   -- exactly this). Legs 1-5 ran green on 2026-09-16 (a LibriVox search; a
   -- real item PARSED and its 58-chapter playlist; the movies family's
   -- cheap scope; a broken query refused inside an HTTP 200; a missing
   -- item's {}). Legs 6-10 were added the same day for the questions the
   -- docs still carry open: three deliberately BAD certificates (the TLS
   -- question root engine notes 6.8 / 6.9 have carried since the suite's
   -- first secure socket - a refusal is the good answer), the scrape API's
   -- body shape, and the blocking download through the /download/
   -- redirect.
   local tUrl, tResult, tOptions, tQuery, tInfo, tId, tItem, tKind
   local tPlaylist, tTable, tBody, tDoc, tPath
   set the defaultStack to the short name of this stack
   uiStatus "live probe running (ten blocking requests)...", "warn"
   adLog "== live probe =="
   put "identifier,title" into tOptions["fields"]
   put 3 into tOptions["rows"]
   put "collection:(librivoxaudio) AND (austen)" into tQuery
   adLog "1. axSearchSync " & tQuery
   put axSearchSync(tQuery, tOptions) into tResult
   put empty into tId
   if tResult is an array then
      put axFirst(tResult["docs"][1]["identifier"]) into tId
      adLog "   ok: numFound " & tResult["numFound"] & ", first " & tId
      adProbeHeaders true
   else
      adLog "   FAILED: " & axLastError()
      adProbeHeaders false
   end if
   if tId is empty then
      put "emma_1903_librivox" into tId
   end if
   adLog "2. axFetchItemSync " & tId & " (parsed, then a playlist)"
   put axFetchItemSync(tId) into tItem
   if tItem is an array then
      adLog "   ok: " & tItem["filesCount"] & " files, mediatype " & axFirst(tItem["metadata"]["mediatype"]) & ", server " & tItem["server"] & ", title " & axFirst(tItem["metadata"]["title"])
      adProbeHeaders true
      put axPlaylistKindFor("librivox", axFirst(tItem["metadata"]["mediatype"])) into tKind
      put axPlaylist(tItem, tKind) into tPlaylist
      if tPlaylist is an array then
         put axPlaylistTable(tPlaylist) into tTable
         adLog "   playlist (" & tKind & "): " & tPlaylist["count"] & " entries; first: " & line 1 of tTable
         adLog "   first url: " & tPlaylist["entries"][1]["url"]
      else
         adLog "   playlist FAILED: " & axLastError()
      end if
   else
      adLog "   FAILED: " & axLastError()
      adProbeHeaders false
   end if
   put axFamilyInfo("movies") into tInfo
   put tInfo["fields"] into tOptions["fields"]
   put tInfo["sort"] into tOptions["sort"]
   put tInfo["rows"] into tOptions["rows"]
   adLog "3. axSearchSync " & tInfo["scope"] & " (the movies family default)"
   put axSearchSync(tInfo["scope"], tOptions) into tResult
   if tResult is an array then
      adLog "   ok: numFound " & tResult["numFound"] & ", first " & axFirst(tResult["docs"][1]["identifier"])
      adProbeHeaders true
   else
      adLog "   FAILED: " & axLastError()
      adProbeHeaders false
   end if
   put "identifier,title" into tOptions["fields"]
   put empty into tOptions["sort"]
   put 3 into tOptions["rows"]
   put "collection:(librivoxaudio) AND" into tQuery
   adLog "4. axSearchSync " & tQuery & " (a broken query, sent unsanitized: the site should refuse it inside an HTTP 200)"
   put axSearchSync(tQuery, tOptions) into tResult
   if tResult is an array then
      adLog "   UNEXPECTED: the site accepted it - numFound " & tResult["numFound"]
   else
      adLog "   refused as expected: " & axLastError()
   end if
   adProbeHeaders true
   put "no_such_item_archivext_probe" into tId
   adLog "5. axFetchItemSync " & tId & " (a missing item: HTTP 200 with the body {})"
   put axFetchItemSync(tId) into tItem
   if tItem is an array then
      adLog "   UNEXPECTED: an item came back - " & tItem["identifier"]
   else
      adLog "   refused as expected: " & axLastError()
   end if
   adProbeHeaders true
   -- 6-8. TLS, the failing direction: three hosts that exist to be
   -- refused (badssl.com). A REFUSAL is the good answer - it means the
   -- Internet library verifies certificates; a body back means it does
   -- not, and root engine notes 6.8 / 6.9 have been waiting for exactly
   -- this measurement since the suite's first secure socket.
   adProbeBadCert 6, "https://self-signed.badssl.com/", "a self-signed certificate"
   adProbeBadCert 7, "https://expired.badssl.com/", "an expired certificate"
   adProbeBadCert 8, "https://wrong.host.badssl.com/", "a certificate for another host name"
   -- 9. the scrape API, which no source app used and no fixture models
   put axScrapeUrl("collection:(librivoxaudio)", "identifier,title", 5, empty) into tUrl
   adLog "9. GET " & tUrl & " (the scrape API: expecting items, count, cursor)"
   put axGetSync(tUrl) into tBody
   if tBody is empty then
      adLog "   FAILED: " & axLastError()
      adProbeHeaders false
   else
      put axJsonParse(tBody) into tDoc
      if tDoc is empty then
         adLog "   not JSON: " & axLastError() & " - body starts " & char 1 to 80 of tBody
      else
         adLog "   ok: " & the number of bytes of tBody & " bytes; count " & axJsonGet(tDoc, "count") & ", items is " & axJsonType(tDoc, "items") & " of " & axJsonCount(tDoc, "items") & ", cursor " & scShow(axJsonGet(tDoc, "cursor")) & ", total " & scShow(axJsonGet(tDoc, "total")) & "; first identifier " & scShow(axJsonGet(tDoc, "items/1/identifier"))
         adLog "   keys: " & replaceText(axJsonKeys(tDoc, empty), return, ", ")
         axJsonFree tDoc
      end if
      put axScrapeParse(tBody) into tResult
      if tResult is an array then
         adLog "   axScrapeParse: count " & tResult["count"] & ", total " & scShow(tResult["total"]) & ", cursor " & scShow(tResult["cursor"]) & ", first " & scShow(axFirst(tResult["items"][1]["identifier"]))
      else
         adLog "   axScrapeParse refused: " & axLastError()
      end if
      adProbeHeaders true
   end if
   -- 10. the blocking download through the /download/ redirect: the
   -- item's own _meta.xml (a few KB) into the temporary folder
   put "emma_version_5_1002_librivox" into tId
   put axDownloadUrl(tId, tId & "_meta.xml") into tUrl
   put specialFolderPath("temporary") & "/archivext-probe-meta.xml" into tPath
   adLog "10. axDownloadSync " & tUrl & " -> " & tPath & " (the blocking download, through the /download/ redirect)"
   if axDownloadSync(tUrl, tPath) is empty then
      adLog "   FAILED: " & axLastError()
      adProbeHeaders false
   else
      adLog "   ok: " & axFormatBytes(adFileSize(specialFolderPath("temporary"), "archivext-probe-meta.xml")) & " on disk; starts " & char 1 to 60 of URL ("binfile:" & tPath)
      adProbeHeaders true
   end if
   uiStatus "live probe done (ten legs) - copy the log", "ok"
end adDoProbe

command adProbeBadCert pLeg, pUrl, pWhat
   -- One deliberately bad certificate: log which way libURL went.
   local tBody, tWhy
   set the defaultStack to the short name of this stack
   adLog pLeg & ". GET " & pUrl & " (" & pWhat & ": a refusal means libURL VERIFIES; a body means it does NOT)"
   put axGetSync(pUrl) into tBody
   if tBody is empty then
      put axLastError() into tWhy
      adLog "   REFUSED: " & tWhy
      adLog "   verdict: libURL refused " & pWhat & " - certificate verification is ON for this case"
      adProbeHeaders false
   else
      adLog "   ANSWERED: " & the number of bytes of tBody & " bytes, starts " & char 1 to 60 of tBody
      adLog "   verdict: libURL accepted " & pWhat & " - certificate verification is OFF for this case; treat every https request from this engine as unverified"
      adProbeHeaders true
   end if
end adProbeBadCert

command adProbeHeaders pAnswered
   -- The response headers of the LAST reply the Internet library received.
   -- After a request that never got an answer (a timeout, a refused second
   -- load) they are the PREVIOUS reply's, which the 2026-09-15 log showed
   -- as a step-3 failure wearing step-2's Onion-Location; the label says so.
   local tHeaders, tError
   set the defaultStack to the short name of this stack
   put empty into tHeaders
   try
      put libURLLastRHHeaders() into tHeaders
   catch tError
      put "(libURLLastRHHeaders threw: " & tError & ")" into tHeaders
   end try
   replace return with " | " in tHeaders
   if pAnswered then
      adLog "   headers: " & tHeaders
   else
      adLog "   headers (the last reply RECEIVED - after a failure these may be an earlier request's): " & tHeaders
   end if
end adProbeHeaders

command adLog pText
   set the defaultStack to the short name of this stack
   put pText & return after field "adLog"
   set the vScroll of field "adLog" to the formattedHeight of field "adLog"
end adLog

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
-- The boot self-check: what this demo asserts about itself on open. Every
-- control this script names (the list is DERIVED by
-- tools/check-demo-control-lists.py), the state adStart establishes, one
-- pinned vector through the embedded library, and the fetch layer idle.
-- Nothing here hosts, connects, binds or fetches.
-- ==========================================================================

constant kAdScControls = "adCopyUrl,adDownload,adExplorePanel,adFamAny,adFamEtree,adFamLibrivox,adFamMovies,adFamilyCap,adFilter1,adFilter2,adFilter3,adFilter4,adFilterCap,adItemCap,adItemMeta,adItemNote,adItemPanel,adItemTitle,adLog,adLogCap,adNext,adOpenPage,adPageInfo,adPlay,adPresetCap,adPresets,adPrev,adProbe,adQuery,adQueryNote,adRandom,adResults,adResultsHead,adSearch,adSearchCap,adSearchPanel,adSort,adSortNote,adStopPlay,adTests,adTracks,adTracksHead,adYearCap,adYearFrom,adYearTo,uiFooter,uiStatus,uiTitle"

command adScRun
   local tMissing, tCaps, tPlaylist
   scBegin "adLog"
   put scMissing(kAdScControls) into tMissing
   scAssert "all 48 controls this script names exist (missing: " & scShow(tMissing) & ")", tMissing is empty
   scAssert "axVersion reports the member", axVersion() begins with "ArchiveXT"
   scAssert "the movies family is in play at boot", sAdFamily is "movies"
   scAssert "a preset is selected at boot (" & scShow(sAdPreset) & ")", sAdPreset is not empty
   scAssert "the preset table has one id line per row", the number of lines of sAdPresetIds is the number of lines of field "adPresets"
   scAssert "the film club's public-domain filter is wired", sAdFilterIds is "publicdomain"
   scAssert "the search URL derives the AudioBooks vector", axSearchUrl("collection:(librivoxaudio) AND (a " & quote & "b" & quote & ")", "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2) is kAxVecUrlSearch
   put axPlaylist(axItemParse(axtHex(kAxVecFixEtreeItemHex)), "audio-tracks") into tPlaylist
   scAssert "the etree fixture plays as six tracks", tPlaylist["count"] is 6
   scAssert "every playlist entry carries a stream URL and a datanode URL", tPlaylist["entries"][1]["url"] is not empty and tPlaylist["entries"][1]["direct"] is not empty
   scAssert "nothing is in flight at boot", axPending() is 0
   put axProbeCapabilities() into tCaps
   if tCaps["hasUrlLib"] is true then
      scAssert "the Internet library answers (" & scShow(tCaps["urlLibVersion"]) & ")", true
   else
      scSkip "the Internet library answers", "libURLVersion did not answer on this engine"
   end if
   scArmProbe
end adScRun
