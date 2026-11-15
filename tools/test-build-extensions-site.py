#!/usr/bin/env python3
"""test-build-extensions-site.py - fixture tests for tools/build-extensions-site.py.

Builds the download page from a made-up release (real .lce zips, a real
SHA256SUMS, a GitHub API release object) and proves what the page must and
must not do: every package is listed with its own download link, version,
platforms and install order; text from a package is escaped; and every
release the builder must refuse (a checksum that does not match, a draft,
no packages, no SHA256SUMS, a package that is not a zip) writes no page and
leaves the last good one in place. Offline: no network, no engine.

    python3 tools/test-build-extensions-site.py
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('build_site', os.path.join(HERE, 'build-extensions-site.py'))
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)

FAILURES = []
BASE = 'https://github.com/example/suite/releases/download/v9/'


def expect(label, ok, detail=''):
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
    if not ok:
        FAILURES.append(label)
        if detail:
            print('    ' + detail)


def manifest(ident, title, version, requires=()):
    req = ''.join('<requires name="%s"/>' % r for r in requires)
    return ('<package version="0.0"><name>%s</name><title>%s</title><author>Someone</author>'
            '<version>%s</version><type>library</type>%s</package>' % (ident, title, version, req)).encode()


def lce(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return buf.getvalue()


LONG = ' '.join(['Sentence number %d says a little more.' % i for i in range(30)])

PACKAGES = {
    # a native library: Summary, two platforms, an engine module requirement
    'alphaxt-1.0.0.lce': lce([
        ('manifest.xml', manifest('org.example.alpha', 'AlphaXT', '1.0.0', ['com.livecode.foreign'])),
        ('api.lcdoc', 'Library: org.example.alpha\n\nType: library\n\nSummary:\nBindings to <alLib>, '
                      'the alpha library.\n\nMore prose here.\n\nName: alOpen\n\nType: function\n'),
        ('code/x86_64-win32/alpha.dll', b'MZ'), ('code/universal-mac/alpha.dylib', b'\xca\xfe'),
        ('code/riscv64-linux/alpha.so', b'\x7fELF')]),
    # its helpers: a script library that requires it
    'alphaxt-helpers-1.0.0.lce': lce([
        ('manifest.xml', manifest('alphaHelpers', 'AlphaXT helpers', '1.0.0', ['org.example.alpha'])),
        ('api.lcdoc', 'Library: alphaHelpers\n\nTitle: AlphaXT helpers\n\nDescription:\n'
                      'The everyday calls for alphaxt.\n\nTags: Library\n')]),
    # a script library whose documentation names another family, and whose
    # text tries to break out of the page
    'betaxt-2.0.0.lce': lce([
        ('manifest.xml', manifest('beta', 'Beta &lt;script&gt;alert(1)&lt;/script&gt;', '2.0.0')),
        ('api.lcdoc', 'Library: beta\n\nDescription:\nIt composes AlphaXT <img src=x onerror=alert(2)>. '
                      + LONG + '\n')]),
}


def release(**over):
    rel = {
        'tag_name': 'v9', 'name': 'Suite v9', 'draft': False, 'prerelease': True,
        'published_at': '2026-11-15T14:51:29Z', 'html_url': 'https://github.com/example/suite/releases/tag/v9',
        'assets': [{'name': n, 'browser_download_url': BASE + n,
                    'digest': 'sha256:' + hashlib.sha256(d).hexdigest()} for n, d in sorted(PACKAGES.items())]
                  + [{'name': 'SHA256SUMS', 'browser_download_url': BASE + 'SHA256SUMS'}],
    }
    rel.update(over)
    return rel


def write_release(tmp, rel, files=None, sums=None):
    files = dict(PACKAGES if files is None else files)
    if sums is None:
        sums = ''.join('%s  %s\n' % (hashlib.sha256(d).hexdigest(), n) for n, d in sorted(files.items()))
    if sums is not False:
        files['SHA256SUMS'] = sums.encode()
    lce_dir = os.path.join(tmp, 'files')
    shutil.rmtree(lce_dir, ignore_errors=True)
    os.makedirs(lce_dir)
    for n, d in files.items():
        with open(os.path.join(lce_dir, n), 'wb') as f:
            f.write(d)
    rel_json = os.path.join(tmp, 'release.json')
    with open(rel_json, 'w') as f:
        json.dump(rel, f)
    return rel_json, lce_dir


def build(tmp, rel, files=None, sums=None, out='out', extra=()):
    rel_json, lce_dir = write_release(tmp, rel, files, sums)
    out_dir = os.path.join(tmp, out)
    err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        code = site.main(['--out', out_dir, '--release-json', rel_json, '--lce-dir', lce_dir] + list(extra))
    page = None
    if os.path.isfile(os.path.join(out_dir, 'index.html')):
        with open(os.path.join(out_dir, 'index.html'), encoding='utf-8') as f:
            page = f.read()
    return code, page, err.getvalue()


def card(page, filename):
    start = page.index('id="pkg-%s"' % filename)
    return page[start:page.index('</article>', start)]


def test_good(tmp):
    code, page, err = build(tmp, release())
    expect('a good release builds', code == 0 and page is not None, err)
    if page is None:
        return
    for name in PACKAGES:
        expect('%s: its own download link' % name, 'href="%s%s" download' % (BASE, name) in card(page, name))
    expect('the SHA256SUMS link', 'href="%sSHA256SUMS"' % BASE in page)
    expect('the .nojekyll marker', os.path.isfile(os.path.join(tmp, 'out', '.nojekyll')))
    a = card(page, 'alphaxt-1.0.0.lce')
    expect('version from the manifest', '<dt>Version</dt><dd>1.0.0</dd>' in a)
    expect('native platforms in order, an unknown id kept',
           'Windows 64-bit, macOS (Intel and Apple silicon), riscv64-linux' in a, a)
    expect('Summary is the description, link brackets dropped',
           '<p>Bindings to alLib, the alpha library.</p>' in a, a)
    expect('an engine module is not something to install first', 'com.livecode' not in a
           and '<dt>Install first</dt><dd>nothing</dd>' in a)
    h = card(page, 'alphaxt-helpers-1.0.0.lce')
    expect('a script library runs everywhere', site.SCRIPT_PLATFORMS in h)
    expect('Description is the description', '<p>The everyday calls for alphaxt.</p>' in h)
    expect('install first links the required package',
           '<dt>Install first</dt><dd><a href="#pkg-alphaxt-1.0.0.lce">AlphaXT</a></dd>' in h, h)
    expect('a required family is not repeated as works-with', 'Works with' not in h)
    expect('a package comes before the one that requires it',
           page.index('id="pkg-alphaxt-1.0.0.lce"') < page.index('id="pkg-alphaxt-helpers-1.0.0.lce"'))
    b = card(page, 'betaxt-2.0.0.lce')
    expect('a family named in the documentation is works-with',
           '<dt>Works with</dt><dd><a href="#pkg-alphaxt-1.0.0.lce">AlphaXT</a></dd>' in b, b)
    expect('no markup from a package reaches the page',
           '<script>alert' not in page and '<img' not in page and '&lt;script&gt;' in b
           and '&lt;img src=x' in b, b[:400])
    expect('a long description is shortened at a sentence',
           'Sentence number 29' not in b and 'Sentence number 0' in b and 'more.</p>' in b)
    expect('the SHA-256 is on the card', hashlib.sha256(PACKAGES['betaxt-2.0.0.lce']).hexdigest() in b)
    expect('a pre-release says so', 'This is a pre-release' in page)
    expect('the count of packages', '3 packages' in page)
    expect('a jump link to every family', 'href="#alphaxt">alphaxt</a> &middot; <a href="#betaxt">' in page)
    _, page2, _ = build(tmp, release(prerelease=False), out='out2')
    expect('a full release does not say pre-release', page2 is not None and 'pre-release' not in page2)
    _, page3, _ = build(tmp, release(), out='out3')
    expect('the same release makes the same page', page3 == page)


def refuses(tmp, label, needle, **kw):
    # the last good page must survive a refused build
    out = os.path.join(tmp, 'kept')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'index.html'), 'w') as f:
        f.write('LAST GOOD')
    code, page, err = build(tmp, out='kept', **kw)
    expect('refuses %s' % label, code == 1 and needle in err and page == 'LAST GOOD', 'code %r err %r' % (code, err))


def test_refusals(tmp):
    good = release()
    bad_sums = ''.join('%s  %s\n' % ('0' * 64 if n.startswith('beta') else hashlib.sha256(d).hexdigest(), n)
                       for n, d in sorted(PACKAGES.items()))
    refuses(tmp, 'a package that does not match SHA256SUMS', 'does not match SHA256SUMS', rel=good, sums=bad_sums)
    unlisted = ''.join('%s  %s\n' % (hashlib.sha256(d).hexdigest(), n)
                       for n, d in sorted(PACKAGES.items()) if not n.startswith('beta'))
    refuses(tmp, 'a package SHA256SUMS does not list', 'not listed', rel=good, sums=unlisted)
    wrong = release()
    wrong['assets'][0]['digest'] = 'sha256:' + 'f' * 64
    refuses(tmp, 'a package that does not match GitHub\'s digest', 'digest GitHub recorded', rel=wrong)
    nosums = release()
    nosums['assets'] = [a for a in nosums['assets'] if a['name'] != 'SHA256SUMS']
    refuses(tmp, 'a release without SHA256SUMS', 'no SHA256SUMS', rel=nosums, sums=False)
    refuses(tmp, 'a release with no packages', 'no published release has .lce',
            rel=release(assets=[{'name': 'SHA256SUMS', 'browser_download_url': BASE + 'SHA256SUMS'}]))
    refuses(tmp, 'a draft', 'no published release', rel=release(draft=True))
    refuses(tmp, 'a named draft', 'is a draft', rel=release(draft=True), extra=['--tag', 'v9'])
    refuses(tmp, 'a tag that is not there', 'no release tagged v8', rel=release(), extra=['--tag', 'v8'])
    broken = dict(PACKAGES)
    broken['betaxt-2.0.0.lce'] = b'not a zip'
    rel = release()
    rel['assets'] = [dict(a, digest='sha256:' + hashlib.sha256(broken[a['name']]).hexdigest())
                     if a['name'] in broken else a for a in rel['assets']]
    refuses(tmp, 'a package that is not a zip', 'not a readable extension package', rel=rel, files=broken)
    nover = dict(PACKAGES)
    nover['betaxt-2.0.0.lce'] = lce([('manifest.xml', b'<package><name>beta</name></package>')])
    rel = release()
    rel['assets'] = [dict(a, digest='sha256:' + hashlib.sha256(nover[a['name']]).hexdigest())
                     if a['name'] in nover else a for a in rel['assets']]
    refuses(tmp, 'a manifest with no version', 'no id or version', rel=rel, files=nover)


def test_pick_release():
    older = release(tag_name='v8', published_at='2026-11-01T00:00:00Z')
    newer = release(tag_name='v9')
    draft = release(tag_name='v10', draft=True, published_at=None)
    expect('the newest published release', site.pick_release([older, draft, newer])['tag_name'] == 'v9')
    expect('a named older release', site.pick_release([older, newer], 'v8')['tag_name'] == 'v8')
    expect('a single release object', site.pick_release(newer)['tag_name'] == 'v9')


def test_description():
    doc = 'Library: x\n\nDescription:\nFirst line\nsecond line.\n\nSecond paragraph.\n\nName: h\n\nSummary: not this\n'
    expect('the first paragraph only, joined', site.lcdoc_description(doc) == 'First line second line.')
    expect('a handler entry is never the description',
           site.lcdoc_description('Library: x\n\nName: h\n\nSummary: a handler\n') == '')
    expect('CRLF documents read the same',
           site.lcdoc_description(doc.replace('\n', '\r\n')) == 'First line second line.')
    expect('a short text is not cut', site.shorten('Short.') == 'Short.')


def main():
    tmp = tempfile.mkdtemp(prefix='test-extensions-site-')
    try:
        test_good(tmp)
        test_refusals(tmp)
        test_pick_release()
        test_description()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if FAILURES:
        print('test-build-extensions-site: %d FAILED' % len(FAILURES))
        return 1
    print('test-build-extensions-site: OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
