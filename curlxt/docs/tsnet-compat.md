# The tsNet calls

`src/tsnet.livecodescript` (stack `tsNetCompat`) answers the calls of LiveCode's tsNet
external by name, built on curlxt. Put `curlHelpers` and then `tsNetCompat` in use, and a
script written for tsNet runs as written.

It was written from the PUBLIC tsNet dictionary entries (docs.livecode.com, read
2026-11-14) and nothing else. Where an entry could not be read, the table says so, and the
behaviour there is our best reading rather than tsNet's documented one.

## The calls

| Call | Kind | Source of the signature |
|---|---|---|
| `tsNetInit` | command | dictionary |
| `tsNetClose` | command | dictionary |
| `tsNetVersion()` | function | dictionary; answers `1.4.5`, the last tsNet LiveCode 9 shipped |
| `tsNetSetTimeouts pDnsCacheTimeout, pRequestTimeoutMS, pConnectTimeoutMS, pAcceptTimeoutMS, pLowSpeedTime, pLowSpeedLimit` | command | dictionary |
| `tsNetSetStatusCallback pCallback` | command | dictionary |
| `tsNetGet(pID, pURL, pHeaders, pCallback, [pSettings])` | function | dictionary |
| `tsNetGetSync(pURL, xHeaders, rOutHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetPost(pID, pURL, pHeaders, pPostData, pCallback, [pSettings])` | function | dictionary |
| `tsNetPostSync(pURL, xHeaders, pPostData, rOutHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetHead(pID, pURL, pHeaders, pCallback, [pSettings])` | function | dictionary |
| `tsNetHeadSync(pURL, xHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetCustom(pID, pURL, pRequest, pHeaders, pCallback, [pSettings])` | function | dictionary |
| `tsNetCustomSync(pURL, pRequest, xHeaders, rOutHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetGetFile(pID, pFile, pURL, pHeaders, pCallback, [pSettings])` | function | dictionary |
| `tsNetGetFileSync(pFile, pURL, xHeaders, rOutHeaders, rBytes, [pSettings])` | function | dictionary |
| `tsNetUpload(pID, pURL, pHeaders, pCallback, pData, [pSettings])` | function | dictionary (the data comes AFTER the callback) |
| `tsNetUploadSync(pURL, xHeaders, pData, rOutHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetUploadFile(pID, pFile, pURL, pHeaders, pCallback, [pSettings])` | function | dictionary |
| `tsNetUploadFileSync(pFile, pURL, xHeaders, rOutHeaders, rResult, rBytes, [pSettings])` | function | dictionary |
| `tsNetSmtp(pID, pURL, pFrom, pRcpt, pCallback, pData, [pSettings])` | function | dictionary (the data comes AFTER the callback) |
| `tsNetSmtpSync(pURL, pFrom, pRcpt, pData, rOutHeaders, rBytes, [pSettings])` | function | dictionary, and OXT-Beyond's own mime library calls it this way |
| `tsNetGetStatus(pID)` | function | dictionary |
| `tsNetRetrError(pID)` | function | dictionary |
| `tsNetCloseConn pID` | command | dictionary |
| `tsNetRetrieveData(pID, rError)` | function | entry not readable; our reading |
| `tsNetHeaders(pID)` | function | entry not readable; our reading |

Every async call returns empty when the transfer started, or text starting `tsneterr:`. Its
callback gets four parameters: the connection ID, the server's status code, the bytes
transferred (sent, for an upload or SMTP), and the curl result (0 = success).

## Where it may differ from tsNet

- **Error wording.** Every `tsneterr:` message is our own words. A script that tests
  `begins with "tsneterr:"`, as the dictionary says to, behaves the same.
- **pSettings.** Honoured: `username`, `password`, `user_agent`, `referer`, `use_ssl`,
  `try_ssl`, `use_ssl_control`, `ssh_private_key`, `ssh_public_key`, `ssh_passphrase`,
  `pre_commands`, `post_commands` (one command per line), `max_file_size`, and `no_verify`.
  Every other tsNet key is ignored, not refused.
- **Redirects** are followed (HTTP 3xx). A 404 or 500 is a finished transfer: the data is
  the server's page and rResult its code, not `tsneterr:`.
- **tsNetGetStatus** answers five words; the first is `loading`, `completed`, `error`,
  `timeout` or `cancelled`. tsNet's own status words are not all documented.
- **A connection's data** stays until `tsNetCloseConn`, until its ID is used for a new
  transfer, or until `tsNetClose`. A finished ID may be reused at once.
- **A cancelled transfer** reports curl result 42 (curl's "aborted"). `tsNetCloseConn` on
  a running transfer stops it without a callback.
- **tsNetCustom** with an ftp, ftps or sftp URL sends the command and transfers nothing.
- **pAcceptTimeoutMS** of `tsNetSetTimeouts` is accepted and unused: curlxt uses passive
  FTP.
- **Callbacks go to the object that received the message** being handled when the transfer
  started (`the target`), and pass up its message path from there.
- **Not provided:** the `tsNetLibURL` stack. tsNet could take over `get url` from libURL;
  this library does not, so libURL keeps handling URL keywords exactly as before.

## How it is tested

`tools/check-script-vectors.py` runs the shipped file on the family's headless interpreter,
with every `cu*` handler bound to the BUILT curlxt library, against an HTTP server and an
SMTP server it runs on 127.0.0.1: every sync and async call above, callbacks and their
parameters, settings, timeouts, status messages, file transfers, errors and cleanup.
`tools/test-script-vectors.py` breaks the layer six ways and requires the gate to catch each.
Verified statically + headless run over the native library; needs an OXT pass.
