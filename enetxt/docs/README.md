# enetxt documentation

enetxt is game-grade reliable UDP for xTalk, over ENet 1.3.18: the `en*` handler
surface. It is the family's smallest binding, and its doc set matches.
Start with [getting-started.md](getting-started.md).

| Document | What it is |
|---|---|
| [getting-started.md](getting-started.md) | From install to two machines chatting over reliable UDP. Read this first. |
| [api-reference.md](api-reference.md) | The public LCB surface of `org.openxtalk.library.enet` - all 23 public handlers, each one documented. Handles are positive integers; every handler is a function unless noted. |
| [architecture.md](architecture.md) | How ENet's sockets and reliability protocol sit under OXT's single interpreted thread, and why events poll-drain on a timer. |
| [building.md](building.md) | The lightest dependency story in the family: one small C library, fetched and pinned by CMake, statically folded into the one shared library. |
| [../THIRD-PARTY-LICENSES.md](../THIRD-PARTY-LICENSES.md) | The license for the vendored ENet source. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
