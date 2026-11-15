#!/usr/bin/env python3
"""build-extensions-site.py - the download page for the suite's .lce packages.

WHY THIS EXISTS
    The extensions reach people who do not use OXT-Beyond (where they are
    built in) as .lce packages attached to a GitHub release
    (.github/workflows/lce-packages.yml). A release page is a bare list of
    file names, and someone on HyperXTalk or LiveCode Community 9.6.3 has to
    guess what "nostrxt-relay-0.1.0.lce" is, what it needs first and whether
    it has a library for their platform. This tool writes one plain static
    page that says so for every package, and .github/workflows/pages.yml
    publishes it to GitHub Pages each time a release is published.

    Everything on the page is READ FROM THE RELEASE, never typed here, so
    the page cannot drift from what the release holds (root CLAUDE.md:
    hand-copied numbers go stale silently):

      title, id, version, author, requires   the package's manifest.xml
      description                            the library entry of its
                                             api.lcdoc (Description: or
                                             Summary:), first paragraph
      platforms                              its code/<platform-id>/ folders;
                                             none means a script library,
                                             which runs on every platform
      size, download link                    the release asset
      SHA-256                                the release's SHA256SUMS

    It fails closed: a package whose bytes do not match SHA256SUMS (or the
    digest GitHub recorded for the asset), a package without a readable
    manifest, or a release with no .lce at all is an error and no page is
    written. A broken page is worse than yesterday's page.

WHICH RELEASE
    The newest PUBLISHED release that has .lce assets (a draft's assets are
    not downloadable by visitors), or the one --tag names. A pre-release is
    allowed, and the page says it is one.

USAGE
    python3 tools/build-extensions-site.py --out DIR [--tag TAG] [--repo OWNER/NAME]
        fetch the release from GitHub (GITHUB_TOKEN is used when set) and
        write DIR/index.html and DIR/.nojekyll
    python3 tools/build-extensions-site.py --out DIR --release-json FILE --lce-dir DIR2
        the same offline: FILE is the GitHub API's release object (or a list
        of them), DIR2 holds the release's .lce files and SHA256SUMS

    tools/test-build-extensions-site.py fixture-proves it.
"""

import argparse
import hashlib
import html
import io
import json
import os
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

REPO = 'SethMorrowSoftware/xtalk-suite'
API = 'https://api.github.com'

# The platform folders a package's code/ can hold (build-lce-packages.py
# PLATFORMS), in the order the page lists them, with the words a visitor
# knows. An id not named here is shown as it is, never dropped.
PLATFORM_NAMES = [
    ('x86_64-win32', 'Windows 64-bit'),
    ('x86-win32', 'Windows 32-bit'),
    ('universal-mac', 'macOS (Intel and Apple silicon)'),
    ('x86_64-linux', 'Linux 64-bit'),
    ('x86-linux', 'Linux 32-bit'),
    ('arm64-linux', 'Linux ARM64'),
]
SCRIPT_PLATFORMS = 'Every platform (script library, no native code)'

# The engine's own modules every LCB package requires: not something a user
# installs, so not listed as a requirement
ENGINE_MODULE = re.compile(r'^com\.livecode\.')

# Longest description the page shows; the rest is in the Dictionary
MAX_DESCRIPTION = 420


class Problem(Exception):
    pass


# --- reading a release -------------------------------------------------------

def http_get(url, accept='application/vnd.github+json'):
    req = urllib.request.Request(url, headers={'Accept': accept, 'User-Agent': 'xtalk-suite-site-builder'})
    token = os.environ.get('GITHUB_TOKEN')
    if token and url.startswith(API):
        req.add_header('Authorization', 'Bearer ' + token)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def lce_assets(release):
    return [a for a in release.get('assets', []) if a.get('name', '').endswith('.lce')]


def pick_release(releases, tag=None):
    """The release the page is built from: the one named, or the newest
    published one that carries .lce packages."""
    if isinstance(releases, dict):
        releases = [releases]
    if tag:
        found = [r for r in releases if r.get('tag_name') == tag]
        if not found:
            raise Problem('no release tagged %s' % tag)
        rel = found[0]
        if rel.get('draft'):
            raise Problem('release %s is a draft: visitors cannot download its files' % tag)
        if not lce_assets(rel):
            raise Problem('release %s has no .lce packages' % tag)
        return rel
    usable = [r for r in releases if not r.get('draft') and lce_assets(r)]
    if not usable:
        raise Problem('no published release has .lce packages')
    return max(usable, key=lambda r: r.get('published_at') or '')


def parse_sums(text):
    sums = {}
    for line in text.splitlines():
        m = re.match(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$', line)
        if m:
            sums[m.group(2)] = m.group(1).lower()
    return sums


# --- reading a package -------------------------------------------------------

def library_entry(text):
    """The library entry of an api.lcdoc: everything before the first
    handler entry."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    return re.split(r'\n(?=Name:)', text, maxsplit=1)[0]


def lcdoc_description(text):
    """The first paragraph of the library entry's Description (script
    libraries) or Summary (LCB libraries), as plain text."""
    head = library_entry(text)
    lines = head.split('\n')
    for key in ('Description', 'Summary'):
        for i, line in enumerate(lines):
            if line.strip() != key + ':' and not line.startswith(key + ': '):
                continue
            body = [line.split(':', 1)[1].strip()] if line.split(':', 1)[1].strip() else []
            for nxt in lines[i + 1:]:
                if re.match(r'^[A-Z][A-Za-z ]*:(\s|$)', nxt):
                    break
                if not nxt.strip():
                    if body:
                        break
                    continue
                body.append(nxt.strip())
            para = ' '.join(body)
            # <handlerName> is a Dictionary link; on the page it is a name
            para = re.sub(r'<([A-Za-z][A-Za-z0-9_.]*)>', r'\1', para)
            if para:
                return shorten(para)
    return ''


def shorten(text, limit=MAX_DESCRIPTION):
    if len(text) <= limit:
        return text
    cut = text[:limit]
    end = cut.rfind('. ')
    if end > limit // 2:
        return cut[:end + 1]
    return cut[:cut.rfind(' ')] + ' ...'


def read_package(name, data):
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
        names = zf.namelist()
        manifest = ET.fromstring(zf.read('manifest.xml'))
    except (zipfile.BadZipFile, KeyError, ET.ParseError) as e:
        raise Problem('%s: not a readable extension package (%s)' % (name, e))

    def field(tag):
        el = manifest.find(tag)
        return (el.text or '').strip() if el is not None else ''

    ident = field('name')
    if not ident or not field('version'):
        raise Problem('%s: manifest.xml names no id or version' % name)
    platforms = sorted({n.split('/')[1] for n in names if n.startswith('code/') and n.count('/') >= 2})
    doc = entry = ''
    if 'api.lcdoc' in names:
        lcdoc = zf.read('api.lcdoc').decode('utf-8', 'replace')
        doc, entry = lcdoc_description(lcdoc), library_entry(lcdoc)
    return {
        'file': name,
        'id': ident,
        'title': field('title') or ident,
        'version': field('version'),
        'author': field('author'),
        'requires': [r.get('name') for r in manifest.findall('requires')
                     if r.get('name') and not ENGINE_MODULE.match(r.get('name'))],
        'platforms': platforms,
        'description': doc,
        'entry': entry,
    }


def family(filename):
    """The member a package belongs to: curlxt-tsnet-0.1.0.lce -> curlxt."""
    return filename.split('-', 1)[0].rsplit('.lce', 1)[0]


def collect(release, fetch):
    """[package] for every .lce of the release, each checked against
    SHA256SUMS and GitHub's own digest. fetch(asset) returns its bytes."""
    assets = lce_assets(release)
    sums_asset = [a for a in release.get('assets', []) if a.get('name') == 'SHA256SUMS']
    if not sums_asset:
        raise Problem('release %s has no SHA256SUMS' % release.get('tag_name'))
    sums = parse_sums(fetch(sums_asset[0]).decode('utf-8', 'replace'))
    packages = []
    for a in assets:
        data = fetch(a)
        digest = hashlib.sha256(data).hexdigest()
        if sums.get(a['name']) != digest:
            raise Problem('%s: SHA-256 %s does not match SHA256SUMS (%s)'
                          % (a['name'], digest, sums.get(a['name'], 'not listed')))
        gh = a.get('digest') or ''
        if gh.startswith('sha256:') and gh[7:].lower() != digest:
            raise Problem('%s: SHA-256 %s does not match the digest GitHub recorded (%s)'
                          % (a['name'], digest, gh))
        pkg = read_package(a['name'], data)
        pkg.update({'url': a['browser_download_url'], 'size': len(data), 'sha256': digest,
                    'family': family(a['name'])})
        packages.append(pkg)
    return packages, sums_asset[0]['browser_download_url']


# --- writing the page --------------------------------------------------------

def esc(s):
    return html.escape(s or '', quote=True)


def human_size(n):
    for unit in ('bytes', 'KB', 'MB', 'GB'):
        if n < 1024 or unit == 'GB':
            return ('%d %s' % (n, unit)) if unit == 'bytes' else ('%.1f %s' % (n, unit))
        n /= 1024.0


def platform_text(ids):
    if not ids:
        return SCRIPT_PLATFORMS
    known = dict(PLATFORM_NAMES)
    ordered = [pid for pid, _ in PLATFORM_NAMES if pid in ids] + sorted(i for i in ids if i not in known)
    return ', '.join(known.get(pid, pid) for pid in ordered)


def base_packages(packages):
    """{family: the package of that family that needs no other of it}."""
    out = {}
    for p in packages:
        fam = [q for q in packages if q['family'] == p['family']]
        ids = {q['id'] for q in fam}
        if not any(r in ids for r in p['requires']):
            out.setdefault(p['family'], p)
    return out


def works_with(p, packages):
    """Other families a package's own documentation names, beyond what its
    manifest requires: nostrxt's entry says its hashes and signatures come
    from CoinXT and SodiumXT, which the Extension Manager does not enforce,
    and a visitor who installs nostrxt alone should know. A name is not
    always a dependency (CoinXT names SodiumXT only as a source of random
    bytes), so the page says "Works with", never "Needs". Read from the
    release (the family name as a word in the library entry), never
    listed here."""
    by_id = {q['id']: q for q in packages}
    required = {by_id[r]['family'] for r in p['requires'] if r in by_id}
    found = []
    for fam, base in sorted(base_packages(packages).items()):
        if fam == p['family'] or fam in required:
            continue
        if re.search(r'(?<![A-Za-z0-9])%s(?![A-Za-z0-9])' % re.escape(fam), p.get('entry', ''), re.I):
            found.append(base)
    return found


def order(packages):
    """Families alphabetically; inside one, a package before any that
    requires it, so reading down the page is an install order."""
    by_id = {p['id']: p for p in packages}

    def depth(p, seen=()):
        deps = [by_id[r] for r in p['requires'] if r in by_id and r not in seen]
        return 1 + max([depth(d, seen + (p['id'],)) for d in deps] or [0])

    return sorted(packages, key=lambda p: (p['family'], depth(p), p['file']))


CSS = '''
:root { --bg: #ffffff; --fg: #1d1d1f; --muted: #5f6368; --card: #f6f7f9; --line: #dfe1e5;
        --link: #0b57d0; --note-bg: #fff6d6; --note-line: #e6c34a; color-scheme: light dark; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #16181c; --fg: #e8eaed; --muted: #a0a4ab; --card: #20232a; --line: #33373f;
          --link: #8ab4f8; --note-bg: #2f2a17; --note-line: #8a7426; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg);
       font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { font-size: 1.7rem; margin: 0 0 4px; }
h2 { font-size: 1.25rem; margin: 32px 0 8px; }
h3 { font-size: 1.05rem; margin: 0; }
a { color: var(--link); }
.sub { color: var(--muted); margin: 0 0 16px; }
.jump { line-height: 1.9; }
.note { background: var(--note-bg); border-left: 4px solid var(--note-line); padding: 8px 12px; border-radius: 4px; }
ol li { margin-bottom: 4px; }
.family { margin-top: 28px; }
.family > h2 { margin-bottom: 10px; text-transform: none; }
.pkg { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; margin: 10px 0; }
.pkg header { display: flex; flex-wrap: wrap; gap: 4px 12px; align-items: baseline; justify-content: space-between; }
.pkg p { margin: 8px 0; }
.pkg dl { display: grid; grid-template-columns: max-content 1fr; gap: 2px 12px; margin: 8px 0; font-size: 0.92rem; }
.pkg dt { color: var(--muted); }
.pkg dd { margin: 0; overflow-wrap: anywhere; }
.dl { display: inline-block; padding: 6px 14px; border-radius: 6px; background: var(--link); color: var(--bg);
      text-decoration: none; font-weight: 600; }
code { font-size: 0.9em; overflow-wrap: anywhere; }
.sha { font-size: 0.78rem; color: var(--muted); }
footer { margin-top: 40px; color: var(--muted); font-size: 0.9rem; }
'''


def render(release, packages, sums_url, repo=REPO):
    tag = release.get('tag_name', '')
    rel_url = release.get('html_url') or 'https://github.com/%s/releases/tag/%s' % (repo, tag)
    published = (release.get('published_at') or '')[:10]
    by_id = {p['id']: p for p in packages}
    out = []
    w = out.append
    w('<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      '<title>xTalk Suite extensions</title>\n'
      '<meta name="description" content="Extension packages (.lce) for HyperXTalk, LiveCode Community and OpenXTalk.">\n'
      '<style>%s</style>\n</head>\n<body>\n<main>\n' % CSS)
    w('<h1>xTalk Suite extensions</h1>\n')
    w('<p class="sub">Extensions for HyperXTalk, LiveCode Community 9 and OpenXTalk, '
      'from release <a href="%s">%s</a>%s. %d packages.</p>\n'
      % (esc(rel_url), esc(tag), (', published ' + esc(published)) if published else '', len(packages)))
    if release.get('prerelease'):
        w('<p class="note">This is a pre-release: the extensions are new, and most of the testing '
          'so far has been in OXT-Beyond. Please report anything that goes wrong on the '
          '<a href="https://github.com/%s/issues">issue tracker</a>.</p>\n' % esc(repo))

    w('<h2>How to install</h2>\n<ol>\n'
      '<li>Download the <code>.lce</code> file for the extension you want. Do not unzip it.</li>\n'
      '<li>In HyperXTalk or LiveCode Community 9, choose <b>Tools &gt; Extension Manager</b>.</li>\n'
      '<li>Click the <b>+</b> button and choose the <code>.lce</code> file.</li>\n'
      '<li>Some extensions need another one installed first; each card says which under '
      '"Install first". Installing a group from the top down gets the order right. '
      '"Works with" names other extensions its documentation pairs it with: '
      'some of its features may need them.</li>\n'
      '</ol>\n'
      '<p>The extension is then loaded every time the IDE starts, and its handlers are in the Dictionary. '
      'To put one in a standalone, tick it in <b>Standalone Application Settings</b>, on the '
      '<b>Inclusions</b> pane (choose "Select inclusions for the standalone application").</p>\n'
      '<p>Packages marked "script library" are plain script and run anywhere the IDE runs. '
      'The others carry a native library for each platform listed on their card. The macOS libraries '
      'are not signed or notarized, so macOS may ask before it lets them load.</p>\n'
      '<p>To check a download, compare its SHA-256 (on its card, and in '
      '<a href="%s">SHA256SUMS</a>) with what your computer reports.</p>\n' % esc(sums_url))

    w('<h2>Extensions</h2>\n')
    families = sorted({p['family'] for p in packages})
    w('<p class="jump">%s</p>\n' % ' &middot; '.join('<a href="#%s">%s</a>' % (esc(f), esc(f)) for f in families))
    current = None
    for p in order(packages):
        if p['family'] != current:
            if current is not None:
                w('</section>\n')
            current = p['family']
            w('<section class="family" id="%s">\n<h2>%s</h2>\n' % (esc(current), esc(current)))
        kind = 'script library' if not p['platforms'] else 'native library'
        needs = []
        for r in p['requires']:
            dep = by_id.get(r)
            needs.append('<a href="#pkg-%s">%s</a>' % (esc(dep['file']), esc(dep['title'])) if dep
                         else '<code>%s</code>' % esc(r))
        w('<article class="pkg" id="pkg-%s">\n<header><h3>%s</h3>'
          '<a class="dl" href="%s" download>Download %s</a></header>\n'
          % (esc(p['file']), esc(p['title']), esc(p['url']), esc(p['file'])))
        if p['description']:
            w('<p>%s</p>\n' % esc(p['description']))
        w('<dl>\n<dt>Version</dt><dd>%s</dd>\n' % esc(p['version']))
        w('<dt>Kind</dt><dd>%s</dd>\n' % kind)
        w('<dt>Platforms</dt><dd>%s</dd>\n' % esc(platform_text(p['platforms'])))
        w('<dt>Install first</dt><dd>%s</dd>\n' % (', '.join(needs) if needs else 'nothing'))
        also = works_with(p, packages)
        if also:
            w('<dt>Works with</dt><dd>%s</dd>\n' % ', '.join(
                '<a href="#pkg-%s">%s</a>' % (esc(b['file']), esc(b['title'])) for b in also))
        if p['author']:
            w('<dt>Author</dt><dd>%s</dd>\n' % esc(p['author']))
        w('<dt>Extension id</dt><dd><code>%s</code></dd>\n' % esc(p['id']))
        w('<dt>Size</dt><dd>%s</dd>\n' % esc(human_size(p['size'])))
        w('<dt>SHA-256</dt><dd class="sha"><code>%s</code></dd>\n</dl>\n</article>\n' % esc(p['sha256']))
    if current is not None:
        w('</section>\n')

    w('<footer>\n<p>OXT-Beyond includes all of these already, so its users need nothing from this page.</p>\n'
      '<p>Built from <a href="%s">release %s</a> of <a href="https://github.com/%s">xtalk-suite</a> '
      'by <code>tools/build-extensions-site.py</code>. Source code, documentation and licences '
      'are in that repository; each package also carries its licences.</p>\n</footer>\n'
      % (esc(rel_url), esc(tag), esc(repo)))
    w('</main>\n</body>\n</html>\n')
    return ''.join(out)


def write_site(out_dir, page):
    os.makedirs(out_dir, exist_ok=True)
    # a temporary file then a rename: a failed run never leaves half a page
    fd, tmp = tempfile.mkstemp(dir=out_dir, suffix='.tmp')
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    os.replace(tmp, os.path.join(out_dir, 'index.html'))
    # GitHub Pages: serve the folder as it is, without Jekyll
    open(os.path.join(out_dir, '.nojekyll'), 'w').close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', required=True, help='folder to write index.html into')
    ap.add_argument('--tag', help='build from this release instead of the newest one')
    ap.add_argument('--repo', default=REPO, help='OWNER/NAME (default %(default)s)')
    ap.add_argument('--release-json', help='offline: the GitHub API release object, or a list of them')
    ap.add_argument('--lce-dir', help='offline: the folder holding the release files')
    args = ap.parse_args(argv)
    if bool(args.release_json) != bool(args.lce_dir):
        ap.error('--release-json and --lce-dir go together')

    try:
        if args.release_json:
            with open(args.release_json, encoding='utf-8') as f:
                releases = json.load(f)

            def fetch(asset):
                path = os.path.join(args.lce_dir, asset['name'])
                if not os.path.isfile(path):
                    raise Problem('%s: not in %s' % (asset['name'], args.lce_dir))
                with open(path, 'rb') as f:
                    return f.read()
        else:
            if args.tag:
                releases = json.loads(http_get('%s/repos/%s/releases/tags/%s' % (API, args.repo, args.tag)))
            else:
                releases = json.loads(http_get('%s/repos/%s/releases?per_page=30' % (API, args.repo)))

            def fetch(asset):
                return http_get(asset['browser_download_url'], accept='application/octet-stream')

        release = pick_release(releases, args.tag)
        packages, sums_url = collect(release, fetch)
        write_site(args.out, render(release, packages, sums_url, args.repo))
    except Problem as e:
        print('build-extensions-site: ' + str(e), file=sys.stderr)
        return 1
    print('build-extensions-site: %s/index.html from %s (%d packages%s)'
          % (args.out, release['tag_name'], len(packages), ', pre-release' if release.get('prerelease') else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
