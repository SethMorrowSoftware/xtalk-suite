# No Cloud Quick Share documentation

No Cloud Quick Share is a shipped APP, not an extension: one stack over
torrentxt, with optional sodiumxt and onionxt. Files go straight from one
computer to another, with no server in the middle.

**If you are deciding whether to trust it, read
[what-it-hides.md](what-it-hides.md) first** - it is the honest page.

| Document | What it is |
|---|---|
| [what-it-hides.md](what-it-hides.md) | The honest page: what the app hides, and what it does not. Read this before relying on it for anything sensitive. |
| [user-routes.md](user-routes.md) | Adding custom HTTP endpoints to a shared folder without opening the stack script, via a `.qsroutes.json` file. |
| [webapp.md](webapp.md) | The `webapp/` single-page demo that ships as sample content. Not part of any extension and not required to run the app. |
| [building-a-standalone.md](building-a-standalone.md) | Building a standalone app. The UI self-builds on every launch, so nothing needs to persist in the stackfile. |
| [http-server-deep-dive.md](http-server-deep-dive.md) | A design and discussion document for the embedded HTTP host, grounded in a read of the source. Improvement ideas and an endpoint brainstorm, not a status page. |
| [oxt-pass-checklist.md](oxt-pass-checklist.md) | The engine pass for the HTTP host. There is no headless way to run a `.livecodescript`, so every change to the host is flagged "verified statically; needs an OXT pass" until this checklist is walked. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
