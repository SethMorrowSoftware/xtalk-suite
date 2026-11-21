# Third-party licenses

oscxt is MIT-licensed (see [LICENSE](LICENSE)). The native library it ships
(`oscxt.so`, `oscxt.dll`, `oscxt.dylib`) contains one third-party component.

## tinyosc (ISC), bundled

A single-file OSC codec by Martin Roth, vendored at
[`src/third_party/tinyosc/`](src/third_party/tinyosc/). Its local changes are
each marked `ShowControl:` in the source: every unaligned read goes through
`memcpy`, so it is alignment-safe on every target. The shim never decodes
through tinyosc's cursor (`src/osc_shim.c` says why). Upstream:
https://github.com/mhroth/tinyosc

```
Copyright (c) 2015, Martin Roth <mhroth@gmail.com>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```
