# SodiumXT documentation

SodiumXT is a thin binding over libsodium: the `sx*` handler surface, plus the
conventions that keep a crypto call honest in xTalk. Start with
[getting-started.md](getting-started.md); reach for
[api-reference.md](api-reference.md) once you know what you are calling.

| Document | What it is |
|---|---|
| [getting-started.md](getting-started.md) | Install, and the handful of conventions worth knowing before your first call. Read this first. |
| [api-reference.md](api-reference.md) | The complete `sx*` handler surface of `org.openxtalk.library.sodium`, as called from LiveCode Script. Every signature, every error convention. |
| [recipes.md](recipes.md) | Copy-paste solutions for common tasks, all over the public `sx*` handlers. |
| [security.md](security.md) | The security model: what libsodium guarantees, what this binding adds (nothing cryptographic, by design), and what an app is still responsible for. Read before shipping anything that protects a user. |
| [building.md](building.md) | Acquiring and building libsodium, and the day-to-day loop: sanitizers, the static gate, packaging. Contributors only. |
| **Archive** - executed plans and superseded designs, kept for the reasoning | |
| [archive/implementation-plan.md](archive/implementation-plan.md) | The original spec and phased plan. A design record: where it differs from the code, the code wins. |
| [archive/torrentxt-integration.md](archive/torrentxt-integration.md) | SUPERSEDED. The plan to replace TorrentXT's crypto with SodiumXT. The migration shipped, and differently than planned here. Kept as the record of why. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
