script "curlxtLive"

-- curlxt-live.livecodescript - curlxt Live: web requests and WebSockets from
-- xTalk, through libcurl, shown as five scenes that run themselves. Every
-- scene talks to a server THIS stack runs on the engine's own sockets, so it
-- all works with no network and nothing to set up.
--
-- HOW TO USE: install the curlxt extension (org.openxtalk.library.curl;
-- OXT-Beyond carries it built in; the WebSocket scenes need its ABI 2).
-- Paste THIS file into a stack script (File > New Mainstack, Object > Stack
-- Script, Apply), then close and reopen the stack: opening the file itself
-- builds no window (the suite's engine note 5.5). start-here's Open button
-- does all of that for you. curlxt's two script libraries, the helpers and
-- the tsNet calls, are EMBEDDED below, so there is nothing to put in use.
--
-- THE SCENES (each runs 5 to 15 seconds, then holds its last picture):
--   1  Round trips: a message every 120 ms over a WebSocket (cuWsOpen,
--      cuWsSendText), echoed back; each round trip drawn as it lands. The
--      stack opens into this one, and after its fast run it keeps one round
--      trip a second going, so the window never goes still.
--   2  Text and bytes: plain, accented, Greek and Japanese text, every byte
--      value, random bytes, and two big messages, each checked identical when
--      it comes back (cuWsSendText, cuWsSendData).
--   3  Full speed: for eight seconds, 64 messages of 1 KB always in flight
--      over one WebSocket (each echo that lands sends the next one), the rate
--      drawn every quarter second, and every echo checked to come back in
--      the order it was sent.
--   4  Many requests at once: sixteen requests started together with
--      cuRequestAsync (GET, POST, HEAD), one through the tsNet calls
--      (tsNetGet), and one out to the internet, which says plainly when
--      there is no network. The server makes each local request wait a
--      while, so the tiles show them overlapping.
--   5  Close and reconnect: a clean close (code 1000), a reconnect, the
--      server going away (1001), retries while it is gone, and the reconnect
--      once it is back on the same port.
--
-- NOTHING HERE WAITS. Every call is the background kind: a message arrives
-- when there is news, and the picture is redrawn on a timer with the screen
-- locked for each frame. (curlxt's waiting calls, cuRequestSync and
-- tsNetGetSync, would pause this stack, and the server they would be asking
-- is this stack.)
--
-- ONE POLLER PER PROCESS. The helpers' timer takes every finished request off
-- curlxt's one queue. This stack carries its own copy; another stack polling
-- its own copy at the same time can take this one's answers, and the other
-- way round.
--
-- THE SERVER ANSWERS THIS MACHINE ONLY. `accept connections on port` takes no
-- address, so the listener may be reachable from the network (and Windows may
-- ask about its firewall the first time): a connection whose peer is not this
-- machine is closed before a byte is read (the peer is parsed by shape, the
-- suite's engine note 6.2). It answers one HTTP request per connection with
-- at most 1 MiB of body, and echoes WebSocket messages of at most 65535 bytes.
-- Every write it makes is the engine's background kind (`write ... with
-- message`), so it never holds the stack either.
--
-- THE LOOK is OXT-Beyond's (the Render3D Tour's palette: a dark stage, orange
-- section heads), at the owner's request on 2026-11-21, so this stack does NOT
-- carry the suite UI kit: tools/check-ui-kit-drift.py lists it in EXEMPT with
-- that reason. It does carry the suite's boot self-check block, which writes
-- the status line through uiStatus; this stack's own uiStatus below does that
-- job in the dark palette.
--
-- HONESTY (the suite convention). On 2026-11-21 this file ran start to finish
-- on OXT-Beyond 0.2.7-rc.6's desktop engine on Linux x86-64 with no screen
-- (tests/engine-demo.livecodescript, through tools/run-engine-demo.py, which
-- curlxt's native lane runs on every change): the boot self-check green,
-- every scene to its own verdict, a close that left nothing open, and a
-- reopen. That run exercises the scripts, the engine's sockets, this stack's
-- server and libcurl together; it sees nothing drawn. The look, the IDE, and
-- Windows, mac and Android are verified statically; needs an OXT pass.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- curlxt/src/curl-helpers.livecodescript ----

-- curl-helpers.livecodescript - the pump and the everyday calls for curlxt.
--
-- curlxt's native layer starts no thread and never calls script (suite rule
-- 1): a background request moves only while cuPoll runs. This library runs
-- cuPoll on a timer WHILE something is waiting on it, and stops the timer
-- when nothing is, so an idle app has no timer at all. Each request started
-- through cuRequestAsync names an object and a message; when it ends, the
-- message is dispatched to that object with the request handle, and the
-- handler reads the outcome (cuResponse) and frees it (cuFree).
--
-- The tsNet library (tsnet.livecodescript) is built on this one.
--
-- WebSockets (2026-11-20) ride the same timer. A socket opened through
-- cuWsOpen names an object and a message too, and the timer dispatches that
-- message for each thing that happens to it: it opened, a text or a binary
-- message arrived, it closed. cuPoll never lists a socket (the native layer
-- keeps them off that list), so the timer asks each watched socket instead,
-- and it stays armed while one is watched. Nothing here changes what a
-- stack that opens no socket sees.
--
-- Script-locals carry the member stem (sCu...): two libraries sharing a
-- column-0 name cannot be co-embedded (suite engine note 1.6, enetxt
-- gotcha 5); the suite's check-cross-library-names.py holds them disjoint.
--
-- Ran on OXT-Beyond's headless Linux server engine 2026-11-21
-- (tests/engine-selftest.lc): cuRequestSync, cuRequestAsync and its
-- callback, cuResponse, and every WebSocket call here with the timer's
-- events (open, text, binary, closed), ws:// and wss://. The IDE, the other
-- platforms and the rest of this file need an OXT pass.

constant kCuDefaultInterval = 20
constant kCuIntOptions = "timeout,connectTimeout,followRedirects,maxRedirects,verifyPeer,verifyHost,lowSpeedLimit,lowSpeedTime,useSsl,ftpPassive,maxBodyBytes,httpVersion,dnsCacheSeconds,createDirs,wsCloseTimeout"
constant kCuListOptions = "mailRcpt,quote,postQuote"
-- The most messages one socket hands its handler in one timer pass: a busy
-- socket must not hold the pass (and the window) until it runs dry.
constant kCuWsBatch = 64

local sCuWaiters        -- array: request handle -> target & tab & message
local sCuPolling        -- "true" while the timer loop is armed
local sCuPollInterval   -- milliseconds between pump passes
local sCuPollNote       -- first pump failure since the last clear, else empty
local sCuHolds          -- cuInitialize holds this library took
local sCuMakeError      -- why the last cuRequestSync/Async returned 0
local sCuWsWatch        -- array: socket handle -> target & tab & message
local sCuWsOpened       -- array: socket handle -> "true" once "open" was sent

/**
Title: curlxt Helpers
Author: Seth Morrow Software
Description:
The everyday calls for curlxt. Put the curlHelpers stack in use (start
using stack "curlHelpers"), then make a request with <cuRequestSync>,
which waits for the answer, or <cuRequestAsync>, which sends your
message when the answer has arrived. A timer moves background requests
along; it runs only while one is waiting.

Read the answer with <cuResponse> and release the request with
<cuFree>.

Tags: Networking, Library
*/

/**
Summary: Take one curlxt hold for this library, if it has none.

Returns: Empty, or the error text when curlxt could not start.

Description:
<cuRequestSync> and <cuRequestAsync> call this for you. Give the hold
back with <cuHelpersRelease> when your stack closes.

References: cuHelpersRelease (handler), cuInitialize (handler)
*/
function cuHelpersInit
   local tR
   if sCuHolds is a number and sCuHolds > 0 then
      return empty
   end if
   put cuInitialize() into tR
   if tR < 1 then
      return "curlxt could not start: " & cuLastError()
   end if
   put 1 into sCuHolds
   return empty
end cuHelpersInit

/**
Summary: Give back the curlxt hold this library took.

Description:
Use it when your stack closes. If it was the last hold in the process,
every request still running stops.

References: cuHelpersInit (handler), cuCleanup (handler)
*/
command cuHelpersRelease
   local tR
   if sCuHolds is a number and sCuHolds > 0 then
      put cuCleanup() into tR
      put 0 into sCuHolds
   end if
   put empty into sCuWaiters
   put empty into sCuWsWatch
   put empty into sCuWsOpened
   put "false" into sCuPolling
end cuHelpersRelease

/**
Summary: Apply headers, a body and options to a request that has not started.

pRequest: A handle from <cuRequestNew>.
pHeaders: Header lines, one per line, or empty.
pBody: The bytes to send, or empty.
pOptions: An array of option name to value (see <cuSetOption> and
<cuSetTextOption>); mailRcpt, quote and postQuote take one value per line.

Returns: Empty, or the first error as text.

References: cuRequestAsync (handler), cuRequestSync (handler)
*/
function cuApplyRequest pRequest, pHeaders, pBody, pOptions
   local tLine, tName, tValue, tR
   repeat for each line tLine in pHeaders
      if tLine is not empty then
         put cuSetHeader(pRequest, tLine) into tR
         if tR < 0 then
            return "header refused (" & tR & "): " & tLine
         end if
      end if
   end repeat
   if pBody is not empty then
      put cuSetBody(pRequest, pBody) into tR
      if tR < 0 then
         return "body refused (" & tR & ")"
      end if
   end if
   if pOptions is an array then
      repeat for each key tName in pOptions
         put pOptions[tName] into tValue
         if tName is among the items of kCuIntOptions then
            if tValue is not an integer then
               return "option" && tName && "needs a whole number, not" && quote & tValue & quote
            end if
            put cuSetOption(pRequest, tName, tValue) into tR
         else if tName is among the items of kCuListOptions then
            repeat for each line tLine in tValue
               if tLine is not empty then
                  put cuSetTextOption(pRequest, tName, tLine) into tR
                  if tR < 0 then
                     exit repeat
                  end if
               end if
            end repeat
         else
            put cuSetTextOption(pRequest, tName, tValue) into tR
         end if
         if tR < 0 then
            return "option" && tName && "refused: " & cuLastError()
         end if
      end repeat
   end if
   return empty
end cuApplyRequest

-- Make and configure one request; 0 with the reason in sCuMakeError.
private function cuMakeRequest pMethod, pURL, pHeaders, pBody, pOptions
   local tReq, tErr
   put empty into sCuMakeError
   put cuHelpersInit() into tErr
   if tErr is not empty then
      put tErr into sCuMakeError
      return 0
   end if
   put cuRequestNew(pMethod, pURL) into tReq
   if tReq is 0 then
      put cuLastError() into sCuMakeError
      return 0
   end if
   put cuApplyRequest(tReq, pHeaders, pBody, pOptions) into tErr
   if tErr is not empty then
      get cuFree(tReq)
      put tErr into sCuMakeError
      return 0
   end if
   return tReq
end cuMakeRequest

/**
Summary: Why the last <cuRequestSync> or <cuRequestAsync> returned 0.

Returns: The reason as text, or empty after a request that was made.

References: cuRequestSync (handler), cuRequestAsync (handler)
*/
function cuHelpersError
   return sCuMakeError
end cuHelpersError

/**
Summary: Make a request and wait for its answer.

pMethod: GET, HEAD, POST, PUT, DELETE, or another method.
pURL: The URL.
pHeaders: Header lines, or empty.
pBody: The bytes to send, or empty.
pOptions: An array of options, or empty.
pTimeoutMs: The longest to wait; empty or -1 waits for the request's own
timeouts.

Returns: The handle of the ENDED request, or 0 with the reason in
<cuHelpersError>. Read it with <cuResponse>, then <cuFree> it.

Example:
put cuRequestSync("GET", "https://example.com/", empty, empty, empty, 10000) into tReq
if tReq is 0 then answer cuHelpersError()
put cuResponse(tReq) into tAnswer
get cuFree(tReq)

References: cuRequestAsync (handler), cuResponse (handler)
*/
function cuRequestSync pMethod, pURL, pHeaders, pBody, pOptions, pTimeoutMs
   local tReq, tR, tWait
   put cuMakeRequest(pMethod, pURL, pHeaders, pBody, pOptions) into tReq
   if tReq is 0 then
      return 0
   end if
   put cuStart(tReq) into tR
   if tR < 0 then
      put cuLastError() into sCuMakeError
      get cuFree(tReq)
      return 0
   end if
   if pTimeoutMs is an integer then
      put pTimeoutMs into tWait
   else
      put -1 into tWait
   end if
   put cuWait(tReq, tWait) into tR
   if tR is not 1 then
      get cuCancel(tReq)
   end if
   return tReq
end cuRequestSync

/**
Summary: Make a request in the background, and get a message when it ends.

pMethod: GET, HEAD, POST, PUT, DELETE, or another method.
pURL: The URL.
pHeaders: Header lines, or empty.
pBody: The bytes to send, or empty.
pOptions: An array of options, or empty.
pTarget: The object to send the message to; empty means this card.
pMessage: The message, sent with the request handle as its parameter.

Returns: The request handle, or 0 with the reason in <cuHelpersError>.

Example:
put cuRequestAsync("GET", tURL, empty, empty, empty, the long id of me, "pageArrived") into tReq

The handler pageArrived then gets the request handle as its parameter,
reads the outcome with <cuResponse> and releases it with <cuFree>.

Description:
The message always arrives once for each started request: when it
succeeds, fails, times out or is cancelled with <cuCancel>.

References: cuRequestSync (handler), cuResponse (handler), cuWatch (handler)
*/
function cuRequestAsync pMethod, pURL, pHeaders, pBody, pOptions, pTarget, pMessage
   local tReq, tR
   put cuMakeRequest(pMethod, pURL, pHeaders, pBody, pOptions) into tReq
   if tReq is 0 then
      return 0
   end if
   put cuStart(tReq) into tR
   if tR < 0 then
      put cuLastError() into sCuMakeError
      get cuFree(tReq)
      return 0
   end if
   cuWatch tReq, pTarget, pMessage
   return tReq
end cuRequestAsync

/**
Summary: Send a message when a started request ends.

pRequest: A request started with <cuStart>.
pTarget: The object to send the message to; empty means this card.
pMessage: The message, sent with the request handle as its parameter.

Description:
<cuRequestAsync> calls this for you. Use it yourself for a request you
built and started by hand. The timer starts if it is not running.

References: cuRequestAsync (handler), cuUnwatch (handler)
*/
command cuWatch pRequest, pTarget, pMessage
   if pRequest is not an integer or pRequest < 1 then
      exit cuWatch
   end if
   if pTarget is empty then
      put the long id of this card into pTarget
   end if
   put pTarget & tab & pMessage into sCuWaiters[pRequest]
   if sCuPollInterval is not an integer or sCuPollInterval < 1 then
      put kCuDefaultInterval into sCuPollInterval
   end if
   if sCuPolling is not "true" then
      put "true" into sCuPolling
      send "cuPollOnce" to me in 0 milliseconds
   end if
end cuWatch

/**
Summary: Stop waiting for a request's message.

pRequest: A handle from <cuRequestNew>.

Description:
The request itself keeps running; use <cuCancel> to stop it.

References: cuWatch (handler)
*/
command cuUnwatch pRequest
   delete variable sCuWaiters[pRequest]
end cuUnwatch

/**
Summary: Set how often the background timer runs.

pIntervalMs: Milliseconds between passes; 20 is the default.

References: cuRequestAsync (handler)
*/
command cuSetPollInterval pIntervalMs
   if pIntervalMs is an integer and pIntervalMs > 0 then
      put pIntervalMs into sCuPollInterval
   end if
end cuSetPollInterval

/**
Summary: How many background requests are waiting to report.

Returns: A count.

References: cuWatch (handler)
*/
function cuWaitingCount
   if sCuWaiters is not an array then
      return 0
   end if
   return the number of lines of the keys of sCuWaiters
end cuWaitingCount

-- The timer. Moves every running request along, dispatches the message of
-- each watched one that ended, tells each watched WebSocket's handler what
-- happened to it, and re-arms only while someone is waiting.
-- A failed poll or dispatch never stops it; the first failure is kept for
-- cuPollLastError (the enetxt pattern).
on cuPollOnce
   local tEnded, tReq, tEntry, tTarget, tMessage, tErr
   if sCuPolling is not "true" then
      exit cuPollOnce
   end if
   put empty into tEnded
   try
      put cuPoll() into tEnded
   catch tErr
      if sCuPollNote is empty then
         put "cuPoll failed: " & line 1 of tErr into sCuPollNote
      end if
   end try
   set the itemDelimiter to comma
   repeat for each item tReq in tEnded
      if tReq is among the keys of sCuWaiters then
         put sCuWaiters[tReq] into tEntry
         delete variable sCuWaiters[tReq]
         set the itemDelimiter to tab
         put item 1 of tEntry into tTarget
         put item 2 of tEntry into tMessage
         set the itemDelimiter to comma
         try
            if tMessage is not empty then
               dispatch tMessage to tTarget with tReq
            end if
         catch tErr
            if sCuPollNote is empty then
               put "dispatch of" && tMessage && "failed: " & line 1 of tErr into sCuPollNote
            end if
         end try
         set the itemDelimiter to comma
      end if
   end repeat
   cuWsDeliver
   if cuWaitingCount() is 0 and cuWsWatchedCount() is 0 then
      put "false" into sCuPolling
      exit cuPollOnce
   end if
   send "cuPollOnce" to me in sCuPollInterval milliseconds
end cuPollOnce

/**
Summary: The first background-timer failure since the last clear.

Returns: Empty while healthy.

References: cuPollClearError (handler)
*/
function cuPollLastError
   return sCuPollNote
end cuPollLastError

/**
Summary: Forget the failure <cuPollLastError> reports.

References: cuPollLastError (handler)
*/
command cuPollClearError
   put empty into sCuPollNote
end cuPollClearError

/**
Summary: Everything about an ended request, as an array.

pRequest: A request handle.

Returns: An array with the keys ok (true when the transfer itself
worked, whatever the server answered), result (0 = success, a libcurl
error number, or 1000 = cancelled), responseCode, error, headers, body,
bytesDown, bytesUp, contentType, effectiveUrl and totalTime.

Description:
An HTTP 404 is a transfer that worked: ok is true and responseCode is
404. ok is false only when the transfer did not complete.

References: cuRequestSync (handler), cuRequestAsync (handler)
*/
function cuResponse pRequest
   local tA
   put cuInfo(pRequest, "result") into tA["result"]
   put (tA["result"] is 0) into tA["ok"]
   put cuInfo(pRequest, "responseCode") into tA["responseCode"]
   put cuText(pRequest, "error") into tA["error"]
   put cuTextData(pRequest, "headers") into tA["headers"]
   put cuBody(pRequest) into tA["body"]
   put cuInfo(pRequest, "bytesDown") into tA["bytesDown"]
   put cuInfo(pRequest, "bytesUp") into tA["bytesUp"]
   put cuText(pRequest, "contentType") into tA["contentType"]
   put cuText(pRequest, "effectiveUrl") into tA["effectiveUrl"]
   put cuInfo(pRequest, "totalTime") into tA["totalTime"]
   return tA
end cuResponse

-- ===================================================================== --
--  WebSockets
-- ===================================================================== --

-- Make, configure and start one socket; 0 with the reason in sCuMakeError.
private function cuWsMake pURL, pHeaders, pOptions
   local tSock, tErr, tR
   put empty into sCuMakeError
   put cuHelpersInit() into tErr
   if tErr is not empty then
      put tErr into sCuMakeError
      return 0
   end if
   put cuWsNew(pURL) into tSock
   if tSock is 0 then
      put cuLastError() into sCuMakeError
      return 0
   end if
   put cuApplyRequest(tSock, pHeaders, empty, pOptions) into tErr
   if tErr is not empty then
      get cuFree(tSock)
      put tErr into sCuMakeError
      return 0
   end if
   put cuStart(tSock) into tR
   if tR < 0 then
      put cuLastError() into sCuMakeError
      get cuFree(tSock)
      return 0
   end if
   return tSock
end cuWsMake

/**
Summary: Open a WebSocket in the background, and get a message for each thing that happens on it.

pURL: The address, starting with ws:// or wss://.
pHeaders: Header lines for the opening request, or empty (a line such as
"Sec-WebSocket-Protocol: chat" asks for a subprotocol).
pOptions: An array of options, or empty (see <cuSetOption> and
<cuSetTextOption>).
pTarget: The object to send the message to; empty means this card.
pMessage: The message. It is sent with three parameters: the socket
handle, what happened, and a value.

Returns: The socket handle, or 0 with the reason in <cuHelpersError>.

Example:
put cuWsOpen("wss://example.com/chat", empty, empty, the long id of me, "chatEvent") into sSocket

The handler chatEvent then gets three parameters, pSocket, pWhat and
pValue. When pWhat is "open" it can send with <cuWsSendText>; when it is
"text", pValue is the message; when it is "closed" it calls <cuFree>.

Description:
What happened is one of:

- "open": the socket is connected. The value is empty.
- "text": a text message arrived. The value is the text.
- "binary": a binary message arrived. The value is its bytes.
- "closed": the socket is over. The value is the close code (1000 is a
normal close, 1006 means the connection was lost, 0 means it never
opened). This always arrives, once, and it is the last message: release
the socket with <cuFree> when it does. <cuText>(pSocket, "error") says
why a socket failed, and <cuText>(pSocket, "wsCloseReason") gives the
reason the other side sent.

Send with <cuWsSendText> and <cuWsSendData>, and close with <cuWsClose>.

References: cuWsOpenSync (handler), cuWsSendText (handler), cuWsClose (handler), cuWsWatch (handler), cuFree (handler)
*/
function cuWsOpen pURL, pHeaders, pOptions, pTarget, pMessage
   local tSock
   put cuWsMake(pURL, pHeaders, pOptions) into tSock
   if tSock is 0 then
      return 0
   end if
   cuWsWatch tSock, pTarget, pMessage
   return tSock
end cuWsOpen

/**
Summary: Open a WebSocket and wait until it is connected.

pURL: The address, starting with ws:// or wss://.
pHeaders: Header lines for the opening request, or empty.
pOptions: An array of options, or empty.
pTimeoutMs: The longest to wait; empty or -1 waits for the socket's own
timeouts.

Returns: The handle of the OPEN socket, or 0 with the reason in
<cuHelpersError>.

Example:
put cuWsOpenSync("wss://example.com/echo", empty, empty, 10000) into tSocket
if tSocket is 0 then answer cuHelpersError()
get cuWsSendText(tSocket, "hello")
if cuWsWait(tSocket, 5000) is 1 then put cuWsReadText(tSocket) into tAnswer
get cuWsClose(tSocket, 1000, empty)
get cuFree(tSocket)

Description:
The script pauses while the socket connects. Nothing watches a socket
opened this way: read it yourself with <cuWsWait> and <cuWsReadText>,
or hand it to the timer with <cuWsWatch>.

References: cuWsOpen (handler), cuWsWait (handler), cuWsWatch (handler)
*/
function cuWsOpenSync pURL, pHeaders, pOptions, pTimeoutMs
   local tSock, tWait, tR, tWhy
   put cuWsMake(pURL, pHeaders, pOptions) into tSock
   if tSock is 0 then
      return 0
   end if
   if pTimeoutMs is an integer then
      put pTimeoutMs into tWait
   else
      put -1 into tWait
   end if
   put cuWsWait(tSock, tWait) into tR
   if cuInfo(tSock, "wsState") is not 2 then
      put cuText(tSock, "error") into tWhy
      if tWhy is empty then
         put "the WebSocket did not open in time" into tWhy
      end if
      get cuFree(tSock)
      put tWhy into sCuMakeError
      return 0
   end if
   return tSock
end cuWsOpenSync

/**
Summary: Send a message for each thing that happens on a started WebSocket.

pSocket: A socket made with <cuWsNew> and started with <cuStart>.
pTarget: The object to send the message to; empty means this card.
pMessage: The message, sent as <cuWsOpen> describes.

Description:
<cuWsOpen> calls this for you. Use it yourself for a socket you built
and started by hand, or opened with <cuWsOpenSync>. The timer starts if
it is not running, and runs for as long as a socket is watched.

References: cuWsOpen (handler), cuWsUnwatch (handler)
*/
command cuWsWatch pSocket, pTarget, pMessage
   if pSocket is not an integer or pSocket < 1 then
      exit cuWsWatch
   end if
   if pTarget is empty then
      put the long id of this card into pTarget
   end if
   put pTarget & tab & pMessage into sCuWsWatch[pSocket]
   if sCuPollInterval is not an integer or sCuPollInterval < 1 then
      put kCuDefaultInterval into sCuPollInterval
   end if
   if sCuPolling is not "true" then
      put "true" into sCuPolling
      send "cuPollOnce" to me in 0 milliseconds
   end if
end cuWsWatch

/**
Summary: Stop sending messages about a WebSocket.

pSocket: A socket handle.

Description:
The socket itself stays as it is; use <cuWsClose> to close it. A socket
nothing watches moves only while something else keeps the timer running,
or while you call <cuWsPoll> or <cuWsWait>.

References: cuWsWatch (handler)
*/
command cuWsUnwatch pSocket
   delete variable sCuWsWatch[pSocket]
   delete variable sCuWsOpened[pSocket]
end cuWsUnwatch

/**
Summary: How many WebSockets the background timer is watching.

Returns: A count.

References: cuWsWatch (handler)
*/
function cuWsWatchedCount
   if sCuWsWatch is not an array then
      return 0
   end if
   return the number of lines of the keys of sCuWsWatch
end cuWsWatchedCount

-- One message to one watched socket's handler. A handler that throws must
-- not stop the timer: the first failure is kept for cuPollLastError.
private command cuWsTell pSocket, pWhat, pValue
   local tEntry, tTarget, tMessage, tErr
   put sCuWsWatch[pSocket] into tEntry
   set the itemDelimiter to tab
   put item 1 of tEntry into tTarget
   put item 2 of tEntry into tMessage
   set the itemDelimiter to comma
   if tMessage is empty then
      exit cuWsTell
   end if
   try
      dispatch tMessage to tTarget with pSocket, pWhat, pValue
   catch tErr
      if sCuPollNote is empty then
         put "dispatch of" && tMessage && "failed: " & line 1 of tErr into sCuPollNote
      end if
   end try
end cuWsTell

-- The WebSocket half of the timer pass (cuPoll has already moved every
-- socket). For each watched socket, in order: "open" once it has opened,
-- then each waiting message, then "closed" once it is over and nothing is
-- left to read. A handler may free or unwatch its socket from inside its
-- message, so the watch is looked up again after every dispatch.
private command cuWsDeliver
   local tSocks, tSock, tState, tSeen, tKind, tWasOpen, tEntry
   if sCuWsWatch is not an array then
      exit cuWsDeliver
   end if
   put the keys of sCuWsWatch into tSocks
   repeat for each line tSock in tSocks
      if tSock is among the keys of sCuWsWatch then
         put cuInfo(tSock, "wsState") into tState
         if tState < 1 then
            -- freed (or never a socket): nothing more can be said about it
            cuWsUnwatch tSock
         else
            put (cuInfo(tSock, "responseCode") is 101) into tWasOpen
            if tWasOpen and tState >= 2 and sCuWsOpened[tSock] is not "true" then
               put "true" into sCuWsOpened[tSock]
               cuWsTell tSock, "open", empty
            end if
            put 0 into tSeen
            repeat while tSeen < kCuWsBatch
               if tSock is not among the keys of sCuWsWatch then
                  exit repeat
               end if
               if cuInfo(tSock, "wsMessages") < 1 then
                  exit repeat
               end if
               add 1 to tSeen
               put cuInfo(tSock, "wsNextType") into tKind
               if tKind is 1 then
                  cuWsTell tSock, "text", cuWsReadText(tSock)
               else
                  cuWsTell tSock, "binary", cuWsRead(tSock)
               end if
            end repeat
            if tSock is among the keys of sCuWsWatch then
               if cuInfo(tSock, "wsState") is 4 and cuInfo(tSock, "wsMessages") < 1 then
                  -- unwatched BEFORE the message, so a handler that opens a
                  -- new socket from inside "closed" is not mistaken for it
                  put sCuWsWatch[tSock] into tEntry
                  delete variable sCuWsOpened[tSock]
                  cuWsLast tSock, tEntry
               end if
            end if
         end if
      end if
   end repeat
end cuWsDeliver

-- The last message of a socket: "closed" with its close code.
private command cuWsLast pSocket, pEntry
   local tTarget, tMessage, tErr
   delete variable sCuWsWatch[pSocket]
   set the itemDelimiter to tab
   put item 1 of pEntry into tTarget
   put item 2 of pEntry into tMessage
   set the itemDelimiter to comma
   if tMessage is empty then
      exit cuWsLast
   end if
   try
      dispatch tMessage to tTarget with pSocket, "closed", cuInfo(pSocket, "wsCloseCode")
   catch tErr
      if sCuPollNote is empty then
         put "dispatch of" && tMessage && "failed: " & line 1 of tErr into sCuPollNote
      end if
   end try
end cuWsLast

-- ---- curlxt/src/tsnet.livecodescript ----

-- tsnet.livecodescript - the tsNet calls, for scripts written against
-- LiveCode's tsNet external, built on curlxt.
--
-- WHAT THIS IS. tsNet was a closed-source libcurl external that LiveCode
-- Ltd shipped with its Indy and Business editions (LiveCode 8.1 onward). It
-- never shipped with Community, so OpenXTalk never had it, and stacks that
-- call tsNetGet, tsNetPostSync or tsNetSmtpSync stop at the first call.
-- This library answers those calls with the same names, parameters,
-- callbacks and "tsneterr:" error strings, implemented over curlxt. It is
-- original code written from the PUBLIC tsNet dictionary only (the
-- docs.livecode.com entries for each call); no tsNet code was seen or used.
--
-- WHERE IT MAY DIFFER from tsNet, said plainly (docs/tsnet-compat.md has
-- the full table):
--   - Each "tsneterr:" message is our own wording; scripts that test only
--     `begins with "tsneterr:"` (as the dictionary tells them to) behave
--     the same.
--   - pSettings: the keys listed in kTsnxSettingKeys are honoured; any other
--     key is ignored rather than refused.
--   - tsNetGetStatus's first word is one of loading, completed, error,
--     timeout, cancelled.
--   - It does not replace libURL: `get url` keeps working exactly as it
--     does today (no "tsNetLibURL" stack is created).
--
-- Every ID's request stays in memory until tsNetCloseConn, until the ID is
-- reused for a new transfer, or until tsNetClose.
--
-- On an engine: tsNetVersion and tsNetGetSync on Windows x86-64
-- (2026-11-15, with an async tsNetGet), and tsNetVersion, tsNetGetSync and
-- tsNetClose on OXT-Beyond's headless Linux server engine (2026-11-21,
-- tests/engine-selftest.lc). Every other call needs an OXT pass.

constant kTsnxVersion = "1.4.5"
constant kTsnxSettingKeys = "username,password,user_agent,referer,use_ssl,try_ssl,use_ssl_control,ssh_private_key,ssh_public_key,ssh_passphrase,pre_commands,post_commands,max_file_size,no_verify"
constant kTsnxCancelledCode = 42
constant kTsnxStatusInterval = 250

local sTsnxReq           -- array: connection ID -> curlxt request handle
local sTsnxId            -- array: request handle -> connection ID
local sTsnxTarget        -- array: connection ID -> object to call back
local sTsnxCallback      -- array: connection ID -> callback message
local sTsnxUpload        -- array: connection ID -> true when it sends data
local sTsnxTimeouts      -- array: the tsNetSetTimeouts values
local sTsnxStatusMsg     -- the tsNetSetStatusCallback message, or empty
local sTsnxStatusTarget  -- the object it goes to
local sTsnxStatusArmed   -- "true" while the status timer runs


-- --------------------------------------------------------- the tsNet calls

/**
Title: tsNet compatibility
Author: Seth Morrow Software
Description:
The tsNet calls (tsNetGet, tsNetPostSync, tsNetSmtpSync and the rest),
for stacks written for LiveCode's tsNet external, built on curlxt.
Put the tsNetCompat stack in use (start using stack "tsNetCompat") and
those scripts run unchanged. New code may prefer curlxt's own calls
(cuRequestSync, cuRequestAsync).

Tags: Networking, Library
*/

/**
Summary: Start the tsNet calls.

Description:
Calling it is optional: every tsNet call starts curlxt when it needs
to. The result is empty, or an error.

References: tsNetClose (handler)
*/
command tsNetInit
   local tErr
   put cuHelpersInit() into tErr
   return tErr
end tsNetInit

/**
Summary: Stop every transfer and close every connection.

References: tsNetInit (handler), tsNetCloseConn (handler)
*/
command tsNetClose
   local tID
   repeat for each key tID in sTsnxReq
      tsnxForget tID
   end repeat
   put empty into sTsnxReq
   put empty into sTsnxId
   cuHelpersRelease
end tsNetClose

/**
Summary: The tsNet version whose calls this library follows.

Returns: "1.4.5", the last tsNet version LiveCode 9 shipped.

Description:
Scripts that check the tsNet version keep working. The native library
underneath is named by <cuLibraryVersion>.

References: cuLibraryVersion (handler)
*/
function tsNetVersion
   return kTsnxVersion
end tsNetVersion

/**
Summary: Set the timeouts every later transfer uses.

pDnsCacheTimeout: Seconds a name lookup is remembered.
pRequestTimeoutMS: Milliseconds the whole transfer may take; 0 = no limit.
pConnectTimeoutMS: Milliseconds to connect.
pAcceptTimeoutMS: Milliseconds to wait for an FTP active-mode server to
connect back (accepted and not used: curlxt uses passive FTP).
pLowSpeedTime: Seconds below pLowSpeedLimit before the transfer stops;
0 = never.
pLowSpeedLimit: Bytes a second.

References: tsNetGet (handler)
*/
command tsNetSetTimeouts pDnsCacheTimeout, pRequestTimeoutMS, pConnectTimeoutMS, pAcceptTimeoutMS, pLowSpeedTime, pLowSpeedLimit
   put empty into sTsnxTimeouts
   if pDnsCacheTimeout is an integer then
      put pDnsCacheTimeout into sTsnxTimeouts["dnsCacheSeconds"]
   end if
   if pRequestTimeoutMS is an integer then
      put pRequestTimeoutMS into sTsnxTimeouts["timeout"]
   end if
   if pConnectTimeoutMS is an integer then
      put pConnectTimeoutMS into sTsnxTimeouts["connectTimeout"]
   end if
   if pLowSpeedTime is an integer then
      put pLowSpeedTime into sTsnxTimeouts["lowSpeedTime"]
   end if
   if pLowSpeedLimit is an integer then
      put pLowSpeedLimit into sTsnxTimeouts["lowSpeedLimit"]
   end if
end tsNetSetTimeouts

/**
Summary: Get progress messages for every transfer.

pCallback: The message; empty turns progress messages off.

Description:
While a transfer runs, the message is sent every quarter second, and
once more when it ends, with: the connection ID, the status (loading,
completed, error, timeout or cancelled), bytes downloaded, total bytes
to download, bytes uploaded and total bytes to upload. A total is 0
when it is not known.

References: tsNetGetStatus (handler)
*/
command tsNetSetStatusCallback pCallback
   put pCallback into sTsnxStatusMsg
   put the long id of the target into sTsnxStatusTarget
   tsnxArmStatus
end tsNetSetStatusCallback

/**
Summary: Download in the background.

pConnectionID: Your name for this transfer.
pURL: An http, https, ftp, ftps or sftp URL.
pHeaders: Request headers, one per line.
pCallback: The message sent when the transfer ends, with the connection
ID, the server's status code, the bytes transferred and the curl result
(0 = success).
pSettings: An optional array of settings.

Returns: Empty, or an error starting "tsneterr:".

Description:
Read the data with <tsNetRetrData> once the callback arrives.

References: tsNetGetSync (handler), tsNetRetrData (handler)
*/
function tsNetGet pConnectionID, pURL, pHeaders, pCallback, pSettings
   return tsnxStartAsync(pConnectionID, "GET", pURL, pHeaders, empty, tsnxOptions(pSettings, pURL), pCallback, the long id of the target, false)
end tsNetGet

/**
Summary: Download and wait for the data.

pURL: The URL.

xHeaders: Request headers, one per line.

rOutHeaders: Receives the response headers.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The data, or an error starting "tsneterr:".

References: tsNetGet (handler)
*/
function tsNetGetSync pURL, @xHeaders, @rOutHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData
   put tsnxRunSync("GET", pURL, xHeaders, empty, tsnxOptions(pSettings, pURL)) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesDown") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuBody(tReq) into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return tFail
   end if
   return tData
end tsNetGetSync

/**
Summary: Send data with POST in the background.

pConnectionID: The connection ID: any text you choose to name this transfer.

pURL: The URL.

pHeaders: Request headers, one per line.

pPostData: The data to post.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetPostSync (handler), tsNetGet (handler)
*/
function tsNetPost pConnectionID, pURL, pHeaders, pPostData, pCallback, pSettings
   return tsnxStartAsync(pConnectionID, "POST", pURL, pHeaders, pPostData, tsnxOptions(pSettings, pURL), pCallback, the long id of the target, false)
end tsNetPost

/**
Summary: Send data with POST and wait for the answer.

pURL: The URL.

xHeaders: Request headers, one per line.

pPostData: The data to post.

rOutHeaders: Receives the response headers.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The data the server sent back, or an error starting "tsneterr:".

References: tsNetPost (handler)
*/
function tsNetPostSync pURL, @xHeaders, pPostData, @rOutHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData
   put tsnxRunSync("POST", pURL, xHeaders, pPostData, tsnxOptions(pSettings, pURL)) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesDown") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuBody(tReq) into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return tFail
   end if
   return tData
end tsNetPostSync

/**
Summary: Ask for headers only, in the background.

pConnectionID: The connection ID: any text you choose to name this transfer.

pURL: The URL.

pHeaders: Request headers, one per line.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetHeadSync (handler), tsNetHeaders (handler)
*/
function tsNetHead pConnectionID, pURL, pHeaders, pCallback, pSettings
   return tsnxStartAsync(pConnectionID, "HEAD", pURL, pHeaders, empty, tsnxOptions(pSettings, pURL), pCallback, the long id of the target, false)
end tsNetHead

/**
Summary: Ask for headers only, and wait.

pURL: The URL.

xHeaders: Request headers, one per line.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The response headers, or an error starting "tsneterr:".

References: tsNetHead (handler)
*/
function tsNetHeadSync pURL, @xHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData
   put tsnxRunSync("HEAD", pURL, xHeaders, empty, tsnxOptions(pSettings, pURL)) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return tReq
   end if
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesDown") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuTextData(tReq, "headers") into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return tFail
   end if
   return tData
end tsNetHeadSync

-- tsNet's custom request is an HTTP method, or a raw command for FTP and
-- SFTP; for those, the command runs and nothing is transferred. Returns
-- pOptions with the method under "_method" (taken out again by the caller).
private function tsnxCustomShape pURL, pRequest, pOptions
   if tsnxScheme(pURL) is among the items of "ftp,ftps,sftp" then
      put "HEAD" into pOptions["_method"]
      put pRequest into pOptions["quote"]
   else
      put pRequest into pOptions["_method"]
   end if
   return pOptions
end tsnxCustomShape

/**
Summary: Send a custom HTTP method, or a raw FTP or SFTP command, in the background.

pConnectionID: The connection ID: any text you choose to name this transfer.

pURL: The URL.

pRequest: The request method, such as DELETE or PATCH; for an ftp, ftps or sftp URL, the command to send.

pHeaders: Request headers, one per line.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetCustomSync (handler)
*/
function tsNetCustom pConnectionID, pURL, pRequest, pHeaders, pCallback, pSettings
   local tMethod, tOptions
   put tsnxCustomShape(pURL, pRequest, tsnxOptions(pSettings, pURL)) into tOptions
   put tOptions["_method"] into tMethod
   delete variable tOptions["_method"]
   return tsnxStartAsync(pConnectionID, tMethod, pURL, pHeaders, empty, tOptions, pCallback, the long id of the target, false)
end tsNetCustom

/**
Summary: Send a custom HTTP method, or a raw FTP or SFTP command, and wait.

pURL: The URL.

pRequest: The request method, such as DELETE or PATCH; for an ftp, ftps or sftp URL, the command to send.

xHeaders: Request headers, one per line.

rOutHeaders: Receives the response headers.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The data retrieved, or an error starting "tsneterr:".

References: tsNetCustom (handler)
*/
function tsNetCustomSync pURL, pRequest, @xHeaders, @rOutHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData, tMethod, tOptions
   put tsnxCustomShape(pURL, pRequest, tsnxOptions(pSettings, pURL)) into tOptions
   put tOptions["_method"] into tMethod
   delete variable tOptions["_method"]
   put tsnxRunSync(tMethod, pURL, xHeaders, empty, tOptions) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesDown") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuBody(tReq) into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return tFail
   end if
   return tData
end tsNetCustomSync

/**
Summary: Download into a file in the background.

pConnectionID: The connection ID: any text you choose to name this transfer.

pFile: The file to save the data to.

pURL: The URL.

pHeaders: Request headers, one per line.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetGetFileSync (handler)
*/
function tsNetGetFile pConnectionID, pFile, pURL, pHeaders, pCallback, pSettings
   local tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFile into tOptions["outputFile"]
   return tsnxStartAsync(pConnectionID, "GET", pURL, pHeaders, empty, tOptions, pCallback, the long id of the target, false)
end tsNetGetFile

/**
Summary: Download into a file and wait.

pFile: The file to save the data to.

pURL: The URL.

xHeaders: Request headers, one per line.

rOutHeaders: Receives the response headers.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The server's status code, or an error starting "tsneterr:".

References: tsNetGetFile (handler)
*/
function tsNetGetFileSync pFile, pURL, @xHeaders, @rOutHeaders, @rBytes, pSettings
   local tReq, tFail, tCode, tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFile into tOptions["outputFile"]
   put tsnxRunSync("GET", pURL, xHeaders, empty, tOptions) into tReq
   if tReq begins with "tsneterr:" then
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "bytesDown") into rBytes
   put cuInfo(tReq, "responseCode") into tCode
   put tsnxFailure(tReq) into tFail
   get cuFree(tReq)
   if tFail is not empty then
      return tFail
   end if
   return tCode
end tsNetGetFileSync

/**
Summary: Upload data in the background (HTTP PUT, FTP or SFTP store).

pConnectionID: The connection ID: any text you choose to name this transfer.

pURL: The URL.

pHeaders: Request headers, one per line.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pData: The data to upload.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetUploadSync (handler), tsNetUploadFile (handler)
*/
function tsNetUpload pConnectionID, pURL, pHeaders, pCallback, pData, pSettings
   return tsnxStartAsync(pConnectionID, "PUT", pURL, pHeaders, pData, tsnxOptions(pSettings, pURL), pCallback, the long id of the target, true)
end tsNetUpload

/**
Summary: Upload data and wait.

pURL: The URL.

xHeaders: Request headers, one per line.

pData: The data to upload.

rOutHeaders: Receives the response headers.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The data the server sent back, or an error starting "tsneterr:".

References: tsNetUpload (handler)
*/
function tsNetUploadSync pURL, @xHeaders, pData, @rOutHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData
   put tsnxRunSync("PUT", pURL, xHeaders, pData, tsnxOptions(pSettings, pURL)) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesUp") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuBody(tReq) into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return tFail
   end if
   return tData
end tsNetUploadSync

/**
Summary: Upload a file in the background.

pConnectionID: The connection ID: any text you choose to name this transfer.

pFile: The file to upload.

pURL: The URL.

pHeaders: Request headers, one per line.

pCallback: The message sent when the transfer ends, with the connection ID, the server's status code, the bytes transferred and the curl result.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetUploadFileSync (handler), tsNetUpload (handler)
*/
function tsNetUploadFile pConnectionID, pFile, pURL, pHeaders, pCallback, pSettings
   local tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFile into tOptions["inputFile"]
   return tsnxStartAsync(pConnectionID, "PUT", pURL, pHeaders, empty, tOptions, pCallback, the long id of the target, true)
end tsNetUploadFile

/**
Summary: Upload a file and wait.

pFile: The file to upload.

pURL: The URL.

xHeaders: Request headers, one per line.

rOutHeaders: Receives the response headers.

rResult: Receives the server's status code.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The data the server sent back; on an error, rResult holds a
string starting "tsneterr:".

References: tsNetUploadFile (handler)
*/
function tsNetUploadFileSync pFile, pURL, @xHeaders, @rOutHeaders, @rResult, @rBytes, pSettings
   local tReq, tFail, tData, tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFile into tOptions["inputFile"]
   put tsnxRunSync("PUT", pURL, xHeaders, empty, tOptions) into tReq
   if tReq begins with "tsneterr:" then
      put tReq into rResult
      return empty
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "responseCode") into rResult
   put cuInfo(tReq, "bytesUp") into rBytes
   put tsnxFailure(tReq) into tFail
   put cuBody(tReq) into tData
   get cuFree(tReq)
   if tFail is not empty then
      put tFail into rResult
      return empty
   end if
   return tData
end tsNetUploadFileSync

/**
Summary: Send a mail message over SMTP in the background.

pConnectionID: Your name for this transfer.
pURL: An smtp:// or smtps:// URL.
pFrom: The sender's address.
pRcpt: The recipients' addresses, one per line or separated by commas.
pCallback: The message sent when the transfer ends.
pData: The whole message: headers, a blank line, then the body.
pSettings: An optional array of settings.

Returns: Empty, or an error starting "tsneterr:".

References: tsNetSmtpSync (handler)
*/
function tsNetSmtp pConnectionID, pURL, pFrom, pRcpt, pCallback, pData, pSettings
   local tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFrom into tOptions["mailFrom"]
   put tsnxRecipients(pRcpt) into tOptions["mailRcpt"]
   return tsnxStartAsync(pConnectionID, "PUT", pURL, empty, pData, tOptions, pCallback, the long id of the target, true)
end tsNetSmtp

/**
Summary: Send a mail message over SMTP and wait.

pURL: The URL.

pFrom: The sender's address.

pRcpt: The recipients' addresses, one per line or separated by commas.

pData: The whole message, headers and body.

rOutHeaders: Receives the response headers.

rBytes: Receives the number of bytes transferred.

pSettings: Optional: an array of tsNet settings; docs/tsnet-compat.md lists the keys honoured.

Returns: The server's last status code (250 when the message was
accepted), or an error starting "tsneterr:".

References: tsNetSmtp (handler)
*/
function tsNetSmtpSync pURL, pFrom, pRcpt, pData, @rOutHeaders, @rBytes, pSettings
   local tReq, tFail, tCode, tOptions
   put tsnxOptions(pSettings, pURL) into tOptions
   put pFrom into tOptions["mailFrom"]
   put tsnxRecipients(pRcpt) into tOptions["mailRcpt"]
   put tsnxRunSync("PUT", pURL, empty, pData, tOptions) into tReq
   if tReq begins with "tsneterr:" then
      return tReq
   end if
   put cuTextData(tReq, "headers") into rOutHeaders
   put cuInfo(tReq, "bytesUp") into rBytes
   put cuInfo(tReq, "responseCode") into tCode
   put tsnxFailure(tReq) into tFail
   get cuFree(tReq)
   if tFail is not empty then
      return tFail
   end if
   return tCode
end tsNetSmtpSync

/**
Summary: The data a background transfer received.

pConnectionID: The connection ID.
rError: Set to empty, or to an error starting "tsneterr:".

Returns: The data.

References: tsNetGet (handler), tsNetRetrError (handler)
*/
function tsNetRetrData pConnectionID, @rError
   local tReq
   put empty into rError
   if pConnectionID is not among the keys of sTsnxReq then
      put tsnxErr("no such connection:" && pConnectionID) into rError
      return empty
   end if
   put sTsnxReq[pConnectionID] into tReq
   put tsnxFailure(tReq) into rError
   return cuBody(tReq)
end tsNetRetrData

/**
Summary: The response headers of a background transfer.

pConnectionID: The connection ID: any text you choose to name this transfer.

Returns: The headers, or an error starting "tsneterr:".

References: tsNetRetrData (handler)
*/
function tsNetHeaders pConnectionID
   if pConnectionID is not among the keys of sTsnxReq then
      return tsnxErr("no such connection:" && pConnectionID)
   end if
   return cuTextData(sTsnxReq[pConnectionID], "headers")
end tsNetHeaders

/**
Summary: Why a background transfer failed.

pConnectionID: The connection ID: any text you choose to name this transfer.

Returns: The error text, empty when it did not fail, or an error starting
"tsneterr:" for an unknown connection.

References: tsNetRetrData (handler)
*/
function tsNetRetrError pConnectionID
   if pConnectionID is not among the keys of sTsnxReq then
      return tsnxErr("no such connection:" && pConnectionID)
   end if
   return cuText(sTsnxReq[pConnectionID], "error")
end tsNetRetrError

/**
Summary: How far a transfer has got.

pConnectionID: The connection ID: any text you choose to name this transfer.

Returns: Five words separated by spaces: the status (loading, completed,
error, timeout or cancelled), bytes downloaded, total bytes to download,
bytes uploaded, total bytes to upload; or an error starting "tsneterr:".

References: tsNetSetStatusCallback (handler)
*/
function tsNetGetStatus pConnectionID
   local tReq
   if pConnectionID is not among the keys of sTsnxReq then
      return tsnxErr("no such connection:" && pConnectionID)
   end if
   put sTsnxReq[pConnectionID] into tReq
   return tsnxStatusWord(tReq) && cuInfo(tReq, "bytesDown") && max(0, cuInfo(tReq, "lengthDown")) \
         && cuInfo(tReq, "bytesUp") && max(0, cuInfo(tReq, "lengthUp"))
end tsNetGetStatus

/**
Summary: Stop a transfer and forget its connection.

pConnectionID: The connection ID: any text you choose to name this transfer.

Description:
The result is empty, or an error starting "tsneterr:" for an unknown
connection. A transfer stopped this way sends no callback.

References: tsNetClose (handler)
*/
command tsNetCloseConn pConnectionID
   if pConnectionID is not among the keys of sTsnxReq then
      return tsnxErr("no such connection:" && pConnectionID)
   end if
   tsnxForget pConnectionID
   return empty
end tsNetCloseConn

-- ------------------------------------------------------------- internals

private function tsnxErr pText
   return "tsneterr: " & pText
end tsnxErr

-- The curlxt options for one transfer: the global timeouts, then pSettings.
private function tsnxOptions pSettings, pURL
   local tOpts, tKey
   put 1 into tOpts["followRedirects"]
   if sTsnxTimeouts is an array then
      repeat for each key tKey in sTsnxTimeouts
         put sTsnxTimeouts[tKey] into tOpts[tKey]
      end repeat
   end if
   if pSettings is not an array then
      return tOpts
   end if
   if pSettings["username"] is not empty then
      put pSettings["username"] into tOpts["username"]
   end if
   if pSettings["password"] is not empty then
      put pSettings["password"] into tOpts["password"]
   end if
   if pSettings["user_agent"] is not empty then
      put pSettings["user_agent"] into tOpts["userAgent"]
   end if
   if pSettings["referer"] is not empty then
      put pSettings["referer"] into tOpts["referer"]
   end if
   if pSettings["use_ssl"] is true then
      put 3 into tOpts["useSsl"]
   else if pSettings["use_ssl_control"] is true then
      put 2 into tOpts["useSsl"]
   else if pSettings["try_ssl"] is true then
      put 1 into tOpts["useSsl"]
   end if
   if pSettings["ssh_private_key"] is not empty then
      put pSettings["ssh_private_key"] into tOpts["sshPrivateKey"]
   end if
   if pSettings["ssh_public_key"] is not empty then
      put pSettings["ssh_public_key"] into tOpts["sshPublicKey"]
   end if
   if pSettings["ssh_passphrase"] is not empty then
      put pSettings["ssh_passphrase"] into tOpts["keyPassword"]
   end if
   if pSettings["pre_commands"] is not empty then
      put pSettings["pre_commands"] into tOpts["quote"]
   end if
   if pSettings["post_commands"] is not empty then
      put pSettings["post_commands"] into tOpts["postQuote"]
   end if
   if pSettings["max_file_size"] is an integer then
      put pSettings["max_file_size"] into tOpts["maxBodyBytes"]
   end if
   if pSettings["no_verify"] is true then
      put 0 into tOpts["verifyPeer"]
      put 0 into tOpts["verifyHost"]
   end if
   return tOpts
end tsnxOptions

-- tsNet takes headers one per line; tolerate CRLF and blank lines.
private function tsnxHeaders pHeaders
   local tLine, tOut
   replace numToChar(13) with empty in pHeaders
   put empty into tOut
   repeat for each line tLine in pHeaders
      if tLine is not empty then
         put tLine & return after tOut
      end if
   end repeat
   return tOut
end tsnxHeaders

-- A recipient list may come one per line or comma-separated.
private function tsnxRecipients pRcpt
   replace comma with return in pRcpt
   return tsnxHeaders(pRcpt)
end tsnxRecipients

private function tsnxScheme pURL
   local tPos
   put offset("://", pURL) into tPos
   if tPos is 0 then
      return empty
   end if
   return char 1 to (tPos - 1) of pURL
end tsnxScheme

private function tsnxInUse pID
   local tReq
   if pID is not among the keys of sTsnxReq then
      return false
   end if
   put sTsnxReq[pID] into tReq
   return (cuInfo(tReq, "state") is 1)
end tsnxInUse

private command tsnxForget pID
   local tReq
   if pID is not among the keys of sTsnxReq then
      exit tsnxForget
   end if
   put sTsnxReq[pID] into tReq
   cuUnwatch tReq
   get cuFree(tReq)
   delete variable sTsnxId[tReq]
   delete variable sTsnxReq[pID]
   delete variable sTsnxTarget[pID]
   delete variable sTsnxCallback[pID]
   delete variable sTsnxUpload[pID]
end tsnxForget

-- Start an asynchronous transfer for a connection ID. Returns empty or a
-- tsneterr string.
private function tsnxStartAsync pID, pMethod, pURL, pHeaders, pBody, pOptions, pCallback, pTarget, pUpload
   local tErr, tReq, tR
   if pID is empty then
      return tsnxErr("no connection ID given")
   end if
   if tsnxInUse(pID) then
      return tsnxErr("connection ID" && pID && "is already in use")
   end if
   tsnxForget pID
   put cuHelpersInit() into tErr
   if tErr is not empty then
      return tsnxErr(tErr)
   end if
   put cuRequestNew(pMethod, pURL) into tReq
   if tReq is 0 then
      return tsnxErr(cuLastError())
   end if
   put cuApplyRequest(tReq, tsnxHeaders(pHeaders), pBody, pOptions) into tErr
   if tErr is not empty then
      get cuFree(tReq)
      return tsnxErr(tErr)
   end if
   put cuStart(tReq) into tR
   if tR < 0 then
      put cuLastError() into tErr
      get cuFree(tReq)
      return tsnxErr(tErr)
   end if
   put tReq into sTsnxReq[pID]
   put pID into sTsnxId[tReq]
   put pTarget into sTsnxTarget[pID]
   put pCallback into sTsnxCallback[pID]
   put (pUpload is true) into sTsnxUpload[pID]
   cuWatch tReq, the long id of me, "tsnxEnded"
   tsnxArmStatus
   return empty
end tsnxStartAsync

-- Run a synchronous transfer. Returns the ENDED request handle, or a
-- tsneterr string when it could not even start. The caller frees it.
private function tsnxRunSync pMethod, pURL, pHeaders, pBody, pOptions
   local tErr, tReq, tR
   put cuHelpersInit() into tErr
   if tErr is not empty then
      return tsnxErr(tErr)
   end if
   put cuRequestNew(pMethod, pURL) into tReq
   if tReq is 0 then
      return tsnxErr(cuLastError())
   end if
   put cuApplyRequest(tReq, tsnxHeaders(pHeaders), pBody, pOptions) into tErr
   if tErr is not empty then
      get cuFree(tReq)
      return tsnxErr(tErr)
   end if
   put cuStart(tReq) into tR
   if tR < 0 then
      put cuLastError() into tErr
      get cuFree(tReq)
      return tsnxErr(tErr)
   end if
   put cuWait(tReq, -1) into tR
   return tReq
end tsnxRunSync

-- The error string of an ended request, or empty when its transfer worked.
private function tsnxFailure pReq
   local tResult
   put cuInfo(pReq, "result") into tResult
   if tResult is 0 then
      return empty
   end if
   return tsnxErr(cuText(pReq, "error") & " (" & tResult & ")")
end tsnxFailure

-- tsNet reports a cancelled transfer as curl's "aborted by callback".
private function tsnxCurlCode pReq
   local tResult
   put cuInfo(pReq, "result") into tResult
   if tResult is 1000 then
      return kTsnxCancelledCode
   end if
   return tResult
end tsnxCurlCode

private function tsnxStatusWord pReq
   local tResult
   if cuInfo(pReq, "state") is 1 then
      return "loading"
   end if
   put cuInfo(pReq, "result") into tResult
   if tResult is 0 then
      return "completed"
   else if tResult is 1000 then
      return "cancelled"
   else if tResult is 28 then
      return "timeout"
   end if
   return "error"
end tsnxStatusWord

-- curlHelpers sends this when a watched transfer ends: call the script's
-- callback with (ID, status code, bytes, curl result), as tsNet does.
on tsnxEnded pReq
   local tID, tBytes, tTarget, tMsg
   if pReq is not among the keys of sTsnxId then
      exit tsnxEnded
   end if
   put sTsnxId[pReq] into tID
   tsnxSendStatus tID
   if sTsnxUpload[tID] is true then
      put cuInfo(pReq, "bytesUp") into tBytes
   else
      put cuInfo(pReq, "bytesDown") into tBytes
   end if
   put sTsnxTarget[tID] into tTarget
   put sTsnxCallback[tID] into tMsg
   if tMsg is not empty then
      dispatch tMsg to tTarget with tID, cuInfo(pReq, "responseCode"), tBytes, tsnxCurlCode(pReq)
   end if
end tsnxEnded

private command tsnxSendStatus pID
   local tReq
   if sTsnxStatusMsg is empty or pID is not among the keys of sTsnxReq then
      exit tsnxSendStatus
   end if
   put sTsnxReq[pID] into tReq
   dispatch sTsnxStatusMsg to sTsnxStatusTarget with pID, tsnxStatusWord(tReq), \
         cuInfo(tReq, "bytesDown"), max(0, cuInfo(tReq, "lengthDown")), \
         cuInfo(tReq, "bytesUp"), max(0, cuInfo(tReq, "lengthUp"))
end tsnxSendStatus

private command tsnxArmStatus
   if sTsnxStatusMsg is empty or sTsnxStatusArmed is "true" then
      exit tsnxArmStatus
   end if
   put "true" into sTsnxStatusArmed
   send "tsnxStatusTick" to me in kTsnxStatusInterval milliseconds
end tsnxArmStatus

-- While a status callback is set and a transfer runs, report progress
-- every kTsnxStatusInterval milliseconds.
on tsnxStatusTick
   local tID, tAny, tErr
   put "false" into sTsnxStatusArmed
   if sTsnxStatusMsg is empty then
      exit tsnxStatusTick
   end if
   put false into tAny
   repeat for each key tID in sTsnxReq
      if cuInfo(sTsnxReq[tID], "state") is 1 then
         put true into tAny
         try
            tsnxSendStatus tID
         catch tErr
         end try
      end if
   end repeat
   if tAny then
      tsnxArmStatus
   end if
end tsnxStatusTick

-- <<< END EMBEDDED LIBRARIES <<<

-- ---- the demo's own constants and state ----------------------------------
-- Bump when the built window changes, so a saved stack rebuilds its controls.
constant kCdUiVersion = "curlxt-live-3"
constant kCdWinW = 1180
constant kCdWinH = 640
-- Room left above the window for its title bar when it is placed (the
-- stack's rect is its card, not its frame).
constant kCdTitleRoom = 32
-- OXT-Beyond's palette (the Render3D Tour's), plus the three status colours.
constant kCdPage = "#12151F"
constant kCdPanel = "#1C2130"
constant kCdInk = "#EEF1F7"
constant kCdSoft = "#A9B2C7"
constant kCdAccent = "#FF8A3D"
constant kCdButton = "#2A3146"
constant kCdDeep = "#161A26"
constant kCdLogBg = "#0E1119"
constant kCdOk = "#5FD38D"
constant kCdWarn = "#F5C04E"
constant kCdBad = "#FF6B6B"
constant kCdTileRun = "#3A4360"
constant kCdTileOk = "#1F6B4A"
constant kCdTileBad = "#7A2E35"
-- The stage, in window coordinates: the graph (the feed and the tiles take
-- its place), its caption, the four readouts, and the progress bar.
constant kCdGraphL = 32
constant kCdGraphT = 128
constant kCdGraphR = 764
constant kCdGraphB = 440
constant kCdCapT = 444
constant kCdBigT = 468
constant kCdBarL = 32
constant kCdBarR = 764
constant kCdBarT = 536
constant kCdBarB = 544
-- The feed shows its last kCdFeedKeep lines, which all fit above kCdFeedB.
constant kCdFeedB = 460
constant kCdFeedKeep = 19
constant kCdFeedLineH = 17
constant kCdTilePitch = 80
constant kCdTileH = 70
-- The frame clock, and how long each scene runs (milliseconds).
constant kCdFrameMs = 40
constant kCdSceneCount = 5
constant kCdFastMs = 12000
constant kCdFastGap = 120
constant kCdSlowGap = 1000
constant kCdRttKeep = 90
constant kCdItemCount = 8
constant kCdItemGap = 900
constant kCdFullMs = 8000
constant kCdFullWindow = 64
constant kCdFullSize = 1000
constant kCdFullSlotMs = 250
constant kCdFullSlots = 32
constant kCdFullDrainMs = 5000
constant kCdTileCount = 16
constant kCdTileLocal = 15
constant kCdLongRun = 25000
-- A request's own limits, which libcurl enforces and reports itself.
constant kCdTimeoutMs = 15000
constant kCdConnectMs = 10000
constant kCdNetTimeoutMs = 8000
constant kCdNetUrl = "https://example.com/"
constant kCdPollMs = 10
constant kCdLogMax = 400
-- The local server: the ports it picks from, its limits, the longest it will
-- make a request wait, and the key RFC 6455 joins to the client's to prove
-- the server read the request.
constant kCdPortLow = 20000
constant kCdPortSpan = 30000
constant kCdSrvMaxBody = 1048576
constant kCdSrvMaxMessage = 65535
constant kCdSrvMaxWait = 3000
-- How long a connection that has had its last bytes waits for its client to
-- close it before the server closes it (cdSrvReap). Every client this stack
-- makes closes at once, so this is for strangers.
constant kCdSrvLingerMs = 3000
constant kCdWsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- ---- script-local state (declared at top) ------------------------------------
local sCdHaveCurl     -- "true" once curlxt answered and the helpers took their hold
local sCdAbi          -- the ABI curlxt reports (2 brings WebSockets)
local sCdVersion      -- cuLibraryVersion's line
local sCdInitError    -- why curlxt could not start, else empty
local sCdT0           -- the milliseconds when the stack opened (the log's clock)
-- the WebSocket every scene uses
local sCdSock         -- its handle, else empty
local sCdWsState      -- "connecting" or "open" while sCdSock is set
local sCdWsUrl        -- the address it was opened to
-- the scene running and its clock
local sCdScene        -- 1 to 5, or 0 for none
local sCdSceneT0      -- the milliseconds it started
local sCdTicking      -- "true" while the frame timer is armed
local sCdDone         -- "true" once the scene has said how it went
local sCdResult       -- that one line
local sCdNextAt       -- the milliseconds the next send or step is due
local sCdStep         -- the next step of scene 5
local sCdSeq          -- messages sent this scene
local sCdBack         -- echoes received this scene
-- scene 1
local sCdRtt          -- round trips in ms, one a line, newest last
local sCdRttSum, sCdRttMin, sCdRttMax, sCdRttCount
-- scene 2
local sCdItems        -- array: number -> kind, data, label, sent
local sCdItemHead     -- the number whose echo comes next
local sCdSame         -- how many came back identical
local sCdChecked      -- bytes of them compared with what was sent
local sCdFeed         -- the feed's lines, as htmlText
-- scene 3
local sCdFullT0       -- when the first message went, else empty
local sCdFullStop     -- when sending stopped, else empty
local sCdFullT1       -- when the last echo came after that, else empty
local sCdFullBody     -- the padding that makes each message kCdFullSize bytes
local sCdSlot         -- array: quarter second -> echoes that landed in it
local sCdInOrder      -- echoes that came back as the n-th, n their own number
local sCdFullBad      -- echoes that came back a different length
local sCdPeak         -- the most echoes a second any quarter second saw
-- scene 4
local sCdTileOf       -- array: request handle -> tile
local sCdTile         -- array: tile -> state, started, waited, label, ms
local sCdTilesDone, sCdTilesLocalT1, sCdTilesWait, sCdNetWords
local sCdTsId        -- the tsNet connection ID this run of scene 4 uses
-- scene 5
local sCdTries        -- reconnect attempts while the server was gone
local sCdFails        -- the attempts that found nothing listening
local sCdCleanCode    -- the close code the clean close gave
local sCdGoneCode     -- the close code the server's going gave
local sCdDownAt       -- when the server went
local sCdBackAt       -- when the socket opened again after that
-- the local server
local sCdSrvPort      -- the port it listens on, else empty
local sCdLastPort     -- the last port it listened on (scene 5 comes back to it)
local sCdConn         -- array: an accepted socket -> what the server knows of it
local sCdSrvSerial    -- the serial the last accepted connection was given

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   cdBuild
   cdPlaceWindow
   cdStart
   -- the boot self-check runs before anything is hosted or connected, and
   -- after the build and start it reads (LAST in this handler's own work)
   cdScRun
   -- straight into motion: the first scene starts a moment after the window
   send "cdAutoStart" to me in 80 milliseconds
end openStack

on closeStack
   cdShutdown
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   if tName begins with "cdScene" and char 8 to -1 of tName is an integer then
      -- a click may come from somewhere that left another stack the
      -- default (the message box, a script that sends mouseUp)
      set the defaultStack to the short name of this stack
      if the enabled of the target then
         cdSceneStart char 8 to -1 of tName
      end if
      exit mouseUp
   end if
   pass mouseUp
end mouseUp

on cdAutoStart
   set the defaultStack to the short name of this stack
   if sCdScene is not 0 and sCdScene is not empty then
      exit cdAutoStart
   end if
   if sCdHaveCurl is not "true" then
      exit cdAutoStart
   end if
   if cdHasWs() then
      cdSceneStart 1
   else
      -- an older curlxt: the requests scene needs no WebSocket
      cdSceneStart 4
   end if
end cdAutoStart

-- Every step guarded: closing with the extension absent, or after a failed
-- start, must not throw out of closeStack.
command cdShutdown
   local tErr
   put 0 into sCdScene
   put "false" into sCdTicking
   cdSrvStop true
   put empty into sCdLastPort
   if sCdSock is not empty then
      try
         cuWsUnwatch sCdSock
         get cuFree(sCdSock)
      catch tErr
      end try
   end if
   put empty into sCdSock
   put empty into sCdWsState
   if sCdHaveCurl is "true" then
      try
         -- tsNetClose forgets every tsNet connection and gives back the
         -- helpers' one hold (cuHelpersRelease); the release that reaches
         -- zero stops and frees everything still running, every request
         -- and old socket included
         tsNetClose
      catch tErr
      end try
   end if
   put empty into sCdHaveCurl
   put empty into sCdTileOf
end cdShutdown

-- ---- the look: OXT-Beyond's dark stage -------------------------------------------
function cdMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end cdMonoFont

-- A quiet field: no border, no background, not editable (the tour's setQuiet).
command cdQuiet pName
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 0
   set the margins of field pName to 2
   set the vScrollbar of field pName to false
   set the autoHilite of field pName to false
end cdQuiet

-- One line of text at a fixed rect. The line's height is the stack's, not
-- the font's: a fixed line height puts the baseline a descent above the
-- line's bottom (MCField::do_recompute), so the words sit in the field
-- whatever the platform says its font's ascent is. With the font's own
-- height, Windows (OXT-Beyond 0.2.8-dp.1, 2026-11-21) drew every label a few
-- pixels too high and its field cut the tops off; the wrapping fields, which
-- always had a fixed height, were whole. The boot self-check holds every
-- label to it (cdLabelFits).
command cdLabel pName, pText, pRect, pSize, pColor, pStyle
   local tHeight
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   cdQuiet pName
   set the rect of field pName to pRect
   set the dontWrap of field pName to true
   set the textSize of field pName to pSize
   set the textStyle of field pName to pStyle
   -- the field's height less its two margins, and never more than one and a
   -- half times the size (the wrapping fields' line)
   put min(the height of field pName - 4, round(pSize * 1.5)) into tHeight
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to tHeight
   set the uCdLabel of field pName to true
   set the foregroundColor of field pName to pColor
   put pText into field pName
end cdLabel

-- True when a label keeps its one line inside it: a fixed line height that
-- its field's height holds with both margins.
function cdLabelFits pName
   if the fixedLineHeight of field pName is not true then
      return false
   end if
   return the textHeight of field pName + 4 <= the height of field pName
end cdLabelFits

-- Text that wraps, with roomy lines (the tour's makeText).
command cdText pName, pText, pRect, pSize, pColor
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   cdQuiet pName
   set the rect of field pName to pRect
   set the dontWrap of field pName to false
   set the textSize of field pName to pSize
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to round(pSize * 1.5)
   set the foregroundColor of field pName to pColor
   put pText into field pName
end cdText

-- A flat rounded button in the tour's colours; the scene that runs is orange.
command cdButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the style of button pName to "roundrect"
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the traversalOn of button pName to false
   set the textSize of button pName to 12
   set the backgroundColor of button pName to kCdButton
   set the foregroundColor of button pName to kCdInk
   set the hiliteColor of button pName to kCdAccent
   -- a theme may draw a border even so: in the stage's own colour, then
   set the borderColor of button pName to kCdTileRun
   set the autoHilite of button pName to false
end cdButton

-- A filled rounded panel (or bar, or tile).
command cdPanel pName, pRect, pColor
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the roundRadius of graphic pName to 8
   set the antialiased of graphic pName to true
   set the filled of graphic pName to true
   set the opaque of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
end cdPanel

-- A line through points (the graph, its shading, the grid).
command cdLine pName, pColor, pSize
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the style of graphic pName to "polygon"
   set the antialiased of graphic pName to true
   set the filled of graphic pName to false
   set the lineSize of graphic pName to pSize
   set the foregroundColor of graphic pName to pColor
   set the points of graphic pName to empty
end cdLine

-- The status line under the header, coloured by what it reports: "ok",
-- "warn", "bad", or anything else for neutral. The boot self-check writes it
-- through this name (its probe and its failure line), so it is spelled as
-- the suite kit spells it, and pinned for the same reason: it is reached from
-- timers and socket messages, when another stack may be the default.
command uiStatus pText, pKind
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kCdOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kCdWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kCdBad
   else
      set the foregroundColor of field "uiStatus" to kCdSoft
   end if
end uiStatus

-- ---- the window (built once; rebuilt on a version bump) -------------------------
command cdBuild
   local tI, tLeft, tTop, tY, tWasLocked
   if the uCdUiVersion of this stack is kCdUiVersion and there is a field "cdLog" then
      exit cdBuild
   end if
   -- Messages locked for the build: every control made or deleted sends a
   -- message the IDE answers (newField, deleteButton, ...), and an open
   -- project browser redraws for each (so say the IDE's own sources, and
   -- box2dxt's platformer locks them for the same reason). On Windows the
   -- first build held the IDE for 22.7 s (2026-11-21). Nothing here listens
   -- for those messages, and the build calls its own handlers, which a lock
   -- does not stop.
   put the lockMessages into tWasLocked
   lock messages
   cdClearGeneratedUI
   lock screen
   set the width of this stack to kCdWinW
   set the height of this stack to kCdWinH
   set the resizable of this stack to false
   set the title of this stack to "curlxt Live - OXT-Beyond"
   set the backgroundColor of this stack to kCdPage
   set the backgroundColor of this card to kCdPage
   -- a theme gives a control with no colour of its own the theme's text
   -- colour, white under a dark one: the stack's own ink and selection
   -- colours come first, and every control below sets its own as well
   set the foregroundColor of this stack to kCdInk
   set the hiliteColor of this stack to kCdAccent
   set the textFont of this stack to empty
   -- the header: whose it is, what it is, what it does, who made it
   cdLabel "cdBrand", "OXT-BEYOND  /  THE CURLXT EXTENSION", "16,6,600,24", 11, kCdAccent, "bold"
   cdLabel "cdTitle", "curlxt Live", "16,24,220,56", 22, kCdInk, "bold"
   cdLabel "cdSub", "Web requests and WebSockets from xTalk, through libcurl, against a server this stack runs itself.", "214,32,990,52", 12, kCdSoft, "plain"
   cdLabel "cdBy", "by Seth Morrow", "994,32,1164,52", 12, kCdSoft, "plain"
   set the textAlign of field "cdBy" to "right"
   cdLabel "uiStatus", empty, "16,58,1164,78", 12, kCdSoft, "plain"
   -- the stage, where a scene draws
   cdPanel "cdStage", "16,86,780,564", kCdPanel
   set the roundRadius of graphic "cdStage" to 10
   cdLabel "cdSceneName", empty, "32,96,560,122", 15, kCdInk, "bold"
   cdLabel "cdSceneClock", empty, "560,98,764,120", 12, kCdSoft, "plain"
   set the textAlign of field "cdSceneClock" to "right"
   cdPanel "cdGraphBg", kCdGraphL & "," & kCdGraphT & "," & kCdGraphR & "," & kCdGraphB, kCdDeep
   repeat with tI = 1 to 4
      cdLine ("cdGrid" & tI), kCdButton, 1
      cdLabel ("cdGridTxt" & tI), empty, "0,0,80,16", 10, kCdSoft, "plain"
   end repeat
   cdLine "cdGraphArea", kCdAccent, 0
   set the filled of graphic "cdGraphArea" to true
   set the opaque of graphic "cdGraphArea" to true
   set the backgroundColor of graphic "cdGraphArea" to kCdAccent
   set the blendLevel of graphic "cdGraphArea" to 82
   cdLine "cdGraphLine", kCdAccent, 2
   cdLabel "cdGraphCap", empty, kCdGraphL & "," & kCdCapT & "," & kCdGraphR & "," & (kCdCapT + 18), 11, kCdSoft, "plain"
   -- the four readouts under the graph: a big number over what it counts,
   -- each 178 wide (built by name, so the derived control list sees them)
   cdLabel "cdBig1", empty, "32," & kCdBigT & ",210," & (kCdBigT + 34), 24, kCdInk, "bold"
   cdLabel "cdCap1", empty, "32," & (kCdBigT + 34) & ",210," & (kCdBigT + 52), 11, kCdSoft, "plain"
   cdLabel "cdBig2", empty, "215," & kCdBigT & ",393," & (kCdBigT + 34), 24, kCdInk, "bold"
   cdLabel "cdCap2", empty, "215," & (kCdBigT + 34) & ",393," & (kCdBigT + 52), 11, kCdSoft, "plain"
   cdLabel "cdBig3", empty, "398," & kCdBigT & ",576," & (kCdBigT + 34), 24, kCdInk, "bold"
   cdLabel "cdCap3", empty, "398," & (kCdBigT + 34) & ",576," & (kCdBigT + 52), 11, kCdSoft, "plain"
   cdLabel "cdBig4", empty, "581," & kCdBigT & ",759," & (kCdBigT + 34), 24, kCdInk, "bold"
   cdLabel "cdCap4", empty, "581," & (kCdBigT + 34) & ",759," & (kCdBigT + 52), 11, kCdSoft, "plain"
   -- the progress bar: how far the scene has come
   cdPanel "cdBarBg", kCdBarL & "," & kCdBarT & "," & kCdBarR & "," & kCdBarB, kCdButton
   cdPanel "cdBarFill", kCdBarL & "," & kCdBarT & "," & (kCdBarL + 8) & "," & kCdBarB, kCdAccent
   set the roundRadius of graphic "cdBarBg" to 8
   set the roundRadius of graphic "cdBarFill" to 8
   -- the feed (scenes 2 and 5) and the tiles (scene 4) share the graph's place
   cdText "cdFeed", empty, kCdGraphL & "," & kCdGraphT & "," & kCdGraphR & "," & kCdFeedB, 12, kCdInk
   set the textFont of field "cdFeed" to cdMonoFont()
   set the dontWrap of field "cdFeed" to true
   set the textHeight of field "cdFeed" to kCdFeedLineH
   repeat with tI = 1 to kCdTileCount
      put kCdGraphL + ((tI - 1) mod 4) * 186 into tLeft
      put kCdGraphT + ((tI - 1) div 4) * kCdTilePitch into tTop
      cdPanel ("cdTile" & tI), tLeft & "," & tTop & "," & (tLeft + 174) & "," & (tTop + kCdTileH), kCdButton
      -- two lines of 18 and the margins are 40 high: centred in the tile
      cdText ("cdTileTxt" & tI), empty, tLeft & "," & (tTop + 15) & "," & (tLeft + 174) & "," & (tTop + 55), 12, kCdInk
      set the textAlign of field ("cdTileTxt" & tI) to "center"
   end repeat
   cdText "cdNotice", empty, "64,220,732,420", 15, kCdInk
   set the textAlign of field "cdNotice" to "center"
   -- the side: the scenes, the connection, what this shows
   cdLabel "cdScenesCap", "SCENES", "796,88,1164,106", 11, kCdAccent, "bold"
   repeat with tI = 1 to kCdSceneCount
      put 110 + (tI - 1) * 32 into tY
      cdButton ("cdScene" & tI), tI & "." && cdSceneTitle(tI), "796," & tY & ",1164," & (tY + 26)
   end repeat
   cdLabel "cdConnCap", "CONNECTION", "796,274,1164,292", 11, kCdAccent, "bold"
   cdPanel "cdWsPillBg", "796,296,890,316", kCdButton
   set the roundRadius of graphic "cdWsPillBg" to 20
   cdLabel "cdWsPill", "closed", "796,297,890,315", 11, kCdSoft, "bold"
   set the textAlign of field "cdWsPill" to "center"
   cdLabel "cdConnInfo", empty, "898,297,1164,315", 11, kCdSoft, "plain"
   cdLabel "cdSrvInfo", empty, "796,320,1164,338", 11, kCdSoft, "plain"
   cdLabel "cdAboutCap", "WHAT THIS SHOWS", "796,346,1164,364", 11, kCdAccent, "bold"
   cdText "cdAbout", empty, "796,368,1164,536", 13, kCdInk
   cdText "cdStats", empty, "796,538,1164,566", 11, kCdSoft
   -- the log: the boot self-check and what happened, newest last
   cdText "cdLog", empty, "16,574,1164,632", 10, kCdSoft
   set the textFont of field "cdLog" to cdMonoFont()
   set the dontWrap of field "cdLog" to true
   set the opaque of field "cdLog" to true
   set the backgroundColor of field "cdLog" to kCdLogBg
   set the showBorder of field "cdLog" to true
   set the borderWidth of field "cdLog" to 1
   set the borderColor of field "cdLog" to kCdButton
   set the margins of field "cdLog" to "6,4,6,4"
   set the vScrollbar of field "cdLog" to true
   set the fixedLineHeight of field "cdLog" to true
   set the textHeight of field "cdLog" to 14
   cdShowStage 0
   set the uCdUiVersion of this stack to kCdUiVersion
   unlock screen
   set the lockMessages to tWasLocked
end cdBuild

-- A script-only stack opens in a small window near the screen's top left,
-- and a width set afterwards keeps the window's centre: 1180 wide, its left
-- edge lands 430 pixels off the screen (Windows, 2026-11-21:
-- -430,-13,750,627; the headless engine makes the same -430). So the window
-- goes to the middle of the screen, unless it is wholly on one already (a
-- stack reopened where its user left it). With no screen at all (the
-- headless engine) it stays put.
command cdPlaceWindow
   local tScreens, tR, tLeft, tTop
   put the working screenRects into tScreens
   if tScreens is empty then
      exit cdPlaceWindow
   end if
   if cdWindowOnScreen(tScreens) then
      exit cdPlaceWindow
   end if
   put line 1 of tScreens into tR
   -- centred in the main screen's working area, never above or left of it
   put max(item 1 of tR, (item 1 of tR + item 3 of tR - the width of this stack) div 2) into tLeft
   put max(item 2 of tR + kCdTitleRoom, (item 2 of tR + item 4 of tR - the height of this stack) div 2) into tTop
   set the topLeft of this stack to tLeft & "," & tTop
end cdPlaceWindow

-- True when the window's top left corner, title bar included, is on one of
-- pScreens (rects, one a line): what cdPlaceWindow promises even on a
-- screen too small for the whole window. The boot self-check holds it.
function cdTitleBarOnScreen pScreens
   local tR, tX, tY
   put item 1 of the rect of this stack into tX
   put item 2 of the rect of this stack - kCdTitleRoom into tY
   repeat for each line tR in pScreens
      if tX >= item 1 of tR and tY >= item 2 of tR and tX < item 3 of tR and tY < item 4 of tR then
         return true
      end if
   end repeat
   return false
end cdTitleBarOnScreen

-- True when the window, its title bar included, is wholly inside one of
-- pScreens (rects, one a line).
function cdWindowOnScreen pScreens
   local tR, tWin
   put the rect of this stack into tWin
   repeat for each line tR in pScreens
      if item 1 of tWin >= item 1 of tR and item 2 of tWin - kCdTitleRoom >= item 2 of tR \
            and item 3 of tWin <= item 3 of tR and item 4 of tWin <= item 4 of tR then
         return true
      end if
   end repeat
   return false
end cdWindowOnScreen

command cdClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "cd" or the short name of field tI of this card is "uiStatus" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "cd" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card begins with "cd" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end cdClearGeneratedUI

function cdSceneTitle pN
   switch pN
      case 1
         return "Round trips"
      case 2
         return "Text and bytes"
      case 3
         return "Full speed"
      case 4
         return "Many requests at once"
      case 5
         return "Close and reconnect"
   end switch
   return empty
end cdSceneTitle

-- Which of the stage's parts a scene uses: 1 and 3 the graph, 2 and 5 the
-- feed, 4 the tiles; 0 shows only the notice.
command cdShowStage pN
   local tGraph, tFeed, tTiles, tI
   put (pN is 1 or pN is 3) into tGraph
   put (pN is 2 or pN is 5) into tFeed
   put (pN is 4) into tTiles
   set the visible of graphic "cdGraphBg" to tGraph
   set the visible of graphic "cdGraphLine" to tGraph
   set the visible of graphic "cdGraphArea" to tGraph
   set the visible of field "cdGraphCap" to tGraph
   repeat with tI = 1 to 4
      set the visible of graphic ("cdGrid" & tI) to tGraph
      set the visible of field ("cdGridTxt" & tI) to tGraph
   end repeat
   set the visible of graphic "cdBarBg" to (pN > 0)
   set the visible of graphic "cdBarFill" to (pN > 0)
   set the visible of field "cdFeed" to tFeed
   repeat with tI = 1 to kCdTileCount
      set the visible of graphic ("cdTile" & tI) to tTiles
      set the visible of field ("cdTileTxt" & tI) to tTiles
   end repeat
   set the visible of field "cdNotice" to (pN is 0)
end cdShowStage

-- The scene buttons: the one running is orange with dark ink, and none
-- works without curlxt; the WebSocket scenes need ABI 2.
command cdPaintScenes
   local tI, tOn
   if there is no field "cdScenesCap" then
      exit cdPaintScenes
   end if
   repeat with tI = 1 to kCdSceneCount
      if tI is 4 then
         put (sCdHaveCurl is "true") into tOn
      else
         put (sCdHaveCurl is "true" and cdHasWs()) into tOn
      end if
      set the enabled of button ("cdScene" & tI) to tOn
      if tI is sCdScene then
         set the backgroundColor of button ("cdScene" & tI) to kCdAccent
         set the foregroundColor of button ("cdScene" & tI) to kCdPage
         set the borderColor of button ("cdScene" & tI) to kCdAccent
      else
         set the backgroundColor of button ("cdScene" & tI) to kCdButton
         set the foregroundColor of button ("cdScene" & tI) to kCdInk
         set the borderColor of button ("cdScene" & tI) to kCdTileRun
      end if
   end repeat
end cdPaintScenes

-- The connection: the pill, the address, the server.
command cdPaintConn
   if there is no field "cdWsPill" then
      exit cdPaintConn
   end if
   if sCdSock is empty then
      put "closed" into field "cdWsPill"
      set the foregroundColor of field "cdWsPill" to kCdSoft
      set the backgroundColor of graphic "cdWsPillBg" to kCdButton
   else if sCdWsState is "open" then
      put "open" into field "cdWsPill"
      set the foregroundColor of field "cdWsPill" to kCdPage
      set the backgroundColor of graphic "cdWsPillBg" to kCdOk
   else
      put "connecting" into field "cdWsPill"
      set the foregroundColor of field "cdWsPill" to kCdPage
      set the backgroundColor of graphic "cdWsPillBg" to kCdWarn
   end if
   put sCdWsUrl into field "cdConnInfo"
   if sCdSrvPort is not empty then
      put "echo server: listening on 127.0.0.1:" & sCdSrvPort & ", inside this stack" into field "cdSrvInfo"
   else
      put "echo server: stopped" into field "cdSrvInfo"
   end if
end cdPaintConn

-- ---- startup (probe, fail closed, and say so on the stage) --------------------------
command cdStart
   local tVer, tErr, tHead
   put the milliseconds into sCdT0
   put empty into sCdHaveCurl
   put empty into sCdAbi
   put empty into sCdVersion
   put empty into sCdInitError
   put 0 into sCdScene
   -- cuLibraryVersion needs no hold and checks no ABI, so it is the probe
   -- that tells "not installed" from "installed but will not start"
   try
      put cuLibraryVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if not (tVer begins with "curlxt ABI ") then
      put "curlxt is not installed" into sCdInitError
      uiStatus "curlxt is NOT loaded: install the curlxt extension (org.openxtalk.library.curl) and reopen this stack.", "bad"
      cdNotice "This stack needs curlxt, the xTalk Suite's web extension, and this engine does not have it. OXT-Beyond carries it built in; elsewhere, install org.openxtalk.library.curl and reopen this stack."
      cdPaintScenes
      cdPaintConn
      exit cdStart
   end if
   put tVer into sCdVersion
   set the itemDelimiter to ";"
   put item 1 of tVer into tHead
   put word 3 of tHead into sCdAbi
   set the itemDelimiter to comma
   -- the helpers' one hold; cuInitialize inside it THROWS when the binding
   -- and the native library disagree about the ABI
   try
      put cuHelpersInit() into sCdInitError
   catch tErr
      put "curlxt could not start: " & line 1 of tErr into sCdInitError
   end try
   if sCdInitError is not empty then
      uiStatus sCdInitError, "bad"
      cdNotice "curlxt is installed but would not start here:" & return & sCdInitError
      cdPaintScenes
      cdPaintConn
      exit cdStart
   end if
   put "true" into sCdHaveCurl
   -- a quicker timer than the helpers' default, so a round trip is measured
   -- in milliseconds rather than in timer ticks
   cuSetPollInterval kCdPollMs
   -- tsNet's own call for its timeouts: the request's, then the connect's
   tsNetSetTimeouts empty, kCdTimeoutMs, kCdConnectMs, empty, empty, empty
   cdLog "curlxt: " & tVer
   if there is a field "cdStats" then
      put tVer into field "cdStats"
   end if
   if cdHasWs() then
      uiStatus "Ready: " & tVer, "ok"
   else
      uiStatus "Ready for requests (" & tVer & "). The WebSocket scenes need curlxt ABI 2.", "warn"
   end if
   cdPaintScenes
   cdPaintConn
end cdStart

function cdHasWs
   if sCdAbi is not an integer then
      return false
   end if
   return sCdAbi >= 2
end cdHasWs

command cdNotice pText
   if there is no field "cdNotice" then
      exit cdNotice
   end if
   cdShowStage 0
   put pText into field "cdNotice"
end cdNotice

-- ---- the scene clock ---------------------------------------------------------------
command cdSceneStart pN
   local tI
   if sCdHaveCurl is not "true" then
      exit cdSceneStart
   end if
   if pN is not 4 and not cdHasWs() then
      uiStatus "This curlxt is ABI " & sCdAbi & ": the WebSocket scenes need ABI 2.", "warn"
      exit cdSceneStart
   end if
   put pN into sCdScene
   put the milliseconds into sCdSceneT0
   put "false" into sCdDone
   put empty into sCdResult
   put 0 into sCdSeq
   put 0 into sCdBack
   put 0 into sCdStep
   put the milliseconds into sCdNextAt
   put empty into sCdFeed
   lock screen
   cdShowStage pN
   put cdSceneTitle(pN) into field "cdSceneName"
   put empty into field "cdSceneClock"
   put cdAboutText(pN) into field "cdAbout"
   put empty into field "cdFeed"
   put empty into field "cdGraphCap"
   repeat with tI = 1 to 4
      put empty into field ("cdBig" & tI)
      put empty into field ("cdCap" & tI)
   end repeat
   set the points of graphic "cdGraphLine" to empty
   set the points of graphic "cdGraphArea" to empty
   cdBar 0
   cdPaintScenes
   unlock screen
   cdLog "scene " & pN & ": " & cdSceneTitle(pN)
   uiStatus "Scene " & pN & ", " & cdSceneTitle(pN) & ": it runs by itself.", empty
   switch pN
      case 1
         put empty into sCdRtt
         put 0 into sCdRttSum
         put 0 into sCdRttCount
         put empty into sCdRttMin
         put empty into sCdRttMax
         break
      case 2
         put empty into sCdItems
         put 1 into sCdItemHead
         put 0 into sCdSame
         put 0 into sCdChecked
         break
      case 3
         put empty into sCdFullT0
         put empty into sCdFullStop
         put empty into sCdFullT1
         put empty into sCdSlot
         put 0 into sCdInOrder
         put 0 into sCdFullBad
         put 0 into sCdPeak
         -- "full", a six-digit number and two spaces make the other 12
         put empty into sCdFullBody
         repeat (kCdFullSize - 12) times
            put "." after sCdFullBody
         end repeat
         break
      case 4
         cdTilesStart
         break
      case 5
         put 0 into sCdTries
         put 0 into sCdFails
         put empty into sCdCleanCode
         put empty into sCdGoneCode
         put empty into sCdDownAt
         put empty into sCdBackAt
         cdFeedAdd "start", "a fresh WebSocket to this stack's own server", kCdSoft
         break
   end switch
   -- every WebSocket scene starts on a fresh socket, so nothing a scene sent
   -- can come back into the next one
   if pN is not 4 then
      cdWsFresh
   else
      cdWsDrop
      cdSrvEnsure
   end if
   cdTickArm
end cdSceneStart

command cdTickArm
   if sCdTicking is "true" then
      exit cdTickArm
   end if
   put "true" into sCdTicking
   send "cdTick" to me in kCdFrameMs milliseconds
end cdTickArm

-- One frame: the scene moves on and is drawn with the screen locked. A
-- scene that throws stops with its reason in the log, never silently.
on cdTick
   local tErr, tNote
   set the defaultStack to the short name of this stack
   put "false" into sCdTicking
   if sCdScene is 0 or sCdScene is empty then
      exit cdTick
   end if
   -- the helpers' timer delivers socket and request messages inside a
   -- try, so a handler of this stack that throws there would be silent:
   -- say it here instead
   put cuPollLastError() into tNote
   if tNote is not empty then
      cuPollClearError
      cdLog "curlxt's timer: " & tNote
      uiStatus "curlxt's timer: " & tNote, "bad"
   end if
   lock screen
   try
      switch sCdScene
         case 1
            cdStep1
            break
         case 2
            cdStep2
            break
         case 3
            cdStep3
            break
         case 4
            cdStep4
            break
         case 5
            cdStep5
            break
      end switch
   catch tErr
      cdLog "scene " & sCdScene & " stopped: " & line 1 of tErr
      uiStatus "Scene " & sCdScene & " stopped: " & line 1 of tErr, "bad"
      put 0 into sCdScene
   end try
   unlock screen
   if sCdScene is not 0 and sCdDone is not "true" then
      cdTickArm
   end if
end cdTick

-- A scene says how it went once, in the log and the status line, and then
-- holds its last picture (scene 1 keeps one round trip a second going).
command cdSceneDone pLine, pKind
   if sCdDone is "true" then
      exit cdSceneDone
   end if
   put pLine into sCdResult
   cdLog "scene " & sCdScene & " done: " & pLine
   uiStatus pLine, pKind
   if sCdScene is not 1 then
      put "true" into sCdDone
   end if
end cdSceneDone

function cdSeconds pMs
   return format("%.1f", pMs / 1000) & " s"
end cdSeconds

command cdClock pText
   put pText into field "cdSceneClock"
end cdClock

-- The progress bar under the readouts, filled to pFraction (0 to 1).
command cdBar pFraction
   local tF, tW
   put pFraction into tF
   if tF is not a number or tF < 0 then
      put 0 into tF
   else if tF > 1 then
      put 1 into tF
   end if
   put max(8, round((kCdBarR - kCdBarL) * tF)) into tW
   set the rect of graphic "cdBarFill" to kCdBarL & "," & kCdBarT & "," & (kCdBarL + tW) & "," & kCdBarB
end cdBar

-- Four readouts at once: a big value and its caption each, in order.
command cdReadouts pB1, pC1, pB2, pC2, pB3, pC3, pB4, pC4
   put pB1 into field "cdBig1"
   put pC1 into field "cdCap1"
   put pB2 into field "cdBig2"
   put pC2 into field "cdCap2"
   put pB3 into field "cdBig3"
   put pC3 into field "cdCap3"
   put pB4 into field "cdBig4"
   put pC4 into field "cdCap4"
end cdReadouts

function cdAboutText pN
   switch pN
      case 1
         return "Each point is one message: the stack sends it over a WebSocket with cuWsSendText, the echo server sends it back, and cuWsOpen's message hands it to the stack, which draws how long the round trip took. Both ends are in this one engine, so the time is libcurl, the engine's sockets and xTalk, with no network in between. After twelve seconds it slows to one a second and keeps going."
      case 2
         return "Text goes out with cuWsSendText as UTF-8 and comes back as text; bytes go out with cuWsSendData and come back as bytes, every value from 0 to 255 included. Each message is compared with what was sent when its echo lands. Four of them are over 125 bytes, so they travel with the protocol's longer length field."
      case 3
         return "For eight seconds the stack keeps 64 messages of 1 KB in flight over one WebSocket: every echo that lands sends the next message. The line is how many came back each second, measured every quarter second, and each echo is checked to come back in the order it was sent. Both ends are xTalk in this one engine."
      case 4
         return "Sixteen requests started together with cuRequestAsync, each ending with its own message: GETs the server makes wait for a while (so they overlap), a POST with a body, a HEAD, one through tsNetGet the way a tsNet script makes it, and one to the internet. When there is no network that tile says so, and the rest work anyway."
      case 5
         return "A WebSocket closes cleanly with code 1000 (cuWsClose), and opens again. Then the server goes away, as real ones do: the socket hears close code 1001, the stack retries while nothing is listening, and connects again once the server is back on the same port."
   end switch
   return empty
end cdAboutText

-- ---- scene 1: round trips ----------------------------------------------------------
command cdStep1
   local tNow, tGap, tAvg
   put the milliseconds into tNow
   -- scene 1 keeps going, so a socket that ended (the machine slept, say)
   -- is opened again, at most every two seconds
   if sCdSock is empty and tNow >= sCdNextAt then
      put tNow + 2000 into sCdNextAt
      cdWsFresh
   end if
   if sCdWsState is "open" and tNow >= sCdNextAt then
      add 1 to sCdSeq
      get cuWsSendText(sCdSock, "rt " & sCdSeq & " " & tNow)
      if tNow - sCdSceneT0 < kCdFastMs then
         put kCdFastGap into tGap
      else
         put kCdSlowGap into tGap
      end if
      put tNow + tGap into sCdNextAt
   end if
   cdBar (tNow - sCdSceneT0) / kCdFastMs
   if tNow - sCdSceneT0 < kCdFastMs then
      cdClock cdSeconds(tNow - sCdSceneT0) & " of " & cdSeconds(kCdFastMs)
   else
      cdClock "live: one round trip a second"
      if sCdDone is not "true" and sCdResult is empty and sCdRttCount > 0 then
         put round(sCdRttSum / sCdRttCount, 1) into tAvg
         cdSceneDone sCdRttCount & " round trips, average " & tAvg & " ms, fastest " & cdMs(sCdRttMin), "ok"
      end if
   end if
   cdDrawSeries sCdRtt, "ms", kCdRttKeep, false
   put "how long each round trip took, newest on the right" into field "cdGraphCap"
end cdStep1

command cdOnEcho1 pKind, pValue
   local tRtt
   if pKind is not "text" or word 1 of pValue is not "rt" then
      exit cdOnEcho1
   end if
   put the milliseconds - word 3 of pValue into tRtt
   add 1 to sCdBack
   put tRtt & return after sCdRtt
   if the number of lines of sCdRtt > kCdRttKeep then
      delete line 1 of sCdRtt
   end if
   add tRtt to sCdRttSum
   add 1 to sCdRttCount
   if sCdRttMin is empty or tRtt < sCdRttMin then
      put tRtt into sCdRttMin
   end if
   if sCdRttMax is empty or tRtt > sCdRttMax then
      put tRtt into sCdRttMax
   end if
   cdReadouts cdMs(tRtt), "the last round trip", round(sCdRttSum / sCdRttCount, 1) & " ms", "on average", \
         cdMs(sCdRttMin), "the fastest", sCdSeq & " / " & sCdBack, "sent / back"
end cdOnEcho1

-- A time in milliseconds as words: the clock counts whole milliseconds, so
-- 0 means "under one".
function cdMs pMs
   if pMs < 1 then
      return "under 1 ms"
   end if
   return pMs & " ms"
end cdMs

-- A series of values as a line over the graph, on a scale that rounds up to
-- a tidy number. The graph has room for pSlots of them: pFromLeft true fills
-- it from the left (a run of known length), false keeps the newest at the
-- right (a run that keeps going).
command cdDrawSeries pValues, pUnit, pSlots, pFromLeft
   local tMax, tScale, tN, tI, tX, tY, tPoints, tW, tV, tFirstX
   put the number of lines of pValues into tN
   put 0 into tMax
   repeat for each line tV in pValues
      if tV > tMax then
         put tV into tMax
      end if
   end repeat
   put cdNiceScale(tMax) into tScale
   cdDrawGrid tScale, pUnit
   if tN < 2 then
      set the points of graphic "cdGraphLine" to empty
      set the points of graphic "cdGraphArea" to empty
      exit cdDrawSeries
   end if
   put (kCdGraphR - kCdGraphL - 64) / (pSlots - 1) into tW
   put 0 into tI
   repeat for each line tV in pValues
      add 1 to tI
      if pFromLeft is true then
         put round(kCdGraphL + 52 + (tI - 1) * tW) into tX
      else
         put round(kCdGraphR - 12 - (tN - tI) * tW) into tX
      end if
      put round(kCdGraphB - 10 - (tV / tScale) * (kCdGraphB - kCdGraphT - 24)) into tY
      if tI is 1 then
         put tX into tFirstX
      end if
      put tX & "," & tY & return after tPoints
   end repeat
   delete the last char of tPoints
   set the points of graphic "cdGraphLine" to tPoints
   set the points of graphic "cdGraphArea" to tPoints & return & tX & "," & (kCdGraphB - 10) \
         & return & tFirstX & "," & (kCdGraphB - 10) & return & line 1 of tPoints
end cdDrawSeries

-- Four grid lines, the top one at pScale, each labelled.
command cdDrawGrid pScale, pUnit
   local tI, tY, tV
   repeat with tI = 1 to 4
      put round(kCdGraphB - 10 - (tI / 4) * (kCdGraphB - kCdGraphT - 24)) into tY
      set the points of graphic ("cdGrid" & tI) to (kCdGraphL + 44) & "," & tY & return & (kCdGraphR - 8) & "," & tY
      put pScale * tI / 4 into tV
      if tV is not an integer then
         put format("%.1f", tV) into tV
      end if
      put tV && pUnit into field ("cdGridTxt" & tI)
      set the rect of field ("cdGridTxt" & tI) to (kCdGraphL + 4) & "," & (tY - 9) & "," & (kCdGraphL + 84) & "," & (tY + 7)
   end repeat
end cdDrawGrid

function cdNiceScale pMax
   local tStep
   repeat for each item tStep in "5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000"
      if pMax <= tStep then
         return tStep
      end if
   end repeat
   return pMax
end cdNiceScale

-- ---- scene 2: text and bytes ---------------------------------------------------------
-- Item pN: its kind (text or binary), its data, and what to call it. The
-- non-ASCII text is built from code points: the suite keeps its sources ASCII.
function cdItem pN
   local tA, tI, tData
   switch pN
      case 1
         put "text" into tA["kind"]
         put "Hello from xTalk" into tA["data"]
         put "plain text" into tA["label"]
         break
      case 2
         put "text" into tA["kind"]
         put "Gr" & numToCodepoint(252) & numToCodepoint(223) & "e aus Wien, " & numToCodepoint(231) & "a va" into tA["data"]
         put "accented text" into tA["label"]
         break
      case 3
         put "text" into tA["kind"]
         put cdCodepoints("915,949,953,940,32,963,959,965,32,954,972,963,956,949") into tA["data"]
         put "Greek" into tA["label"]
         break
      case 4
         put "text" into tA["kind"]
         put cdCodepoints("12371,12435,12395,12385,12399,19990,30028") into tA["data"]
         put "Japanese" into tA["label"]
         break
      case 5
         repeat with tI = 0 to 255
            put numToByte(tI) after tData
         end repeat
         put "binary" into tA["kind"]
         put tData into tA["data"]
         put "every byte value" into tA["label"]
         break
      case 6
         repeat 4096 times
            put numToByte(random(256) - 1) after tData
         end repeat
         put "binary" into tA["kind"]
         put tData into tA["data"]
         put "4 KB of random bytes" into tA["label"]
         break
      case 7
         repeat 2000 times
            put "xTalk say " after tData
         end repeat
         put "text" into tA["kind"]
         put tData into tA["data"]
         put "20,000 characters" into tA["label"]
         break
      case 8
         repeat 60000 times
            put numToByte(random(256) - 1) after tData
         end repeat
         put "binary" into tA["kind"]
         put tData into tA["data"]
         put "60 KB of bytes" into tA["label"]
         break
   end switch
   return tA
end cdItem

function cdCodepoints pList
   local tCp, tOut
   repeat for each item tCp in pList
      put numToCodepoint(tCp) after tOut
   end repeat
   return tOut
end cdCodepoints

command cdStep2
   local tNow, tA, tR
   put the milliseconds into tNow
   if sCdWsState is "open" and tNow >= sCdNextAt and sCdSeq < kCdItemCount then
      add 1 to sCdSeq
      put cdItem(sCdSeq) into tA
      put tNow into tA["sent"]
      put tA into sCdItems[sCdSeq]
      if tA["kind"] is "text" then
         put cuWsSendText(sCdSock, tA["data"]) into tR
      else
         put cuWsSendData(sCdSock, tA["data"]) into tR
      end if
      if tR < 0 then
         cdFeedAdd "refused", tA["label"] & ": " & cuLastError(), kCdBad
      else
         cdFeedAdd "out", tA["label"] & ", " & cdSize(tA) & ": " & cdPreview(tA), kCdInk
      end if
      put tNow + kCdItemGap into sCdNextAt
   end if
   cdClock sCdBack & " of " & kCdItemCount & " back"
   cdBar sCdBack / kCdItemCount
   cdReadouts sCdSeq, "messages sent", sCdBack, "came back", sCdSame, "identical to what went", \
         format("%.1f", sCdChecked / 1024) & " KB", "checked on the way back"
   if sCdBack is kCdItemCount then
      if sCdSame is kCdItemCount then
         cdSceneDone kCdItemCount & " messages, text and bytes, all " & kCdItemCount & " back identical", "ok"
      else
         cdSceneDone (kCdItemCount - sCdSame) & " of " & kCdItemCount & " messages came back different", "bad"
      end if
   else if tNow - sCdSceneT0 > kCdLongRun then
      cdSceneDone "only " & sCdBack & " of " & kCdItemCount & " messages came back in " & cdSeconds(kCdLongRun), "bad"
   end if
end cdStep2

command cdOnEcho2 pKind, pValue
   local tA, tOk
   if sCdItemHead > sCdSeq then
      exit cdOnEcho2
   end if
   put sCdItems[sCdItemHead] into tA
   add 1 to sCdItemHead
   add 1 to sCdBack
   if tA["kind"] is "text" then
      put (pKind is "text" and cdSame(pValue, tA["data"])) into tOk
   else
      put (pKind is "binary" and cdSame(base64Encode(pValue), base64Encode(tA["data"]))) into tOk
   end if
   if tA["kind"] is "text" then
      add the number of bytes of textEncode(tA["data"], "UTF-8") to sCdChecked
   else
      add the number of bytes of tA["data"] to sCdChecked
   end if
   if tOk then
      add 1 to sCdSame
      cdFeedAdd "back", "in " & (the milliseconds - tA["sent"]) & " ms, identical", kCdOk
   else
      cdFeedAdd "back", "DIFFERENT: " & the number of bytes of pValue & " bytes as " & pKind, kCdBad
   end if
end cdOnEcho2

function cdSize pA
   if pA["kind"] is "text" then
      return the number of bytes of textEncode(pA["data"], "UTF-8") & " bytes of UTF-8"
   end if
   return the number of bytes of pA["data"] & " bytes"
end cdSize

function cdPreview pA
   local tData
   put pA["data"] into tData
   if pA["kind"] is "binary" then
      return cdHex(tData, 8) & " ..."
   end if
   if the number of chars of tData > 28 then
      return char 1 to 28 of tData & " ..."
   end if
   return tData
end cdPreview

-- One line of the feed: a tag in its colour, then the words. The feed keeps
-- its last lines only.
command cdFeedAdd pTag, pWords, pColor
   local tLine
   put "<p><font color=" & quote & pColor & quote & ">" & cdHtml(cdPad(pTag, 10)) & "</font>" \
         & cdHtml(pWords) & "</p>" into tLine
   put tLine & return after sCdFeed
   if the number of lines of sCdFeed > kCdFeedKeep then
      delete line 1 of sCdFeed
   end if
   if there is a field "cdFeed" then
      set the htmlText of field "cdFeed" to sCdFeed
   end if
end cdFeedAdd

function cdPad pText, pWidth
   repeat while the number of chars of pText < pWidth
      put space after pText
   end repeat
   return pText
end cdPad

function cdHtml pText
   replace "&" with "&amp;" in pText
   replace "<" with "&lt;" in pText
   replace ">" with "&gt;" in pText
   return pText
end cdHtml

-- ---- scene 3: full speed ----------------------------------------------------------------
-- kCdFullWindow messages always in flight: each echo that lands sends the
-- next one (cdOnEcho3), and the frame tops the window up too, for a send
-- that was refused or a window not yet filled. After kCdFullMs no more go
-- out, and the scene ends when the last echo is in.
command cdStep3
   local tNow, tRun, tDone, tRates, tI, tRate, tNowRate, tAvg, tEnd
   put the milliseconds into tNow
   if sCdWsState is "open" and sCdFullT0 is empty then
      put tNow into sCdFullT0
      cdFullTopUp
      cdLog "scene 3: " & sCdSeq & " messages of " & kCdFullSize & " bytes in flight"
   end if
   if sCdFullT0 is empty then
      cdClock "connecting..."
      if tNow - sCdSceneT0 > kCdConnectMs + 2000 then
         cdSceneDone "the WebSocket did not open in " & cdSeconds(kCdConnectMs + 2000), "bad"
      end if
      exit cdStep3
   end if
   put tNow - sCdFullT0 into tRun
   if sCdFullStop is empty then
      if tRun >= kCdFullMs then
         put tNow into sCdFullStop
         cdLog "scene 3: sending stopped after " & cdSeconds(kCdFullMs) & ", " & (sCdSeq - sCdBack) & " still in flight"
         if sCdBack >= sCdSeq and sCdFullT1 is empty then
            put tNow into sCdFullT1
         end if
      else
         cdFullTopUp
      end if
   end if
   -- the rate of each quarter second that is over, at most the run's own
   put min((tRun div kCdFullSlotMs), kCdFullSlots) into tDone
   put empty into tRates
   repeat with tI = 1 to tDone
      put round((sCdSlot[tI] + 0) * 1000 / kCdFullSlotMs) into tRate
      put tRate & return after tRates
      if tRate > sCdPeak then
         put tRate into sCdPeak
      end if
      put tRate into tNowRate
   end repeat
   if tRates is not empty then
      delete the last char of tRates
   end if
   cdDrawSeries tRates, "/s", kCdFullSlots, true
   put "echoes a second, measured every quarter second, with " & kCdFullWindow & " messages always in flight" into field "cdGraphCap"
   if sCdFullT1 is not empty then
      put sCdFullT1 into tEnd
   else
      put tNow into tEnd
   end if
   if tEnd > sCdFullT0 then
      put round(sCdBack * 1000 / (tEnd - sCdFullT0)) into tAvg
   else
      put 0 into tAvg
   end if
   if sCdFullStop is empty then
      cdClock cdSeconds(tRun) & " of " & cdSeconds(kCdFullMs)
      cdBar tRun / kCdFullMs
      cdReadouts sCdBack, "echoes back", (tNowRate + 0), "a second, right now", \
            round((tNowRate + 0) * kCdFullSize / 1024) & " KB", "a second, each way", \
            cdOrderWord(), "every echo in order"
   else
      cdBar 1
      cdReadouts sCdBack, "echoes back", tAvg, "a second, on average", \
            sCdPeak, "a second at the peak", cdOrderWord(), "every echo in order"
      if sCdFullT1 is empty then
         cdClock "the last " & (sCdSeq - sCdBack) & " in flight..."
      else
         cdClock cdSeconds(sCdFullT1 - sCdFullT0)
      end if
   end if
   if sCdFullT1 is not empty then
      if sCdInOrder is sCdBack and sCdFullBad is 0 then
         cdSceneDone sCdBack & " messages echoed in " & cdSeconds(sCdFullT1 - sCdFullT0) \
               & ", every one back in order (" & tAvg & " a second, peak " & sCdPeak & ")", "ok"
      else
         cdSceneDone (sCdBack - sCdInOrder) & " of " & sCdBack & " echoes came back out of order, and " \
               & sCdFullBad & " a different length", "bad"
      end if
   else if sCdFullStop is not empty and tNow - sCdFullStop > kCdFullDrainMs then
      cdSceneDone "only " & sCdBack & " of " & sCdSeq & " echoes came back (" \
            & (sCdSeq - sCdBack) & " still missing " & cdSeconds(kCdFullDrainMs) & " after the last went)", "bad"
   end if
end cdStep3

function cdOrderWord
   if sCdInOrder is sCdBack and sCdFullBad is 0 then
      return "yes"
   end if
   return "NO"
end cdOrderWord

-- Send until kCdFullWindow are in flight. A refused send (the socket is
-- gone, or curlxt's send queue is full) waits for the next frame.
command cdFullTopUp
   local tR
   if sCdWsState is not "open" or sCdFullStop is not empty then
      exit cdFullTopUp
   end if
   repeat while sCdSeq - sCdBack < kCdFullWindow
      put cuWsSendText(sCdSock, "full " & format("%06d", sCdSeq + 1) & " " & sCdFullBody) into tR
      if tR < 0 then
         exit repeat
      end if
      add 1 to sCdSeq
   end repeat
end cdFullTopUp

-- An echo: the n-th to land must carry number n, at its full length.
command cdOnEcho3 pKind, pValue
   local tSlot
   if pKind is not "text" or word 1 of pValue is not "full" then
      exit cdOnEcho3
   end if
   add 1 to sCdBack
   if word 2 of pValue is sCdBack then
      add 1 to sCdInOrder
   end if
   if the number of chars of pValue is not kCdFullSize then
      add 1 to sCdFullBad
   end if
   put (the milliseconds - sCdFullT0) div kCdFullSlotMs + 1 into tSlot
   add 1 to sCdSlot[tSlot]
   if sCdFullStop is empty then
      cdFullTopUp
   else if sCdBack >= sCdSeq and sCdFullT1 is empty then
      put the milliseconds into sCdFullT1
   end if
end cdOnEcho3

-- ---- scene 4: many requests at once ------------------------------------------------------
-- Tiles 1-12 GET, 13 POST, 14 HEAD (all cuRequestAsync), 15 tsNetGet: all to
-- this stack's own server, which makes each wait a while before it answers.
-- Tile 16 goes to the internet.
command cdTilesStart
   local tI
   put empty into sCdTileOf
   put empty into sCdTile
   put 0 into sCdTilesDone
   put empty into sCdTilesLocalT1
   put 0 into sCdTilesWait
   put empty into sCdNetWords
   -- a fresh ID each run: one still running from an earlier run keeps its own
   put "tile15-" & sCdSceneT0 into sCdTsId
   repeat with tI = 1 to kCdTileCount
      put "queued" into sCdTile[tI]["state"]
      put cdTileName(tI) into sCdTile[tI]["label"]
      cdTilePaint tI
   end repeat
end cdTilesStart

function cdTileName pTile
   if pTile <= 12 then
      return "GET " & pTile
   end if
   switch pTile
      case 13
         return "POST"
      case 14
         return "HEAD"
      case 15
         return "tsNetGet"
   end switch
   return "the internet"
end cdTileName

-- Start every request (once the server listens), all in one go.
command cdTilesGo
   local tI, tWait, tUrl, tMethod, tBody, tHeaders, tOpts, tReq, tR
   put kCdTimeoutMs into tOpts["timeout"]
   put kCdConnectMs into tOpts["connectTimeout"]
   repeat with tI = 1 to kCdTileLocal
      put 300 + random(1500) into tWait
      add tWait to sCdTilesWait
      put tWait into sCdTile[tI]["waited"]
      put "http://127.0.0.1:" & sCdSrvPort & "/tile/" & tI & "?wait=" & tWait into tUrl
      put the milliseconds into sCdTile[tI]["started"]
      put "running" into sCdTile[tI]["state"]
      -- the tile says so at once (it said "queued" until its answer came)
      cdTilePaint tI
      if tI is 15 then
         -- the tsNet spelling: a connection ID, and a callback with tsNet's
         -- own four parameters
         put tsNetGet(sCdTsId, tUrl, empty, "cdTsEnded") into tR
         if tR is not empty then
            cdTileEnd 15, false, tR
         end if
         next repeat
      end if
      put "GET" into tMethod
      put empty into tBody
      put empty into tHeaders
      if tI is 13 then
         put "POST" into tMethod
         put textEncode("a POST body from tile 13", "UTF-8") into tBody
         put "Content-Type: text/plain; charset=utf-8" into tHeaders
      else if tI is 14 then
         put "HEAD" into tMethod
      end if
      put cuRequestAsync(tMethod, tUrl, tHeaders, tBody, tOpts, the long id of me, "cdTileEnded") into tReq
      if tReq is 0 then
         cdTileEnd tI, false, cuHelpersError()
      else
         put tI into sCdTileOf[tReq]
      end if
   end repeat
   -- out to the internet: a missing network is said plainly, nothing else
   -- depends on it
   put kCdNetTimeoutMs into tOpts["timeout"]
   put kCdNetTimeoutMs into tOpts["connectTimeout"]
   put the milliseconds into sCdTile[16]["started"]
   put "running" into sCdTile[16]["state"]
   cdTilePaint 16
   put cuRequestAsync("GET", kCdNetUrl, empty, empty, tOpts, the long id of me, "cdTileEnded") into tReq
   if tReq is 0 then
      cdTileEnd 16, false, cuHelpersError()
   else
      put 16 into sCdTileOf[tReq]
   end if
   cdLog "scene 4: " & kCdTileCount & " requests started together (" & cdSeconds(sCdTilesWait) & " of waiting asked of the server)"
end cdTilesGo

-- cuRequestAsync's message, once for each request, however it ended.
on cdTileEnded pReq
   local tI, tA, tOk, tWords
   set the defaultStack to the short name of this stack
   if pReq is not among the keys of sCdTileOf then
      -- a request from a scene that is over: release it quietly
      get cuFree(pReq)
      exit cdTileEnded
   end if
   put sCdTileOf[pReq] into tI
   delete variable sCdTileOf[pReq]
   put cuResponse(pReq) into tA
   get cuFree(pReq)
   put (tA["ok"] is true and tA["responseCode"] is 200) into tOk
   if tOk then
      put "HTTP 200" into tWords
      if tI is 13 then
         put ", " & tA["bytesUp"] & " bytes up" after tWords
      else if tI is 14 then
         put ", headers only" after tWords
      end if
   else if tA["ok"] is true then
      put "HTTP " & tA["responseCode"] into tWords
   else
      put tA["error"] into tWords
   end if
   cdTileEnd tI, tOk, tWords
end cdTileEnded

-- tsNetGet's callback, with tsNet's own four parameters.
on cdTsEnded pID, pResult, pBytes, pCurlCode
   local tErr, tData
   set the defaultStack to the short name of this stack
   if pID is not sCdTsId or sCdScene is not 4 then
      tsNetCloseConn pID
      exit cdTsEnded
   end if
   put tsNetRetrData(pID, tErr) into tData
   -- the connection keeps its answer until it is closed
   tsNetCloseConn pID
   if tErr is not empty then
      cdTileEnd 15, false, tErr
   else
      cdTileEnd 15, (pResult is 200), "status " & pResult & ", " & pBytes & " bytes"
   end if
end cdTsEnded

command cdTileEnd pTile, pOk, pWords
   if sCdTile[pTile]["state"] is "done" or sCdTile[pTile]["state"] is "failed" then
      exit cdTileEnd
   end if
   if pOk then
      put "done" into sCdTile[pTile]["state"]
   else
      put "failed" into sCdTile[pTile]["state"]
   end if
   put the milliseconds - sCdTile[pTile]["started"] into sCdTile[pTile]["ms"]
   put pWords into sCdTile[pTile]["words"]
   add 1 to sCdTilesDone
   if pTile is 16 then
      if pOk then
         put "the internet answered too (" & sCdTile[16]["ms"] & " ms)" into sCdNetWords
      else
         put "the internet was not reached (" & pWords & ")" into sCdNetWords
      end if
      cdLog "scene 4: " & kCdNetUrl & ": " & pWords
   else if not pOk then
      -- a local request should never fail: say which, and why, where it can
      -- be copied from (the tile has room for one word)
      cdLog "scene 4: " & cdTileName(pTile) & " failed after " & sCdTile[pTile]["ms"] & " ms: " & pWords
   end if
   cdTilePaint pTile
end cdTileEnd

command cdTilePaint pTile
   local tState, tColor, tWords
   put sCdTile[pTile]["state"] into tState
   switch tState
      case "done"
         put kCdTileOk into tColor
         put sCdTile[pTile]["ms"] & " ms" into tWords
         break
      case "failed"
         put kCdTileBad into tColor
         if pTile is 16 then
            put "not reached" into tWords
         else
            put "failed" into tWords
         end if
         break
      case "running"
         put kCdTileRun into tColor
         put "waiting..." into tWords
         break
      default
         put kCdButton into tColor
         put "queued" into tWords
   end switch
   set the backgroundColor of graphic ("cdTile" & pTile) to tColor
   put sCdTile[pTile]["label"] & return & tWords into field ("cdTileTxt" & pTile)
   set the foregroundColor of field ("cdTileTxt" & pTile) to kCdInk
end cdTilePaint

command cdStep4
   local tNow, tI, tLocalDone, tTook, tBlend, tFaster
   put the milliseconds into tNow
   if sCdSeq is 0 then
      if sCdSrvPort is empty then
         cdClock "starting the server..."
         exit cdStep4
      end if
      put 1 into sCdSeq
      cdTilesGo
   end if
   -- the running tiles breathe, so a wait looks like one
   put 40 + round(30 * sin((tNow - sCdSceneT0) / 180)) into tBlend
   put 0 into tLocalDone
   repeat with tI = 1 to kCdTileCount
      if sCdTile[tI]["state"] is "running" then
         set the blendLevel of graphic ("cdTile" & tI) to tBlend
      else
         set the blendLevel of graphic ("cdTile" & tI) to 0
         if tI <= kCdTileLocal then
            add 1 to tLocalDone
         end if
      end if
   end repeat
   if tLocalDone is kCdTileLocal and sCdTilesLocalT1 is empty then
      put tNow into sCdTilesLocalT1
   end if
   if sCdTilesLocalT1 is not empty then
      put sCdTilesLocalT1 - sCdSceneT0 into tTook
   else
      put tNow - sCdSceneT0 into tTook
   end if
   if tTook > 0 then
      put format("%.1f", sCdTilesWait / tTook) & " x" into tFaster
   else
      put "-" into tFaster
   end if
   cdReadouts sCdTilesDone & " / " & kCdTileCount, "requests ended", \
         cdSeconds(sCdTilesWait), "of waiting asked, all told", \
         cdSeconds(tTook), "for all " & kCdTileLocal & " local ones", \
         tFaster, "faster than one at a time"
   cdBar sCdTilesDone / kCdTileCount
   cdClock cdSeconds(tNow - sCdSceneT0)
   if sCdTilesDone is kCdTileCount then
      cdSceneDone cdTilesSummary(), cdTilesKind()
   else if tNow - sCdSceneT0 > kCdLongRun then
      cdSceneDone "only " & sCdTilesDone & " of " & kCdTileCount & " requests ended in " & cdSeconds(kCdLongRun), "bad"
   end if
end cdStep4

function cdTilesLocalOk
   local tI, tN
   put 0 into tN
   repeat with tI = 1 to kCdTileLocal
      if sCdTile[tI]["state"] is "done" then
         add 1 to tN
      end if
   end repeat
   return tN
end cdTilesLocalOk

function cdTilesSummary
   return cdTilesLocalOk() & " of " & kCdTileLocal & " local requests answered in " \
         & cdSeconds(sCdTilesLocalT1 - sCdSceneT0) & " for " & cdSeconds(sCdTilesWait) \
         & " of waiting asked; " & sCdNetWords
end cdTilesSummary

function cdTilesKind
   if cdTilesLocalOk() is not kCdTileLocal then
      return "bad"
   end if
   if sCdTile[16]["state"] is not "done" then
      return "warn"
   end if
   return "ok"
end cdTilesKind

-- ---- scene 5: close and reconnect -------------------------------------------------------
-- A script of steps. Steps 1, 2, 4, 6, 8, 10 and 11 run when their time
-- comes (sCdNextAt); 0, 3, 5, 7, 9 and 12 wait for the socket's own message.
command cdStep5
   local tNow, tWas, tDown
   put the milliseconds into tNow
   if sCdDownAt is empty then
      put "-" into tDown
   else if sCdBackAt is empty then
      put cdSeconds(tNow - sCdDownAt) into tDown
   else
      put cdSeconds(sCdBackAt - sCdDownAt) into tDown
   end if
   cdReadouts cdOr(sCdCleanCode, "-"), "the clean close's code", \
         cdOr(sCdGoneCode, "-"), "the code as the server went", \
         sCdFails, "tries that found no server", tDown, "without a server"
   cdBar sCdStep / 13
   cdClock cdSeconds(tNow - sCdSceneT0)
   if tNow - sCdSceneT0 > kCdLongRun and sCdDone is not "true" then
      cdSceneDone "stopped at step " & sCdStep & " after " & cdSeconds(kCdLongRun), "bad"
      exit cdStep5
   end if
   if tNow < sCdNextAt then
      exit cdStep5
   end if
   switch sCdStep
      case 1
         if sCdSock is empty then
            exit cdStep5
         end if
         get cuWsSendText(sCdSock, "hello before the close")
         cdFeedAdd "out", "hello before the close", kCdInk
         put 2 into sCdStep
         put tNow + 1200 into sCdNextAt
         break
      case 2
         if sCdSock is empty then
            exit cdStep5
         end if
         get cuWsClose(sCdSock, 1000, "scene 5 says goodbye")
         cdFeedAdd "closing", "code 1000 sent with cuWsClose", kCdWarn
         put 3 into sCdStep
         break
      case 4
         cdFeedAdd "opening", "the same address again", kCdWarn
         cdWsOpenTo sCdSrvPort
         put 5 into sCdStep
         break
      case 6
         cdFeedAdd "server", "goes away, as a real one might", kCdWarn
         cdSrvStop
         put 7 into sCdStep
         break
      case 8
         add 1 to sCdTries
         cdFeedAdd "retry " & sCdTries, "port " & sCdLastPort & ", where nothing listens now", kCdWarn
         cdWsOpenTo sCdLastPort
         put 9 into sCdStep
         break
      case 10
         put sCdLastPort into tWas
         cdSrvStart
         if sCdSrvPort is empty then
            cdSceneDone "the server could not come back", "bad"
            exit cdStep5
         end if
         if sCdSrvPort is tWas then
            cdFeedAdd "server", "back on the same port, " & sCdSrvPort, kCdOk
         else
            cdFeedAdd "server", "back on port " & sCdSrvPort & " (the old one was still held)", kCdOk
         end if
         put 11 into sCdStep
         put tNow + 300 into sCdNextAt
         break
      case 11
         add 1 to sCdTries
         cdFeedAdd "retry " & sCdTries, "port " & sCdSrvPort & ", where the server is back", kCdWarn
         cdWsOpenTo sCdSrvPort
         put 12 into sCdStep
         break
   end switch
end cdStep5

-- The socket's own messages move scene 5 along.
command cdOnOpen5
   if sCdStep is 0 then
      cdFeedAdd "open", sCdWsUrl, kCdOk
      put 1 into sCdStep
      put the milliseconds + 600 into sCdNextAt
   else if sCdStep is 5 then
      cdFeedAdd "open", "again, on a new socket", kCdOk
      put 6 into sCdStep
      put the milliseconds + 1200 into sCdNextAt
   else if sCdStep is 12 then
      put the milliseconds into sCdBackAt
      cdFeedAdd "open", "again, " & cdSeconds(sCdBackAt - sCdDownAt) & " after the server went", kCdOk
      get cuWsSendText(sCdSock, "hello after the reconnect")
      cdFeedAdd "out", "hello after the reconnect", kCdInk
      put 13 into sCdStep
   end if
end cdOnOpen5

command cdOnClosed5 pCode, pWords, pError
   if sCdStep is 3 then
      put pCode into sCdCleanCode
      cdFeedAdd "closed", pWords, kCdSoft
      put 4 into sCdStep
      put the milliseconds + 1000 into sCdNextAt
   else if sCdStep is 7 then
      put pCode into sCdGoneCode
      cdFeedAdd "closed", pWords, kCdSoft
      put the milliseconds into sCdDownAt
      put 8 into sCdStep
      put the milliseconds + 700 into sCdNextAt
   else if sCdStep is 9 then
      -- what is expected here, said shortly: nothing listens on that port
      add 1 to sCdFails
      cdFeedAdd "no server", "nothing answered (" & cdLastClause(pError) & ")", kCdWarn
      if sCdTries < 2 then
         put 8 into sCdStep
         put the milliseconds + 1000 * sCdTries into sCdNextAt
      else
         put 10 into sCdStep
         put the milliseconds + 800 into sCdNextAt
      end if
   else if sCdStep is 12 then
      cdFeedAdd "failed", pWords, kCdBad
      cdSceneDone "the reconnect failed: " & pWords, "bad"
   end if
end cdOnClosed5

command cdOnEcho5 pKind, pValue
   local tLine, tKind
   cdFeedAdd "back", pValue, kCdOk
   if sCdStep is not 13 then
      exit cdOnEcho5
   end if
   put "ok" into tKind
   if sCdCleanCode is 1000 then
      put "closed cleanly (1000)" into tLine
   else
      put "closed with code " & cdOr(sCdCleanCode, "none") & ", not 1000" into tLine
      put "warn" into tKind
   end if
   if sCdGoneCode is 1001 then
      put ", heard the server go (code 1001)" after tLine
   else
      put ", heard the server go with code " & cdOr(sCdGoneCode, "none") & ", not 1001" after tLine
      put "warn" into tKind
   end if
   put ", found nothing there " & cdTimes(sCdFails) & ", and reconnected " \
         & cdSeconds(sCdBackAt - sCdDownAt) & " after it went" after tLine
   cdSceneDone tLine, tKind
end cdOnEcho5

-- pValue, or pElse when it is empty.
function cdOr pValue, pElse
   if pValue is empty then
      return pElse
   end if
   return pValue
end cdOr

function cdTimes pN
   if pN is 1 then
      return "once"
   else if pN is 2 then
      return "twice"
   end if
   return pN & " times"
end cdTimes

-- The last clause of an error ("... after 10 ms: Could not connect to
-- server" gives "Could not connect to server"), or all of it.
function cdLastClause pText
   local tAt
   repeat with tAt = the number of chars of pText - 1 down to 1
      if char tAt to (tAt + 1) of pText is ": " then
         return char (tAt + 2) to -1 of pText
      end if
   end repeat
   if pText is empty then
      return "no reason given"
   end if
   return pText
end cdLastClause

-- ---- the WebSocket every scene uses --------------------------------------------------------
-- A fresh socket to this stack's own server. The old one is let go: closed
-- if it was open, stopped if it was still connecting; its "closed" message
-- frees it later (cdWsEvent: no longer ours).
command cdWsFresh
   cdWsDrop
   cdSrvEnsure
   if sCdSrvPort is empty then
      exit cdWsFresh
   end if
   cdWsOpenTo sCdSrvPort
end cdWsFresh

-- Let the current socket go (if there is one); this stack forgets it now.
command cdWsDrop
   local tOld
   put sCdSock into tOld
   put empty into sCdSock
   put empty into sCdWsState
   if tOld is not empty then
      cdWsLetGo tOld
   end if
   cdPaintConn
end cdWsDrop

command cdWsLetGo pSock
   local tState
   put cuInfo(pSock, "wsState") into tState
   if tState is 2 then
      get cuWsClose(pSock, 1000, "the next scene")
   else if tState is 1 then
      get cuCancel(pSock)
   end if
end cdWsLetGo

command cdWsOpenTo pPort
   local tUrl, tOpts, tSock
   put "ws://127.0.0.1:" & pPort & "/echo" into tUrl
   -- timeout bounds the OPENING, never the socket's life
   put kCdTimeoutMs into tOpts["timeout"]
   put kCdConnectMs into tOpts["connectTimeout"]
   put cuWsOpen(tUrl, empty, tOpts, the long id of me, "cdWsEvent") into tSock
   put tUrl into sCdWsUrl
   if tSock is 0 then
      cdLog "WebSocket: could not open " & tUrl & ": " & cuHelpersError()
      uiStatus "The WebSocket could not be opened: " & cuHelpersError(), "bad"
      cdPaintConn
      exit cdWsOpenTo
   end if
   put tSock into sCdSock
   put "connecting" into sCdWsState
   cdPaintConn
end cdWsOpenTo

-- cuWsOpen's message: "open", "text", "binary", then "closed" exactly once.
on cdWsEvent pSocket, pWhat, pValue
   local tWords, tError
   set the defaultStack to the short name of this stack
   if pSocket is not sCdSock then
      -- a socket this stack let go of: release it at its last message
      if pWhat is "closed" then
         get cuFree(pSocket)
      end if
      exit cdWsEvent
   end if
   switch pWhat
      case "open"
         put "open" into sCdWsState
         cdLog "socket " & pSocket & ": open to " & sCdWsUrl
         if sCdScene is 5 then
            cdOnOpen5
         end if
         break
      case "text"
      case "binary"
         switch sCdScene
            case 1
               cdOnEcho1 pWhat, pValue
               break
            case 2
               cdOnEcho2 pWhat, pValue
               break
            case 3
               cdOnEcho3 pWhat, pValue
               break
            case 5
               cdOnEcho5 pWhat, pValue
               break
         end switch
         break
      case "closed"
         -- read why BEFORE cuFree: the reason lives with the handle
         put cdCloseWords(pSocket, pValue) into tWords
         put cuText(pSocket, "error") into tError
         get cuFree(pSocket)
         put empty into sCdSock
         put empty into sCdWsState
         cdLog "socket " & pSocket & ": closed, " & tWords
         if sCdScene is 5 then
            cdOnClosed5 pValue, tWords, tError
         end if
         break
   end switch
   cdPaintConn
end cdWsEvent

function cdCloseWords pSocket, pCode
   local tWords, tReason, tError
   if pCode is 1000 then
      put "code 1000 (a normal close)" into tWords
   else if pCode is 1001 then
      put "code 1001 (the server went away)" into tWords
   else if pCode is 1005 then
      put "code 1005 (a close with no code)" into tWords
   else if pCode is 1006 then
      put "code 1006 (the connection ended without a close)" into tWords
   else if pCode is 0 then
      put "it never opened" into tWords
   else
      put "code " & pCode into tWords
   end if
   put cuText(pSocket, "wsCloseReason") into tReason
   if tReason is not empty then
      put ", reason " & quote & tReason & quote after tWords
   end if
   put cuText(pSocket, "error") into tError
   if tError is not empty then
      put ", " & tError after tWords
   end if
   return tWords
end cdCloseWords

-- ---- the echo server: HTTP and WebSockets on the engine's own sockets -------------------
-- It starts with the first scene that needs it and listens until the stack
-- closes (scene 5 stops it on purpose, and starts it again on the same
-- port). Nothing it does waits: every read and every write is the engine's
-- background kind.
--
-- Once a connection's last bytes are written (cdSrvWrote) it is the CLIENT
-- that ends it: the answer says "Connection: close", or the close frame says
-- goodbye, and the client's socketClosed ends it here. The server does not
-- close a connection by its id once the client may have closed it, because
-- the id may already name the next connection: on Windows the engine names
-- an accepted socket after its handle, and Windows hands a closed one's
-- handle to the next connection at once (engine note 6.20). Closing by the
-- id then closed the NEW connection, which its client saw as "Empty reply
-- from server" (one request in four on Windows, 2026-11-21). A connection
-- that outstays kCdSrvLingerMs is closed by its serial (cdSrvReap).
command cdSrvEnsure
   if sCdSrvPort is empty then
      cdSrvStart
   end if
end cdSrvEnsure

command cdSrvStart
   local tTry, tPort, tErr
   if sCdSrvPort is not empty then
      exit cdSrvStart
   end if
   -- the port it had before comes first, so scene 5's client finds it again
   repeat with tTry = 0 to 5
      if tTry is 0 then
         if sCdLastPort is empty then
            next repeat
         end if
         put sCdLastPort into tPort
      else
         put kCdPortLow + random(kCdPortSpan) into tPort
      end if
      accept connections on port tPort with message "cdSrvAccept"
      -- a failed bind shows ONLY in the result (engine note 6.12)
      put the result into tErr
      if tErr is empty then
         put tPort into sCdSrvPort
         exit repeat
      end if
      if tTry is 0 then
         cdLog "server: port " & tPort & " is still held (" & tErr & "); another port then"
      end if
   end repeat
   if sCdSrvPort is empty then
      cdLog "server: could not listen: " & tErr
      uiStatus "The echo server could not listen on this machine: " & tErr, "bad"
      cdPaintConn
      exit cdSrvStart
   end if
   put sCdSrvPort into sCdLastPort
   cdLog "server: listening on 127.0.0.1:" & sCdSrvPort & " (HTTP and WebSocket, this machine only)"
   cdPaintConn
end cdSrvStart

-- pNow true (closing the stack): every connection ends at once. Otherwise a
-- WebSocket hears close code 1001 ("going away") first, as it would from a
-- real server shutting down, and its connection ends once that is written.
command cdSrvStop pNow
   local tSocks, tSock
   put the keys of sCdConn into tSocks
   repeat for each line tSock in tSocks
      if pNow is not true and sCdConn[tSock]["kind"] is "ws" \
            and sCdConn[tSock]["done"] is not true then
         cdSrvSend tSock, 8, numToByte(3) & numToByte(233), true
      else
         cdSrvForget tSock
      end if
   end repeat
   if sCdSrvPort is empty then
      exit cdSrvStop
   end if
   cdSrvCloseSocket sCdSrvPort
   cdLog "server: stopped; port " & sCdSrvPort & " closed"
   put empty into sCdSrvPort
   cdPaintConn
end cdSrvStop

-- Close a socket the engine still lists, and nothing else.
command cdSrvCloseSocket pSock
   local tErr
   if pSock is empty then
      exit cdSrvCloseSocket
   end if
   if pSock is among the lines of the openSockets then
      try
         close socket pSock
      catch tErr
      end try
   end if
end cdSrvCloseSocket

function cdSrvKnows pSock
   return pSock is among the keys of sCdConn
end cdSrvKnows

-- Forget a connection and close it: only for one the engine still holds
-- open as THIS connection (refused at its accept, a request that never came,
-- the server stopping, cdSrvReap).
command cdSrvForget pSock
   delete variable sCdConn[pSock]
   cdSrvCloseSocket pSock
end cdSrvForget

-- Forget a connection the engine has closed already (its socketClosed or
-- socketError came, or a read came back short because it closed), and do
-- NOT close by its id, which may be the next connection's now (engine note
-- 6.20).
command cdSrvDrop pSock
   delete variable sCdConn[pSock]
end cdSrvDrop

-- A connection had its last bytes kCdSrvLingerMs ago and its client has not
-- closed it. pSerial says which connection the timer was set for: an id the
-- engine has since given to another connection has another serial, and is
-- left alone. The serial knows only the accepts that have come: a client
-- that closed and a new connection on its id, both still queued when this
-- timer runs, would need the engine held for kCdSrvLingerMs across the two,
-- and every client this stack makes closes long before.
on cdSrvReap pSock, pSerial
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvReap
   end if
   if sCdConn[pSock]["serial"] is not pSerial then
      exit cdSrvReap
   end if
   if pSock is among the lines of the openSockets then
      cdLog "server: " & pSock & " was still open " & cdSeconds(kCdSrvLingerMs) & " after its last bytes; closed it"
   end if
   cdSrvForget pSock
end cdSrvReap

-- The HOST of an accepted socket id, by shape (engine note 6.2): drop a
-- "|name" suffix; a bracketed group is the host; otherwise everything up to
-- the LAST colon, since an IPv6 host has colons of its own. The boot
-- self-check holds it to five ids.
function cdSrvHostOf pSock
   local tRaw, tAt
   put pSock into tRaw
   put offset("|", tRaw) into tAt
   if tAt > 0 then
      put char 1 to tAt - 1 of tRaw into tRaw
   end if
   if char 1 of tRaw is "[" then
      put offset("]", tRaw) into tAt
      if tAt < 3 then
         return empty
      end if
      return char 2 to tAt - 1 of tRaw
   end if
   repeat with tAt = the number of chars of tRaw down to 1
      if char tAt of tRaw is ":" then
         return char 1 to tAt - 1 of tRaw
      end if
   end repeat
   return tRaw
end cdSrvHostOf

function cdSrvIsLoopback pHost
   return pHost is "127.0.0.1" or pHost is "::1" or pHost is "::ffff:127.0.0.1"
end cdSrvIsLoopback

on cdSrvAccept pSock
   set the defaultStack to the short name of this stack
   cdSrvTakeId pSock
   if sCdSrvPort is empty then
      cdSrvForget pSock
      exit cdSrvAccept
   end if
   if not cdSrvIsLoopback(cdSrvHostOf(pSock)) then
      cdLog "server: refused " & pSock & " (only this machine may connect)"
      cdSrvForget pSock
      exit cdSrvAccept
   end if
   cdSrvReadHead pSock
end cdSrvAccept

-- A connection's first moment: a serial of its own and a fresh entry. An id
-- the server still holds is a connection that has ended without the server
-- hearing it (engine note 6.20: on Windows the id is the socket's handle,
-- which the next connection gets at once). Its entry goes, unclosed: the id
-- is the new connection's now. The boot self-check holds it to that.
command cdSrvTakeId pSock
   if cdSrvKnows(pSock) then
      cdSrvDrop pSock
   end if
   add 1 to sCdSrvSerial
   put sCdSrvSerial into sCdConn[pSock]["serial"]
   put "head" into sCdConn[pSock]["stage"]
   put "http" into sCdConn[pSock]["kind"]
   put 0 into sCdConn[pSock]["out"]
   put false into sCdConn[pSock]["done"]
end cdSrvTakeId

command cdSrvReadHead pSock
   local tEnd
   put crlf & crlf into tEnd
   -- the data arrives WITH the delimiter (engine note 6.10)
   read from socket pSock until tEnd with message "cdSrvHead"
end cdSrvReadHead

-- One request head: the request line, then the headers this server reads.
on cdSrvHead pSock, pData
   local tHead, tLine, tName, tValue, tColon, tLines, tLen, tKey, tUpgrade, tExpect
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvHead
   end if
   if pData is empty then
      -- the read ended because the client closed before it sent anything
      cdSrvDrop pSock
      exit cdSrvHead
   end if
   put pData into tHead
   replace numToChar(13) with empty in tHead
   if not (word 3 of line 1 of tHead begins with "HTTP/") then
      cdSrvReply pSock, "400 Bad Request", textEncode("That is not an HTTP request." & return, "UTF-8"), false
      exit cdSrvHead
   end if
   put 0 into tLen
   put 0 into tLines
   put false into tUpgrade
   put false into tExpect
   repeat for each line tLine in line 2 to -1 of tHead
      put offset(":", tLine) into tColon
      if tColon > 1 then
         add 1 to tLines
         put char 1 to tColon - 1 of tLine into tName
         -- the inner chunk in parentheses: unparenthesized, this line stops
         -- the whole script from compiling (the suite's engine note 1.10)
         put word 1 to -1 of (char (tColon + 1) to -1 of tLine) into tValue
         if tName is "Content-Length" then
            put tValue into tLen
         else if tName is "Sec-WebSocket-Key" then
            put tValue into tKey
         else if tName is "Upgrade" then
            put (tValue is "websocket") into tUpgrade
         else if tName is "Expect" then
            put (tValue is "100-continue") into tExpect
         end if
      end if
   end repeat
   put word 1 of line 1 of tHead into sCdConn[pSock]["method"]
   put word 2 of line 1 of tHead into sCdConn[pSock]["path"]
   put tLines into sCdConn[pSock]["lines"]
   put cdSrvWaitOf(word 2 of line 1 of tHead) into sCdConn[pSock]["wait"]
   if tUpgrade and tKey is not empty then
      cdSrvUpgrade pSock, tKey
      exit cdSrvHead
   end if
   if tLen is not an integer then
      cdSrvReply pSock, "400 Bad Request", textEncode("Content-Length is not a whole number." & return, "UTF-8"), false
      exit cdSrvHead
   end if
   if tLen > kCdSrvMaxBody then
      cdSrvReply pSock, "413 Payload Too Large", textEncode("This server reads at most " & kCdSrvMaxBody & " bytes of body." & return, "UTF-8"), false
      exit cdSrvHead
   end if
   if tLen < 1 then
      cdSrvAnswer pSock, empty
      exit cdSrvHead
   end if
   if tExpect then
      cdSrvWrite pSock, "HTTP/1.1 100 Continue" & crlf & crlf
   end if
   put "body" into sCdConn[pSock]["stage"]
   read from socket pSock for tLen with message "cdSrvBody"
end cdSrvHead

-- "?wait=N" in a path asks this server to take N milliseconds over its
-- answer (scene 4 asks it, so its requests overlap); at most kCdSrvMaxWait.
function cdSrvWaitOf pPath
   local tAt, tWait
   put offset("wait=", pPath) into tAt
   if tAt is 0 then
      return 0
   end if
   put char (tAt + 5) to -1 of pPath into tWait
   put offset("&", tWait) into tAt
   if tAt > 0 then
      put char 1 to tAt - 1 of tWait into tWait
   end if
   if tWait is not an integer or tWait < 0 then
      return 0
   end if
   return min(tWait, kCdSrvMaxWait)
end cdSrvWaitOf

on cdSrvBody pSock, pData
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvBody
   end if
   cdSrvAnswer pSock, pData
end cdSrvBody

-- Any method, any path: say what arrived, and send a body back as it came.
-- A request that asked for a wait is answered by cdSrvLater when it is up.
command cdSrvAnswer pSock, pBody
   local tWait
   put pBody into sCdConn[pSock]["body"]
   put sCdConn[pSock]["wait"] into tWait
   if tWait > 0 then
      put "waiting" into sCdConn[pSock]["stage"]
      -- the serial goes with it: a client that gave up while it waited
      -- leaves its id free for the next connection (engine note 6.20),
      -- which is not to be answered early
      send ("cdSrvLater" && quote & pSock & quote & comma & sCdConn[pSock]["serial"]) \
            to me in tWait milliseconds
      exit cdSrvAnswer
   end if
   cdSrvAnswerNow pSock
end cdSrvAnswer

on cdSrvLater pSock, pSerial
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvLater
   end if
   if sCdConn[pSock]["serial"] is not pSerial or sCdConn[pSock]["stage"] is not "waiting" then
      exit cdSrvLater
   end if
   cdSrvAnswerNow pSock
end cdSrvLater

command cdSrvAnswerNow pSock
   local tMethod, tText, tBody, tPosted
   put sCdConn[pSock]["method"] into tMethod
   put sCdConn[pSock]["body"] into tPosted
   put "Hello from the curlxt Live stack's own server: xTalk on the engine's sockets." & return \
         & "You sent " & tMethod && sCdConn[pSock]["path"] & " with " & sCdConn[pSock]["lines"] \
         & " header lines and " & the number of bytes of tPosted & " bytes of body, and I took " \
         & sCdConn[pSock]["wait"] & " ms to answer." & return into tText
   put textEncode(tText, "UTF-8") into tBody
   if tPosted is not empty then
      put textEncode("Here is that body, sent back:" & return, "UTF-8") after tBody
      put tPosted after tBody
   end if
   cdSrvReply pSock, "200 OK", tBody, (tMethod is "HEAD")
end cdSrvAnswerNow

-- One answer, then the connection ends ("Connection: close"): its client
-- closes it once it has read the answer (cdSrvWrote).
command cdSrvReply pSock, pStatus, pBody, pHeadOnly
   local tHead, tAll
   put "HTTP/1.1 " & pStatus & crlf & "Content-Type: text/plain; charset=utf-8" & crlf \
         & "Content-Length: " & the number of bytes of pBody & crlf \
         & "X-Served-By: curlxt-live" & crlf & "X-Waited-Ms: " & (sCdConn[pSock]["wait"] + 0) & crlf \
         & "Connection: close" & crlf & crlf into tHead
   put textEncode(tHead, "UTF-8") into tAll
   if pHeadOnly is not true then
      put pBody after tAll
   end if
   put true into sCdConn[pSock]["done"]
   cdSrvWrite pSock, tAll
end cdSrvReply

-- Every write is the background kind, and counted, so the server knows when
-- a connection's last bytes are out.
command cdSrvWrite pSock, pData
   add 1 to sCdConn[pSock]["out"]
   write pData to socket pSock with message "cdSrvWrote"
end cdSrvWrite

-- When the last bytes of a connection that is done are out, its client
-- closes it (see the top of the server), and cdSrvReap closes it from here
-- only if that has not happened in kCdSrvLingerMs. The serial goes with the
-- timer, so a connection that has been given the id by then is left alone.
on cdSrvWrote pSock
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvWrote
   end if
   subtract 1 from sCdConn[pSock]["out"]
   if sCdConn[pSock]["done"] is true and sCdConn[pSock]["out"] < 1 \
         and sCdConn[pSock]["stage"] is not "ended" then
      put "ended" into sCdConn[pSock]["stage"]
      send ("cdSrvReap" && quote & pSock & quote & comma & sCdConn[pSock]["serial"]) \
            to me in kCdSrvLingerMs milliseconds
   end if
end cdSrvWrote

-- RFC 6455's opening handshake: the accept key is the base64 of the SHA-1
-- of the client's key joined to the protocol's own constant. The boot
-- self-check holds it to the RFC's own example.
function cdSrvAcceptKey pKey
   return base64Encode(sha1Digest(pKey & kCdWsGuid))
end cdSrvAcceptKey

command cdSrvUpgrade pSock, pKey
   local tReply
   put "HTTP/1.1 101 Switching Protocols" & crlf & "Upgrade: websocket" & crlf \
         & "Connection: Upgrade" & crlf & "Sec-WebSocket-Accept: " & cdSrvAcceptKey(pKey) \
         & crlf & crlf into tReply
   put "ws" into sCdConn[pSock]["kind"]
   put empty into sCdConn[pSock]["fragOpcode"]
   put empty into sCdConn[pSock]["frag"]
   cdSrvWrite pSock, tReply
   cdLog "server: " & sCdConn[pSock]["path"] & " became a WebSocket (" & pSock & ")"
   cdSrvReadFrame pSock
end cdSrvUpgrade

-- A frame is read in three steps: two head bytes; then the extended length
-- (if any) and the four-byte mask every client frame carries; then the
-- payload.
command cdSrvReadFrame pSock
   put "frame" into sCdConn[pSock]["stage"]
   read from socket pSock for 2 with message "cdSrvFrameHead"
end cdSrvReadFrame

on cdSrvFrameHead pSock, pData
   local tB1, tB2, tLen7, tNeed
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvFrameHead
   end if
   -- a short read is a socket the engine has closed (cdSrvDrop)
   if the number of bytes of pData < 2 then
      cdSrvDrop pSock
      exit cdSrvFrameHead
   end if
   put byteToNum(byte 1 of pData) into tB1
   put byteToNum(byte 2 of pData) into tB2
   put tB1 div 128 into sCdConn[pSock]["fin"]
   put tB1 mod 16 into sCdConn[pSock]["opcode"]
   if (tB1 div 16) mod 8 is not 0 then
      cdSrvCloseWs pSock, 1002, "reserved bits set"
      exit cdSrvFrameHead
   end if
   if tB2 div 128 is not 1 then
      cdSrvCloseWs pSock, 1002, "a client's frames must be masked"
      exit cdSrvFrameHead
   end if
   put tB2 mod 128 into tLen7
   if tLen7 is 127 then
      cdSrvCloseWs pSock, 1009, "message too big for this demo"
      exit cdSrvFrameHead
   end if
   put tLen7 into sCdConn[pSock]["len7"]
   if tLen7 is 126 then
      put 6 into tNeed
   else
      put 4 into tNeed
   end if
   read from socket pSock for tNeed with message "cdSrvFrameMask"
end cdSrvFrameHead

on cdSrvFrameMask pSock, pData
   local tNeed, tLen, tMask
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvFrameMask
   end if
   if sCdConn[pSock]["len7"] is 126 then
      put 6 into tNeed
   else
      put 4 into tNeed
   end if
   if the number of bytes of pData < tNeed then
      cdSrvDrop pSock
      exit cdSrvFrameMask
   end if
   if tNeed is 6 then
      put byteToNum(byte 1 of pData) * 256 + byteToNum(byte 2 of pData) into tLen
      put byte 3 to 6 of pData into tMask
   else
      put sCdConn[pSock]["len7"] into tLen
      put byte 1 to 4 of pData into tMask
   end if
   if tLen > kCdSrvMaxMessage then
      cdSrvCloseWs pSock, 1009, "message too big for this demo"
      exit cdSrvFrameMask
   end if
   put tMask into sCdConn[pSock]["mask"]
   put tLen into sCdConn[pSock]["len"]
   if tLen < 1 then
      cdSrvFrame pSock, empty
      exit cdSrvFrameMask
   end if
   read from socket pSock for tLen with message "cdSrvFramePayload"
end cdSrvFrameMask

on cdSrvFramePayload pSock, pData
   local tMask
   set the defaultStack to the short name of this stack
   if not cdSrvKnows(pSock) then
      exit cdSrvFramePayload
   end if
   if the number of bytes of pData < sCdConn[pSock]["len"] then
      cdSrvDrop pSock
      exit cdSrvFramePayload
   end if
   -- a chunk of an array element is taken from a local copy (holde-em H6)
   put sCdConn[pSock]["mask"] into tMask
   cdSrvFrame pSock, cdSrvUnmask(pData, tMask)
end cdSrvFramePayload

-- Each payload byte XOR the mask byte at its position mod 4.
function cdSrvUnmask pData, pMask
   local tKeys, tI, tOut, tByte
   repeat with tI = 0 to 3
      put byteToNum(byte (tI + 1) of pMask) into tKeys[tI]
   end repeat
   put 0 into tI
   repeat for each byte tByte in pData
      put numToByte(byteToNum(tByte) bitXor tKeys[tI mod 4]) after tOut
      add 1 to tI
   end repeat
   return tOut
end cdSrvUnmask

-- One whole frame. Text and binary come back as they came (a fragmented
-- message is gathered first and comes back whole); a ping gets its pong; a
-- close gets its close, and then the connection ends.
command cdSrvFrame pSock, pPayload
   local tOpcode, tFrag
   put sCdConn[pSock]["opcode"] into tOpcode
   if tOpcode is 8 then
      cdSrvSend pSock, 8, byte 1 to 2 of pPayload, true
      exit cdSrvFrame
   end if
   if tOpcode is 9 then
      cdSrvSend pSock, 10, pPayload, false
   else if tOpcode is 1 or tOpcode is 2 then
      if sCdConn[pSock]["fragOpcode"] is not empty then
         cdSrvCloseWs pSock, 1002, "a new message began inside a fragmented one"
         exit cdSrvFrame
      end if
      if sCdConn[pSock]["fin"] is 1 then
         cdSrvSend pSock, tOpcode, pPayload, false
      else
         put tOpcode into sCdConn[pSock]["fragOpcode"]
         put pPayload into sCdConn[pSock]["frag"]
      end if
   else if tOpcode is 0 then
      if sCdConn[pSock]["fragOpcode"] is empty then
         cdSrvCloseWs pSock, 1002, "a continuation with nothing to continue"
         exit cdSrvFrame
      end if
      put sCdConn[pSock]["frag"] into tFrag
      put pPayload after tFrag
      if the number of bytes of tFrag > kCdSrvMaxMessage then
         cdSrvCloseWs pSock, 1009, "message too big for this demo"
         exit cdSrvFrame
      end if
      if sCdConn[pSock]["fin"] is 1 then
         cdSrvSend pSock, sCdConn[pSock]["fragOpcode"], tFrag, false
         put empty into sCdConn[pSock]["fragOpcode"]
         put empty into sCdConn[pSock]["frag"]
      else
         put tFrag into sCdConn[pSock]["frag"]
      end if
   else if tOpcode is not 10 then
      cdSrvCloseWs pSock, 1002, "an opcode this server does not know"
      exit cdSrvFrame
   end if
   cdSrvReadFrame pSock
end cdSrvFrame

-- One whole unmasked frame (a server never masks): FIN and the opcode, the
-- length in 7 bits or in 7 + 16, then the payload. Nothing this server
-- sends is longer than kCdSrvMaxMessage, so the 64-bit form is never needed.
function cdSrvFrameBytes pOpcode, pPayload
   local tLen, tFrame
   put the number of bytes of pPayload into tLen
   put numToByte(128 + pOpcode) into tFrame
   if tLen < 126 then
      put numToByte(tLen) after tFrame
   else
      put numToByte(126) & numToByte(tLen div 256) & numToByte(tLen mod 256) after tFrame
   end if
   put pPayload after tFrame
   return tFrame
end cdSrvFrameBytes

-- Send one frame. pThenClose makes it the connection's last (a close
-- frame): nothing is sent after it (RFC 6455, section 5.5.1), so the
-- client's own close frame in reply is not answered again, and the client
-- ends the connection once it has read it (cdSrvWrote).
command cdSrvSend pSock, pOpcode, pPayload, pThenClose
   if sCdConn[pSock]["done"] is true then
      exit cdSrvSend
   end if
   if pThenClose is true then
      put true into sCdConn[pSock]["done"]
   end if
   cdSrvWrite pSock, cdSrvFrameBytes(pOpcode, pPayload)
end cdSrvSend

command cdSrvCloseWs pSock, pCode, pWhy
   cdLog "server: closing a WebSocket with " & pCode & " (" & pWhy & ")"
   cdSrvSend pSock, 8, numToByte(pCode div 256) & numToByte(pCode mod 256) & textEncode(pWhy, "UTF-8"), true
end cdSrvCloseWs

-- ---- the engine's socket messages: this stack's sockets only -----------------------
-- Each one asks a named function "was this socket the server's, and did it
-- handle it?" and passes every other socket on, so a library or another
-- stack in the message path still hears about its own.
on socketClosed pSock
   if not cdSrvSocketClosed(pSock) then
      pass socketClosed
   end if
end socketClosed

on socketError pSock, pErr
   if not cdSrvSocketError(pSock, pErr) then
      pass socketError
   end if
end socketError

on socketTimeout pSock
   if not cdSrvSocketTimeout(pSock) then
      pass socketTimeout
   end if
end socketTimeout

-- The engine has closed these sockets itself: forget them, never close by
-- the id (cdSrvDrop, engine note 6.20).
function cdSrvSocketClosed pSock
   if not cdSrvKnows(pSock) then
      return false
   end if
   cdSrvDrop pSock
   return true
end cdSrvSocketClosed

function cdSrvSocketError pSock, pErr
   if sCdSrvPort is not empty and pSock is sCdSrvPort then
      set the defaultStack to the short name of this stack
      cdLog "server: the listener failed: " & pErr
      cdSrvStop true
      return true
   end if
   if not cdSrvKnows(pSock) then
      return false
   end if
   set the defaultStack to the short name of this stack
   if sCdConn[pSock]["done"] is not true then
      cdLog "server: connection " & pSock & " failed: " & pErr
   end if
   cdSrvDrop pSock
   return true
end cdSrvSocketError

-- socketTimeout REPEATS while a read waits (engine note 6.1), so a quiet
-- WebSocket is not a broken one: only a connection that never sent its
-- request is closed.
function cdSrvSocketTimeout pSock
   if not cdSrvKnows(pSock) then
      return false
   end if
   if sCdConn[pSock]["stage"] is "head" then
      set the defaultStack to the short name of this stack
      cdLog "server: " & pSock & " sent no request; closed"
      cdSrvForget pSock
   end if
   return true
end cdSrvSocketTimeout

-- ---- small helpers -------------------------------------------------------------------
-- One line of the log, stamped with the seconds since the stack opened; the
-- log keeps its last kCdLogMax lines.
command cdLog pText
   local tN
   if there is no field "cdLog" then
      exit cdLog
   end if
   put format("[%.1fs] ", (the milliseconds - sCdT0) / 1000) & pText & return after field "cdLog"
   put the number of lines of field "cdLog" into tN
   if tN > kCdLogMax then
      delete line 1 to (tN - kCdLogMax) of field "cdLog"
   end if
   set the vScroll of field "cdLog" to the formattedHeight of field "cdLog"
end cdLog

-- Text equal character for character. The letter in front keeps both sides
-- off the number path, where "1e3" is "1000" (engine note 2.11).
function cdSame pA, pB
   set the caseSensitive to true
   return ("t" & pA) is ("t" & pB)
end cdSame

-- Bytes from hex pairs separated by spaces ("7f 9f 4d").
function cdBytes pPairs
   local tPair, tOut
   repeat for each word tPair in pPairs
      put numToByte(baseConvert(tPair, 16, 10)) after tOut
   end repeat
   return tOut
end cdBytes

-- The first pMax bytes of pData (all of them for 0 or empty) as lower-case
-- hex pairs separated by spaces.
function cdHex pData, pMax
   local tByte, tPair, tOut, tN
   put 0 into tN
   repeat for each byte tByte in pData
      add 1 to tN
      if pMax is an integer and pMax > 0 and tN > pMax then
         exit repeat
      end if
      put toLower(baseConvert(byteToNum(tByte), 10, 16)) into tPair
      if the number of chars of tPair < 2 then
         put "0" before tPair
      end if
      put tPair & space after tOut
   end repeat
   return char 1 to -2 of tOut
end cdHex

-- ---- the boot self-check ----------------------------------------------------------------
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

-- Every control this script names (DERIVED: tools/check-demo-control-lists.py
-- --write keeps this list and the count in the assertion below).
constant kCdScControls = "cdAbout,cdBarBg,cdBarFill,cdBig1,cdBig2,cdBig3,cdBig4,cdBy,cdCap1,cdCap2,cdCap3,cdCap4,cdConnInfo,cdFeed,cdGraphArea,cdGraphBg,cdGraphCap,cdGraphLine,cdLog,cdNotice,cdSceneClock,cdSceneName,cdScenesCap,cdSrvInfo,cdStage,cdStats,cdWsPill,cdWsPillBg,uiStatus"

-- What a fresh window can say about itself without hosting, connecting or
-- binding anything: the controls, the boot state, the protocol this stack's
-- server speaks (against RFC 6455's own examples), the peer check, and the
-- curlxt surface it carries.
command cdScRun
   local tMissing, tVer, tV, tI, tN, tSock
   scBegin "cdLog"
   put scMissing(kCdScControls) into tMissing
   scAssert "all 29 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", (tMissing is empty)
   -- nothing runs yet: the first scene starts a moment after this block
   scAssert "no scene runs at boot (sCdScene is " & scShow(sCdScene) & ")", (sCdScene is 0)
   scAssert "no WebSocket is open at boot", (sCdSock is empty)
   scAssert "the echo server is not listening yet (the first scene starts it)", (sCdSrvPort is empty)
   scAssert "the echo server holds no connection at boot", (the number of lines of the keys of sCdConn is 0)
   -- RFC 6455, section 1.3 and section 5.7
   put cdSrvAcceptKey("dGhlIHNhbXBsZSBub25jZQ==") into tV
   scAssert "the handshake answer is RFC 6455's example (got " & scShow(tV) & ")", \
         cdSame(tV, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
   put cdSrvUnmask(cdBytes("7f 9f 4d 51 58"), cdBytes("37 fa 21 3d")) into tV
   scAssert "a masked frame unmasks to RFC 6455's example (got " & scShow(tV) & ")", cdSame(tV, "Hello")
   put cdHex(cdSrvFrameBytes(1, "Hello"), 0) into tV
   scAssert "the server's text frame is RFC 6455's example (got " & scShow(tV) & ")", \
         cdSame(tV, "81 05 48 65 6c 6c 6f")
   put empty into tV
   repeat with tI = 1 to 300
      put numToByte(tI mod 256) after tV
   end repeat
   put cdHex(cdSrvFrameBytes(2, tV), 4) into tV
   scAssert "a 300-byte message takes the 16-bit length (got " & scShow(tV) & ")", \
         cdSame(tV, "82 7e 01 2c")
   -- this machine only: a socket id read by its shape (engine note 6.2)
   scAssert "127.0.0.1:54321 is this machine", cdSrvIsLoopback(cdSrvHostOf("127.0.0.1:54321"))
   scAssert "::1:54321 is this machine", cdSrvIsLoopback(cdSrvHostOf("::1:54321"))
   scAssert "[::1]:54321 is this machine", cdSrvIsLoopback(cdSrvHostOf("[::1]:54321"))
   scAssert "192.168.1.20:54321 is refused", not cdSrvIsLoopback(cdSrvHostOf("192.168.1.20:54321"))
   scAssert "a bare 54321 is refused", not cdSrvIsLoopback(cdSrvHostOf("54321"))
   scAssert "a wait of 99999 ms is held to " & kCdSrvMaxWait, (cdSrvWaitOf("/tile/1?wait=99999") is kCdSrvMaxWait)
   -- An id the engine gives again is a new connection, and a timer set for
   -- the old one leaves it alone (engine note 6.20). The id is one no socket
   -- has: 7 is neither a Windows socket handle (a multiple of four) nor a
   -- client's port.
   put "127.0.0.1:7" into tSock
   put 41 into sCdConn[tSock]["serial"]
   put "ended" into sCdConn[tSock]["stage"]
   put true into sCdConn[tSock]["done"]
   cdSrvTakeId tSock
   put sCdConn[tSock]["serial"] into tV
   scAssert "an id the engine gives again is a new connection (engine note 6.20)", \
         (sCdConn[tSock]["stage"] is "head" and sCdConn[tSock]["done"] is false and tV is not 41)
   cdSrvReap tSock, 41
   scAssert "a late timer for the old connection leaves the new one alone", \
         (cdSrvKnows(tSock) and sCdConn[tSock]["serial"] is tV)
   cdSrvReap tSock, tV
   scAssert "a connection that outstays its last bytes is let go by its own timer", not cdSrvKnows(tSock)
   -- every label holds its line (cdLabel: Windows cut the tops off)
   put 0 into tN
   put empty into tV
   repeat with tI = 1 to the number of fields of this card
      if the uCdLabel of field tI of this card is true then
         add 1 to tN
         if not cdLabelFits(the short name of field tI of this card) then
            put the short name of field tI of this card & " " after tV
         end if
      end if
   end repeat
   scAssert "all " & tN & " labels hold their line: a fixed line height inside the field (too tall: " \
         & scShow(word 1 to -1 of tV) & ")", (tN > 0 and tV is empty)
   -- the window's title bar is on a screen (cdPlaceWindow)
   put the working screenRects into tV
   if tV is empty then
      scSkip "the window's place on the screen", "this engine has no screen"
   else
      scAssert "the window's title bar is on a screen (the window is at " & the rect of this stack & ")", \
            cdTitleBarOnScreen(tV)
   end if
   if sCdHaveCurl is not "true" then
      scSkip "curlxt and the two layers this stack carries", scShow(sCdInitError)
   else
      put cuLibraryVersion() into tVer
      scAssert "cuLibraryVersion names libcurl (" & tVer & ")", \
            (tVer begins with "curlxt ABI " and tVer contains "libcurl/")
      scAssert "handle 0 is no request (cuInfo answers -1)", (cuInfo(0, "result") is -1)
      scAssert "no request is waiting at boot", (cuWaitingCount() is 0)
      put tsNetVersion() into tV
      scAssert "tsNetVersion is 1.4.5 (got " & scShow(tV) & ")", (tV is "1.4.5")
      put tsNetGetStatus("no-such-connection") into tV
      scAssert "an unknown tsNet connection answers tsneterr: (got " & scShow(tV) & ")", \
            (tV begins with "tsneterr:")
      if cdHasWs() then
         scAssert "no WebSocket is watched at boot", (cuWsWatchedCount() is 0)
      else
         scSkip "the WebSocket scenes", "this curlxt is ABI " & scShow(sCdAbi) & "; they need ABI 2"
      end if
   end if
   scArmProbe
end cdScRun
