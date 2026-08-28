# HEADLESS-ENGINE.md - can the engine run without a human at a GUI?

**Scope: the whole suite. Status: NOTHING HERE HAS BEEN OBSERVED.** Every
capability claim below is DOCUMENTED or weaker under the evidence rule in
[OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md). This document exists to make the
question cheap to settle, not to answer it. When the first probe runs, its
report goes in this file with a date and the claims below are re-classed one by
one.

---

## 1. What prompted this

The suite posted about the consolidation on the LiveCode forum. On
**2026-08-27** Brian Milby (`bwmilby`) replied:

> I stumbled upon this repo a week or so ago and was going to ask about which
> was going to be most current, but I think you answered it here... you are
> consolidating the individual repos into this one.
>
> It is possible to run both the standalone (or server build) and the lcb
> compiler headless via script. Linting in various text editors typically use
> the server engine to lint scripts and provide info on where errors occur. I
> was going to mention that when I ran across the repo but had not had a chance
> to look deeper and see how to leverage that for your projects.

Two separate claims, and they are worth separating because they have different
costs and different odds:

- **C1 - the LCB compiler runs headless.** `lc-compile` is a command-line
  program that turns a `.lcb` into a module. If true, the suite's six `.lcb`
  files can be *compiled* in CI.
- **C2 - the server engine can compile LiveCodeScript, and editors already use
  it that way.** If true, all 50 `.livecodescript` files can be *parsed* in CI,
  with the engine's own error text and line numbers.

Neither claim says anything about *running* the suite's tests headlessly. That
is a third question (C3), it depends on the server engine having a message
loop, and it is the one with the largest prize and the least evidence.

---

## 2. Why this matters more here than it would in most repositories

This tree asserts the opposite premise in **74 places across 65 files** -
"OXT has no headless way to compile or run `.livecodescript` or `.lcb`" - and
that premise is load-bearing, not decorative. It is the stated reason for:

- `tools/check-livecodescript.py`, the unified static checker: ~25 hand-written
  rules, carried byte-identical into ten members, that approximate a parse;
- `tools/check-duplicate-declarations.py`, `check-cross-library-names.py`,
  `check-lcb-call-types.py`, `box2dxt/tools/check-lcb-signatures.py` - each
  re-deriving something a compiler knows;
- `coinxt/tools/lcs-interp.py`, a **1,020-line LiveCodeScript interpreter
  written in Python** so that Base58Check and bech32 would execute at least
  once before shipping;
- the honesty convention itself: *"verified statically; needs an OXT pass"* on
  every runtime claim in the suite;
- and [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md), whose opening sentence is
  that engine access is sparse and whose cheapest session is an hour of a
  human's hands on a GUI.

So if C1 and C2 hold, this is not a nice-to-have. It changes what the static
apparatus is *for*.

---

## 3. The honest sizing - what a compiler would and would not buy

It is tempting to read "we can compile headlessly now" as "the engine notes
were avoidable". They were not, and the measurement matters more than the
enthusiasm.

`docs/OXT-ENGINE-NOTES.md` carried **26 entries** before this document added one
(22 OBSERVED, 3 DOCUMENTED, 1 UNEVIDENCED). Classified by whether a *compiler*
could have caught them:

| Would a compiler have caught it? | Entries | Count |
|---|---|---|
| **Yes - compile-time** | 1.3 constants literal and before use; 1.4 smart quotes fail compilation; 1.5 a prefixed name whose spelling IS a reserved token; 1.6 two script-level declarations of one name; 1.7 `the number of keys of X` does not parse; 3.3 a zero-argument call in statement position | **6** |
| **Yes, but only with `the explicitVariables` set** | 1.2 script-level declarations resolve by lexical position, and 2.1 an undeclared name evaluates to the literal text of its own name - one class, and the one behind the 106-declaration fold | **2** |
| **No - runtime or GUI semantics** | 1.1, 2.2, 2.3, 3.1, 3.2, 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8 | **18** |

**So: roughly a quarter, or nearly a third if `the explicitVariables` works.** That is a great deal - entry 3.3 alone is the
`dcCleanup()` line that took a 4,400-line paste down and cost a session - and
it is not everything. The expensive knowledge in this project is mostly
*runtime semantics*: the case-folding `is`, the trailing-delimiter eat, the
defaultStack rule for `send ... in`, an empty value into a typed `.lcb`
parameter. No compiler sees any of that. Anyone selling this proposal
internally should sell the quarter, not the whole.

**The one row worth staring at is `the explicitVariables`.** Engine note 2.1 -
OBSERVED - is that an undeclared name evaluates to *the literal text of its own
name*. That is this tree's most dangerous failure shape, because it never
errors: the generated fold ran `add "cx1sPassed" to sPassed` and produced a
tidy wrong answer, and the checker carries a whole hand-written rule
(`check_undeclared_k_constants`) approximating one flag the engine may already
have. If setting `the explicitVariables to true` before compiling turns that
class from runtime-silent into compile-loud across the whole corpus at once,
it is worth more than the lint that carries it. It is probe row
`compile.explicitVariables`. Nobody here has ever tried it.

---

## 4. What is favourable, measured rather than hoped

Four facts about this tree make the headless route easier than it might be
elsewhere. All four were measured on 2026-08-28 against the current tree.

**4.1 The `.lcb` corpus has no dependency graph.** Across all six modules the
only `use` clauses are `com.livecode.foreign` (6), `com.livecode.arithmetic`
(2) and `com.livecode.string` (2) - all builtin. No user modules, nothing to
resolve between members: each file compiles alone against the stock module
path.

**4.2 The foreign bindings look like load-time lookups.** Every one is of the
form `binds to "c:enetxt>enx_abi_version!cdecl"`, where the library token is
resolved in the extension's `code/<platform>/` folder. *Expected* (DOCUMENTED,
not observed) to be a LOAD-time lookup, so `lc-compile` should not need any
native `.so` present. If that is wrong, `tools/check-lcb-compile.py` reports
the compiler's own words and the fix is one CI step: build the libraries first.

**4.3 Thirty-two of the 50 `.livecodescript` files are script-only stacks.**
They carry a `script "Name"` first line, which is the marker that makes a plain
text file a stack the engine can load from disk. The other **18** - all seven
box2dxt files, all seven onionxt files, plus `sodiumxt/examples/sodium-tests`,
`tests/preflight`, and the two carried masters `tools/ui-kit` and
`tools/harness-scaffold` - are paste-in fragments, which their own docs say
(`box2dxt/docs/kit-guide.md:74`: *"Or save it as a library stack and `start
using` it"*). *This split is not recorded anywhere else in the tree.* It matters
because it decides the lint idiom per file: the 32 could also be checked via
`start using stack`, which exercises the same path a real user takes. The
`set the script of` route covers all 50 uniformly and is what the tooling here
uses.

*(An earlier draft of this section said 35 and 14. Both were eyeball counts off
a directory listing and both were wrong; the figures above come from a scripted
count against `HEAD`. Recorded rather than quietly corrected, because
hand-copied numbers going stale is the failure this tree documents most often
and it should be visible when it happens here too.)*

**4.4 The "make a harness headless" transform already exists.**
`tools/build-suite-selftest.py` drops exactly the window half from every folded
member harness - `DROP_HANDLERS` names `openStack`, `closeStack`, `mouseUp`,
`openCard`, `closeCard`, `stBuild`, the three `stMake*` builders, `stMonoFont`,
`stShow`, `stPaint`, `stCopyResults`, `stReportText` - and stubs `stShow` and
`stPaint` where folded code still calls them. The scaffold master states the
rule outright: *"UI goes in the droppable set, accounting does not."* That
transform, already written and already drift-gated, has been applied to ten
member harnesses. A headless run of the suite core is the same transform one
level up. **That is why C3 is worth asking about at all** - the hard part is
done, and what remains is whether the server engine has a message loop to drive
`send "stPump" to me in 33 milliseconds`.

---

## 5. The architecture: measure first, gate second

The rule this document is built on is the one the root `CLAUDE.md` states as
*descriptions rot and checks do not*. Every capability above is a guess. So the
first artefact is not a gate - it is an **instrument**.

```
  tools/engine-probe.livecodescript   ASK the engine what it can do. Dumps raw
                                      answers, interprets nothing. Runs headless
                                      via the driver OR pasted into a GUI stack,
                                      so the GUI column is a known-good control.
        |
        v
  a dated probe report                the first OBSERVED evidence this project
                                      has about the headless surfaces
        |
        +---> tools/check-engine-lint.py   drives engine-lint.livecodescript over
        |                                  all 50 .livecodescript files
        |
        +---> tools/check-lcb-compile.py   drives lc-compile over all 6 .lcb files
        |
        +---> (only if the probe says there is a message loop)
                                           a headless harness runner - C3
```

**Nothing downstream may assume a capability the probe has not confirmed.**
That is the whole discipline, and it is the reason the probe exists as a
separate thing rather than as error handling inside a gate.

---

## 6. What is built today, and exactly what it proves

| File | What it is | What it proves today |
|---|---|---|
| `tools/engine-probe.livecodescript` | ten capability probes, each in its own `try`, raw evidence dumped | Nothing yet. It passes the suite's own static gate; it has never met an engine. |
| `tools/engine-lint.livecodescript` | Compiles every file in a manifest via `set the script of`, emits one record each | Nothing yet, same reason. |
| `tools/check-engine-lint.py` | The driver: discovery, wrapper generation, report parsing, refusals | That the driver handles the report format correctly - proven by fixtures, below. |
| `tools/test-engine-lint.py` | 20 cases against a **fake engine** that lies one way per run | That every refusal fires, and that the unmutated baseline passes. |
| `tools/check-lcb-compile.py` | The same shape for `lc-compile`, with a three-way control set | That the driver handles a compiler's results correctly. |
| `tools/test-lcb-compile.py` | 9 cases against a **fake compiler** | Same. |
| `.github/workflows/engine.yml` | Manual-dispatch lane: fetch an engine, probe, then lint/compile advisorily | Nothing yet - it has never been dispatched. |

**The fixtures are the honest part, and their limit is the honest part of the
honest part.** They prove the drivers handle *the format the engine-side scripts
are written to emit*. They do not prove a real engine emits it, that
`set the script of` reports compile errors through `the result`, or that the
server engine will run the generated wrapper at all. If the first real run
shows a different shape, the format changes and the fixtures change with it -
which is cheap, and is the point of keeping the assumption in one place.

### Every refusal, and why it is there

Both drivers have three outcomes, and the third is the one that matters:
**SKIPPED** (no engine; exits 0 so the gate can sit in the always-on lane
without pretending), **MEASURED**, and **REFUSED** - the report cannot account
for itself, so the run says *nothing* about the corpus and exits non-zero
anyway. A lane that shells out to an external binary is a fresh chance to join
this repository's own catalogue of gates that reported OK while measuring
nothing, so:

- a **known-good** and a **known-bad** control run on every invocation. The
  known-bad for the script lane is engine note 3.3's own defect - a
  zero-argument call in statement position. If it compiles, the engine is not
  checking and the whole report is refused.
- the report carries a **completeness marker with a record count**. A truncated
  report reads exactly like a finished one; this tree has already spent an
  evening diagnosing three early clipboard copies as a hung pump.
- **every requested file must come back with exactly one verdict.** A dropped
  file is the difference between "the corpus is clean" and "the part I looked at
  is clean".
- **an empty read is an ERROR, not an empty script.** An empty script compiles.
- a **corpus floor** (30) refuses a run whose discovery walk returned
  implausibly few files.
- `EXPECTED_FAILURES` is **empty on purpose**, and a stale entry is refused. It
  would be easy to guess which fragments cannot compile standalone; guessing is
  how a permanent exemption gets written for a file that would in fact have
  compiled.

A note on how one of those was found. The fake engine's first version located
the entry call by searching the wrapper for `xtLintRun("...")` - and matched the
**usage example in a comment** in the engine-side script's own header, so it
went looking for `/abs/path/to/manifest.txt` and every case "passed" for the
wrong reason. That is this tree's recorded comment-versus-code trap landing
inside the tool written to guard against it. The driver now emits the call under
a sentinel line. The fixtures caught it on their first run, which is the
argument for writing them first.

---

## 7. The staged plan, with abort criteria

Each stage is independently useful, each is authorised by a measurement from the
one before, and each can be the last without leaving debris.

**Stage 0 - PROBE. Cost: one engine-minute.**
Run `check-engine-lint.py --probe` against any headless engine, and paste the
same file into a GUI engine for the control column. Commit the output here.
- *Abort if:* the server engine cannot run the wrapper at all. Record that in
  OXT-ENGINE-NOTES.md with the engine build - a negative result, dated, is worth
  more than the current silence, and it retires the question for that engine.

**Stage 1 - LCB COMPILE. Authorised by:** an `lc-compile` binary existing.
Highest confidence in the whole plan (it is a real compiler with a documented
command line) and the smallest surface (6 files, no dependency graph).
- *Exit criterion:* all six modules compile, controls behaved, in CI.
- *Abort if:* the compiler needs the IDE's environment, or resolves foreign
  bindings at compile time and cannot be given them.

**Stage 2 - SCRIPT LINT. Authorised by:** probe rows `object.createStack` and
`compile.badIsReported` both YES.
Broadest reach (50 files), and the stage that would have caught engine note 3.3.
- *Exit criterion:* the corpus lints green in CI, with `EXPECTED_FAILURES`
  populated from real engine output rather than from guesses.
- *Abort if:* the server engine has no object model. Then the lint needs a
  different target and this stage waits.

**Stage 2b - EXPLICIT VARIABLES. Authorised by:** probe row
`compile.explicitVariables` YES.
Turn the flag on and lint again. Expect noise on the first pass; every genuine
hit is an instance of the class that produced the 106-declaration fold.
- *Abort if:* the noise is structural rather than incidental.

**Stage 3 - RUN THE HARNESS. Authorised by:** probe row `runtime.sendInTime`
YES *and* stage 2 green.
The big one, and the only stage that would change an honesty label from
"verified statically" to something stronger. Reuses `build-suite-selftest.py`'s
existing drop/stub transform on the core.
- *Abort if:* there is no message loop. A synchronous subset could still run,
  and that is a separate decision with its own cost.

**Stage 4 - LOAD THE EXTENSIONS.** Authorised by: probe row
`load.extensionCommand`, plus committed `x86_64-linux` libraries.
Only this stage tests that a binding LOADS and a foreign call MARSHALS - the
thing the runbook says CI "can never prove".

---

## 8. What stays manual no matter how well this goes

Written down so the proposal is not oversold, and so the runbook is not retired
by accident:

- **every GUI demo.** Sixteen stacks whose whole job is building a window. A
  headless engine cannot tell you a window looks right.
- **the two-machine legs** - ENet LAN/internet chat, the torrent transfers.
- **the live tor daemon legs** - eleven of onionxt's exempted handlers take an
  engine-supplied socket id no harness can mint.
- **the 5-platform matrix.** A headless Linux lane loads the `x86_64-linux`
  library and nothing else.
- **all 18 runtime entries in the engine notes**, which is the point of section
  3 above.

The manual pass gets *smaller and better targeted*. It does not go away.

---

## 9. Open questions this document deliberately does not answer

1. Does an OpenXTalk distribution ship a server engine and `lc-compile` at all,
   or would this run against stock LiveCode Community 9.6.x? If the latter: what
   diverges between them, and is a lint result from one honest about the other?
   *(The suite targets OXT 9.6.3. A Community-engine result is evidence about
   Community, and saying otherwise would be exactly the overstatement this
   file's own convention exists to prevent.)*
2. What is `lc-compile`'s real command line? The driver's flags are a documented
   claim; it prints what it ran so a first run corrects one string.
3. Does the server engine set a process exit code? The drivers do not rely on
   one - they require the report's own marker - but knowing would simplify them.
4. What happens to `coinxt/tools/lcs-interp.py` if the real thing can run the
   same files? It has named divergences from the engine and this would settle
   every one of them. Retire it, or keep it as a **differential oracle** - run
   both, report disagreement? The second is more valuable and nobody has to
   decide today.
5. GPL/licensing: LiveCode Community is GPL and this suite is MIT. Downloading
   an engine in CI to *run* it is ordinary tool use, but nothing here should be
   asserted without someone actually reading the licence.

---

## 10. Status log

| Date | Event |
|---|---|
| 2026-08-27 | bwmilby's forum reply (section 1). |
| 2026-08-28 | This document, the probe, both drivers, both fixture suites and the CI lane written. **No engine has run.** Every capability claim is DOCUMENTED or weaker. The 74 no-headless assertions elsewhere in the tree are deliberately left alone: nothing has been measured, so nothing may be rewritten. |
