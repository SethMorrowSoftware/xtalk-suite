# Building and testing oscxt

You do not need any of this to USE oscxt: the libraries ship inside the extension
(`src/code/<arch>-<platform>/`), landed by the suite's `release-binaries.yml`. This is for
changing it.

## What builds

ONE shared library, `oscxt.{so,dll,dylib}` under its bare name (no `lib` prefix): the C shim
`src/osc_shim.c` and tinyosc (ISC, vendored under `src/third_party/tinyosc/`), compiled
together. It exports `osc_*` and nothing else (`src/oscxt.map` for GNU ld; the same pattern
for ld64), carries the static C runtime on Windows, starts no thread and opens no socket.
It needs nothing but a C17 compiler, so nothing in it stops an Android build, but none has
run yet: the suite's `tools/build-android.sh` names it desktop-only until one has (the suite's
work plan carries it).

## Build

A C17 compiler and CMake 3.22:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DOSCXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --build-config Release --output-on-failure --no-tests=error
```

Under the sanitizers (gcc on Linux):

```sh
cmake -S . -B build-asan -DCMAKE_BUILD_TYPE=Debug -DOSCXT_BUILD_TESTS=ON -DOSCXT_SANITIZE=address
cmake --build build-asan && ctest --test-dir build-asan --output-on-failure
```

## The tests

Everything runs headless, with no OSC hardware or software on the other end.

| Layer | What | How |
|---|---|---|
| C | `tests/osc_smoke_test.c` (every export, the caller-buffer contract, refusals, the number and locale rules), `tests/osc_vectors_test.c` (the shared wire-format vectors) | ctest |
| Fuzz | `tests/fuzz/osc_fuzz.c`: a deterministic mutation fuzzer over `osc_parse` and every getter, seeded from the vectors; under the sanitizer build every input is checked | ctest `osc_fuzz` (100000 inputs); `osc_fuzz <count> <seed>` for more; `--replay FILE` for one |
| Wire format | `tests/vectors_reference_test.py`: a clean-room Python codec written from the OSC 1.0 specification (`tools/sim/refcodec.py`), and python-osc when it is installed, against every vector; `tests/simulators_test.py`: the virtual peer over real UDP | `bash tools/run-gates.sh` |
| LCB | `tests/lcb/osc_test.lcb` under lc-run: the real binding over the real library, plus the vectors module generated from `tests/vectors/osc.json` | `python3 tools/run-lcb-tests.py --oxt-bin <OXT bin folder> --build-dir build` |
| Script, in the engine | `tests/lcs/*.livecodescript` in the standalone engine with `-ui`: the Script-to-LCB boundary, the shipped helpers, the shipped self-test, real UDP through the engine's own sockets, and interop with the virtual peer `tools/sim/osc_peer.py` | `python3 tools/run-lcs-tests.py --oxt-bin <OXT bin folder> --build-dir build` |

The coverage-guided build of the same fuzzer needs clang with libFuzzer
(`-DOSCXT_LIBFUZZER`; the command is at the top of `tests/fuzz/osc_fuzz.c`). A fuzz failure:
bisect the count, set `OSC_FUZZ_DUMP_AT=N` to write that input out, and `--replay` it.

The OXT folder for the two runners is any OXT build folder holding `lc-compile`, `lc-run` and
the standalone engine, or an OXT-Beyond `*-binaries` release archive unpacked; `$OXT_BIN`
works too. `OSCXT_REQUIRE_ALL=1` turns every skip of the runners into a failure (the
socket suites skip on an engine that delivers no socket events without a UI),
`OSCXT_REQUIRE_PYTHONOSC=1` a missing python-osc, and `OSCXT_REQUIRE_COMMA_LOCALE=1` a
machine with no comma-decimal locale for the smoke test's locale check.

**Done means:** a shim change is green in ctest under `-DOSCXT_SANITIZE=address`, the fuzzer
included; a binding change passes `run-lcb-tests.py` (lc-compile `-Werror`, as the Extension
Builder compiles); a Script change passes `run-lcs-tests.py`; all of them pass
`bash tools/run-gates.sh`. A change to the wire format starts in `tests/vectors/osc.json`
(`python3 tools/gen_vectors.py` regenerates the C header; `--check` is a gate).

## The API reference is generated

`docs/api-reference.md` is written from the binding's `/** */` doc blocks by
`python3 tools/build-api-reference.py`; its `--check` is a gate.

## Refreshing the committed libraries

The libraries under `src/code/` are committed only by the suite's `release-binaries.yml`, a
manual dispatch (pressing Run is the human decision the suite's rule 5 asks for), which
checks each library's name, format, architecture and exports and refreshes
`src/code/MANIFEST.sha256`. `tools/package-extension.py --build-dir build` copies a local
build into the tree for a test of your own; do not commit what it writes.

## Bumping the ABI

`OSC_ABI_VERSION` in `src/osc_shim.h` and the literal in `checkABI()` of `src/osc.lcb` move
together, on any change to an export's name, arguments or meaning.
