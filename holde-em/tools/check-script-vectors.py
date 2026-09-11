#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/holdem.livecodescript's own
self-test sections, headlessly, through the family's stack runner.

WHY THIS EXISTS. holde-em's game and its harness are ONE FILE, and until this
gate the harness had exactly one way to run: paste the stack into an engine.
The seven KAT mirrors in tools/ (evaluator, betting, shuffle, fold, protocol,
atlas, sounds) prove the Python MIRRORS of the game's pure handlers; the
harness constants are re-derived from them; and `check-suite-selftest.py`
proves the fold holds together. None of that RUNS the script. So a rules
defect in the evaluator or the settlement could pass every headless gate and
be found only on the next engine session - which is this tree's most
expensive lesson, "shipped is not run", in the member where the rules are the
product. Every other member with a script layer closed the same gap the same
way (coinxt, nostrxt, riptide, the wallet, nocloud); this is holde-em's.

WHAT IT DOES. It loads the shipped stack through riptide's DemoInterp - the
same runner that boots riptide, the coin wallet and nocloud's helpers - with
the SodiumXT surface the pure sections need modelled (below), and calls the
harness's own section handlers one by one, exactly as `heTestRunAllSections`
does on an engine: reset the counters, run the section, read `gPassN`,
`gFailN`, `gSkipN` and the report. The harness's assertions ARE the vectors;
this file adds none. A section that throws, a FAIL line in its report, or a
pass count below its floor fails the gate. The floors are a RATCHET (a
section that quietly stops asserting must fail rather than print OK), and
they are set from measured runs, so raising them is the normal edit after a
harness grows.

WHAT IT IS NOT. The interpreter, not the engine. Nothing here promotes a
section out of "verified statically; needs an OXT pass"; the engine passes
the member's CLAUDE.md records still stand and are still the record. What
this settles is that the LOGIC the harness pins holds in the shipped text.

THE SODIUMXT MODELS, and which are faithful. riptide's runner already models
ed25519 (RFC 8032, anchored to sodiumxt's C KAT), BLAKE2b-derived key
exchange, hex, memEqual and SHA3-256. This gate adds, for the sections that
need them: sxHash (BLAKE2b at the asked digest size - FAITHFUL, it is the
same hash), sxHmacSha256 (FAITHFUL), sxSignSeedToExpandedKey (SHA-512 of the
seed, clamped - FAITHFUL, the Tor expanded-key rule onion-kat pins),
sxBin2Base64 (FAITHFUL), sxRandomUniform and sxRandomBytes over the world's
SEEDED generator (deterministic on purpose: a gate that reads real randomness
cannot reproduce its failures), sxBoxKeypairFromSeed (libsodium's rule: the
secret is SHA-512(seed)[:32], the public key its X25519 base multiple -
FAITHFUL over the oracle's X25519), and sxSeal / sxSealOpen, which are a
MODEL and the one real stand-in: an ephemeral X25519 exchange over the real
curve, then an authenticated stream over BLAKE2b and HMAC rather than
XSalsa20-Poly1305. It has the SHAPE the harness depends on - a seal opens
under the right secret, fails under the wrong one, and a flipped byte is
refused - and it is not libsodium's bytes. No section pins sealed-box BYTES
(they could not: the ephemeral key makes every seal different), so the model
cannot pass a check it should fail. Ristretto255 (`sxRistretto*`, SodiumXT
ABI 8/9) is NOT modelled: the Level 2 deal algebra and the DLEQ proofs skip
themselves through the harness's own capability probe, exactly as they do on
an engine without that surface, and the gate REQUIRES those skips (a Level 2
section that stopped skipping would be one that ran against a surface that
does not exist here).

NOT DRIVEN, with the reason: heTestNetPlay (an online hand over a REAL
TorrentXT session - nothing headless can carry it), heProbeSodium (a
diagnostic that prints a report; it asserts nothing), and the LIVE rows the
onion and oracle sections declare as skips by name (a tor daemon, three
machines).

THE SOURCE IS READ THE WAY THE ENGINE READS IT. The base interpreter strips
`--` comments; this stack also carries `/* ... */` block comments (the
family's static checker admits them, and the member's own coverage gate
records the trap where one swallows 2,200 lines), so build_source strips
those too, outside strings, keeping the line count. And ONE guard in the
shipped script was nested for this gate (`heBetApply`'s non-numeric wager
refusal, see the member's CLAUDE.md, 2026-09-11): `X is not a number or X is
not trunc(X)` evaluates `trunc("abc")` under the both-operands rule (root
engine notes 2.5), which the interpreter refuses; nested, the answer is the
same under either reading of the engine and the section can run.

Mutation-tested (tools/test-script-vectors.py): a wrong straight-flush rank,
a settlement that gives the odd chip to the wrong seat, and a shuffle that
does not swap are each caught by name, and the untouched copy passes.

Run from the member directory or anywhere:  python3 tools/check-script-vectors.py
"""
import base64
import hashlib
import hmac
import importlib.util
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
SUITE = os.path.dirname(MEMBER)
STACK = os.path.join(MEMBER, "src", "holdem.livecodescript")
RUNNER = os.path.join(SUITE, "riptide", "tools", "check-demo-boot.py")
ORACLE = os.path.join(SUITE, "riptide", "tools", "riptide_reference.py")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DB = _load("he_demo_boot", RUNNER)
LCS = DB.LCS
RR = _load("he_riptide_reference", ORACLE)
Thrown = LCS.Thrown

# (section, minimum passes, exact skips). The pass floors are the counts
# measured on 2026-09-11 (stack 0.25.3, harness v44); raise them when the
# harness grows. A skip count is EXACT: a section that skips more than it
# did is a section that stopped running something.
SECTIONS = [
    ("heTestEvaluatorRun", 28, 0),
    ("heTestBettingRun", 68, 0),
    ("heTestAnteRun", 23, 0),
    ("heTestLevelRun", 12, 0),
    ("heTestLegalRun", 18, 0),
    ("heTestScheduleRun", 3, 0),
    ("heTestShuffleRun", 9, 0),
    ("heTestFoldRun", 17, 0),
    ("heTestCryptoRun", 25, 0),
    ("heTestReceiptRun", 17, 0),
    ("heTestDealRun", 16, 0),
    ("heTestDealOrderRun", 5, 0),
    ("heTestLobbyRun", 10, 0),
    ("heTestNetSim", 20, 0),
    ("heTestNetPlay", 47, 0),
    ("heTestLevel2Run", 0, 1),          # ristretto255 is not modelled: skips
    ("heTestOnionRun", 35, 1),          # the LIVE tor table skips by name
    ("heTestOracleRun", 32, 2),         # the LIVE three-machine round + the onion oracle
    ("heTestLevel2VoidRun", 2, 1),      # its ristretto (DLEQ) half skips
    ("heTestLivenessRun", 84, 2),       # the LIVE timed table + the LIVE tor redial
    ("heTestHelpersRun", 28, 1),
    ("heTestLeafRun", 39, 0),
    ("heTestLeafRun2", 83, 0),
]
TOTAL_FLOOR = 600


# --------------------------------------------------------------------------
# the source, read the way the engine reads it

def strip_block_comments(src):
    """Remove `/* ... */` outside string literals, keeping every newline so
    line numbers survive. `--` comments are left for the base to strip."""
    out, i, n, instr = [], 0, len(src), False
    while i < n:
        c = src[i]
        if instr:
            out.append(c)
            if c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
            out.append(c)
            i += 1
            continue
        if src.startswith("--", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(src[i:j])
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            if j < 0:
                raise SyntaxError("unterminated block comment")
            out.append("\n" * src[i:j].count("\n"))
            i = j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def build_source(path):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)
    stripped = strip_block_comments(src)
    assert stripped.count("\n") == src.count("\n"), "the stripper moved a line"
    return stripped


# --------------------------------------------------------------------------
# the SodiumXT surface the pure sections reach (see the header)

def _s(a):
    return str(LCS._disp(a))


def _b(a):
    return _s(a).encode("latin-1")


def _t(b):
    return b.decode("latin-1")


def _keystream(shared, nonce, length):
    out, ctr = b"", 0
    while len(out) < length:
        out += hashlib.blake2b(shared + nonce + ctr.to_bytes(4, "big"),
                               digest_size=64).digest()
        ctr += 1
    return out[:length]


def seal_model(msg, pk, esk):
    """The sealed-box MODEL (see the header): ephemeral X25519 over the real
    curve, then a BLAKE2b keystream and a 16-byte HMAC tag."""
    epk = RR.x25519_base(esk)
    shared = RR._x25519(esk, pk)
    nonce = hashlib.blake2b(epk + pk, digest_size=24).digest()
    ct = bytes(x ^ y for x, y in zip(msg, _keystream(shared, nonce, len(msg))))
    tag = hmac.new(shared, nonce + ct, hashlib.sha256).digest()[:16]
    return epk + tag + ct


def seal_open_model(sealed, pk, sk):
    if len(sealed) < 48:
        raise Thrown("SodiumXT: sxSealOpen: sealed data too short")
    epk, tag, ct = sealed[:32], sealed[32:48], sealed[48:]
    shared = RR._x25519(sk, epk)
    nonce = hashlib.blake2b(epk + pk, digest_size=24).digest()
    want = hmac.new(shared, nonce + ct, hashlib.sha256).digest()[:16]
    if not hmac.compare_digest(tag, want):
        raise Thrown("SodiumXT: sxSealOpen: forged or corrupted")
    return bytes(x ^ y for x, y in zip(ct, _keystream(shared, nonce, len(ct))))


def install_sodium(world):
    def expanded(a):
        h = bytearray(hashlib.sha512(_b(a[0])).digest())
        h[0] &= 248
        h[31] &= 127
        h[31] |= 64
        return _t(bytes(h))

    LCS.HASHES.update({
        "sxhash": lambda a: _t(hashlib.blake2b(
            _b(a[0]), digest_size=int(LCS._n(a[1])) if len(a) > 1 else 32).digest()),
        # sxHmacSha256(pKey, pMessage): the KEY is the first argument
        "sxhmacsha256": lambda a: _t(hmac.new(_b(a[0]), _b(a[1]), hashlib.sha256).digest()),
        "sxbin2base64": lambda a: base64.b64encode(_b(a[0])).decode("ascii"),
        "sxsignseedtoexpandedkey": expanded,
        "sxrandomuniform": lambda a: world.rng.randrange(max(1, int(LCS._n(a[0])))),
        "sxrandombytes": lambda a: _t(bytes(world.rng.randrange(256)
                                            for _ in range(int(LCS._n(a[0]))))),
        "sxseal": lambda a: _t(seal_model(
            _b(a[0]), _b(a[1]), bytes(world.rng.randrange(256) for _ in range(32)))),
        "sxsealopen": lambda a: _t(seal_open_model(_b(a[0]), _b(a[1]), _b(a[2]))),
    })


class HeInterp(DB.DemoInterp):
    """The runner plus the one SodiumXT COMMAND holde-em uses that riptide
    does not: sxBoxKeypairFromSeed, which returns through two out-parameters
    like the sign and kx keypair commands the runner already models."""

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        m = re.match(r'sxBoxKeypairFromSeed\s+(.+?)\s*,\s*(\w+)\s*,\s*(\w+)\s*$',
                     line, re.I)
        if m:
            seed = _b(self.eval_expr(m.group(1), env))
            if len(seed) != 32:
                raise Thrown("SodiumXT: the seed must be 32 bytes")
            sk = hashlib.sha512(seed).digest()[:32]
            self.assign(m.group(2), _t(RR.x25519_base(sk)), env)
            self.assign(m.group(3), _t(sk), env)
            return i + 1
        return super()._exec_stmt(body, i, env)


# --------------------------------------------------------------------------
# the drive

def run_section(ip, name):
    for k in ("gpassn", "gfailn", "gskipn"):
        ip.globals[k] = 0
    ip.globals["grpt"] = ""
    threw = None
    try:
        ip.call(name, [])
    except Exception as e:                       # noqa: BLE001 - reported below
        threw = "%s: %s" % (type(e).__name__, str(e)[:300])
    rpt = str(ip.globals.get("grpt", ""))
    lines = rpt.split("\n")
    # a FAIL line and the observed/expected lines the harness prints under it
    fails = []
    for k, ln in enumerate(lines):
        if ln.startswith("FAIL"):
            detail = [x.strip() for x in lines[k + 1:k + 3] if x.startswith("      ")]
            fails.append(ln + ("  [" + "; ".join(detail) + "]" if detail else ""))
    return (int(LCS._n(ip.globals["gpassn"])), int(LCS._n(ip.globals["gfailn"])),
            int(LCS._n(ip.globals["gskipn"])), fails, threw, rpt)


def main(argv):
    path = STACK
    args = [a for a in argv[1:] if a != "--check"]
    if len(args) == 2 and args[0] == "--source":
        path = args[1]
    elif args:
        print("usage: check-script-vectors.py [--check] [--source PATH]")
        return 2
    sandbox = tempfile.mkdtemp(prefix="holdem-vectors-")
    problems, total = [], 0
    try:
        world = DB.World(sandbox)
        ip = HeInterp(build_source(path), world)
        DB.install_common(world)
        install_sodium(world)
        for name, floor, skips in SECTIONS:
            passed, failed, skipped, fails, threw, rpt = run_section(ip, name)
            total += passed
            line = "%-22s pass=%-3d fail=%-2d skip=%d" % (name, passed, failed, skipped)
            if threw:
                problems.append("%s THREW %s" % (name, threw))
                line += "  THREW"
            for f in fails:
                problems.append("%s: %s" % (name, f))
            if failed and not fails:
                problems.append("%s counted %d failure(s) with no FAIL line" % (name, failed))
            if passed < floor:
                problems.append("%s passed %d, below its floor of %d" % (name, passed, floor))
            if skipped != skips:
                problems.append("%s skipped %d section(s), expected exactly %d"
                                % (name, skipped, skips))
            print(line)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
    if problems:
        print("check-script-vectors: FAIL (%d)\n  %s" % (len(problems), "\n  ".join(problems)))
        return 1
    if total < TOTAL_FLOOR:
        print("check-script-vectors: FAIL - %d passes in all, below the floor of %d"
              % (total, TOTAL_FLOOR))
        return 1
    print("check-script-vectors: OK (%d harness assertions passed across %d sections "
          "of the shipped stack, run headlessly; ristretto255 and the live rows skip "
          "by name)" % (total, len(SECTIONS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
