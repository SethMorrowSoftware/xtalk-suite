#!/usr/bin/env python3
"""archive-kat.py - known-answer vectors for ArchiveXT's pure layer.

ArchiveXT owns no cryptography and speaks to no protocol with a published
vector set; what it owns is a set of RULES three shipped apps wrote for
archive.org's public JSON - a Lucene sanitizer, URL bytes, chapter and
episode grouping, format ranking, natural order, duration parsing - and
every one of those has a known answer worth pinning. This tool derives the
constants the member harness pins (examples/archivext-tests.livecodescript)
through tools/archive_reference.py, the independent oracle, which anchors
itself at import to the three apps' OWN test vectors (a broken oracle
refuses to load).

The inputs are the SYNTHETIC fixtures under tests/fixtures/: archive.org is
not reachable from the build sandbox (the egress proxy refuses the CONNECT),
so they are shaped from the apps' mocked responses (the AudioBooks e2e
fixtures, the film club's browser fixture) and the documented API, not
recorded from the site. What the pinned answers therefore prove is that the
script derives what the oracle derives from the same bytes - the live shape
of a real response is the runbook's to confirm.

What --check sweeps:
  1. the oracle's own anchors (they ran at import; a failure never gets here)
  2. every fixture parses and derives the answers printed below, twice - a
     second derivation must match the first (the tables are deterministic)
  3. the preset tables' row counts and every preset id being unique

Pure standard library. Usage:
  python3 tools/archive-kat.py            # print the harness constants
  python3 tools/archive-kat.py --check    # sweep everything, exit non-zero on failure
"""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
FIXTURES = os.path.join(MEMBER, "tests", "fixtures")

_spec = importlib.util.spec_from_file_location(
    "archive_reference", os.path.join(HERE, "archive_reference.py"))
REF = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(REF)

# fixture file -> constant stem; every fixture the harness parses is pinned
# as the hex of its exact bytes, because an xTalk literal cannot hold the
# quotes JSON is made of.
FIXTURE_CONSTS = [
    ("librivox-search.json", "LibrivoxSearch"),
    ("librivox-item.json", "LibrivoxItem"),
    ("etree-search.json", "EtreeSearch"),
    ("etree-item.json", "EtreeItem"),
    ("movies-search.json", "MoviesSearch"),
    ("movies-item.json", "MoviesItem"),
    ("texts-item.json", "TextsItem"),
    ("search-error.json", "SearchError"),
    ("missing-item.json", "MissingItem"),
]


def fixture(name):
    with open(os.path.join(FIXTURES, name), "rb") as f:
        return f.read()


def _join(values, sep="|"):
    return sep.join(REF.num_text(v) if v is not None else "" for v in values)


def harness_vectors():
    """Every constant the member harness pins, derived in one place."""
    out = []
    for fname, stem in FIXTURE_CONSTS:
        out.append(("kAxVecFix%sHex" % stem, fixture(fname).hex()))
    # the exact search-URL bytes (the AudioBooks test) and a scrape URL
    out.append(("kAxVecUrlSearch", REF.search_url(
        'collection:(librivoxaudio) AND (a "b")',
        "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2)))
    out.append(("kAxVecUrlScrape", REF.scrape_url("collection:(GratefulDead)", "identifier,title", 100, "W3siaWRlbnRpZmllciI6ImdkNzcifV0=")))
    out.append(("kAxVecUrlDownload", REF.download_url("abc", "a b#1.mp3")))
    out.append(("kAxVecUrlDownloadDir", REF.download_url("abc", "dir/one two.mp3")))
    # the search fixtures
    ls = REF.search_parse(fixture("librivox-search.json").decode("utf-8"))
    out.append(("kAxVecLibrivoxDocIds", _join(d["identifier"] for d in ls["docs"])))
    out.append(("kAxVecLibrivoxDocOneCreator", ls["docs"][0]["creator"].replace("\n", "|")))
    out.append(("kAxVecLibrivoxNumFound", str(ls["numFound"])))
    es = REF.search_parse(fixture("etree-search.json").decode("utf-8"))
    table = "\n".join("\t".join(REF.first_value(d.get(f, "").split("\n")) if d.get(f) else ""
                                for f in ("identifier", "creator", "date", "source", "downloads"))
                      for d in es["docs"])
    out.append(("kAxVecEtreeDocsTableHex", table.encode("utf-8").hex()))
    ms = REF.search_parse(fixture("movies-search.json").decode("utf-8"))
    out.append(("kAxVecMoviesDocTypes", _join(d.get("mediatype", "") for d in ms["docs"])))
    # the item fixtures and their playlists
    li = REF.item_parse(fixture("librivox-item.json").decode("utf-8"))
    out.append(("kAxVecLibrivoxCreator", li["metadata"]["creator"].replace("\n", "|")))
    out.append(("kAxVecLibrivoxFilesCount", str(li["filesCount"])))
    pl = REF.playlist(li, "audio-chapters")
    out.append(("kAxVecLibrivoxChapterNames", _join(e["name"] for e in pl["entries"])))
    out.append(("kAxVecLibrivoxChapterTitlesHex", "|".join(e["title"] for e in pl["entries"]).encode("utf-8").hex()))
    out.append(("kAxVecLibrivoxChapterTracks", _join(e["track"] for e in pl["entries"])))
    out.append(("kAxVecLibrivoxChapterLengths", _join(e["length"] for e in pl["entries"])))
    ei = REF.item_parse(fixture("etree-item.json").decode("utf-8"))
    out.append(("kAxVecEtreeSetlist", ei["metadata"]["setlist"].replace("\n", "|")))
    out.append(("kAxVecEtreeYear", REF.year_of(ei["metadata"]["date"])))
    pl = REF.playlist(ei, "audio-tracks")
    out.append(("kAxVecEtreeTrackNames", _join(e["name"] for e in pl["entries"])))
    out.append(("kAxVecEtreeTrackTitles", _join(e["title"] for e in pl["entries"])))
    out.append(("kAxVecEtreeTrackLengths", _join(e["length"] for e in pl["entries"])))
    out.append(("kAxVecEtreeTrackFormats", _join(e["format"] for e in pl["entries"])))
    out.append(("kAxVecEtreeTrackOneUrl", pl["entries"][0]["url"]))
    mi = REF.item_parse(fixture("movies-item.json").decode("utf-8"))
    pl = REF.playlist(mi, "video")
    out.append(("kAxVecMoviesEpisodeNames", _join(e["name"] for e in pl["entries"])))
    out.append(("kAxVecMoviesEpisodeTitles", _join(e["title"] for e in pl["entries"])))
    out.append(("kAxVecMoviesEpisodeQuality", _join(e["quality"] for e in pl["entries"])))
    out.append(("kAxVecMoviesVariantsOne", ";".join("|".join(v) for v in pl["entries"][0]["variants"])))
    out.append(("kAxVecMoviesAutoKind", REF.playlist(mi, "auto")["kind"]))
    ti = REF.item_parse(fixture("texts-item.json").decode("utf-8"))
    pl = REF.playlist(ti, "auto")
    out.append(("kAxVecTextsAutoKind", pl["kind"]))
    out.append(("kAxVecTextsDocNames", _join(e["name"] for e in pl["entries"])))
    out.append(("kAxVecTextsImageNames", _join(e["name"] for e in REF.playlist(ti, "images")["entries"])))
    out.append(("kAxVecTextsFilesCount", str(REF.playlist(ti, "files")["count"])))
    # the tables
    out.append(("kAxVecPresetCounts", ",".join("%s:%d" % (f, len(REF.presets(f))) for f in ("etree", "librivox", "movies", "any"))))
    out.append(("kAxVecVideoScope", REF.video_scope()))
    out.append(("kAxVecPresetRomance", REF.preset_spec_query("librivox", "Romance", "emma", "", "", ("solo", "english", "bogus"))))
    out.append(("kAxVecPresetDeadYears", REF.preset_spec_query("etree", "GratefulDead", "", "", "", ())))
    out.append(("kAxVecPresetBobWeirHex", REF.preset_query("etree", "BobWeir").encode("utf-8").hex()))
    out.append(("kAxVecPresetPrelingerHex", REF.preset_spec_query("movies", "prelinger", "moon: rocket (test)", "", "", ("publicdomain",)).encode("utf-8").hex()))
    out.append(("kAxVecPresetAuthor", REF.preset_spec_query("librivox", "Author_Search", "Jane Austen", "", "", ())))
    out.append(("kAxVecPresetCollectionHex", REF.preset_spec_query("etree", "Collection_Search", "Phish", "1997", "1999", ("soundboard",)).encode("utf-8").hex()))
    # AN xTALK LITERAL CANNOT HOLD A DOUBLE QUOTE (there are no string
    # escapes in the dialect), so any value that carries one, a line break
    # or a non-ASCII byte is pinned as the hex of its UTF-8 bytes under a
    # ...Hex name, and the harness decodes it. Asserted here rather than
    # trusted: a value that needs hexing and is not named ...Hex would
    # produce a constant line that does not compile.
    for name, value in out:
        needs_hex = ('"' in value) or ("\n" in value) or any(ord(c) > 126 or ord(c) < 32 for c in value)
        if needs_hex and not name.endswith("Hex"):
            raise SystemExit("archive-kat: %s carries a quote, a line break or a non-ASCII byte and must be pinned as hex" % name)
    return out


def check():
    problems = []
    first = harness_vectors()
    second = harness_vectors()
    if first != second:
        problems.append("harness_vectors() is not deterministic")
    names = [n for n, _ in first]
    if len(names) != len(set(names)):
        problems.append("duplicate constant names")
    for fname, _ in FIXTURE_CONSTS:
        try:
            json.loads(fixture(fname).decode("utf-8"))
        except ValueError as exc:
            problems.append("%s is not JSON: %s" % (fname, exc))
    for family in ("etree", "librivox", "movies", "any"):
        rows = REF.presets(family)
        ids = [r[0] for r in rows]
        if len(ids) != len(set(ids)):
            problems.append("%s: duplicate preset ids" % family)
        for r in rows:
            if len(r) != 7:
                problems.append("%s: row %s has %d columns" % (family, r[0], len(r)))
            if not r[4] and family != "any" and not r[3]:
                problems.append("%s: fixed preset %s has no query" % (family, r[0]))
    counts = {"etree": 49, "librivox": 40, "movies": 26, "any": 10}
    for family, want in counts.items():
        if len(REF.presets(family)) != want:
            problems.append("%s: %d presets, expected %d (the source app's table)" % (family, len(REF.presets(family)), want))
    if REF.search_parse(fixture("search-error.json").decode("utf-8")) is not None:
        problems.append("the search-error fixture parsed as a result")
    if REF.item_parse(fixture("missing-item.json").decode("utf-8")) is not None:
        problems.append("the missing-item fixture parsed as an item")
    return problems


def main(argv):
    if "--check" in argv:
        problems = check()
        for p in problems:
            print("archive-kat: " + p)
        if problems:
            print("archive-kat: %d problem(s)" % len(problems))
            return 1
        print("archive-kat: OK (the oracle's anchors held at import; %d harness constants derive "
              "deterministically from %d fixtures; every preset table has unique ids and the "
              "source app's row count)" % (len(harness_vectors()), len(FIXTURE_CONSTS)))
        return 0
    for name, value in harness_vectors():
        print('constant %s = "%s"' % (name, value))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
