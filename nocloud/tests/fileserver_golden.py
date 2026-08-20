#!/usr/bin/env python3
"""fileserver_golden.py - pure-Python reference for the security- and
correctness-critical logic of No Cloud Quick Share's web server (the browsable
directory page, HTTP range, MIME, request framing, dotfile guard, and the editor
path-confinement linchpin), in src/nocloudquickshare.livecodescript.

OXT cannot compile/run .livecodescript headlessly, so this PINS the parts of the
web server that are verifiable off-engine: the HTTP byte-range parser, the
path-traversal decision, the MIME mapping, and the HTML escaper. If this and the
.livecodescript ever disagree, one of them is wrong.

Mirrors these LiveCodeScript handlers, grouped by surface. This index is the
AUTHORITATIVE list (CONTRIBUTING.md points here instead of keeping its own
copy: by 2026-08-15 both enumerations had drifted stale - the guide's table
named 16 rows, this docstring 13, while the file defined 33 mirrors). A new
mirror is not done until it is listed here, next to its group.

Static file serving (both transports):
  qsFsParseRange  -> parse_range()      (RFC 7233 single-range; 416 on out-of-range)
  qsFsServePath   -> traversal_ok()     (".." refused after urlDecode + \\ -> /)
  qsHasDotSegment -> has_dot_segment()  (dotfile guard: .git/.env invisible to serving)
  qsFsMime        -> mime()
  qsFsIcon        -> fs_icon()          (directory-listing icon/colour type token)
  qsFsHtmlEscape  -> html_escape()
  qsFileSizeSeek  -> file_size_probe()  (O(log n) file-size probe)
  qsSafeFilename  -> safe_filename()    (Content-Disposition filename sanitiser)
  qsSiteSpaTarget -> spa_is_route()     (SPA fallback: a route vs a missing asset)
  qsCwServe       -> capability_route() (clearweb: the /<token>/ capability gate)

HTTP framing, headers, and conditional GET:
  qsHttpHeaderEnd -> http_header_end()  (byte index of the CRLFCRLF head terminator)
  qsHttpReqComplete -> http_req_complete() (head + Content-Length body received?)
  qsHttpReqLength -> http_req_length()  (one request's exact byte length; keep-alive trim)
  qsJsonEscape    -> json_escape()      (the /_qs/info route's JSON value escaping)
  qsHttpDate      -> http_date()        (+ its qsIsLeapYear/qsMonthLength/qsPad2 helpers)
  qsHttpAllow     -> http_allow()       (the Allow header value for a path)
  qsCorsPreflight -> cors_preflight()   (the OPTIONS preflight header block)
  qsHttpWeakETag  -> http_weak_etag()   (the weak validator, W/"size-seed-gen")
  qsETagCore      -> etag_core()        (RFC weak-comparison core of one ETag token)
  qsIfNoneMatch   -> if_none_match()    (the 304 decision)
  qsHttpExtraHeaders -> http_extra_headers() (the always-sent header block; Date epoch injected)
  qsFsLeaf        -> fs_leaf()          (last path segment - the disposition filename)
  qsHttpDisposition -> http_disposition() (inline vs ?dl attachment Content-Disposition)
  qsHttpFileHead  -> http_file_head()   (the ONE 304/416/200/206 file-head plan both
                                         transport twins call - the Phase 2 dedup)
  qsFsSendText / qsCwSendText -> http_text_response() (the one-shot text reply both
                                         transports send; a HEAD keeps the GET's
                                         Content-Length and sends no body)

The web editor (the WRITE path):
  qsEditSafePath  -> edit_safe_path()   (write-path confinement - THE linchpin)
  qsEditIsLocal   -> edit_is_local()    (LAN-first gate - the other linchpin; + qsIsPrivateIp)
  qsEditParentDirs -> edit_parent_dirs() (the folder chain a write must create first)
  qsEditLoginWait -> edit_login_wait()  (login brute-force backoff)
  qsQueryParam    -> query_param()      (editor read/write ?path= extraction)

User-declared routes (.qsroutes.json):
  qsHttpReservedPath -> reserved_path() (/_qs and /_edit belong to the route layer: no user
                                         route declares one, no pattern matches one, and the
                                         static pipeline refuses one)
  qsUserPathValid -> user_path_valid()  (absolute, traversal-free; /_qs and /_edit reserved)
  qsSanitizeHeaderName  -> sanitize_header_name()  (letters/digits/hyphen only)
  qsSanitizeHeaderValue -> sanitize_header_value() (CR/LF/control bytes dropped)
  qsRenderTemplate -> render_template() (bounded {{...}} substitution in a route body)
  qsTemplateValue  -> template_value()  (deterministic tokens; clock tokens empty here)
  qsTemplateEscape -> template_escape() (default-deny: json types JSON, all else HTML)
  qsMountLocation -> mount_location()   (redirect Location re-based onto the /<token>/ mount)
  qsRouteKeyPath   -> route_key_path()  (the path half of a "METHOD /path" key)
  qsRouteLookupKey -> route_lookup_key() (the key a request LOOKS UP: a HEAD falls back to
                                         the GET route, else it missed the table entirely
                                         and the SPA fallback answered it)
  qsRouteHasParams -> route_has_params() (exact key vs :param pattern - the one test)
  qsRouteParamCount -> route_param_count() (specificity rank: fewest params = most literal)
  qsUserPatternValid -> user_pattern_valid() (the :param declaration gate: static FIRST
                                         segment, [A-Za-z0-9_] names, no duplicates)
  qsRouteMatch     -> route_match()     (segment matcher + the reserved-path backstop)
  qsUserRouteFind  -> user_route_find() (deterministic pattern pick for one request)

Transfers-row formatting:
  qsRateShort     -> rate_short()
  qsEtaShort      -> eta_short()

    python3 tests/fileserver_golden.py     # exit 0 = OK, 1 = mismatch
"""
import sys
from email.utils import formatdate
from urllib.parse import unquote, unquote_plus

_fail = []


def check(name, got, want):
    if got != want:
        _fail.append("%s:\n    got  %r\n    want %r" % (name, got, want))


# ---- fsParseRange: single HTTP byte-range against a known total -------------
# Returns "start,end" (inclusive, 0-based), "" (no/ignored range -> whole file),
# or "unsatisfiable" (valid syntax, out of bounds -> 416). Only ONE range is
# honoured; a multi-range (comma) request falls back to the whole file.

def _is_int(s):
    # LiveCode "X is an integer": an optional sign then digits, no decimal point.
    if s == "":
        return False
    try:
        int(s)
    except ValueError:
        return False
    return "." not in s and "e" not in s.lower()


def _item(s, idx):
    """LiveCode `item idx of s` with itemDelimiter '-' (1-based; missing -> "")."""
    parts = s.split("-")
    return parts[idx - 1] if idx - 1 < len(parts) else ""


def parse_range(rng, total):
    if rng == "":
        return ""
    if not rng.startswith("bytes="):
        return ""
    spec = rng[6:]                      # char 7 to -1 of pRange
    if "," in spec:
        return ""                       # multi-range: serve the whole file
    start, end = _item(spec, 1), _item(spec, 2)
    if start == "":
        # suffix range "bytes=-N": the last N bytes
        if end == "" or not _is_int(end):
            return "unsatisfiable"
        start = total - int(end)
        if start < 0:
            start = 0
        end = total - 1
    else:
        if not _is_int(start):
            return "unsatisfiable"
        start = int(start)
        if end == "":
            end = total - 1
        elif not _is_int(end):
            return "unsatisfiable"
        else:
            end = int(end)
    if start > end or start < 0 or start >= total:
        return "unsatisfiable"
    if end >= total:
        end = total - 1
    return "%d,%d" % (start, end)


# ---- fsServePath traversal guard: urlDecode, \ -> /, refuse ".." ------------

def traversal_ok(raw_path):
    """True if the request is allowed to touch disk; False -> 403. Mirrors the
    order in fsServePath: urlDecode, empty -> '/', backslashes -> '/', then the
    literal '..' substring test (intentionally strict, matching OnionXT)."""
    path = unquote(raw_path)
    if path == "":
        path = "/"
    path = path.replace("\\", "/")
    return ".." not in path


# ---- qsHasDotSegment: the static-path dotfile guard (round 5) ----------------
# Any "/"-separated segment starting with "." makes the path invisible to the
# static pipelines (listing + serving, both transports): a shared website
# folder must never leak .git / .env over an anonymous link. Mirrors
# qsHasDotSegment: split on "/", skip empty segments, test the first char.

def has_dot_segment(path):
    return any(seg.startswith(".") for seg in path.split("/") if seg)


# ---- fsMime -----------------------------------------------------------------

_MIME = {
    "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
    "css": "text/css; charset=utf-8", "js": "application/javascript; charset=utf-8",
    "json": "application/json; charset=utf-8",
    "txt": "text/plain; charset=utf-8", "md": "text/plain; charset=utf-8",
    "log": "text/plain; charset=utf-8",
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
    "ico": "image/x-icon", "pdf": "application/pdf",
    "mp4": "video/mp4", "m4v": "video/mp4", "webm": "video/webm",
    "mp3": "audio/mpeg", "ogg": "audio/ogg", "oga": "audio/ogg", "wav": "audio/wav",
    "zip": "application/zip",
    # web-app essentials
    "wasm": "application/wasm", "mjs": "application/javascript; charset=utf-8",
    "xml": "application/xml; charset=utf-8", "map": "application/json; charset=utf-8",
    "webmanifest": "application/manifest+json",
    "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
    "eot": "application/vnd.ms-fontobject", "avif": "image/avif",
    "csv": "text/csv; charset=utf-8",
    # extended media / data types
    "flac": "audio/flac", "m4a": "audio/mp4", "aac": "audio/aac",
    "opus": "audio/ogg", "weba": "audio/webm", "ogv": "video/ogg",
    "mov": "video/quicktime", "mkv": "video/x-matroska", "avi": "video/x-msvideo",
    "bmp": "image/bmp", "heic": "image/heic", "heif": "image/heif",
    "apng": "image/apng", "tiff": "image/tiff", "tif": "image/tiff",
    "ics": "text/calendar; charset=utf-8", "vtt": "text/vtt; charset=utf-8",
    "yaml": "application/yaml; charset=utf-8", "yml": "application/yaml; charset=utf-8",
}


def mime(path):
    # LiveCode: the last item of pPath with itemDelimiter "." (a name with no dot
    # is its own last item -> unknown -> octet-stream).
    extn = path.split(".")[-1].lower()
    return _MIME.get(extn, "application/octet-stream")


# ---- qsFsIcon: directory-listing icon/colour type token ---------------------
# Groups a filename (or folder) into one of dir/img/vid/aud/code/doc/zip/pdf/file for
# the listing's per-row icon. Same extension-family idea as mime(); mirrors qsFsIcon.

_ICON = {
    "img": "png jpg jpeg gif webp svg ico avif bmp heic",
    "vid": "mp4 m4v webm mov mkv avi",
    "aud": "mp3 ogg oga wav flac m4a aac",
    "code": "html htm css js mjs json xml yml yaml wasm map ts tsx jsx py rb go rs c h cpp sh",
    "doc": "txt md log csv doc docx rtf odt",
    "zip": "zip tar gz tgz rar 7z bz2 xz",
    "pdf": "pdf",
}


def fs_icon(name, is_dir):
    if is_dir:
        return "dir"
    extn = name.split(".")[-1].lower()
    for token, exts in _ICON.items():
        if extn in exts.split():
            return token
    return "file"


# ---- qsFileSizeSeek: O(log n) file-size probe --------------------------------
# Instead of reading a whole file to size it (a UI-freezing, disk-doubling full read),
# find EOF by exponential-then-binary search over `seek to N; read 1`. readable(N) means
# "a byte exists at 0-based offset N" (N < size); the size is the smallest non-readable
# offset. Returns None (-> fall back to the linear count) if it exceeds the 8 GiB serve
# cap. This mirrors qsFileSizeSeek's control flow EXACTLY so the algorithm is pinned; the
# only on-engine unknown (seek-past-EOF returning empty) is guarded by the fallback.

def file_size_probe(size, cap=8589934592):
    def readable(n):
        return n < size
    if not readable(0):
        return 0                                  # empty file
    lo, hi = 0, 1
    while True:
        if hi > cap:
            return None                           # too big / no EOF: caller falls back
        if not readable(hi):
            break                                 # hi is an upper bound (not readable)
        lo, hi = hi, hi * 2
    while (hi - lo) > 1:
        mid = (lo + hi) // 2
        if readable(mid):
            lo = mid
        else:
            hi = mid
    return hi


# ---- qsSafeFilename: Content-Disposition filename sanitiser ------------------
# Printable ASCII only, minus quote and backslash, so the name is safe inside a
# quoted-string without RFC 5987 encoding. Empty -> "download". Mirrors qsSafeFilename.

def safe_filename(name):
    out = "".join(c for c in name if 32 <= ord(c) <= 126 and c not in '"\\')
    return out if out else "download"


# ---- qsRateShort / qsEtaShort: compact Transfers-row stats -------------------
# Compact data-rate ("1.2M/s") and ETA ("1h2m") strings that fit the narrow progress
# column. Mirror qsRateShort / qsEtaShort. _round1 reproduces LiveCode's
# `the round of (v*10)/10` (round half away from zero, number formatted with no .0).

def _round1(v):
    import math
    x = v * 10.0
    r = (math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)) / 10.0
    return "%g" % r


def rate_short(bps):
    if isinstance(bps, bool) or not isinstance(bps, (int, float)) or bps <= 0:
        return "0B/s"
    units = ["B", "K", "M", "G", "T"]
    v, u = float(bps), 0
    while v >= 1024 and u < len(units) - 1:
        v /= 1024
        u += 1
    return _round1(v) + units[u] + "/s"


def eta_short(secs):
    if isinstance(secs, bool) or not isinstance(secs, (int, float)) or secs < 0:
        return ""
    s = int(secs)                                  # trunc toward zero (LiveCode trunc)
    if s < 60:
        return "%ds" % s
    if s < 3600:
        return "%dm" % (s // 60)
    if s < 86400:
        return "%dh%dm" % (s // 3600, (s % 3600) // 60)
    return ">1d"


# ---- fsHtmlEscape: & first, then the rest -----------------------------------

def html_escape(text):
    out = text.replace("&", "&amp;")
    out = out.replace("<", "&lt;")
    out = out.replace(">", "&gt;")
    out = out.replace('"', "&quot;")
    out = out.replace("'", "&#39;")
    return out


# ---- qsSiteSpaTarget: the SPA route-vs-asset heuristic ----------------------

# ---- the light HTTP backend: request framing + JSON escaping ----------------

def http_header_end(data):
    """1-based byte index of the first CR of the CRLFCRLF that ends the header block,
    or 0 if not fully received. Mirrors qsHttpHeaderEnd (a byte scan)."""
    i = data.find(b"\r\n\r\n")
    return 0 if i < 0 else i + 1


# ---- qsHttpParseHead, mirrored properly ------------------------------------
# THE STAND-IN THIS REPLACES WAS WRONG, and wrong on the input the whole
# exercise is about. It scanned for a Content-Length and RETURNED ON THE FIRST
# one; qsHttpParseHead does `put tValue into tOut[tName]` unconditionally, so
# the LAST one wins. On `Content-Length: 5` followed by `Content-Length: 10`
# the server frames 10 and this file said 5 - a mirror disagreeing with the
# thing it mirrors, about request smuggling's classic lever, in the file whose
# job is to pin that framing.
#
# It also modelled none of the parser's other decisions, so none of them could
# be tested: the __dupcl conflict flag the 400-refusals read, and the refusal
# to let a client header shadow the "__" pseudo-field namespace.
def parse_head(head_bytes):
    """Mirror qsHttpParseHead: lowercased header names -> values, plus the
    synthetic __method / __path / __query / __resource and the __dupcl flag."""
    text = head_bytes.decode("utf-8", "replace")
    lines = text.split("\r\n")
    out = {}
    req = lines[0] if lines else ""
    words = req.split()
    out["__method"] = words[0] if words else ""
    out["__resource"] = words[1] if len(words) > 1 else ""
    res = out["__resource"]
    out["__path"] = res.split("?", 1)[0]
    out["__query"] = res.split("?", 1)[1] if "?" in res else ""
    for line in lines[1:]:
        if not line:
            continue
        name, sep, val = line.partition(":")
        if not sep or not name.strip():
            continue
        nm = name.strip().lower()
        v = val.strip()
        # "__" is the reserved pseudo-field namespace; a client may not shadow it
        if nm.startswith("__"):
            continue
        # a CONFLICTING duplicate Content-Length is the smuggling lever: flag it
        # and let the serve handlers answer 400. An identical repeat is not a
        # conflict and must NOT set the flag.
        if nm == "content-length" and out.get(nm) not in (None, "") and out[nm] != v:
            out["__dupcl"] = "true"
        out[nm] = v                       # LAST wins, exactly as the engine does
    return out


def _content_length(head_bytes):
    """The declared body length, or None when there is none or it is unusable."""
    v = parse_head(head_bytes).get("content-length")
    if v is None:
        return None
    try:
        return int(v) if "." not in v else None
    except ValueError:
        return None


def http_req_complete(data):
    """Mirror qsHttpReqComplete: the head plus (if a Content-Length is declared) the
    whole body must be present. A non-integer/absent Content-Length means no body."""
    he = http_header_end(data)
    if he == 0:
        return False
    cl = _content_length(data[:he - 1])          # byte 1..headEnd-1
    if cl is None:
        return True
    body_start = he + 4                           # 1-based, just past CRLFCRLF
    have = len(data) - body_start + 1
    return have >= cl


def http_req_length(data):
    """Mirror qsHttpReqLength: exact byte length of ONE complete request at the front of
    `data` = head-with-CRLFCRLF (headEnd + 3 bytes) + Content-Length body. 0 if the head
    is not yet complete. Keep-alive trims this many bytes to leave any pipelined bytes."""
    he = http_header_end(data)
    if he == 0:
        return 0
    cl = _content_length(data[:he - 1])
    if cl is None or cl < 0:
        cl = 0
    return he + 3 + cl


def json_escape(s):
    """Mirror qsJsonEscape: backslash first, then quote, CR, LF, tab."""
    out = s.replace("\\", "\\\\")
    out = out.replace('"', '\\"')
    out = out.replace("\r", "\\r")
    out = out.replace("\n", "\\n")
    out = out.replace("\t", "\\t")
    return out


# ---- qsEditSafePath: the web-EDITOR write-path confinement (THE linchpin) ----
# The editor can WRITE, so a traversal here = arbitrary file overwrite. This must
# resolve a caller-supplied relative path to an absolute path GUARANTEED inside the
# served root, or reject (""). It is intentionally over-cautious: ANY ".." or ":"
# anywhere, any control char, rejects the whole path (so a rare filename containing
# ".." is refused - a safe trade for the write path). Mirrors qsEditSafePath.

def edit_safe_path(root, rel):
    r = rel.replace("\\", "/")
    if ".." in r:
        return ""
    if ":" in r:                                  # drive letter or URL scheme
        return ""
    if any(ord(c) < 32 for c in r):               # NUL / control chars
        return ""
    out = []
    for seg in r.split("/"):
        if seg == "" or seg == ".":
            continue
        if seg == "..":
            return ""
        out.append(seg)
    if not out:
        return ""
    return root + "/" + "/".join(out)


# ---- qsEditParentDirs: the folder chain an editor write must create first -------
# "a/b/c.png" -> ["a", "a/b"]; a root-level file -> []. Trailing "/" stripped so a
# folder-ish input can't make its own leaf a folder. Only ever called on a path that
# edit_safe_path already accepted. Mirrors qsEditParentDirs.

def edit_parent_dirs(rel):
    r = rel.replace("\\", "/")
    clean = [seg for seg in r.split("/") if seg != "" and seg != "."]
    out, cur = [], ""
    for i, seg in enumerate(clean):
        if i == len(clean) - 1:
            break                                 # the last real segment is the file itself
        cur = seg if not cur else cur + "/" + seg
        out.append(cur)
    return out


# ---- qsEditIsLocal: the LAN-first gate (the editor's OTHER linchpin) ---------
# The web editor may only be reached from the local network. The ONLY trustworthy
# signal is the accepted-socket peer address the engine gives us (a remote client
# cannot forge it across a TCP handshake) - never a request header. Tor (ox:) is
# always remote. Mirrors qsEditIsLocal + qsIsPrivateIp.

def _edit_local_ip(ip):
    # STRICTER than qsIsPrivateIp: loopback + RFC-1918 + link-local ONLY. Carrier-NAT
    # (100.64/10) is the ISP's shared space, not the home LAN, so it is NOT local here.
    parts = ip.split(".")
    a = parts[0] if len(parts) >= 1 else ""
    b = parts[1] if len(parts) >= 2 else ""
    if not a.lstrip("-").isdigit():                # LiveCode "tA is not a number"
        return False
    a = int(a)
    bn = int(b) if b.lstrip("-").isdigit() else None
    if a == 10 or a == 127:
        return True
    if a == 192 and bn == 168:
        return True
    if a == 169 and bn == 254:
        return True
    if a == 172 and bn is not None and 16 <= bn <= 31:
        return True
    return False


def edit_is_local(conn):
    kind = conn[:3]
    if kind != "cw:":                              # Tor (ox:) / anything else: remote
        return False
    cid = conn[3:]
    if cid.startswith("::1"):                       # IPv6 loopback "::1:<port>"
        return True
    ip = cid.split(":")[0]                          # "<ip>:<port>[|n]" -> the ip
    return _edit_local_ip(ip)


# ---- qsQueryParam: one URL-decoded query value ------------------------------
# Splits on '&' then '=' (first match wins); a value may itself contain '='. NOTE
# LiveCode's urlDecode form-decodes '+' to a space (it is the inverse of urlEncode),
# so the faithful Python mirror is unquote_plus, NOT unquote. (The editor's JS client
# sends paths via encodeURIComponent, which emits '%2B' for a literal '+' and '%20'
# for a space, so a real filename still round-trips; the '+'->space rule only bites a
# hand-crafted URL.) The '+' handling cannot synthesise '..'/':' so it is traversal-neutral.

def query_param(query, name):
    if query == "":
        return ""
    for pair in query.split("&"):
        items = pair.split("=")
        if items[0] == name:
            return unquote_plus("=".join(items[1:])) if len(items) >= 2 else ""
    return ""


def spa_is_route(rel_path):
    """Mirror qsSiteSpaTarget's route-vs-asset heuristic (the part independent of the
    filesystem): the last '/' segment with NO '.' looks like a client-side route (fall
    back to index.html); a segment WITH a '.' looks like a missing asset (real 404).
    The caller separately requires a root index.html to exist before falling back."""
    leaf = rel_path.replace("\\", "/").split("/")[-1]
    return "." not in leaf


# ---- qsCwServe: the clearweb /<token>/ capability gate ----------------------
# The first path segment must equal the share's random token, else 404 (an open
# port must not be an open directory). The rest of the path is folder-relative.

def capability_route(decoded_path, token):
    """Returns 'forbidden' (.. present), or (matches, rest) where matches is
    whether the token segment equals `token` and rest is the folder-relative path
    (leading '/'). Mirrors qsCwServe: replace \\ -> /, refuse '..', then split on
    '/' with item 2 the token and item 3..-1 the rest."""
    p = decoded_path.replace("\\", "/")
    if ".." in p:
        return "forbidden"
    items = p.split("/")                 # "/tok/a/b" -> ["", "tok", "a", "b"]
    tok = items[1] if len(items) >= 2 else ""
    rest = "/" + "/".join(items[2:]) if len(items) >= 3 else "/"
    return (tok == token, rest)


# ---- qsHttpDate: epoch (UTC seconds) -> HTTP-date / IMF-fixdate --------------
# Pure integer date math, no timezone conversion (mirrors qsHttpDate + its helpers
# qsIsLeapYear/qsMonthLength/qsPad2). Empty for a negative/non-integer input. Validated
# below against the stdlib's email.utils.formatdate(usegmt=True).

def is_leap_year(y):
    if y % 4 != 0:
        return False
    if y % 100 == 0 and y % 400 != 0:
        return False
    return True


def month_length(m, leap):
    lens = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if m == 2 and leap:
        return 29
    return lens[m - 1]


def pad2(n):
    return ("0" + str(n))[-2:]


def http_date(epoch):
    if not isinstance(epoch, int) or epoch < 0:
        return ""
    days = epoch // 86400
    rem = epoch % 86400
    hour, minute, sec = rem // 3600, (rem % 3600) // 60, rem % 60
    dow = (days + 4) % 7          # 0=Sun ... 6=Sat (1970-01-01 = Thursday)
    wdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    year, leap = 1970, True
    while True:
        leap = is_leap_year(year)
        ylen = 366 if leap else 365
        if days < ylen:
            break
        days -= ylen
        year += 1
    mon = 1
    for i in range(1, 13):
        mlen = month_length(i, leap)
        if days < mlen:
            mon = i
            break
        days -= mlen
    day = days + 1
    return "%s, %s %s %d %s:%s:%s GMT" % (
        wdays[dow], pad2(day), mons[mon - 1], year,
        pad2(hour), pad2(minute), pad2(sec))


# ---- :param route patterns (Phase 3): key split, pattern test, matcher, picker ----
# A user route path may carry :param segments. The pieces mirror one property each and
# compose into the request-time walk: route_key_path splits a "METHOD /path" table key;
# route_has_params is the ONE exact-vs-pattern test (safe because user_pattern_valid
# refuses any param-shaped path it cannot store, so within the stored table the two are
# the same predicate); route_param_count ranks specificity; route_match extracts the
# captures; user_route_find arbitrates deterministically. Mirrors qsRouteKeyPath /
# qsRouteHasParams / qsRouteParamCount / qsUserPatternValid / qsRouteMatch /
# qsUserRouteFind.

def route_key_path(key):
    sp = key.find(" ")
    return "" if sp < 0 else key[sp + 1:]


def route_lookup_key(method, path, table_keys):
    """Mirror qsRouteLookupKey: the route-table key a request should LOOK UP, and the one
    place HEAD is turned back into GET. Every method looks up its own "METHOD /path" key; a
    HEAD looks up its own only when the table actually declares a HEAD route (an explicit
    one wins) and otherwise falls back to the GET key, because HEAD is GET-without-a-body
    and the server advertises it on every path (http_allow always lists it). Until
    2026-08-17 the key was built from the literal method, so a HEAD missed BOTH route tables
    and fell into the static pipeline - where the path has no file, its leaf has no ".", and
    spa_is_route() therefore said index.html: HEAD /_qs/info answered the SPA at 200
    text/html while GET /_qs/info answered JSON. `table_keys` is the key set of the table
    being consulted; both tables key the same way, so one lookup serves both."""
    method = method.upper()
    key = method + " " + path
    if method != "HEAD":
        return key
    # an EMPTY table (no .qsroutes.json loaded, or nothing shared) declares no HEAD route,
    # so it takes the same branch - the LCS guards that case explicitly because there the
    # table arrives unset rather than empty, and indexing a non-array is not a lookup
    if key in table_keys:
        return key
    return "GET " + path


def route_has_params(path):
    return any(seg.startswith(":") for seg in path.split("/"))


def route_param_count(path):
    return sum(1 for seg in path.split("/") if seg.startswith(":"))


def user_pattern_valid(path):
    """Declaration gate for a possibly-parameterised route path. A plain path defers to
    user_path_valid; a pattern must ALSO keep its FIRST segment static (a leading param
    would match into /_qs and /_edit - with it static, the reserved namespaces are
    unreachable by any stored pattern BY CONSTRUCTION), name every param [A-Za-z0-9_],
    and never reuse a name. Mirrors qsUserPatternValid."""
    if not user_path_valid(path):
        return False
    if not route_has_params(path):
        return True
    seen = set()
    for idx, seg in enumerate(path.split("/"), 1):
        if not seg.startswith(":"):
            continue
        if idx == 2:                 # item 1 is the empty text before the leading "/"
            return False             # -> the FIRST real segment must be static
        name = seg[1:]
        if name == "":
            return False
        for c in name:
            o = ord(c)
            if not ((48 <= o <= 57) or (65 <= o <= 90) or (97 <= o <= 122) or c == "_"):
                return False
        if name in seen:
            return False
        seen.add(name)
    return True


def route_match(pattern, path):
    """Match one STORED pattern against a decoded request path -> {name: value} or None.
    Segments compare pairwise; a :param captures exactly ONE nonempty segment (the request
    path was urlDecoded before routing, so an encoded %2F is already a real separator and
    splits - a param can never smuggle a slash). Trailing slash is significant, checked up
    front (which also keeps the engine's trailing-delimiter item counting and this split()
    in verdict agreement). BACKSTOP: never matches anything against a reserved request
    path - declaration makes such a pattern unstorable, so this pins the defense-in-depth
    line against a hostile pattern injected past declaration. Mirrors qsRouteMatch."""
    if reserved_path(path):
        return None
    if pattern.endswith("/") != path.endswith("/"):
        return None
    pat_segs = pattern.split("/")
    path_segs = path.split("/")
    if len(pat_segs) != len(path_segs):
        return None
    params = {}
    for pat, got in zip(pat_segs, path_segs):
        if pat.startswith(":"):
            if got == "":
                return None
            params[pat[1:]] = got
        elif pat != got:
            return None
    return params


def user_route_find(keys, method, path):
    """The stored pattern key that should serve method+path, or "". Exact keys are the
    caller's fast path and are SKIPPED here. Deterministic across matches: fewest params
    wins, ties broken by the smallest key (array iteration order is not a contract).
    Mirrors qsUserRouteFind (which walks the same keys off the live table)."""
    best_key, best_count = "", -1
    for k in keys:
        sp = k.find(" ")
        if sp < 0:
            continue
        if k[:sp] != method:
            continue
        rp = k[sp + 1:]
        if not route_has_params(rp):
            continue
        if route_match(rp, path) is None:
            continue
        count = route_param_count(rp)
        if best_key == "" or count < best_count or (count == best_count and k < best_key):
            best_key, best_count = k, count
    return best_key


# ---- qsHttpAllow: the Allow header value for a path --------------------------
# Static verbs GET/HEAD/OPTIONS plus any method registered for a route CLAIMING this
# path - built-in routes (always exact) and (when a root is shared) the folder's
# user-declared .qsroutes.json routes, where "claiming" is an exact key match OR a
# :param pattern that MATCHES the path (a param route's methods must never fall out of
# the OPTIONS/405 derivation) - in deterministic (sorted) order, de-duplicated. Both
# tables key on "METHOD /path". Mirrors qsHttpAllow(pPath, pRoot).

def http_allow(route_keys, path, user_keys=None):
    extras = set()
    for k in route_keys:
        if " " in k:
            m, p = k.split(" ", 1)
            if p == path and m not in ("GET", "HEAD", "OPTIONS"):
                extras.add(m)
    for k in (user_keys or []):
        if " " in k:
            m, p = k.split(" ", 1)
            claims = (p == path) or (route_has_params(p)
                                     and route_match(p, path) is not None)
            if claims and m not in ("GET", "HEAD", "OPTIONS"):
                extras.add(m)
    return ", ".join(["GET", "HEAD", "OPTIONS"] + sorted(extras))


# ---- qsCorsPreflight: the CORS header block for an OPTIONS preflight ----------
# Empty unless some user route CLAIMING `path` (exact, or a matching :param pattern -
# the same rule as http_allow, so the preflight promise holds identically for param
# routes) opted into cors; else the four Access-Control-* lines (Allow-Methods reuses
# the already-computed Allow value). `cors_keys` = the set of "METHOD /path" keys whose
# route set cors:true. Mirrors qsCorsPreflight.

def cors_preflight(cors_keys, path, allow):
    for k in cors_keys:
        if " " not in k:
            continue
        p = k.split(" ", 1)[1]
        if p == path or (route_has_params(p) and route_match(p, path) is not None):
            return ("Access-Control-Allow-Origin: *\r\n"
                    "Access-Control-Allow-Methods: " + allow + "\r\n"
                    "Access-Control-Allow-Headers: *\r\n"
                    "Access-Control-Max-Age: 600\r\n")
    return ""


# ---- conditional GET: the weak ETag + If-None-Match match ---------------------
# A file response carries W/"<size>-<seed>-<gen>" (no cheap per-file mtime on the engine, so the
# ETag changes on every signal the server CAN see: size, per-launch seed, edit generation). A
# non-Range request whose If-None-Match matches -> 304. Mirrors qsHttpWeakETag / qsETagCore /
# qsIfNoneMatch.

def http_weak_etag(size, seed, gen):
    return 'W/"%s-%s-%s"' % (size, seed, gen)


def etag_core(tag):
    out = tag.strip()
    if out[:2] == "W/":
        out = out[2:]
    out = out.strip()
    if out[:1] == '"':
        out = out[1:]
    if out[-1:] == '"':
        out = out[:-1]
    return out


def if_none_match(header, etag):
    if header == "":
        return False
    if header.strip() == "*":
        return True
    want = etag_core(etag)
    return any(etag_core(tok) == want for tok in header.split(","))


# ---- the shared file-response head plan (the deep-dive's Phase 2 dedup) -------
# qsFsServeFile (Tor) and qsCwServeFile (clearweb) used to each carry the whole
# conditional-GET + Range + head-assembly block; both now call ONE helper,
# qsHttpFileHead, and http_file_head() pins that branch once instead of two pasted
# copies being trusted twice. The LCS side reads the clock inside qsHttpExtraHeaders
# (`the seconds`); the mirror takes the epoch as a parameter so the vectors stay
# deterministic (the same convention as template_value's clock tokens).

def fs_leaf(path):
    """Mirror qsFsLeaf: the last '/'-segment of a path (backslashes normalised).
    A trailing '/' yields '' - LiveCode's `the last item` of "a/b/" is empty too."""
    return path.replace("\\", "/").split("/")[-1]


def http_disposition(formime, headers):
    """Mirror qsHttpDisposition: inline by default, attachment when the request
    carries a non-empty ?dl= value; the filename is the sanitised leaf."""
    kind = "attachment" if query_param(headers.get("__query", ""), "dl") != "" else "inline"
    return 'Content-Disposition: %s; filename="%s"\r\n' % (kind, safe_filename(fs_leaf(formime)))


def http_extra_headers(epoch):
    """Mirror qsHttpExtraHeaders: the header block on EVERYTHING served - Server, Date
    (omitted when the date formatter declines), nosniff, revalidate-caching, and the
    four privacy headers. Order matters: it is pinned into every head vector below."""
    crlf = "\r\n"
    out = "Server: No Cloud Quick Share" + crlf
    date = http_date(epoch)
    if date != "":
        out += "Date: " + date + crlf
    out += "X-Content-Type-Options: nosniff" + crlf + "Cache-Control: no-cache" + crlf
    out += "Referrer-Policy: no-referrer" + crlf + "X-Frame-Options: DENY" + crlf
    out += "X-Robots-Tag: noindex, nofollow" + crlf + "Permissions-Policy: browsing-topics=()" + crlf
    return out


def http_file_head(size, formime, headers, type_override, extra, seed, gen, epoch):
    """Mirror qsHttpFileHead: the transport-neutral file-head plan. Returns a dict with
    "kind" ("304"/"416"/"serve"), "head" (the complete head text through the blank
    line), and for "serve" also "status"/"start"/"length" (the pump window). Every
    branch says Connection: close - as-built on both transports, kept byte-identical."""
    crlf = "\r\n"
    ctype = type_override if type_override != "" else mime(formime)
    etag = http_weak_etag(size, seed, gen)
    if headers.get("range", "") == "" and if_none_match(headers.get("if-none-match", ""), etag):
        head = ("HTTP/1.1 304 Not Modified" + crlf + "ETag: " + etag + crlf
                + http_extra_headers(epoch) + extra + "Connection: close" + crlf + crlf)
        return {"kind": "304", "head": head}
    rng = parse_range(headers.get("range", ""), size)
    if rng == "unsatisfiable":
        # deliberately spartan, as both twins always sent it: no ETag, no extra block
        head = ("HTTP/1.1 416 Range Not Satisfiable" + crlf
                + "Content-Range: bytes */%d" % size + crlf
                + "Content-Length: 0" + crlf + "Connection: close" + crlf + crlf)
        return {"kind": "416", "head": head}
    if rng == "":
        start, end, status = 0, size - 1, "200 OK"
    else:
        start, end = (int(v) for v in rng.split(","))
        status = "206 Partial Content"
    length = end - start + 1
    head = ("HTTP/1.1 " + status + crlf + "Content-Type: " + ctype + crlf
            + "Accept-Ranges: bytes" + crlf + "ETag: " + etag + crlf
            + "Content-Length: %d" % length + crlf)
    if status.startswith("206"):
        head += "Content-Range: bytes %d-%d/%d" % (start, end, size) + crlf
    head += http_extra_headers(epoch) + extra + http_disposition(formime, headers)
    head += "Connection: close" + crlf + crlf
    return {"kind": "serve", "head": head, "status": status, "start": start, "length": length}


def http_text_response(status, ctype, body, extra, epoch, method, keep=False):
    """Mirror the ONE-SHOT text reply both transports send - qsFsSendText over Tor,
    qsCwSendText over clearweb: every non-file answer (directory listings, 404s, the
    /_qs/* endpoints, every user-route body) goes out through one of these two. Returns
    the complete wire bytes, head then body - EXCEPT on a HEAD, where Content-Length still
    reports exactly what a GET would return and NO body follows it.

    The twins differ in one line, the Connection header (`keep` picks it; the Tor twin is
    always close-per-response and passes keep=False), which is why one mirror can pin both
    - and pinning both is the point: until 2026-08-17 only the clearweb twin had the HEAD
    test, so every non-file Tor reply shipped its body to a client that discards it unread.
    Nothing DESYNCS on that transport, since the response closes the stream; the cost is
    wasted onion bandwidth plus a plain spec violation."""
    crlf = "\r\n"
    data = body.encode("utf-8")
    head = ("HTTP/1.1 " + status + crlf + "Content-Type: " + ctype + crlf
            + "Content-Length: %d" % len(data) + crlf)
    head += http_extra_headers(epoch) + extra
    head += ("Connection: keep-alive" if keep else "Connection: close") + crlf + crlf
    return head.encode("utf-8") + (b"" if method == "HEAD" else data)


# ---- qsEditLoginWait: editor login brute-force backoff -----------------------
# ms this peer must still wait before another attempt. First _EDIT_FREE_TRIES fails are
# free; after that the required gap doubles each fail, capped. Constants mirror the kEdit*
# constants in the script - keep them in lockstep.
_EDIT_FREE_TRIES = 4
_EDIT_LOCK_BASE_MS = 1000
_EDIT_LOCK_CAP_MS = 30000


def edit_login_wait(fails, last_ms, now_ms):
    if not isinstance(fails, int) or fails < _EDIT_FREE_TRIES:
        return 0
    exp = fails - _EDIT_FREE_TRIES
    if exp > 20:
        exp = 20
    need = _EDIT_LOCK_BASE_MS * (2 ** exp)
    if need > _EDIT_LOCK_CAP_MS:
        need = _EDIT_LOCK_CAP_MS
    if not isinstance(last_ms, int):
        return 0
    elapsed = now_ms - last_ms
    if elapsed < 0:
        elapsed = 0            # clock went backwards: never wait more than `need`
    if elapsed >= need:
        return 0
    return need - elapsed


# ---- user-defined API routes (.qsroutes.json) security helpers ---------------
# A user route path must be absolute, traversal-free, control-free, and NEVER under the
# reserved /_qs/ or /_edit/ namespaces. Mirrors qsUserPathValid.

def reserved_path(path):
    """Mirror qsHttpReservedPath: is this path inside a RESERVED server namespace? /_qs
    (observability) and /_edit (the LAN editor) belong to the ROUTE layer alone - no user
    route may declare a path there, no :param pattern may match one, and (2026-08-17) the
    static pipeline refuses one instead of resolving it off disk or through the SPA
    fallback. One predicate for all three, because it was the same literal test written out
    three times and the static one would have made a fourth copy of a security rule.
    Prefix-exact: "/_qsx" and "/_editor" are ordinary paths."""
    return (path in ("/_qs", "/_edit")
            or path.startswith("/_qs/") or path.startswith("/_edit/"))


def user_path_valid(path):
    if path == "" or path[:1] != "/":
        return False
    if ".." in path:
        return False
    if any(ord(c) < 32 for c in path):
        return False
    if reserved_path(path):
        return False
    return True


def sanitize_header_value(v):
    # drop anything that could break out of one header line (CR/LF/NUL/other controls)
    return "".join(c for c in v if ord(c) >= 32)


def sanitize_header_name(n):
    out = ""
    for c in n:
        o = ord(c)
        if (48 <= o <= 57) or (65 <= o <= 90) or (97 <= o <= 122) or c == "-":
            out += c
    return out


# ---- qsMountLocation: user-route redirect Location vs the capability mount ----
# Over a web link the app is mounted under /<token>/, so a FOLDER-ABSOLUTE redirect
# Location ("/gallery") must be re-prefixed with the mount or the browser leaves the
# mount and the token gate 404s the redirected request (the audit's token-mount
# redirect hole). Everything else passes through verbatim: external URLs (a scheme, or
# scheme-relative "//host/...") point off-host on purpose, a relative path already
# resolves against the tokened request URL in the browser, and an empty mount (the Tor
# root) needs no re-basing. The "//" test must precede the "/" prefixing or a
# scheme-relative URL would corrupt into "/<token>//host/...". Mirrors qsMountLocation.

def mount_location(location, mount):
    if mount == "":
        return location
    if not location.startswith("/"):
        return location
    if location.startswith("//"):
        return location
    return mount + location


# ---- render_template: {{...}} substitution in a route body (templating's security core) ----
# Mirrors qsRenderTemplate + qsTemplateValue + qsTemplateEscape. A route body may reflect
# request context ({{method}}/{{path}}/{{query.NAME}}); each value is ESCAPED for the body's
# content-type so a reflected query value can NEVER break the response (inject JSON/HTML/a
# header/control bytes/executable markup). DEFAULT-DENY: only a json type is JSON-escaped; EVERY
# other type (html/xml/svg/js/plain/unknown) is HTML-escaped - a markup/active type that got only
# control-stripping would still execute a reflected <script>. No code runs. ({{now}}/{{date}}
# read the clock, so they are not pinned here - they resolve to empty in this pure mirror; only
# the deterministic tokens + the escaping + the render-size cap are golden-checked.)
_RENDER_MAX = 524288                       # mirrors kRenderMax (512 KB rendered-size guard)


def template_value(tok, req):
    if tok == "method":
        return req.get("__method", "")
    if tok == "path":
        return req.get("__path", "")
    if tok.startswith("query."):
        return query_param(req.get("__query", ""), tok[6:])
    if tok.startswith("param."):
        # the :param captures ride the request array as __params (server-owned "__"
        # namespace - unforgeable by a client); a missing capture is empty, like an
        # absent query value, and the value is escaped at the substitution site
        return req.get("__params", {}).get(tok[6:], "")
    return ""                       # unknown (incl. clock tokens now/date) -> empty here


def template_escape(val, ctype):
    if "json" in ctype:
        return json_escape(val)
    return html_escape(val)               # html/xml/svg/js/plain/unknown: escape markup


def render_template(text, req, ctype):
    out = ""
    rest = text
    while True:
        o = rest.find("{{")
        if o < 0:
            out += rest
            break
        out += rest[:o]                   # literal text before the token
        rest = rest[o + 2:]
        c = rest.find("}}")
        if c < 0:
            out += "{{" + rest            # unterminated -> emit literally
            break
        tok = rest[:c]
        rest = rest[c + 2:]
        out += template_escape(template_value(tok.strip(), req), ctype)
        if len(out.encode("utf-8")) > _RENDER_MAX:
            return out[:_RENDER_MAX]       # bounded: never build an unbounded string
    return out


def main():
    total = 1000
    # -- byte-range parsing --
    for rng, want in [
        ("", ""),                               # no Range header -> whole file
        ("bytes=0-499", "0,499"),               # a normal first-chunk range
        ("bytes=500-999", "500,999"),
        ("bytes=500-", "500,999"),              # open-ended -> to EOF
        ("bytes=0-", "0,999"),
        ("bytes=999-", "999,999"),              # last byte
        ("bytes=-500", "500,999"),              # suffix: last 500 bytes
        ("bytes=-5000", "0,999"),               # suffix bigger than file -> whole
        ("bytes=0-100000", "0,999"),            # end past EOF -> clamped
        ("bytes=1000-", "unsatisfiable"),       # start == total -> 416
        ("bytes=1500-2000", "unsatisfiable"),   # wholly past EOF -> 416
        ("bytes=5-3", "unsatisfiable"),         # start > end -> 416
        ("bytes=abc-10", "unsatisfiable"),      # non-numeric start -> 416
        ("bytes=10-xyz", "unsatisfiable"),      # non-numeric end -> 416
        ("bytes=-", "unsatisfiable"),           # empty suffix -> 416
        ("bytes=0-499,600-799", ""),            # multi-range -> serve whole file
        ("chunks=0-1", ""),                     # not a bytes range -> whole file
        ("bytes=0-0", "0,0"),                   # single first byte
    ]:
        check("parse_range(%r)" % rng, parse_range(rng, total), want)

    # empty file (total 0): any concrete range is unsatisfiable; no range -> ""
    check("parse_range empty-file no-range", parse_range("", 0), "")
    check("parse_range empty-file 0-", parse_range("bytes=0-", 0), "unsatisfiable")

    # -- path-traversal decision --
    for raw, ok in [
        ("/", True),
        ("/file.txt", True),
        ("/sub/dir/a.png", True),
        ("/a%20b.txt", True),                   # a space, decoded, is fine
        ("/../etc/passwd", False),              # literal ..
        ("/%2e%2e/secret", False),              # encoded ..
        ("/a/..%2f..%2fb", False),              # encoded ../.. mid-path
        ("/..%5c..%5cwindows", False),          # encoded ..\ (backslash) -> ..
        ("/deep/../../x", False),
        ("/weird..name.txt", False),            # intentionally strict (matches OnionXT)
    ]:
        check("traversal_ok(%r)" % raw, traversal_ok(raw), ok)

    # -- dotfile guard: dot-leading segments are invisible to the static paths --
    for path, want in [
        ("/", False),
        ("", False),
        ("/file.txt", False),                   # dot INSIDE a name is fine
        ("/notes.d/file", False),               # ...and inside a folder name
        ("/a/b.txt", False),
        ("/.git/config", True),
        ("/a/.env", True),
        ("/dir/.hidden/", True),
        ("/.", True),
        ("/.well-known/x", True),               # wholesale policy: hidden is hidden
    ]:
        check("has_dot_segment(%r)" % path, has_dot_segment(path), want)

    # -- MIME mapping (extension is case-insensitive; unknown -> octet-stream) --
    for path, want in [
        ("index.html", "text/html; charset=utf-8"),
        ("a.PNG", "image/png"),
        ("movie.mp4", "video/mp4"),
        ("song.MP3", "audio/mpeg"),
        ("doc.pdf", "application/pdf"),
        ("archive.zip", "application/zip"),
        ("data.bin", "application/octet-stream"),
        ("noextension", "application/octet-stream"),
        ("a.tar.gz", "application/octet-stream"),   # only the final ext is looked up
        ("app.wasm", "application/wasm"),           # web-app essentials
        ("module.mjs", "application/javascript; charset=utf-8"),
        ("feed.xml", "application/xml; charset=utf-8"),
        ("bundle.js.map", "application/json; charset=utf-8"),
        ("site.webmanifest", "application/manifest+json"),
        ("f.woff", "font/woff"),
        ("font.WOFF2", "font/woff2"),
        ("f.ttf", "font/ttf"),
        ("f.otf", "font/otf"),
        ("f.eot", "application/vnd.ms-fontobject"),
        ("pic.avif", "image/avif"),
        ("data.csv", "text/csv; charset=utf-8"),
    ]:
        check("mime(%r)" % path, mime(path), want)

    # -- HTML escaping (& first so an existing entity is not double-mangled wrong) --
    check("html_escape script",
          html_escape("<script>alert('x')</script>"),
          "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;")
    check("html_escape amp-first", html_escape("a & <b>"), "a &amp; &lt;b&gt;")
    check("html_escape quote", html_escape('say "hi"'), "say &quot;hi&quot;")

    # -- clearweb capability gate (the /<token>/ prefix) --
    tok = "abc123"
    for path, want in [
        ("/abc123/", (True, "/")),                 # folder root
        ("/abc123", (True, "/")),                  # no trailing slash -> root
        ("/abc123/sub/", (True, "/sub/")),         # a subfolder
        ("/abc123/a/b.txt", (True, "/a/b.txt")),   # a nested file
        ("/abc123/photo.jpg", (True, "/photo.jpg")),
        ("/wrongtoken/", (False, "/")),            # bad token -> 404
        ("/", (False, "/")),                       # bare root, no token -> 404
        ("", (False, "/")),                        # empty -> 404
        ("/abc123/../etc", "forbidden"),           # traversal refused first
    ]:
        check("capability_route(%r)" % path, capability_route(path, tok), want)

    # -- SPA fallback: is an unresolved path a client-side route or a missing asset? --
    for path, want in [
        ("/dashboard", True),                      # a route -> index.html
        ("/users/42", True),
        ("/deep/route/here", True),
        ("/", True),                               # empty leaf -> route (resolves anyway)
        ("/a.b/c", True),                          # dot is in a PARENT segment, not the leaf
        ("/app.js", False),                        # a missing asset -> real 404
        ("/assets/logo.png", False),
        ("/favicon.ico", False),
        ("/a/b.min.js", False),
        ("/style.css", False),
    ]:
        check("spa_is_route(%r)" % path, spa_is_route(path), want)

    # -- HTTP request framing (head terminator + Content-Length body) --
    get_full = b"GET /_qs/info HTTP/1.1\r\nHost: x\r\n\r\n"
    check("header_end GET", http_header_end(get_full), get_full.find(b"\r\n\r\n") + 1)
    check("complete GET (no body)", http_req_complete(get_full), True)
    check("incomplete head", http_req_complete(b"GET / HTTP/1.1\r\nHost: x\r\n"), False)
    post_hdr = b"POST /api HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
    check("post no body yet", http_req_complete(post_hdr), False)
    check("post partial body", http_req_complete(post_hdr + b"hel"), False)
    check("post full body", http_req_complete(post_hdr + b"hello"), True)
    check("post over-long body still complete", http_req_complete(post_hdr + b"helloEXTRA"), True)
    check("post non-integer CL -> no body", http_req_complete(
        b"POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n"), True)

    # -- keep-alive framing: qsHttpReqLength trims exactly one request, leaving pipelined
    #    bytes intact and complete for the next round (headEnd + 3 + Content-Length) --
    check("reqlen GET exact", http_req_length(get_full), len(get_full))
    check("reqlen GET incomplete head", http_req_length(b"GET / HTTP/1.1\r\nHost: x\r\n"), 0)
    check("reqlen POST with body", http_req_length(post_hdr + b"hello"), len(post_hdr) + 5)
    # a pipelined pair: trimming the first length leaves EXACTLY the second request
    pair = get_full + post_hdr + b"hello"
    n = http_req_length(pair)
    check("reqlen pipelined GET length", n, len(get_full))
    check("reqlen pipelined remainder intact", pair[n:], post_hdr + b"hello")
    check("reqlen pipelined remainder complete", http_req_complete(pair[n:]), True)
    # trimming a POST(+body) leaves the trailing pipelined GET
    pair2 = post_hdr + b"hello" + get_full
    n2 = http_req_length(pair2)
    check("reqlen POST length includes body", n2, len(post_hdr) + 5)
    check("reqlen POST remainder is next GET", pair2[n2:], get_full)
    # ---- qsHttpParseHead's own decisions, none of which had a test ---------
    # DUPLICATE CONTENT-LENGTH IS THE SMUGGLING LEVER. The engine takes the
    # LAST value and flags the conflict; the stand-in this mirror replaced took
    # the FIRST and modelled no flag, so it disagreed with the server about
    # exactly this input.
    dup = b"POST /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 10\r\n\r\n"
    h = parse_head(dup[:http_header_end(dup) - 1])
    check("parse_head duplicate CL: LAST wins", h.get("content-length"), "10")
    check("parse_head duplicate CL: conflict flagged", h.get("__dupcl"), "true")
    check("framing follows the last CL", _content_length(dup[:http_header_end(dup) - 1]), 10)

    same = b"POST /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n"
    hs = parse_head(same[:http_header_end(same) - 1])
    check("parse_head identical repeat is not a conflict", hs.get("__dupcl"), None)
    check("parse_head identical repeat still frames", hs.get("content-length"), "5")

    # A CLIENT MAY NOT SHADOW THE "__" PSEUDO-FIELD NAMESPACE. __params is
    # unforgeable only because this refusal exists; onionxt shipped the same
    # parser WITHOUT it until 2026-08-19, where a header named __path replaced
    # the parsed path.
    inj = (b"GET /safe HTTP/1.1\r\n__path: /../../etc/passwd\r\n"
           b"__method: DELETE\r\n__params: forged\r\nHost: h\r\n\r\n")
    hi = parse_head(inj[:http_header_end(inj) - 1])
    check("parse_head: __path cannot be shadowed", hi.get("__path"), "/safe")
    check("parse_head: __method cannot be shadowed", hi.get("__method"), "GET")
    check("parse_head: __params cannot be forged", hi.get("__params"), None)
    check("parse_head: an ordinary header still lands", hi.get("host"), "h")

    # the request line, which nothing pinned either
    rl = b"GET /a/b?x=1&y=2 HTTP/1.1\r\nHost: h\r\n\r\n"
    hr = parse_head(rl[:http_header_end(rl) - 1])
    check("parse_head method", hr.get("__method"), "GET")
    check("parse_head path", hr.get("__path"), "/a/b")
    check("parse_head query", hr.get("__query"), "x=1&y=2")
    check("parse_head resource", hr.get("__resource"), "/a/b?x=1&y=2")
    check("parse_head no query is empty, not absent",
          parse_head(b"GET /a HTTP/1.1\r\nHost: h").get("__query"), "")

    # non-integer Content-Length frames as no body (matches http_req_complete)
    check("reqlen non-integer CL -> head only", http_req_length(
        b"POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n"),
        http_header_end(b"POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n") + 3)

    # -- JSON value escaping (for the /_qs/info route) --
    check("json plain", json_escape("hello"), "hello")
    check("json quote", json_escape('a"b'), 'a\\"b')
    check("json backslash", json_escape("c:\\path"), "c:\\\\path")
    check("json crlf", json_escape("a\r\nb"), "a\\r\\nb")
    check("json tab", json_escape("x\ty"), "x\\ty")
    check("json backslash-before-quote order", json_escape('\\"'), '\\\\\\"')

    # -- editor write-path confinement (THE security linchpin) --
    R = "/srv"
    for rel, want in [
        ("index.html", "/srv/index.html"),        # allowed: a plain file
        ("css/app.css", "/srv/css/app.css"),
        ("/css/app.css", "/srv/css/app.css"),     # leading slash is fine
        ("a//b.txt", "/srv/a/b.txt"),             # empty segment collapses
        ("./a.txt", "/srv/a.txt"),                # "." segment dropped
        ("a/./b.txt", "/srv/a/b.txt"),
        (".env", "/srv/.env"),                    # a dotfile UNDER root is fine
        ("../etc/passwd", ""),                    # REJECT: traversal
        ("a/../b", ""),
        ("..", ""),
        ("...", ""),                              # REJECT: contains ".." (over-cautious)
        ("my..file.txt", ""),                     # REJECT: contains ".." (over-cautious)
        ("C:/Windows/win.ini", ""),               # REJECT: drive colon
        ("http://evil/x", ""),                    # REJECT: scheme colon
        ("", ""),                                 # REJECT: names nothing
        ("/", ""),
        ("\\..\\..\\x", ""),                      # REJECT: backslashes -> ".."
        ("a\x00b.txt", ""),                       # REJECT: NUL / control char
        ("a\tb.txt", ""),                         # REJECT: control char (tab)
    ]:
        check("edit_safe_path(%r)" % rel, edit_safe_path(R, rel), want)

    # -- parent-folder chain for editor writes/uploads into new subfolders --
    for rel, want in [
        ("c.png", []),                            # root-level file: nothing to create
        ("a/c.png", ["a"]),
        ("a/b/c.png", ["a", "a/b"]),
        ("assets/uploads/pic.jpg", ["assets", "assets/uploads"]),
        ("a//b/c.png", ["a", "a/b"]),             # doubled slash collapses
        ("a/./b/c.png", ["a", "a/b"]),            # "." segments vanish
        ("a\\b\\c.png", ["a", "a/b"]),            # backslashes normalise
        ("a/b/", ["a"]),                          # trailing "/": leaf is still the leaf
        ("a/b/.", ["a"]),                         # trailing "." must NOT make the leaf a folder
        ("a/b/./", ["a"]),                        # ...nor a trailing "/./"
        (".", []),                                # a lone "." -> no parents
        ("/", []),
        ("", []),
    ]:
        check("edit_parent_dirs(%r)" % rel, edit_parent_dirs(rel), want)

    # -- directory-listing icon classification --
    for name, is_dir, want in [
        ("photos", True, "dir"),                  # a folder
        ("index.html", False, "code"),            # web source -> code icon
        ("app.min.js", False, "code"),            # last ext only
        ("styles.css", False, "code"),
        ("logo.PNG", False, "img"),               # case-insensitive
        ("clip.mp4", False, "vid"),
        ("song.flac", False, "aud"),
        ("notes.txt", False, "doc"),
        ("readme.md", False, "doc"),
        ("data.csv", False, "doc"),
        ("archive.tar.gz", False, "zip"),         # final ext gz -> zip
        ("manual.pdf", False, "pdf"),
        ("photo.heic", False, "img"),
        ("blob.bin", False, "file"),              # unknown -> generic
        ("Makefile", False, "file"),              # no extension -> generic
    ]:
        check("fs_icon(%r)" % name, fs_icon(name, is_dir), want)

    # -- file-size seek probe: must return the exact size for every shape --
    for s in [0, 1, 2, 3, 4, 7, 8, 255, 256, 257, 1000, 4095, 4096, 65535, 65536,
              1000000, 2 ** 30, 8589934592]:      # last = exactly the 8 GiB cap
        check("file_size_probe(%d)" % s, file_size_probe(s), s)
    # a file larger than the cap gives up (caller falls back to the linear count)
    check("file_size_probe over-cap", file_size_probe(8589934592 + 1), None)

    # -- Content-Disposition filename sanitising --
    for name, want in [
        ("report.pdf", "report.pdf"),
        ("my file.txt", "my file.txt"),           # spaces are fine
        ('a"b.txt', "ab.txt"),                     # drop the quote
        ("back\\slash", "backslash"),             # drop the backslash
        ("nau\x00gh\tty", "naughty"),             # drop control bytes
        ("café.png", "caf.png"),             # drop non-ASCII (no RFC 5987 needed)
        ("", "download"),                          # nothing left -> a default
        ("\x01\x02", "download"),
    ]:
        check("safe_filename(%r)" % name, safe_filename(name), want)

    # -- compact transfer-row rate + ETA formatting --
    for bps, want in [
        (0, "0B/s"), (-5, "0B/s"), (512, "512B/s"), (1024, "1K/s"),
        (1536, "1.5K/s"), (1048576, "1M/s"), (1300000, "1.2M/s"),
        (1073741824, "1G/s"), (2000, "2K/s"),
    ]:
        check("rate_short(%d)" % bps, rate_short(bps), want)
    for secs, want in [
        (-1, ""), (0, "0s"), (45, "45s"), (59, "59s"), (60, "1m"), (125, "2m"),
        (3599, "59m"), (3600, "1h0m"), (3725, "1h2m"), (86399, "23h59m"),
        (86400, ">1d"), (200000, ">1d"), (44.9, "44s"),
    ]:
        check("eta_short(%r)" % secs, eta_short(secs), want)

    # -- editor LAN-first gate (only local peers may reach the editor) --
    for conn, want in [
        ("cw:192.168.1.5:52000", True),           # home LAN
        ("cw:10.0.0.9:1234", True),               # RFC-1918 10/8
        ("cw:127.0.0.1:5000", True),              # loopback
        ("cw:172.16.4.4:80", True),               # 172.16/12 lower edge
        ("cw:172.31.9.9:80", True),               # 172.16/12 upper edge
        ("cw:172.32.0.1:80", False),              # just outside 172.16-31 -> public
        ("cw:100.64.0.1:80", False),              # carrier-NAT: ISP-shared, NOT the LAN
        ("cw:169.254.1.1:80", True),              # link-local
        ("cw:::1:5000", True),                    # IPv6 loopback
        ("cw:8.8.8.8:443", False),                # public
        ("cw:203.0.113.7:12345", False),          # public (TEST-NET-3)
        ("cw:192.168.0.1:80|2", True),            # private with a |n socket suffix
        ("cw:1.2.3.4:80|3", False),               # public with a |n socket suffix
        ("ox:streamhandle42", False),             # Tor: ALWAYS remote
        ("ox:anything", False),
    ]:
        check("edit_is_local(%r)" % conn, edit_is_local(conn), want)

    # -- query-string value extraction (editor read/write ?path=) --
    for query, name, want in [
        ("path=css/app.css", "path", "css/app.css"),
        ("path=a%2Fb.txt", "path", "a/b.txt"),    # %2F decoded to /
        ("path=a%20b.txt", "path", "a b.txt"),    # %20 decoded to a space
        ("path=a+b.txt", "path", "a b.txt"),      # LiveCode urlDecode: '+' -> space
        ("path=a%2Bb.txt", "path", "a+b.txt"),    # %2B -> a literal '+' (what the JS sends)
        ("x=1&path=main.js", "path", "main.js"),  # second param
        ("path=main.js&x=1", "path", "main.js"),  # first param
        ("path=x=y", "path", "x=y"),              # value may contain '='
        ("path=", "path", ""),                    # present but empty
        ("q=hello", "path", ""),                  # absent -> empty
        ("", "path", ""),                         # no query -> empty
        ("foo=bar&foo=baz", "foo", "bar"),        # first match wins
    ]:
        check("query_param(%r,%r)" % (query, name), query_param(query, name), want)

    # -- HTTP-date formatting: cross-check the pure impl against the stdlib --
    for epoch in [0, 1, 59, 60, 3599, 3600, 86399, 86400,
                  951782400, 951868800,        # 2000-02-29 / 2000-03-01 (leap)
                  1078012800,                   # 2004-02-29 (leap)
                  1709164800, 1709251200,       # 2024-02-29 / 2024-03-01 (leap)
                  1751812800, 1767225599,       # 2025 mid / 2025-12-31 23:59:59
                  1735689600, 2147483647,       # 2025-01-01 / the 2038 boundary
                  4102444800, 4107456000,       # 2100-01-01 / 2100-02-28 (century, NOT leap)
                  4133980800]:                  # 2101-01-01 (proves 2100 had 365 days)
        check("http_date(%d)" % epoch, http_date(epoch), formatdate(epoch, usegmt=True))
    check("http_date(-1)", http_date(-1), "")
    check("http_date('x')", http_date("x"), "")
    check("http_date(0) literal", http_date(0), "Thu, 01 Jan 1970 00:00:00 GMT")

    # -- Allow header: static verbs + registered route methods for a path --
    _routes = ["GET /_qs/info", "GET /_edit", "POST /_edit/login",
               "GET /_edit/api/list", "GET /_edit/api/read", "PUT /_edit/api/write"]
    for path, want in [
        ("/_edit/login", "GET, HEAD, OPTIONS, POST"),
        ("/_edit/api/write", "GET, HEAD, OPTIONS, PUT"),
        ("/_qs/info", "GET, HEAD, OPTIONS"),          # a GET route dedups into the static set
        ("/nope", "GET, HEAD, OPTIONS"),              # no route -> just the static verbs
    ]:
        check("http_allow(%r)" % path, http_allow(_routes, path), want)
    # multiple non-static methods on one path sort deterministically
    check("http_allow multi",
          http_allow(["POST /x", "PUT /x", "DELETE /x", "GET /x"], "/x"),
          "GET, HEAD, OPTIONS, DELETE, POST, PUT")
    # user-declared (.qsroutes.json) methods merge in, de-duplicated with the built-in table
    _uroutes = ["POST /api/submit", "GET /api/hello", "PUT /api/submit"]
    for path, want in [
        ("/api/submit", "GET, HEAD, OPTIONS, POST, PUT"),   # two user methods, sorted
        ("/api/hello", "GET, HEAD, OPTIONS"),               # a GET user route dedups away
        ("/nope", "GET, HEAD, OPTIONS"),                    # no user route for this path
    ]:
        check("http_allow user(%r)" % path, http_allow([], path, _uroutes), want)
    # a method present in BOTH tables appears once (dedup across tables)
    check("http_allow dedup-cross",
          http_allow(["POST /dup"], "/dup", ["POST /dup"]), "GET, HEAD, OPTIONS, POST")

    # -- CORS preflight block: only when a cors route exists on the path --
    _cors_keys = ["POST /api/submit", "GET /api/open"]
    _pf = ("Access-Control-Allow-Origin: *\r\n"
           "Access-Control-Allow-Methods: GET, HEAD, OPTIONS, POST\r\n"
           "Access-Control-Allow-Headers: *\r\n"
           "Access-Control-Max-Age: 600\r\n")
    check("cors_preflight match",
          cors_preflight(_cors_keys, "/api/submit", "GET, HEAD, OPTIONS, POST"), _pf)
    check("cors_preflight no-cors-route", cors_preflight(_cors_keys, "/api/other", "GET, HEAD, OPTIONS"), "")
    check("cors_preflight empty", cors_preflight([], "/api/submit", "GET, HEAD, OPTIONS"), "")

    # -- conditional GET: weak ETag build, core extraction, If-None-Match match --
    check("http_weak_etag", http_weak_etag(1000, 42, 0), 'W/"1000-42-0"')
    _et = http_weak_etag(1000, 42, 3)                       # W/"1000-42-3"
    for tag, want in [
        ('W/"1000-42-3"', "1000-42-3"),                    # weak form
        ('"1000-42-3"', "1000-42-3"),                      # strong form
        (' W/"abc" ', "abc"),                              # surrounding whitespace
        ('W/""', ""),                                      # empty value
    ]:
        check("etag_core(%r)" % tag, etag_core(tag), want)
    for header, want in [
        ("", False),                                       # no header -> not conditional
        ("*", True),                                       # wildcard matches anything
        ('W/"1000-42-3"', True),                           # exact weak match
        ('"1000-42-3"', True),                             # strong sent, weak compare -> match
        ('W/"1000-42-2"', False),                          # a stale gen -> no match (re-send)
        ('W/"9-9-9", W/"1000-42-3"', True),                # match anywhere in the list
        ('W/"9-9-9"', False),                              # different resource -> no match
    ]:
        check("if_none_match(%r)" % header, if_none_match(header, _et), want)

    # -- the shared file-head plan: the ONE 304/416/200/206 decision both twins call --
    _fh_epoch = 1751812800                                 # fixed clock for the Date line
    _fh_extra = http_extra_headers(_fh_epoch)
    check("http_extra_headers block", _fh_extra,
          "Server: No Cloud Quick Share\r\n"
          "Date: " + formatdate(_fh_epoch, usegmt=True) + "\r\n"
          "X-Content-Type-Options: nosniff\r\nCache-Control: no-cache\r\n"
          "Referrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\n"
          "X-Robots-Tag: noindex, nofollow\r\nPermissions-Policy: browsing-topics=()\r\n")
    for path, want in [
        ("movie.mp4", "movie.mp4"),                        # bare name is its own leaf
        ("a/b/c.txt", "c.txt"),
        ("a\\b\\x.png", "x.png"),                          # backslashes normalise
        ("/abs/dir/f.pdf", "f.pdf"),
        ("dir/", ""),                                      # trailing slash -> empty leaf
    ]:
        check("fs_leaf(%r)" % path, fs_leaf(path), want)
    check("http_disposition inline", http_disposition("a/movie.mp4", {"__query": ""}),
          'Content-Disposition: inline; filename="movie.mp4"\r\n')
    check("http_disposition ?dl", http_disposition("movie.mp4", {"__query": "dl=1"}),
          'Content-Disposition: attachment; filename="movie.mp4"\r\n')
    check("http_disposition sanitised", http_disposition('a"b.txt', {"__query": ""}),
          'Content-Disposition: inline; filename="ab.txt"\r\n')
    _fh_get = {"__method": "GET", "__query": "", "range": "", "if-none-match": ""}
    # a plain full GET: 200, the whole file, the complete head byte-for-byte
    _fh = http_file_head(1000, "movie.mp4", _fh_get, "", "", 42, 0, _fh_epoch)
    check("file_head 200 kind", _fh["kind"], "serve")
    check("file_head 200 window", (_fh["status"], _fh["start"], _fh["length"]),
          ("200 OK", 0, 1000))
    check("file_head 200 head", _fh["head"],
          "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\n"
          'ETag: W/"1000-42-0"\r\nContent-Length: 1000\r\n' + _fh_extra +
          'Content-Disposition: inline; filename="movie.mp4"\r\nConnection: close\r\n\r\n')
    # a Range request: 206 + Content-Range, window honoured
    _fh = http_file_head(1000, "movie.mp4", dict(_fh_get, range="bytes=500-"),
                         "", "", 42, 0, _fh_epoch)
    check("file_head 206 kind+window", (_fh["kind"], _fh["status"], _fh["start"], _fh["length"]),
          ("serve", "206 Partial Content", 500, 500))
    check("file_head 206 head", _fh["head"],
          "HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\n"
          'ETag: W/"1000-42-0"\r\nContent-Length: 500\r\nContent-Range: bytes 500-999/1000\r\n'
          + _fh_extra +
          'Content-Disposition: inline; filename="movie.mp4"\r\nConnection: close\r\n\r\n')
    # a matching If-None-Match on a full request: 304, no pump window
    _fh_inm = dict(_fh_get)
    _fh_inm["if-none-match"] = 'W/"1000-42-0"'
    _fh = http_file_head(1000, "movie.mp4", _fh_inm, "", "", 42, 0, _fh_epoch)
    check("file_head 304 kind", _fh["kind"], "304")
    check("file_head 304 head", _fh["head"],
          'HTTP/1.1 304 Not Modified\r\nETag: W/"1000-42-0"\r\n' + _fh_extra +
          "Connection: close\r\n\r\n")
    # a Range request NEVER 304s: the bytes are served even when the validator matches
    check("file_head range beats 304",
          http_file_head(1000, "movie.mp4", dict(_fh_inm, range="bytes=0-9"),
                         "", "", 42, 0, _fh_epoch)["kind"], "serve")
    # a stale validator (the edit generation moved on) re-serves rather than 304s
    check("file_head stale gen re-serves",
          http_file_head(1000, "movie.mp4", _fh_inm, "", "", 42, 1, _fh_epoch)["kind"], "serve")
    # an unsatisfiable Range: 416, and the head stays deliberately spartan (no ETag,
    # no extra-header block) exactly as both twins have always sent it
    _fh = http_file_head(1000, "movie.mp4", dict(_fh_get, range="bytes=5000-"),
                         "", "", 42, 0, _fh_epoch)
    check("file_head 416 kind", _fh["kind"], "416")
    check("file_head 416 head", _fh["head"],
          "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */1000\r\n"
          "Content-Length: 0\r\nConnection: close\r\n\r\n")
    # a user file route: type override + route extra headers land in order, ?dl attaches
    _fh = http_file_head(10, "data.bin", dict(_fh_get, __query="dl=1"),
                         "application/json; charset=utf-8", "X-Extra: 1\r\n",
                         7, 2, _fh_epoch)
    check("file_head override+extra head", _fh["head"],
          "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"
          'Accept-Ranges: bytes\r\nETag: W/"10-7-2"\r\nContent-Length: 10\r\n' + _fh_extra +
          "X-Extra: 1\r\n"
          'Content-Disposition: attachment; filename="data.bin"\r\nConnection: close\r\n\r\n')

    # -- the one-shot TEXT reply (the non-file half): a HEAD keeps the Content-Length a GET
    # would have sent and ships NO body. Until 2026-08-17 the Tor twin qsFsSendText had no
    # method test at all, so every non-file Tor reply - listings, 404s, /_qs/info,
    # /_qs/transparency, /_qs/routes, every user-route body - sent its body in answer to a
    # HEAD. Nothing desyncs there (a Tor response closes its stream), so the cost is bytes
    # pushed down an onion circuit for a client that discards them, plus the spec violation.
    _tx = "hello, HEAD"                                    # 11 bytes when UTF-8 encoded
    _tx_get = http_text_response("200 OK", "text/plain; charset=utf-8", _tx, "",
                                 _fh_epoch, "GET")
    _tx_head = http_text_response("200 OK", "text/plain; charset=utf-8", _tx, "",
                                  _fh_epoch, "HEAD")
    check("text_response GET body", _tx_get.split(b"\r\n\r\n", 1)[1], b"hello, HEAD")
    check("text_response HEAD body", _tx_head.split(b"\r\n\r\n", 1)[1], b"")
    # THE property: the head is byte-identical, so Content-Length is UNCHANGED at 11 - a
    # HEAD reports what a GET would return, which is the whole point of the method
    check("text_response HEAD head is the GET head",
          _tx_head.split(b"\r\n\r\n", 1)[0], _tx_get.split(b"\r\n\r\n", 1)[0])
    check("text_response Content-Length survives HEAD",
          b"Content-Length: 11\r\n" in _tx_head, True)
    # the full head byte-for-byte, so the header ORDER is pinned like every file head above
    check("text_response head", _tx_get.split(b"\r\n\r\n", 1)[0].decode("utf-8"),
          "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n"
          "Content-Length: 11\r\n" + _fh_extra + "Connection: close")
    # pExtra lands after the always-sent block (the 405's Allow line, the 429's Retry-After)
    check("text_response extra header",
          http_text_response("405 Method Not Allowed", "text/plain; charset=utf-8",
                             "Method not allowed.", "Allow: GET, HEAD, OPTIONS\r\n",
                             _fh_epoch, "GET").split(b"\r\n\r\n", 1)[0].decode("utf-8"),
          "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain; charset=utf-8\r\n"
          "Content-Length: 19\r\n" + _fh_extra + "Allow: GET, HEAD, OPTIONS\r\n"
          "Connection: close")
    # the twins differ in exactly ONE line: clearweb may keep the connection, Tor never does
    check("text_response keep-alive is the only twin difference",
          http_text_response("200 OK", "text/plain; charset=utf-8", _tx, "",
                             _fh_epoch, "GET", True),
          _tx_get.replace(b"Connection: close", b"Connection: keep-alive"))
    # a HEAD suppresses the body on a kept-alive connection too (there the unread body would
    # also be mis-read as the framing of the NEXT response - the clearweb-only hazard)
    check("text_response HEAD keep-alive body",
          http_text_response("200 OK", "text/plain; charset=utf-8", _tx, "",
                             _fh_epoch, "HEAD", True).split(b"\r\n\r\n", 1)[1], b"")

    # -- editor login brute-force backoff --
    for fails, last_ms, now_ms, want in [
        (0, None, 1000, 0),                     # first attempt: free
        (3, 500, 600, 0),                       # still within the free tries
        (4, 1000, 1000, 1000),                  # 1st throttled: base 1s, no time elapsed
        (4, 1000, 1500, 500),                   # 500ms already waited -> 500 left
        (4, 1000, 2000, 0),                     # full second elapsed -> allowed
        (5, 1000, 1000, 2000),                  # doubles: 2s
        (6, 1000, 1000, 4000),                  # 4s
        (9, 1000, 1000, 30000),                 # 32s -> capped at 30s
        (100, 1000, 1000, 30000),               # exponent bounded, still capped
        (5, None, 1000, 0),                     # no recorded last attempt -> allowed
        (4, 5000, 3000, 1000),                  # clock skew (now < last): treat as no time waited
    ]:
        check("edit_login_wait(%r,%r,%r)" % (fails, last_ms, now_ms),
              edit_login_wait(fails, last_ms, now_ms), want)

    # -- user-route path validation (reserved namespaces, traversal, controls) --
    for path, want in [
        ("/api/hello", True),
        ("/hello", True),
        ("/go/docs", True),
        ("/normal-path_123", True),
        ("/_qsx", True),                        # not /_qs or /_qs/... -> allowed
        ("", False),
        ("api/x", False),                       # must be absolute
        ("/../etc", False),
        ("/a/../b", False),
        ("/_qs", False),                        # reserved (exact)
        ("/_qs/info", False),                   # reserved (prefix)
        ("/_edit", False),
        ("/_edit/login", False),
        ("/a\nb", False),                       # control byte
    ]:
        check("user_path_valid(%r)" % path, user_path_valid(path), want)

    # -- the reserved-namespace predicate the three refusals above all share --
    for path, want in [
        ("/_qs", True), ("/_qs/info", True), ("/_qs/", True),
        ("/_edit", True), ("/_edit/api/write", True),
        ("/_qsx", False),                       # a longer first segment is a normal path
        ("/_editor", False),
        ("/a/_qs", False),                      # reserved only at the ROOT of the app path
        ("/_q", False), ("/", False), ("", False),
    ]:
        check("reserved_path(%r)" % path, reserved_path(path), want)

    # -- HEAD route lookup: HEAD is GET-without-a-body, so it must reach the GET route --
    # Until 2026-08-17 the lookup key was built from the literal method, so a HEAD matched
    # nothing in either table and fell into the static pipeline - where the leaf has no "."
    # and the SPA fallback answers index.html. HEAD /_qs/info came back as the SPA page at
    # 200 text/html while http_allow had advertised HEAD on every path. Both transports
    # shared that path, so both were wrong.
    _lk_builtin = ["GET /_qs/info", "GET /_qs/transparency", "POST /_edit/login"]
    _lk_user = ["GET /api/hello", "HEAD /probe", "GET /probe", "POST /api/submit"]
    for method, path, keys, want in [
        ("HEAD", "/_qs/info", _lk_builtin, "GET /_qs/info"),     # the built-in route answers
        ("HEAD", "/api/hello", _lk_user, "GET /api/hello"),      # a user route answers
        ("HEAD", "/probe", _lk_user, "HEAD /probe"),             # a DECLARED HEAD route wins
        ("GET", "/api/hello", _lk_user, "GET /api/hello"),       # a GET is untouched
        ("GET", "/nope", _lk_user, "GET /nope"),                 # ... including a miss
        ("POST", "/api/submit", _lk_user, "POST /api/submit"),   # no fallback for other verbs
        ("POST", "/probe", _lk_user, "POST /probe"),             # ... even where GET exists
        ("HEAD", "/nope", _lk_user, "GET /nope"),                # falls back, then misses ->
                                                                 # the static pipeline, as before
        ("head", "/api/hello", _lk_user, "GET /api/hello"),      # method upper-cased first
        ("HEAD", "/api/hello", [], "GET /api/hello"),            # an EMPTY table: no HEAD route
        ("GET", "/api/hello", [], "GET /api/hello"),             # ... and unchanged for a GET
    ]:
        check("route_lookup_key(%r,%r)" % (method, path),
              route_lookup_key(method, path, keys), want)

    # -- :param patterns: the key split, the exact-vs-pattern test, the specificity rank --
    for key, want in [
        ("GET /api/x", "/api/x"),
        ("DELETE /api/files/:name", "/api/files/:name"),
        ("GET /a b", "/a b"),                   # a path may contain a space; first space splits
        ("NOSPACE", ""),
    ]:
        check("route_key_path(%r)" % key, route_key_path(key), want)
    for path, want in [
        ("/api/hello", False),
        ("/api/:name", True),
        ("/api/files/:name", True),
        ("/api/x:y", False),                    # ":" not segment-leading -> literal, not a param
        ("/", False),
    ]:
        check("route_has_params(%r)" % path, route_has_params(path), want)
    for path, want in [
        ("/api/hello", 0),
        ("/api/:a", 1),
        ("/api/:a/:b", 2),
        ("/api/:a/sub/:b", 2),
    ]:
        check("route_param_count(%r)" % path, route_param_count(path), want)

    # -- :param declaration gate: static first segment, named params, no duplicates --
    for path, want in [
        ("/api/:name", True),
        ("/api/files/:name", True),
        ("/api/:a/:b", True),
        ("/api/:a/sub/:b", True),
        ("/dl/:tag/", True),                    # trailing slash is a legal (significant) shape
        ("/api/hello", True),                   # a plain path defers to user_path_valid
        ("/:x", False),                         # THE constraint: a leading param would match
        ("/:x/y", False),                       #   /_qs and /_edit - first segment must be static
        ("/_qs/:x", False),                     # reserved at declaration (literal prefix)
        ("/_edit/:x", False),
        ("/api/:", False),                      # ":" alone names nothing
        ("/api/:na-me", False),                 # names are [A-Za-z0-9_] only
        ("/api/:x/:x", False),                  # duplicate capture name
        ("/files/:a..b", False),                # ".." refused (user_path_valid runs first)
        ("api/:x", False),                      # must be absolute
    ]:
        check("user_pattern_valid(%r)" % path, user_pattern_valid(path), want)

    # -- :param matching: capture extraction + the request-time reserved backstop --
    for pattern, path, want in [
        ("/api/files/:name", "/api/files/readme.txt", {"name": "readme.txt"}),
        ("/api/:a/:b", "/api/x/y", {"a": "x", "b": "y"}),
        ("/api/files/:name", "/api/files/", None),      # a param never matches empty
        ("/api/files/:name", "/api/files/a/b", None),   # one segment only (an encoded %2F
        #   decodes to a real "/" BEFORE routing, so it splits and cannot ride a param)
        ("/api/files/:name", "/api/other/x", None),     # static segment mismatch
        ("/dl/:tag/", "/dl/v1/", {"tag": "v1"}),        # trailing slash on both -> match
        ("/dl/:tag", "/dl/v1/", None),                  # trailing slash is significant...
        ("/dl/:tag/", "/dl/v1", None),                  # ...in both directions
        # a request whose literal path IS the pattern text still goes through the matcher
        # (qsHttpTryRoutes skips patterns on the exact fast path), so it captures ":name"
        ("/api/greet/:name", "/api/greet/:name", {"name": ":name"}),
        # request-time reserved backstop: even HOSTILE patterns that declaration refuses
        # (leading param / reserved prefix) can never match a reserved request path
        ("/:x/info", "/_qs/info", None),
        ("/_qs/:x", "/_qs/info", None),
        ("/files/:x", "/_qs/info", None),
        ("/:x", "/_edit", None),
        ("/:x/login", "/_edit/login", None),
    ]:
        check("route_match(%r,%r)" % (pattern, path), route_match(pattern, path), want)

    # -- deterministic pattern pick: method filter, specificity, tie-break, backstop --
    _pat_keys = ["GET /api/hello", "GET /api/files/:name",
                 "POST /api/files/:name", "GET /api/:a/:b"]
    for method, path, want in [
        ("GET", "/api/files/x", "GET /api/files/:name"),   # 1 param beats 2
        ("POST", "/api/files/x", "POST /api/files/:name"), # method filters
        ("DELETE", "/api/files/x", ""),                    # no route for the method
        ("GET", "/api/x/y", "GET /api/:a/:b"),
        ("GET", "/api/hello", ""),               # exact keys are the caller's fast path
        ("GET", "/_qs/info", ""),                # reserved: nothing ever matches
    ]:
        check("user_route_find(%r,%r)" % (method, path),
              user_route_find(_pat_keys, method, path), want)
    # equal param counts tie-break on the smallest key - never on table iteration order
    check("user_route_find tie-break",
          user_route_find(["GET /api/files/:b", "GET /api/:a/x"], "GET", "/api/files/x"),
          "GET /api/:a/x")
    # a hostile pattern injected past declaration still cannot claim a reserved path
    check("user_route_find hostile-reserved",
          user_route_find(["GET /:x/info"], "GET", "/_qs/info"), "")
    check("user_route_find literal-pattern-text",
          user_route_find(["GET /api/greet/:name"], "GET", "/api/greet/:name"),
          "GET /api/greet/:name")

    # -- Allow/405 derivation with :param routes: a matching pattern contributes its methods --
    for path, ukeys, want in [
        ("/api/files/readme.txt",
         ["DELETE /api/files/:name", "GET /api/files/:name", "PUT /api/other/:x"],
         "GET, HEAD, OPTIONS, DELETE"),
        ("/api/files/x", ["POST /api/files/x", "POST /api/files/:n"],
         "GET, HEAD, OPTIONS, POST"),           # exact + pattern dedup to one POST
        ("/api/files/a/b", ["DELETE /api/files/:n"],
         "GET, HEAD, OPTIONS"),                 # non-matching pattern contributes nothing
        ("/_qs/info", ["DELETE /:x/info"],
         "GET, HEAD, OPTIONS"),                 # the reserved backstop shows up in Allow too
    ]:
        check("http_allow param(%r)" % path, http_allow([], path, ukeys), want)

    # -- CORS preflight promise holds identically for :param routes --
    _pf_param = ("Access-Control-Allow-Origin: *\r\n"
                 "Access-Control-Allow-Methods: GET, HEAD, OPTIONS, POST\r\n"
                 "Access-Control-Allow-Headers: *\r\n"
                 "Access-Control-Max-Age: 600\r\n")
    check("cors_preflight param match",
          cors_preflight(["POST /api/thing/:id"], "/api/thing/42",
                         "GET, HEAD, OPTIONS, POST"), _pf_param)
    check("cors_preflight param no-match",
          cors_preflight(["POST /api/thing/:id"], "/api/other/42",
                         "GET, HEAD, OPTIONS"), "")
    check("cors_preflight param reserved",
          cors_preflight(["GET /:x/info"], "/_qs/info", "GET, HEAD, OPTIONS"), "")

    # -- the file-pointing param route: find + captures + the SAME bounded-pump head plan --
    # (Phase 3's "streaming" scope: a route response beyond the inline-body budget points at
    # a folder file and rides the existing pump - Range-aware, per-route headers, type
    # override - through the one shared head builder already pinned above.)
    _dl_key = user_route_find(["GET /dl/:version"], "GET", "/dl/v1.2.3")
    check("param file route find", _dl_key, "GET /dl/:version")
    check("param file route captures",
          route_match(route_key_path(_dl_key), "/dl/v1.2.3"), {"version": "v1.2.3"})
    _fh = http_file_head(10, "big.bin", dict(_fh_get, range="bytes=0-3"),
                         "application/octet-stream", "X-Route: dl\r\n", 42, 0, _fh_epoch)
    check("param file route head kind+window",
          (_fh["kind"], _fh["status"], _fh["start"], _fh["length"]),
          ("serve", "206 Partial Content", 0, 4))
    check("param file route head", _fh["head"],
          "HTTP/1.1 206 Partial Content\r\nContent-Type: application/octet-stream\r\n"
          'Accept-Ranges: bytes\r\nETag: W/"10-42-0"\r\nContent-Length: 4\r\n'
          "Content-Range: bytes 0-3/10\r\n" + _fh_extra + "X-Route: dl\r\n"
          'Content-Disposition: inline; filename="big.bin"\r\nConnection: close\r\n\r\n')

    # -- header sanitisation (no CRLF/control injection) --
    for val, want in [
        ("value", "value"),
        ("a\r\nb", "ab"),                       # CR + LF stripped
        ("a\tb", "ab"),                         # tab (9) stripped
        ("x\x00y", "xy"),                       # NUL stripped
        ("keep me", "keep me"),                 # space (32) kept
    ]:
        check("sanitize_header_value(%r)" % val, sanitize_header_value(val), want)
    for name, want in [
        ("X-Custom", "X-Custom"),
        ("Content-Type", "Content-Type"),
        ("bad name", "badname"),                # space dropped
        ("X:Injection", "XInjection"),          # colon dropped
        ("a\r\nb", "ab"),
        ("under_score", "underscore"),          # underscore not a kept token char (strict)
    ]:
        check("sanitize_header_name(%r)" % name, sanitize_header_name(name), want)

    # -- redirect Location vs the /<token>/ capability mount (the redirect hole) --
    for loc, mount, want in [
        ("/gallery", "/abc123", "/abc123/gallery"),  # folder-absolute under the mount
        ("/", "/abc123", "/abc123/"),                # the folder root itself
        ("/go/x/y", "/abc123", "/abc123/go/x/y"),    # deep folder path
        ("/gallery", "", "/gallery"),                # Tor / root mount: unchanged
        ("http://example.org/x", "/abc123", "http://example.org/x"),   # external http
        ("https://example.org/x", "/abc123", "https://example.org/x"), # external https
        ("//example.org/x", "/abc123", "//example.org/x"),  # scheme-relative external
        ("gallery/pics", "/abc123", "gallery/pics"), # relative: browser resolves in-mount
        ("mailto:a@b.example", "/abc123", "mailto:a@b.example"),  # non-http scheme
    ]:
        check("mount_location(%r,%r)" % (loc, mount), mount_location(loc, mount), want)

    # -- template rendering ({{...}} reflected request context, escaped per content-type) --
    # raw  = the URL-decoded query value '"<b>"' (a quote, <b>, a quote) - the adversarial input.
    # evil = a reflected <script> payload - the XSS lever a non-html/json type must still defuse.
    _treq = {"__method": "GET", "__path": "/api/echo",
             "__query": "name=world&raw=%22%3Cb%3E%22"
                        "&evil=%3Cscript%3Ealert(1)%3C%2Fscript%3E"}
    _json_ct = "application/json; charset=utf-8"
    _html_ct = "text/html; charset=utf-8"
    _text_ct = "text/plain; charset=utf-8"
    _svg_ct = "image/svg+xml"
    _js_ct = "application/javascript"
    for text, ctype, want in [
        ("no tokens here", _json_ct, "no tokens here"),
        ("{{method}}", _json_ct, "GET"),
        ("path={{path}}", _text_ct, "path=/api/echo"),
        ("{{ method }}", _json_ct, "GET"),               # surrounding space is trimmed
        ("{{query.name}}", _text_ct, "world"),
        ("{{unknown}}", _json_ct, ""),                   # unknown token -> empty
        ("{{now}}", _json_ct, ""),                       # clock token -> empty in this mirror
        ("a {{method}} b {{path}} c", _text_ct, "a GET b /api/echo c"),   # multiple tokens
        ("{{oops", _json_ct, "{{oops"),                  # unterminated -> emitted literally
        ("x {{oops y", _text_ct, "x {{oops y"),
        # -- the security core: a reflected value can NEVER break out of the body --
        ('{"q":"{{query.raw}}"}', _json_ct, '{"q":"\\"<b>\\""}'),   # json: quotes escaped
        ("<p>{{query.raw}}</p>", _html_ct, "<p>&quot;&lt;b&gt;&quot;</p>"),  # html: <>" escaped
        ("v={{query.raw}}", _text_ct, "v=&quot;&lt;b&gt;&quot;"),   # plain: HTML-escaped (deny)
        # -- default-deny: svg / xml / js types escape markup too, so no reflected <script> runs --
        ("<svg>{{query.evil}}</svg>", _svg_ct,
           "<svg>&lt;script&gt;alert(1)&lt;/script&gt;</svg>"),
        ("cb({{query.raw}})", _js_ct, "cb(&quot;&lt;b&gt;&quot;)"),
        # no __params on this request (an exact route): a param token is simply empty
        ("{{param.name}}", _text_ct, ""),
    ]:
        check("render_template(%r,%s)" % (text, ctype.split(";")[0]),
              render_template(text, _treq, ctype), want)

    # -- :param captures reach a template exactly like query values: escaped per type --
    # A param value is HOSTILE input (it is a request-path segment the visitor chose);
    # it rides __params and goes through the same default-deny escaping as everything else.
    _preq = {"__method": "GET", "__path": "/api/greet/x", "__query": "",
             "__params": {"name": "world", "q": '"<b>"',
                          "evil": "<script>alert(1)</script>"}}
    for text, ctype, want in [
        ("hello {{param.name}}", _text_ct, "hello world"),
        ("{{ param.name }}", _json_ct, "world"),                 # trimmed like any token
        ("{{param.missing}}", _json_ct, ""),                     # absent capture -> empty
        ('{"who":"{{param.q}}"}', _json_ct, '{"who":"\\"<b>\\""}'),   # json-escaped
        ("<p>{{param.evil}}</p>", _html_ct, "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"),
        ("<svg>{{param.evil}}</svg>", _svg_ct,
           "<svg>&lt;script&gt;alert(1)&lt;/script&gt;</svg>"),  # default-deny holds
        ("v={{param.q}}", _text_ct, "v=&quot;&lt;b&gt;&quot;"),
    ]:
        check("render_template param(%r,%s)" % (text, ctype.split(";")[0]),
              render_template(text, _preq, ctype), want)

    # -- render-size cap: a token-saturated body x a huge value stays bounded (no unbounded build) --
    _cap_req = {"__query": "big=" + ("x" * 200000)}      # one ~200 KB reflected value
    _capped = render_template("{{query.big}}" * 60, _cap_req, "text/plain")
    check("render_template cap len", len(_capped), _RENDER_MAX)

    if _fail:
        print("fileserver_golden: FAIL\n" + "\n".join(_fail))
        return 1
    print("fileserver_golden: OK (range parse, traversal guard, MIME, icon classify, "
          "HTML escape, capability gate, SPA fallback, HTTP framing, keep-alive req "
          "length, JSON escape, editor confinement, LAN-first gate, query parse, size "
          "probe, filename sanitise, rate + ETA format, HTTP-date, Allow header, "
          "editor login backoff, user-route path + header sanitise, template render + "
          "escape, CORS preflight, conditional-GET ETag, shared file-head plan, "
          "redirect mount re-prefix, editor parent-dirs, param patterns + reserved "
          "backstop + pattern Allow/preflight, reserved-namespace predicate, HEAD route "
          "lookup, one-shot text reply + HEAD body suppression all match)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
