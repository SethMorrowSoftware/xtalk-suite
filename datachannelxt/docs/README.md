# DataChannelXT documentation

DataChannelXT is browser-interoperable WebRTC data channels for xTalk, over
libdatachannel: the `dc*` handler surface, with real NAT traversal.
Start with [getting-started.md](getting-started.md).

| Document | What it is |
|---|---|
| [getting-started.md](getting-started.md) | Install to a working two-machine connection, with a zero-setup loopback demo first. Read this first - it is also where the signalling shapes are explained, including why the local-description event is `dcLocalDescriptionReady` and not `dcLocalDescription`. |
| [api-reference.md](api-reference.md) | The public LCB surface of `org.openxtalk.library.datachannel`. Every handler and every event, including the one namespace collision the naming avoids. |
| [architecture.md](architecture.md) | The design answer to one question: how do libdatachannel's worker threads and OXT's single interpreted thread share a process safely? |
| [building.md](building.md) | Building the one shared library: the C++ shim statically linking libdatachannel and its vendored dependency stack. |
| [../THIRD-PARTY-LICENSES.md](../THIRD-PARTY-LICENSES.md) | The per-file license map for libdatachannel and its vendored dependency stack. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
