# curlxt API reference

Every public handler, from the doc blocks in the source (the IDE dictionary reads the same
blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Every handler of the binding, and the helpers' requests and WebSocket calls, run on
OXT-Beyond's headless Linux server engine in the native lane (`tests/engine-selftest.lc`;
README, Status); the rest, the IDE and the other platforms need an OXT pass.

## The binding: src/curl.lcb

### `cuInitialize`

`cuInitialize() returns Integer`

Initialize curlxt before any other call.

Returns: The number of holds now taken (1 or more), or a negative error.

### `cuCleanup`

`cuCleanup() returns Integer`

Give back one hold taken by <cuInitialize>.

Returns: The number of holds still taken; 0 means curlxt is shut down.

### `cuLibraryVersion`

`cuLibraryVersion() returns String`

The versions of curlxt's ABI, libcurl and the libraries it uses.

Returns: A line such as "curlxt ABI 2; libcurl/8.22.0 OpenSSL/3.5.9 libssh2/1.11.1".

### `cuLastError`

`cuLastError() returns String`

The last error curlxt recorded, as text.

Returns: The text of the last error, or empty.

### `cuClearError`

`cuClearError()`

Clear the text <cuLastError> returns.

### `cuRequestNew`

`cuRequestNew(in pMethod as String, in pURL as String) returns Integer`

Make a new request.

- pMethod: GET, HEAD, POST, PUT, DELETE, or any other method name. PUT (or UPLOAD) sends the body as an upload, which is how FTP and SFTP files are stored and how SMTP sends a message.
- pURL: The URL, such as https://example.com/ or sftp://host/path/file.

Returns: A request handle, or 0 if it could not be made (see <cuLastError>).

### `cuSetHeader`

`cuSetHeader(in pRequest as Integer, in pLine as String) returns Integer`

Add one request header.

- pRequest: A handle from <cuRequestNew>.
- pLine: One header line, such as "Accept: application/json".

Returns: 0, or a negative error.

### `cuSetOption`

`cuSetOption(in pRequest as Integer, in pName as String, in pValue as Integer) returns Integer`

Set a number option of a request.

- pRequest: A handle from <cuRequestNew>.
- pName: timeout (ms, whole transfer), connectTimeout (ms), followRedirects (0 or 1), maxRedirects, verifyPeer (0 or 1), verifyHost (0 or 1), lowSpeedLimit (bytes a second), lowSpeedTime (seconds), useSsl (0 none, 1 try, 2 control, 3 all), ftpPassive (0 or 1), maxBodyBytes (0 = no cap), httpVersion (0 default, 1 is 1.0, 2 is 1.1), dnsCacheSeconds, createDirs (0 or 1), wsCloseTimeout (ms a WebSocket waits for the other side to answer a close; 5000 unless set, 0 = no limit).
- pValue: The value.

Returns: 0, or a negative error (an unknown name included).

### `cuSetTextOption`

`cuSetTextOption(in pRequest as Integer, in pName as String, in pValue as String) returns Integer`

Set a text option of a request.

- pRequest: A handle from <cuRequestNew>.
- pName: username, password, proxy, caFile, outputFile (download straight to this file), inputFile (upload straight from this file), mailFrom, mailRcpt (adds one recipient), userAgent, sshPublicKey, sshPrivateKey, keyPassword, quote and postQuote (each adds one FTP or SFTP command, run before or after the transfer), proxyUserPassword, referer, acceptEncoding.
- pValue: The value.

Returns: 0, or a negative error (an unknown name included).

### `cuSetBody`

`cuSetBody(in pRequest as Integer, in pData as Data) returns Integer`

Set the body a request sends.

- pRequest: A handle from <cuRequestNew>.
- pData: The bytes to send: the POST body, the PUT or upload content, or a whole mail message for SMTP.

Returns: 0, or a negative error.

### `cuStart`

`cuStart(in pRequest as Integer) returns Integer`

Start a request.

- pRequest: A handle from <cuRequestNew>.

Returns: 0, or a negative error (an output or input file that cannot be opened is refused here).

### `cuCancel`

`cuCancel(in pRequest as Integer) returns Integer`

Stop a request.

- pRequest: A handle from <cuRequestNew>.

Returns: 0, or a negative error.

### `cuFree`

`cuFree(in pRequest as Integer) returns Integer`

Release a request and everything it holds.

- pRequest: A handle from <cuRequestNew>.

Returns: 0, or a negative error. After this the handle is stale.

### `cuPoll`

`cuPoll() returns String`

Move every running request along, and list those that ended.

Returns: A comma-separated list of the request handles that have ended since the last call, or empty. Each is listed once.

### `cuWait`

`cuWait(in pRequest as Integer, in pTimeoutMs as Integer) returns Integer`

Wait for one request to end.

- pRequest: A started request.
- pTimeoutMs: The longest to wait, in milliseconds; -1 waits for the request's own timeouts alone.

Returns: 1 when it ended, 0 when the wait ran out (it keeps running, and <cuPoll> reports it later), or a negative error.

### `cuInfo`

`cuInfo(in pRequest as Integer, in pName as String) returns Number`

A number about a request.

- pRequest: A request handle.
- pName: state (0 new, 1 running, 2 ended), result (0 = success, a libcurl error number, 1000 = cancelled, -1 while running), responseCode, bytesDown, bytesUp, lengthDown and lengthUp (-1 = not known), totalTime (seconds), redirectCount, bodySize, cancelled (0 or 1). For a WebSocket also wsState (1 connecting, 2 open, 3 closing, 4 closed; 0 = not a WebSocket), wsMessages (messages waiting to be read), wsNextType (1 text, 2 binary, 0 = none waiting), wsNextSize (bytes), wsCloseCode, wsQueuedBytes (sent by script, not yet on the wire), wsPongs (pongs received).

Returns: The number, or -1 for a stale handle or an unknown name.

### `cuText`

`cuText(in pRequest as Integer, in pName as String) returns String`

A piece of text about a request.

- pRequest: A request handle.
- pName: headers (the final response's header block), error, effectiveUrl, contentType, method, wsCloseReason (the reason a WebSocket's close gave).

Returns: The text, decoded from UTF-8, or empty.

### `cuTextData`

`cuTextData(in pRequest as Integer, in pName as String) returns Data`

A piece of text about a request, as its raw bytes.

- pRequest: A handle from <cuRequestNew>.
- pName: The field name, as for <cuText>.

### `cuBody`

`cuBody(in pRequest as Integer) returns Data`

The response body a request received.

- pRequest: A handle from <cuRequestNew>.

Returns: The bytes, or empty. Reading the body does not release it; <cuFree> does. A request with an outputFile holds no body.

### `cuLiveCount`

`cuLiveCount() returns Integer`

How many request handles are live.

Returns: The count of requests made and not yet freed.

### `cuWsNew`

`cuWsNew(in pURL as String) returns Integer`

Make a new WebSocket.

- pURL: The address, starting with ws:// or wss:// (wss is the secure kind).

Returns: A socket handle, or 0 if it could not be made (see <cuLastError>).

### `cuWsSendText`

`cuWsSendText(in pSocket as Integer, in pText as String) returns Integer`

Send a text message on a WebSocket.

- pSocket: An open socket from <cuWsNew>.
- pText: The text. It is sent as UTF-8.

Returns: 0, or a negative error: -4 when the socket is not open, or when the other side has stopped reading and too much is already waiting.

### `cuWsSendData`

`cuWsSendData(in pSocket as Integer, in pData as Data) returns Integer`

Send a binary message on a WebSocket.

- pSocket: An open socket from <cuWsNew>.
- pData: The bytes.

Returns: 0, or a negative error, as for <cuWsSendText>.

### `cuWsPing`

`cuWsPing(in pSocket as Integer, in pData as Data) returns Integer`

Send a ping on a WebSocket, to check the other side is there.

- pSocket: An open socket from <cuWsNew>.
- pData: Up to 125 bytes to send with it, or empty.

Returns: 0, or a negative error.

### `cuWsClose`

`cuWsClose(in pSocket as Integer, in pCode as Integer, in pReason as String) returns Integer`

Close a WebSocket politely.

- pSocket: A socket from <cuWsNew>.
- pCode: The close code: 1000 for a normal close, 1001, a code of your own from 3000 to 4999, or 0 for none.
- pReason: A short reason (up to 123 bytes), or empty.

Returns: 0, or a negative error.

### `cuWsRead`

`cuWsRead(in pSocket as Integer) returns Data`

Take the next message a WebSocket received, as bytes.

- pSocket: A socket from <cuWsNew>.

Returns: The bytes of the oldest waiting message, or empty.

### `cuWsReadText`

`cuWsReadText(in pSocket as Integer) returns String`

Take the next message a WebSocket received, as text.

- pSocket: A socket from <cuWsNew>.

Returns: The oldest waiting message, decoded from UTF-8, or empty.

### `cuWsPoll`

`cuWsPoll() returns Integer`

Move every WebSocket (and every request) along.

Returns: How many received messages are waiting to be read, over every socket, or a negative error.

### `cuWsWait`

`cuWsWait(in pSocket as Integer, in pTimeoutMs as Integer) returns Integer`

Wait until something happens on a WebSocket.

- pSocket: A started socket from <cuWsNew>.
- pTimeoutMs: The longest to wait, in milliseconds; -1 waits without limit.

Returns: 1 when a message is waiting, the socket has closed, or a connecting socket has opened; 0 when the wait ran out; or a negative error.

## The helpers: src/curl-helpers.livecodescript

### `cuHelpersInit`

`cuHelpersInit`

Take one curlxt hold for this library, if it has none.

Returns: Empty, or the error text when curlxt could not start.

### `cuHelpersRelease`

`cuHelpersRelease`

Give back the curlxt hold this library took.

### `cuApplyRequest`

`cuApplyRequest pRequest, pHeaders, pBody, pOptions`

Apply headers, a body and options to a request that has not started.

- pRequest: A handle from <cuRequestNew>.
- pHeaders: Header lines, one per line, or empty.
- pBody: The bytes to send, or empty.
- pOptions: An array of option name to value (see <cuSetOption> and <cuSetTextOption>); mailRcpt, quote and postQuote take one value per line.

Returns: Empty, or the first error as text.

### `cuHelpersError`

`cuHelpersError`

Why the last <cuRequestSync> or <cuRequestAsync> returned 0.

Returns: The reason as text, or empty after a request that was made.

### `cuRequestSync`

`cuRequestSync pMethod, pURL, pHeaders, pBody, pOptions, pTimeoutMs`

Make a request and wait for its answer.

- pMethod: GET, HEAD, POST, PUT, DELETE, or another method.
- pURL: The URL.
- pHeaders: Header lines, or empty.
- pBody: The bytes to send, or empty.
- pOptions: An array of options, or empty.
- pTimeoutMs: The longest to wait; empty or -1 waits for the request's own timeouts.

Returns: The handle of the ENDED request, or 0 with the reason in <cuHelpersError>. Read it with <cuResponse>, then <cuFree> it.

### `cuRequestAsync`

`cuRequestAsync pMethod, pURL, pHeaders, pBody, pOptions, pTarget, pMessage`

Make a request in the background, and get a message when it ends.

- pMethod: GET, HEAD, POST, PUT, DELETE, or another method.
- pURL: The URL.
- pHeaders: Header lines, or empty.
- pBody: The bytes to send, or empty.
- pOptions: An array of options, or empty.
- pTarget: The object to send the message to; empty means this card.
- pMessage: The message, sent with the request handle as its parameter.

Returns: The request handle, or 0 with the reason in <cuHelpersError>.

### `cuWatch`

`cuWatch pRequest, pTarget, pMessage`

Send a message when a started request ends.

- pRequest: A request started with <cuStart>.
- pTarget: The object to send the message to; empty means this card.
- pMessage: The message, sent with the request handle as its parameter.

### `cuUnwatch`

`cuUnwatch pRequest`

Stop waiting for a request's message.

- pRequest: A handle from <cuRequestNew>.

### `cuSetPollInterval`

`cuSetPollInterval pIntervalMs`

Set how often the background timer runs.

- pIntervalMs: Milliseconds between passes; 20 is the default.

### `cuWaitingCount`

`cuWaitingCount`

How many background requests are waiting to report.

Returns: A count.

### `cuPollLastError`

`cuPollLastError`

The first background-timer failure since the last clear.

Returns: Empty while healthy.

### `cuPollClearError`

`cuPollClearError`

Forget the failure <cuPollLastError> reports.

### `cuResponse`

`cuResponse pRequest`

Everything about an ended request, as an array.

- pRequest: A request handle.

Returns: An array with the keys ok (true when the transfer itself worked, whatever the server answered), result (0 = success, a libcurl error number, or 1000 = cancelled), responseCode, error, headers, body, bytesDown, bytesUp, contentType, effectiveUrl and totalTime.

### `cuWsOpen`

`cuWsOpen pURL, pHeaders, pOptions, pTarget, pMessage`

Open a WebSocket in the background, and get a message for each thing that happens on it.

- pURL: The address, starting with ws:// or wss://.
- pHeaders: Header lines for the opening request, or empty (a line such as "Sec-WebSocket-Protocol: chat" asks for a subprotocol).
- pOptions: An array of options, or empty (see <cuSetOption> and <cuSetTextOption>).
- pTarget: The object to send the message to; empty means this card.
- pMessage: The message. It is sent with three parameters: the socket handle, what happened, and a value.

Returns: The socket handle, or 0 with the reason in <cuHelpersError>.

### `cuWsOpenSync`

`cuWsOpenSync pURL, pHeaders, pOptions, pTimeoutMs`

Open a WebSocket and wait until it is connected.

- pURL: The address, starting with ws:// or wss://.
- pHeaders: Header lines for the opening request, or empty.
- pOptions: An array of options, or empty.
- pTimeoutMs: The longest to wait; empty or -1 waits for the socket's own timeouts.

Returns: The handle of the OPEN socket, or 0 with the reason in <cuHelpersError>.

### `cuWsWatch`

`cuWsWatch pSocket, pTarget, pMessage`

Send a message for each thing that happens on a started WebSocket.

- pSocket: A socket made with <cuWsNew> and started with <cuStart>.
- pTarget: The object to send the message to; empty means this card.
- pMessage: The message, sent as <cuWsOpen> describes.

### `cuWsUnwatch`

`cuWsUnwatch pSocket`

Stop sending messages about a WebSocket.

- pSocket: A socket handle.

### `cuWsWatchedCount`

`cuWsWatchedCount`

How many WebSockets the background timer is watching.

Returns: A count.

## The tsNet calls

See [tsnet-compat.md](tsnet-compat.md).
