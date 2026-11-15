script "tsNetCompat"

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
-- Verified statically; needs an OXT pass.

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
