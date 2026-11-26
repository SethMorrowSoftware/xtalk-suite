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
                                             none means a script library, or
                                             an LCB library with no native
                                             code (module.lcm and no code/),
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
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SUITE_ROOT = os.path.dirname(HERE)
REPO = 'SethMorrowSoftware/xtalk-suite'
API = 'https://api.github.com'

# The platform folders a package's code/ can hold (build-lce-packages.py
# PLATFORMS), in the order the page lists them, with the words a visitor
# knows. An id not named here is shown as it is, never dropped.
PLATFORM_NAMES = [
    ('x86_64-win32', 'Windows 64-bit', 'Win 64'),
    ('x86-win32', 'Windows 32-bit', 'Win 32'),
    ('universal-mac', 'macOS (Intel and Apple silicon)', 'macOS'),
    ('x86_64-linux', 'Linux 64-bit', 'Linux 64'),
    ('x86-linux', 'Linux 32-bit', 'Linux 32'),
    ('arm64-linux', 'Linux ARM64', 'Linux ARM'),
    # Android (2026-11-18): one chip per ABI, as with the desktop rows. Most
    # phones and tablets are the first; the x86 pair is emulators and a few
    # Chromebooks.
    ('arm64-android', 'Android phones and tablets (64-bit ARM)', 'Android ARM64'),
    ('armv7-android', 'Older Android devices (32-bit ARM)', 'Android ARM32'),
    ('x86_64-android', 'Android on 64-bit x86 (emulators, Chromebooks)', 'Android x86-64'),
    ('x86-android', 'Android on 32-bit x86 (emulators)', 'Android x86'),
]
SCRIPT_PLATFORMS = 'Every platform (script library, no native code)'
# an LCB module that binds no library of its own (native=False in
# tools/build-lce-packages.py, such as showcontrol's Art-Net)
LCB_PLATFORMS = 'Every platform (LiveCode Builder, no native code)'

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

# The keys an api.lcdoc entry is made of (Beyond's docs parser writes them;
# "author:" and "version:" arrive lower-case). Only a line that starts with
# one of these ends a field: a description line such as "Note: ..." or a
# parameter line ("pRequest: A handle ...") is text, not a key.
LCDOC_KEYS = frozenset(('library', 'type', 'title', 'author', 'description', 'summary', 'tags', 'name',
                        'syntax', 'returns', 'parameters', 'references', 'example', 'examples', 'version',
                        'os', 'platforms', 'associations', 'introduced', 'changes', 'related'))


def lcdoc_entries(text):
    """An api.lcdoc as [entry text]: the library entry first, then one per
    handler (each starts with "Name:")."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    return re.split(r'\n(?=Name:)', text)


def library_entry(text):
    return lcdoc_entries(text)[0]


def lcdoc_fields(entry):
    """{key (lower case): [lines]} of one entry, in the order met."""
    fields, key = {}, None
    for line in entry.split('\n'):
        m = re.match(r'^([A-Za-z][A-Za-z ]*):(?:\s+(.*))?$', line)
        if m and m.group(1).lower() in LCDOC_KEYS:
            key = m.group(1).lower()
            fields.setdefault(key, [])
            if m.group(2) and m.group(2).strip():
                fields[key].append(m.group(2).rstrip())
        elif key is not None:
            fields[key].append(line.rstrip())
    return fields


def paragraphs(lines):
    """[[line]] split on blank lines, with no empty paragraph."""
    out, cur = [], []
    for line in lines:
        if line.strip():
            cur.append(line)
        elif cur:
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def flat(par):
    return ' '.join(l.strip() for l in par)


def lcdoc_about(text):
    """The library entry's Description (script libraries) or Summary (LCB
    libraries) as paragraphs, and its tags."""
    fields = lcdoc_fields(library_entry(text))
    about = paragraphs(fields.get('description') or fields.get('summary') or [])
    tags = [t.strip() for t in ' '.join(fields.get('tags', [])).split(',') if t.strip()]
    # "Library" is every package's tag: it says nothing
    return about, [t for t in tags if t.lower() != 'library']


def lcdoc_description(text):
    """The first paragraph of the library entry, as short plain text."""
    about, _ = lcdoc_about(text)
    if not about:
        return ''
    # <handlerName> is a Dictionary link; in plain text it is a name
    return shorten(re.sub(r'<([A-Za-z][A-Za-z0-9_.]*)>', r'\1', flat(about[0])))


def lcdoc_handlers(text):
    """[{name, type, syntax, summary}] of every handler entry."""
    out = []
    for entry in lcdoc_entries(text)[1:]:
        f = lcdoc_fields(entry)
        name = ' '.join(f.get('name', [])).strip()
        if not name:
            continue
        summary = paragraphs(f.get('summary', []))
        out.append({'name': name, 'type': ' '.join(f.get('type', [])).strip(),
                    'syntax': (f.get('syntax') or [''])[0].strip(),
                    'summary': flat(summary[0]) if summary else ''})
    return out


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
    doc, entry, about, tags, handlers = '', '', [], [], []
    if 'api.lcdoc' in names:
        lcdoc = zf.read('api.lcdoc').decode('utf-8', 'replace')
        doc, entry = lcdoc_description(lcdoc), library_entry(lcdoc)
        about, tags = lcdoc_about(lcdoc)
        handlers = lcdoc_handlers(lcdoc)
    return {
        'file': name,
        'stem': name[:-len('-%s.lce' % field('version'))] if name.endswith('-%s.lce' % field('version'))
                else name[:-len('.lce')],
        'id': ident,
        'title': field('title') or ident,
        'version': field('version'),
        'author': field('author'),
        'requires': [r.get('name') for r in manifest.findall('requires')
                     if r.get('name') and not ENGINE_MODULE.match(r.get('name'))],
        'platforms': platforms,
        'lcb': 'module.lcm' in names,
        'description': doc,
        'entry': entry,
        'about': about,
        'tags': tags,
        'handlers': handlers,
        'licences': sorted(n.split('/', 1)[1] for n in names if n.startswith('licenses/') and not n.endswith('/')),
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


# --- the OpenXTalk family bar ---------------------------------------------
#
# The same slim strip of links across the top of the three sites of the
# OpenXTalk family (2026-11-26): OXT-Beyond's (its tools/pages/family.py,
# the master copy), this page, and the OXT Community Stacks gallery (its
# tools/build_site.py). FAMILY, FAMILY_CSS, MARK and family_bar are copies of the
# master's: change the three together. It is inline and draws its mark in
# SVG, so the page still loads nothing.

BEYOND = 'https://sethmorrowsoftware.github.io/OpenXTalk-Beyond/'
GALLERY = 'https://oxt-stacks.github.io/oxt-community-stacks/'
FORUM = 'https://openxtalk.org/forum/'
OPENXTALK = 'https://openxtalk.org/'

# (key, words, address): the bar's links, in their order, the same on
# every site. A site gives its own pages by key (relative, so a preview
# or a fork links itself) and leaves out a key it maps to None.
FAMILY = (
    ('beyond', 'OXT-Beyond', BEYOND),
    ('ide', 'Web IDE', BEYOND + 'ide/'),
    ('lessons', 'Lessons', BEYOND + 'lessons/'),
    ('extensions', 'Extensions', BEYOND + 'extensions/'),
    ('stacks', 'Community stacks', GALLERY),
    ('forum', 'Forum', FORUM),
)

# The bar's look, whole: every rule is under .oxt-family, and it resets
# what a page's own rules for nav, ul, li and a could give it, so it looks
# the same on every page of every site, light or dark.
FAMILY_CSS = (
    '.oxt-family{position:relative;z-index:60;display:flex;align-items:center;gap:0 10px;margin:0;'
    'padding:0 max(16px,env(safe-area-inset-right)) 0 max(16px,env(safe-area-inset-left));'
    'min-height:40px;background:#0a0f1a;border-bottom:1px solid rgba(255,255,255,.09);color:#c3cddc;'
    'font:500 13.5px/1.2 system-ui,-apple-system,"Segoe UI",Roboto,Ubuntu,sans-serif;letter-spacing:0;'
    'text-align:left;white-space:nowrap;overflow-x:auto;scrollbar-width:none;-webkit-font-smoothing:antialiased;'
    # a row longer than a phone scrolls sideways; its right edge fades to
    # say so (on a wide window the edge is empty, and the fade unseen)
    '-webkit-mask-image:linear-gradient(90deg,#000 calc(100% - 28px),transparent);'
    'mask-image:linear-gradient(90deg,#000 calc(100% - 28px),transparent)}'
    '.oxt-family::-webkit-scrollbar{display:none}'
    '.oxt-family a{color:inherit;font:inherit;letter-spacing:inherit;text-transform:none;text-decoration:none;'
    'background:none;box-shadow:none;border:0;border-radius:0;margin:0;min-height:0}'
    '.oxt-family .oxt-family-home{display:inline-flex;flex:none;align-items:center;gap:8px;padding:8px 6px 8px 0;'
    'color:#eef3ff;font-weight:700}'
    '.oxt-family .oxt-family-home svg{display:block;width:22px;height:22px;flex:none}'
    '.oxt-family ul{display:flex;flex:none;gap:0;margin:0;padding:0;list-style:none;background:none}'
    '.oxt-family li{margin:0;padding:0;list-style:none}'
    '.oxt-family li::before{content:none}'
    '.oxt-family li a{display:block;padding:12px 9px 10px;border-bottom:2px solid transparent}'
    '.oxt-family li:last-child a{margin-right:20px}'
    '.oxt-family li a:hover{color:#fff;border-bottom-color:rgba(255,179,71,.55)}'
    '.oxt-family li a[aria-current="page"]{color:#fff;border-bottom-color:#ff7a00}'
    '.oxt-family a:focus-visible{outline:2px solid #ffb347;outline-offset:-3px;border-radius:4px}'
    '@media (max-width:640px){.oxt-family .oxt-family-home span{display:none}}'
    '@media print{.oxt-family{display:none}}'
)

# The family's mark: a small tile in OXT-Beyond's fire, with its bolt
MARK = ('<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
        '<defs><linearGradient id="oxt-family-fire" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#ffc24d"/><stop offset=".55" stop-color="#ff7700"/>'
        '<stop offset="1" stop-color="#ff3d00"/></linearGradient></defs>'
        '<rect x="1" y="1" width="22" height="22" rx="6" fill="url(#oxt-family-fire)"/>'
        '<path d="M13.6 4.5 7.5 13.2h4.1l-1.3 6.3 6.2-8.8h-4.1z" fill="#1a1206"/></svg>')


SHOW_CURRENT = ('<script>(function (n) {'
                'var c = n && n.querySelector(\'[aria-current="page"]\');'
                'if (c && n.scrollWidth > n.clientWidth) n.scrollLeft = c.offsetLeft - 48;'
                '})(document.currentScript && document.currentScript.previousElementSibling);</script>')


def family_bar(current=None, links=None):
    """The bar, as HTML: its <style> and its <nav>. `current` is the key
    of the part the page is in, which the bar marks for the eye and for
    screen readers; `links` maps a key to this site's own address for it,
    or to None to leave it out."""
    links = links or {}
    items = []
    for key, words, href in FAMILY:
        href = links.get(key, href)
        if href is None:
            continue
        items.append('<li><a href="%s"%s>%s</a></li>' % (
            html.escape(href, quote=True), ' aria-current="page"' if key == current else '', html.escape(words)))
    # On a phone the row scrolls sideways: the one line of script after it
    # scrolls it so that the part the page is in shows, not only the first
    return ('<style>%s</style>\n<nav class="oxt-family" aria-label="OpenXTalk sites">'
            '<a class="oxt-family-home" href="%s">%s<span>OpenXTalk</span></a><ul>%s</ul></nav>\n%s\n'
            % (FAMILY_CSS, OPENXTALK, MARK, ''.join(items), SHOW_CURRENT))


# --- writing the page --------------------------------------------------------

def esc(s):
    return html.escape(s or '', quote=True)


def human_size(n):
    for unit in ('bytes', 'KB', 'MB', 'GB'):
        if n < 1024 or unit == 'GB':
            return ('%d %s' % (n, unit)) if unit == 'bytes' else ('%.1f %s' % (n, unit))
        n /= 1024.0


def platforms_of(ids):
    """[(long name, short label)] in the page's order; an id not in
    PLATFORM_NAMES is shown as it is, never dropped."""
    known = {pid: (name, short) for pid, name, short in PLATFORM_NAMES}
    ordered = [pid for pid, _, _ in PLATFORM_NAMES if pid in ids] + sorted(i for i in ids if i not in known)
    return [known.get(pid, (pid, pid)) for pid in ordered]


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


# --- what the tree says about each family -------------------------------------

def load_tool(name):
    path = os.path.join(HERE, name)
    if not os.path.isfile(path):
        return None
    spec = importlib.util.spec_from_file_location(name.replace('-', '_').replace('.py', ''), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tree_facts():
    '''({family: {title, url, docs, examples}}, {package stem: (member, path)})
    from the two tables the rest of the suite already reads: a member's own
    repository from tools/member-registry.py, and the source file each
    package is made from from tools/build-lce-packages.py PACKAGES. Nothing
    here is a second copy of either. A family neither table knows still gets
    its page section, just without those links.'''
    members, sources = {}, {}
    reg = load_tool('member-registry.py')
    for m in getattr(reg, 'MEMBERS', []) or []:
        if m.kind != 'extension':
            continue
        here = os.path.join(SUITE_ROOT, m.name)
        members[m.name] = {'title': m.title, 'url': m.url,
                           'docs': os.path.isdir(os.path.join(here, 'docs')),
                           'examples': os.path.isdir(os.path.join(here, 'examples'))}
    lce = load_tool('build-lce-packages.py')
    for row in getattr(lce, 'PACKAGES', []) or []:
        sources[row['file']] = (row['member'], row['main'])
    return members, sources


# --- writing the page --------------------------------------------------------

CSS = '''
/* A catalogue in the OpenXTalk family's look (2026-11-26): OXT-Beyond's
   night-sky masthead, its orange and amber, its teal kicker and its
   system sans, so this page reads as one of the family's sites with
   OXT-Beyond's own and the community stacks gallery. Light and dark follow
   the system; the masthead is the night sky in both, as Beyond's are.
   System fonts only: the page loads nothing. */
:root {
  --paper: #fbf7f1; --panel: #ffffff; --ink: #18212e; --muted: #556275; --rule: #e7dfd3;
  --accent: #b44d00; --accent-ink: #1a1206; --chip: #f3ece2; --mark: #ffe2b8;
  --night: #0a0f1a; --night-2: #111a2b; --star: #eef3ff; --ember: #ff7a00; --amber: #ffb347; --teal: #4fd1c5;
  --fire: linear-gradient(135deg, #ffc24d, #ff7700 55%, #ff3d00);
  --sans: system-ui, -apple-system, "Segoe UI", Roboto, Ubuntu, "Helvetica Neue", sans-serif;
  --serif: var(--sans);
  --mono: ui-monospace, "SF Mono", "Cascadia Mono", "DejaVu Sans Mono", Consolas, monospace;
  --shadow: 0 1px 2px rgba(24,33,46,.06), 0 12px 32px rgba(24,33,46,.08);
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --paper: #0d1420; --panel: #141d2c; --ink: #e8edf4; --muted: #9aa8ba; --rule: #223047;
          --accent: #ffb347; --chip: #1b2638; --mark: #4a3413;
          --shadow: 0 1px 2px rgba(0,0,0,.3), 0 16px 40px rgba(0,0,0,.35); }
}
* { box-sizing: border-box; }
html { scroll-padding-top: 16px; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 16px/1.6 var(--sans); -webkit-font-smoothing: antialiased; }
a { color: var(--accent); text-underline-offset: 2px; }
a:focus-visible, summary:focus-visible { outline: 3px solid var(--amber); outline-offset: 2px; border-radius: 4px; }
code { font: 0.88em var(--mono); overflow-wrap: anywhere; }
.wrap { max-width: 1120px; margin: 0 auto; padding: 0 20px; }

.mast { position: relative; overflow: hidden; padding: 44px 0 34px; color: var(--star);
        background: radial-gradient(ellipse 90% 140% at 85% -10%, rgba(255,122,0,.20), transparent 60%),
                    radial-gradient(ellipse 60% 90% at 0% 0%, rgba(79,209,197,.10), transparent 60%),
                    linear-gradient(180deg, var(--night-2), var(--night)); }
.mast a { color: var(--amber); }
.kicker { display: flex; align-items: center; gap: 10px; font: 600 0.78rem/1 var(--mono); letter-spacing: 0.14em;
          text-transform: uppercase; color: var(--teal); margin: 0 0 16px; }
.kicker::before { content: ""; width: 26px; height: 1px; background: currentColor; }
.mast h1 { font: 850 clamp(2rem, 5vw, 3.4rem)/1.04 var(--sans); margin: 0 0 16px; letter-spacing: -0.03em; max-width: 20ch; }
.lede { font-size: 1.1rem; max-width: 62ch; margin: 0 0 20px; color: rgba(222,230,244,.84); }
.meta { display: flex; flex-wrap: wrap; gap: 6px 18px; margin: 0; padding: 0; list-style: none; color: rgba(200,212,230,.72); font-size: 0.92rem; }
.meta b { color: var(--star); font-weight: 650; }
.pre { display: inline-block; font: 600 0.72rem var(--mono); letter-spacing: 0.08em; text-transform: uppercase;
       border: 1px solid currentColor; border-radius: 999px; padding: 1px 8px; color: #b45a00; }
@media (prefers-color-scheme: dark) { .pre { color: #ffc46b; } }
.mast .pre { color: #ffc46b; background: rgba(255,179,71,.1); }
.navlinks { display: flex; flex-wrap: wrap; gap: 6px 20px; margin: 16px 0 0; padding: 0; list-style: none; font-weight: 500; }
.mast .navlinks { gap: 10px; margin-top: 22px; }
.mast .navlinks a { display: inline-block; padding: 7px 14px; border-radius: 999px; text-decoration: none; color: var(--star);
                    background: rgba(255,255,255,.06); border: 1px solid rgba(255,255,255,.14); font-size: .92rem; }
.mast .navlinks a:hover { border-color: var(--amber); color: #fff; }

.layout { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 48px; padding-top: 32px; }
.toc { position: sticky; top: 16px; align-self: start; font-size: 0.93rem; }
.toc h2 { font: 600 0.75rem var(--sans); letter-spacing: 0.12em; text-transform: uppercase; color: var(--muted); margin: 0 0 8px; }
.toc ol { list-style: none; margin: 0; padding: 0; border-left: 1px solid var(--rule); }
.toc li a { display: flex; gap: 10px; padding: 3px 0 3px 12px; text-decoration: none; color: var(--ink); }
.toc li a:hover { color: var(--accent); }
.toc li a:hover .num { color: var(--ember); }
.num { font: 0.8rem var(--mono); color: var(--muted); min-width: 2ch; }
.fam-head .num { color: var(--ember); }
@media (max-width: 860px) {
  .layout { grid-template-columns: 1fr; gap: 8px; }
  .toc { position: static; }
  .toc ol { columns: 2; column-gap: 16px; }
}

.install { background: var(--panel); border: 1px solid var(--rule); border-radius: 16px; padding: 22px 24px; margin-bottom: 8px; box-shadow: var(--shadow); }
.install h2, .family h2 { font: 800 1.6rem/1.2 var(--sans); letter-spacing: -0.02em; margin: 0; }
.steps { counter-reset: step; list-style: none; margin: 16px 0; padding: 0;
         display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; }
.steps li { counter-increment: step; border-top: 2px solid var(--ember); padding-top: 8px; }
.steps li::before { content: counter(step); display: grid; place-items: center; width: 30px; height: 30px; margin: 6px 0 6px;
                   border-radius: 50%; border: 1.5px solid var(--ember); color: var(--accent); font: 700 0.95rem var(--mono); }
.install p { margin: 8px 0; font-size: 0.95rem; }

.family { padding-top: 36px; }
.fam-head { display: grid; grid-template-columns: auto 1fr; column-gap: 14px; align-items: baseline;
            border-bottom: 2px solid var(--rule); padding-bottom: 10px; }
.fam-head .num { font-size: 1rem; }
.fam-head p { grid-column: 2; margin: 6px 0 0; color: var(--muted); }
.fam-head .navlinks { grid-column: 2; margin-top: 6px; font-size: 0.92rem; }

.pkg { border-bottom: 1px solid var(--rule); padding: 20px 0; }
.pkg-top { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 8px 24px; align-items: start; }
.pkg h3 { font: 750 1.22rem/1.3 var(--sans); letter-spacing: -0.01em; margin: 0; }
.ver { font: 0.85rem var(--mono); color: var(--muted); margin-left: 6px; }
.kind { font: 600 0.7rem var(--sans); letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); margin-left: 8px; }
.get { text-align: right; }
.dl { display: inline-block; background: var(--fire); color: var(--accent-ink); text-decoration: none;
      font-weight: 700; padding: 9px 20px; border-radius: 999px; white-space: nowrap;
      box-shadow: 0 6px 18px rgba(255,122,0,.28); transition: transform .15s ease, box-shadow .15s ease; }
.dl:hover { transform: translateY(-1px); box-shadow: 0 10px 24px rgba(255,122,0,.36); }
@media (prefers-reduced-motion: reduce) { .dl { transition: none; } .dl:hover { transform: none; } }
.get small { display: block; color: var(--muted); font: 0.78rem var(--mono); margin-top: 4px; }
@media (max-width: 560px) { .pkg-top { grid-template-columns: 1fr; } .get { text-align: left; } }
.pkg p { margin: 10px 0; max-width: 70ch; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 10px 0 0; padding: 0; list-style: none; }
.chips li { background: var(--chip); border-radius: 999px; padding: 1px 10px; font: 0.8rem var(--mono); }
.facts { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 3px 16px; margin: 14px 0 0; font-size: 0.9rem; }
.facts dt { color: var(--muted); }
.facts dd { margin: 0; overflow-wrap: anywhere; }
.sha { font-size: 0.75rem; color: var(--muted); }
details { margin: 10px 0 0; }
summary { cursor: pointer; color: var(--accent); font-weight: 500; }
.handlers { list-style: none; margin: 10px 0 0; padding: 0; display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 0 24px; font-size: 0.88rem; }
.handlers li { padding: 6px 0; border-top: 1px solid var(--rule); }
.handlers li:target { background: var(--mark); }
.handlers .k { color: var(--muted); font-size: 0.75rem; margin-left: 4px; }
.handlers span.s { display: block; color: var(--muted); }

footer { border-top: 1px solid var(--rule); margin-top: 48px; padding: 24px 0 48px; color: var(--muted); font-size: 0.9rem; }
footer p { max-width: 75ch; }
'''


def anchor(p, name):
    return 'h-%s-%s' % (p['stem'], name)


def rich(par, p):
    '''One documentation paragraph as HTML: escaped, a <handlerName> link
    pointing at that handler in the package's handler list, and a paragraph
    whose lines are a list or are indented keeping its line breaks.'''
    names = {h['name'] for h in p['handlers']}

    def link(m):
        name = html.unescape(m.group(1))
        if name in names:
            return '<a href="#%s"><code>%s</code></a>' % (esc(anchor(p, name)), esc(name))
        return '<code>%s</code>' % esc(name)

    keep_lines = any(re.match(r'^(\s+|[-*] |[0-9]+[.)] )', l) for l in par[1:]) or \
        bool(re.match(r'^([-*] |[0-9]+[.)] )', par[0]))
    text = '<br>\n'.join(esc(l.strip()) for l in par) if keep_lines else esc(flat(par))
    return re.sub(r'&lt;([A-Za-z][A-Za-z0-9_.]*)&gt;', link, text)


def render(release, packages, sums_url, repo=REPO, members=None, sources=None):
    if members is None or sources is None:
        tm, ts = tree_facts()
        members = tm if members is None else members
        sources = ts if sources is None else sources
    tag = release.get('tag_name', '')
    suite = 'https://github.com/%s' % repo
    rel_url = release.get('html_url') or '%s/releases/tag/%s' % (suite, tag)
    published = (release.get('published_at') or '')[:10]
    by_id = {p['id']: p for p in packages}
    ordered = order(packages)
    families = []
    for p in ordered:
        if p['family'] not in families:
            families.append(p['family'])

    def fam_title(f):
        return members.get(f, {}).get('title') or f

    out = []
    w = out.append
    home = site_url(repo)
    desc = 'Extension packages (.lce) for HyperXTalk, LiveCode Community and OpenXTalk.'
    w('<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      '<title>xTalk Suite extensions</title>\n'
      '<meta name="description" content="%s">\n' % esc(desc))
    # For search engines and link previews (2026-11-16): the page's one
    # address, so .../index.html and ...?x count as it, and what a shared
    # link shows. The address is the repository's GitHub Pages site.
    w('<link rel="canonical" href="%s">\n'
      '<meta property="og:type" content="website">\n'
      '<meta property="og:title" content="xTalk Suite extensions">\n'
      '<meta property="og:description" content="%s">\n'
      '<meta property="og:url" content="%s">\n'
      '<meta name="twitter:card" content="summary">\n' % (esc(home), esc(desc), esc(home)))
    w('<style>%s</style>\n</head>\n<body>\n' % CSS)
    # this page is the family's Extensions for the IDEs built on LiveCode
    # Community 9: the bar marks it, and links it here
    w(family_bar('extensions', {'extensions': home}))

    w('<header class="mast">\n<div class="wrap">\n<p class="kicker">xTalk Suite &middot; extension catalogue</p>\n'
      '<h1>Extensions for HyperXTalk and LiveCode Community</h1>\n'
      '<p class="lede">Free, open-source extensions for any IDE built on LiveCode Community 9. Most are '
      'thin layers over proven open-source libraries; the rest are plain script. Each package carries '
      'its own documentation, which appears in the Dictionary once it is installed.</p>\n')
    w('<ul class="meta">\n<li>Release <b><a href="%s">%s</a></b></li>\n' % (esc(rel_url), esc(tag)))
    if published:
        w('<li>Published <b>%s</b></li>\n' % esc(published))
    w('<li><b>%d</b> packages in <b>%d</b> families</li>\n' % (len(packages), len(families)))
    if release.get('prerelease'):
        w('<li><span class="pre">Pre-release</span></li>\n')
    w('</ul>\n')
    w('<ul class="navlinks">\n<li><a href="%s">Source code</a></li>\n<li><a href="%s">Release notes</a></li>\n'
      '<li><a href="%s/releases">All releases</a></li>\n<li><a href="%s/issues">Report a problem</a></li>\n'
      '<li><a href="%s">SHA256SUMS</a></li>\n</ul>\n</div>\n</header>\n'
      % (esc(suite), esc(rel_url), esc(suite), esc(suite), esc(sums_url)))

    w('<div class="wrap layout">\n<nav class="toc" aria-label="Contents">\n<h2>Contents</h2>\n<ol>\n'
      '<li><a href="#install"><span class="num">00</span>Installing</a></li>\n')
    for i, f in enumerate(families, 1):
        w('<li><a href="#%s"><span class="num">%02d</span>%s</a></li>\n' % (esc(f), i, esc(fam_title(f))))
    w('</ol>\n</nav>\n<main>\n')

    w('<section class="install" id="install">\n<h2>Installing an extension</h2>\n<ol class="steps">\n'
      '<li>Download its <code>.lce</code> file below. Leave it zipped.</li>\n'
      '<li>In HyperXTalk or LiveCode Community 9, choose <b>Tools &gt; Extension Manager</b>.</li>\n'
      '<li>Click <b>+</b> and choose the <code>.lce</code> file.</li>\n'
      '</ol>\n'
      '<p>Some extensions need another installed first: each entry says which under "Install first", '
      'and installing a family from the top down gets the order right. "Works with" names other '
      'extensions its documentation pairs it with, which some of its features may need.</p>\n'
      '<p>An installed extension loads every time the IDE starts. To put one in a standalone, tick it in '
      '<b>Standalone Application Settings &gt; Inclusions</b> (choose "Select inclusions for the standalone '
      'application"). A <i>script</i> library, or one with no native code, runs anywhere the IDE runs; a '
      '<i>native</i> library carries compiled code for the platforms listed with it. The macOS libraries are not signed or notarized, so '
      'macOS may ask before it lets them load. To check a download, compare its SHA-256 with '
      '<a href="%s">SHA256SUMS</a>.</p>\n' % esc(sums_url))
    if release.get('prerelease'):
        w('<p><span class="pre">Pre-release</span> These extensions are new, and most of the testing so far has '
          'been in OXT-Beyond. Please <a href="%s/issues">report</a> anything that goes wrong.</p>\n' % esc(suite))
    w('</section>\n')

    for i, f in enumerate(families, 1):
        info = members.get(f, {})
        n = len([p for p in packages if p['family'] == f])
        w('<section class="family" id="%s">\n<header class="fam-head">\n<span class="num">%02d</span>'
          '<h2>%s</h2>\n<p>%s</p>\n' % (esc(f), i, esc(fam_title(f)),
                                     'One package' if n == 1 else '%d packages, in install order' % n))
        links = []
        if info.get('url'):
            links.append('<a href="%s">Repository and README</a>' % esc(info['url']))
        if info.get('docs'):
            links.append('<a href="%s/tree/%s/%s/docs">Documentation</a>' % (esc(suite), esc(tag), esc(f)))
        if info.get('examples'):
            links.append('<a href="%s/tree/%s/%s/examples">Examples</a>' % (esc(suite), esc(tag), esc(f)))
        links.append('<a href="%s/tree/%s/%s">Source at %s</a>' % (esc(suite), esc(tag), esc(f), esc(tag)))
        w('<ul class="navlinks">\n%s\n</ul>\n</header>\n' % '\n'.join('<li>%s</li>' % l for l in links))
        for p in [q for q in ordered if q['family'] == f]:
            render_card(w, p, packages, by_id, suite, tag, sources)
        w('</section>\n')
    w('</main>\n</div>\n')

    w('<footer>\n<div class="wrap">\n<p>OXT-Beyond includes all of these already, so its users need nothing '
      'from this page.</p>\n'
      '<p>Built from <a href="%s">release %s</a> of <a href="%s">xtalk-suite</a> by '
      '<code>tools/build-extensions-site.py</code>, from the packages themselves: their manifests, their '
      'documentation and the checksums of the release. The extensions are MIT-licensed, the libraries they '
      'bundle keep their own licences, and each package carries the text of every one.</p>\n</div>\n</footer>\n'
      % (esc(rel_url), esc(tag), esc(suite)))
    w('</body>\n</html>\n')
    return ''.join(out)


def render_card(w, p, packages, by_id, suite, tag, sources):
    kind = 'native library' if p['platforms'] else ('LCB library' if p.get('lcb') else 'script library')
    needs = []
    for r in p['requires']:
        dep = by_id.get(r)
        needs.append('<a href="#pkg-%s">%s</a>' % (esc(dep['file']), esc(dep['title'])) if dep
                     else '<code>%s</code>' % esc(r))
    w('<article class="pkg" id="pkg-%s">\n<div class="pkg-top">\n<div>\n'
      '<h3>%s<span class="ver">%s</span><span class="kind">%s</span></h3>\n'
      % (esc(p['file']), esc(p['title']), esc(p['version']), kind))
    about = p['about']
    if about:
        w('<p>%s</p>\n' % rich(about[0], p))
    elif p['description']:
        w('<p>%s</p>\n' % esc(p['description']))
    if p['platforms']:
        w('<ul class="chips" aria-label="Platforms">%s</ul>\n' % ''.join(
            '<li title="%s">%s</li>' % (esc(name), esc(short)) for name, short in platforms_of(p['platforms'])))
    else:
        w('<ul class="chips" aria-label="Platforms"><li title="%s">Any platform</li></ul>\n'
          % esc(LCB_PLATFORMS if p.get('lcb') else SCRIPT_PLATFORMS))
    w('</div>\n<div class="get"><a class="dl" href="%s" download>Download</a><small>%s &middot; %s</small></div>\n'
      '</div>\n' % (esc(p['url']), esc(p['file']), esc(human_size(p['size']))))
    if len(about) > 1:
        w('<details><summary>More about %s</summary>\n%s\n</details>\n'
          % (esc(p['title']), '\n'.join('<p>%s</p>' % rich(par, p) for par in about[1:])))
    w('<dl class="facts">\n')
    w('<dt>Install first</dt><dd>%s</dd>\n' % (', '.join(needs) if needs else 'nothing'))
    also = works_with(p, packages)
    if also:
        w('<dt>Works with</dt><dd>%s</dd>\n' % ', '.join(
            '<a href="#pkg-%s">%s</a>' % (esc(b['file']), esc(b['title'])) for b in also))
    if p['tags']:
        w('<dt>Topics</dt><dd>%s</dd>\n' % esc(', '.join(p['tags'])))
    if p['author']:
        w('<dt>Author</dt><dd>%s</dd>\n' % esc(p['author']))
    w('<dt>Extension id</dt><dd><code>%s</code></dd>\n' % esc(p['id']))
    src = sources.get(p['stem'])
    if src:
        w('<dt>Source</dt><dd><a href="%s/blob/%s/%s/%s"><code>%s/%s</code></a></dd>\n'
          % (esc(suite), esc(tag), esc(src[0]), esc(src[1]), esc(src[0]), esc(src[1])))
    if p['licences']:
        w('<dt>Licences</dt><dd>%s</dd>\n' % esc(', '.join(p['licences'])))
    w('<dt>SHA-256</dt><dd class="sha"><code>%s</code></dd>\n</dl>\n' % esc(p['sha256']))
    if p['handlers']:
        n = len(p['handlers'])
        w('<details><summary>%s</summary>\n<ul class="handlers">\n'
          % ('The one handler' if n == 1 else 'All %d handlers' % n))
        for h in p['handlers']:
            w('<li id="%s"><code>%s</code><span class="k">%s</span>%s</li>\n'
              % (esc(anchor(p, h['name'])), esc(h['syntax'] or h['name']), esc(h['type']),
                 ('<span class="s">%s</span>' % rich([h['summary']], p)) if h['summary'] else ''))
        w('</ul>\n</details>\n')
    w('</article>\n')


def site_url(repo):
    """The repository's GitHub Pages address: OWNER/NAME -> https://owner.github.io/NAME/."""
    owner, _, name = repo.partition('/')
    return 'https://%s.github.io/%s/' % (owner.lower(), name)


def write_site(out_dir, page, repo=REPO):
    os.makedirs(out_dir, exist_ok=True)
    # a temporary file then a rename: a failed run never leaves half a page
    fd, tmp = tempfile.mkstemp(dir=out_dir, suffix='.tmp')
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    os.replace(tmp, os.path.join(out_dir, 'index.html'))
    # GitHub Pages: serve the folder as it is, without Jekyll
    open(os.path.join(out_dir, '.nojekyll'), 'w').close()
    # The one page, for search engines (given to them through Search
    # Console: a robots.txt here would not be read, only the host's own)
    with open(os.path.join(out_dir, 'sitemap.xml'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
                '  <url><loc>%s</loc></url>\n</urlset>\n' % esc(site_url(repo)))


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
        write_site(args.out, render(release, packages, sums_url, args.repo), args.repo)
    except Problem as e:
        print('build-extensions-site: ' + str(e), file=sys.stderr)
        return 1
    print('build-extensions-site: %s/index.html from %s (%d packages%s)'
          % (args.out, release['tag_name'], len(packages), ', pre-release' if release.get('prerelease') else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
