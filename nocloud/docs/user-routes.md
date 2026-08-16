# Custom API endpoints without LiveCode (`.qsroutes.json`)

You can add your own HTTP endpoints to a shared folder **without opening the stack script**.
Drop a file named **`.qsroutes.json`** in the folder you share, declare your routes in it, and
No Cloud Quick Share serves them alongside your static files.

It is **declarative and safe by design**: a route can only return a **canned body**, a **file
from the shared folder**, or a **redirect** — no code runs. A body may reflect a few request
values with `{{...}}` placeholders, but every value is **escaped for the response type**, so a
visitor can never inject markup, JSON, or a header. Paths under `/_qs/` and `/_edit/` are
reserved, header values are sanitised, file routes are confined to the shared folder, and the
`.qsroutes.json` file itself is never served or listed (it is a dotfile).

> Requires the engine's JSON support. Custom routes are **fail-closed**: if the build has no
> JSON decoder, the feature is simply off and everything else works. When you build a
> standalone, tick the **JSON Library** in the Inclusions pane (see
> `building-a-standalone.md`).

## The file

`.qsroutes.json` at the root of your shared folder:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/api/hello",
      "type": "application/json; charset=utf-8",
      "body": "{\"hello\":\"from a folder\",\"cloud\":false}",
      "cors": true
    },
    {
      "method": "GET",
      "path": "/api/note",
      "type": "text/plain; charset=utf-8",
      "body": "Declared in .qsroutes.json - no LiveCode, no cloud.",
      "headers": { "X-Defined-By": "qsroutes.json" }
    },
    {
      "method": "GET",
      "path": "/api/echo",
      "type": "application/json; charset=utf-8",
      "template": true,
      "body": "{\"method\":\"{{method}}\",\"you_said\":\"{{query.msg}}\"}",
      "cors": true
    },
    {
      "method": "GET",
      "path": "/api/greet/:name",
      "type": "application/json; charset=utf-8",
      "template": true,
      "body": "{\"hello\":\"{{param.name}}\"}",
      "cors": true
    },
    {
      "method": "GET",
      "path": "/api/config",
      "file": "config.json",
      "type": "application/json; charset=utf-8"
    },
    {
      "method": "GET",
      "path": "/go/gallery",
      "redirect": "/gallery",
      "status": 302
    }
  ]
}
```

Now `GET /api/hello` (at the onion root over Tor, or under `/<token>/` over a web link)
returns your JSON with an `Access-Control-Allow-Origin: *` header; `GET /api/echo?msg=hi`
reflects that back as `{"method":"GET","you_said":"hi"}`; `GET /api/greet/world` answers
`{"hello":"world"}` (a `:name` path parameter — see "Path parameters" below);
`GET /api/config` streams `config.json` from the folder under a friendlier URL; and
`/go/gallery` redirects — to `/gallery` at the Tor root, and to `/<token>/gallery` over a
web link (the mount re-prefix described under `redirect` below).

## Route fields

| Field | Meaning | Default |
|---|---|---|
| `method` | HTTP method to match (`GET`, `POST`, …) | `GET` |
| `path` | The URL path. Must start with `/`; may not contain `..` or control bytes; may not be under the reserved `/_qs/` or `/_edit/`. May contain `:name` **parameter segments** (see "Path parameters" below) — but the **first** segment must always be literal. | *(required)* |
| `body` | The response body (any text). Capped at 64 KB. | `""` |
| `template` | `true` enables `{{...}}` substitution in `body` (see below). Values are escaped for `type`. | `false` |
| `file` | Serve this file (path **relative to the shared folder**) instead of an inline `body`. Range-aware and streamed; confined to the folder just like a static file. | — |
| `type` | `Content-Type` for a `body` or `file` response. For a file, omit to derive it from the extension. | `text/plain; charset=utf-8` |
| `status` | HTTP status code. | `200` (body) / `302` (redirect) |
| `redirect` | If present, the route becomes a redirect to this `Location`. `status` may be `301/302/303/307/308`. A **folder-absolute** target (starts with `/`, e.g. `/gallery`) is written relative to *your shared folder* and served relative to wherever the app is mounted: at the Tor root it goes out as-is, and over a web link it is automatically re-prefixed with the `/<token>/` capability mount (so `/gallery` becomes `Location: /<token>/gallery` and the redirect stays inside your share — emitted verbatim it would escape the mount and the token gate would 404 it). External URLs (`http://…`, `https://…`, scheme-relative `//host/…`) and relative paths are never rewritten. *(Mount re-prefix verified statically; needs an OXT pass.)* | — |
| `cors` | `true` adds `Access-Control-Allow-Origin: *` (so other pages/tools may fetch it), and makes an `OPTIONS` preflight to the path answer with the `Access-Control-Allow-*` headers, so even a preflighted cross-origin request (POST+JSON, `PUT`/`DELETE`, custom headers) works. | `false` |
| `headers` | An object of extra response headers. Names are limited to letters/digits/`-`; CR/LF/control bytes are stripped from values; framing/server-owned headers (`Content-Length`, `Connection`, `Content-Type`, `Location`, `Date`, …) can't be overridden. | — |

A route needs exactly one of `body` (default), `file`, or `redirect`; if more than one is
present the precedence is `redirect` > `file` > `body`.

## Path parameters (`:name`)

A `path` segment written `:name` matches **any one** URL segment and captures it, so one
route can serve a family of URLs:

```json
{
  "method": "GET",
  "path": "/api/greet/:name",
  "type": "application/json; charset=utf-8",
  "template": true,
  "body": "{\"hello\":\"{{param.name}}\"}",
  "cors": true
}
```

`GET /api/greet/world` answers `{"hello":"world"}`. The rules, all enforced when the file
is loaded (an invalid pattern is skipped, like any other invalid route):

- **The first segment must be literal.** `/api/:name` is fine; `/:name` is refused — a
  leading parameter would match *every* top-level path, including the reserved `/_qs/`
  and `/_edit/` namespaces. With the first segment static (and reserved prefixes already
  refused literally), no pattern can ever reach a reserved path — by construction, and
  the request-time matcher independently refuses reserved paths as a backstop.
- **A parameter matches exactly one non-empty segment.** `/api/files/:name` matches
  `/api/files/readme.txt`, not `/api/files/` and not `/api/files/a/b`. An encoded slash
  (`%2F`) is decoded *before* routing, so it splits into real segments — a parameter can
  never smuggle one. A trailing `/` in the pattern is significant and must be present in
  the request too.
- **Names are `A–Z a–z 0–9 _`, non-empty, and unique** within one pattern.
- **Captures reach only a templated `body`,** as `{{param.name}}` — escaped for the
  response type exactly like `{{query.NAME}}` (a parameter value is visitor-chosen input).
  Parameters are **never** substituted into a `file` target, a `redirect` location, or
  header values — those stay exactly as declared.
- **Precedence is deterministic:** an exact route on the literal path always wins over a
  pattern; among matching patterns the one with the *fewest* parameters (most literal)
  wins, ties broken by comparing the route keys — never by table order.
- **`Allow`, `405`, and CORS see patterns.** An `OPTIONS` (or an unsupported method) on
  `/api/greet/world` derives its `Allow` from every route *matching* that path, patterns
  included, and a `cors: true` param route answers the preflight for its matching paths
  just like an exact route does.
- **Big/streamed responses:** a parameterised route can also be a `file` route (the
  static file target streams Range-aware through the normal pump, with the route's
  headers). Inline bodies stay capped at 64 KB — point at a file for anything larger.
- `GET /_qs/routes` lists a pattern route with its literal pattern text
  (e.g. `/api/greet/:name`).

## Template placeholders (`{{...}}`)

Set `"template": true` and a `body` can reflect a little request context. Each placeholder is
replaced with its value **escaped for the response `type`**: JSON-escaped for a `json` type, and
**HTML-escaped for everything else** (HTML, SVG, XML, JavaScript, plain text, …). That
default-deny escaping means a visitor-supplied value can never inject markup — a reflected
`<script>` in, say, an `image/svg+xml` body comes out inert as `&lt;script&gt;`. Unknown
placeholders become empty.

> **Footgun:** escaping makes a value safe as *text* inside JSON/HTML/SVG. It does **not** make a
> value safe when you drop it into a **URL** (`href="{{query.u}}"` — a `javascript:` URL still
> works) or into a **code position** (`cb({{query.q}})` without quotes). Reflect values into text
> or quoted-string positions, not into code or bare URLs.

| Placeholder | Becomes |
|---|---|
| `{{method}}` | The request method (`GET`, `POST`, …) |
| `{{path}}` | The request path |
| `{{query.NAME}}` | The `NAME` query-string parameter (URL-decoded), e.g. `{{query.msg}}` |
| `{{param.NAME}}` | The `:NAME` path-parameter capture (see "Path parameters"), e.g. `{{param.name}}`. Empty when the route has no such parameter. |
| `{{now}}` | Current time in whole seconds (Unix epoch) |
| `{{date}}` | Current time as an HTTP-date (`Sun, 06 Jul 2026 12:00:00 GMT`) |

There is still **no scripting** — templating only substitutes these fixed, escaped values.

## Good to know

- **What it's for:** mock/JSON APIs, config endpoints, CORS-enabled data, files under friendlier
  URLs, tiny reflected/echo endpoints, redirects and short-links — anything a *canned* or
  *file-backed* response covers. For genuinely dynamic logic the stack still offers
  `qsHttpRoute "GET","/api/thing","myHandler"` → `qsHttpReply` inside the script.
- **Reserved:** paths under `/_qs/` (the host's own info/transparency routes) and `/_edit/`
  (the LAN editor) can never be overridden, and an invalid route is skipped, not fatal.
- **Dotfiles stay hidden:** a `file` route can't point at a hidden dot-file (`.env`, `.git/…`,
  `.qsroutes.json` itself) — those are invisible over both transports, exactly as they are to
  the static file paths. Such a route is skipped.
- **See what's active:** `GET /_qs/routes` returns a read-only JSON list of the custom routes the
  served folder loaded (method + path + kind only — never the file target, the redirect target, or
  any disk path), so you can confirm your `.qsroutes.json` was picked up.
- **Reload:** the file is read when you start sharing the folder. If you edit it while
  sharing, stop and re-share (or share it again) to pick up the changes.
- **Limits:** up to 100 routes per file; the config file is read up to 256 KB; each inline
  body is capped at 64 KB and a templated body renders up to 512 KB. A malformed file disables
  *only* custom routes, never the server.
- **Privacy:** these routes are served over whichever transport you picked, with the same
  honesty as everything else — a web link exposes your IP; Tor hides both ends. Nothing here
  changes that (see `what-it-hides.md`).
