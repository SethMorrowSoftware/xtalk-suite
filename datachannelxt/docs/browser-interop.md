# Browser interop: the browser leg of runbook row 40

DataChannelXT's first claim is that its channels are ordinary WebRTC data channels, so the
far side can be a browser. Every engine record in `CLAUDE.md`'s ledger is OXT talking to
OXT. This page is the procedure for the leg that tests the browser claim: one OXT stack and
one browser tab on the same machine, copy/paste signaling, three things to see. It is the
browser half of the suite runbook's row 40 (session S1 plus a browser). The row's other
half, a call across two networks, is a separate leg with its own green.

## The two halves

| File | Role |
|---|---|
| `tests/browser-peer.html` | The browser side. A static, self-contained page (no external script, style or font) that you open from disk. Plain JavaScript `RTCPeerConnection`. It runs the row-40 checks and has a "Copy results" button. |
| `tests/datachannel-browser-peer.livecodescript` | The OXT side. A stack script that builds no window. You drive it by typing commands in the message box, and it reports there. It runs its own `dcPoll` loop, so no helpers stack is needed. It checks the reverse direction. |

**Signaling** uses one blob each way. It is the non-trickle shape from `docs/getting-started.md`
section 3. Each side waits for ICE gathering to complete, so its local description then
contains every candidate. It ships that description as

```
<type> LF <sdp>          offer\nv=0\r\no=- ...     (OXT: dcLocalDescriptionType & LF & dcLocalDescription)
```

This is the signaling body of `examples/datachannel-dht-chat.livecodescript` without its
nonce. The DHT chat needs the nonce to pair an answer with its offer, because DHT items
linger for hours. A live paste has no stale items, so it needs no pairing. Both sides accept
CRLF or bare LF: libdatachannel trims every SDP line, and the page rebuilds its CRLFs. A blob
without a type line (one that starts at `v=0`) is read as the type that side is waiting for.

**The payloads** are fixed, so each side can check exact content as well as kind:

| Direction | Text | Binary |
|---|---|---|
| OXT to browser (`dcSendText`, `dcSendData`) | `hello from OXT` | `00 01 7f 80 fe ff` |
| browser to OXT ("Send test pair") | `hello from the browser` | `ff fe 80 7f 01 00` |

Each binary payload contains a NUL and bytes with the high bit set, so it could not survive
a text path. If a message arrives as the wrong kind (text as binary, or binary as text), it
is a **FAIL**, and a later good message does not clear it. If a message arrives as the right
kind with the wrong content, it shows **CHECK**, which is not a pass. Either one means the
two files have drifted apart or something mangled the bytes.

## Procedure (S1 + a browser; about 15 minutes)

Before you start: install DataChannelXT from the current tree (runbook section 2). You need
a current Chrome, Edge or Firefox on the same machine. Quit and relaunch OXT. Make sure no
other DataChannelXT stack is open: the event queue is shared by the whole process, so a
second poller would steal events.

1. **OXT side.** Choose `File > New Mainstack`, then `Object > Stack Script`. Paste ALL of
   `tests/datachannel-browser-peer.livecodescript`, click Apply, then **close the stack and
   reopen it** (the ritual in runbook section 3.1). Opening the file itself from disk builds
   nothing (the suite's engine note 5.5). The message box should list six `bp` commands.
2. **Browser side.** Open `tests/browser-peer.html` from disk. Its status line should say
   `idle`.
3. In the message box, type **`bpOffer`**. Within a few seconds it prints
   `the offer is on the clipboard (N candidates, ...)`.
4. In the page, paste into box 1 and press **Apply remote blob**. When box 2 fills and the
   status line says the answer is ready, press **Copy blob**.
5. In the message box, type **`bpAccept`**. It prints the value `dcSetRemoteDescription`
   returned, then `CHANNEL OPEN - sending the text and the bytes`, then the value each send
   returned (`0` is success). Last, it prints the selected candidate pair.
6. **The page's checks** should read PASS for all three:
   - the data channel opens;
   - `dcSendText` arrives as a string (`hello from OXT`);
   - `dcSendData` arrives as an ArrayBuffer (`00 01 7f 80 fe ff`).
7. In the page, press **Send test pair**. The message box should print a `RECV text` line
   and a `RECV payload` line with the page's values.
8. Type **`bpReport`** in the message box. It prints the OXT record and puts it on the
   clipboard with the log; paste it into your pass notes. Then press **Copy results** in the
   page and paste that record too.
9. *(Optional: the other direction.)* Run **`bpStop`** in OXT and press **Reset** in the
   page. In the page, press **Or: make an offer here** and copy box 2. In the message box,
   type **`bpAnswer`**; it puts OXT's answer on the clipboard. Paste that answer into the
   page's box 1 and press Apply. The same checks apply, plus a
   `incoming channel ... label browser-interop` line in the message box.
10. Run **`bpStop`**, or close the stack (`closeStack` calls `dcCleanup`).

**Green:** both records end without `RUN NOT FINISHED`. The page shows three PASS lines. The
OXT report shows `PASS  the channel opened`, `dcSendText 0`, `dcSendData 0`,
`PASS  the browser's string arrived as text` and
`PASS  the browser's ArrayBuffer arrived as a payload, byte-exact`.

**Record:** the browser and its version (the page's record names the user agent), the OS,
the engine version (`bpReport` prints `the version` and `the platform`), and which
DataChannelXT library loaded. Record the selected pair from both sides and the page's
`binaryType default` line. Add the dated result to `CLAUDE.md`'s evidence ledger and update
its Status. Close the browser half of runbook row 40 in the runbook.

## What to expect on one machine

Browsers normally hide their host addresses behind mDNS names. Headless Chromium did in
the 2026-09-24 run below: its candidates read `<uuid>.local ... typ host`. The shim's
selected remote candidate was then `prflx`: the shim learned the browser's address from the
browser's connectivity checks, not from that host candidate. So on one machine, a `prflx`
remote on the OXT side is normal. It says nothing about NAT traversal, which is the other
half of row 40 (`srflx` or `prflx` across two networks).

If step 5 prints `NOT OPEN after 30000 ms`, first try the other browser. Then open
`chrome://webrtc-internals` (or Firefox's `about:webrtc`) during a retry to see which
candidate pairs failed. A local firewall that blocks UDP between processes stops both
halves, the same way trap 5.5 in the runbook stops the suite's loopbacks. If the page reports
`clipboard refused`, select the text in box 2 and copy it by hand. If the message box says
`REFUSED`, it names what it found on the clipboard instead of a blob.

## What has run, and what has not

**Headless, 2026-09-24, no engine.** Playwright drove headless Chromium 141.0.7390.37 on
x86_64 Linux in four scenarios:

- two copies of the page signaled each other through the same blobs, in both roles;
- the page's FAIL rules were exercised with a text sent as binary and bytes sent as a
  string, and both FAILs held after the correct messages followed;
- the page ran against the committed `src/code/x86_64-linux/datachannelxt.so` (libdatachannel
  v0.24.5), driven through its `dcx_*` C ABI by a scratch ctypes driver, once with the shim
  offering (as `bpOffer`) and once with the shim answering (as `bpAnswer`). The driver
  stripped CRs from the page's blob, as `bpReadBlob` does.

Against the shim, `dcx_send_text` arrived as a string and `dcx_send_data` arrived as an
ArrayBuffer, byte-exact, with `binaryType` defaulting to `"arraybuffer"` in that browser.
The page's pair arrived in the shim as a TEXT event and a PAYLOAD event, byte-exact. The
selected pair was a host candidate on the shim's side and `prflx` on the browser's side.

**What that proves:** the page's JavaScript, the blob format in both directions, and that
the shipped library's text and binary sends reach a browser as a string and an ArrayBuffer.

**What it does not prove:** the `.lcb` binding's marshalling (`dcSendText`'s UTF-8 encode
and NUL refusal, and `dcSendData`'s `Data` to pointer), the OXT script, and any engine.
`tests/datachannel-browser-peer.livecodescript` is verified statically; needs an OXT pass.
That pass is the engine leg the work plan lists under datachannelxt.
