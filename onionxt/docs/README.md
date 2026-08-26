# OnionXT documentation

OnionXT is anonymous TCP and serverless v3 onion services for xTalk, in pure
LiveCodeScript over a local Tor daemon: the `ox*` surface.

These docs are a NUMBERED SERIES, meant to be readable in order: 00-01 orient
you, 02-04 and 07 are the wire-level and lifecycle specs, 05 is the API, and 10
is the from-zero guide. **If you just want to use it, jump to
[10-usage-guide.md](10-usage-guide.md).**

| Document | What it is |
|---|---|
| [00-overview.md](00-overview.md) | Overview and architecture: the one-sentence version, and how the two wire protocols fit together. |
| [01-threat-model.md](01-threat-model.md) | The honest account of what routing through Tor with onion-service rendezvous actually buys, and what it does not. |
| [02-socks5-client.md](02-socks5-client.md) | Byte-level spec for the outbound path: Tor's SOCKS5 proxy, RFC 1928 plus Tor's extensions. |
| [03-control-port.md](03-control-port.md) | Command-level spec for the inbound and management path: authenticating to the control port, publishing onion services, reading events. |
| [04-onion-rendezvous.md](04-onion-rendezvous.md) | The idea that makes this more than Tor-for-xTalk: a v3 onion address IS a public key, so rendezvous is self-authenticating and deterministic. |
| [05-api-reference.md](05-api-reference.md) | The public `ox*` surface an app calls. Commands report status through `the result`; handles come back as positive integers. |
| [06-transport-integration.md](06-transport-integration.md) | Using OnionXT as a pluggable transport underneath a higher-layer protocol. |
| [07-tor-lifecycle.md](07-tor-lifecycle.md) | Where the daemon comes from: assume-running versus launch-a-binary, and why both are supported without letting the convenient one become the default. |
| [08-capabilities-required.md](08-capabilities-required.md) | The honest list of narrow crypto primitives this member wants from SodiumXT, and the family rule that keeps it from growing its own. |
| [09-open-questions.md](09-open-questions.md) | Design decisions not yet settled and limits not yet closed, each labelled for what it is. |
| [10-usage-guide.md](10-usage-guide.md) | From zero: loading the layer, dialling anonymously, and publishing a serverless address. The page most readers want. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
