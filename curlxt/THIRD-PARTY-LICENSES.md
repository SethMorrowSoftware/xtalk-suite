# Third-party licenses - curlxt

The curlxt shim, LCB binding and script libraries are MIT (see LICENSE).

curlxt's committed binaries statically link the libraries below. Each license is
reproduced verbatim from the pinned release's source archive.

## libcurl 8.22.0 (the curl license, MIT-style)

```
COPYRIGHT AND PERMISSION NOTICE

Copyright (c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many
contributors, see the THANKS file.

All rights reserved.

Permission to use, copy, modify, and distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright
notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD PARTY RIGHTS. IN
NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall not
be used in advertising or otherwise to promote the sale, use or other dealings
in this Software without prior written authorization of the copyright holder.
```

## libssh2 1.11.1 (BSD 3-clause)

```
/* Copyright (C) 2004-2007 Sara Golemon <sarag@libssh2.org>
 * Copyright (C) 2005,2006 Mikhail Gusarov <dottedmag@dottedmag.net>
 * Copyright (C) 2006-2007 The Written Word, Inc.
 * Copyright (C) 2007 Eli Fant <elifantu@mail.ru>
 * Copyright (C) 2009-2023 Daniel Stenberg
 * Copyright (C) 2008, 2009 Simon Josefsson
 * Copyright (C) 2000 Markus Friedl
 * Copyright (C) 2015 Microsoft Corp.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms,
 * with or without modification, are permitted provided
 * that the following conditions are met:
 *
 *   Redistributions of source code must retain the above
 *   copyright notice, this list of conditions and the
 *   following disclaimer.
 *
 *   Redistributions in binary form must reproduce the above
 *   copyright notice, this list of conditions and the following
 *   disclaimer in the documentation and/or other materials
 *   provided with the distribution.
 *
 *   Neither the name of the copyright holder nor the names
 *   of any other contributors may be used to endorse or
 *   promote products derived from this software without
 *   specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 */
```

## OpenSSL 3.5.9 (Apache License 2.0; in some of the release libraries)

The release libraries for 64-bit Linux (`x86_64-linux`, `arm64-linux`) and macOS
(`universal-mac`) link OpenSSL 3.5.9 statically, built from its pinned release tarball by
the suite's `release-binaries.yml`. OpenSSL is Copyright (c) 1998-2025 The OpenSSL Project
Authors and Copyright (c) 1995-1998 Eric A. Young, Tim J. Hudson, and is licensed under
the Apache License 2.0; its full text, OpenSSL's own `LICENSE.txt` unchanged, is in
`OpenSSL-LICENSE.txt` alongside this file, and a redistribution of those libraries
must carry it.
The 32-bit Linux library (`x86-linux`) links the system's OpenSSL 3 (`libssl.so.3`)
dynamically and bundles none; the Windows libraries use the operating system's Schannel
and link no OpenSSL. A local build links whatever OpenSSL CMake finds.
