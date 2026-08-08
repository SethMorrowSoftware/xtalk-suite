# Third-party licenses - coinxt

The coinxt shim (`native/coinxt.c`), the LCB binding, the tools and the docs are
MIT (see [LICENSE](LICENSE)). The committed per-platform binaries under
`src/code/` statically link a vendored subset of **trezor-crypto**, and the
license texts that subset carries are reproduced here in full, as binary
distribution requires.

## Why this file exists, and why "trezor-crypto is MIT" was not enough

trezor-crypto as a project is MIT, and `native/vendor/LICENSE` is that MIT text.
But the `crypto/` directory vendors third-party implementations that keep their
own terms, and **four of the licenses below are not that MIT license**. Two of
them came in with the phase-1 hash surface and were already being shipped under
an attribution that did not mention them:

- **`sha2.c` / `sha2.h` is BSD-3-Clause**, and its clause 2 is the one that
  actually binds us: a binary redistribution must reproduce the notice "in the
  documentation and/or other materials provided with the distribution". coinxt
  commits built libraries, so that is exactly what coinxt does, and this file is
  the material that carries the notice.
- **`ripemd160.c` is public domain**, **`blake256.c` is CC0**, and **`blake2b.c`
  is tri-licensed** (CC0, the OpenSSL license, or Apache-2.0, at the user's
  option). None of these impose an attribution requirement; they are recorded
  anyway, because "we checked and it is unrestricted" and "we never looked" are
  the same silence otherwise.
- **`groestl.c` and its headers are MIT but under a different copyright holder**
  (Projet RNRT SAPHIR, not the trezor authors), so the single MIT text in
  `native/vendor/LICENSE` does not by itself carry that notice.

Everything here is permissive and compatible with shipping coinxt under MIT.
Nothing below restricts commercial use, and no file is copyleft.

**For `blake2b.c` this project elects CC0**, which is the option with no
downstream obligations; the Apache-2.0 and OpenSSL alternatives are not taken, so
no `NOTICE` file is required.

> Note on what is actually reachable. `blake2b.c`, `blake256.c` and `groestl.c`
> are linked because upstream's `hasher.c` dispatch table references them, not
> because coinxt calls them: coinxt uses SHA-2, SHA-3/Keccak-256, RIPEMD-160,
> HMAC, PBKDF2 and secp256k1. They are compiled in and therefore redistributed,
> which is what creates the obligation, so they are listed. See
> `native/vendor/VENDOR.md` for why the closure includes them.

## The per-file map

| File(s) | License | Copyright |
|---|---|---|
| `ecdsa.*`, `bignum.*`, `secp256k1.*`, `rfc6979.*`, `hmac.*`, `hmac_drbg.*`, `pbkdf2.*`, `base58.*`, `bip32.h`, `rand.h`, `script.h`, `options.h`, `memzero.*`, `byte_order.h`, `ed25519-donna/ed25519.h` | MIT (trezor-crypto) | Tomas Dzetkulic, Pavol Rusnak, Jochen Hoenicke, Alex Beregszaszi, Andrew R. Kozlik and contributors |
| `hasher.*` | MIT (trezor-crypto) | Saleem Rashid |
| `address.*` | MIT | Daira Hopwood |
| `sha2.c`, `sha2.h` | **BSD-3-Clause** | Aaron D. Gifford (2000-2001), Pavol Rusnak (2013-2014) |
| `sha3.c`, `sha3.h` | MIT (RHash) | Aleksey Kravchenko (2013) |
| `ripemd160.c`, `ripemd160.h` | **Public domain** | Dwayne C. Litzenberger (2008); changes by Pieter Wuille (2012) |
| `blake256.c`, `blake256.h` | **CC0-1.0** | Jean-Philippe Aumasson (2012) |
| `blake2b.c`, `blake2b.h`, `blake2_common.h` | **CC0-1.0 / OpenSSL / Apache-2.0, at your option** (coinxt elects CC0) | Samuel Neves (2012) |
| `groestl.c`, `groestl.h`, `groestl_internal.h` | MIT | Projet RNRT SAPHIR (2007-2010); trezor adaptation by Yura Pakhuchiy |

Every file also carries its own license header verbatim, because the vendored
sources are copied byte-identical from upstream and are never edited in place
(`native/vendor/VENDOR.md`). This file does not replace those headers; it
reproduces the texts that have distribution requirements so they travel with the
built library and not only with the source.

-------------------------------------------------------------------------------
## trezor-crypto (MIT)

The full text is in [`native/vendor/LICENSE`](native/vendor/LICENSE) and covers
every file marked "MIT (trezor-crypto)" above.

-------------------------------------------------------------------------------
## SHA-2 (`sha2.c`, `sha2.h`) - BSD-3-Clause

Copyright (c) 2000-2001 Aaron D. Gifford
Copyright (c) 2013-2014 Pavol Rusnak
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTOR(S) ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-------------------------------------------------------------------------------
## SHA-3 / Keccak (`sha3.c`, `sha3.h`) - MIT (RHash)

Copyright: 2013 Aleksey Kravchenko <rhash.admin@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Use this program at your own risk!

-------------------------------------------------------------------------------
## RIPEMD-160 (`ripemd160.c`, `ripemd160.h`) - public domain

Written in 2008 by Dwayne C. Litzenberger <dlitz@dlitz.net>. Adapted by Pieter
Wuille in 2012; all changes are in the public domain.

The contents of this file are dedicated to the public domain. To the extent that dedication to the public domain is not available, everyone is granted a worldwide, perpetual, royalty-free, non-exclusive license to exercise all rights associated with the contents of this file for any purpose whatsoever. No rights are reserved.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-------------------------------------------------------------------------------
## BLAKE-256 (`blake256.c`, `blake256.h`) - CC0-1.0

BLAKE reference C implementation.

Copyright (c) 2012 Jean-Philippe Aumasson <jeanphilippe.aumasson@gmail.com>

To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to this software to the public domain worldwide. This software is distributed without any warranty.

You should have received a copy of the CC0 Public Domain Dedication along with this software. If not, see <http://creativecommons.org/publicdomain/zero/1.0/>.

-------------------------------------------------------------------------------
## BLAKE2b (`blake2b.c`, `blake2b.h`, `blake2_common.h`) - CC0-1.0, as elected

BLAKE2 reference source code package - reference C implementations.

Copyright 2012, Samuel Neves <sneves@dei.uc.pt>. You may use this under the terms of the CC0, the OpenSSL Licence, or the Apache Public License 2.0, at your option. The terms of these licenses can be found at:

- CC0 1.0 Universal : http://creativecommons.org/publicdomain/zero/1.0
- OpenSSL license   : https://www.openssl.org/source/license.html
- Apache 2.0        : http://www.apache.org/licenses/LICENSE-2.0

**coinxt elects CC0 1.0 Universal**, under which no attribution or NOTICE file is
required. This entry is a record of that election, not an obligation.

-------------------------------------------------------------------------------
## Groestl (`groestl.c`, `groestl.h`, `groestl_internal.h`) - MIT

Groestl hash, from https://github.com/Groestlcoin/vanitygen. Trezor adaptation by
Yura Pakhuchiy <pakhuchiy@gmail.com>.

Copyright (c) 2007-2010 Projet RNRT SAPHIR

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
