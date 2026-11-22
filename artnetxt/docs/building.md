# Building and testing artnetxt

There is nothing to build. artnetxt is pure LiveCode Builder (`src/artnet.lcb`), with no C
shim and no native library: the Extension Builder packages the `.lcb` as it is, and the same
`.lce` serves every platform. This page is for changing it.

## The tests

Everything runs headless, with no lighting gear on the other end.

| Layer | What | How |
|---|---|---|
| Wire format | `tests/vectors/artnet.json` is the one source of the format. `tests/vectors_reference_test.py` holds a clean-room Python codec (`tools/sim/refcodec.py`, written from the Art-Net 4 specification) to every vector; `tests/artnet_golden_test.py` is a third encoder with hand-checked golden packets, each byte-order trap called out on its own; `tests/simulators_test.py` proves the virtual node over real UDP | `bash tools/run-gates.sh` |
| LCB | `tests/lcb/artnet_test.lcb` under lc-run: round trips, every length and range rule, every refusal and that a success clears it, the reply's ports and MAC at each length a node may send, and mutation fuzzing of both parsers; plus the vectors module `tools/gen_vectors.py` writes from `tests/vectors/artnet.json` | `python3 tools/run-lcb-tests.py --oxt-bin <OXT bin folder>` |
| Script, in the engine | `tests/lcs/*.livecodescript` in the standalone engine with `-ui`: the Script-to-LCB boundary (numbers as text or computed, empty, the reply's lists as arrays), the shipped helpers, the engine behaviour they are built around (`engine_notes_test`), the shipped self-test, real UDP through the engine's own sockets, and discovery plus DMX against the virtual node `tools/sim/artnet_node.py` | `python3 tools/run-lcs-tests.py --oxt-bin <OXT bin folder>` |

The OXT folder for the two runners is any OXT build folder holding `lc-compile`, `lc-run` and
the standalone engine, or an OXT-Beyond `*-binaries` release archive unpacked; `$OXT_BIN`
works too. `ARTNETXT_REQUIRE_ALL=1` (or `--require-all`) turns every skip of the runners into
a failure: the socket suites skip on an engine that delivers no socket events without a UI.
The virtual node runs on its own too: `python3 tools/sim/artnet_node.py --help`.

**Done means:** a binding change passes `run-lcb-tests.py` (lc-compile `-Werror`, as the
Extension Builder compiles); a Script change passes `run-lcs-tests.py`; all of them pass
`bash tools/run-gates.sh`. A change to the wire format starts in `tests/vectors/artnet.json`
(`python3 tools/gen_vectors.py --check` is a gate: the LCB vectors module is generated from
it at test time).

## The API reference is generated

`docs/api-reference.md` is written from the binding's `/** */` doc blocks by
`python3 tools/build-api-reference.py`; its `--check` is a gate.
