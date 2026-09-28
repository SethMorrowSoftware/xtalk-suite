#!/usr/bin/env python3
"""check-transport-holds.py - DRIVE the windows outside the suite paste that
take a process-wide transport hold, headlessly, beside ANOTHER stack that
holds one too: enetxt's own enet-selftest, the suite closing pass, and
enetxt's two chat demos (since the review of 2026-09-27).

WHY THIS EXISTS
---------------
ENet's initialisation belongs to the whole PROCESS. enetxt's shim refcounts
enInitialize and enDeinitialize (enx_initialize / enx_deinitialize over
g_init_count, enetxt/src/enet_shim.cpp), and the deinitialize that takes the
count to zero destroys EVERY live host in the process, whichever stack made
it. DataChannel's is worse: dcCleanup frees every peer and channel in the
process however many dcInit calls came first. So a window beside another may
give back only the holds it took. The suite paste learned that on 2026-09-25
(work plan suite-wide #16: it counts its holds through suEnInit / suEnRelease
and suDcInit / suDcRelease, driven by tools/check-suite-ui-boot.py), and the
same day's interpreter probes found the two other windows that did not:

  enet-selftest   (work plan enetxt #4) a run took two holds and gave back
                  two, and then stCleanup gave back a THIRD on every close
                  and every Re-run - the probe read the count 1, 3, 1, 0,
                  and the other stack's host was gone.
  closing pass    (work plan suite-wide #20) closeStack called enDeinitialize
                  bare whether or not leg B ever ran (a close with leg B
                  never run took no hold, gave one back, and the other
                  stack's host was lost); cpBStart's "already hosting"
                  refusal came after its enInitialize; and dcCleanup was
                  gated on a flag a refused dcInit set too.

Both were fixed on 2026-09-26 the paste's way: a count only two handlers
write, a release that gives back exactly that count, a refused init counted
as none. This gate is what holds them to it. Neither window is in the paste,
so check-suite-ui-boot.py never saw them.

The adversarial review of that fix (2026-09-27) drove the two ENet chat
demos the same way, which the enetxt #4 row had called paired ("their only
unpaired path is a re-fired openStack", a leak that harms no other window),
and found the defect itself: ecStart / eiStart exited on a REFUSED
enInitialize while ecStop / eiStop called enDeinitialize on every close, so a
close after a refusal (or with the start never reached, or a second close)
gave back another window's hold and ended its host. Each now takes at most
ONE hold, flagged by sHaveEn, and gives back only that one; they are driven
here too.

WHAT IT DOES
------------
TWO HALVES, because a drive sees only the paths it drives.

  ROUTING (static, every path). In each file, comments stripped and string
  literals blanked (a literal counts on a do / send / dispatch / call /
  value line, where it is how a name becomes a call - check-suite-
  selftest.py check 18's rule, and its scanner), each library call sits
  only in its counted wrapper, each count is named only by its own
  handlers (and outside every handler only by a bare `local`), and each
  wrapper is defined once and does make its call (so the rule is not
  vacuous). enet-selftest's no-op leg is the one declared exception: it
  calls enDeinitialize where the shim has just answered that the count is
  zero (below).

  THE DRIVE. Each file is loaded - the whole file, the text a maintainer
  pastes - into riptide's stack runner (riptide/tools/check-demo-boot.py,
  over the family interpreter), with check-suite-ui-boot.py's board
  surface (the timer queue, `cancel`, statement-position extension
  commands) and its two library models: ENet's refcount, where the
  deinitialize that reaches zero destroys every host, and DataChannel's
  uncounted cleanup. Another stack holds ENet once with a live host of its
  own, and has a live DataChannel peer. Every scenario is a FRESH window
  (a new interpreter, so fresh script locals, as on a new open), and at
  each step the other stack's hold and host survive and the window gives
  back EXACTLY the holds it took: a refused init is none, a close with
  nothing run gives back none.

  enet-selftest   open and run to its finish (the model delivers no event,
                  so the async loopback meets its deadline, as on a machine
                  with blocked loopback UDP: runbook trap 5.5), then a close
                  at rest; Re-run at rest and Re-run mid-run; a close
                  mid-run; the same run ALONE, where the no-op leg runs
                  (the shim refuses a probe host, so the count is known to
                  be zero) and beside the other stack, where it SKIPs and
                  its probe host is destroyed, or where the probe is refused
                  for another reason (it SKIPs and makes no call); a run
                  whose every enInitialize is refused while the other stack
                  takes a hold mid-run; and a close after a run that threw
                  because the extension is absent. The report must carry exactly
                  one FAIL line (the deadline) and the release's PASS.
  closing pass    open and close with no leg run; leg B's Host, pressed
                  once and twice (the second refused before any hold);
                  Join with an address and with none; a refused
                  enInitialize while the other stack then takes a hold;
                  enetxt absent; leg A run and closed twice; leg A on a
                  refused dcInit; leg E's Host (a minimal TorrentXT model:
                  a session, a keypair) and a close.
  chat demos      enet-lan-chat and enet-internet-chat, each through its
                  start handler (the one line of openStack that takes a
                  hold; the window build and the boot self-check around it
                  are not driven) and its real closeStack: start and close,
                  a second close, a reopen and its close; a re-fired
                  openStack (two starts, one hold); a close with the start
                  never reached; a refused enInitialize while the other
                  stack then takes a hold; enetxt absent.

THE MODEL, beyond check-suite-ui-boot.py's
------------------------------------------
Named, so the divergences are read rather than discovered; each is counted
and must fire, the family's rule for a model hook.

  hold-ledger     EnetHolds keeps, beside the refcount, how many holds the
                  window still has by the model's own count, and sorts
                  every deinitialize: one that gives back the window's own
                  hold, one at a process count of zero (harmless: the
                  shim's `g_init_count <= 0` guard), and one that takes a
                  hold the window never had (STOLEN - the defect).
  enet-surface    the calls the sync half makes, each answering as the shim
                  does for the case the harness drives: a stale handle is
                  ENX_ERR_STALE (-2), channel 5 of 2 is ENX_ERR_ARG (-3),
                  60001 bytes is ENX_ERR_TOO_LARGE (-4), a peer record is
                  not modelled (empty), a live host's record counts no
                  peers, and host creation at a count of zero is refused
                  with enx_last_error "call enInitialize first".
  strict-integer  an EMPTY or non-integer value into a typed Integer
                  parameter THROWS, as the engine does (engine note 6.4),
                  so an unguarded teardown cannot pass here.
  hostname        `the hostName` answers a fixed name and hostNameToAddress
                  a private address (leg B's host path lists them).
  torrent         leg E's minimal TorrentXT: btStartSession answers a
                  handle and btDhtKeypair a seed; the configuration commands
                  answer 0, and starts and stops are counted.

WHAT IT CANNOT SEE
------------------
PARSING (the interpreter reads a wider language than OXT compiles; the
static gate owns that), MESSAGE DELIVERY (timers fire when this file says
so), RENDERING, and every event path: no connect, receive or disconnect
ever arrives, so enet-selftest's loopback always meets its deadline and the
closing pass's legs never complete. It settles the LOGIC of who gives back
which hold, and it upgrades no honesty label: every window's hold handling
here is "verified statically; needs an OXT pass".

Usage:
  python3 tools/check-transport-holds.py              # the gate
  python3 tools/check-transport-holds.py --verbose    # every check printed
  python3 tools/check-transport-holds.py --selftest PATH --closing PATH
          --lanchat PATH --netchat PATH               # mutated copies
                                                      # (tools/test-transport-holds.py)
"""

import collections
import importlib.util
import os
import re
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SELFTEST = os.path.join(ROOT, "enetxt", "tests", "enet-selftest.livecodescript")
CLOSING = os.path.join(ROOT, "tests", "suite-closing-pass.livecodescript")
LANCHAT = os.path.join(ROOT, "enetxt", "examples",
                       "enet-lan-chat.livecodescript")
NETCHAT = os.path.join(ROOT, "enetxt", "examples",
                       "enet-internet-chat.livecodescript")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# ONE board surface and ONE pair of library models: check-suite-ui-boot.py's
# (its SuiteInterp, EnetModel, DcModel and install_transports), and ONE
# scanner: check-suite-selftest.py's (the generator's comment stripper, its
# literal blanker and handler spans). A root tool reaches into a member
# directly; only a member's own tools go through sibling().
UB = _load("check_suite_ui_boot", os.path.join(HERE, "check-suite-ui-boot.py"))
CSS = _load("check_suite_selftest", os.path.join(HERE, "check-suite-selftest.py"))
DB, LCS = UB.DB, UB.LCS
Thrown = LCS.Thrown

DELTAS = collections.OrderedDict([
    ("hold-ledger", "every deinitialize sorted: own, harmless at zero, stolen"),
    ("enet-surface", "the sync half's calls answer as the shim does"),
    ("strict-integer", "empty into a typed Integer parameter throws"),
    ("hostname", "the hostName and hostNameToAddress"),
    ("torrent", "leg E's minimal TorrentXT session and keypair"),
])
FIRED = collections.Counter()


def fire(name):
    FIRED[name] += 1


# ==========================================================================
# the routing half (static)
# ==========================================================================

# (label, path key, {library call: handlers allowed to make it},
#  {count: handlers allowed to name it})
ROUTING = (
    ("enet-selftest", "selftest",
     {"enInitialize": ("stEnInit",),
      # stEnNoOpLeg: the declared exception, a call where the shim has
      # just refused a probe host, so the process count is zero
      "enDeinitialize": ("stEnRelease", "stEnNoOpLeg")},
     {"sStEnHeld": ("stEnInit", "stEnRelease")}),
    ("closing pass", "closing",
     {"enInitialize": ("cpEnInit",), "enDeinitialize": ("cpEnRelease",),
      "dcInit": ("cpDcInit",), "dcCleanup": ("cpDcRelease",)},
     {"sCpEnHeld": ("cpEnInit", "cpEnRelease"),
      "sCpDcHeld": ("cpDcInit", "cpDcRelease", "cpHoldsDc")}),
    # The chat demos take at most ONE hold, so their count is the flag
    # sHaveEn, which other handlers READ (the Host / Join guards, the boot
    # self-check); the count half does not apply, the call half does.
    ("enet-lan-chat", "lanchat",
     {"enInitialize": ("ecStart",), "enDeinitialize": ("ecStop",)}, {}),
    ("enet-internet-chat", "netchat",
     {"enInitialize": ("eiStart",), "enDeinitialize": ("eiStop",)}, {}),
)
STRINGY = re.compile(r'\b(?:do|send|dispatch|call)\b|\bvalue\s*\(', re.I)
DECL = re.compile(r'^\s*local\s+[\w\s,]*$', re.I)


def check_routing(c, label, path, calls, counts):
    c.section("routing: %s" % label)
    text = open(path, encoding="utf-8").read()
    bare = CSS.strip_comments(text, os.path.relpath(path, ROOT)).split("\n")
    blank = [CSS.blank_literals(ln) for ln in bare]
    raw = text.split("\n")
    spans, open_name = CSS.handler_spans(bare)
    if not c.ck("every handler in %s ends" % label, open_name is None,
                "handler %s never ends" % open_name):
        return
    by_name = collections.defaultdict(list)
    for name, a, b in spans:
        by_name[name.lower()].append((a, b))

    def rows_naming(word, a, b):
        rx = re.compile(r'\b' + word + r'\b', re.I)
        return [i for i in range(a + 1, b)
                if rx.search(blank[i])
                or (rx.search(bare[i]) and STRINGY.search(blank[i]))]

    for lib, allowed in calls.items():
        low = {h.lower() for h in allowed}
        outside = [(name, i) for name, a, b in spans
                   if name.lower() not in low
                   for i in rows_naming(lib, a, b)]
        c.eq("%s is called only by %s" % (lib, " and ".join(allowed)),
             ["%s (line %d: %s)" % (n, i + 1, raw[i].strip())
              for n, i in outside], [])
        for h in allowed:
            defs = by_name.get(h.lower(), [])
            c.eq("%s is defined exactly once" % h, len(defs), 1)
            if len(defs) == 1:
                a, b = defs[0]
                c.ck("%s calls %s (so this rule checks something)" % (h, lib),
                     bool(rows_naming(lib, a, b)))
    inside = set()
    for _name, a, b in spans:
        inside.update(range(a, b + 1))
    for var, allowed in counts.items():
        low = {h.lower() for h in allowed}
        rx = re.compile(r'\b' + var + r'\b', re.I)
        outside = [(name, i) for name, a, b in spans
                   if name.lower() not in low
                   for i in rows_naming(var, a, b)]
        c.eq("%s is named only by %s" % (var, ", ".join(allowed)),
             ["%s (line %d: %s)" % (n, i + 1, raw[i].strip())
              for n, i in outside], [])
        decls = [i for i, ln in enumerate(blank)
                 if i not in inside and rx.search(ln)]
        c.eq("%s is declared once, a bare `local` with no initial value"
             % var, [raw[i].strip() for i in decls
                     if not DECL.match(blank[i])], [])
        c.eq("%s is declared exactly once" % var, len(decls), 1)


# ==========================================================================
# the model
# ==========================================================================

def _int(v, what):
    """A typed Integer parameter: the engine throws on empty or a non-integer
    (engine note 6.4); the model does too."""
    fire("strict-integer")
    s = str(LCS._disp(v)).strip()
    if not re.match(r'^-?\d+$', s):
        raise Thrown("%s: type conversion error (%r into Integer)" % (what, s))
    return int(s)


class EnetHolds(UB.EnetModel):
    """check-suite-ui-boot.py's ENet refcount (a deinitialize that reaches
    zero destroys every host) plus the hold ledger and the sync half's calls
    (see the header's hold-ledger and enet-surface)."""

    def __init__(self, other=1, init_fails=False):
        super().__init__(other=other, init_fails=init_fails)
        self.own = 0            # the window's holds outstanding, by the model
        self.stolen = 0         # deinitializes that took a hold it never had
        self.noop = 0           # deinitializes at a process count of zero
        self.last_error = ""
        self.peers = {}         # peer handle -> host handle
        self.probe_refusals = 0
        # set by a scenario: host creation refused for ANOTHER reason while
        # ENet is held (the shim's "enet_host_create failed ..." path)
        self.create_refusal = None

    def other_takes_a_hold(self):
        """Another stack initializes ENet and makes a host of its own."""
        self.count += 1
        self.hosts[self._mint()] = "other"

    def initialize(self, a):
        fire("hold-ledger")
        r = super().initialize(a)
        if r == 0:
            self.own += 1
        else:
            self.last_error = "enet_initialize failed"
        return r

    def deinitialize(self, a):
        fire("hold-ledger")
        if self.count <= 0:
            self.noop += 1
        elif self.own > 0:
            self.own -= 1
        else:
            self.stolen += 1
        return super().deinitialize(a)

    def create_host(self, a, n):
        for k in range(n):
            _int(a[k], "enHostCreate*")
        if self.create_refusal is not None and self.count > 0:
            fire("enet-surface")
            self.attempts += 1
            self.last_error = self.create_refusal
            return 0
        h = super().create(a)
        if h == 0:
            fire("enet-surface")
            self.last_error = "call enInitialize first"
            self.probe_refusals += 1
        return h

    def connect(self, a):
        host = _int(a[0], "enConnect")
        _int(a[2], "enConnect")
        if host not in self.hosts:
            return 0
        p = self._mint()
        self.peers[p] = host
        return p

    def destroy(self, a):
        h = _int(a[0], "enHostDestroy")
        self.hosts.pop(h, None)
        for p in [p for p, host in self.peers.items() if host == h]:
            del self.peers[p]
        return 0

    def deinit_clears_peers(self):
        if self.count == 0:
            self.peers.clear()

    def send(self, a):
        fire("enet-surface")
        p, ch = _int(a[0], "enSend"), _int(a[1], "enSend")
        if p not in self.peers:
            return -2
        if len(str(LCS._disp(a[2]))) > 60000:
            return -4
        if not 0 <= ch < 2:
            return -3
        return 0

    def peer_op(self, a):
        fire("enet-surface")
        return 0 if _int(a[0], "enPeer*") in self.peers else -2

    def host_op(self, a):
        fire("enet-surface")
        return 0 if _int(a[0], "enHost*") in self.hosts else -2

    def host_status(self, a):
        fire("enet-surface")
        h = _int(a[0], "enHostStatus")
        if h not in self.hosts:
            return {}
        return LCS.LcsArray({"peerCount": 0, "address": "127.0.0.1:27098"})

    def peer_status(self, a):
        fire("enet-surface")
        _int(a[0], "enPeerStatus")
        return {}


class DcRefusing(UB.DcModel):
    """DataChannel whose dcInit is REFUSED (a non-zero code, no hold)."""

    def init(self, a):
        return -5


class TorrentModel:
    """Leg E's minimal TorrentXT (the header's `torrent`)."""

    def __init__(self):
        self.sessions = 0
        self.stopped = 0

    def start(self, a):
        fire("torrent")
        self.sessions += 1
        return 7

    def keypair(self, a):
        fire("torrent")
        return LCS.LcsArray({"seed": "ab" * 32, "publicKey": "cd" * 32})

    def stop(self, a):
        fire("torrent")
        self.stopped += 1
        return 0


ENET_NAMES = ("eninitialize", "endeinitialize", "enlibraryversion",
              "enlasterror", "enclearerror", "enhostcreateserver",
              "enhostcreateclient", "enhostdestroy", "enconnect", "ensend",
              "ensendtext", "endisconnect", "endisconnectnow", "enresetpeer",
              "enbroadcast", "enbroadcasttext", "enflush", "ensetpeertimeout",
              "ensetpeerpinginterval", "ensethostbandwidth", "enpeerstatus",
              "enhoststatus", "enpoll")
# The statement-position commands the two windows write, beyond
# check-suite-ui-boot.py's TRANSPORT_COMMANDS. `dcInit` is here because the
# closing pass wrote it bare until 2026-09-26, and the fixture's planted old
# code must reach the model the way the engine would.
COMMANDS = ("enclearerror", "dcinit", "btstopsession", "btsetbool",
            "btdhtaddbootstrap", "btrp1enable")


def install(world, models, torrent=None, enet_absent=False):
    """The two libraries (and leg E's TorrentXT when asked) as modelled
    natives, re-pointed at models["en"] / models["dc"]; returns every name
    installed so the caller removes them."""
    names = UB.install_transports(world, models)
    en = lambda name: (lambda a: getattr(models["en"], name)(a))   # noqa: E731

    def enet_lasterror(a):
        fire("enet-surface")
        return models["en"].last_error

    def enet_clearerror(a):
        fire("enet-surface")
        models["en"].last_error = ""
        return ""

    def deinit(a):
        r = models["en"].deinitialize(a)
        models["en"].deinit_clears_peers()
        return r

    funcs = {
        "endeinitialize": deinit,
        "enlasterror": enet_lasterror,
        "enclearerror": enet_clearerror,
        "enhostcreateserver": lambda a: models["en"].create_host(a[1:], 5),
        "enhostcreateclient": lambda a: models["en"].create_host(a, 4),
        "enconnect": en("connect"),
        "enhostdestroy": en("destroy"),
        "ensend": en("send"),
        "ensendtext": en("send"),
        "endisconnect": en("peer_op"),
        "endisconnectnow": en("peer_op"),
        "enresetpeer": en("peer_op"),
        "ensetpeertimeout": en("peer_op"),
        "ensetpeerpinginterval": en("peer_op"),
        "enbroadcast": en("host_op"),
        "enbroadcasttext": en("host_op"),
        "enflush": en("host_op"),
        "ensethostbandwidth": en("host_op"),
        "enpeerstatus": en("peer_status"),
        "enhoststatus": en("host_status"),
        "dclasterror": lambda a: "dcInit refused (modelled)",
        "specialfolderpath": lambda a: world.special_folder(LCS._disp(a[0])),
        "hostnametoaddress": lambda a: (fire("hostname"), "192.168.1.5")[1],
    }
    if torrent is not None:
        funcs.update({
            "btstartsession": torrent.start,
            "btsetbool": lambda a: 0,
            "btdhtaddbootstrap": lambda a: 0,
            "btrp1enable": lambda a: 0,
            "btdhtkeypair": torrent.keypair,
            "btstopsession": torrent.stop,
            "btpoll": lambda a: {},
            "btrp1poll": lambda a: {},
            "btlistenport": lambda a: 6881,
        })
    LCS.HASHES.update(funcs)
    names = sorted(set(names) | set(funcs))
    world.native_commands = set(UB.TRANSPORT_COMMANDS) | set(COMMANDS)
    if enet_absent:
        # absent means absent in both positions: a function call and a
        # statement-position command each raise the engine's catchable
        # "can't find handler"
        for n in ENET_NAMES:
            LCS.HASHES.pop(n, None)
        world.native_commands -= set(ENET_NAMES)
    return names


class HoldExpr(UB.SuiteExpr):
    """`the hostName` (leg B's host path)."""

    def p_atom(self):
        self.ws()
        m = UB._rxi(r'the\s+hostName\b').match(self.s[self.i:])
        if m:
            self.i += m.end()
            fire("hostname")
            return "modelled-host"
        return super().p_atom()


class HoldInterp(UB.SuiteInterp):
    def eval_expr(self, expr, env):
        return HoldExpr(self, env).parse(expr)


# ==========================================================================
# a window
# ==========================================================================

# The runner's shared spelling rewrites (riptide/tools/check-script-vectors.py
# REWRITES) each file needs, by name, and each REQUIRED to fire, the family's
# rule: a rewrite that stops matching fails the gate rather than leaving it
# reading a file nobody ships. enet-selftest's carried harness scaffold writes
# two one-line `if ... then exit ...` guards (stShow, stPaint), a form the
# interpreter models only as a block; the closing pass needs none.
FILE_REWRITES = {
    "selftest": ("one-line `if ... then STMT` -> block form",),
    "closing": (),
    "lanchat": (),
    "netchat": (),
}


def build_source(path, key, fail):
    """The file the way the runner reads a stack: minus its `script "..."`
    line, with the engine's non-literal-constant refusal and the runner's
    one-line if/else refusal applied (DB.build_source's), and only the shared
    rewrites FILE_REWRITES names for it, each required to fire."""
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    rel = os.path.relpath(path, ROOT)
    src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)
    DB._refuse_nonliteral_constants(src, fail)
    if re.search(r'^\s*if .+ then .+ else ', src, re.M):
        fail("%s: a one-line `if ... then ... else ...` appeared; the runner "
             "would drop its else branch" % rel)
    table = dict((name, fn) for name, _why, fn in DB.CSV.REWRITES)
    wanted = FILE_REWRITES[key]
    unknown = [n for n in wanted if n not in table]
    if unknown:
        fail("FILE_REWRITES names %s, which the runner's shared rewrites no "
             "longer define" % ", ".join(unknown))
    hits = dict((n, 0) for n in wanted)
    out = []
    for line in src.split("\n"):
        for name in wanted:
            new = table[name](line)
            if new != line:
                hits[name] += 1
                line = new
        out.append(line)
    stale = [n for n in wanted if hits[n] == 0]
    if stale:
        fail("%s: the shared rewrite(s) %s matched nothing - stale against "
             "this file; drop them from FILE_REWRITES" % (rel, ", ".join(stale)))
    return "\n".join(out)


class Window:
    """One open window: a fresh interpreter over the file (fresh script
    locals, as on a new open), its world, and the models beside it."""

    def __init__(self, src, sandbox, en=None, dc=None, torrent=None,
                 enet_absent=False):
        self.world = UB.SuiteWorld(tempfile.mkdtemp(dir=sandbox))
        self.ip = HoldInterp(src, self.world)
        UB.install_engine_builtins(self.world)
        self.models = {"en": en or EnetHolds(), "dc": dc or UB.DcModel()}
        self.torrent = torrent
        self.names = install(self.world, self.models, torrent, enet_absent)

    @property
    def en(self):
        return self.models["en"]

    @property
    def dc(self):
        return self.models["dc"]

    def close(self):
        for name in self.names:
            LCS.HASHES.pop(name, None)
        self.world.native_commands = set()

    def g(self, name):
        return self.ip.globals.get(name.lower(), "")

    def held(self, name):
        """A hold count as a number: empty (never written) reads as zero."""
        return int(LCS._n(self.g(name)))

    def call(self, name, args=()):
        return self.ip.call(name, list(args))

    def press(self, name):
        """A click on the control named `name`: mouseUp with `the target`
        set (neither window handles mouseDown)."""
        ctl = self.world.anywhere(name)
        if ctl is None:
            raise RuntimeError("there is no control %r to press" % name)
        self.world.target = (ctl.ctype, ctl.name)
        try:
            self.ip.call("mouseUp", [1])
        finally:
            self.world.target = None

    def text(self, name):
        ctl = self.world.anywhere(name)
        return "" if ctl is None else ctl.content

    def set_text(self, name, value):
        self.world.anywhere(name).content = value

    def pending(self):
        return self.ip.pending_names()


def check_other(c, w, when, dc_lost_ok=False, count=1):
    """The other stack's side after `when`: its hold and host intact, no
    hold taken from it, the window holding nothing and hosting nothing."""
    en, dc = w.en, w.dc
    c.eq("%s: no deinitialize took a hold this window never had" % when,
         en.stolen, 0)
    c.ck("%s: the other stack's ENet host is alive" % when,
         not en.other_host_lost)
    c.eq("%s: the process count is the other stack's alone (%d)"
         % (when, count), en.count, count)
    c.eq("%s: this window holds no ENet hold" % when, en.own, 0)
    c.eq("%s: this window's hosts are destroyed" % when,
         len(en.paste_hosts()), 0)
    c.eq("%s: no dcCleanup without a DataChannel hold of this window's own"
         % when, dc.unpaired, 0)
    if not dc_lost_ok:
        c.ck("%s: the other stack's DataChannel peer is alive" % when,
             not dc.other_peer_lost)


# ==========================================================================
# enet-selftest
# ==========================================================================

DEADLINE_FAIL = "FAIL  async loopback finished before the deadline"


def report_lines(w):
    return LCS._split_chunks(str(w.g("sResultText")), "\n")


def st_finish(c, w, label):
    """Deliver the pump once, then move the clock past the run's deadline
    and deliver every queued message: the loopback meets its deadline (no
    event ever arrives in the model) and the run reaches stFinish."""
    try:
        UB.deliver_next(w.ip, w.world, only=("stPump",))
        w.world.ms = max(w.world.ms, int(LCS._n(w.g("sDeadline"))) + 1)
        UB.deliver_all(w.ip, w.world)
    except Exception as exc:                            # noqa: BLE001
        return c.threw(label, exc)
    return c.eq("%s: the run finished (sPhase done, no timer left)" % label,
                (w.g("sPhase"), w.pending()), ("done", []))


def check_st_report(c, w, when, noop):
    """The report a finished run leaves: the deadline its only FAIL, the
    release's PASS, and the no-op leg as `noop` says ("PASS" or "SKIP")."""
    lines = report_lines(w)
    c.eq("%s: the only FAIL line is the loopback's deadline (the model "
         "delivers no event)" % when,
         [ln for ln in lines if ln.startswith("FAIL")], [DEADLINE_FAIL])
    c.ck("%s: the release asserted, and passed" % when,
         "PASS  enDeinitialize returns 0" in lines,
         [ln for ln in lines if "enDeinitialize" in ln])
    leg = [ln for ln in lines if "extra deinitialize is a no-op 0" in ln]
    c.eq("%s: the no-op leg reads %s" % (when, noop),
         [ln.split()[0] for ln in leg], [noop])


def scenario_selftest(c, src, sandbox):
    # 1. open beside the other stack, the run to its finish, then a close
    c.section("enet-selftest: open, run to the finish, close at rest")
    w = Window(src, sandbox)
    try:
        w.call("openStack")
        c.eq("the run took two holds (stRun's two enInitialize calls) and "
             "counts them", (w.en.own, w.en.count, w.held("sStEnHeld")),
             (2, 3, 2))
        c.eq("the run's loopback made two hosts, its pump queued",
             (len(w.en.paste_hosts()), w.pending()), (2, ["stPump"]))
        if st_finish(c, w, "the first run"):
            check_other(c, w, "after the run's finish")
            c.eq("the finish gave back exactly the run's two",
                 (w.en.gave, w.held("sStEnHeld")), (2, 0))
            check_st_report(c, w, "beside the other stack", "SKIP")
            c.ck("the no-op leg asked the shim with a probe host, and "
                 "destroyed it (another stack holds ENet)",
                 w.en.attempts == 4 and not w.en.paste_hosts())
        w.call("closeStack")
        check_other(c, w, "a close at rest")
        c.eq("a close at rest gave back nothing", w.en.gave, 2)
    finally:
        w.close()

    # 2. Re-run at rest, then Re-run MID-run, then a close mid-run
    c.section("enet-selftest: Re-run at rest, Re-run mid-run, close mid-run")
    w = Window(src, sandbox)
    try:
        w.call("openStack")
        if st_finish(c, w, "the first run"):
            w.press("stRerun")
            c.eq("Re-run at rest gave back nothing and the new run holds two",
                 (w.en.gave, w.en.own, w.en.count), (2, 2, 3))
            if st_finish(c, w, "the re-run"):
                check_other(c, w, "after a Re-run at rest")
        w.call("stRun")
        w.press("stRerun")
        c.eq("Re-run MID-run gave back exactly the live run's two and the "
             "new run holds two", (w.en.gave, w.en.own, w.en.count),
             (6, 2, 3))
        c.eq("... and destroyed the live run's hosts (two left: the new "
             "run's)", len(w.en.paste_hosts()), 2)
        if st_finish(c, w, "the run after a mid-run Re-run"):
            check_other(c, w, "after a Re-run mid-run")
        w.call("stRun")
        w.call("closeStack")
        check_other(c, w, "a close mid-run")
        UB.deliver_all(w.ip, w.world)
        check_other(c, w, "the closed run's queued pump, delivered")
        w.call("closeStack")
        check_other(c, w, "a second close")
    finally:
        w.close()

    # 3. ALONE: the no-op leg runs, at a count the shim says is zero
    c.section("enet-selftest: alone (nobody else holds ENet)")
    w = Window(src, sandbox, en=EnetHolds(other=0))
    try:
        w.call("openStack")
        if st_finish(c, w, "the run alone"):
            check_st_report(c, w, "alone", "PASS")
            c.eq("the no-op leg made its one call at a process count of "
                 "zero, after the shim refused the probe host",
                 (w.en.noop, w.en.probe_refusals, w.en.stolen), (1, 1, 0))
            check_other(c, w, "alone, after the finish", count=0)
        w.call("closeStack")
        check_other(c, w, "alone, a close at rest", count=0)
        c.eq("... and the close made no call", w.en.noop, 1)
    finally:
        w.close()

    # 3b. the probe refused for ANOTHER reason while ENet is held elsewhere:
    # the leg cannot tell the count is zero, so it must not call
    c.section("enet-selftest: the no-op leg's probe refused for another "
              "reason")
    w = Window(src, sandbox)
    try:
        w.call("openStack")
        w.en.create_refusal = ("enet_host_create failed (port in use? too "
                               "many sockets?)")
        if st_finish(c, w, "the run"):
            leg = [ln for ln in report_lines(w)
                   if "extra deinitialize is a no-op 0" in ln]
            c.eq("a probe refused for another reason: the no-op leg SKIPs",
                 [ln.split()[0] for ln in leg], ["SKIP"])
            c.eq("a probe refused for another reason: no call was made "
                 "(none at zero, none stolen)", (w.en.noop, w.en.stolen),
                 (0, 0))
            check_other(c, w, "a probe refused for another reason")
    finally:
        w.close()

    # 4. every enInitialize REFUSED, and the other stack takes a hold mid-run
    c.section("enet-selftest: every enInitialize refused, then another stack "
              "initializes mid-run")
    w = Window(src, sandbox, en=EnetHolds(other=0, init_fails=True))
    try:
        w.call("openStack")
        c.eq("two refused enInitialize calls are counted as no hold",
             (w.en.took, w.held("sStEnHeld")), (0, 0))
        w.en.other_takes_a_hold()
        if st_finish(c, w, "the refused run"):
            check_other(c, w, "the refused run's finish, the other stack "
                              "holding")
        w.call("closeStack")
        check_other(c, w, "the refused run's close")
        c.eq("the refused run gave back nothing at all", w.en.gave, 0)
    finally:
        w.close()

    # 5. the extension ABSENT: the run throws at its first enInitialize
    c.section("enet-selftest: enetxt absent")
    w = Window(src, sandbox, enet_absent=True)
    try:
        threw = None
        try:
            w.call("openStack")
        except Thrown as exc:
            threw = str(exc)
        c.ck("the run throws at enInitialize (the extension is absent)",
             threw is not None and "eninitialize" in threw.lower(), threw)
        try:
            w.call("closeStack")
            c.ck("closeStack after that throws nothing", True)
        except Exception as exc:                        # noqa: BLE001
            c.threw("closeStack after that throws nothing", exc)
        check_other(c, w, "the absent run's close")
    finally:
        w.close()


# ==========================================================================
# the closing pass
# ==========================================================================

def cp_open(c, src, sandbox, label, **kw):
    w = Window(src, sandbox, **kw)
    try:
        w.call("openStack")
    except Exception as exc:                            # noqa: BLE001
        c.threw("%s: openStack runs" % label, exc)
        w.close()
        return None
    return w


def cp_close(c, w, label):
    try:
        w.call("closeStack")
        return True
    except Exception as exc:                            # noqa: BLE001
        return c.threw("%s: closeStack runs" % label, exc)


def scenario_closing(c, src, sandbox):
    c.section("closing pass: open, then close with no leg run")
    w = cp_open(c, src, sandbox, "no leg")
    if w:
        try:
            c.eq("opening took no hold", (w.en.took, w.dc.holding),
                 (0, False))
            if cp_close(c, w, "no leg"):
                check_other(c, w, "a close with no leg run")
                c.eq("the close gave back nothing and called no dcCleanup",
                     (w.en.gave, w.dc.cleanups), (0, 0))
        finally:
            w.close()

    c.section("closing pass: leg B Host, pressed twice, then close")
    w = cp_open(c, src, sandbox, "leg B host")
    if w:
        try:
            w.press("cpBHost")
            c.eq("Host took one hold and made one host",
                 (w.en.took, w.en.own, len(w.en.paste_hosts())), (1, 1, 1))
            UB.deliver_next(w.ip, w.world, only=("cpPump",))
            w.press("cpBHost")
            c.ck("the second press is refused",
                 "already hosting" in w.text("cpBOut"), w.text("cpBOut"))
            c.eq("... BEFORE a hold is taken (one hold, one host)",
                 (w.en.took, len(w.en.paste_hosts())), (1, 1))
            if cp_close(c, w, "leg B host"):
                check_other(c, w, "leg B Host's close")
                c.eq("the close gave back exactly its one", w.en.gave, 1)
            if cp_close(c, w, "leg B host, again"):
                check_other(c, w, "a second close")
        finally:
            w.close()

    c.section("closing pass: leg B Join, with an address and with none")
    w = cp_open(c, src, sandbox, "leg B join")
    if w:
        try:
            w.press("cpBJoin")
            c.ck("Join with no address says so",
                 "enter the host machine's ip first" in w.text("cpBOut"),
                 w.text("cpBOut"))
            w.set_text("cpBAddr", "192.168.1.20:27300")
            w.press("cpBJoin")
            c.eq("Join made a client host and connected (a peer handle)",
                 (len(w.en.paste_hosts()), len(w.en.peers)), (1, 1))
            c.ck("... and armed its watchdog",
                 "cpBCheckStuck" in w.pending(), w.pending())
            if cp_close(c, w, "leg B join"):
                check_other(c, w, "leg B Join's close")
                c.eq("the close gave back exactly the holds the two presses "
                     "took", (w.en.took, w.en.gave), (2, 2))
        finally:
            w.close()

    c.section("closing pass: leg B on a refused enInitialize, then another "
              "stack initializes")
    w = cp_open(c, src, sandbox, "refused",
                en=EnetHolds(other=0, init_fails=True))
    if w:
        try:
            w.press("cpBHost")
            c.ck("Host says the init was refused",
                 "enInitialize refused" in w.text("cpBOut"),
                 w.text("cpBOut"))
            c.eq("a refused init is no hold, and no host was attempted",
                 (w.en.took, w.en.attempts), (0, 0))
            w.en.other_takes_a_hold()
            if cp_close(c, w, "refused"):
                check_other(c, w, "the refused leg's close")
                c.eq("the close gave back nothing", w.en.gave, 0)
        finally:
            w.close()

    c.section("closing pass: leg B with enetxt absent")
    w = cp_open(c, src, sandbox, "absent", enet_absent=True)
    if w:
        try:
            w.press("cpBHost")
            c.ck("Host says enetxt is missing",
                 "enetxt missing" in w.text("cpBOut"), w.text("cpBOut"))
            if cp_close(c, w, "absent"):
                c.ck("the close throws nothing, with enetxt absent", True)
        finally:
            w.close()

    c.section("closing pass: leg A run, then close twice")
    w = cp_open(c, src, sandbox, "leg A")
    if w:
        try:
            w.press("cpARun")
            c.eq("leg A took a DataChannel hold and made its two peers",
                 (w.dc.holding, len(w.dc.paste_peers())), (True, 2))
            UB.deliver_next(w.ip, w.world, only=("cpPump",))
            if cp_close(c, w, "leg A"):
                check_other(c, w, "leg A's close", dc_lost_ok=True)
                c.eq("the close called dcCleanup once, with its own hold",
                     (w.dc.cleanups, w.dc.paste_peers()), (1, []))
                c.ck("[RESIDUAL] leg A still ends the other stack's "
                     "DataChannel peer (dcCleanup is uncounted in its shim: "
                     "the work plan's datachannelxt #8)",
                     w.dc.other_peer_lost)
            if cp_close(c, w, "leg A, again"):
                c.eq("a second close calls no dcCleanup", w.dc.cleanups, 1)
        finally:
            w.close()

    c.section("closing pass: leg A on a refused dcInit")
    w = cp_open(c, src, sandbox, "leg A refused", dc=DcRefusing())
    if w:
        try:
            w.press("cpARun")
            c.ck("leg A says the init was refused",
                 "dcInit refused" in w.text("cpAOut"), w.text("cpAOut"))
            c.eq("... and stopped there: no peer was made",
                 w.dc.paste_peers(), [])
            if cp_close(c, w, "leg A refused"):
                check_other(c, w, "leg A refused, its close")
                c.eq("the close called no dcCleanup", w.dc.cleanups, 0)
        finally:
            w.close()

    c.section("closing pass: leg E Host, then close")
    bt = TorrentModel()
    w = cp_open(c, src, sandbox, "leg E", torrent=bt)
    if w:
        try:
            w.press("cpEHost")
            c.eq("leg E took the session and a DataChannel hold, and made "
                 "its peer", (bt.sessions, w.dc.holding,
                              len(w.dc.paste_peers())), (1, True, 1))
            if cp_close(c, w, "leg E"):
                check_other(c, w, "leg E's close", dc_lost_ok=True)
                c.eq("the close stopped the session and called dcCleanup "
                     "once", (bt.stopped, w.dc.cleanups), (1, 1))
        finally:
            w.close()


# ==========================================================================
# the two ENet chat demos
# ==========================================================================
#
# Added by the adversarial review of 2026-09-27. The enetxt #4 row (and
# enetxt CLAUDE.md gotcha 7, as first written) said the chat demos' only
# unpaired path was a re-fired openStack, which "leaks a hold and harms no
# other window". Driving them found a second: ecStart / eiStart exited on a
# REFUSED enInitialize, but ecStop / eiStop called enDeinitialize on every
# close, so a close after a refusal, beside a window that initialized ENet
# since, gave back that window's hold and ended its host (and so did a close
# whose start was never reached, and a second close). Each now takes at most
# ONE hold, flagged by sHaveEn, and its stop gives back only that one.
#
# Their openStack builds the window first (ecBuild / eiBuild walk `the number
# of buttons of this card`, a form this interpreter does not read) and runs
# the boot self-check last; neither touches the hold. So the drive calls the
# one line of openStack that does, the start handler, and the real
# closeStack, whose only line is the stop.

CHATS = (
    ("enet-lan-chat", "lanchat", "ecStart"),
    ("enet-internet-chat", "netchat", "eiStart"),
)


def chat_step(c, w, label, handler):
    try:
        w.call(handler)
        return True
    except Exception as exc:                            # noqa: BLE001
        return c.threw("%s: %s runs" % (label, handler), exc)


def scenario_chat(c, src, sandbox, label, start):
    c.section("%s: start beside the other stack, then close" % label)
    w = Window(src, sandbox)
    try:
        if chat_step(c, w, label, start):
            c.eq("%s: the start took one hold" % label,
                 (w.en.took, w.en.own, w.en.count), (1, 1, 2))
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s's close" % label)
            c.eq("%s: the close gave back exactly its one" % label,
                 w.en.gave, 1)
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: a second close" % label)
            c.eq("%s: a second close gave back nothing" % label,
                 w.en.gave, 1)
        # closed, then reopened: the stop cleared the flag, so the reopen
        # takes (and its close gives back) a hold of its own
        if chat_step(c, w, label, start):
            c.eq("%s: a reopen after a close took a hold again" % label,
                 (w.en.took, w.en.own), (2, 1))
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: the reopened window's close" % label)
    finally:
        w.close()

    c.section("%s: a re-fired openStack, then close" % label)
    w = Window(src, sandbox)
    try:
        chat_step(c, w, label, start)
        if chat_step(c, w, label, start):
            c.eq("%s: a re-fired openStack took no second hold" % label,
                 (w.en.took, w.en.own), (1, 1))
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: a re-fired openStack's close" % label)
    finally:
        w.close()

    c.section("%s: a close with the start never reached" % label)
    w = Window(src, sandbox)
    try:
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: a close with no start" % label)
            c.eq("%s: a close with no start gave back nothing" % label,
                 w.en.gave, 0)
    finally:
        w.close()

    c.section("%s: the start's enInitialize refused, then another stack "
              "initializes" % label)
    w = Window(src, sandbox, en=EnetHolds(other=0, init_fails=True))
    try:
        if chat_step(c, w, label, start):
            c.eq("%s: a refused enInitialize is no hold" % label,
                 (w.en.took, w.en.own), (0, 0))
        w.en.other_takes_a_hold()
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: a refused start's close" % label)
            c.eq("%s: a refused start's close gave back nothing" % label,
                 w.en.gave, 0)
    finally:
        w.close()

    c.section("%s: enetxt absent" % label)
    w = Window(src, sandbox, enet_absent=True)
    try:
        chat_step(c, w, label, start)
        if chat_step(c, w, label, "closeStack"):
            check_other(c, w, "%s: the absent start's close" % label)
    finally:
        w.close()


# ==========================================================================

KEYS = (("--selftest", "selftest"), ("--closing", "closing"),
        ("--lanchat", "lanchat"), ("--netchat", "netchat"))


def main(argv):
    verbose = "--verbose" in argv
    paths = {"selftest": SELFTEST, "closing": CLOSING, "lanchat": LANCHAT,
             "netchat": NETCHAT}
    for flag, key in KEYS:
        if flag in argv:
            k = argv.index(flag)
            if k + 1 >= len(argv):
                print("usage: check-transport-holds.py [--verbose] "
                      "[--selftest PATH] [--closing PATH] [--lanchat PATH] "
                      "[--netchat PATH]")
                return 2
            paths[key] = argv[k + 1]
    t0 = time.time()
    c = UB.Checker(verbose)

    def fail(msg):
        print("check-transport-holds: %s" % msg)
        sys.exit(1)

    for label, key, calls, counts in ROUTING:
        check_routing(c, label, paths[key], calls, counts)

    sandbox = tempfile.mkdtemp(prefix="transport-holds-")
    try:
        for key, scenario in (("selftest", scenario_selftest),
                              ("closing", scenario_closing)):
            src = build_source(paths[key], key, fail)
            try:
                scenario(c, src, sandbox)
            except Exception as exc:                    # noqa: BLE001
                c.threw("the %s scenarios ran to their end" % key, exc)
        for label, key, start in CHATS:
            src = build_source(paths[key], key, fail)
            try:
                scenario_chat(c, src, sandbox, label, start)
            except Exception as exc:                    # noqa: BLE001
                c.threw("the %s scenarios ran to their end" % key, exc)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    c.section("the model")
    c.eq("every model delta fired (a hook nobody exercises is a stale "
         "excuse)", [n for n in DELTAS if FIRED[n] == 0], [])
    elapsed = time.time() - t0
    print("check-transport-holds: deltas fired: %s" % ", ".join(
        "%s x%d" % (n, FIRED[n]) for n in DELTAS))
    if c.failures:
        print("check-transport-holds: %d of %d check(s) FAILED (%.1fs)"
              % (len(c.failures), c.n, elapsed))
        return 1
    print("check-transport-holds: OK (%d checks, %.1fs): in enet-selftest, "
          "the suite closing pass and the two ENet chat demos every library "
          "init and release is routed through its counted wrapper; and "
          "driven beside another stack's modelled ENet hold and host and "
          "DataChannel peer, every open, run, Re-run, leg, start and close "
          "gave back exactly the holds its window took (a refused init "
          "none), and enet-selftest's no-op leg "
          "called only at a count the shim said was zero. The interpreter's "
          "run, not an engine's: logic only; no event path; it upgrades no "
          "label (needs an OXT pass)." % (c.n, elapsed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
