#!/usr/bin/env python3
"""test-build-lce-packages.py - fixture tests for tools/build-lce-packages.py.

Proves that `check` refuses each package shape the Extension Manager or the
layout rules refuse (and passes a good one), that `table` sees a row that
no longer matches the tree, and that a script library is wrapped the way
the IDE needs. Nothing here needs lc-compile or an engine: the engine half
(tools/lce-engine-check.lc) runs in .github/workflows/lce-packages.yml.

    python3 tools/test-build-lce-packages.py
"""

import copy
import importlib.util
import io
import os
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


def expect(label, ok):
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
    if not ok:
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
        expect('table holds on the tree', lce.check_table() == [])
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
        lce.PACKAGES.append(copy.deepcopy(saved[0]))
        expect('table sees an id used twice', any('twice' in p for p in lce.check_table()))
    finally:
        lce.PACKAGES[:] = saved
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


def main():
    with tempfile.TemporaryDirectory() as tmp:
        test_check(tmp)
        test_zip_order(tmp)
    test_table()
    test_wrap()
    if FAILURES:
        print('FAIL: %d fixture(s) did not hold' % len(FAILURES))
        return 1
    print('OK: every fixture held')
    return 0


if __name__ == '__main__':
    sys.exit(main())
