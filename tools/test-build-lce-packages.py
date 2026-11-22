#!/usr/bin/env python3
"""test-build-lce-packages.py - fixture tests for tools/build-lce-packages.py.

Proves that `check` refuses each package shape the Extension Manager or the
layout rules refuse (and passes a good one), that `table` sees a row that
no longer matches the tree, and that a script library is wrapped the way
the IDE needs. Nothing here needs lc-compile or an engine: the engine half
(tools/lce-engine-check.lc) runs in .github/workflows/lce-packages.yml.

Since 2026-11-21 (every extension the suite makes is on the extensions
site): that `table` refuses an extension member of the registry with no
package (box3dxt's state until that day) and a workflow path filter that
misses a package's files (curlxt's since it joined), lets a row wait for
libraries its member has never committed but never one that ships them,
that `plan` tells what a release would bring the site from made-up
releases, and the workflow's publish block, RUN against a gh that answers
as GitHub would. Also that `docs-log` refuses every error Beyond's docs
parser logged in the docs step's output (artnetxt's first header made one
that the engine check passed), with the workflow's docs step RUN over an
engine that prints what the real one printed.

    python3 tools/test-build-lce-packages.py
"""

import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('build_lce', os.path.join(HERE, 'build-lce-packages.py'))
lce = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lce)

FAILURES = []

LCB_MANIFEST = (b'<package version="0.0"><name>org.example.x</name><title>X</title><author>A</author>'
                b'<version>1.0.0</version><type>library</type></package>')
LCS_MANIFEST = (b'<package version="0.0"><name>xlib</name><title>X</title><author>A</author>'
                b'<version>1.0.0</version><type>library</type></package>')
GOOD_LCB = [('manifest.xml', LCB_MANIFEST), ('code/x86_64-linux/x.so', b'\x7fELF'),
            ('licenses/LICENSE', b'MIT'), ('module.lcm', b'LC\x00\x00'), ('x.lcb', b'library org.example.x')]
GOOD_LCS = [('manifest.xml', LCS_MANIFEST), ('licenses/LICENSE', b'MIT'),
            ('xlib.livecodescript', b'script "xlib"\non a\nend a\n')]


def make(tmp, name, entries):
    path = os.path.join(tmp, name)
    with zipfile.ZipFile(path, 'w') as zf:
        for n, data in entries:
            zf.writestr(n, data)
    return path


def expect(label, ok, detail=''):
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
    if not ok:
        if detail:
            print('    ' + detail)
        FAILURES.append(label)


def refuses(tmp, label, entries, needle):
    problems = lce.check_packages([make(tmp, 'p.lce', entries)])
    expect('check refuses %s' % label, len(problems) == 1 and needle in problems[0])
    if len(problems) != 1 or needle not in problems[0]:
        print('    got: %r' % problems)


def test_check(tmp):
    expect('check passes a good LCB package', lce.check_packages([make(tmp, 'a.lce', GOOD_LCB)]) == [])
    expect('check passes a good LCS package', lce.check_packages([make(tmp, 'b.lce', GOOD_LCS)]) == [])
    refuses(tmp, 'a folder entry', [('code/', b'')] + GOOD_LCB, 'folder entry')
    refuses(tmp, 'manifest.xml not first', GOOD_LCB[1:] + GOOD_LCB[:1], 'not manifest.xml')
    refuses(tmp, 'a manifest without a title',
            [('manifest.xml', LCB_MANIFEST.replace(b'<title>X</title>', b''))] + GOOD_LCB[1:], 'no title')
    refuses(tmp, 'an LCB package without module.lcm', [e for e in GOOD_LCB if e[0] != 'module.lcm'],
            'module.lcm')
    refuses(tmp, 'an LCB package without code/', [e for e in GOOD_LCB if not e[0].startswith('code/')],
            'without code/')
    refuses(tmp, 'an unknown platform folder',
            [e if not e[0].startswith('code/') else ('code/x86_64-plan9/x.so', e[1]) for e in GOOD_LCB],
            'code/<platform-id>')
    android = [('code/%s/x.so' % p, b'\x7fELF') for p in lce.ANDROID]
    expect('check passes an LCB package with all four Android libraries',
           lce.check_packages([make(tmp, 'c.lce', GOOD_LCB + android)]) == [])
    refuses(tmp, 'Android libraries for three ABIs of four', GOOD_LCB + android[:3], 'all four, or none')
    refuses(tmp, 'a script library without its script line',
            GOOD_LCS[:2] + [('xlib.livecodescript', b'on a\nend a\n')], 'script "<name>"')
    refuses(tmp, 'a script library named unlike its manifest',
            GOOD_LCS[:2] + [('ylib.livecodescript', b'script "ylib"\n')], 'differ')
    refuses(tmp, 'a package without licenses/', [e for e in GOOD_LCS if not e[0].startswith('licenses/')],
            'licenses/')
    refuses(tmp, 'a package with nothing to load', GOOD_LCS[:2], 'no stack or module')
    refuses(tmp, 'an unsafe path', GOOD_LCS + [('../evil', b'')], 'unsafe')


def test_table():
    saved = copy.deepcopy(lce.PACKAGES)
    try:
        problems = lce.check_table()
        expect('table holds on the tree', problems == [])
        for problem in problems:
            # Name the row: a bare FAIL here once cost a whole release
            # dispatch to diagnose (2026-11-14, curlxt's first).
            print('     ' + problem)
        lce.PACKAGES[0]['main'] = 'src/missing.lcb'
        expect('table sees a missing main file', any('missing' in p for p in lce.check_table()))
        lce.PACKAGES[:] = copy.deepcopy(saved)
        lce.PACKAGES[0]['id'] = 'org.example.wrong'
        expect('table sees an id the .lcb does not declare', any('declares' in p for p in lce.check_table()))
        lce.PACKAGES[:] = copy.deepcopy(saved)
        row = next(r for r in lce.PACKAGES if r['kind'] == 'lcs' and r['requires'])
        row['requires'] = ['org.example.later']
        expect('table sees a requirement no earlier row provides', any('requires' in p for p in lce.check_table()))
        lce.PACKAGES[:] = copy.deepcopy(saved)
        row = next(r for r in lce.PACKAGES if r['kind'] == 'lcs')
        row['stack'] = 'bad.name'
        expect('table sees a stack name with a dot', any('without dots' in p for p in lce.check_table()))
        lce.PACKAGES[:] = copy.deepcopy(saved)
        # Android is all four ABIs or none: `libraries` answering with one
        # (as a tree holding a single <abi>-android folder would) must be
        # refused, and with all four accepted
        # (whatever the tree holds: its own Android libraries are taken out
        # of the answer first, so this reads the same before and after a
        # release dispatch lands them)
        real = lce.libraries
        desktop = lambda row: [e for e in real(row) if e[0] not in lce.ANDROID]
        # (only to rows with desktop libraries: a row with none waits, and
        # Android libraries alone would make it a row that owes six)
        android = lambda row, abis: [(p, 'x.so') for p in abis] if desktop(row) else []
        try:
            lce.libraries = lambda row: desktop(row) + android(row, ['arm64-android'])
            expect('table sees Android libraries for one ABI only',
                   any('all four, or none' in p for p in lce.check_table()))
            lce.libraries = lambda row: desktop(row) + android(row, lce.ANDROID[:3])
            expect('table sees Android libraries for three ABIs of four',
                   any('none for x86-android' in p for p in lce.check_table()))
            lce.libraries = lambda row: desktop(row) + android(row, lce.ANDROID)
            expect('table holds with all four Android libraries', lce.check_table() == [])
            lce.libraries = desktop
            expect('table holds with no Android library', lce.check_table() == [])
        finally:
            lce.libraries = real
        lce.PACKAGES.append(copy.deepcopy(saved[0]))
        expect('table sees an id used twice', any('twice' in p for p in lce.check_table()))
    finally:
        lce.PACKAGES[:] = saved
    # secur32.dll is Schannel's SSPI (curlxt's TLS on Windows), on every
    # Windows since NT; Beyond's builder must list it too
    expect('secur32.dll counts as a system DLL', lce.is_system_dll('SECUR32.dll'))
    # SDL inside gamepadxt imports SetupAPI, COM (ole32) and shell32, all in
    # every Windows since 2000; Beyond's builder lists the same three
    for dll in ('SETUPAPI.dll', 'ole32.dll', 'SHELL32.dll'):
        expect('%s counts as a system DLL' % dll, lce.is_system_dll(dll))
    # ...but SDL itself, linked as a DLL instead of statically, ships with
    # nothing, so a library importing it is refused
    expect('SDL3.dll is not a system DLL', not lce.is_system_dll('SDL3.dll'))
    # what PDFium's prebuilt pdfium.dll imports (pdfxt), by the case it has
    for dll in ('KERNEL32.dll', 'USER32.dll', 'ADVAPI32.dll', 'GDI32.dll'):
        expect('%s counts as a system DLL' % dll, lce.is_system_dll(dll))
    expect('pdfium.dll is not a system DLL', not lce.is_system_dll('pdfium.dll'))
    expect('a pinned runtime DLL is not a system DLL', not lce.is_system_dll('vcruntime140.dll'))
    pins = copy.deepcopy(lce.VC_RUNTIME_PINS)
    try:
        del lce.VC_RUNTIME_PINS['x86_64-win32']['vcruntime140_1.dll']
        expect('table sees a Windows import that is neither system nor pinned',
               any('vcruntime140_1.dll' in p for p in lce.check_table()))
    finally:
        lce.VC_RUNTIME_PINS.clear()
        lce.VC_RUNTIME_PINS.update(pins)


def test_wrap():
    out = lce.wrap_lcs(b'on a\nend a', 'xlib')
    expect('wrap adds the script line', out.startswith(b'script "xlib"\non a\n'))
    expect('wrap appends extensionInitialize/extensionFinalize',
           b'on extensionInitialize' in out and out.rstrip().endswith(b'end extensionFinalize'))
    kept = b'script "xlib"\non extensionInitialize\nend extensionInitialize\n' \
           b'on extensionFinalize\nend extensionFinalize\n'
    expect('wrap leaves a library that handles both alone', lce.wrap_lcs(kept, 'xlib') == kept)
    try:
        lce.wrap_lcs(b'on extensionInitialize\nend extensionInitialize\n', 'xlib')
        expect('wrap refuses a library that handles only one', False)
    except lce.Problem:
        expect('wrap refuses a library that handles only one', True)


def test_zip_order(tmp):
    folder = os.path.join(tmp, 'f')
    for rel, data in GOOD_LCB:
        os.makedirs(os.path.dirname(os.path.join(folder, *rel.split('/'))), exist_ok=True)
        with open(os.path.join(folder, *rel.split('/')), 'wb') as f:
            f.write(data)
    a, b = os.path.join(tmp, 'z1.lce'), os.path.join(tmp, 'z2.lce')
    lce.zip_folder(folder, a)
    lce.zip_folder(folder, b)
    with zipfile.ZipFile(a) as zf:
        names = zf.namelist()
    expect('pack puts manifest.xml first', names[0] == 'manifest.xml')
    expect('pack writes no folder entry', not any(n.endswith('/') for n in names))
    expect('pack is the same bytes twice', open(a, 'rb').read() == open(b, 'rb').read())
    expect('a packed folder passes check', lce.check_packages([a]) == [])


# --- every extension has a package (2026-11-21) ------------------------------

def saved_state():
    """Everything the table tests below change, to put back."""
    lce.suite_tables()
    return (copy.deepcopy(lce.PACKAGES), dict(lce.NOT_PACKAGED), copy.deepcopy(lce._TABLES), lce.libraries)


def restore(state):
    packages, not_packaged, tables, libraries = state
    lce.PACKAGES[:] = copy.deepcopy(packages)
    lce.NOT_PACKAGED.clear()
    lce.NOT_PACKAGED.update(not_packaged)
    lce._TABLES.clear()
    lce._TABLES.update(copy.deepcopy(tables))
    lce.libraries = libraries


def test_registry():
    state = saved_state()
    try:
        problems = lce.check_registry()
        expect('registry: every extension member has a package on the tree', problems == [])
        for problem in problems:
            print('     ' + problem)
        # The class the rule exists for: a member joins the registry and
        # nobody gives it a row
        lce._TABLES['extensions'].append('newxt')
        expect('registry: a new extension member with no row is refused, by name',
               any(p.startswith('newxt is an extension') for p in lce.check_registry()))
        lce.NOT_PACKAGED['newxt'] = 'its library is a service, not a file'
        expect('registry: ...unless NOT_PACKAGED says why', lce.check_registry() == [])
        lce.NOT_PACKAGED['newxt'] = '  '
        expect('registry: a NOT_PACKAGED entry needs a reason',
               any('without a reason' in p for p in lce.check_registry()))
        restore(state)
        # box3dxt as it was until this rule: in the registry, with no row
        lce.PACKAGES[:] = [r for r in lce.PACKAGES if r['member'] != 'box3dxt']
        expect('registry: box3dxt without its row is refused, as it went unlisted until 2026-11-21',
               any(p.startswith('box3dxt is an extension') for p in lce.check_table()))
        restore(state)
        lce.NOT_PACKAGED['sodiumxt'] = 'stale'
        expect('registry: a NOT_PACKAGED entry for a packaged member is stale',
               any('names sodiumxt, which has a package' in p for p in lce.check_registry()))
        restore(state)
        lce.NOT_PACKAGED['riptide'] = 'an app'
        expect('registry: NOT_PACKAGED names extensions only',
               any('riptide, which is not an extension' in p for p in lce.check_registry()))
        restore(state)
        row = copy.deepcopy(lce.PACKAGES[0])
        row.update(member='riptide', id='org.example.app', file='riptide')
        lce.PACKAGES.append(row)
        expect('registry: a package of a member that is not an extension is refused',
               any(p.startswith('riptide has a package') for p in lce.check_registry()))
    finally:
        restore(state)


def test_waiting():
    state = saved_state()
    real = lce.libraries
    try:
        ident = 'org.openxtalk.library.sodium'
        lce.libraries = lambda r: [] if r['member'] == 'sodiumxt' else real(r)
        lce._TABLES['ships']['sodiumxt'] = []
        expect('waiting: a member that ships nothing and has committed nothing waits', ident in lce.waiting())
        problems = lce.check_table()
        expect('waiting: ...the table holds', problems == [])
        for problem in problems:
            print('     ' + problem)
        expect('waiting: ...and stage, pack and list leave it out', ident not in [r['id'] for r in lce.active()])
        # no package carries the web archive: xlsxt's landed before its
        # other libraries, and its row must go on waiting, not be refused
        lce._TABLES['ships']['sodiumxt'] = ['wasm32-emscripten']
        expect('waiting: a member that ships only the web archive waits',
               ident in lce.waiting() and lce.check_table() == [])
        # a member that ships even one platform never waits: a lost library
        # is the refusal it always was
        lce._TABLES['ships']['sodiumxt'] = ['x86_64-linux']
        expect('waiting: a member that ships a platform and lost its libraries is refused',
               ident not in lce.waiting() and any('sodiumxt %s: no committed library' % ident in p
                                                  for p in lce.check_table()))
        lce._TABLES['ships']['sodiumxt'] = []
        lce.libraries = lambda r: [e for e in real(r) if e[0] != 'x86-win32'] if r['member'] == 'sodiumxt' \
            else real(r)
        expect('waiting: some libraries, not all, is refused as before',
               any('no committed library for x86-win32' in p for p in lce.check_table()))
        lce.libraries = real
        expect('waiting: libraries committed before the ships row names them are packaged',
               ident not in lce.waiting())
        # a helper waits with the library it needs
        lce.libraries = lambda r: [] if r['member'] == 'torrentxt' else real(r)
        lce._TABLES['ships']['torrentxt'] = []
        wait = lce.waiting()
        expect('waiting: a script library that requires a waiting one waits too',
               'torrentHelpers' in wait and 'org.openxtalk.library.torrent' in wait)
        # no freshness row: nothing says what it owes, so it never waits
        del lce._TABLES['ships']['torrentxt']
        expect('waiting: a native row whose member has no freshness row is refused',
               any('no row in tools/check-binary-freshness.py' in p for p in lce.check_table()))
    finally:
        restore(state)


def test_workflow_paths():
    with open(lce.WORKFLOW, encoding='utf-8') as f:
        text = f.read()
    patterns = lce.workflow_paths(text) or []
    expect('paths: the push trigger\'s list is read', 'tools/build-lce-packages.py' in patterns)
    problems = lce.check_workflow_paths(text)
    expect('paths: every package\'s files start the workflow', problems == [])
    for problem in problems:
        print('     ' + problem)
    # the gap this rule found: curlxt/src/** was never in the list from the
    # day curlxt joined (2026-11-14) until 2026-11-21
    line = "      - 'curlxt/src/**'\n"
    expect('paths: (the fixture finds its line)', line in text)
    problems = lce.check_workflow_paths(text.replace(line, ''))
    expect('paths: without curlxt/src/** every curlxt package is refused, by name',
           sum(p.startswith('curlxt ') for p in problems) == 3)
    problems = lce.check_workflow_paths(text.replace(line, line + "      - '!curlxt/src/*.livecodescript'\n"))
    expect('paths: a later ! pattern takes files out again',
           any(p.startswith('curlxt curlHelpers:') for p in problems)
           and not any(p.startswith('curlxt org.openxtalk.library.curl:') for p in problems))
    line = "      - 'xlsxt/src/**'\n"
    expect('paths: a row that waits is held too (its libraries landing must start the build)',
           line in text and any(p.startswith('xlsxt ') for p in lce.check_workflow_paths(text.replace(line, ''))))
    expect('paths: a workflow with no list is refused', lce.check_workflow_paths('on:\n  push:\n') != [])
    expect('glob: * stops at a slash', lce.filter_takes(['*/LICENSE'], 'box3dxt/LICENSE')
           and not lce.filter_takes(['*/LICENSE'], 'box3dxt/docs/LICENSE'))
    expect('glob: ** crosses slashes',
           lce.filter_takes(['box3dxt/src/**'], 'box3dxt/src/code/x86-win32/box3dxt.dll'))


def test_pure(tmp):
    """A pure LCB row (native=False, 2026-11-21): a module that binds no
    library of its own, such as showcontrol's Art-Net, is packaged with no
    code/ folder on any platform and never waits for libraries."""
    state = saved_state()
    real = lce.libraries
    try:
        row = next(r for r in lce.PACKAGES if r['member'] == 'sodiumxt' and r['kind'] == 'lcb')
        ident = row['id']
        row['native'] = False
        lce.libraries = lambda r: [] if r['member'] == 'sodiumxt' else real(r)
        del lce._TABLES['ships']['sodiumxt']
        problems = lce.check_table()
        expect('pure: a native=False row with no library and no freshness row holds', problems == [],
               repr(problems))
        expect('pure: ...never waits, and is packaged',
               ident not in lce.waiting() and ident in [r['id'] for r in lce.active()])
        expect('pure: ...made of its source and licences only',
               not any('/src/code/' in p for p in lce.package_inputs(row)), repr(lce.package_inputs(row)))
        lce.libraries = real
        expect('pure: native=False over committed libraries is refused (the package would leave them out)',
               any('native=False, but sodiumxt has committed libraries' in p for p in lce.check_table()))
        lce.libraries = lambda r: [] if r['member'] == 'sodiumxt' else real(r)
        row['native'] = 'no'
        expect('pure: native is True or False', any("native='no'" in p for p in lce.check_table()))
        row['native'] = False
        helper = next(r for r in lce.PACKAGES if r['kind'] == 'lcs')
        helper['native'] = False
        expect('pure: native= on a script library row is refused',
               any('native= is for an lcb row' in p for p in lce.check_table()))
        del helper['native']
        # without the flag the same row is what it always was: refused,
        # since nothing says which libraries it owes
        row['native'] = True
        expect('pure: a native row with no freshness row is still refused',
               any('no row in tools/check-binary-freshness.py' in p for p in lce.check_table()))

        # check: a pure package has no code/, any other LCB package has one
        manifest = LCB_MANIFEST.replace(b'org.example.x', ident.encode())
        bare = [('manifest.xml', manifest)] + [e for e in GOOD_LCB[1:] if not e[0].startswith('code/')]
        coded = [('manifest.xml', manifest)] + GOOD_LCB[1:]
        row['native'] = False
        expect('pure: check passes a pure package without code/', lce.check_packages([make(tmp, 'q.lce', bare)]) == [])
        refuses(tmp, 'a pure package with code/', coded, 'pure LCB package (native=False) with code/')
        row['native'] = True
        refuses(tmp, 'the same package without code/ when its row is native', bare, 'without code/')
        refuses(tmp, 'an LCB package of no row without code/', [e for e in GOOD_LCB if not e[0].startswith('code/')],
                'without code/')

        # pack tells the engine check which kind it is: packages.tsv's
        # sixth column, "pure", "native", or empty for a script library
        row['native'] = False
        other = copy.deepcopy(next(r for r in state[0] if r['member'] == 'enetxt' and r['kind'] == 'lcb'))
        helper = copy.deepcopy(next(r for r in state[0] if r['member'] == 'enetxt' and r['kind'] == 'lcs'))
        lce.PACKAGES[:] = [row, other, helper]
        stage, out = os.path.join(tmp, 'stage'), os.path.join(tmp, 'packed')
        folders = {row['file']: bare,
                   other['file']: [('manifest.xml', LCB_MANIFEST.replace(b'org.example.x', other['id'].encode()))]
                   + GOOD_LCB[1:],
                   helper['file']: [('manifest.xml', LCS_MANIFEST.replace(b'xlib', helper['stack'].encode())),
                                    ('licenses/LICENSE', b'MIT'),
                                    (helper['stack'] + '.livecodescript',
                                     ('script "%s"\non a\nend a\n' % helper['stack']).encode())]}
        for name, entries in folders.items():
            for rel, data in entries:
                path = os.path.join(stage, name, *rel.split('/'))
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'wb') as f:
                    f.write(data)
        with contextlib.redirect_stdout(io.StringIO()):
            lce.cmd_pack(type('A', (), {'stage': stage, 'out': out, 'release': False})())
        with open(os.path.join(out, 'packages.tsv'), encoding='utf-8') as f:
            rows = [line.split('\t') for line in f.read().splitlines()]
        expect('pure: packages.tsv says pure, native, and nothing for a script library',
               [r[0] for r in rows] == ['lcb', 'lcb', 'lcs'] and [r[5] for r in rows] == ['pure', 'native', '']
               and all(len(r) == 6 for r in rows), repr(rows))
    finally:
        lce.libraries = real
        restore(state)


# --- plan: what a release would bring the site --------------------------------

def package(ident, title, version, platforms=(), salt=b''):
    entries = [('manifest.xml', ('<package version="0.0"><name>%s</name><title>%s</title><author>A</author>'
                                 '<version>%s</version><type>library</type></package>'
                                 % (ident, title, version)).encode()),
               ('licenses/LICENSE', b'MIT' + salt)]
    entries += [('code/%s/x.so' % p, b'\x7fELF') for p in platforms]
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return buf.getvalue()


def write_files(folder, files, sums=None):
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    for name, data in files.items():
        with open(os.path.join(folder, name), 'wb') as f:
            f.write(data)
    if sums is None:
        sums = ''.join('%s  %s\n' % (hashlib.sha256(d).hexdigest(), n) for n, d in sorted(files.items()))
    with open(os.path.join(folder, 'SHA256SUMS'), 'w') as f:
        f.write(sums)


def release_object(tag, files, draft=False, published='2026-11-15T14:51:29Z'):
    return {'tag_name': tag, 'draft': draft, 'prerelease': True, 'published_at': published,
            'assets': [{'name': n, 'browser_download_url': 'https://example.invalid/%s/%s' % (tag, n)}
                       for n in sorted(files) + ['SHA256SUMS']]}


WIN = ('x86_64-win32',)
OLD = {
    'alphaxt-1.0.0.lce': package('org.example.alpha', 'AlphaXT', '1.0.0', WIN),
    'alphaxt-helpers-1.0.0.lce': package('alphaHelpers', 'AlphaXT helpers', '1.0.0'),
    'betaxt-1.0.0.lce': package('org.example.beta', 'BetaXT', '1.0.0', ('x86_64-linux',)),
    'gammaxt-1.0.0.lce': package('gamma', 'GammaXT', '1.0.0'),
    'epsxt-1.0.0.lce': package('eps', 'EpsXT', '1.0.0'),
}
NEW = {
    # Android arrives at the same version
    'alphaxt-1.0.0.lce': package('org.example.alpha', 'AlphaXT', '1.0.0', WIN + tuple(lce.ANDROID)),
    'alphaxt-helpers-1.1.0.lce': package('alphaHelpers', 'AlphaXT helpers', '1.1.0'),
    'betaxt-1.0.0.lce': OLD['betaxt-1.0.0.lce'],
    'epsxt-1.0.0.lce': package('eps', 'EpsXT', '1.0.0', salt=b' rebuilt'),
    'newxt-0.1.0.lce': package('org.example.new', 'NewXT', '0.1.0', WIN),
}


def run_plan(tmp, mine, releases, rel_files):
    mine_dir, rel_dir = os.path.join(tmp, 'mine'), os.path.join(tmp, 'rel')
    write_files(mine_dir, mine)
    write_files(rel_dir, rel_files)
    rel_json = os.path.join(tmp, 'releases.json')
    with open(rel_json, 'w') as f:
        json.dump(releases, f)
    notes, out = os.path.join(tmp, 'notes.md'), os.path.join(tmp, 'gh-output')
    for path in (notes, out):
        if os.path.exists(path):
            os.remove(path)
    log = io.StringIO()
    with contextlib.redirect_stdout(log):
        code = lce.main(['plan', mine_dir, '--release-json', rel_json, '--lce-dir', rel_dir,
                         '--notes', notes, '--github-output', out])
    text = lambda p: open(p).read() if os.path.exists(p) else ''
    return code, log.getvalue(), text(notes), text(out)


def test_plan(tmp):
    expect('plan: a stem and version from a file name',
           lce.split_name('curlxt-tsnet-0.1.0.lce') == ('curlxt-tsnet', '0.1.0')
           and lce.split_name('x-1.0.0-rc.1.lce') == ('x', '1.0.0-rc.1')
           and lce.split_name('odd.lce') == ('odd', ''))
    rel = release_object('v9', OLD)
    # what is fetched: SHA256SUMS, and only the packages whose bytes differ
    # at the same version
    fetched = []
    rel_dir = os.path.join(tmp, 'rel')
    write_files(rel_dir, OLD)
    mine_dir = os.path.join(tmp, 'mine')
    write_files(mine_dir, NEW)

    def fetch(asset):
        fetched.append(asset['name'])
        with open(os.path.join(rel_dir, asset['name']), 'rb') as f:
            return f.read()

    changes = lce.plan(lce.read_local(mine_dir), rel, fetch)
    kinds = {name: kind for kind, name, _ in changes}
    expect('plan: NEW, VERSION, PLATFORMS, REBUILT and GONE, and nothing for an unchanged package',
           kinds == {'alphaxt-1.0.0.lce': 'PLATFORMS', 'alphaxt-helpers-1.1.0.lce': 'VERSION',
                     'epsxt-1.0.0.lce': 'REBUILT', 'newxt-0.1.0.lce': 'NEW', 'gammaxt-1.0.0.lce': 'GONE'},
           repr(kinds))
    expect('plan: only SHA256SUMS and the same-version packages with other bytes are downloaded',
           sorted(fetched) == ['SHA256SUMS', 'alphaxt-1.0.0.lce', 'epsxt-1.0.0.lce'], repr(fetched))
    words = dict((name, w) for _, name, w in changes)
    expect('plan: a platform change is told in the site\'s words',
           'now also for Android ARM64' in words.get('alphaxt-1.0.0.lce', ''), words.get('alphaxt-1.0.0.lce'))

    code, log, notes, out = run_plan(tmp, NEW, [rel], OLD)
    expect('plan: publishes when the site differs', code == 0 and out == 'release=true\nbaseline=v9\n',
           repr((code, out)))
    expect('plan: the notes credit the author and say what is new since the release',
           notes.startswith('The xTalk Suite extensions by Seth Morrow') and 'New since v9:' in notes
           and '`newxt-0.1.0.lce`: NewXT 0.1.0' in notes and '`gammaxt-1.0.0.lce` is no longer offered' in notes
           and 'Changed at the same version (rebuilt from this commit): `epsxt-1.0.0.lce`' in notes, notes)
    # a rebuild alone publishes too: a fix without a version bump must reach
    # the site, and a deterministic build gives other bytes only for one
    only = dict(OLD)
    only['epsxt-1.0.0.lce'] = NEW['epsxt-1.0.0.lce']
    code, log, notes, out = run_plan(tmp, only, [rel], OLD)
    expect('plan: a rebuild at the same version and platforms publishes',
           code == 0 and out == 'release=true\nbaseline=v9\n' and 'REBUILT' in log
           and 'New since' not in notes and '`epsxt-1.0.0.lce`' in notes, repr((code, out, notes)))
    code, log, notes, out = run_plan(tmp, OLD, [rel], OLD)
    expect('plan: the same packages publish nothing', out == 'release=false\nbaseline=v9\n' and 'nothing to publish' in log)
    # the baseline is the newest PUBLISHED release with packages
    draft = release_object('v10', {}, draft=True, published='')
    draft['assets'] = rel['assets']
    newer_empty = release_object('v11', {}, published='2026-11-20T00:00:00Z')
    newer_empty['assets'] = []
    code, log, notes, out = run_plan(tmp, OLD, [draft, newer_empty, rel], OLD)
    expect('plan: a draft, and a release without packages, are not the baseline', out.endswith('baseline=v9\n'), out)
    code, log, notes, out = run_plan(tmp, NEW, [draft], OLD)
    expect('plan: with no published release every package is new',
           out == 'release=true\nbaseline=\n' and 'In this first release:' in notes, repr((out, notes)))
    # fail closed
    bad = ''.join('%s  %s\n' % (hashlib.sha256(d).hexdigest(), n) for n, d in sorted(OLD.items())
                  if n != 'betaxt-1.0.0.lce')
    write_files(rel_dir, OLD, sums=bad)
    try:
        lce.plan(lce.read_local(mine_dir), rel, fetch)
        expect('plan: a release package missing from its SHA256SUMS is refused', False)
    except lce.Problem as err:
        expect('plan: a release package missing from its SHA256SUMS is refused', 'betaxt' in str(err), str(err))
    write_files(rel_dir, dict(OLD, **{'epsxt-1.0.0.lce': b'not the bytes'}),
                sums=''.join('%s  %s\n' % (hashlib.sha256(d).hexdigest(), n) for n, d in sorted(OLD.items())))
    try:
        lce.plan(lce.read_local(mine_dir), rel, fetch)
        expect('plan: a release package whose bytes do not match is refused', False)
    except lce.Problem as err:
        expect('plan: a release package whose bytes do not match is refused', 'epsxt' in str(err), str(err))
    write_files(mine_dir, NEW, sums='0' * 64 + '  newxt-0.1.0.lce\n')
    try:
        lce.read_local(mine_dir)
        expect('plan: a package of this run that does not match its SHA256SUMS is refused', False)
    except lce.Problem as err:
        expect('plan: a package of this run that does not match its SHA256SUMS is refused', True)


# --- the workflow's publish block, run -------------------------------------------

FAKE_GH = r"""#!/bin/bash
{ printf 'gh'; printf ' [%s]' "$@"; echo; } >> "$GH_LOG"
if [ "$1" = api ]; then
  case "$2" in
    */commits/*) echo "$BASE_SHA" ;;
    */compare/*) echo "$COMPARE_STATUS" ;;
    */git/ref/tags/*) case " $EXISTING_TAGS " in *" ${2##*/} "*) exit 0 ;; *) exit 1 ;; esac ;;
    *) exit 1 ;;
  esac
  exit 0
fi
if [ "$1 $2" = "release view" ]; then
  case " $EXISTING_RELEASES " in *" $3 "*) exit 0 ;; *) exit 1 ;; esac
fi
exit 0
"""


def marked_block(text, name):
    """The lines of lce-packages.yml between `# >>> name` and `# <<< name`,
    unindented: the shell a step runs."""
    m = re.search(r'\n( *)# >>> %s\n(.*?)\n *# <<< %s' % (name, name), text, re.S)
    if not m:
        return None
    indent = m.group(1)
    return '\n'.join(l[len(indent):] if l.startswith(indent) else l for l in m.group(2).split('\n')) + '\n'


def publish_block(text):
    return marked_block(text, 'publish')


def test_publish(tmp):
    with open(lce.WORKFLOW, encoding='utf-8') as f:
        text = f.read()
    block = publish_block(text)
    expect('publish: the block is marked in lce-packages.yml', block is not None)
    job = text[text.index('\n  publish:\n'):] if '\n  publish:\n' in text else ''
    expect('publish: the job runs for a push to main only',
           "if: github.event_name == 'push' && github.ref == 'refs/heads/main'" in job)
    expect('publish: ...with contents and actions write, and no more',
           re.search(r'permissions:\n\s+contents: write[^\n]*\n\s+actions: write[^\n]*\n\s+steps:', job) is not None)
    expect('publish: ...after the plan says there is something to publish',
           "if: steps.plan.outputs.release == 'true'" in job and '--github-output "$GITHUB_OUTPUT"' in job)
    expect('publish: a push to main builds as a release does (the pinned Visual C++ runtime or nothing)',
           "(github.event_name == 'push' && github.ref == 'refs/heads/main')) && '--release'" in text)
    expect('publish: LCE_AUTO_PUBLISH is set', re.search(r"\n  LCE_AUTO_PUBLISH: '(true|false)'\n", text) is not None)
    if block is None or not shutil.which('bash'):
        print('SKIP publish: no bash here; the block is not run')
        return
    bindir = os.path.join(tmp, 'bin')
    os.makedirs(bindir)
    with open(os.path.join(bindir, 'gh'), 'w') as f:
        f.write(FAKE_GH)
    with open(os.path.join(bindir, 'date'), 'w') as f:
        f.write('#!/bin/sh\necho 2026.11.21\n')
    for n in ('gh', 'date'):
        os.chmod(os.path.join(bindir, n), 0o755)
    runner = os.path.join(tmp, 'runner')
    os.makedirs(os.path.join(runner, 'lce'))
    for n in ('a-1.0.0.lce', 'b-2.0.0.lce', 'SHA256SUMS', '../notes.md'):
        open(os.path.join(runner, 'lce', n), 'w').close()

    def run(baseline='v2026.11.15', status='ahead', releases='', tags='', auto='true'):
        logf = os.path.join(tmp, 'gh.log')
        if os.path.exists(logf):
            os.remove(logf)
        env = dict(os.environ, PATH=bindir + os.pathsep + os.environ['PATH'], GH_LOG=logf,
                   GITHUB_REPOSITORY='o/r', GITHUB_SHA='c0ffee', RUNNER_TEMP=runner,
                   GITHUB_STEP_SUMMARY=os.path.join(tmp, 'summary'), BASELINE=baseline,
                   LCE_AUTO_PUBLISH=auto, BASE_SHA='ba5e', COMPARE_STATUS=status,
                   EXISTING_RELEASES=releases, EXISTING_TAGS=tags)
        p = subprocess.run(['bash', '-c', block], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True)
        calls = open(logf).read().splitlines() if os.path.exists(logf) else []
        return p.returncode, calls, p.stdout

    def made(calls):
        return [c for c in calls if c.startswith('gh [release] [create]')]

    code, calls, out = run()
    create = made(calls)
    expect('publish: ahead of the newest release, it makes vYYYY.MM.DD as a draft from this commit',
           code == 0 and len(create) == 1 and '[v2026.11.21]' in create[0] and '[--target] [c0ffee]' in create[0]
           and '[--draft]' in create[0] and '[--prerelease]' in create[0], repr((code, calls, out)))
    expect('publish: ...with every package and SHA256SUMS of the run',
           bool(create) and all('%s/lce/%s]' % (runner, n) in create[0] for n in ('a-1.0.0.lce', 'b-2.0.0.lce',
                                                                                 'SHA256SUMS')))
    order = [i for i, c in enumerate(calls) if c.startswith(('gh [release] [create]', 'gh [release] [edit]',
                                                             'gh [workflow] [run]'))]
    expect('publish: ...then publishes it, then starts pages.yml with its tag',
           len(order) == 3 and '[--draft=false]' in calls[order[1]]
           and '[pages.yml]' in calls[order[2]] and '[tag=v2026.11.21]' in calls[order[2]], repr(calls))
    code, calls, out = run(releases='v2026.11.21', tags='v2026.11.21.2')
    expect('publish: a second the same day is .2, and a bare tag is taken too (.3)',
           made(calls) and '[v2026.11.21.3]' in made(calls)[0], repr(calls))
    for status in ('behind', 'identical'):
        code, calls, out = run(status=status)
        expect('publish: %s the newest release, it publishes nothing' % status,
               code == 0 and not made(calls) and 'nothing published' in out, repr((code, calls, out)))
    code, calls, out = run(status='diverged')
    expect('publish: beside a release dispatched from a branch (diverged), it publishes', len(made(calls)) == 1)
    code, calls, out = run(baseline='')
    expect('publish: with no release yet there is nothing to compare: it publishes',
           len(made(calls)) == 1 and not any('[compare]' in c or '/compare/' in c for c in calls), repr(calls))
    code, calls, out = run(auto='false')
    expect('publish: LCE_AUTO_PUBLISH false leaves the release a draft and starts nothing',
           len(made(calls)) == 1 and not any(c.startswith(('gh [release] [edit]', 'gh [workflow]')) for c in calls)
           and 'press Publish' in out, repr(calls))


# --- the docs step's log (2026-11-21) ---------------------------------------------

# The docs step's lines as OXT-Beyond v0.2.7-rc.6's server engine printed
# them, over #200's first headers (artnetxt's, oscxt's and midixt's .lcb at
# e74c338) beside main's packages: artnetxt's error left a library and its
# entries behind, so the engine check said PASS for it; oscxt's did not
DOCS_STAGE = '/runner/stage'
DOCS_INFO = 'INFO engine 9.7.1-OXT Linux x86_64'
ARTNET_ERROR = (DOCS_STAGE + '/artnetxt/artnet.lcb: error: Required documentation not found for library '
                'implements the published protocol ("Art-Net compatible"); no')
OSC_ERROR = DOCS_STAGE + '/oscxt/osc.lcb: error: No extension name found'
OSC_WARNING = DOCS_STAGE + '/oscxt/osc.lcb: warning: Invalid library-level docs'
OSC_FAIL = ('FAIL oscxt api.lcdoc - the parser returned no library with entries: Name: oscBuildBundle  '
            'Type: handler')
OSC_ANNOTATION = '::error title=lce packages::oscxt api.lcdoc - the parser returned no library with entries'

FAKE_ENGINE = r"""#!/bin/sh
cat "$FAKE_OUT"
exit "$FAKE_STATUS"
"""


def test_docs_log(tmp):
    def lines(*ls):
        return '\n'.join(ls) + '\n'

    clean = lines(DOCS_INFO, 'PASS sodiumxt api.lcdoc', 'PASS onionxt api.lcdoc', 'SUMMARY 2 0')
    expect('docs-log: a clean run passes', lce.docs_log(clean) == ([], []), repr(lce.docs_log(clean)))
    artnet = lines(DOCS_INFO, ARTNET_ERROR, 'PASS artnetxt api.lcdoc', 'PASS sodiumxt api.lcdoc', 'SUMMARY 2 0')
    problems, warnings = lce.docs_log(artnet)
    expect('docs-log: an error the parser logged is refused though the engine check said PASS (artnetxt)',
           len(problems) == 1 and '/artnetxt/artnet.lcb' in problems[0] and 'library implements' in problems[0]
           and not warnings, repr((problems, warnings)))
    osc = lines(DOCS_INFO, OSC_ERROR, OSC_WARNING, OSC_FAIL, OSC_ANNOTATION, 'SUMMARY 0 1')
    problems, warnings = lce.docs_log(osc)
    expect('docs-log: ...and beside the engine check\'s own FAIL, the parser\'s error once (oscxt)',
           len(problems) == 1 and 'No extension name found' in problems[0], repr(problems))
    expect('docs-log: a warning is shown, not refused',
           len(warnings) == 1 and 'Invalid library-level docs' in warnings[0], repr(warnings))
    script = lines('stack "/runner/stage/onionxt/onionxt.livecodescript": error: No extension name found',
                   'SUMMARY 1 0')
    problems, _ = lce.docs_log(script)
    expect('docs-log: a script library\'s error names its stack',
           len(problems) == 1 and 'stack "/runner/stage/onionxt/onionxt.livecodescript"' in problems[0],
           repr(problems))
    engine_fail = lines('FAIL x api.lcdoc - Execution error: error: at line 3', 'SUMMARY 0 1')
    expect('docs-log: the engine check\'s own lines are not read as the parser\'s',
           lce.docs_log(engine_fail) == ([], []), repr(lce.docs_log(engine_fail)))
    problems, _ = lce.docs_log(lines(DOCS_INFO, 'PASS sodiumxt api.lcdoc'))
    expect('docs-log: a run with no SUMMARY line did not finish',
           len(problems) == 1 and 'did not finish' in problems[0], repr(problems))
    expect('docs-log: CRLF lines read the same', lce.docs_log(clean.replace('\n', '\r\n')) == ([], []))
    path = os.path.join(tmp, 'docs.log')
    with open(path, 'w') as f:
        f.write(artnet)
    with contextlib.redirect_stdout(io.StringIO()) as out:
        code = lce.main(['docs-log', path])
    expect('docs-log: the command fails it, with an annotation naming the file',
           code == 1 and '::error title=lce packages::Beyond\'s docs parser, on /runner/stage/artnetxt/artnet.lcb'
           in out.getvalue(), repr((code, out.getvalue())))

    with open(lce.WORKFLOW, encoding='utf-8') as f:
        block = marked_block(f.read(), 'docs')
    expect('docs: the step is marked in lce-packages.yml, and reads its log with docs-log',
           block is not None and 'build-lce-packages.py docs-log "$RUNNER_TEMP/docs.log"' in block)
    if block is None or not shutil.which('bash'):
        print('SKIP docs: no bash here; the step is not run')
        return
    runner = os.path.join(tmp, 'runner')
    os.makedirs(os.path.join(runner, 'oxt', 'engine'))
    engine = os.path.join(runner, 'oxt', 'engine', 'server-community')
    with open(engine, 'w') as f:
        f.write(FAKE_ENGINE)
    os.chmod(engine, 0o755)

    def run(text, status=0):
        out_path = os.path.join(tmp, 'engine-out')
        with open(out_path, 'w') as f:
            f.write(text)
        env = dict(os.environ, RUNNER_TEMP=runner, FAKE_OUT=out_path, FAKE_STATUS=str(status))
        p = subprocess.run(['bash', '-c', block], env=env, cwd=lce.ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
        return p.returncode, p.stdout

    code, out = run(clean)
    expect('docs: the step passes a clean run', code == 0, repr((code, out)))
    code, out = run(artnet)
    expect('docs: ...fails one whose parser logged an error, though the engine exited 0',
           code == 1 and 'FAIL Beyond\'s docs parser, on /runner/stage/artnetxt/artnet.lcb' in out, repr((code, out)))
    code, out = run(lines(DOCS_INFO, OSC_FAIL, 'SUMMARY 0 1'), status=1)
    expect('docs: ...fails with the engine when the engine check failed', code == 1, repr((code, out)))
    code, out = run(lines(DOCS_INFO, 'PASS sodiumxt api.lcdoc'))
    expect('docs: ...fails a run that never printed its SUMMARY', code == 1 and 'did not finish' in out,
           repr((code, out)))
    code, out = run(lines(DOCS_INFO, OSC_WARNING, 'PASS oscxt api.lcdoc', 'SUMMARY 1 0'))
    expect('docs: ...and passes a warning, annotated', code == 0 and '::warning title=lce packages::' in out,
           repr((code, out)))


def main():
    with tempfile.TemporaryDirectory() as tmp:
        test_check(tmp)
        test_zip_order(tmp)
    test_table()
    test_wrap()
    test_registry()
    test_waiting()
    test_workflow_paths()
    with tempfile.TemporaryDirectory() as tmp:
        test_pure(tmp)
    with tempfile.TemporaryDirectory() as tmp:
        test_plan(tmp)
    with tempfile.TemporaryDirectory() as tmp:
        test_publish(tmp)
    with tempfile.TemporaryDirectory() as tmp:
        test_docs_log(tmp)
    if FAILURES:
        print('FAIL: %d fixture(s) did not hold' % len(FAILURES))
        return 1
    print('OK: every fixture held')
    return 0


if __name__ == '__main__':
    sys.exit(main())
