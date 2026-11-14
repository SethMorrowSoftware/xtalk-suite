script "curlHelpers"

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
-- Script-locals carry the member stem (sCu...): two libraries sharing a
-- column-0 name cannot be co-embedded (suite engine note 1.6, enetxt
-- gotcha 5); the suite's check-cross-library-names.py holds them disjoint.
--
-- Verified statically; needs an OXT pass.

constant kCuDefaultInterval = 20
constant kCuIntOptions = "timeout,connectTimeout,followRedirects,maxRedirects,verifyPeer,verifyHost,lowSpeedLimit,lowSpeedTime,useSsl,ftpPassive,maxBodyBytes,httpVersion,dnsCacheSeconds,createDirs"
constant kCuListOptions = "mailRcpt,quote,postQuote"

local sCuWaiters        -- array: request handle -> target & tab & message
local sCuPolling        -- "true" while the timer loop is armed
local sCuPollInterval   -- milliseconds between pump passes
local sCuPollNote       -- first pump failure since the last clear, else empty
local sCuHolds          -- cuInitialize holds this library took
local sCuMakeError      -- why the last cuRequestSync/Async returned 0

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
-- each watched one that ended, and re-arms only while someone is waiting.
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
   if cuWaitingCount() is 0 then
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
