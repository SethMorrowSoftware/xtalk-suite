# CLAUDE.md - No Cloud Quick Share (`nocloud/`)

Guidance for Claude Code (claude.ai/code) and human contributors. **Inside `nocloud/`
this file wins over the suite root `CLAUDE.md`.** Paths are relative to this member's
root, which holds in the suite tree and in the repository this member is published
into. Engine BEHAVIOUR lives in the suite's
[`docs/OXT-ENGINE-NOTES.md`](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/OXT-ENGINE-NOTES.md):
cite it by note number, and keep only this app's own traps here.

## 1. What this is

**No Cloud Quick Share** is peer-to-peer file sharing with no server, no account and no
size limit: a shipped APP (not an extension), one OpenXTalk stack script plus a sample
web app. Three share paths: **Share code** (BitTorrent over the DHT; the code is the
info-hash; your IP is visible to peers), **Private / Tor** (an onion stream; both IPs
hidden; no torrent) and **Web link** (any browser). A passphrase adds end-to-end
encryption. Read `docs/what-it-hides.md` before touching anything on the wire. It began
as a TorrentXT demo and was folded into the suite from its own repository on 2026-08-13.

```
src/     nocloudquickshare.livecodescript: the whole app (self-building UI, three
         transports, HTTP + Tor servers, LAN web editor, poll loop)
webapp/  the sample SPA to serve over a web link or Tor (docs/webapp.md)
site/    the product landing page: static files, no build step (site/README.md)
tools/   run-gates.sh (THE gate list), check-livecodescript.py (the suite's unified
         checker), check-script-vectors.py (execution gate) + test-script-vectors.py
tests/   fileserver_golden.py: Python mirrors of the pure helpers, pinned to vectors
docs/    what-it-hides, user-routes, webapp, building-a-standalone, http-server-deep-dive
         (the HTTP host's contracts), oxt-pass-checklist (the engine pass owed)
```

| Dependency | Library id | Handlers | Required? | Without it |
|---|---|---|---|---|
| TorrentXT | `org.openxtalk.library.torrent` | `bt*` | **required** | no session: nothing is shared or downloaded (gotcha 8) |
| SodiumXT | `org.openxtalk.library.sodium` | `sx*` | optional | no passphrase encryption, no LAN-editor password, no Tor path |
| OnionXT | none: carried in the script since 2026-08-24 | `ox*` | nothing to install | the Tor path also needs SodiumXT and a local tor daemon (system tor: control 9051 / SOCKS 9050; Tor Browser: 9151 / 9150) |
| libURL | - | `load URL` | optional | only the try-guarded public-IP lookup (web link) |
| JSON library | - | `JSONToArray` | optional | no `.qsroutes.json` routes (a standalone must tick it) |

OnionXT rides between the suite's `tools/sync-demo-embeds.py` sentinels. Only `ox*` is
carried, never `oxh*` (the app ships its own HTTP server). Never edit inside the
sentinels: change `../onionxt/src/onionxt.livecodescript` and re-run that tool.

## 2. Rules for working here

1. **Fail closed, probed once.** Each dependency is probed ONCE at startup into a script
   local; no guarded handler is called outside its guard or a `try`. `qsCanEncrypt()`
   sets `sCanEncrypt` by a guarded `sxSecretBox`/`sxSecretBoxOpen` round trip and gates
   every `sx*` call. `qsHasOnion()` sets `sHasOnion`, requires `sCanEncrypt`, then a
   guarded `oxVersion()`, and gates every `ox*` call. `sTorReady` / `qsOnionReadyNow()`
   (`oxIsReady()`, true only at 100% bootstrap) is RE-CHECKED at the moment of use. A
   missing piece gets a clear install message and every other feature keeps working.
2. **Never call an extension handler from an engine thread** (BitTorrent events are
   poll-drained by `btPoll` in `qsPollOnce` every 250 ms; OnionXT stream callbacks, the one
   supported exception, are marshalled onto the interpreter thread), and **payload never
   crosses the FFI into script** (the Tor path moves bytes through script only by
   fixed-slice streaming, one bounded frame per pump). Why: suite rules 1 and 3.
3. **Wrap every `sx*`/`ox*` call, clipboard read and file op in `try`**, and every `bt*`
   call that can meet an absent TorrentXT (gotcha 8). Why: one throw takes the stack down.
4. **Socket messages dispatch, they never swallow.** `socketError` / `socketClosed` /
   `socketTimeout` handle OUR clearweb sockets first (`sCwServed`), then ask the embedded
   OnionXT (`oxSocketError` / `oxSocketClosed` / `oxSocketTimeout`: "was that socket
   mine, and did I handle it?"), then `pass`. The suite's `sync-demo-embeds.py` drops
   OnionXT's thin wrappers via `DROP_HANDLERS`, keyed by the (app, library) pair. Why: a
   swallowing socket handler is a silent hang. The OnionXT branches need a live-Tor pass.
5. **Encryption is SodiumXT, never OXT's `encrypt using "aes-256-cbc"`.** Argon2id via
   `sxPwHash` (opslimit `"2"` + `sxPwMemInteractive()`); files via `sxEncryptFile`
   (`crypto_secretstream`; truncation detected); tokens and verifiers via `sxSecretBox`.
   KDF parameters must match on both ends: change both AND bump the wire marker. Why: a
   one-sided change breaks every transfer silently.
6. **Every wire format has a versioned marker:** `BTXQS1:` (encrypted share code),
   `BTXTOR1:` (Tor code), `BTXQSVERIFY` (passphrase authenticator), `BTXEDIT1` (editor
   login verifier); `BTXENC2:` is torrentxt's `torrent-dht-channels`. A new format gets a
   versioned prefix pinned in the golden, and old readers reject an unknown prefix
   cleanly. Verify the passphrase up front, before any ciphertext downloads.
7. **`qsEditSafePath` and `qsEditIsLocal` gate a path that WRITES TO DISK** and must be
   reachable only from the LAN. Change them with real care, in lockstep with their
   golden mirrors. Why: they are the editor's whole security boundary.
8. **Any generated-layout change bumps `kQsUiVersion`** (now `"ncqs-kit2-1"`), or a saved
   stack keeps its old controls. `kQsAppVersion` (`"1.0.0"`) is the release string (title
   bar, startup log, `/_qs/info` `version`); the `Server:` header carries no version.
9. **Carried blocks change in the suite, never here** (masters: the suite's
   `tools/ui-kit.livecodescript` and `tools/demo-selfcheck.livecodescript`, drift-gated).
   The kit's v2 card look was absorbed FROM this app, which adopted it on 2026-08-14:
   `qsLabel`/`qsGfx`/`qsPanel`/`qsCap`/`qsButton`/`qsMonoFont`/`qsCopyFlash*` became
   `uiWrap`/`uiGfx`/`uiPanel`/`uiCap`/`uiButton`/`uiMonoFont`/`uiCopyFlash*`; `qsField`/
   `qsList`/`qsHdr` are thin wrappers; the Tor chip is `uiPill` via `qsOnionPill`; the kit
   status line sits in the bottom-left strip; only the drop-zone palette and `kClrAccent`
   stay local. `uiFooter` is not carried: the honesty surfaces are the per-share
   `qsSharing` copy, `/_qs/transparency` and the header HONESTY block. `qsScRun` (the boot
   self-check) checks the 49 controls in `kQsScControls`.
10. **`tools/check-livecodescript.py` is the suite's unified checker**, byte-identical in
    every member (held by the suite's `tools/check-checker-drift.py`, fixture-tested by
    `tools/test-checker.py`). Never edit it here alone.
11. **Single-thread performance:** costs run interpreter ops, then FFI round trips, then
    redraws. One FFI round trip per poll (`btTorrentStatus` returns the whole Array);
    repaint at 4 Hz or less and only on change (`sLastXferRows`; dashboard 1 Hz), since a
    mid-drag repaint can make an OS drop fail; one clock read per pass. The HTTP servers
    stream one bounded slice per write completion (clearweb `kCwChunk` 256 KiB; Tor
    `kOnionChunk` 64 KiB paced by `kOnionPumpTick` 15 ms), each slice reopened, seeked,
    read and closed so concurrent downloads never share a cursor.
12. **Every pure-logic helper is mirrored AND driven.** (1) Keep its pure core separable
    from I/O. (2) Add a mirror named after it in `tests/fileserver_golden.py` and LIST IT
    in the docstring index, the one authoritative mirror list (hand-kept copies had
    drifted to 16, 13 and 33 entries by 2026-08-15). (3) Reproduce xTalk exactly:
    `item N` is 1-based and empty past the end; `is an integer` rejects decimals;
    `urlDecode` turns `+` into a space (`unquote_plus`); `the round of` rounds half AWAY
    from zero; one trailing item delimiter is ignored (suite engine note 2.2). (4) Write
    table-driven edge cases. (5) Get the golden green. (6) Add the same inputs to
    `tools/check-script-vectors.py`'s drive and get it green. (7) Spot-check a couple on
    the engine during the OXT pass. An all-I/O handler has nothing to mirror.
13. **New interpreter spellings go in riptide's shared runner**, with their engine rule
    (`../riptide/tools/check-demo-boot.py`: `DemoExpr` / `DemoInterp` /
    `install_engine_functions`; since 2026-09-11, when holde-em became their second
    writer). This gate keeps only its write interception (`class NcInterp`). Never edit
    `lcs-interp.py` from here.
14. **Honesty.** Claim only "verified statically; needs an OXT pass" for anything not
    observed on a running engine; never write "fixed the server hang" unless you watched
    it in the IDE. PR text separates what was OBSERVED in OXT from what was verified
    statically. The golden and the execution gate settle LOGIC, not parser behaviour.
15. **Definition of done:** `bash tools/run-gates.sh` passes; the suite gates pass
    (`tools/build-all.sh --gates` at the suite root); the checker was not edited here
    alone; new pure helpers are mirrored, indexed and driven; `kQsUiVersion` is bumped on
    any layout change; an OXT pass was done (paste into the stack script, close + reopen,
    exercise the change); new comments explain the why, densely. Work on a per-task
    branch, open a draft PR, and never push to `main` without permission.

## 3. Gotchas and traps

Gotchas 1-10 keep their numbers: the suite work plan cites gotcha 8.

1. **Pure ASCII only**, even in comments: a curly quote fails compilation (engine note 1.4).
2. **Reserved-word stem shadowing:** `tExt` = `text`, `sSort` = `sort`, `pPut` = `put`
   evaluate as keywords, silently. Use multi-word stems like `tSuffix` (engine note 1.5).
3. **Prefixes:** `t` local, `p` parameter, `s` script-local, `k` constant; public
   handlers are `qsPascalCase` (namespace `qs*`).
4. **Constants are literal and declared before first use** (lexical position; a forward
   reference is empty); the `kClr*` and protocol `k*` block is at the top (notes 1.2, 1.3).
5. **Declare every `local` at the top of a handler:** a nested one has broken
   whole-script compilation in this family.
6. **Commands report via `the result`; functions return:** `btAddMagnet` is a command
   (`put the result into tH`); `btTorrentStatus(tH)` is a function.
7. **`itemDelimiter` / `lineDelimiter` are global state:** set them right before use, as
   the code does before splitting a `BTXQS1:`/`BTXTOR1:` code (engine note 2.3).
8. **A `bt*` call outside a `try` with TorrentXT absent is an uncaught engine error.** With
   the library missing or ABI-skewed (recorded symptom: "can't find handler" on
   `btRp1Enable`), `btStartSession` raised out of `qsStart` AND `openStack` until
   2026-09-09: a built-but-dead window behind a raw engine dialog. It is guarded now, and
   the catch deliberately skips the session-refused branch, which opens with
   `btLastError()` and would throw again. Verified statically; the probe is
   `docs/oxt-pass-checklist.md` section 8.
9. **Engine and library callbacks are delayed handlers: pin the defaultStack at their
   entry** (engine note 5.3). Socket/URL `with message` handlers, the `socket*` messages
   and the callbacks handed to OnionXT have no defaultStack guarantee; eight here were
   pinned 2026-09-09, and the suite's `tools/check-timer-stack-pin.py` (fixture
   `tools/test-timer-stack-pin.py`) holds all three delivery classes.
10. **`and` / `or` evaluate BOTH operands**, so a type guard cannot share an expression
    with the comparison it guards (engine note 2.5). `qsHttpReqLength` and `qsHttpDate`
    were nested 2026-09-11; the port guards and row formatters keep the shape on values
    only ever compared. `X + 0` on a non-number is a hard engine error; none is written.
11. **A script recompile sends `openStack` but NOT `preOpenStack`**, so a UI built only in
    `preOpenStack` is missing (`Chunk: no such object` at `field "qsXfers"`). Now
    `preOpenStack` builds the UI, `qsStart` calls the idempotent `qsBuild` first, and every
    timer refresh exits when the field is missing.
12. **Never guess font metrics.** `uiWrap` FITS a field to its `formattedHeight` with the
    top pinned (never grow-only: band-title and badge centering read that height), and
    only when `formattedHeight > 0`, or an early blank measurement collapses every label.
13. **`set the margins` needs the 4-item form** (`"6,6,6,6"`); one number is ignored.
14. **Chrome is graphics** (roundRect / rectangle) created BEFORE the controls on them, for
    z-order; `dropShadow` goes in a `try`; `qsClearGeneratedUI` deletes graphics too.
15. **`does not contain` is not valid xTalk:** write `not (X contains Y)`.
16. **Quote a `send` parameter that can hold `:`** (a clearweb socket id is `"ip:port"`):
    `send ("qsCwWatchdog " & quote & pSocketID & quote) to me in ...`. Numeric OnionXT
    handles are fine unquoted.
17. **Read the clipboard inside `try`** (it fails transiently on Windows). Offer each value
    once (`sClipSuggested`), never overwrite input, never offer own codes (`qsIsOwnCode`).
18. **A standalone quits via `shutdownRequest` with no guaranteed `closeStack`.** Both call
    the idempotent `qsStop` (session pause, flush resume, join; Tor service and web
    listener torn down; temp `.enc` files deleted). No teardown only on `closeStack`.
19. **LCB public handlers work in BOTH command and function form:** `btCreateTorrent(...)`
    is torrentxt's documented command (coinxt's engine passes proved the function form).
20. **A mirror can only be checked against what its author believed.** The execution
    gate's first run (2026-09-11) found two MIRROR defects: `fs_leaf` pinned `("dir/", "")`
    but the engine ignores ONE trailing delimiter, so the leaf is `"dir"` (engine note 2.2;
    fixed, `"dir//"` added); `parse_head` had a `__resource` field the script never sets and
    lacked the `__version` `qsCwServe` reads for the keep-alive default. The gate compares
    the WHOLE map (an unset key reads as empty), which caught both.
21. **A token, hash or nonce never meets bare `is`.** `is` compares two operands that
    both parse as numbers AS NUMBERS (C `strtod`, no range check; the suite's engine note
    2.11, from the engine source, not yet observed): a hex token shaped digits-`e`-digits
    overflows to +inf, and so do `1e999` and `inf` in a request, so `qsCwServe`'s capability
    gate let `/1e999/` in on about one share in 1.2 million until it compared
    `("t" & tTok)` with `("t" & sCwToken)` (2026-09-25; verified statically; needs an OXT
    pass). Prefix a letter to both sides, or compare byte by byte.

## 4. Engine evidence ledger

No dated engine pass of this stack is recorded in this tree. Gotchas 11-18 came from
undated pre-fold passes of the standalone app; the 2026-08-14 kit adoption re-opened the
whole stack. The dated rows are STATIC records, each waiting on the checklist.

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| undated, pre-fold | OXT (the standalone repository) | the app's own passes | gave gotchas 11-18; re-opened 2026-08-14 |
| 2026-08-13 | none (static) | fold into the suite under the unified checker | clean on first contact |
| 2026-08-14 | none (static) | kit adoption + audit fixes: six `if not sCwActive` became `is not "true"`; both crypto prologues try-guarded; a second control-connect failure reaches the Activity log | the whole stack needs an OXT re-pass |
| 2026-08-15 | none (static + golden) | `qsHttpFileHead` (one file head for both transports); `qsMountLocation` redirect re-prefix | green; checklist sections 1, 4 |
| 2026-08-16 | none (static + golden) | `:param` user routes | green; checklist section 1a |
| 2026-08-17 | none (static + golden) | HEAD reaches the GET route; the Tor text reply stops sending a HEAD body; `qsHttpReservedPath` | green; checklist section 4 |
| 2026-08-24 | none (static) | OnionXT embedded, with the socket split | OnionXT branches need a live-Tor re-pass |
| 2026-09-09 | none (static) | eight delayed handlers pinned; `btStartSession` guarded | checklist section 8 is its pass |
| 2026-09-11 | family interpreter, not the engine | `tools/check-script-vectors.py` on the golden's inputs | 435 checks green; the fixture test catches 4 of 4 seeded defects (dotfile guard false; FIRST Content-Length kept; `..` admitted; Tor HEAD body sent) |
| 2026-09-24 | none (static) | the OnionXT wording the 2026-08-24 embed made wrong: the header's builder list, `qsCapabilityLine`'s "OnionXT not in the message path", two `qsLog` lines advising an OnionXT install, the Tor chip's "extension not installed", two stale comments; one reason sentence, `qsOnionOffReason` | checklist section 8's "Without SodiumXT" line is its pass |

Decisions that bind this app (the suite's docs/OPEN-DECISIONS.md), all 2026-08-27: **D-09**
the Tor path stays close-per-response; **D-02** the HTTP-host endpoint menu waits for the
first external user report; **D-10** spend an engine minute on the cheap single-file mtime
probe (checklist section 4; not yet run); **D-11** the anon path warns above 256 MiB
(`kAnonSizeWarn`), never auto-downgrades; **D-07** tor stays a documented user install.

## 5. Status

Every runtime behaviour here is "verified statically; needs an OXT pass"; the gates are
green. The owed pass is `docs/oxt-pass-checklist.md` (69 items, none ticked; the boot
record should read "all 49 controls"), the suite runbook's row 22: web-link half in
session S1 (row S), Tor half in S2 (item 7). The source's VERIFY markers say what each
engine-dependent line still needs. Suite engine note 6.9 (OBSERVED 2026-09-15, on
another member's demo) shows libURL speaking https; this app's public-IP probe has not
been run. Open work is tracked in the suite's docs/WORK-PLAN.md.

## 6. Build and gates

No native code. `bash tools/run-gates.sh` (from anywhere) is the list CI runs: the static
checker; every `tests/*golden*.py`; `tools/test-script-vectors.py` BEFORE
`tools/check-script-vectors.py --check` (a gate gone blind prints OK). The golden holds the
mirrors to vectors and the execution gate holds the SHIPPED script to the mirrors (vector,
mirror, script: no expected value typed twice). The suite's `build-all.sh` delegates to
this script; its `check-member-standalone.py` refuses a gate file the script does not
name. The execution gate imports `../riptide/tools/check-demo-boot.py` (`DemoInterp`),
which loads nostrxt's interpreter and the committed coinxt, so its siblings are riptide,
nostrxt and coinxt (`../<name>`, or `XTALK_SIBLINGS` / `XTALK_SIBLING_<NAME>`). An absent
riptide exits 2 (a setup failure, not a vector failure); `XTALK_REQUIRE_SIBLINGS=1` in CI
turns sibling skips into failures. It does not drive `qsFsServePath`, `qsCwServe`,
`qsFileSizeSeek`'s file I/O or the `{{now}}` clock; its docstring says why.

Suite gates also walk this member: `check-handler-calls`, `check-stack-size` (the 720p
budget of 1200 x 640; this window is 1100 x 640), ui-kit and demo-selfcheck drift, the
timer-stack-pin closure, `check-lcb-call-types`, `sync-demo-embeds --check`. The list is
the `== suite: tools/...` block in the suite's `tools/build-all.sh` (run
`tools/build-all.sh --gates` there). Packaging: `docs/building-a-standalone.md`.
