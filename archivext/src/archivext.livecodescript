script "archivext"
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
--   6. No CHARACTER is ever handed to byteToNum. A char is a grapheme on
--      this engine line and byteToNum throws on one that is more than a
--      single code unit (an emoji, a flag, a decomposed accent - engine
--      source 9.6.3, MCStringsEvalByteToNum), which archive.org titles and
--      a search box both carry; every char-walking rule below classifies
--      through axCharCode, which answers a value no ASCII test matches for
--      anything wider than one byte. byteToNum stays for BYTES only (the
--      encoders and the JSON reader walk textEncode'd data, where it is
--      exact).
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
local sAxSocketTimeoutWas   -- the engine's socketTimeoutInterval before this layer raised it

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

private function axCharCode pChar
   -- The value this file classifies ONE CHARACTER by: its byte value when
   -- the character is a single byte, and 256 - a value no ASCII test in
   -- this file can match - for anything wider. Every char-walking rule
   -- goes through here rather than through byteToNum, because byteToNum
   -- THROWS on a character that is more than one code unit ("argument is
   -- not a single byte": engine source 9.6.3, MCStringsEvalByteToNum,
   -- which tests the code-unit length, not the byte count) and a char is
   -- a grapheme on this engine line - an emoji, a flag, a skin tone, a
   -- decomposed accent, anything outside the Basic Multilingual Plane is
   -- one char and two or more code units. archive.org titles, subjects
   -- and file names carry those, and so does whatever a reader types into
   -- a search box, so a library that promises never to throw cannot hand
   -- a char to byteToNum: the first draft did, in twenty-three helpers,
   -- and every one of them would have thrown out of a callback the fetch
   -- layer swallows - a search whose results silently never arrive.
   -- The family interpreter models byteToNum as a plain code point and
   -- never throws, which is why the vector gate could not see it; the
   -- gate's tier 0 now states that model, and its wide-character vectors
   -- drive this path on every build. A one-byte character answers exactly
   -- what byteToNum answered, so nothing else in this file moved.
   local tBytes
   put textEncode(pChar, "UTF-8") into tBytes
   if the number of bytes of tBytes is 1 then
      return byteToNum(byte 1 of tBytes)
   end if
   return 256
end axCharCode

private function axIsDigits pText
   -- True for one or more ASCII digits and nothing else. The strict test
   -- this file uses instead of `is an integer`, which folds "1e3" and " 7 ".
   local tI, tCount
   put the number of chars of pText into tCount
   if tCount is 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      if not axIsDigitByte(axCharCode(char tI of pText)) then
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
   put axCharCode(char 1 of pText) into tByte
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
         put axCharCode(char 1 of tText) into tByte
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
         put axCharCode(char -1 of tText) into tByte
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
      put axCharCode(char tI of pText) into tByte
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
   put axCharCode(pChar) into tByte
   put the number of chars of pSet into tCount
   repeat with tI = 1 to tCount
      if axCharCode(char tI of pSet) is tByte then
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
      put axCharCode(tChar) into tByte
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
      put axCharCode(char tI of pText) into tByte
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
      put axCharCode(char tI of pText) into tByte
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
      put axCharCode(char tI of tLower) into tByte
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
      put axCharCode(char tI of pText) into tByte
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
   put axCharCode(pChar) into tByte
   put the number of chars of pText into tCount
   put 0 into tN
   repeat with tI = 1 to tCount
      if axCharCode(char tI of pText) is tByte then
         add 1 to tN
      end if
   end repeat
   return tN
end axCountChar

private function axIsBalanced pText, pOpen, pClose
   -- Every pClose has a pOpen before it and the depth ends at zero.
   local tI, tCount, tDepth, tByte, tOpenByte, tCloseByte
   put axCharCode(pOpen) into tOpenByte
   put axCharCode(pClose) into tCloseByte
   put the number of chars of pText into tCount
   put 0 into tDepth
   repeat with tI = 1 to tCount
      put axCharCode(char tI of pText) into tByte
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
      put axCharCode(char tI of pText) into tByte
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
         put axCharCode(tChar) into tByte
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
   return axCharCode(char -1 of pTok) is 40
end axIsOpenToken

private function axIsCloseToken pTok
   if pTok is empty then
      return false
   end if
   return axCharCode(char 1 of pTok) is 41
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
      if axCharCode(char tPos of pText) is 45 then
         add 1 to tPos
      end if
   end if
   if tPos > tCount then
      return false
   end if
   put axCharCode(char tPos of pText) into tByte
   if tByte is 48 then
      add 1 to tPos
   else
      if not axIsDigitByte(tByte) then
         return false
      end if
      repeat while tPos <= tCount
         if axIsDigitByte(axCharCode(char tPos of pText)) then
            add 1 to tPos
         else
            exit repeat
         end if
      end repeat
   end if
   if tPos <= tCount then
      if axCharCode(char tPos of pText) is 46 then
         add 1 to tPos
         put 0 into tDigits
         repeat while tPos <= tCount
            if axIsDigitByte(axCharCode(char tPos of pText)) then
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
      put axCharCode(char tPos of pText) into tByte
      if tByte is 101 then
         add 1 to tPos
      else if tByte is 69 then
         add 1 to tPos
      else
         return false
      end if
      if tPos <= tCount then
         put axCharCode(char tPos of pText) into tByte
         if tByte is 43 then
            add 1 to tPos
         else if tByte is 45 then
            add 1 to tPos
         end if
      end if
      put 0 into tDigits
      repeat while tPos <= tCount
         if axIsDigitByte(axCharCode(char tPos of pText)) then
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
      put axCharCode(char tI of tLower) into tByte
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
   -- The film club's normalizeBaseName spelling of "extension off",
   -- /\.[^.]+$/: everything from the last dot on, provided at least one
   -- character follows it. Three edges the first draft got wrong, each
   -- found on 2026-09-21 by the vector that first tried it: a name that
   -- IS only an extension (".ogv") strips to nothing; a trailing dot
   -- ("x.") is not an extension and stays; and a "/" inside the tail does
   -- NOT protect it ("dir.d/x" becomes "dir"), which is a quirk of the
   -- app and is kept because the oracle keeps it. The episode TITLE is
   -- that app's other regex and takes axStripTitleExtension.
   local tI, tCount, tByte
   put the number of chars of pName into tCount
   repeat with tI = tCount down to 1
      put axCharCode(char tI of pName) into tByte
      if tByte is 46 then
         if tI is tCount then
            return pName
         end if
         if tI is 1 then
            return empty
         end if
         return char 1 to (tI - 1) of pName
      end if
   end repeat
   return pName
end axStripExtension

private function axStripTitleExtension pName
   -- The film club's getCleanTitle spelling, /\.[^/.]+$/: as above, but
   -- a "/" inside the tail means there is no extension to strip.
   local tI, tCount, tByte
   put the number of chars of pName into tCount
   repeat with tI = tCount down to 1
      put axCharCode(char tI of pName) into tByte
      if tByte is 46 then
         if tI is tCount then
            return pName
         end if
         if tI is 1 then
            return empty
         end if
         return char 1 to (tI - 1) of pName
      end if
      if tByte is 47 then
         return pName
      end if
   end repeat
   return pName
end axStripTitleExtension

private function axStripAlnumExtension pName
   -- The AudioBooks spelling of "extension off" (/\.[a-z0-9]+$/i): only
   -- when everything after the last dot is ASCII letters and digits.
   -- "a.mp3" loses its tail; "a.b c", "x.mp3~" and a name ending in a
   -- character no ASCII test matches keep theirs. The chapter stem and
   -- the pretty name are that app's rules and take this one; the video
   -- stem and the episode title are the film club's and take the looser
   -- axStripExtension. The two agreed on every fixture and disagreed on
   -- the first non-alphanumeric tail a vector tried (2026-09-21).
   local tI, tCount, tByte, tTail
   put the number of chars of pName into tCount
   put 0 into tTail
   repeat with tI = tCount down to 1
      put axCharCode(char tI of pName) into tByte
      if tByte is 46 then
         if tTail is 0 then
            return pName
         end if
         if tI is 1 then
            return empty
         end if
         return char 1 to (tI - 1) of pName
      end if
      if axIsAlphaByte(tByte) then
         add 1 to tTail
         next repeat
      end if
      if axIsDigitByte(tByte) then
         add 1 to tTail
         next repeat
      end if
      return pName
   end repeat
   return pName
end axStripAlnumExtension

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
   put axStripAlnumExtension(axLowerAscii(pName)) into tStem
   put the number of chars of tStem into tCount
   if axEndsWithAny(tStem, "_vbr,_orig,_original") then
      repeat with tI = tCount down to 1
         if axCharCode(char tI of tStem) is 95 then
            return char 1 to (tI - 1) of tStem
         end if
      end repeat
   end if
   if axEndsWithAny(tStem, "kb") then
      -- _<1-3 digits>kb
      put 0 into tLen
      repeat with tI = (tCount - 2) down to 1
         put axCharCode(char tI of tStem) into tByte
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
         if axCharCode(char tCount of tStem) is 112 then
            put 0 into tRun
            repeat with tI = (tCount - 1) down to 1
               put axCharCode(char tI of tStem) into tByte
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
                     put axCharCode(char tI of tStem) into tSep
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
      if axCharCode(char tI of tStem) is 47 then
         put char (tI + 1) to tCount of tStem into tStem
         exit repeat
      end if
   end repeat
   put axStripAlnumExtension(tStem) into tStem
   put axLowerAscii(tStem) into tOut
   put the number of chars of tStem into tCount
   if axEndsWithAny(tOut, "_vbr") then
      put char 1 to (tCount - 4) of tStem into tStem
   else if axEndsWithAny(tOut, "kb") then
      put 0 into tLen
      repeat with tI = (tCount - 2) down to 1
         put axCharCode(char tI of tStem) into tByte
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
      put axCharCode(char 1 of axLowerAscii(char 1 of tText)) into tByte
      if tByte is 100 then
         put 0 into tDigits
         put 2 into tI
         repeat while tI <= tCount
            if axIsDigitByte(axCharCode(char tI of tText)) then
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
      put axCharCode(char 1 of axLowerAscii(char tPos of tText)) into tByte
      if tByte is 116 then
         put 0 into tDigits
         put tPos + 1 into tI
         repeat while tI <= tCount
            if axIsDigitByte(axCharCode(char tI of tText)) then
               add 1 to tDigits
               add 1 to tI
            else
               exit repeat
            end if
         end repeat
         if tDigits > 0 then
            repeat while tI <= tCount
               put axCharCode(char tI of tText) into tByte
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
   put axStripTitleExtension(pName) into tTitle
   put empty into tId
   put axLowerAscii(pItemTitle) into tLower
   put the number of chars of tLower into tCount
   repeat with tI = 1 to tCount
      put axCharCode(char tI of tLower) into tByte
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
   put axCharCode(pChar) into tSplit
   put the number of chars of pText into tCount
   put empty into tOut
   put empty into tPiece
   repeat with tI = 1 to tCount
      put axCharCode(char tI of pText) into tByte
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
   -- forgotten (default 60; the live site took over 30 s on a broad
   -- search). A non-number or a value under 1 keeps the current setting.
   -- The engine's own socket timeout is raised to match on the next
   -- request (axRaiseSocketTimeout), because the Internet library gives
   -- up first otherwise.
   if pSeconds is not a number then
      exit axSetTimeout
   end if
   if pSeconds < 1 then
      exit axSetTimeout
   end if
   put trunc(pSeconds) into sAxTimeout
end axSetTimeout

private command axRaiseSocketTimeout
   -- THE INTERNET LIBRARY'S OWN CLOCK IS THE ENGINE'S socketTimeoutInterval,
   -- ten seconds by default, and it runs out long before this layer's
   -- watchdog: libURL reads its reply with `read from socket`, the engine
   -- sends socketTimeout when nothing has arrived inside the interval,
   -- and libURL answers that by giving the request up as status "timeout"
   -- with "socket timeout <socket>" as the reason. OBSERVED 2026-09-21,
   -- twice in a row on a text search sorted by downloads over every video
   -- on the site (the query archive.org takes longest over), and the same
   -- shape on 2026-09-20 (root engine notes 5.10): every "timeout" this
   -- layer has ever reported was libURL's ten seconds, never its own
   -- sixty. The dictionary says the interval is read every time a read
   -- or write is issued, so it has to be raised BEFORE the load and left
   -- raised while replies are pending - which is what onionxt and nostrxt
   -- do before their own connects. It is raised, never lowered, to this
   -- layer's timeout, and axShutdown puts back what it found. Global to
   -- the process, like the status callback: a stack that co-loads a
   -- socket library gets a longer idle tick on its sockets while this
   -- layer is in use, and no library in this suite decides anything from
   -- that tick's timing.
   local tNow, tWant, tError
   put sAxTimeout * 1000 into tWant
   try
      put the socketTimeoutInterval into tNow
      if tNow is not a number then
         exit axRaiseSocketTimeout
      end if
      if tNow >= tWant then
         exit axRaiseSocketTimeout
      end if
      if sAxSocketTimeoutWas is empty then
         put tNow into sAxSocketTimeoutWas
      end if
      set the socketTimeoutInterval to tWant
   catch tError
      -- an engine without the property: libURL keeps its own clock
   end try
end axRaiseSocketTimeout

function axSettings
   -- EVERY PROCESS-WIDE SETTING OF THE FETCH LAYER, IN ONE ARRAY, so a
   -- caller that is about to change them can put them back. That is not a
   -- convenience: axInit, axSetCallback, axSetTimeout and axSetMaxBody
   -- write script locals of THIS library, and a library is one object per
   -- process - so a harness or a second panel exercising those setters
   -- silently re-points the host app's callbacks and re-caps its replies.
   -- It happened on a real engine (2026-09-20): this member's own harness
   -- set the cap to 64 KB to prove the setter works, never put it back,
   -- and from then on every item metadata reply, every full picture and
   -- every 192-row search in the app around it was refused as "larger
   -- than 65536 bytes". The app was correct, the library was correct, and
   -- the state between them was a test fixture.
   --   owner      the long id callbacks dispatch to (empty: the topStack)
   --   callback   the handler name dispatched
   --   timeout    seconds before a request is reported timed out
   --   maxBody    the largest reply this layer will parse
   --   baseUrl    the site the builders address
   -- axRestoreSettings takes this array back.
   local tOut
   put sAxOwner into tOut["owner"]
   if sAxCallback is empty then
      put kAxCallbackDefault into tOut["callback"]
   else
      put sAxCallback into tOut["callback"]
   end if
   if sAxTimeout is empty then
      put kAxTimeoutDefault into tOut["timeout"]
   else
      put sAxTimeout into tOut["timeout"]
   end if
   if sAxMaxBody is empty then
      put kAxMaxBodyDefault into tOut["maxBody"]
   else
      put sAxMaxBody into tOut["maxBody"]
   end if
   put axBaseUrl() into tOut["baseUrl"]
   return tOut
end axSettings

command axRestoreSettings pSettings
   -- Put back what axSettings handed out. Restoring writes each setting
   -- DIRECTLY rather than through the setters, because the setters refuse
   -- values outside their own ranges and a restore is not a request - it
   -- is an undo, and an undo that silently declines is the bug it exists
   -- to prevent. A key the array does not carry is left alone, so a
   -- caller may restore one setting.
   if pSettings is not an array then
      exit axRestoreSettings
   end if
   if "owner" is among the keys of pSettings then
      put pSettings["owner"] into sAxOwner
   end if
   if "callback" is among the keys of pSettings then
      if pSettings["callback"] is empty then
         put kAxCallbackDefault into sAxCallback
      else
         put pSettings["callback"] into sAxCallback
      end if
   end if
   if "timeout" is among the keys of pSettings then
      if pSettings["timeout"] is a number then
         put trunc(pSettings["timeout"]) into sAxTimeout
      end if
   end if
   if "maxBody" is among the keys of pSettings then
      if pSettings["maxBody"] is a number then
         put trunc(pSettings["maxBody"]) into sAxMaxBody
      end if
   end if
   if "baseUrl" is among the keys of pSettings then
      -- WRITTEN DIRECTLY, like the four above, and for a second reason:
      -- axSetBaseUrl is a FUNCTION, and the first draft called it here as
      -- a command - `axSetBaseUrl pSettings["baseUrl"]` - which the engine
      -- answers with "Handler: can't find handler" naming the function
      -- (OBSERVED 2026-09-21: the harness died at its fetch-layer section
      -- on every run, and the boot self-check beside it stayed green
      -- because nothing at boot restores settings). The checker refuses
      -- that spelling now. axSettings() hands out axBaseUrl(), which is
      -- the default when nothing was set, so the default comes back as
      -- "nothing set" rather than as an explicit copy of itself.
      if axStrEq(pSettings["baseUrl"], kAxDefaultBase) then
         put empty into sAxBase
      else
         put pSettings["baseUrl"] into sAxBase
         if char -1 of sAxBase is "/" then
            put char 1 to -2 of sAxBase into sAxBase
         end if
      end if
   end if
end axRestoreSettings

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
   axRaiseSocketTimeout
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
   axRaiseSocketTimeout
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
   -- callback back and the engine's socket timeout back, and drop the
   -- owner. Safe to call twice.
   local tError
   axCancelAll
   axUnhookStatus
   if sAxSocketTimeoutWas is not empty then
      try
         set the socketTimeoutInterval to sAxSocketTimeoutWas
      catch tError
      end try
      put empty into sAxSocketTimeoutWas
   end if
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
      -- The site's response headers travel with the reason (2026-09-15: a
      -- bare "400 Bad Request" said nothing about WHICH server refused, or
      -- why). They are LABELLED as the last reply's rather than as this
      -- request's, because that is all libURLLastRHHeaders can promise
      -- (engine notes 6.9) and a failure report is exactly where a reader
      -- trusts a header block: on 2026-09-20 a timed-out search quoted a
      -- 200 and an Onion-Location naming a DIFFERENT URL, which had been
      -- fetched by a blocking call beside it (notes 5.10).
      put empty into tHeaders
      try
         put libURLLastRHHeaders() into tHeaders
      catch tError
         put empty into tHeaders
      end try
      if tHeaders is not empty then
         replace return with " | " in tHeaders
         put " [headers of the last reply this process received, which may be another request's: " & tHeaders & "]" after tDetail
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
