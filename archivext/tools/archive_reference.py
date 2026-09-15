#!/usr/bin/env python3
"""archive_reference.py - the independent oracle for ArchiveXT's pure layer.

WHAT THIS IS. A second implementation, in Python, of every rule
src/archivext.livecodescript owns: the two URL encoders, the query
sanitizer and builder, the search/metadata/download/image URLs, the
duration and size formatters, natural ordering, the file-name stems and
title cleaners, the accept tests, and the playlist engine for every kind.
It is written from the THREE SOURCE APPS' own code (the AudioBooks
archive.js, the film club's VideoService.js / SearchService.js /
helpers.js, the tape finder's ArchiveProxy.php / search.js / utils.js),
regex for regex where they used one, NOT from the LiveCodeScript - so a
transcription slip in the script and a slip here would have to agree to
pass, and tools/check-script-vectors.py compares the two on every build.

WHAT ANCHORS IT. The three apps ship tests, and their known answers are
asserted here AT IMPORT (`_anchor()` below): the AudioBooks
test/archive.test.mjs and test/utils.test.mjs vectors (sanitizer, query
builder, URLs, parseLength, formatTime, chapterStem, prettifyFileName,
isAudioFile, selectAudioFiles, subjectTags), the film club's
formatFileSize and formatRuntime answers and its browser test's series
expectations, the tape finder's formatTime answers. A broken oracle
refuses to load - the nostr_reference.py contract.

WHERE THE ORACLE DEFINES A RULE OF ITS OWN, it says so, because the
three apps disagree in places and ArchiveXT had to pick:
  - the tape finder's PHP dedup was inverted (a repeated title kept its
    second MP3 and dropped a first-seen FLAC's later MP3); ArchiveXT ranks
    inside a group instead (VBR MP3 first), the rule the code reads as
    intending;
  - the year is the first run of EXACTLY four digits, where PHP's /(\d{4})/
    would take the first four of a longer run;
  - the film club keys episode titles off the file NAME even when the
    file carries a title; ArchiveXT prefers a file title when present,
    the AudioBooks rule, and falls back to the film club's cleaner;
  - multi-valued fields are LINES, one value per line (asList), so a
    scalar and a one-element array read the same.
Pure standard library. Never imported by shipped code.
"""

import json
import math
import re

ARCHIVE_BASE = "https://archive.org"

KEEP_URI = "-_.!~*'()"          # encodeURIComponent's spared characters
KEEP_FORM = "*-._"              # URLSearchParams' spared characters


# ------------------------------------------------------------------ encoders
def _is_alnum_ascii(ch):
    return ("a" <= ch <= "z") or ("A" <= ch <= "Z") or ("0" <= ch <= "9")


def url_encode(text):
    """encodeURIComponent, byte for byte."""
    out = []
    for b in str(text).encode("utf-8"):
        ch = chr(b)
        if _is_alnum_ascii(ch) or ch in KEEP_URI:
            out.append(ch)
        else:
            out.append("%%%02X" % b)
    return "".join(out)


def url_encode_path(path):
    return "/".join(url_encode(seg) for seg in str(path).split("/"))


def query_encode(text):
    """URLSearchParams' application/x-www-form-urlencoded."""
    out = []
    for b in str(text).encode("utf-8"):
        ch = chr(b)
        if ch == " ":
            out.append("+")
        elif _is_alnum_ascii(ch) or ch in KEEP_FORM:
            out.append(ch)
        else:
            out.append("%%%02X" % b)
    return "".join(out)


# ---------------------------------------------------------------------- urls
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$")


def identifier_valid(text):
    return isinstance(text, str) and bool(IDENTIFIER_RE.match(text))


def search_url(query, fields, sort="downloads desc", rows=24, page=1, base=ARCHIVE_BASE):
    parts = ["q=" + query_encode(query)]
    for f in [x.strip() for x in fields.split(",") if x.strip()]:
        parts.append("fl%5B%5D=" + query_encode(f))
    if sort and sort.strip():
        parts.append("sort%5B%5D=" + query_encode(sort.strip()))
    parts.append("rows=%d" % int(rows))
    parts.append("page=%d" % int(page))
    parts.append("output=json")
    return base + "/advancedsearch.php?" + "&".join(parts)


def scrape_url(query, fields, count=100, cursor="", base=ARCHIVE_BASE):
    url = base + "/services/search/v1/scrape?q=" + query_encode(query)
    if fields and fields.strip():
        url += "&fields=" + query_encode(fields.strip())
    url += "&count=%d" % int(count)
    if cursor:
        url += "&cursor=" + query_encode(cursor)
    return url


def metadata_url(identifier, base=ARCHIVE_BASE):
    return base + "/metadata/" + url_encode(identifier)


def download_url(identifier, file_name="", base=ARCHIVE_BASE):
    if not file_name:
        return base + "/download/" + url_encode(identifier)
    return base + "/download/" + url_encode(identifier) + "/" + url_encode_path(file_name)


def thumbnail_url(identifier, base=ARCHIVE_BASE):
    return base + "/services/img/" + url_encode(identifier)


def details_url(identifier, base=ARCHIVE_BASE):
    return base + "/details/" + url_encode(identifier)


def embed_url(identifier, base=ARCHIVE_BASE):
    return base + "/embed/" + url_encode(identifier)


# ------------------------------------------------------------------- scalars
def year_of(text):
    """ArchiveXT's rule: the first run of EXACTLY four digits."""
    m = re.search(r"(?<!\d)(\d{4})(?!\d)", str(text))
    return m.group(1) if m else ""


def normalize_year(value):
    text = str(value if value is not None else "").strip()
    if not re.match(r"^\d{4}$", text):
        return ""
    n = int(text)
    return text if 1000 <= n <= 9999 else ""


def duration_seconds(value):
    """The AudioBooks parseLength: None for unreadable, else a number."""
    if value is None or value == "":
        return None
    text = str(value).strip()
    if ":" in text:
        parts = text.split(":")
        total = 0.0
        for p in parts:
            p = p.strip()
            if not re.match(r"^\d+(\.\d+)?$", p) and not re.match(r"^\.\d+$", p):
                return None
            total = total * 60 + float(p)
        return total
    if not re.match(r"^\d*\.?\d*$", text) or not re.search(r"\d", text):
        return None
    return float(text)


def num_text(v):
    """A number the way xTalk prints it: integers without a point."""
    if v is None:
        return ""
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def format_time(seconds):
    """The AudioBooks formatTime."""
    try:
        total = float(seconds)
    except (TypeError, ValueError):
        return "0:00"
    if math.isnan(total) or math.isinf(total) or total < 0:
        return "0:00"
    whole = int(math.floor(total))
    hours, rest = divmod(whole, 3600)
    mins, secs = divmod(rest, 60)
    if hours > 0:
        return "%d:%02d:%02d" % (hours, mins, secs)
    return "%d:%02d" % (mins, secs)


def format_bytes(nbytes):
    """The film club's formatFileSize."""
    try:
        b = float(nbytes)
    except (TypeError, ValueError):
        return ""
    if not b or b < 0:
        return ""
    units = ["B", "KB", "MB", "GB", "TB"]
    i = min(len(units) - 1, max(0, int(math.floor(math.log(b) / math.log(1024)))))
    value = round(b / math.pow(1024, i) * 100) / 100
    text = num_text(value)
    return text + " " + units[i]


def natural_key(text):
    return re.sub(r"\d+", lambda m: m.group(0).zfill(12), str(text).lower())


def natural_sort(lines):
    return sorted(lines, key=natural_key)


def first_value(value, fallback=""):
    lst = as_list(value)
    return lst[0] if lst else fallback


def as_list(value):
    if value is None:
        return []
    lst = value if isinstance(value, list) else [value]
    out = []
    for v in lst:
        if v is None:
            continue
        s = str(v).strip() if not isinstance(v, bool) else ("true" if v else "false")
        if s:
            out.append(s)
    return out


def track_number(track):
    if track is None:
        return None
    m = re.search(r"\d+", str(track))
    return int(m.group(0)) if m else None


# ----------------------------------------------------------------- sanitizer
def _is_balanced(text, open_ch, close_ch):
    depth = 0
    for ch in text:
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def sanitize(raw, allow_field_syntax=False):
    """The AudioBooks sanitizeUserQuery, regex for regex."""
    q = str(raw if raw is not None else "").strip()
    if not q:
        return ""
    q = re.sub(r"[\\/]", " ", q)
    if not allow_field_syntax:
        q = re.sub(r"[{}\[\]^~:]", " ", q)
        q = re.sub(r"(^|\s)[+\-!]+(?=\s|$)", " ", q)
        q = re.sub(r"&&|\|\|", " ", q)
    else:
        if not _is_balanced(q, "[", "]"):
            q = re.sub(r"[\[\]]", " ", q)
        if not _is_balanced(q, "{", "}"):
            q = re.sub(r"[{}]", " ", q)
    if q.count('"') % 2 == 1:
        q = q.replace('"', " ")
    if not _is_balanced(q, "(", ")"):
        q = re.sub(r"[()]", " ", q)
    while True:
        previous = q
        q = re.sub(r"\(\s*\)", " ", q)
        q = re.sub(r"\b(?:AND|OR|NOT)(?:\s+(?:AND|OR|NOT))+\b",
                   lambda m: m.group(0).split()[-1], q)
        q = re.sub(r"^(?:AND|OR)\s+", "", q)
        q = re.sub(r"\s+(?:AND|OR|NOT)$", "", q)
        q = re.sub(r"\(\s*(?:AND|OR)\s+", "(", q)
        q = re.sub(r"\s+(?:AND|OR|NOT)\s*\)", ")", q)
        q = re.sub(r"\s+", " ", q).strip()
        if q == previous:
            break
    if re.match(r"^(?:AND|OR|NOT)$", q):
        q = ""
    return q


def plain_text_clean(text):
    """The film club's user-text rule: strip : " ( ) and collapse."""
    return re.sub(r"\s+", " ", re.sub(r'[:"()]', " ", str(text or ""))).strip()


def query_years(year_from, year_to):
    f, t = normalize_year(year_from), normalize_year(year_to)
    if not f and not t:
        return ""
    if f and t and int(f) > int(t):
        f, t = t, f
    return "year:[%s TO %s]" % (f or "*", t or "*")


def build_query(base="", text="", text_field="", field_syntax=False,
                year_from="", year_to="", filters=(), plain_text=False):
    q = (base or "").strip()
    clean = plain_text_clean(text) if plain_text else sanitize(text, field_syntax)
    parts = [q] if q else []
    if clean:
        parts.append("%s:(%s)" % (text_field, clean) if text_field else "(%s)" % clean)
    years = query_years(year_from, year_to)
    if years:
        parts.append(years)
    for f in filters:
        f = (f or "").strip()
        if f:
            parts.append(f)
    return " AND ".join(parts)


# -------------------------------------------------------------------- tables
LIBRIVOX_SCOPE = "collection:(librivoxaudio)"

# The AudioBooks categoryConfig.js, transcribed from the JS source (a
# second transcription, so the script's table is checked against it).
LIBRIVOX_PRESETS = [
    ("AllLibriVox", "All audiobooks", "Browse", LIBRIVOX_SCOPE, ""),
    ("Author_Search", "Search by author", "Browse", "", "creator"),
    ("Title_Search", "Search by title", "Browse", "", "title"),
    ("Custom", "Advanced search", "Browse", "", "custom"),
    ("ClassicLiterature", "Classic literature", "Fiction",
     LIBRIVOX_SCOPE + " AND subject:(fiction) AND (subject:(classic) OR subject:(literature))", ""),
    ("Romance", "Romance", "Fiction", LIBRIVOX_SCOPE + " AND subject:(romance)", ""),
    ("Mystery", "Mystery & detective", "Fiction", LIBRIVOX_SCOPE + " AND (subject:(mystery) OR subject:(detective))", ""),
    ("ScienceFiction", "Science fiction", "Fiction", LIBRIVOX_SCOPE + ' AND subject:("science fiction")', ""),
    ("Fantasy", "Fantasy", "Fiction", LIBRIVOX_SCOPE + " AND subject:(fantasy)", ""),
    ("Adventure", "Adventure", "Fiction", LIBRIVOX_SCOPE + " AND subject:(adventure)", ""),
    ("Horror", "Horror & gothic", "Fiction", LIBRIVOX_SCOPE + " AND (subject:(horror) OR subject:(ghost))", ""),
    ("ShortStories", "Short stories", "Fiction", LIBRIVOX_SCOPE + ' AND subject:("short stories")', ""),
    ("Humor", "Humor & satire", "Fiction", LIBRIVOX_SCOPE + " AND (subject:(humor) OR subject:(humorous))", ""),
    ("History", "History", "Non-fiction", LIBRIVOX_SCOPE + " AND subject:(history)", ""),
    ("Biography", "Biography & memoir", "Non-fiction", LIBRIVOX_SCOPE + " AND (subject:(biography) OR subject:(autobiography))", ""),
    ("Philosophy", "Philosophy", "Non-fiction", LIBRIVOX_SCOPE + " AND subject:(philosophy)", ""),
    ("Science", "Science & nature", "Non-fiction", LIBRIVOX_SCOPE + " AND subject:(science) -subject:(fiction)", ""),
    ("Religion", "Religion & spirituality", "Non-fiction", LIBRIVOX_SCOPE + " AND (subject:(religion) OR subject:(theology))", ""),
    ("Travel", "Travel & exploration", "Non-fiction", LIBRIVOX_SCOPE + " AND subject:(travel)", ""),
    ("Essays", "Essays & letters", "Non-fiction", LIBRIVOX_SCOPE + " AND subject:(essays)", ""),
    ("Poetry", "Poetry", "Poetry and drama", LIBRIVOX_SCOPE + " AND subject:(poetry)", ""),
    ("Drama", "Drama & plays", "Poetry and drama", LIBRIVOX_SCOPE + " AND (subject:(drama) OR subject:(plays))", ""),
    ("Shakespeare", "Shakespeare", "Poetry and drama", LIBRIVOX_SCOPE + " AND creator:(Shakespeare)", ""),
    ("Childrens", "Children's literature", "Children's books", LIBRIVOX_SCOPE + ' AND subject:("children\'s literature")', ""),
    ("FairyTales", "Fairy tales & folklore", "Children's books", LIBRIVOX_SCOPE + ' AND (subject:("fairy tales") OR subject:(folklore))', ""),
    ("JaneAusten", "Jane Austen", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Jane Austen")', ""),
    ("CharlesDickens", "Charles Dickens", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Charles Dickens")', ""),
    ("MarkTwain", "Mark Twain", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Mark Twain")', ""),
    ("ArthurConanDoyle", "Arthur Conan Doyle", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Arthur Conan Doyle")', ""),
    ("EdgarAllanPoe", "Edgar Allan Poe", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Edgar Allan Poe")', ""),
    ("HGWells", "H.G. Wells", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("H. G. Wells")', ""),
    ("JulesVerne", "Jules Verne", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Jules Verne")', ""),
    ("LouisaMayAlcott", "Louisa May Alcott", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Louisa May Alcott")', ""),
    ("OscarWilde", "Oscar Wilde", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("Oscar Wilde")', ""),
    ("LFrankBaum", "L. Frank Baum (Oz)", "Popular authors", LIBRIVOX_SCOPE + ' AND creator:("L. Frank Baum")', ""),
    ("French", "French audiobooks", "By language", LIBRIVOX_SCOPE + " AND language:(French)", ""),
    ("German", "German audiobooks", "By language", LIBRIVOX_SCOPE + " AND language:(German)", ""),
    ("Spanish", "Spanish audiobooks", "By language", LIBRIVOX_SCOPE + " AND language:(Spanish)", ""),
    ("Italian", "Italian audiobooks", "By language", LIBRIVOX_SCOPE + " AND language:(Italian)", ""),
    ("Russian", "Russian audiobooks", "By language", LIBRIVOX_SCOPE + " AND language:(Russian)", ""),
]

# The tape finder's bandConfig.js: (id, title, group, query, mode, yearFrom, yearTo)
_E = " AND mediatype:(etree)"
ETREE_PRESETS = [
    ("AllArchive", "All Archive.org live music", "Quick options", "mediatype:(etree)", "", "1900", ""),
    ("Collection_Search", "Search by collection name", "Quick options", "", "collection", "", ""),
    ("Custom", "Custom advanced search", "Quick options", "", "custom", "", ""),
    ("GratefulDead", "Grateful Dead", "Dead family", "collection:(GratefulDead) AND mediatype:(etree) AND creator:(Grateful Dead)", "", "1965", "1995"),
    ("DeadAndCompany", "Dead & Company", "Dead family", 'collection:(etree) AND creator:("Dead and Company" OR "Dead & Company")', "", "", ""),
    ("PhilLesh", "Phil Lesh & Friends", "Dead family", "collection:(PhilLeshandFriends)" + _E, "", "", ""),
    ("JerryGarciaBand", "Jerry Garcia Band", "Dead family", 'collection:(etree) AND creator:("Jerry Garcia Band" OR "JGB")', "", "", ""),
    ("RatDog", "Ratdog", "Dead family", 'collection:(etree) AND creator:("Ratdog" OR "Bob Weir and Ratdog")', "", "", ""),
    ("BobWeir", "Bob Weir", "Dead family", 'collection:(etree) AND creator:("Bob Weir") -creator:("Bob Weir and Ratdog")', "", "", ""),
    ("Furthur", "Furthur", "Dead family", "collection:(Furthur)" + _E, "", "", ""),
    ("DarkStar", "Dark Star Orchestra", "Dead family", "collection:(DarkStarOrchestra)" + _E, "", "", ""),
    ("JRAD", "Joe Russo's Almost Dead", "Dead family", "collection:(JoeRussosAlmostDead)" + _E, "", "", ""),
    ("WidespreadPanic", "Widespread Panic", "Jam bands", "collection:(WidespreadPanic)" + _E, "", "", ""),
    ("StringCheese", "String Cheese Incident", "Jam bands", "collection:(StringCheeseIncident)" + _E, "", "", ""),
    ("UmphreysMcGee", "Umphrey's McGee", "Jam bands", "collection:(UmphreysMcGee)" + _E, "", "", ""),
    ("moe", "moe.", "Jam bands", "collection:(moe)" + _E, "", "", ""),
    ("DiscoBiscuits", "Disco Biscuits", "Jam bands", "collection:(DiscoBiscuits)" + _E, "", "", ""),
    ("STS9", "STS9", "Jam bands", "collection:(SoundTribeSector9)" + _E, "", "", ""),
    ("Goose", "Goose", "Jam bands", "collection:(GooseBand)" + _E, "", "", ""),
    ("Lotus", "Lotus", "Jam bands", "collection:(Lotus)" + _E, "", "", ""),
    ("Twiddle", "Twiddle", "Jam bands", "collection:(Twiddle)" + _E, "", "", ""),
    ("Dopapod", "Dopapod", "Jam bands", "collection:(Dopapod)" + _E, "", "", ""),
    ("PigeonsPPP", "Pigeons Playing Ping Pong", "Jam bands", "collection:(PigeonsPlayingPingPong)" + _E, "", "", ""),
    ("Spafford", "Spafford", "Jam bands", "collection:(Spafford)" + _E, "", "", ""),
    ("BillyStrings", "Billy Strings", "Bluegrass and acoustic", "collection:(BillyStrings)" + _E, "", "", ""),
    ("GreenskyBluegrass", "Greensky Bluegrass", "Bluegrass and acoustic", "collection:(GreenskyBluegrass)" + _E, "", "", ""),
    ("YonderMountain", "Yonder Mountain String Band", "Bluegrass and acoustic", "collection:(YonderMountainStringBand)" + _E, "", "", ""),
    ("LeftoverSalmon", "Leftover Salmon", "Bluegrass and acoustic", "collection:(LeftoverSalmon)" + _E, "", "", ""),
    ("KitchenDwellers", "Kitchen Dwellers", "Bluegrass and acoustic", "collection:(KitchenDwellers)" + _E, "", "", ""),
    ("InfamousStringdusters", "Infamous Stringdusters", "Bluegrass and acoustic", "collection:(InfamousStringdusters)" + _E, "", "", ""),
    ("Lettuce", "Lettuce", "Funk and soul", "collection:(Lettuce)" + _E, "", "", ""),
    ("Soulive", "Soulive", "Funk and soul", "collection:(Soulive)" + _E, "", "", ""),
    ("GalacticFunk", "Galactic", "Funk and soul", "collection:(GalacticFunk)" + _E, "", "", ""),
    ("Dumpstaphunk", "Dumpstaphunk", "Funk and soul", "collection:(Dumpstaphunk)" + _E, "", "", ""),
    ("TheMotet", "The Motet", "Funk and soul", "collection:(TheMotet)" + _E, "", "", ""),
    ("Vulfpeck", "Vulfpeck", "Funk and soul", "collection:(Vulfpeck)" + _E, "", "", ""),
    ("Ween", "Ween", "Rock and indie", "collection:(Ween)" + _E, "", "", ""),
    ("Wilco", "Wilco", "Rock and indie", "collection:(Wilco)" + _E, "", "", ""),
    ("MyMorningJacket", "My Morning Jacket", "Rock and indie", "collection:(MyMorningJacket)" + _E, "", "", ""),
    ("KingGizzard", "King Gizzard & The Lizard Wizard", "Rock and indie", "collection:(KingGizzardAndTheLizardWizard)" + _E, "", "", ""),
    ("DrDog", "Dr. Dog", "Rock and indie", "collection:(DrDog)" + _E, "", "", ""),
    ("TenaciousD", "Tenacious D", "Rock and indie", "collection:(TenaciousD)" + _E, "", "", ""),
    ("Tipper", "Tipper", "Electronic", "collection:(Tipper)" + _E, "", "", ""),
    ("Papadosio", "Papadosio", "Electronic", "collection:(Papadosio)" + _E, "", "", ""),
    ("Shpongle", "Shpongle", "Electronic", "collection:(Shpongle)" + _E, "", "", ""),
    ("EOTO", "EOTO", "Electronic", "collection:(EOTO)" + _E, "", "", ""),
    ("Matisyahu", "Matisyahu", "Reggae and world", "collection:(Matisyahu)" + _E, "", "", ""),
    ("RebelutionMusic", "Rebelution", "Reggae and world", "collection:(RebelutionMusic)" + _E, "", "", ""),
    ("StickFigure", "Stick Figure", "Reggae and world", "collection:(StickFigure)" + _E, "", "", ""),
]

# The film club's config.js COLLECTIONS, in insertion order.
VIDEO_COLLECTIONS = [
    ("all_videos", "All Videos"), ("feature_films", "Feature Films"), ("adviews", "AdViews"),
    ("academic_films", "Academic Films"), ("animationandcartoons", "Animation & Cartoons"),
    ("artsandmusicvideos", "Arts & Music"), ("classic_tv", "Classic TV"), ("Comedy_Films", "Comedy Films"),
    ("educationalfilms", "Educational Films"), ("ephemera", "Ephemeral Films"), ("FedFlix", "FedFlix"),
    ("Film_Noir", "Film Noir"), ("gamevideos", "Game Videos"), ("home_movies", "Home Movies"),
    ("movie_trailers", "Movie Trailers"), ("movies", "Moving Image Archive"), ("nasa", "NASA Archive"),
    ("newsandpublicaffairs", "News & Public Affairs"), ("opensource_movies", "Open Source Movies"),
    ("prelinger", "Prelinger Archives"), ("short_films", "Short Format Films"), ("silent_films", "Silent Films"),
    ("SciFi_Horror", "Sci-Fi / Horror Films"), ("sports", "Sports"), ("tvarchive", "Television Archive"),
    ("television", "Television"),
]


def video_scope():
    ids = [i for i, _ in VIDEO_COLLECTIONS if i != "all_videos"]
    return ("(mediatype:(movies OR video OR television) OR (mediatype:collection AND identifier:("
            + " OR ".join(ids) + ")))")


VIDEO_SCOPE_FAST = "mediatype:(movies OR video OR television)"


def movies_presets():
    # The CHEAP scope (2026-09-15): the film club's full video_scope() did not
    # answer inside 30 s on the live site; a collection clause plus the
    # mediatype clause did.
    rows = []
    for cid, title in VIDEO_COLLECTIONS:
        q = VIDEO_SCOPE_FAST if cid == "all_videos" else "collection:(%s) AND %s" % (cid, VIDEO_SCOPE_FAST)
        rows.append((cid, title, "Collections", q, "", "", ""))
    return rows


ANY_PRESETS = [
    ("all", "Everything", "Media types", "", "", "", ""),
    ("texts", "Texts (books, documents)", "Media types", "mediatype:(texts)", "", "", ""),
    ("audio", "Audio", "Media types", "mediatype:(audio)", "", "", ""),
    ("movies", "Moving images", "Media types", "mediatype:(movies)", "", "", ""),
    ("image", "Images", "Media types", "mediatype:(image)", "", "", ""),
    ("software", "Software", "Media types", "mediatype:(software)", "", "", ""),
    ("etree", "Live music", "Media types", "mediatype:(etree)", "", "", ""),
    ("data", "Data sets", "Media types", "mediatype:(data)", "", "", ""),
    ("collection", "Collections", "Media types", "mediatype:(collection)", "", "", ""),
    ("Custom", "Advanced search (field syntax)", "Media types", "", "custom", "", ""),
]

PUBLIC_DOMAIN = ('(licenseurl:"http://creativecommons.org/publicdomain/mark/1.0/" OR '
                 'licenseurl:"https://creativecommons.org/publicdomain/mark/1.0/" OR '
                 'licenseurl:"http://creativecommons.org/publicdomain/")')

FILTERS = {
    "etree": [("soundboard", "Soundboard (SBD)", 'source:(soundboard OR sbd OR "sbd")'),
              ("aud", "Audience (AUD)", 'source:(audience OR aud OR "aud")'),
              ("matrix", "Matrix", 'source:(matrix OR "matrix")'),
              ("five-star", "Top rated", "avg_rating:[4.5 TO 5]")],
    "librivox": [("solo", "Solo reader", "subject:(solo)"),
                 ("complete", "Complete works", "subject:(complete)"),
                 ("english", "English only", "language:(English)")],
    "movies": [("publicdomain", "Public domain only", PUBLIC_DOMAIN)],
    "any": [],
}

SORTS = [("downloads", "Most downloaded", "downloads desc"), ("date", "Newest added", "publicdate desc"),
         ("dateDesc", "Date, newest first", "date desc"), ("dateAsc", "Date, oldest first", "date asc"),
         ("title", "Title A-Z", "titleSorter asc"), ("creator", "Creator A-Z", "creatorSorter asc"),
         ("relevance", "Relevance", "")]

FAMILIES = {
    "etree": dict(title="Live music (etree)", kind="audio-tracks", scope="mediatype:(etree)", rows=10,
                  fields="identifier,title,creator,date,year,venue,coverage,source,avg_rating,downloads"),
    "librivox": dict(title="Audiobooks (LibriVox)", kind="audio-chapters", scope=LIBRIVOX_SCOPE, rows=24,
                     fields="identifier,title,year,creator,date,language,runtime,subject"),
    "movies": dict(title="Films and video", kind="video", scope=None, rows=24,
                   fields="identifier,title,description,date,downloads,creator,runtime,licenseurl,subject,mediatype,num_items"),
    "any": dict(title="Everything on archive.org", kind="auto", scope="", rows=24,
                fields="identifier,title,creator,date,year,mediatype,collection,downloads,avg_rating,num_reviews"),
}


def family_scope(family):
    if family == "movies":
        return VIDEO_SCOPE_FAST
    return FAMILIES[family]["scope"]


def presets(family):
    if family == "etree":
        return list(ETREE_PRESETS)
    if family == "librivox":
        return [(i, t, g, q, m, "", "") for i, t, g, q, m in LIBRIVOX_PRESETS]
    if family == "movies":
        return movies_presets()
    if family == "any":
        return list(ANY_PRESETS)
    raise KeyError(family)


def preset_table_text(family):
    """The exact text axPresetTable answers: one row per line, | separated."""
    return "\n".join("|".join(r) for r in presets(family))


def preset_query(family, pid):
    for row in presets(family):
        if row[0] == pid:
            return row[3] if not row[4] else family_scope(family)
    return None


def preset_spec_query(family, pid, text="", year_from="", year_to="", filter_ids=()):
    """What axPresetSpec + axQueryBuild answer for a preset."""
    row = next(r for r in presets(family) if r[0] == pid)
    mode = row[4]
    yf, yt = year_from, year_to
    if not normalize_year(yf) and not normalize_year(yt):
        yf, yt = row[5], row[6]
    clauses = [c for i, _, c in FILTERS[family] if i in filter_ids]
    if not mode:
        return build_query(base=row[3], text=text, year_from=yf, year_to=yt, filters=clauses,
                           plain_text=(family == "movies"))
    if mode == "custom":
        return build_query(base=family_scope(family), text=text, field_syntax=True, year_from=yf,
                           year_to=yt, filters=clauses, plain_text=(family == "movies"))
    return build_query(base=family_scope(family), text=text, text_field=mode, year_from=yf,
                       year_to=yt, filters=clauses, plain_text=(family == "movies"))


# ----------------------------------------------------------- names and files
def file_stem(name):
    """The AudioBooks chapterStem."""
    return re.sub(r"_(?:\d{1,3}kb|vbr|orig|original)$", "",
                  re.sub(r"\.[a-z0-9]+$", "", str(name).lower()))


def video_stem(name):
    """The film club's normalizeBaseName."""
    bn = re.sub(r"\.[^.]+$", "", str(name))
    while True:
        prev = bn
        bn = re.sub(r"\.(mp4|m4v|webm|ogv|ogg|avi|mov|mkv|flv|wmv|mpg|mpeg|ia)$", "", bn, flags=re.I)
        bn = re.sub(r"[_.-]\d{3,4}p$", "", bn, flags=re.I)
        bn = re.sub(r"[_.-](?:archive|512kb|h264|h\.264|hd|sd)$", "", bn, flags=re.I)
        if bn == prev:
            break
    return bn.lower().strip()


def pretty_name(name):
    """The AudioBooks prettifyFileName."""
    stem = re.sub(r"_(?:\d{1,3}kb|vbr)$", "",
                  re.sub(r"\.[a-z0-9]+$", "", str(name).split("/")[-1], flags=re.I), flags=re.I)
    out = re.sub(r"\s+", " ", re.sub(r"[_]+", " ", stem)).strip()
    return out or str(name)


def track_title_clean(title):
    """The tape finder's PHP title cleaner, whitespace collapsed after it
    (ArchiveXT's one cosmetic addition)."""
    t = re.sub(r"^(d\d+)?t\d+[\s._-]*", "", str(title), flags=re.I)
    t = t.replace("_", " ").replace("-", " ")
    return re.sub(r"\s+", " ", t).strip()


def clean_title(filename, item_title):
    """The film club's getCleanTitle."""
    if not filename:
        return "Untitled"
    title = re.sub(r"\.[^/.]+$", "", filename)
    ident = re.sub(r"[^a-z0-9]", "", (item_title or "").lower())
    if ident and title.lower().startswith(ident):
        title = title[len(ident):]
    title = re.sub(r"^[-_\s]+|[-_\s]+$", "", title)
    title = re.sub(r"\s+", " ", re.sub(r"[-_]", " ", title)).strip()
    return title or "Untitled"


def quality_label(name):
    n = str(name).lower()
    if "1080p" in n or "1920x1080" in n:
        return "1080p"
    if "720p" in n or "1280x720" in n:
        return "720p"
    if "480p" in n or "854x480" in n:
        return "480p"
    if "360p" in n or "640x360" in n:
        return "360p"
    if "_h264" in n:
        return "H.264"
    if "_512kb" in n:
        return "SD"
    if "_archive" in n:
        return "Archive"
    return "Auto"


NOISE_SUBJECTS = re.compile(r"^(librivox|audio ?books?|audio|literature)$", re.I)


def subject_tags(subject, max_tags=2, max_length=20):
    seen, tags = set(), []
    for raw in [s for v in as_list(subject) for s in re.split(r"[;|]", v)]:
        tag = raw.strip()
        if not tag or len(tag) >= max_length or NOISE_SUBJECTS.match(tag):
            continue
        key = tag.lower()
        if key in seen:
            continue
        seen.add(key)
        tags.append(tag[0].upper() + tag[1:])
        if len(tags) == max_tags:
            break
    return tags


def _ext(name):
    m = re.search(r"\.([^./]+)$", str(name).lower())
    return m.group(1) if m else ""


AUDIO_EXT = re.compile(r"\.(mp3|ogg|oga|opus|m4a|m4b|flac|wav)$", re.I)
NON_AUDIO_FORMAT = re.compile(r"zip|m3u|spectrogram|png|jpeg|jpg|peaks|metadata|torrent|text|xml")


def is_audio(f):
    if not f or not isinstance(f.get("name"), str) or not AUDIO_EXT.search(f["name"]):
        return False
    fmt = str(f.get("format") or "").lower()
    if NON_AUDIO_FORMAT.search(fmt):
        return False
    return fmt == "" or bool(re.search(r"mp3|ogg|vorbis|mpeg|audio|flac|wave|opus|aac", fmt))


PLAYABLE_EXTS = re.compile(r"\.(mp4|m4v|webm|ogv|ogg|mov|mpg|mpeg)$", re.I)
TOLERATED_EXTS = re.compile(r"\.(avi|flv|mkv|wmv)$", re.I)
SENTINELS = [re.compile(p, re.I) for p in (
    r"_meta\.(xml|sqlite|json)$", r"_files\.(xml|json)$", r"_reviews\.(xml|json)$", r"_itemimage\.",
    r"__ia_thumb\.", r"_thumb\.(jpg|jpeg|png|gif|webp)$",
    r"\.(torrent|srt|vtt|ass|ssa|json|xml|txt|pdf|doc|docx|sqlite|gz|zip|nfo|md5|asr|cue)$", r"\.ia$")]


def is_video(f):
    fmt = str(f.get("format") or "").lower()
    name = str(f.get("name") or "")
    lower = name.lower()
    try:
        size = int(str(f.get("size") or 0), 10)
    except ValueError:
        size = 0
    if not name:
        return False
    for rx in SENTINELS:
        if rx.search(lower):
            return False
    if any(k in fmt for k in ("metadata", "text", "image", "thumbnail", "archive bittorrent", "json",
                              "item tile", "subtitles")):
        return False
    is_playable = bool(PLAYABLE_EXTS.search(lower))
    is_tolerated = bool(TOLERATED_EXTS.search(lower))
    is_fmt = any(k in fmt for k in ("mp4", "mpeg", "video", "h.264", "h264", "webm", "ogv", "ogg video",
                                    "matroska", "quicktime"))
    if not is_playable and not is_tolerated and not is_fmt:
        return False
    if 0 < size < 100 * 1024:
        return False
    return True


def is_document(f):
    name = str(f.get("name") or "").lower()
    if not name:
        return False
    if re.search(r"(_meta\.xml|_files\.xml|_reviews\.xml|_meta\.sqlite|_abbyy\.gz|_djvu\.xml|_scandata\.xml|_hocr\.html)$", name):
        return False
    fmt = str(f.get("format") or "").lower()
    if any(k in fmt for k in ("metadata", "archive bittorrent", "item tile", "abbyy", "scandata", "hocr")):
        return False
    if _ext(name) in ("pdf", "epub", "djvu", "txt", "mobi", "azw3", "cbz", "cbr", "rtf", "html", "htm"):
        return True
    return any(k in fmt for k in ("pdf", "epub", "djvu", "kindle", "daisy", "full text", "plain text"))


def is_image(f):
    name = str(f.get("name") or "").lower()
    if not name:
        return False
    if "__ia_thumb." in name or "_itemimage." in name:
        return False
    if re.search(r"_thumb\.(jpg|jpeg|png|gif|webp)$", name):
        return False
    fmt = str(f.get("format") or "").lower()
    if any(k in fmt for k in ("thumb", "item tile", "metadata", "spectrogram")):
        return False
    return _ext(name) in ("jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "bmp", "jp2")


def is_content(f):
    name = str(f.get("name") or "").lower()
    if not name:
        return False
    if re.search(r"(_meta\.xml|_files\.xml|_reviews\.xml|_meta\.sqlite)$", name) or "__ia_thumb." in name:
        return False
    if _ext(name) == "torrent":
        return False
    fmt = str(f.get("format") or "").lower()
    return not any(k in fmt for k in ("metadata", "archive bittorrent", "item tile"))


ACCEPT = {"audio-chapters": is_audio, "audio-tracks": is_audio, "video": is_video,
          "documents": is_document, "images": is_image, "files": is_content}


def rank(f, kind):
    fmt = str(f.get("format") or "").lower()
    name = str(f.get("name") or "").lower()
    ext = _ext(name)
    source = str(f.get("source") or "").lower()
    if kind == "audio-chapters":
        is_mp3 = "mp3" in fmt or ext == "mp3"
        if is_mp3:
            if source == "original":
                return 0
            if "64kbps" in fmt:
                return 1
            if "vbr" in fmt:
                return 2
            return 3
        if ext in ("m4a", "m4b") or "aac" in fmt:
            return 4
        if "ogg" in fmt or "vorbis" in fmt or ext in ("ogg", "oga"):
            return 5
        return 6
    if kind == "audio-tracks":
        if "mp3" in fmt:
            if "vbr" in fmt:
                return 0
            if "64kbps" in fmt or "_64kb" in name:
                return 2
            return 1
        if ext == "mp3":
            if "_vbr" in name:
                return 0
            if "_64kb" in name:
                return 2
            return 1
        if any(k in fmt for k in ("ogg", "vorbis", "opus", "aac")) or ext in ("ogg", "oga", "opus", "m4a"):
            return 3
        if "flac" in fmt or "wave" in fmt or ext in ("flac", "wav"):
            return 4
        return 5
    if kind == "video":
        return 0 if ext == "mp4" else 1
    if kind == "documents":
        if "text pdf" in fmt:
            return 0
        return {"pdf": 1, "epub": 2, "djvu": 3, "txt": 4}.get(ext, 5)
    if kind == "images":
        return 0 if source == "original" else 1
    return 0


def _size(f):
    s = str(f.get("size") or "")
    return int(s) if s.isdigit() else 0


def group_key(f, kind):
    if kind in ("audio-chapters", "audio-tracks"):
        src = str(f.get("source") or "").lower()
        if src == "derivative" and f.get("original"):
            return file_stem(f["original"])
        return file_stem(f["name"])
    if kind == "video":
        return video_stem(f["name"])
    return "file:" + str(f["name"])


def kind_for(family, mediatype):
    if family == "etree":
        return "audio-tracks"
    if family == "librivox":
        return "audio-chapters"
    if family == "movies":
        return "video"
    t = first_value(mediatype).lower()
    return {"etree": "audio-tracks", "audio": "audio-tracks", "movies": "video", "texts": "documents",
            "image": "images"}.get(t, "files")


def playlist(item, kind, identifier=None, item_title=None):
    """ArchiveXT's playlist for a parsed item (a metadata-API dict)."""
    files = item.get("files") or []
    meta = item.get("metadata") or {}
    identifier = identifier or first_value(meta.get("identifier"))
    item_title = item_title if item_title is not None else first_value(meta.get("title"))
    if kind in ("auto", ""):
        kind = kind_for("", meta.get("mediatype")) if kind == "auto" else "files"
    groups, order = {}, []
    for idx, f in enumerate(files, start=1):
        if not ACCEPT[kind](f):
            continue
        key = group_key(f, kind)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append((idx, f))
    entries = []
    for key in order:
        members = groups[key]

        def sort_key(pair):
            idx, f = pair
            nm = str(f.get("name") or "").lower()
            if kind == "video":
                return (rank(f, kind), 999999999999 - min(_size(f), 999999999999), natural_key(nm))
            return (rank(f, kind), natural_key(nm))
        members = sorted(members, key=sort_key)
        best_idx, best = members[0]
        entry = {
            "name": best["name"], "format": str(best.get("format") or ""), "size": str(best.get("size") or ""),
            "url": download_url(identifier, best["name"]), "stem": key, "index": best_idx,
            "title": "", "track": None, "length": None, "quality": "", "variants": [],
        }
        for _, f in members:
            if not entry["title"]:
                t = first_value(f.get("title")).strip()
                if t:
                    entry["title"] = track_title_clean(t) if kind == "audio-tracks" else t
            if entry["track"] is None:
                entry["track"] = track_number(first_value(f.get("track")) or None)
            if entry["length"] is None:
                entry["length"] = duration_seconds(first_value(f.get("length")) or None)
            if kind == "video":
                entry["variants"].append((f["name"], quality_label(f["name"]), str(f.get("size") or ""),
                                          str(f.get("format") or "")))
        if not entry["title"]:
            if kind == "audio-tracks":
                entry["title"] = track_title_clean(pretty_name(best["name"])) or pretty_name(best["name"])
            elif kind == "video":
                entry["title"] = clean_title(best["name"], item_title)
            else:
                entry["title"] = pretty_name(best["name"])
        if kind == "video":
            entry["quality"] = quality_label(best["name"])
        entry["_rank"] = rank(best, kind)
        entries.append(entry)

    def order_key(e):
        nm = natural_key(e["name"])
        if kind == "audio-tracks":
            return (1, "", nm)
        if kind == "documents":
            return (1, str(e["_rank"]), nm)
        if e["track"] is None:
            return (1, "", nm)
        return (0, "%012d" % e["track"], nm)
    entries.sort(key=order_key)
    for e in entries:
        del e["_rank"]
    return {"kind": kind, "count": len(entries), "entries": entries}


# --------------------------------------------------------------- responses
def _lines(value):
    """A JSON scalar or array as ArchiveXT's line convention."""
    if value is None:
        return ""
    if isinstance(value, list):
        return "\n".join(_scalar(v) for v in value if not isinstance(v, (list, dict)))
    if isinstance(value, dict):
        return ""
    return _scalar(value)


def _scalar(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def search_parse(text):
    data = json.loads(text)
    if isinstance(data.get("error"), str):
        return None
    resp = data.get("response")
    if not isinstance(resp, dict) or not isinstance(resp.get("docs"), list):
        return None
    docs = []
    for d in resp["docs"]:
        docs.append({k: _lines(v) for k, v in d.items()})
    num = resp.get("numFound")
    return {"numFound": num if isinstance(num, int) else len(docs), "start": resp.get("start", 0) or 0,
            "count": len(docs), "docs": docs}


def item_parse(text):
    data = json.loads(text)
    if not isinstance(data.get("metadata"), dict):
        return None
    meta = {k: _lines(v) for k, v in data["metadata"].items()}
    files = [{k: _lines(v) for k, v in f.items()} for f in (data.get("files") or [])]
    return {"identifier": meta.get("identifier", "").split("\n")[0], "metadata": meta, "files": files,
            "filesCount": len(files), "itemSize": _scalar(data.get("item_size")),
            "server": _scalar(data.get("server")), "dir": _scalar(data.get("dir"))}


# ---------------------------------------------------------------- anchors
def _anchor():
    """The published vectors. A wrong oracle refuses to load."""
    A = []

    def eq(got, want, label):
        if got != want:
            A.append("%s: got %r want %r" % (label, got, want))

    # AudioBooks archive.test.mjs
    eq(sanitize("Title - Subtitle"), "Title Subtitle", "san1")
    eq(sanitize("austen -"), "austen", "san2")
    eq(sanitize("+"), "", "san3")
    eq(sanitize("!"), "", "san4")
    eq(sanitize("a &&"), "a", "san5")
    eq(sanitize("a || b"), "a b", "san6")
    eq(sanitize("-austen"), "-austen", "san7")
    eq(sanitize("austen AND AND dickens"), "austen AND dickens", "san8")
    eq(sanitize("(austen AND)"), "(austen)", "san9")
    eq(sanitize("()"), "", "san10")
    eq(sanitize("austen AND OR"), "austen", "san11")
    eq(sanitize("NOT austen"), "NOT austen", "san12")
    eq(sanitize("austen AND NOT dickens"), "austen NOT dickens", "san13")
    eq(sanitize("AND OR NOT"), "", "san14")
    eq(sanitize("year:[1800 TO 1850]", True), "year:[1800 TO 1850]", "san15")
    eq(sanitize("year:[1800 TO", True), "year: 1800 TO", "san16")
    eq(sanitize("title:emma~2 dickens^3", True), "title:emma~2 dickens^3", "san17")
    eq(sanitize("austen (("), "austen", "san18")
    eq(sanitize('"Pride and Prejudice'), "Pride and Prejudice", "san19")
    eq(sanitize('"Pride and Prejudice"'), '"Pride and Prejudice"', "san20")
    eq(sanitize("(austen OR dickens)"), "(austen OR dickens)", "san21")
    eq(sanitize("austen AND"), "austen", "san22")
    eq(sanitize("AND"), "", "san23")
    eq(sanitize("Pride and"), "Pride and", "san24")
    eq(sanitize("a[b]{c}\\d^e~f/g"), "a b c d e f g", "san25")
    eq(sanitize("   "), "", "san26")
    eq(sanitize("Dracula: Chapter 1"), "Dracula Chapter 1", "san27")
    eq(sanitize("Dracula: Chapter 1", True), "Dracula: Chapter 1", "san28")
    eq(build_query(base=LIBRIVOX_SCOPE, text="Dracula: Chapter 1", text_field="title"),
       "collection:(librivoxaudio) AND title:(Dracula Chapter 1)", "bq1")
    eq(build_query(base=LIBRIVOX_SCOPE, text="creator:austen AND title:emma", field_syntax=True),
       "collection:(librivoxaudio) AND (creator:austen AND title:emma)", "bq2")
    eq(build_query(base=LIBRIVOX_SCOPE, text="year:[1800 TO 1850]", field_syntax=True),
       "collection:(librivoxaudio) AND (year:[1800 TO 1850])", "bq3")
    eq(build_query(base=LIBRIVOX_SCOPE, year_from="1900"), "collection:(librivoxaudio) AND year:[1900 TO *]", "bq4")
    eq(build_query(base=LIBRIVOX_SCOPE, year_to="1950"), "collection:(librivoxaudio) AND year:[* TO 1950]", "bq5")
    eq(build_query(base=LIBRIVOX_SCOPE, year_from="1950", year_to="1900"),
       "collection:(librivoxaudio) AND year:[1900 TO 1950]", "bq6")
    eq(build_query(base=LIBRIVOX_SCOPE, text="Jane Austen", text_field="creator"),
       "collection:(librivoxaudio) AND creator:(Jane Austen)", "bq7")
    eq(build_query(base=LIBRIVOX_SCOPE + " AND subject:(romance)", text="emma",
                   filters=["subject:(solo)", "language:(English)"]),
       "collection:(librivoxaudio) AND subject:(romance) AND (emma) AND subject:(solo) AND language:(English)", "bq8")
    eq(preset_spec_query("librivox", "Romance", "emma", "", "", ("solo", "english", "bogus")),
       "collection:(librivoxaudio) AND subject:(romance) AND (emma) AND subject:(solo) AND language:(English)", "bq9")
    eq(normalize_year("1900"), "1900", "ny1")
    eq(normalize_year(" 2024 "), "2024", "ny2")
    eq(normalize_year(""), "", "ny3")
    eq(normalize_year("19"), "", "ny4")
    eq(normalize_year("abcd"), "", "ny5")
    eq(search_url('collection:(librivoxaudio) AND (a "b")',
                  "identifier,title,year,creator,date,language,runtime,subject", "downloads desc", 24, 2),
       "https://archive.org/advancedsearch.php?q=collection%3A%28librivoxaudio%29+AND+%28a+%22b%22%29"
       "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=year&fl%5B%5D=creator&fl%5B%5D=date&fl%5B%5D=language"
       "&fl%5B%5D=runtime&fl%5B%5D=subject&sort%5B%5D=downloads+desc&rows=24&page=2&output=json", "url1")
    eq(metadata_url("abc"), "https://archive.org/metadata/abc", "url2")
    eq(download_url("abc", "a b#1.mp3"), "https://archive.org/download/abc/a%20b%231.mp3", "url3")
    eq(download_url("abc", "dir/one.mp3"), "https://archive.org/download/abc/dir/one.mp3", "url4")
    eq(thumbnail_url("abc"), "https://archive.org/services/img/abc", "url5")
    for good in ("pride_and_prejudice_librivox", "a.b-c_1"):
        eq(identifier_valid(good), True, "id " + good)
    for bad in ("", "../etc", "x y", "<script>"):
        eq(identifier_valid(bad), False, "id " + bad)
    eq(track_number("01"), 1, "tn1")
    eq(track_number("4/5"), 4, "tn2")
    eq(track_number(7), 7, "tn3")
    eq(track_number(None), None, "tn4")
    eq(track_number("n/a"), None, "tn5")
    eq(duration_seconds("600.12"), 600.12, "dur1")
    eq(duration_seconds("12:34"), 754, "dur2")
    eq(duration_seconds("1:02:03"), 3723, "dur3")
    eq(duration_seconds(""), None, "dur4")
    eq(duration_seconds("1:02:03.5"), 3723.5, "dur5")
    eq(duration_seconds("abc"), None, "dur6")
    eq(file_stem("pp_01_austen_64kb.mp3"), "pp_01_austen", "stem1")
    eq(file_stem("pp_01_austen.ogg"), "pp_01_austen", "stem2")
    eq(file_stem("PP_01_austen_VBR.mp3"), "pp_01_austen", "stem3")
    eq(pretty_name("pp_01_austen_64kb.mp3"), "pp 01 austen", "pretty1")
    eq(pretty_name("dir/sub_ch_01_vbr.mp3"), "sub ch 01", "pretty2")
    eq(is_audio({"name": "a_64kb.mp3", "format": "64Kbps MP3"}), True, "aud1")
    eq(is_audio({"name": "a.ogg", "format": "Ogg Vorbis"}), True, "aud2")
    eq(is_audio({"name": "a.mp3"}), True, "aud3")
    eq(is_audio({"name": "a_64kb_mp3.zip", "format": "64Kbps MP3 ZIP"}), False, "aud4")
    eq(is_audio({"name": "a_64kb.m3u", "format": "64Kbps M3U"}), False, "aud5")
    eq(is_audio({"name": "a_spectrogram.png", "format": "Spectrogram"}), False, "aud6")
    eq(is_audio({"name": "a_meta.xml", "format": "Metadata"}), False, "aud7")
    eq(is_audio({"name": "a.mp3", "format": "Metadata"}), False, "aud8")
    eq(is_audio({"format": "VBR MP3"}), False, "aud9")

    def chapter(n, old_style=False):
        base = "pp_0%d_austen" % n
        original = base + ("_128kb.mp3" if old_style else "_64kb.mp3")
        files = []
        if old_style:
            files.append({"name": base + "_128kb.mp3", "source": "original", "format": "128Kbps MP3",
                          "title": "Chapter %d" % n, "track": str(n), "length": "600"})
            files.append({"name": base + "_64kb.mp3", "source": "derivative", "original": original,
                          "format": "64Kbps MP3", "length": "600"})
        else:
            files.append({"name": base + "_64kb.mp3", "source": "original", "format": "64Kbps MP3",
                          "title": "Chapter %d" % n, "track": str(n), "length": "600"})
        files.append({"name": base + ".ogg", "source": "derivative", "original": original, "format": "Ogg Vorbis", "length": "600"})
        files.append({"name": base + "_spectrogram.png", "source": "derivative", "original": original, "format": "Spectrogram"})
        files.append({"name": base + ".png", "source": "derivative", "original": original, "format": "PNG"})
        return files
    files = chapter(3) + chapter(1) + chapter(5, True) + chapter(2) + chapter(4, True) + [
        {"name": "x_meta.xml", "source": "original", "format": "Metadata"},
        {"name": "x_64kb_mp3.zip", "source": "derivative", "format": "64Kbps MP3 ZIP"},
        {"name": "x.jpg", "source": "original", "format": "JPEG"}]
    pl = playlist({"files": files, "metadata": {"identifier": "x"}}, "audio-chapters")
    eq([e["track"] for e in pl["entries"]], [1, 2, 3, 4, 5], "sel1 tracks")
    eq([e["title"] for e in pl["entries"]], ["Chapter %d" % i for i in range(1, 6)], "sel1 titles")
    eq([e["name"] for e in pl["entries"]], ["pp_01_austen_64kb.mp3", "pp_02_austen_64kb.mp3", "pp_03_austen_64kb.mp3",
                                            "pp_04_austen_128kb.mp3", "pp_05_austen_128kb.mp3"], "sel1 names")
    eq(pl["entries"][0]["length"], 600, "sel1 length")
    pl = playlist({"files": [{"name": "b_part2.ogg", "format": "Ogg Vorbis", "source": "original"},
                             {"name": "b_part10.ogg", "format": "Ogg Vorbis", "source": "original"},
                             {"name": "b_part1.ogg", "format": "Ogg Vorbis", "source": "original"}],
                   "metadata": {"identifier": "b"}}, "audio-chapters")
    eq([e["name"] for e in pl["entries"]], ["b_part1.ogg", "b_part2.ogg", "b_part10.ogg"], "sel2 names")
    eq([e["title"] for e in pl["entries"]], ["b part1", "b part2", "b part10"], "sel2 titles")
    eq(playlist({"files": [{"name": "only.zip", "format": "ZIP"}], "metadata": {"identifier": "z"}},
                "audio-chapters")["count"], 0, "sel3")
    pl = playlist({"files": [{"name": "c_01_64kb.mp3", "source": "original", "format": "64Kbps MP3", "title": "One", "track": "1"},
                             {"name": "c_01.ogg", "source": "derivative", "original": "c_01_64kb.mp3", "format": "Ogg Vorbis"},
                             {"name": "c_02.ogg", "source": "derivative", "original": "c_02_64kb.mp3", "format": "Ogg Vorbis"}],
                   "metadata": {"identifier": "c"}}, "audio-chapters")
    eq([(e["name"], e["title"], e["track"]) for e in pl["entries"]],
       [("c_01_64kb.mp3", "One", 1), ("c_02.ogg", "c 02", None)], "sel4")
    eq(subject_tags(["Fiction", "Romance", "Audiobook", "A very long subject name that exceeds twenty characters"]),
       ["Fiction", "Romance"], "tags1")
    eq(subject_tags("librivox; audiobooks; literature; ghost stories"), ["Ghost stories"], "tags2")
    eq(subject_tags(["fiction", "Fiction", "poetry"]), ["Fiction", "Poetry"], "tags3")
    eq(subject_tags(None), [], "tags4")
    eq(subject_tags(["x" * 20]), [], "tags5")
    # AudioBooks utils.test.mjs
    for sec, want in ((0, "0:00"), (65, "1:05"), (3599.9, "59:59"), (3600, "1:00:00"), (45296, "12:34:56"),
                      (float("nan"), "0:00"), (-5, "0:00"), (None, "0:00")):
        eq(format_time(sec), want, "ft %r" % (sec,))
    # the tape finder's formatTime (same shape, its own numbers)
    eq(format_time(225), "3:45", "tf1")
    eq(format_time(5025), "1:23:45", "tf2")
    # the film club's helpers
    eq(format_bytes(80000000), "76.29 MB", "fb1")
    eq(format_bytes(20000000), "19.07 MB", "fb2")
    eq(format_bytes(1024), "1 KB", "fb3")
    eq(format_bytes(0), "", "fb4")
    eq(format_bytes(-3), "", "fb5")
    eq(video_stem("episode_archive_h264.mp4"), "episode", "vs1")
    eq(video_stem("Show_E01_512kb.mp4"), video_stem("Show_E01.mp4"), "vs2")
    eq(clean_title("Show_E01.mp4", "Show"), "E01", "ct1")
    eq(clean_title("", "Show"), "Untitled", "ct2")
    eq(quality_label("Show_E01_512kb.mp4"), "SD", "ql1")
    eq(quality_label("film_1080p.mp4"), "1080p", "ql2")
    eq(video_scope().startswith("(mediatype:(movies OR video OR television) OR (mediatype:collection AND identifier:(feature_films OR adviews"), True, "scope")
    # the film club browser fixture: 3 episodes with 512kb variants collapse to one entry each, the 80 MB mp4 winning
    series = []
    for i in range(1, 4):
        n = "%02d" % i
        series.append({"name": "Show_E%s_512kb.mp4" % n, "format": "512Kb MPEG4", "size": "20000000", "length": "600"})
        series.append({"name": "Show_E%s.mp4" % n, "format": "h.264", "size": "80000000", "length": "600"})
    pl = playlist({"files": series, "metadata": {"identifier": "show", "title": "Show"}}, "video")
    eq(pl["count"], 3, "series count")
    eq([e["name"] for e in pl["entries"]], ["Show_E01.mp4", "Show_E02.mp4", "Show_E03.mp4"], "series best")
    eq(len(pl["entries"][0]["variants"]), 2, "series variants")
    # the tape finder's regexes
    eq(track_title_clean("d1t01 Scarlet_Begonias"), "Scarlet Begonias", "ttc1")
    eq(track_title_clean("T03-Fire_On_The_Mountain"), "Fire On The Mountain", "ttc2")
    eq(year_of("1977-05-08T00:00:00Z"), "1977", "yo1")
    eq(year_of("77-05-08"), "", "yo2")
    if A:
        raise SystemExit("archive_reference.py failed its own anchors:\n  " + "\n  ".join(A))


_anchor()
