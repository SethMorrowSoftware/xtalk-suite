#!/usr/bin/env python3
"""check-script-vectors.py - RUN the shipped signaling parse boundary of
examples/datachannel-dht-chat.livecodescript headlessly, against
tests/dht_signal_golden.py's mirrors.

WHY THIS EXISTS. The suite work plan's datachannelxt coding #9 (2026-09-27): the
dht-chat took whatever preceded the first LF of a signaling body as the offer's nonce,
and its dedup compares ("n" & nonce) with the last one answered. A letter prefix keeps
`is` off its number path only for hex, and a nonce "an" spells "nan", a NaN to C's
strtod, equal to nothing, itself included (the suite's engine note 2.11): the same
offer was re-answered, and the peer rebuilt, on every DHT delivery. The fix is
wxNonceValid at the split in wxApplyRemote (8 lowercase hex, what wxRandomNonce mints).
Until this file nothing but the static checker had read the demo, and the checker
cannot tell whether a nonce is refused before or after it is compared. The family
closed that gap member by member with gates of this shape (coinxt, nostrxt, riptide,
nocloud, holde-em, torrentxt); this is datachannelxt's, and it holds four things to the
golden's mirrors, each on the golden's own rows:

  1. wxNonceValid        against nonce_valid(), on NONCE_ROWS.
  2. wxRandomNonce       64 draws, each 8 characters and accepted by BOTH the script's
                         wxNonceValid and the mirror: the minting side and the checking
                         side agree, so the fix can never refuse the demo's own offers.
  3. the JOIN side       every JOIN_SEQUENCES delivery list, each body compressed and
                         handed to the real wxApplyRemote (which calls wxApplyOffer): the
                         offers ANSWERED (a dcSetRemoteDescription of type "offer", with
                         the nonce the script stored) must equal join_answers(), one
                         dcCreatePeer per answer, and a refused blob changes no state.
  4. the HOST side       every HOST_SEQUENCES list through wxApplyRemote -> wxApplyAnswer
                         under the row's current offer nonce: the answers APPLIED must
                         equal host_applies(). Two rows in 3 and 4 give two DIFFERENT
                         nonces that one number reads the same (00000001, 1e000000), so
                         the 2026-09-25 letter prefix on both compares is held too.
  5. the CHUNK LIST      every FETCH_SEQUENCES list of "C" heads through the real
                         wxTryHead: the lists that START a fetch (btDhtGetImmutable once
                         per target) must equal fetches(). Two one-chunk lists that one
                         number reads the same (both +inf, both 1) are two fetches.

A comparison the family interpreter REFUSES (LCS.Indistinct: one the engine answers
differently from the model, engine notes 2.10 and 2.11) FAILS A ROW OF ITS OWN, named
by the call, and the run goes on: before the fix the second delivery of the "an" offer
is exactly such a comparison ("nan" is "nan"), and the fixture test needs its name.

WHAT IT IS NOT. An approximation of the engine, not the engine: riptide's runner over
the family interpreter. It settles LOGIC, not parser behaviour, and promotes nothing
past "verified statically; needs an OXT pass". If this gate and the engine disagree,
the engine is right.

THE MODEL'S STAND-INS, declared rather than discovered:
  - `decompress` is gzip's (the engine's compress writes gzip data); the gate builds
    each blob with gzip.compress of the body's UTF-8 bytes, so only the round trip is
    modelled, and a blob that does not decompress takes the script's own catch.
  - DataChannelXT is absent from a headless run, so its four calls here are recorded:
    dcCreatePeer answers a fresh positive handle, dcSetRemoteDescription 0, dcLastError
    empty, and the statement `dcFreePeer(sPeer)` is intercepted. TorrentXT's
    btDhtGetImmutable (wxTryHead's fetch) is recorded the same way. None decides a
    row's outcome except as recorded.
  - The two fields the path touches ("wxIce", read by wxIceServers; "wxLog", written by
    wxLog) are created in the runner's world, so the script's own handlers run; the
    delayed `send "wxGatherWatch"` is queued by the runner and never delivered.

THE SIBLINGS, AND HOW THEY ARE FOUND (docs/MEMBER-REPO-SPLIT.md in the suite): riptide
for the runner, which loads nostrxt's interpreter and oracle at import, so nostrxt is
needed too (tools/member-registry.py). sibling() below resolves each: the directory
beside this member in the suite tree, the repository cloned beside it in a standalone
checkout, or wherever XTALK_SIBLING_<NAME> / XTALK_SIBLINGS point. An absent runner
stops the gate (exit 2, the clone to run).

tools/test-script-vectors.py edits one defect at a time into a copy of the demo and
requires this gate to fail naming it; a gate that went blind would otherwise print OK.

Usage:
  python3 tools/check-script-vectors.py                # per-section detail
  python3 tools/check-script-vectors.py --check        # terse (run-gates.sh)
  python3 tools/check-script-vectors.py --demo PATH    # drive a copy
"""
import gzip
import importlib.util
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)


def sibling(name):
    """Path of a sibling member's checkout (docs/MEMBER-REPO-SPLIT.md): the
    directory beside this member in the suite tree, or the repository cloned
    beside it in a standalone checkout. XTALK_SIBLING_<NAME> (one member) and
    XTALK_SIBLINGS (a directory holding them all) override, in that order. A
    member is never its own sibling."""
    if name == os.path.basename(MEMBER):
        return MEMBER
    one = os.environ.get("XTALK_SIBLING_" + name.upper().replace("-", "_"))
    if one:
        return one
    return os.path.join(os.environ.get("XTALK_SIBLINGS")
                        or os.path.dirname(MEMBER), name)


DEMO = os.path.join(MEMBER, "examples", "datachannel-dht-chat.livecodescript")
GOLDEN = os.path.join(MEMBER, "tests", "dht_signal_golden.py")
RUNNER = os.path.join(sibling("riptide"), "tools", "check-demo-boot.py")
if not os.path.isfile(RUNNER):
    print("check-script-vectors: %s is not present: it belongs to the riptide member, "
          "which is not beside this checkout. Clone "
          "https://github.com/SethMorrowSoftware/RipTide beside this checkout as "
          "../riptide (with https://github.com/SethMorrowSoftware/NostrXT as ../nostrxt, "
          "which the runner loads), or point XTALK_SIBLING_RIPTIDE / XTALK_SIBLINGS at "
          "them." % RUNNER, file=sys.stderr)
    sys.exit(2)

# Per-section ratchets, not targets: a section that ran fewer rows than its floor
# silently stopped executing part of itself (a row list that went empty, a loop that no
# longer iterates), and the run must fail, not print OK. Measured 2026-09-27.
FLOORS = {"wxNonceValid": 29, "wxRandomNonce": 64, "join": 42, "host": 24,
          "fetch": 12}


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DB = _load("dc_demo_boot", RUNNER)
LCS = DB.LCS
G = _load("dc_signal_golden", GOLDEN)


def boolish(v):
    if isinstance(v, bool):
        return v
    return str(v).lower() == "true"


def to_str(b):
    return bytes(b).decode("latin-1")


def blob(body):
    """What wxApplyRemote receives: the body's UTF-8 bytes, compressed."""
    return to_str(gzip.compress(body.encode("utf-8")))


# --------------------------------------------------------------------------
# the model's stand-ins (see the header)

class DcInterp(DB.DemoInterp):
    def __init__(self, src, world):
        self.dc = []            # (call, args) for every DataChannelXT call recorded
        self.next_peer = 40
        super().__init__(src, world)

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        m = re.match(r'dcFreePeer\s*\((.*)\)\s*$', line, re.I)
        if m:
            self.dc.append(("dcFreePeer", [LCS._disp(self.eval_expr(m.group(1), env))]))
            return i + 1
        return super()._exec_stmt(body, i, env)


def install(ip):
    def create_peer(a):
        ip.next_peer += 1
        ip.dc.append(("dcCreatePeer", [str(LCS._disp(x)) for x in a]))
        return ip.next_peer

    def set_remote(a):
        ip.dc.append(("dcSetRemoteDescription", [str(LCS._disp(x)) for x in a]))
        return 0

    def decompress(a):
        try:
            return to_str(gzip.decompress(str(LCS._disp(a[0])).encode("latin-1")))
        except (OSError, EOFError, ValueError):
            raise LCS.Thrown("decompress: not compressed data")

    def get_immutable(a):
        ip.dc.append(("btDhtGetImmutable", [str(LCS._disp(x)) for x in a]))
        return 0

    LCS.HASHES["btdhtgetimmutable"] = get_immutable
    LCS.HASHES["dccreatepeer"] = create_peer
    LCS.HASHES["dcsetremotedescription"] = set_remote
    LCS.HASHES["dclasterror"] = lambda a: ""
    LCS.HASHES["decompress"] = decompress


def field(world, name, text):
    ctl = world.create("field")
    ctl.name = name
    ctl.content = text
    return ctl


def load_demo(path, sandbox):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)
    world = DB.World(sandbox)
    DB.install_engine_functions(world)
    ip = DcInterp(src, world)
    install(ip)
    field(world, "wxIce", "stun:stun.l.google.com:19302")
    field(world, "wxLog", "")
    return ip


# --------------------------------------------------------------------------
# the checker

class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.n = 0
        self.failed = []
        self.counts = {}
        self.key = None

    def section(self, key, text):
        self.key = key
        self.counts.setdefault(key, 0)
        if not self.terse:
            print("-- %s" % text)

    def ck(self, label, got, want):
        self.n += 1
        if self.key is not None:
            self.counts[self.key] += 1
        if got != want:
            self.failed.append("%s:\n    script %r\n    mirror %r" % (label, got, want))

    def short(self):
        return ["%s ran %d rows (floor %d)" % (k, n, FLOORS[k])
                for k, n in sorted(self.counts.items()) if n < FLOORS[k]]


REFUSED = "REFUSED by the family interpreter (LCS.Indistinct)"


def named_call(c, ip, label, name, args):
    """ip.call, bar two things. A comparison the interpreter REFUSES fails a row of its
    own, named by `label` (the refusal is never a pass, and a row reading the value
    through a filter could let one through), and answers REFUSED. A handler the demo no
    longer has fails a row too, so a rename cannot turn a section into a no-op."""
    try:
        return ip.call(name, args)
    except LCS.Indistinct as exc:
        c.ck("%s: a comparison REFUSED by the family interpreter" % label,
             "%s: %s" % (REFUSED, str(exc)[:200]), "an answer")
        return REFUSED
    except NameError as exc:
        c.ck("%s: the demo's %s" % (label, name), "missing (%s)" % exc, "present")
        return REFUSED


# --------------------------------------------------------------------------
# 1-2. the nonce predicate and the minting side

def check_nonce(c, ip):
    c.section("wxNonceValid", "wxNonceValid against nonce_valid(), on NONCE_ROWS")
    for text, _ in G.NONCE_ROWS:
        label = "wxNonceValid(%r)" % text
        c.ck(label, boolish(named_call(c, ip, label, "wxNonceValid", [text])),
             G.nonce_valid(text))
    c.section("wxRandomNonce", "wxRandomNonce: every nonce minted passes both checks")
    for n in range(64):
        label = "wxRandomNonce draw %d" % (n + 1)
        got = str(LCS._disp(named_call(c, ip, label, "wxRandomNonce", [])))
        c.ck(label + " is accepted by the script's wxNonceValid and the mirror",
             (len(got), boolish(named_call(c, ip, label, "wxNonceValid", [got])),
              G.nonce_valid(got)), (8, True, True))


# --------------------------------------------------------------------------
# 3-4. the two sides of the handshake, through the real wxApplyRemote

STATE = ("srole", "speer", "schan", "snonce", "sseenoffernonce", "sseenanswernonce",
         "sphase", "sfetchtargets", "sfetchhave", "sfetchtries")


def reset(ip, role, current=""):
    for name in STATE:
        ip.globals[name] = ""
    ip.globals["srole"] = role
    ip.globals["snonce"] = current
    if role == "host":
        ip.globals["speer"] = 7            # the host's own offer peer, already made
        ip.globals["sphase"] = "waiting-answer"
    ip.dc = []
    ip.world.sends = []


def deliver(c, ip, label, bodies, role):
    """Hand each body to wxApplyRemote; answer the (nonce, sdp) acted on, in order,
    reading the nonce the script STORED for the one it acted on."""
    kind = "offer" if role == "join" else "answer"
    stored = "sseenoffernonce" if role == "join" else "sseenanswernonce"
    acted = []
    for n, body in enumerate(bodies):
        before = len(ip.dc)
        named_call(c, ip, "%s delivery %d" % (label, n + 1), "wxApplyRemote", [blob(body)])
        for call, args in ip.dc[before:]:
            if call == "dcSetRemoteDescription" and len(args) == 3 and args[2] == kind:
                acted.append((str(LCS._disp(ip.globals.get(stored, ""))), args[1]))
    return acted


def check_join(c, ip):
    c.section("join", "the join side: wxApplyRemote -> wxApplyOffer, against "
              "join_answers()")
    for label, bodies in G.JOIN_SEQUENCES:
        tag = "join: " + label
        reset(ip, "join")
        want = G.join_answers(bodies)
        got = deliver(c, ip, tag, bodies, "join")
        c.ck(tag + ": the offers answered", got, want)
        c.ck(tag + ": one peer made per answer",
             sum(1 for call, _ in ip.dc if call == "dcCreatePeer"), len(want))
        c.ck(tag + ": the nonce left stored",
             str(LCS._disp(ip.globals.get("sseenoffernonce", ""))),
             want[-1][0] if want else "")


def check_host(c, ip):
    c.section("host", "the host side: wxApplyRemote -> wxApplyAnswer, against "
              "host_applies()")
    for label, current, bodies in G.HOST_SEQUENCES:
        tag = "host: " + label
        reset(ip, "host", current)
        want = G.host_applies(bodies, current)
        got = deliver(c, ip, tag, bodies, "host")
        c.ck(tag + ": the answers applied", got, want)
        c.ck(tag + ": the host's own nonce untouched",
             str(LCS._disp(ip.globals.get("snonce", ""))), current)
        c.ck(tag + ": no peer made on the host side",
             sum(1 for call, _ in ip.dc if call == "dcCreatePeer"), 0)


def check_fetch(c, ip):
    c.section("fetch", "a chunk-list head: wxTryHead, against fetches()")
    for label, lists in G.FETCH_SEQUENCES:
        tag = "fetch: " + label
        reset(ip, "join")
        ip.globals["ssession"] = 3
        started = []
        for n, lst in enumerate(lists):
            before = len(ip.dc)
            named_call(c, ip, "%s head %d" % (tag, n + 1), "wxTryHead",
                       ["DXC1C" + to_str(lst.encode("utf-8"))])
            got = [args[1] for call, args in ip.dc[before:] if call == "btDhtGetImmutable"]
            if got:
                started.append(",".join(got))
        want = G.fetches(lists)
        c.ck(tag + ": the lists that started a fetch", started, want)
        c.ck(tag + ": the list left running",
             str(LCS._disp(ip.globals.get("sfetchtargets", ""))), want[-1] if want else "")


# --------------------------------------------------------------------------

def main(argv):
    terse = "--check" in argv
    args = [a for a in argv[1:] if a != "--check"]
    demo = DEMO
    while args:
        if len(args) >= 2 and args[0] == "--demo":
            demo = args[1]
        else:
            print("usage: check-script-vectors.py [--check] [--demo PATH]")
            return 2
        args = args[2:]
    c = Checker(terse)
    sandbox = tempfile.mkdtemp(prefix="datachannelxt-vectors-")
    try:
        ip = load_demo(demo, sandbox)
        check_nonce(c, ip)
        check_join(c, ip)
        check_host(c, ip)
        check_fetch(c, ip)
    finally:
        import shutil
        shutil.rmtree(sandbox, ignore_errors=True)
    if c.failed:
        print("check-script-vectors: FAIL (%d of %d)\n%s"
              % (len(c.failed), c.n, "\n".join(c.failed)))
        return 1
    short = c.short()
    if short:
        print("check-script-vectors: FAIL - a section stopped executing: "
              + "; ".join(short))
        return 1
    print("check-script-vectors: OK (%d checks: %s)"
          % (c.n, ", ".join("%s %d" % kv for kv in sorted(c.counts.items()))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
