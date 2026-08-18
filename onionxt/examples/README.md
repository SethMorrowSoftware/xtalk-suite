# Examples

Formatted like the sibling family's example stacks (SodiumXT's
`sodiumxt/examples/sodium-demo.livecodescript` /
`sodiumxt/examples/sodium-tests.livecodescript`, and TorrentXT's
`torrentxt/examples/`).

| File | What it shows |
|---|---|
| `onionxt-demo.livecodescript` | An interactive, tabbed showcase of every public `ox*` feature: connect + bootstrap, dial through SOCKS5, HOST over Tor (serve the editable page, or share a folder as a browsable file list, via the `onion-httpd` layer), the address/base32 tools, and the capability flags + a "Run self-test" button. **Paste-and-run**: it carries `onionxt`, `onion-httpd` and `onionxt-tests` embedded between the sentinels that `tools/sync-demo-embeds.py` owns, so there is no `start using` wiring. Edit the sources under `src/`, never inside the sentinels. |
| `onionxt-tests.livecodescript` | A pure, offline self-test harness: module-level `sLog`/`sPass`/`sFail`, an `oxCheck`/`oxSection` assertion pair, and known-answer vectors cross-checked against `tools/onion-kat.py`. Call `oxSelfTest()` directly, or use the demo's "Run self-test" button. Read its header before extending it: it deliberately does not attempt a live daemon handshake (see the header for why). |
| `onion-httpd/` | Host a site / a browsable file share over an onion with the `oxh*` layer: the `spike.livecodescript` file-sharing app - paste-and-run, with both libraries embedded - and a README covering the whole `oxh*` API. |
| `socks-dial/` | The thinnest slice: dial a host through Tor and read the reply. No control port needed. |
| `onion-roundtrip/` | The headline milestone: two instances talk over Tor with no server, sealed by SodiumXT. |

The `ox*` / `oxh*` library paths behind these (SOCKS dial, control auth, publishing an onion, and serving
HTTP on the accept loop) have had on-engine bring-up against a real tor daemon (CLAUDE.md as-built notes),
and the tabbed demo's UI has rendered and served on-engine too (the Service tab's live mode swap and the
About-tab self-test are part of that record). The optional Mode B tor launch remains the one unexercised
path.
