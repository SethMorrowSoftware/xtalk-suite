# Third-party licenses

xlsxt's native library is ONE file that holds three libraries, built from
source at pinned commits (`CMakeLists.txt`; `tools/check-pins.py` holds this
file to it). xlsxt's own code is MIT (see `LICENSE`). Anyone who passes the
library on, alone or inside an application, passes these notices on with it.

| Library | Version | Commit | License |
|---|---|---|---|
| libxlsxwriter | libxlsxwriter 1.2.4 | `2894634d65cee6021901a165bfc2bb0fad6da193` | BSD 2-Clause |
| zlib, with `contrib/minizip` | zlib 1.4 | `99623ef7097352da7993ba614161fd6a311e046e` | zlib |
| Expat | Expat 2.10.0 | `a70841d9ffa64ddde29ab824ed6305035ebe4c47` | MIT |

Inside libxlsxwriter's source tree are smaller pieces by other authors. What
of them is compiled into xlsxt:

| Piece | Used | License |
|---|---|---|
| `queue.h`, `tree.h` (FreeBSD) | yes: libxlsxwriter's lists and trees | BSD |
| tmpfileplus (David Ireland) | yes: its temporary files | Mozilla Public License 2.0 |
| MD5 (Alexander Peslyak, Openwall) | yes: to find one picture used twice | public domain |
| minizip, the 2010 copy | NO: zlib 1.4's own `contrib/minizip` is used instead | (zlib) |
| emyg_dtoa (Doug Currie, Milo Yip) | NO code: only the one-line declaration in `emyg_dtoa.h`; the function is xlsxt's own | (MIT) |

## libxlsxwriter

https://github.com/jmcnamara/libxlsxwriter

    Copyright 2014-2026, John McNamara <jmcnamara@cpan.org>
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:

    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
    IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
    THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
    PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
    CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
    EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
    PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

    The views and conclusions contained in the software and documentation are
    those of the authors and should not be interpreted as representing
    official policies, either expressed or implied, of the FreeBSD Project.

### queue.h, from FreeBSD

    Copyright (c) 1991, 1993
     The Regents of the University of California.  All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
    4. Neither the name of the University nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
    OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
    SUCH DAMAGE.

### tree.h, from FreeBSD

    Copyright 2002 Niels Provos <provos@citi.umich.edu>
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
    THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### tmpfileplus

`third_party/tmpfileplus/tmpfileplus.c` and `tmpfileplus.h`, unmodified, as
libxlsxwriter 1.2.4 carries them:

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.

    Copyright (c) 2012-16 David Ireland, DI Management Services Pty Ltd
    <http://www.di-mgt.com.au/contact/>.

The Mozilla Public License covers those two files and asks that their source
stay available to whoever receives the library. It is: in libxlsxwriter's
repository, at the commit in the table above, under
`third_party/tmpfileplus/`. The license does not reach the rest of xlsxt or
an application that uses it.

### MD5

`third_party/md5/md5.c` and `md5.h`:

    This software was written by Alexander Peslyak in 2001.  No copyright is
    claimed, and the software is hereby placed in the public domain.
    In case this attempt to disclaim copyright and place the software in the
    public domain is deemed null and void, then the software is
    Copyright (c) 2001 Alexander Peslyak and it is hereby released to the
    general public under the following terms:

    Redistribution and use in source and binary forms, with or without
    modification, are permitted.

    There's ABSOLUTELY NO WARRANTY, express or implied.

## zlib

https://github.com/madler/zlib

    Copyright notice:

     (C) 1995-2026 Jean-loup Gailly and Mark Adler

      This software is provided 'as-is', without any express or implied
      warranty.  In no event will the authors be held liable for any damages
      arising from the use of this software.

      Permission is granted to anyone to use this software for any purpose,
      including commercial applications, and to alter it and redistribute it
      freely, subject to the following restrictions:

      1. The origin of this software must not be misrepresented; you must not
         claim that you wrote the original software. If you use this software
         in a product, an acknowledgment in the product documentation would be
         appreciated but is not required.
      2. Altered source versions must be plainly marked as such, and must not be
         misrepresented as being the original software.
      3. This notice may not be removed or altered from any source distribution.

      Jean-loup Gailly        Mark Adler
      jloup@gzip.org          madler@alumni.caltech.edu

minizip (`contrib/minizip`, Copyright (C) 1998-2026 Gilles Vollant, with
Zip64 support Copyright (C) 2009-2010 Mathias Svensson) is distributed under
the same terms.

## Expat

https://github.com/libexpat/libexpat

    Copyright (c) 1998-2000 Thai Open Source Software Center Ltd and Clark Cooper
    Copyright (c) 2001-2025 Expat maintainers

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
