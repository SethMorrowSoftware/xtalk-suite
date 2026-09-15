#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/archivext.livecodescript
against the oracle, headlessly, through tools/lcs-interp.py.

WHY THIS EXISTS. OXT cannot compile or run a .livecodescript headlessly, so
without this gate ArchiveXT's pure layer would ship having never executed
once: tools/archive-kat.py proves the EXPECTED answers are right (the
oracle anchors to the three source apps' own tests) and
tools/check-selftest-vectors.py proves the harness pins those answers, but
nothing would prove the SCRIPT derives them. The family's interpreter
(byte-identical with coinxt's and nostrxt's copies, drift-gated) drives
the real shipped file, function by function, and compares every answer
with tools/archive_reference.py's - the CoinXT model, where the gate found
a would-be-red engine line the day it was wired up.

WHAT IT IS NOT. An approximation of the engine, not the engine: the
interpreter's own header carries the modelled-subset contract and its
named divergences, and nothing here promotes a handler out of "verified
statically". If this file and the engine disagree, the engine is right.

WHAT IT DRIVES, in tiers:
  0. the interpreter behaviours this member leans on (the 3-argument
     byteOffset added for it; `sort lines of`; the trailing-delimiter eat)
  1. every scalar rule against the oracle over the anchored vectors AND a
     wider sweep: encoders, identifiers, years, durations, sizes, natural
     order, the sanitizer in both modes, the clause builders, every URL
  2. the TABLES: every preset row of every family, every filter, every
     sort, compared whole against the oracle's second transcription
  3. the fixtures: both response parsers over every fixture, then the
     playlist engine for every kind the fixture supports - names, titles,
     tracks, lengths, urls, quality and variants, entry by entry
  4. the refusals: the site's error shape, the missing item, malformed
     JSON, bad identifiers, empty queries - each must answer empty and
     record a reason

The fetch layer is deliberately NOT driven (it is `load URL`, which no
headless model can stand in for); the harness exercises its refusal paths
and the runbook owns its live legs.

MUTATION-TESTED the way the family law demands (root CLAUDE.md: exercise a
gate the way the build runs it): tools/test-script-vectors.py seeds real
defects into the SHIPPED file in place and requires this gate to fail each
time.

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse (the gate set)
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LCS = _load("lcs_interp", os.path.join(HERE, "lcs-interp.py"))
REF = _load("archive_reference", os.path.join(HERE, "archive_reference.py"))
SCRIPT = os.path.join(MEMBER, "src", "archivext.livecodescript")
FIXTURES = os.path.join(MEMBER, "tests", "fixtures")


class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.n = 0
        self.failed = 0

    def note(self, text):
        if not self.terse:
            print(f"-- {text}")

    def ck(self, label, got, want):
        self.n += 1
        if got == want:
            if not self.terse:
                print(f"  ok   {label}")
        else:
            self.failed += 1
            print(f"  FAIL {label}\n       got  {got!r}\n       want {want!r}")


def as_str(v):
    """An interpreter answer as text the way the engine would show it."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def fixture(name):
    return open(os.path.join(FIXTURES, name), encoding="utf-8").read()


# --------------------------------------------------------------------- tier 0
def check_interp_model(c, ip):
    c.note("tier 0: the interpreter model this member leans on")

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)
    c.ck("byteOffset with a skip answers relative to the skip", ev('byteOffset("c", "abcabc", 3)'), 3)
    c.ck("byteOffset without a hit answers 0", ev('byteOffset("z", "abcabc", 0)'), 0)
    c.ck("offset two-argument form", ev('offset("ca", "abcabc")'), 3)
    c.ck("the trailing-delimiter eat: items of 'a,b,'", ev('the number of items of "a,b,"'), 2)
    c.ck("chunk to -1", ev('char 3 to -1 of "abcdef"'), "cdef")


# --------------------------------------------------------------------- tier 1
def check_scalars(c, ip):
    c.note("tier 1: scalar rules against the oracle")
    call = ip.call
    for text in ["a b#1.mp3", "-_.!~*'()", "/", "café ñ", "100%", "a+b"]:
        c.ck(f"axUrlEncode {text!r}", call("axUrlEncode", [text]), REF.url_encode(text))
    for text in ["dir/one two.mp3", "a/b/c#d", "plain"]:
        c.ck(f"axUrlEncodePath {text!r}", call("axUrlEncodePath", [text]), REF.url_encode_path(text))
    for text in ['collection:(librivoxaudio) AND (a "b")', "*-._ x", "café", "[1 TO 2]"]:
        c.ck(f"axQueryEncode {text!r}", call("axQueryEncode", [text]), REF.query_encode(text))
    for ident in ["pride_and_prejudice_librivox", "a.b-c_1", "", "../etc", "x y", "<script>", "-lead", "a" * 100, "a" * 101]:
        c.ck(f"axIdentifierIsValid {ident[:20]!r}", call("axIdentifierIsValid", [ident]), REF.identifier_valid(ident))
    for text in ["1977-05-08T00:00:00Z", "05/08/1977", "77-05-08", "12345", "", "c. 1900 (reprint 1950)"]:
        c.ck(f"axYearOf {text!r}", as_str(call("axYearOf", [text])), REF.year_of(text))
    for text in ["1900", " 2024 ", "", "19", "abcd", "0999", "9999"]:
        c.ck(f"axNormalizeYear {text!r}", as_str(call("axNormalizeYear", [text])), REF.normalize_year(text))
    for text in ["600.12", "12:34", "1:02:03", "1:02:03.5", "", "n/a", "abc", "0:00", "  45  ", "1:xx", "1e3"]:
        want = REF.duration_seconds(text)
        c.ck(f"axDurationSeconds {text!r}", as_str(call("axDurationSeconds", [text])),
             "" if want is None else REF.num_text(want))
    for sec in [0, 65, 3599.9, 3600, 45296, -5, 225, 5025, "abc", ""]:
        c.ck(f"axFormatTime {sec!r}", call("axFormatTime", [sec]), REF.format_time(sec if sec != "" else None))
    for b in [80000000, 20000000, 1024, 1536, 0, -3, 1, 1023, 1048576, 5000000000, "x", ""]:
        c.ck(f"axFormatBytes {b!r}", call("axFormatBytes", [b]), REF.format_bytes(b if b != "" else None))
    for text in ["Part10", "b_part2.ogg", "ABC", "x1y22z333"]:
        c.ck(f"axNaturalKey {text!r}", call("axNaturalKey", [text]), REF.natural_key(text))
    lines = ["b_part2.ogg", "b_part10.ogg", "b_part1.ogg", "A_part1.ogg", "b_Part1.ogg"]
    c.ck("axNaturalSort", call("axNaturalSort", ["\n".join(lines)]).split("\n"), REF.natural_sort(lines))
    for t in ["01", "4/5", 7, "n/a", "", "track 12 of 20"]:
        want = REF.track_number(t if t != "" else None)
        c.ck(f"axTrackNumber {t!r}", as_str(call("axTrackNumber", [t])), "" if want is None else str(want))
    for subj, mx in [("librivox; audiobooks; literature; ghost stories", 2), ("fiction\nFiction\npoetry", 2),
                     ("Fiction\nRomance\nAudiobook\nA very long subject name that exceeds twenty characters", 2),
                     ("", 2), ("x" * 20, 2), ("a|b", 3), ("Audio Books; audio; History", 5)]:
        c.ck(f"axSubjectTags {subj[:30]!r}", call("axSubjectTags", [subj, mx]).split("\n") if call("axSubjectTags", [subj, mx]) else [],
             REF.subject_tags(subj.split("\n") if subj else None, mx))


SANITIZE_VECTORS = [
    ("Title - Subtitle", False), ("austen -", False), ("+", False), ("!", False), ("a &&", False), ("a || b", False),
    ("-austen", False), ("austen AND AND dickens", False), ("(austen AND)", False), ("()", False), ("austen AND OR", False),
    ("NOT austen", False), ("austen AND NOT dickens", False), ("AND OR NOT", False), ("year:[1800 TO 1850]", True),
    ("year:[1800 TO", True), ("title:emma~2 dickens^3", True), ("austen ((", False), ('"Pride and Prejudice', False),
    ('"Pride and Prejudice"', False), ("(austen OR dickens)", False), ("austen AND", False), ("AND", False),
    ("Pride and", False), ("a[b]{c}\\d^e~f/g", False), ("   ", False), ("Dracula: Chapter 1", False),
    ("Dracula: Chapter 1", True), ("creator:austen AND title:emma", True), ("(a OR (b AND c))", False),
    ("NOT (a OR b)", False), ("a -b +c !d", False), ("moon rocket", False), ("café crème", False),
    ("x {1 TO 2}", True), ("x {1 TO", True), ("OR austen", False), ("austen NOT", False),
]


def check_sanitizer(c, ip):
    c.note("tier 1: the sanitizer, both modes, and the query builders")
    for text, mode in SANITIZE_VECTORS:
        c.ck(f"axQuerySanitize {text!r} field={mode}", ip.call("axQuerySanitize", [text, mode]), REF.sanitize(text, mode))
    c.ck("axQueryClause", ip.call("axQueryClause", ["collection", " Phish "]), "collection:(Phish)")
    c.ck("axQueryPhrase", ip.call("axQueryPhrase", ["creator", 'Jane "Austen"']), 'creator:("Jane Austen")')
    for f, t in [("1965", "1995"), ("1995", "1965"), ("", "1950"), ("1900", ""), ("", ""), ("19", "abcd")]:
        c.ck(f"axQueryYears {f!r} {t!r}", ip.call("axQueryYears", [f, t]), REF.query_years(f, t))
    c.ck("axPublicDomainClause", ip.call("axPublicDomainClause", []), REF.PUBLIC_DOMAIN)
    specs = [
        dict(base=REF.LIBRIVOX_SCOPE, text="Dracula: Chapter 1", textField="title"),
        dict(base=REF.LIBRIVOX_SCOPE, text="creator:austen AND title:emma", fieldSyntax=True),
        dict(base=REF.LIBRIVOX_SCOPE, yearFrom="1950", yearTo="1900"),
        dict(base=REF.LIBRIVOX_SCOPE + " AND subject:(romance)", text="emma", filters="subject:(solo)\nlanguage:(English)"),
        dict(base="collection:(prelinger)", text="moon: rocket (test)", plainText=True),
        dict(base="", text="only text"),
        dict(base="", text="   "),
    ]
    for spec in specs:
        want = REF.build_query(base=spec.get("base", ""), text=spec.get("text", ""), text_field=spec.get("textField", ""),
                               field_syntax=spec.get("fieldSyntax", False), year_from=spec.get("yearFrom", ""),
                               year_to=spec.get("yearTo", ""), filters=spec.get("filters", "").split("\n") if spec.get("filters") else (),
                               plain_text=spec.get("plainText", False))
        got = ip.call("axQueryBuild", [dict(spec)])
        c.ck(f"axQueryBuild {spec}", as_str(got), want)


NAME_VECTORS = [
    # the AudioBooks chapter stems, both spellings of the derivative suffix
    "pride_01_austen_64kb.mp3", "pride_01_austen_vbr.mp3", "pride_01_austen.mp3", "Pride_01_Austen_orig.flac",
    "pride_01_austen_original.wav", "pride_01_austen_128kb.ogg", "a_vbr_b.mp3", "x_1000kb.mp3", "noext",
    # the tape finder's track spellings
    "gd77-05-08d1t01.flac", "gd77-05-08d1t01_vbr.mp3", "gd77-05-08d1t01_64kb.mp3", "gd77-05-08d1t01.shn",
    # the film club's variants
    "Night_of_the_Living_Dead_512kb.mp4", "Night_of_the_Living_Dead.ogv", "Night_of_the_Living_Dead_archive.mp4",
    "Night_of_the_Living_Dead.mp4.ia", "Plan9_h264.mp4", "Plan9_1080p.mkv", "Plan9-720p.webm", "Plan9.h.264.mp4",
    "Plan9_hd.mp4", "Plan9_sd_512kb.mp4", "Plan9.1280x720.mp4", "Plan9_854x480.mp4", "Plan9_640x360.mp4",
    "Plan9.mp4", "dir/sub/Plan9_512kb.mp4", "__init__.py", "", "A  B__C.mp3", "  ",
]

TITLE_VECTORS = [
    "d1t01 - Bertha", "d1t01Bertha", "t05_Scarlet_Begonias", "D2T11 Playing In The Band", "t1", "d1t01",
    "Bertha", "  d1t01  -  Jack-Straw  ", "d10t99 x", "tea for two", "",
]

CLEAN_TITLE_VECTORS = [
    ("night_of_the_living_dead_512kb.mp4", "Night of the Living Dead"),
    ("Night_of_the_Living_Dead.mp4", "Night of the Living Dead"),
    ("plan9_h264.mp4", "Plan 9"), ("Plan9_1080p.mkv", "Plan9"), ("plan9.mp4", "Plan 9"),
    ("   .mp4", "x"), ("", "Anything"), ("episode-02.mp4", ""), ("a.b.c.mp4", "a.b"),
    ("nightofthelivingdead.mp4", "Night of the Living Dead"), ("nightofthelivingdead_1968.mp4", "Night of the Living Dead"),
    ("dir/sub/x.mp4", "x"),
]


def check_name_rules(c, ip):
    c.note("tier 1: the file-name rules (stems, pretty names, labels)")
    call = ip.call
    # These are the rules the fixtures reach only INDIRECTLY (a fixture groups
    # by `original`, so a stem that stops stripping _vbr still groups the same
    # files). The mutation drive proved that on 2026-09-15: dropping _vbr from
    # axFileStem left every fixture check green. Direct vectors against the
    # oracle are what make that mutation visible.
    for name in NAME_VECTORS:
        c.ck(f"axFileStem {name!r}", call("axFileStem", [name]), REF.file_stem(name))
        c.ck(f"axVideoStem {name!r}", call("axVideoStem", [name]), REF.video_stem(name))
        c.ck(f"axPrettyName {name!r}", call("axPrettyName", [name]), REF.pretty_name(name))
        c.ck(f"axQualityLabel {name!r}", call("axQualityLabel", [name]), REF.quality_label(name))
    for title in TITLE_VECTORS:
        c.ck(f"axTrackTitleClean {title!r}", call("axTrackTitleClean", [title]), REF.track_title_clean(title))
    for name, item_title in CLEAN_TITLE_VECTORS:
        c.ck(f"axCleanTitle {name!r} / {item_title!r}", call("axCleanTitle", [name, item_title]),
             REF.clean_title(name, item_title))


def check_urls(c, ip):
    c.note("tier 1: every URL builder")
    call = ip.call
    c.ck("axSearchUrl (the AudioBooks bytes)",
         call("axSearchUrl", ['collection:(librivoxaudio) AND (a "b")', "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2]),
         REF.search_url('collection:(librivoxaudio) AND (a "b")', "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2))
    c.ck("axSearchUrl no sort", call("axSearchUrl", ["x", "identifier, title", "", 10, 3]), REF.search_url("x", "identifier, title", "", 10, 3))
    c.ck("axSearchUrl defaults", call("axSearchUrl", ["x", "identifier", "", "", ""]), REF.search_url("x", "identifier", "", 24, 1))
    c.ck("axScrapeUrl", call("axScrapeUrl", ["collection:(GratefulDead)", "identifier,title", 100, "abc=="]),
         REF.scrape_url("collection:(GratefulDead)", "identifier,title", 100, "abc=="))
    c.ck("axScrapeUrl defaults", call("axScrapeUrl", ["x", "", "", ""]), REF.scrape_url("x", "", 100, ""))
    for ident in ["abc", "gd1977-05-08.sbd.hicks.4982.sbeok.shnf"]:
        c.ck(f"axMetadataUrl {ident}", call("axMetadataUrl", [ident]), REF.metadata_url(ident))
        c.ck(f"axThumbnailUrl {ident}", call("axThumbnailUrl", [ident]), REF.thumbnail_url(ident))
        c.ck(f"axDetailsUrl {ident}", call("axDetailsUrl", [ident]), REF.details_url(ident))
        c.ck(f"axEmbedUrl {ident}", call("axEmbedUrl", [ident]), REF.embed_url(ident))
        for name in ["a b#1.mp3", "dir/one two.mp3", "", "café.mp3"]:
            c.ck(f"axDownloadUrl {ident} {name!r}", call("axDownloadUrl", [ident, name]), REF.download_url(ident, name))
    c.ck("axSetBaseUrl + axMetadataUrl", (call("axSetBaseUrl", ["http://mirror.test/"]), call("axMetadataUrl", ["abc"])),
         (True, "http://mirror.test/metadata/abc"))
    call("axSetBaseUrl", [""])


# --------------------------------------------------------------------- tier 2
def check_tables(c, ip):
    c.note("tier 2: the preset, filter and sort tables against the oracle's transcription")
    for family in ("etree", "librivox", "movies", "any"):
        got = ip.call("axPresetTable", [family])
        c.ck(f"axPresetTable {family}", got, REF.preset_table_text(family))
        for row in REF.presets(family):
            c.ck(f"axPresetQuery {family} {row[0]}", as_str(ip.call("axPresetQuery", [family, row[0]])), REF.preset_query(family, row[0]))
        want_filters = "\n".join("|".join(r) for r in REF.FILTERS[family])
        c.ck(f"axFilterList {family}", ip.call("axFilterList", [family]), want_filters)
    c.ck("axSortList", ip.call("axSortList", []), "\n".join("|".join(r) for r in REF.SORTS))
    c.ck("axVideoScope", ip.call("axVideoScope", []), REF.video_scope())
    for family in REF.FAMILIES:
        info = ip.call("axFamilyInfo", [family])
        c.ck(f"axFamilyInfo {family} scope", info["scope"], REF.family_scope(family))
        c.ck(f"axFamilyInfo {family} fields", info["fields"], REF.FAMILIES[family]["fields"])
        c.ck(f"axFamilyInfo {family} kind", info["kind"], REF.FAMILIES[family]["kind"])
        c.ck(f"axFamilyInfo {family} rows", as_str(info["rows"]), str(REF.FAMILIES[family]["rows"]))
    cases = [("librivox", "Romance", "emma", "", "", ("solo", "english", "bogus")),
             ("etree", "GratefulDead", "", "", "", ()),
             ("etree", "GratefulDead", "", "1977", "", ()),
             ("etree", "Collection_Search", "Phish", "1997", "1999", ("soundboard",)),
             ("etree", "Custom", "creator:(Phish) AND year:[1997 TO 1999]", "", "", ("matrix", "five-star")),
             ("librivox", "Author_Search", "Jane Austen", "", "", ()),
             ("librivox", "Title_Search", "Dracula: Chapter 1", "", "", ()),
             ("movies", "prelinger", "moon: rocket (test)", "", "", ("publicdomain",)),
             ("movies", "all_videos", "", "", "", ()),
             ("any", "texts", "pride \"and\" prejudice", "1800", "1900", ()),
             ("any", "Custom", "creator:(Austen)", "", "", ())]
    for family, pid, text, yf, yt, fids in cases:
        clauses = ip.call("axFilterClauses", [family, ",".join(fids)])
        spec = ip.call("axPresetSpec", [family, pid, text, yf, yt, clauses])
        got = as_str(ip.call("axQueryBuild", [spec]))
        c.ck(f"axPresetSpec+axQueryBuild {family}/{pid} {text!r}", got, REF.preset_spec_query(family, pid, text, yf, yt, fids))


# --------------------------------------------------------------------- tier 3
def entries_of(pl):
    out = []
    count = int(pl["count"])
    for i in range(1, count + 1):
        e = pl["entries"][str(i)]
        out.append(e)
    return out


def check_fixtures(c, ip):
    c.note("tier 3: the fixtures through both parsers and every playlist kind")
    for fname in ("librivox-search.json", "etree-search.json", "movies-search.json"):
        text = fixture(fname)
        got = ip.call("axSearchParse", [text])
        want = REF.search_parse(text)
        c.ck(f"{fname}: numFound/start/count", (as_str(got["numFound"]), as_str(got["start"]), as_str(got["count"])),
             (str(want["numFound"]), str(want["start"]), str(want["count"])))
        for i, wdoc in enumerate(want["docs"], start=1):
            gdoc = got["docs"][str(i)]
            for k, v in wdoc.items():
                c.ck(f"{fname}: doc {i} {k}", as_str(gdoc.get(k, "")), v)
        fields = "identifier,title,creator,date"
        table = ip.call("axDocsTable", [got, fields])
        want_table = "\n".join("\t".join(REF.first_value(d.get(f, "").split("\n")).replace("\t", " ") if d.get(f) else ""
                                         for f in fields.split(",")) for d in want["docs"])
        c.ck(f"{fname}: axDocsTable", table, want_table)
    kinds_for = {"librivox-item.json": ["audio-chapters", "audio-tracks", "files", "images", "auto"],
                 "etree-item.json": ["audio-tracks", "audio-chapters", "files", "auto", "documents"],
                 "movies-item.json": ["video", "files", "images", "auto"],
                 "texts-item.json": ["documents", "images", "files", "auto", "video"]}
    for fname, kinds in kinds_for.items():
        text = fixture(fname)
        got = ip.call("axItemParse", [text])
        want = REF.item_parse(text)
        c.ck(f"{fname}: identifier", got["identifier"], want["identifier"])
        c.ck(f"{fname}: filesCount", as_str(got["filesCount"]), str(want["filesCount"]))
        for k, v in want["metadata"].items():
            c.ck(f"{fname}: metadata {k}", as_str(got["metadata"].get(k, "")), v)
        for i, wf in enumerate(want["files"], start=1):
            gf = got["files"][str(i)]
            for k, v in wf.items():
                c.ck(f"{fname}: file {i} {k}", as_str(gf.get(k, "")), v)
        for kind in kinds:
            wpl = REF.playlist(want, kind)
            gpl = ip.call("axPlaylist", [got, kind])
            if wpl["count"] == 0:
                c.ck(f"{fname}/{kind}: refuses with no file of that kind", gpl, "")
                c.ck(f"{fname}/{kind}: the reason names the kind", "no %s file" % wpl["kind"] in ip.call("axLastError", []), True)
                continue
            c.ck(f"{fname}/{kind}: kind", gpl["kind"], wpl["kind"])
            c.ck(f"{fname}/{kind}: count", as_str(gpl["count"]), str(wpl["count"]))
            for ge, we in zip(entries_of(gpl), wpl["entries"]):
                for k in ("name", "title", "format", "size", "url", "stem", "quality"):
                    c.ck(f"{fname}/{kind}: {we['name']} {k}", as_str(ge[k]), we[k])
                c.ck(f"{fname}/{kind}: {we['name']} track", as_str(ge["track"]), "" if we["track"] is None else str(we["track"]))
                c.ck(f"{fname}/{kind}: {we['name']} length", as_str(ge["length"]), "" if we["length"] is None else REF.num_text(we["length"]))
                c.ck(f"{fname}/{kind}: {we['name']} index", as_str(ge["index"]), str(we["index"]))
                want_variants = "\n".join("|".join(v) for v in we["variants"])
                c.ck(f"{fname}/{kind}: {we['name']} variants", as_str(ge["variants"]), want_variants)
            table = ip.call("axPlaylistTable", [gpl])
            c.ck(f"{fname}/{kind}: table has one line per entry", len(table.split("\n")), wpl["count"])


# --------------------------------------------------------------------- tier 4
def check_refusals(c, ip):
    c.note("tier 4: refusals answer empty and record a reason")
    call = ip.call
    c.ck("the site's error shape", call("axSearchParse", [fixture("search-error.json")]), "")
    c.ck("  reason quotes the site", call("axLastError", []).startswith("Archive.org rejected the query"), True)
    c.ck("a missing item", call("axItemParse", [fixture("missing-item.json")]), "")
    c.ck("  reason says not found", "could not be found" in call("axLastError", []), True)
    for bad in ["not json", "{", "[1,2] x", '{"a":1,}', "[tRUE]", '["\\ud83d"]', '["\\q"]', "", "[01]"]:
        c.ck(f"axJsonParse refuses {bad!r}", call("axJsonParse", [bad]), "")
    c.ck("axJsonParse accepts a leading-zero-free number", call("axJsonParse", ["[0, 1.5, -2e3]"]) != "", True)
    for bad in ["", "../etc", "x y"]:
        c.ck(f"axMetadataUrl refuses {bad!r}", call("axMetadataUrl", [bad]), "")
    c.ck("axSearchUrl refuses an empty query", call("axSearchUrl", ["", "identifier", "", 10, 1]), "")
    c.ck("axSearchUrl refuses page 0", call("axSearchUrl", ["x", "identifier", "", 10, 0]), "")
    c.ck("axPresetInfo refuses an unknown id", call("axPresetInfo", ["etree", "gratefuldead"]), "")
    c.ck("axFamilyInfo refuses an unknown family", call("axFamilyInfo", ["nope"]), "")
    c.ck("axQueryBuild refuses nothing", call("axQueryBuild", [{}]), "")


def main(argv):
    terse = "--check" in argv
    c = Checker(terse)
    src = open(SCRIPT, encoding="utf-8").read()
    ip = LCS.Interp(src)
    check_interp_model(c, ip)
    check_scalars(c, ip)
    check_sanitizer(c, ip)
    check_name_rules(c, ip)
    check_urls(c, ip)
    check_tables(c, ip)
    check_fixtures(c, ip)
    check_refusals(c, ip)
    if c.failed:
        print(f"check-script-vectors: {c.failed} of {c.n} checks FAILED")
        return 1
    print(f"check-script-vectors: OK ({c.n} checks; the shipped script executed against the oracle "
          "and the fixtures)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
