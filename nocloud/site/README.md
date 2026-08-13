# `site/` - the product landing page

A standalone marketing / product page for **No Cloud Quick Share**, built in the same
**"Aurora Vault"** visual language as the bundled web-app demo (`../webapp/`). It is a
professional open-source product page: the pitch, the three ways to share (with the
honest privacy breakdown), the full feature set, a **lower-level tech-stack** section for
people who read the source, cloud-vs-us and per-path comparison tables, a get-started
guide, and an FAQ.

## What it is

A **dependency-free static page** - three files, no build step, no framework, no CDN, no
external fonts, **no network calls at all**. That is deliberate: the whole folder could be
served *by Quick Share itself* over a web link or a Tor `.onion`, offline, and under a
strict CSP (`default-src 'self'`).

```
index.html   the page: header, hero, how-it-works, ways-to-share, features,
             transparency table, under-the-hood (architecture diagram), vs-cloud,
             get-started, FAQ, footer
style.css    one stylesheet - the Aurora Vault system (glass cards over a living
             aurora), light + dark, responsive, reduced-motion aware
app.js       progressive enhancement only: theme toggle, mobile nav, copy-command,
             scroll-spy, sticky-header state, reveal-on-scroll
assets/
  logo.svg   the app mark (favicon + brand), shared with the webapp
```

## Design notes

- **It degrades without JavaScript.** Every section is fully readable and navigable with
  JS off; `app.js` only adds polish. The reveal-on-scroll class is *added by JS*, so with
  JS off nothing is ever hidden.
- **Theme:** light/dark ride `prefers-color-scheme` by default; the header toggle stamps
  `:root[data-theme="light"|"dark"]` and remembers the choice in `localStorage`.
- **Self-contained + CSP-clean:** no external requests, so it keeps working offline, over
  Tor, and under the same strict policy the demo uses.
- **Faithful to the family:** the tokens, aurora field, glass cards, gradient buttons and
  kicker eyebrows are the same language as `../webapp/app.css`.

## Serving it

Open `index.html` directly, drop the `site/` folder onto Quick Share and share it over a
web link or Tor, or host it anywhere static. There is nothing to build.
