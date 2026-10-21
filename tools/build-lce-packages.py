#!/usr/bin/env python3
"""build-lce-packages.py - the suite's extensions as installable .lce packages.

WHY THIS EXISTS
    Until 2026-10-21 a user who wanted SodiumXT (or any member) in an IDE
    other than OXT-Beyond had to open the member's .lcb in the Extension
    Builder, press Package and install what it made - and Package passes
    lc-compile -Werror, which refuses box2dxt.lcb outright (a digit in the
    namespace component of org.openxtalk.box2dxt is a warning). This tool
    makes the finished packages instead: one .lce per extension, which the
    Extension Manager of any IDE built on LiveCode Community 9 installs
    (Tools > Extension Manager > + ): LiveCode Community 9.6.3, OpenXTalk,
    HyperXTalk and OXT-Beyond itself. .github/workflows/lce-packages.yml
    runs it, uploads the packages as the run's artifact and attaches them
    to a GitHub release when one is asked for.

    The packages hold what OXT-Beyond's built-in copies of the same
    extensions hold (its tools/oxt/xtalk_extensions.py and
    tools/oxt/xtalk-extensions.json at v0.2.7-rc.6, whose rules this file
    follows and cites as "Beyond's builder"), so an extension behaves the
    same installed from a package as built in:

      LCB  <source>.lcb, module.lcm and manifest.xml from lc-compile (run
           in the package folder with relative paths, because module.lcm
           embeds the source path as given; the interface goes to a scratch
           folder; no -Werror, see above), code/<platform-id>/<library> for
           every committed platform (the IDE maps the one for its platform
           into revLibraryMapping, the standalone builder copies the one for
           the target), the Visual C++ runtime DLLs a Windows library
           imports (enetxt, box2dxt; below), licenses/.
      LCS  <stack>.livecodescript (a `script "<stack>"` first line added
           where the file has none, and an extensionInitialize /
           extensionFinalize pair appended, because the IDE loads a script
           library by sending it extensionInitialize and without a handler
           it would sit in memory outside the message path), manifest.xml,
           licenses/.
      both api.lcdoc, written by tools/lce-engine-check.lc with Beyond's
           docs parser (revDocsParser): an INSTALLED IDE never generates it
           (revideextensionlibrary, revEnvironmentIsInstalled), and without
           it the Dictionary has no entry for the extension.

    A package is the same bytes for the same inputs: files in order, one
    fixed time, manifest.xml first (the Extension Manager refuses a zip
    whose first entry is a folder: extensionValidateLCEPackage).

THE VISUAL C++ RUNTIME
    enetxt.dll imports MSVCP140.dll, VCRUNTIME140.dll and (x86-64)
    VCRUNTIME140_1.dll, box2dxt.dll VCRUNTIME140.dll: those two members
    build with the dynamic runtime, and a PC without the Visual C++
    Redistributable lacks the DLLs, so the library would not load. As in
    Beyond's builder, every DLL a Windows library imports that is neither a
    Windows system DLL nor next to it is copied from --vc-runtime (a folder
    with x64/ and x86/, the CRT folders of Visual Studio's redistributable;
    the workflow's vc-runtime job makes it on windows-2022) and checked
    against VC_RUNTIME_PINS, the pins Beyond's builder uses. Without
    --vc-runtime the packages are built WITHOUT the runtime and say so
    loudly; --release refuses that, and refuses an unpinned copy.

USAGE
    python3 tools/build-lce-packages.py table
        the gate: every PACKAGES row matches the tree (files present,
        versions read, script headers agree, every Windows library's
        non-system imports known). No compiler, no network.
    python3 tools/build-lce-packages.py stage --bin DIR --out STAGE
            [--vc-runtime DIR] [--openssl-licence FILE] [--release]
        one folder per package in STAGE; DIR holds lc-compile and
        modules/lci (OXT-Beyond's <platform>-bin folder, or an IDE's).
    python3 tools/build-lce-packages.py pack STAGE --out DIR [--release]
        STAGE's folders zipped as DIR/<file>-<version>.lce, plus SHA256SUMS
        and packages.tsv (what tools/lce-engine-check.lc probes).
    python3 tools/build-lce-packages.py check PACKAGE.lce ...
        each package as the Extension Manager checks it, plus the layout
        rules above.
    python3 tools/build-lce-packages.py list
        the packages, one per line.

    tools/test-build-lce-packages.py fixture-proves `table` and `check`.
"""

import argparse
import collections
import hashlib
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The platforms the members commit libraries for (src/code/<id>/), in
# Beyond's builder's order
PLATFORMS = ('x86_64-win32', 'x86-win32', 'x86_64-linux', 'x86-linux', 'arm64-linux', 'universal-mac')
WINDOWS = collections.OrderedDict([('x86_64-win32', ('x64', 0x8664)), ('x86-win32', ('x86', 0x14c))])

# DLLs every supported Windows has (Beyond's builder's SYSTEM_DLLS):
# api-ms-win-crt-* is the Universal CRT, part of Windows 10 and later;
# msvcrt.dll is the system C runtime MinGW builds (coinxt) use
SYSTEM_DLLS = frozenset(('kernel32.dll', 'user32.dll', 'advapi32.dll', 'ws2_32.dll', 'winmm.dll',
                         'crypt32.dll', 'bcrypt.dll', 'iphlpapi.dll', 'mswsock.dll', 'msvcrt.dll'))
SYSTEM_DLL_PREFIXES = ('api-ms-win-crt-',)

# The runtime DLLs copied next to the libraries that import them, as
# Beyond's xtalk-extensions.json "vc_runtime" pins them: Visual Studio
# 2022 17.14's redistributable 14.44.35112 (file version 14.44.35211.0),
# the one on the windows-2022 runner image
VC_RUNTIME_REDIST = '14.44.35112'
VC_RUNTIME_PINS = {
    'x86_64-win32': {
        'msvcp140.dll': ('0f885b509a685d2bbfa652fed26b5fb31d88fbdab0a978c641d1c7b8aa460aa9', 557728),
        'vcruntime140.dll': ('d5e4d9a3e835fa679450145d6a7d94e36573a509317111904d9b3712c30d9066', 124544),
        'vcruntime140_1.dll': ('1f2d41c4aa5db0bc33ebf7b66d72943a817d7ce6cbe880502a9403823633093f', 49792),
    },
    'x86-win32': {
        'msvcp140.dll': ('97e71a3c697fb1ab3af777db39009e4602525e8c3aff0837ecc7031cba188165', 447616),
        'vcruntime140.dll': ('a9d7732a3c3de09f0601a7fa2555093dcb49f08e2fc62a86091461f0f38393ed', 91216),
    },
}
VC_RUNTIME_NOTICE = 'Microsoft-Visual-C++-Runtime.txt'

# OpenSSL 3 is statically linked into torrentxt and into the Windows and
# macOS datachannelxt libraries; neither member's licence files carry its
# text, so the packages take OpenSSL's own (openssl-3.6.4's LICENSE.txt,
# the blob Beyond's builder pins)
OPENSSL_LICENCE_URL = ('https://raw.githubusercontent.com/openssl/openssl/'
                       'd3c1b1169b3569ff3069e5b399f47b2b28e03d79/LICENSE.txt')
OPENSSL_LICENCE_SHA256 = '7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a'
OPENSSL = '@openssl'

LICENCE_DIR = 'licenses'
ZIP_TIME = (2026, 1, 1, 0, 0, 0)

# Where each member keeps its version: the .lcb metadata, or a script
# library's version constant (Beyond's builder's version_from)
LCB_VERSION = r'^\s*metadata\s+version\s+is\s+"([^"]+)"'
VERSION_FROM = {
    'sodiumxt': ('src/sodium.lcb', LCB_VERSION),
    'torrentxt': ('src/torrent.lcb', LCB_VERSION),
    'enetxt': ('src/enet.lcb', LCB_VERSION),
    'datachannelxt': ('src/datachannel.lcb', LCB_VERSION),
    'box2dxt': ('src/box2dxt.lcb', LCB_VERSION),
    'coinxt': ('src/coinxt.lcb', LCB_VERSION),
    'onionxt': ('src/onionxt.livecodescript', r'^\s*constant\s+kOxVersion\s*=\s*"([^"]+)"'),
    'nostrxt': ('src/nostrxt.livecodescript', r'^\s*constant\s+kNxVersion\s*=\s*"([^"]+)"'),
}

# A member's licence files: (path in the member or OPENSSL, name in
# licenses/ or None for its own, "leading-comment" when only the comment at
# the top of the file is shipped: the notices of sources compiled into the
# libraries)
LICENCES = {
    'sodiumxt': [('LICENSE', None, None), ('src/vendor/LICENSE', 'trezor-crypto-LICENSE', None),
                 ('src/vendor/sha3.c', 'RHash-SHA3-NOTICE.txt', 'leading-comment')],
    'torrentxt': [('LICENSE', None, None), ('THIRD-PARTY-LICENSES.md', None, None),
                  (OPENSSL, 'OpenSSL-LICENSE.txt', None)],
    'enetxt': [('LICENSE', None, None), ('THIRD-PARTY-LICENSES.md', None, None)],
    'datachannelxt': [('LICENSE', None, None), ('THIRD-PARTY-LICENSES.md', None, None),
                      (OPENSSL, 'OpenSSL-LICENSE.txt', None)],
    'box2dxt': [('LICENSE', None, None)],
    'coinxt': [('LICENSE', None, None), ('THIRD-PARTY-LICENSES.md', None, None),
               ('native/vendor/LICENSE', 'trezor-crypto-LICENSE', None),
               ('native/vendor/address.c', 'trezor-crypto-address-NOTICE.txt', 'leading-comment'),
               ('native/vendor/hasher.c', 'trezor-crypto-hasher-NOTICE.txt', 'leading-comment')],
    'onionxt': [('LICENSE', None, None)],
    'nostrxt': [('LICENSE', None, None)],
}


def P(kind, member, ident, main, file, probe, expect, **extra):
    row = collections.OrderedDict([('kind', kind), ('member', member), ('id', ident), ('main', main),
                                   ('file', file), ('probe', probe), ('expect', expect)])
    row.update(extra)
    return row


# THE TABLE: one row per package, in load order (a package after the ones it
# requires). id, main, stack, title, author, requires, probe and expect are
# Beyond's builder's, so a package and the built-in copy are one extension;
# "file" names the .lce (the Extension Manager reads the id and version from
# the manifest and of the file name only that it ends in .lce). A probe is an
# expression tools/lce-engine-check.lc evaluates after loading the package,
# and expect a regular expression its value must match.
PACKAGES = [
    P('lcb', 'sodiumxt', 'org.openxtalk.library.sodium', 'src/sodium.lcb', 'sodiumxt',
      'sxVersion()', '^SodiumXT [0-9]'),
    # TorrentXT has no version handler; btLastError() calls into the library
    # without starting a session
    P('lcb', 'torrentxt', 'org.openxtalk.library.torrent', 'src/torrent.lcb', 'torrentxt',
      'btLastError()', '^$'),
    P('lcs', 'torrentxt', 'torrentHelpers', 'examples/torrent-helpers.livecodescript', 'torrentxt-helpers',
      'btFormatBytes(2048)', r'^2(\.0+)? KiB$', stack='torrentHelpers', title='TorrentXT helpers',
      author='Seth Morrow Software', requires=['org.openxtalk.library.torrent']),
    P('lcb', 'enetxt', 'org.openxtalk.library.enet', 'src/enet.lcb', 'enetxt',
      'enLibraryVersion()', '^enet [0-9]'),
    P('lcs', 'enetxt', 'enetHelpers', 'examples/enet-helpers.livecodescript', 'enetxt-helpers',
      'enFormatBytes(2048)', r'^2(\.0+)? KiB$', stack='enetHelpers', title='enetxt helpers',
      author='Seth Morrow Software', requires=['org.openxtalk.library.enet']),
    P('lcb', 'datachannelxt', 'org.openxtalk.library.datachannel', 'src/datachannel.lcb', 'datachannelxt',
      'dcLibraryVersion()', '^libdatachannel v?[0-9]'),
    P('lcs', 'datachannelxt', 'dataChannelHelpers', 'examples/datachannel-helpers.livecodescript',
      'datachannelxt-helpers', 'dcFormatBytes(2048)', r'^2(\.0+)? KiB$', stack='dataChannelHelpers',
      title='DataChannelXT helpers', author='Seth Morrow Software',
      requires=['org.openxtalk.library.datachannel']),
    P('lcb', 'box2dxt', 'org.openxtalk.box2dxt', 'src/box2dxt.lcb', 'box2dxt', 'b2Version()', '^4$'),
    P('lcs', 'box2dxt', 'box2dxt-kit', 'src/box2dxt-kit.livecodescript', 'box2dxt-kit',
      'b2kVersion()', '^4$', stack='box2dxt-kit', title='Box2Dxt Kit', author='Box2Dxt contributors',
      requires=['org.openxtalk.box2dxt']),
    P('lcb', 'coinxt', 'org.openxtalk.library.coin', 'src/coinxt.lcb', 'coinxt',
      'cxKeccak256Len()', '^32$'),
    P('lcs', 'coinxt', 'coinxt', 'src/coinxt.livecodescript', 'coinxt-script',
      'cxHexEncode(numToByte(0))', '^00$', stack='coinxt', title='CoinXT script layer',
      author='Seth Morrow Software', requires=['org.openxtalk.library.coin']),
    P('lcs', 'onionxt', 'onionxt', 'src/onionxt.livecodescript', 'onionxt',
      'oxVersion()', r'^[0-9]+\.[0-9]+', stack='onionxt', title='OnionXT', author='Seth Morrow Software',
      requires=[]),
    # onion-httpd has only commands, so the probe looks for one in the
    # stack's handler list
    P('lcs', 'onionxt', 'onion-httpd', 'src/onion-httpd.livecodescript', 'onionxt-httpd',
      '"oxhServe" is among the words of the revAvailableHandlers of stack "onion-httpd"', '^true$',
      stack='onion-httpd', title='OnionXT HTTP server', author='Seth Morrow Software', requires=['onionxt']),
    P('lcs', 'nostrxt', 'nostrxt', 'src/nostrxt.livecodescript', 'nostrxt',
      'nxVersion()', '^NostrXT [0-9]', stack='nostrxt', title='NostrXT', author='Seth Morrow Software',
      requires=[]),
    P('lcs', 'nostrxt', 'nostr-relay', 'src/nostr-relay.livecodescript', 'nostrxt-relay',
      'nxrVersion()', '^NostrXT relay NostrXT [0-9]', stack='nostr-relay', title='NostrXT relay client',
      author='Seth Morrow Software', requires=['nostrxt']),
]

# Appended to a script library that handles neither message itself:
# Beyond's builder's LCS_WRAPPER, with this tool named instead. The guard
# keeps a second extensionInitialize from inserting the script twice;
# appended at the END so that no declaration moves (script-level
# declarations resolve by position, engine note 1.2).
LCS_WRAPPER = '''
-- xTalk Suite: added when this library was packaged as an extension (see
-- tools/build-lce-packages.py in the xtalk-suite repository). The IDE
-- sends extensionInitialize to a script library extension when it loads it
-- and extensionFinalize when it unloads it.
on extensionInitialize
   if the target is not me then
      pass extensionInitialize
   end if

   if the long id of me is not among the lines of the backScripts then
      insert the script of me into back
   end if

   if the environment contains "development" then
      set the _ideoverride of me to true
   end if
end extensionInitialize

on extensionFinalize
   if the target is not me then
      pass extensionFinalize
   end if

   remove the script of me from back
end extensionFinalize
'''


class Problem(Exception):
    pass


def log(msg=''):
    print(msg, flush=True)


def member_path(member, rel):
    return os.path.join(ROOT, member, *rel.split('/'))


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def member_version(member):
    rel, pattern = VERSION_FROM[member]
    text = read(member_path(member, rel)).decode('utf-8', 'replace')
    found = re.findall(pattern, text, re.M)
    if len(found) != 1:
        raise Problem('%s/%s: %d version declarations (%s), expected one' % (member, rel, len(found), pattern))
    if not re.match(r'^[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.-]+)?$', found[0]):
        raise Problem('%s/%s: version %r is not a version' % (member, rel, found[0]))
    return found[0]


def lcs_header(data):
    """The stack name of a `script "<name>"` first line, or None."""
    text = data.decode('utf-8', 'replace').lstrip('﻿')
    first = text.split('\n', 1)[0].strip()
    m = re.match(r'^script\s+"([^"]+)"\s*$', first, re.I)
    return m.group(1) if m else None


def lcb_module_id(text):
    m = re.search(r'^\s*(?:library|widget|module)\s+([A-Za-z0-9_.]+)\s*$', text, re.M)
    return m.group(1) if m else None


def libraries(row):
    """[(platform id, path on disk)] of an LCB row's committed libraries."""
    code = member_path(row['member'], 'src/code')
    found = []
    for platform in PLATFORMS:
        folder = os.path.join(code, platform)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.startswith('.'):
                found.append((platform, os.path.join(folder, name)))
    return found


# --- PE imports (only what the runtime check needs) -------------------------

def pe_machine_and_imports(data, what):
    """(machine, [imported DLL names]) of a PE image."""
    try:
        if data[:2] != b'MZ':
            raise Problem('%s: not a PE image' % what)
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        if data[pe:pe + 4] != b'PE\0\0':
            raise Problem('%s: no PE signature' % what)
        machine, nsect = struct.unpack_from('<HH', data, pe + 4)
        opt_size = struct.unpack_from('<H', data, pe + 20)[0]
        opt = pe + 24
        magic = struct.unpack_from('<H', data, opt)[0]
        dirs = opt + (112 if magic == 0x20b else 96)
        imp_rva = struct.unpack_from('<I', data, dirs + 8)[0]
        sections = []
        for i in range(nsect):
            s = opt + opt_size + 40 * i
            vsize, va, rsize, raw = struct.unpack_from('<IIII', data, s + 8)
            sections.append((va, max(vsize, rsize), raw))

        def off(rva):
            for va, size, raw in sections:
                if va <= rva < va + size:
                    return rva - va + raw
            raise Problem('%s: RVA 0x%x is in no section' % (what, rva))

        names = []
        if imp_rva:
            at = off(imp_rva)
            while True:
                name_rva = struct.unpack_from('<I', data, at + 12)[0]
                if name_rva == 0:
                    break
                start = off(name_rva)
                names.append(data[start:data.index(b'\0', start)].decode('ascii'))
                at += 20
        return machine, names
    except (struct.error, ValueError, UnicodeDecodeError) as err:
        raise Problem('%s: unreadable PE image (%s)' % (what, err))


def is_system_dll(name):
    n = name.lower()
    return n in SYSTEM_DLLS or n.startswith(SYSTEM_DLL_PREFIXES)


def runtime_needs(platform, path):
    """The non-system DLLs a Windows library imports, lower-cased."""
    machine, imports = pe_machine_and_imports(read(path), path)
    want = WINDOWS[platform][1]
    if machine != want:
        raise Problem('%s: PE machine 0x%04x, expected 0x%04x for %s' % (path, machine, want, platform))
    return sorted(d.lower() for d in imports if not is_system_dll(d))


# --- table ------------------------------------------------------------------

def check_table():
    """Problems with PACKAGES against the tree; [] when it holds."""
    problems = []
    seen_ids, seen_files, loaded = set(), set(), set()
    for row in PACKAGES:
        where = '%s %s' % (row['member'], row['id'])
        try:
            if row['member'] not in VERSION_FROM or row['member'] not in LICENCES:
                raise Problem('%s: no VERSION_FROM or LICENCES entry for the member' % where)
            member_version(row['member'])
            path = member_path(row['member'], row['main'])
            if not os.path.isfile(path):
                raise Problem('%s: %s/%s is missing' % (where, row['member'], row['main']))
            data = read(path)
            if row['kind'] == 'lcb':
                ident = lcb_module_id(data.decode('utf-8', 'replace'))
                if ident != row['id']:
                    raise Problem('%s: the .lcb declares %r' % (where, ident))
                libs = libraries(row)
                have = {p for p, _ in libs}
                missing = [p for p in PLATFORMS if p not in have]
                if missing:
                    raise Problem('%s: no committed library for %s' % (where, ', '.join(missing)))
                for platform, lib in libs:
                    if platform in WINDOWS:
                        for dll in runtime_needs(platform, lib):
                            if dll not in VC_RUNTIME_PINS[platform]:
                                raise Problem('%s: %s imports %s, which is neither a system DLL nor a pinned '
                                              'runtime DLL' % (where, os.path.relpath(lib, ROOT), dll))
            elif row['kind'] == 'lcs':
                if not re.match(r'^[A-Za-z][A-Za-z0-9-]*$', row['stack']):
                    raise Problem('%s: stack %r must be a name without dots (the IDE loads a script '
                                  'library under the part of its file name before the first dot)'
                                  % (where, row['stack']))
                header = lcs_header(data)
                if header is not None and header.lower() != row['stack'].lower():
                    raise Problem('%s: the script starts with script "%s"' % (where, header))
                for r in row['requires']:
                    if r not in loaded:
                        raise Problem('%s: requires %s, which no earlier row provides' % (where, r))
            else:
                raise Problem('%s: kind %r' % (where, row['kind']))
            for rel, _, _ in LICENCES[row['member']]:
                if rel != OPENSSL and not os.path.isfile(member_path(row['member'], rel)):
                    raise Problem('%s: licence file %s/%s is missing' % (where, row['member'], rel))
            if row['id'] in seen_ids or row['file'] in seen_files:
                raise Problem('%s: id or file name used twice' % where)
            seen_ids.add(row['id'])
            seen_files.add(row['file'])
            loaded.add(row['id'])
        except Problem as err:
            problems.append(str(err))
    return problems


# --- stage ------------------------------------------------------------------

def xml_text(text):
    return (text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;'))


def lcs_manifest(row, version):
    """manifest.xml of a script library, in the element order LiveCode's
    extension-utils writes (extensionGenerateManifestForLCSExtension)."""
    lines = ['<package version="0.0">',
             '  <name>%s</name>' % xml_text(row['stack']),
             '  <title>%s</title>' % xml_text(row['title']),
             '  <author>%s</author>' % xml_text(row['author']),
             '  <version>%s</version>' % xml_text(version),
             '  <type>library</type>',
             '  <license>community</license>']
    for r in row['requires']:
        lines.append('  <requires name="%s"/>' % xml_text(r))
    lines.append('</package>')
    return ('\n'.join(lines) + '\n').encode('utf-8')


def wrap_lcs(data, stack):
    text = data.decode('utf-8', 'replace')
    has_init = re.search(r'^\s*(?:on|command)\s+extensionInitialize\b', text, re.M | re.I) is not None
    has_fini = re.search(r'^\s*(?:on|command)\s+extensionFinalize\b', text, re.M | re.I) is not None
    if has_init != has_fini:
        raise Problem('%s handles only one of extensionInitialize and extensionFinalize' % stack)
    out = data
    if lcs_header(data) is None:
        bom = b'\xef\xbb\xbf' if data.startswith(b'\xef\xbb\xbf') else b''
        out = bom + ('script "%s"\n' % stack).encode('ascii') + data[len(bom):]
    if not has_init:
        if not out.endswith(b'\n'):
            out += b'\n'
        out += LCS_WRAPPER.encode('ascii')
    return out


def leading_comment(data, what):
    text = data.decode('utf-8', 'replace').replace('\r\n', '\n').lstrip()
    if not text.startswith('/*') or '*/' not in text:
        raise Problem('%s does not start with a /* ... */ comment' % what)
    return text[:text.index('*/') + 2] + '\n'


def add_licences(row, folder, openssl):
    dest = os.path.join(folder, LICENCE_DIR)
    os.makedirs(dest, exist_ok=True)
    for rel, name, extract in LICENCES[row['member']]:
        target = os.path.join(dest, name or os.path.basename(rel))
        if os.path.exists(target):
            raise Problem('%s: two licence files are named %s' % (row['member'], os.path.basename(target)))
        if rel == OPENSSL:
            if openssl is None:
                raise Problem('%s needs OpenSSL\'s licence text: pass --openssl-licence (%s)'
                              % (row['member'], OPENSSL_LICENCE_URL))
            shutil.copyfile(openssl, target)
        elif extract == 'leading-comment':
            comment = leading_comment(read(member_path(row['member'], rel)), rel)
            text = ('The licence notice at the top of %s/%s in the xTalk Suite,\n'
                    'which is compiled into the native libraries of this extension:\n\n%s'
                    % (row['member'], rel, comment))
            with open(target, 'wb') as f:
                f.write(text.encode('utf-8'))
        else:
            shutil.copyfile(member_path(row['member'], rel), target)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def add_runtime(folder, platform, vc_runtime, release, warnings):
    """Copy into a package's code/<platform> folder the runtime DLLs its
    library imports. Returns the names copied."""
    copied = []
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith('.dll'):
            continue
        present = {n.lower() for n in os.listdir(folder)}
        for dll in runtime_needs(platform, os.path.join(folder, name)):
            if dll in present:
                continue
            if vc_runtime is None:
                warnings.append('%s/%s needs %s: NOT bundled (no --vc-runtime); it cannot load on a PC '
                                'without the Visual C++ Redistributable' % (platform, name, dll))
                continue
            src_dir = os.path.join(vc_runtime, WINDOWS[platform][0])
            match = [n for n in os.listdir(src_dir) if n.lower() == dll] if os.path.isdir(src_dir) else []
            if not match:
                raise Problem('%s/%s imports %s, which is not in %s' % (platform, name, dll, src_dir))
            target = os.path.join(folder, match[0])
            shutil.copyfile(os.path.join(src_dir, match[0]), target)
            pin = VC_RUNTIME_PINS[platform].get(dll)
            got = (sha256_file(target), os.path.getsize(target))
            if pin != got:
                msg = ('%s/%s from %s is SHA-256 %s, %d bytes; the pin (redistributable %s) is %s'
                       % (platform, match[0], src_dir, got[0], got[1], VC_RUNTIME_REDIST, pin))
                if release:
                    raise Problem(msg)
                warnings.append(msg + ' (kept: not a release build)')
            copied.append(match[0])
            present.add(dll)
    return copied


def write_runtime_notice(folder, copies):
    lines = [
        'Microsoft Visual C++ runtime',
        '',
        'These files of this extension are the Microsoft Visual C++ runtime, copied',
        'from Visual Studio 2022\'s redistributable %s so that the library next to' % VC_RUNTIME_REDIST,
        'them loads on a PC without the Visual C++ Redistributable installed:',
        '',
    ] + ['  ' + c for c in copies] + [
        '',
        'They are Microsoft\'s Distributable Code, under neither this extension\'s',
        'licence nor the GPL: Microsoft\'s terms for Visual Studio 2022 apply',
        '(https://visualstudio.microsoft.com/license-terms/, and the list of files',
        'that may be redistributed at',
        'https://learn.microsoft.com/visualstudio/releases/2022/redistribution).',
        'The latest redistributable is at',
        'https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist',
        '',
    ]
    with open(os.path.join(folder, LICENCE_DIR, VC_RUNTIME_NOTICE), 'wb') as f:
        f.write('\r\n'.join(lines).encode('utf-8'))


def compile_lcb(row, folder, source_name, lc_compile, lci_dir, scratch, version):
    cmd = [lc_compile, '--modulepath', lci_dir, '--interface', os.path.join(scratch, row['id'] + '.lci'),
           '--manifest', 'manifest.xml', '--output', 'module.lcm', source_name]
    p = subprocess.run(cmd, cwd=folder, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    for line in p.stdout.decode('utf-8', 'replace').splitlines():
        log('  lc-compile: ' + line.rstrip())
    if p.returncode != 0:
        raise Problem('%s: lc-compile failed with exit code %d' % (row['id'], p.returncode))
    root = ET.parse(os.path.join(folder, 'manifest.xml')).getroot()
    if root.tag != 'package' or root.findtext('name') != row['id']:
        raise Problem('%s: manifest.xml names %r' % (row['id'], root.findtext('name')))
    if root.findtext('version') != version:
        raise Problem('%s: manifest.xml has version %r, the source %s' % (row['id'], root.findtext('version'),
                                                                        version))
    log('  module.lcm %d bytes, %d handlers' % (os.path.getsize(os.path.join(folder, 'module.lcm')),
                                                 len(root.findall('handler'))))


def cmd_stage(args):
    problems = check_table()
    if problems:
        raise Problem('the table does not match the tree:\n  ' + '\n  '.join(problems))
    bin_dir = os.path.abspath(args.bin)
    lc_compile = next((os.path.join(bin_dir, n) for n in ('lc-compile', 'lc-compile.exe')
                       if os.path.isfile(os.path.join(bin_dir, n))), None)
    lci_dir = os.path.join(bin_dir, 'modules', 'lci')
    if lc_compile is None or not os.path.isdir(lci_dir):
        raise Problem('%s has no lc-compile and modules/lci' % bin_dir)
    if args.release and not args.vc_runtime:
        raise Problem('--release needs --vc-runtime: a release package must load without the Visual C++ '
                      'Redistributable')
    out = os.path.abspath(args.out)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    warnings = []
    scratch = tempfile.mkdtemp(prefix='lce-lci-')
    try:
        for row in PACKAGES:
            version = member_version(row['member'])
            log('%s (%s, %s %s)' % (row['id'], row['kind'], row['member'], version))
            folder = os.path.join(out, row['file'])
            os.makedirs(folder)
            data = read(member_path(row['member'], row['main']))
            if row['kind'] == 'lcb':
                name = os.path.basename(row['main'])
                with open(os.path.join(folder, name), 'wb') as f:
                    f.write(data)
                compile_lcb(row, folder, name, lc_compile, lci_dir, scratch, version)
                for platform, lib in libraries(row):
                    dest = os.path.join(folder, 'code', platform)
                    os.makedirs(dest, exist_ok=True)
                    shutil.copyfile(lib, os.path.join(dest, os.path.basename(lib)))
            else:
                with open(os.path.join(folder, row['stack'] + '.livecodescript'), 'wb') as f:
                    f.write(wrap_lcs(data, row['stack']))
                with open(os.path.join(folder, 'manifest.xml'), 'wb') as f:
                    f.write(lcs_manifest(row, version))
            add_licences(row, folder, args.openssl_licence)
            copies = []
            for platform in WINDOWS:
                code = os.path.join(folder, 'code', platform)
                if os.path.isdir(code):
                    copies += ['code/%s/%s' % (platform, n)
                               for n in add_runtime(code, platform, args.vc_runtime, args.release, warnings)]
            if copies:
                write_runtime_notice(folder, copies)
                log('  bundled the Visual C++ runtime: ' + ', '.join(copies))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    for w in warnings:
        log('WARNING: ' + w)
        if os.environ.get('GITHUB_ACTIONS'):
            log('::warning title=lce packages::' + w)
    log('staged %d packages in %s' % (len(PACKAGES), out))


# --- pack and check -----------------------------------------------------------

def package_name(row, version):
    return '%s-%s.lce' % (row['file'], version)


def zip_folder(folder, target):
    entries = []
    for dirpath, dirnames, filenames in os.walk(folder):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            entries.append((os.path.relpath(full, folder).replace(os.sep, '/'), full))
    order = sorted(entries, key=lambda e: (e[0] != 'manifest.xml', e[0]))
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as zf:
        for rel, full in order:
            info = zipfile.ZipInfo(rel, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, read(full))


def cmd_pack(args):
    stage = os.path.abspath(args.stage)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    made, lines, sums = [], [], []
    for row in PACKAGES:
        folder = os.path.join(stage, row['file'])
        if not os.path.isdir(folder):
            raise Problem('%s: not staged (%s)' % (row['id'], folder))
        if args.release and not os.path.isfile(os.path.join(folder, 'api.lcdoc')):
            raise Problem('%s: no api.lcdoc (run tools/lce-engine-check.lc docs first)' % row['id'])
        version = member_version(row['member'])
        name = package_name(row, version)
        target = os.path.join(out, name)
        zip_folder(folder, target)
        made.append(target)
        sums.append('%s  %s' % (sha256_file(target), name))
        main = row['stack'] if row['kind'] == 'lcs' else row['id']
        lines.append('\t'.join([row['kind'], name, main, row['probe'], row['expect']]))
        log('%s  %d bytes' % (name, os.path.getsize(target)))
    problems = check_packages(made)
    if problems:
        raise Problem('\n'.join(problems))
    with open(os.path.join(out, 'SHA256SUMS'), 'w', newline='\n') as f:
        f.write('\n'.join(sums) + '\n')
    with open(os.path.join(out, 'packages.tsv'), 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    log('packed %d packages into %s' % (len(made), out))


def check_packages(paths):
    """The Extension Manager's own checks (extensionValidateLCEPackage,
    extensionFetchSourceFromFolder) plus this tool's layout rules."""
    problems = []
    for path in paths:
        where = os.path.basename(path)
        try:
            with zipfile.ZipFile(path) as zf:
                names = zf.namelist()
                if not names:
                    raise Problem('%s: empty' % where)
                if names[0].endswith('/') or any(n.endswith('/') for n in names):
                    raise Problem('%s: has a folder entry (files must be at the root or in folders under it, '
                                  'never a folder entry)' % where)
                if names[0] != 'manifest.xml':
                    raise Problem('%s: the first entry is %s, not manifest.xml' % (where, names[0]))
                if len(set(names)) != len(names):
                    raise Problem('%s: a name is in the zip twice' % where)
                for n in names:
                    if n.startswith('/') or '..' in n.split('/') or '\\' in n:
                        raise Problem('%s: unsafe path %r' % (where, n))
                root = ET.fromstring(zf.read('manifest.xml'))
                for tag in ('name', 'version', 'author', 'type', 'title'):
                    if not (root.findtext(tag) or '').strip():
                        raise Problem('%s: manifest.xml has no %s' % (where, tag))
                top = [n for n in names if '/' not in n]
                lcb = [n for n in top if n.endswith('.lcb')]
                lcs = [n for n in top if re.match(r'^.*\.livecode(script)?$', n)]
                if lcb or 'module.lcm' in top:
                    if not (lcb and 'module.lcm' in top):
                        raise Problem('%s: an LCB package needs its .lcb and module.lcm at the root' % where)
                    if not any(n.startswith('code/') for n in names):
                        raise Problem('%s: an LCB package without code/' % where)
                    for n in names:
                        if n.startswith('code/'):
                            parts = n.split('/')
                            if len(parts) != 3 or parts[1] not in PLATFORMS:
                                raise Problem('%s: %s is not code/<platform-id>/<file>' % (where, n))
                elif lcs:
                    if len(lcs) != 1:
                        raise Problem('%s: %d script stacks at the root, expected one' % (where, len(lcs)))
                    stack = lcs[0].rsplit('.', 1)[0]
                    if stack != root.findtext('name'):
                        raise Problem('%s: the stack file %s and the manifest name %s differ'
                                      % (where, lcs[0], root.findtext('name')))
                    if lcs_header(zf.read(lcs[0])) is None:
                        raise Problem('%s: %s has no script "<name>" first line' % (where, lcs[0]))
                else:
                    raise Problem('%s: invalid package - no stack or module found' % where)
                if not any(n.startswith(LICENCE_DIR + '/') for n in names):
                    raise Problem('%s: no %s/' % (where, LICENCE_DIR))
        except (zipfile.BadZipFile, ET.ParseError, KeyError) as err:
            problems.append('%s: %s' % (where, err))
        except Problem as err:
            problems.append(str(err))
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd')
    sub.add_parser('table')
    sub.add_parser('list')
    s = sub.add_parser('stage')
    s.add_argument('--bin', required=True)
    s.add_argument('--out', required=True)
    s.add_argument('--vc-runtime')
    s.add_argument('--openssl-licence')
    s.add_argument('--release', action='store_true')
    p = sub.add_parser('pack')
    p.add_argument('stage')
    p.add_argument('--out', required=True)
    p.add_argument('--release', action='store_true')
    c = sub.add_parser('check')
    c.add_argument('packages', nargs='+')
    args = ap.parse_args(argv)
    try:
        if args.cmd == 'table':
            problems = check_table()
            for prob in problems:
                log('FAIL ' + prob)
            log('%s: %d packages, %d problems' % ('OK' if not problems else 'FAIL', len(PACKAGES), len(problems)))
            return 1 if problems else 0
        if args.cmd == 'list':
            for row in PACKAGES:
                log('%s\t%s\t%s' % (package_name(row, member_version(row['member'])), row['kind'], row['id']))
            return 0
        if args.cmd == 'stage':
            if args.openssl_licence and sha256_file(args.openssl_licence) != OPENSSL_LICENCE_SHA256:
                raise Problem('%s is not the pinned OpenSSL licence (SHA-256 %s)'
                              % (args.openssl_licence, OPENSSL_LICENCE_SHA256))
            cmd_stage(args)
            return 0
        if args.cmd == 'pack':
            cmd_pack(args)
            return 0
        if args.cmd == 'check':
            problems = check_packages(args.packages)
            for prob in problems:
                log('FAIL ' + prob)
            log('%s: %d packages checked' % ('OK' if not problems else 'FAIL', len(args.packages)))
            return 1 if problems else 0
        ap.print_help()
        return 2
    except Problem as err:
        log('ERROR: %s' % err)
        return 1


if __name__ == '__main__':
    sys.exit(main())
