# holde-em documentation

holde-em is a capstone APP, not an extension: serverless online no-limit Texas
Hold'em composed from TorrentXT, SodiumXT, Box2Dxt and (optionally) OnionXT.

**Its documents live at the member ROOT, not in this folder.** That is
deliberate, and this page exists so a reader who expects every member to have a
`docs/README.md` finds one that says where to go. The reason they stay put:
`IMPLEMENTATION-PLAN.md` and `holdem-spec.md` are cited by name from the game
source, from the member CI workflow, and from five suite-level documents, and the
member's game and its test harness are the same file -- so the paths are load
bearing in a way an ordinary member's docs are not.

| Document | What it is |
|---|---|
| [../README.md](../README.md) | The front door: what the game is, which extension provides what, the honest status, and how to run it. Read this first. |
| [../holdem-spec.md](../holdem-spec.md) | The design contract, corrected against the as-built code inline. Every place the build diverged from the spec is marked in the body. This is the authority on what the game is supposed to do; where it disagrees with the code, the body says which one won. |
| [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) | The phased build order. Phases are strictly ordered by dependency, each with exit criteria that separate what a machine can verify (static gates, KATs) from what only an on-engine OXT pass can confirm. Nothing advances a phase on "verified statically" alone. |
| [../CLAUDE.md](../CLAUDE.md) | Maintainer memory: the operational guide, the as-built record, the fold record, and the gotchas. Read before touching the source. |
| [../assets/cards/NOTICE.md](../assets/cards/NOTICE.md) · [../assets/sounds/NOTICE.md](../assets/sounds/NOTICE.md) | Attribution and licensing for the bundled card art and sound assets. |

**Where else to look.** The suite-level index is
[`../../docs/README.md`](../../docs/README.md); this app's entry in the
cross-member catalogue is in
[`../../docs/EXTENSIONS-OVERVIEW.md`](../../docs/EXTENSIONS-OVERVIEW.md).
