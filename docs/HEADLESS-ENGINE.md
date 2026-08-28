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

This tree asserts the opposite premise **all over itself** -
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
| `tools/engine-probe.livecodescript` | twelve probe groups, each in its own `try`, raw evidence dumped; one of them is the mandatory execution check that emits the two rows the driver requires | Nothing yet. It passes the suite's own static gate; it has never met an engine. |
| `tools/engine-lint.livecodescript` | Compiles every file in a manifest via `set the script of`, emits one record each | Nothing yet, same reason. |
| `tools/check-engine-lint.py` | The driver: discovery, wrapper generation, report parsing, refusals | That the driver handles the report format correctly - proven by fixtures, below. |
| `tools/test-engine-lint.py` | 34 cases against a **fake engine** that lies one way per run | That every refusal fires, and that the unmutated baseline passes. |
| `tools/check-lcb-compile.py` | The same shape for `lc-compile`, with a three-way control set | That the driver handles a compiler's results correctly. |
| `tools/test-lcb-compile.py` | 12 cases against a **fake compiler** | Same. |
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
anyway. Every run ends with one machine-readable line, `XT-ENGINE-STATUS: ...`,
so CI asserts on that rather than on prose that changes when a message is
improved.

A lane that shells out to an external binary is a fresh chance to join this
repository's own catalogue of gates that reported OK while measuring nothing,
so:

- **five controls, not one.** A known-good and a known-bad pair runs *before*
  the corpus and again *after* it under distinct names, because a single
  pre-corpus pair cannot see an engine that degrades partway through - and a
  degraded engine's silence is a clean report. A fifth, `known-bad-large`,
  carries the same defect inside a synthetic 20,000-line module, because two
  sixty-byte control strings say nothing about an engine's behaviour at the
  1.95 MB this corpus actually reaches. The known-bad defect is engine note
  3.3's own: a zero-argument call in statement position.
- **a cascade detector.** If a successful `set the script of` leaves `the
  result` *unchanged* rather than emptying it, one real compile failure becomes
  every later file's verdict and the run reports a corpus full of defects that
  reads like a catastrophe rather than a broken measurement. The engine-side
  script clears the result before each compile (via a handled `send`, since an
  assignment does not touch it); the driver additionally refuses a report whose
  failures look like one error copied down the run. Deliberately **not** "any
  two files agree" - in this tree two files agreeing is ordinary, because four
  blocks are carried byte-identically into a dozen files each, so one defect in
  a master legitimately produces the same text in sixteen demos. The signature
  is three or more files sharing one text *and* that group being most of the
  failures, and the refusal names the one command that tells the two apart.
  Whether the clear is even necessary is probe row
  `compile.resultClearedOnSuccess`.
- **the report carries a completeness marker with a record count.** A truncated
  report reads exactly like a finished one; this tree has already spent an
  evening diagnosing three early clipboard copies as a hung pump.
- **no record name may appear twice**, in any record kind. A report that can
  carry two answers to one question cannot be trusted for either, whichever
  answer a parser happens to keep.
- **every requested file must come back with exactly one verdict**, and **an
  empty read is an ERROR, not an empty script** (an empty script compiles).
- **two independent corpus lists.** The `os.walk` has a prune list, and a prune
  bug that silently drops four members leaves the count plausible and the run
  green. `git ls-files` cannot be broken by the same bug, so a walk that has
  lost something git can see is a refusal. A floor of 30 backs both up.
- **the probe can fail.** Its first version printed its rows and exited 0
  whatever they said, so a report in which every capability came back NO - or
  every row came back ERROR - read as a successful probe worth committing. Two
  **mandatory rows** now separate "this engine cannot do these things" from
  "nothing ran": `probe.selfArithmetic` (2+2) and `probe.emitRoundTrip` (a value
  containing a tab and a return, fed through the same emitter every other row
  uses). The probe refuses when a mandatory row is not YES, when neither
  `engine.environment` nor `engine.version` is present (so the report cannot be
  pinned to a build), or when more than half the rows are ERROR - the probe
  failing to *ask* rather than the engine failing to *do*.
- **but a NO is not a refusal.** `compile.badIsReported: NO` means this engine
  does not lint - which is a successful measurement of a limited engine and the
  single most important negative result to record. It prints as a loud verdict
  and exits 0. In the *lint*, the same shape voids the report; in the *probe* it
  is the finding. Conflating the two would make the probe unable to report the
  answer that most needs reporting.
- **an unrecognised binary is classified, not guessed at.** The driver generates
  a server-shaped `<?lc ?>` wrapper. Handed a standalone or desktop engine, the
  resulting "no marker" refusal would read as *headless does not work* rather
  than *wrong engine kind*, so a refusal on that path runs the binary bare and
  with `--help` and prints the transcript.
- **a hang surrenders what it buffered.** The timeout path carries whatever the
  engine printed before it stopped; that partial report names the probe that did
  not return.
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

  Measured 2026-08-28 over the assembled 42,014-line paste, which makes this
  stage much better specified than it looked:

  - **Seven of the ten folded harnesses contribute ZERO control-touching
    statements.** The regions carrying UI are the scaffold (38, every one inside
    a handler the generator already drops), the embedded b2k Kit (68),
    `fold:box2dxt` (79) and `fold:holde-em` (360). Holde-em's are already proven
    unreachable from its entry point by `check-suite-selftest.py`'s check 7d,
    which is an armed gate rather than prose.
  - **box2dxt is the one genuine GUI dependency, and it is structural** - the
    Kit binds physics bodies to xTalk graphics, so 47 of its 51 test handlers
    and roughly 415 of its 428 assertion sites need controls. A headless run
    means running the paste *minus box2dxt's fold*, and saying so.
  - **Exactly ONE timer chain has to fire: the core's `stPump`.** Of the 25
    `send ... in` sites in the paste, every other one is never entered, guarded
    off, or swept by the generator's pending-message sweep.
  - **The async loopbacks are POLL-DRAINED, not callback-driven** (suite rule 1:
    no native callback ever re-enters script). They need WALL-CLOCK TIME, not a
    message loop.

  That last point changes the abort criterion. The question is not really "does
  the engine dispatch `send ... in`" but "can the run be driven forward in
  time", and a driver that calls `stPump` in a plain `repeat` with a `wait`
  would satisfy the loopbacks even on an engine with no timer dispatch at all.
- *Abort if:* neither a message loop NOR a synchronous pump-and-wait driver can
  advance the run - and note that the terminating condition already exists and
  is unambiguous: `stReportDone` is the single write that stops
  `stReportText()` appending its `RUN NOT FINISHED` trailer, so a headless
  runner must require that trailer's ABSENCE rather than the absence of output.

**Stage 4 - LOAD THE EXTENSIONS.** Authorised by: probe row
`load.extensionCommand`, plus committed `x86_64-linux` libraries.
Only this stage tests that a binding LOADS and a foreign call MARSHALS - the
thing the runbook says CI "can never prove".

---

## 7a. Rules for the later stages, written down before anyone reaches them

An adversarial review of section 7's plan produced five rules that are cheap to
honour now and expensive to retrofit. None of them constrains anything built
today; all of them constrain what stage 1-4 may do.

**R1 - a gate may be retired only by a replacement that runs in the same lane,
at the same cadence, and is proven non-inert on that lane.** The tempting move
after a green stage 2 is to delete `tools/check-duplicate-declarations.py`,
whose whole subject is a hard compile error. But it runs on every push in
`suite-gates.yml`, and the engine lane is manual dispatch: trading the first for
the second is a net loss of coverage that reads as progress. No retirement until
an engine lane runs in the always-on job and a MEASURED run is recorded *from
that lane*. "Demote" means editing a docstring, not lowering a severity.

**R2 - controls are DATA, never tracked broken scripts.** A subsumption matrix
(one specimen per checker rule, to measure what the compiler actually catches)
must live as string constants in a `.py`, materialised to a temp directory -
the shape `tools/check-lcb-compile.py` already uses. Forty deliberately-broken
`.livecodescript` files in the tree would be walked by every gate that globs for
one, would need an exemption in each, and would make the corpus count a lie.

**R3 - every lint ROUTE carries its own control pair.** If the `start using
stack` route is added for the 32 script-only stacks, its controls must travel
that route, as real files with a `script "Name"` line. Otherwise a dead route
returns "no failures" and a two-route diff reads route silence as route
agreement.

**R4 - engine identity is part of a claim's primary key.** A result from stock
LiveCode Community is evidence about Community. The suite targets OXT 9.6.3, and
a label that cites a record from a different fork is precisely the overstatement
the honesty convention exists to prevent. If the GUI control column and the
headless column come from different forks, builds or platforms, the comparison
has an unresolved confound and the record must say which one.

**R5 - a subsumption credit needs the engine's own words.** Before any checker
rule is called redundant, the rejection that justifies it must be recorded
verbatim, and two rules rejected with byte-identical text count as one reason,
not two.

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
| 2026-08-28 | This document, the probe, both drivers, both fixture suites and the CI lane written. **No engine has run.** Every capability claim is DOCUMENTED or weaker. The no-headless assertions elsewhere in the tree are deliberately left alone: nothing has been measured, so nothing may be rewritten. |
| 2026-08-28 | An adversarial review of the above found two ways it could still fail open, and both are fixed here. **(1) The probe could not fail** - it printed its rows and exited 0 whatever they said, so an all-NO or all-ERROR report read as a successful probe worth committing; it now carries mandatory execution rows and refuses. **(2) Nothing cleared `the result` between the file read and the compile**, so if a successful `set the script of` leaves it unchanged, one real failure would have become every later file's verdict - a cascade reported as a corpus full of defects. Also added in the same pass: pre/post controls, a control at corpus scale, per-name uniqueness, `git ls-files` as an independent corpus list, engine-kind classification on an unrecognised report, partial output on a hang, and a machine-readable `XT-ENGINE-STATUS:` line CI asserts on. Three defects in the engine-side scripts were found by reading them against the engine notes themselves: a `catch` binding an error into the variable being built, `the itemDelimiter` left set to `/` (note 2.3), and `the number of chars of X & "..."` binding as a chunk over the concatenation. A fourth - a duplicate `local` left by an earlier tidy-up - was found by the review. |
| 2026-08-28 | A second adversarial pass, on the hardened lane. Three more fail-opens closed: the engine's own `chars=` count was emitted by the instrument and **read by nobody**, so a wrapper pointed at a stale manifest or a truncated read would have produced a well-formed report full of clean verdicts - it is now cross-checked against every file on disk, exactly, because the ASCII gate makes one character one byte; `--only` narrowed the corpus *and* disabled the floor, so it is now refused under `--require` (what CI passes) and stamped into the report otherwise; and the cascade detector was widened into a discriminating one, because in this tree two files sharing an error text is ordinary - four blocks are carried byte-identically into a dozen files each. Two counts that were wrong in the tree itself: `CLAUDE.md` said **TEN** copies of the unified checker when there are **eleven** (nostrxt's fold added one and nothing swept the sentence), and the CORPUS_FLOOR comment quoted a corpus size that was stale within hours - both fixed, the second by removing the number rather than correcting it. |
| 2026-08-28 | **Rule 22 added to the unified checker, and the premise count made a gate.** A name declared twice inside ONE handler is now refused in both dialects - neither existing gate could see it (rule 3 is `.lcb` only by deliberate measurement; `check-duplicate-declarations.py` is script-level by design) and this tooling shipped one on the day it was written. Synced across all eleven copies, five fixtures x eleven copies. Separately, `tools/check-premise-count.py` now RE-DERIVES how many places assert the no-headless premise and prints the convention that produced it, refusing prose that quotes a drifted figure. It exists because this document's own first draft said "74 places across 65 files" [stale-by-design], that figure reached seven documents inside a day, and a second measurement with a different pattern got a different answer - the hand-copied constant landing on the document that argues for measurement over approximation. The gate failed on its first run, which is the evidence it measures something. |
