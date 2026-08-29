#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/riptide.livecodescript
against the oracle's vectors, headlessly, through nostrxt's lcs-interp.py.

WHY THIS EXISTS. Until this file, riptide's whole vector spine was
ORACLE-ONLY: tools/riptide_reference.py proves the EXPECTED answers are
right, tests/riptide_golden_test.py pins them in Python, and
tools/check-selftest-vectors.py proves the harness constants match - but
NOTHING proved the SCRIPT derives them. The only thing that had ever read
src/riptide.livecodescript was check-livecodescript.py, which validates
balance, quoting and the token traps and cannot tell whether a handler
computes the right bytes. That is precisely the gap the member's own
CLAUDE.md names as its most expensive class of bug, and the gap CoinXT and
NostrXT each closed with their own copy of this gate.

It paid for itself on its first run, twice over, and NEITHER defect was in
the shipped script - which is worth saying plainly, because a new tool's
first findings are the ones most likely to be the tool's own (nostrxt
learned that the expensive way and wrote it down: suspect the probe first,
with evidence).

  - The INTERPRETER mis-modelled a negative chunk range, clamping instead of
    counting from the end, so `char -3 to -1 of "abcdef"` came back "abcde".
    Latent rather than active: neither coinxt's nor nostrxt's source uses the
    form, so no existing gate had ever read a wrong answer from it. It
    surfaced here on `byte 10 to -1 of pFileBytes`, the idiom rsOpenMasterSeed
    has used since phase 1. Fixed at the source in both copies, with both
    dependent members' gates re-run to prove nothing moved.
  - The ORACLE crashed on a tampered signature: _verify_ed25519 decompressed
    the signature's R point without the not-a-point guard its public-key path
    already had, so a corrupted signature raised TypeError instead of
    answering False. Every earlier negative test had tampered with the
    MESSAGE, never the signature, so nothing had ever reached that line.

One thing in the shipped script did change as a result, and it was a
readability call rather than a bug: the media-tag reader now takes its
40-hex tail by positive indices, because the length is pinned one line above
and an explicit span is easier to check than a negative one.

WHAT IT IS NOT. An approximation of the engine, not the engine. Nothing
here promotes a handler out of "verified statically; needs an OXT pass" -
what it settles is LOGIC, not parser behaviour. If this file and the engine
disagree, the engine is right. The interpreter's own header carries the
modelled-subset contract and its named divergences.

THE SOURCE REWRITES, AND WHY THEY ARE ASSERTED. riptide was written before
this gate existed and uses three spellings outside the interpreter's
modelled subset. The line between what got FIXED in the interpreter and what
gets REWRITTEN here is deliberate: lcs-interp.py is shared byte-identical
with CoinXT's copy and drift-gated, so every change there rides on two other
members' gates. A wrong ANSWER earns that risk (the negative-range bug
above, fixed at the source). Three missing SPELLINGS do not - they are
syntax the interpreter has simply never been taught, riptide is the only
member that writes them, and teaching them means new parser paths under two
members that would gain nothing.

So this file rewrites those three forms into equivalent ones the interpreter
already models, and the rewrites are NAMED and COUNTED. Every one must match
at least once or the gate FAILS: a rewrite that silently stops applying
would leave the gate quietly testing a file nobody ships, which is this
tree's own recurring failure shape (a gate that looks like it checks
something and does not). The rewrites are behaviour-preserving by
inspection; each is listed in REWRITES below with what it stands in for.

THE NAMED STAND-INS, all of them declared rather than hidden:
  - sxSignKeypairFromSeed is a COMMAND WITH OUT-PARAMETERS, which the
    interpreter does not model at all. rsIdentityKeys - and only that one
    handler - is replaced by the shim in SHIM below, whose ed25519 comes
    from the oracle. rsIdentityKeys is phase-1 code that passed on a real
    engine in 2026-08-12, so it is not what this gate is for.
  - sxSignDetached / sxSignVerifyDetached are the oracle's RFC 8032
    ed25519, which is anchored to the cross-project BEP44 conformance
    vector and sodiumxt's own C KAT at oracle import.
  - sxKdfDerive is hashlib.blake2b, the model the oracle already proves
    against sodiumxt's C KAT. A faithful model, not a stub.
  - sxSecretBox / sxSecretBoxOpen are a MODEL, and the only real stand-in
    here: authenticated (HMAC over nonce and ciphertext, verified before
    anything is returned) and nonce-prefixed, so it has the shape the app
    code depends on, but it is NOT XSalsa20-Poly1305. What it therefore
    exercises is rsSealAppState/rsOpenAppState's own framing, caps, header
    and UTF-8 round trip - which is the code this member owns. The
    cryptography underneath is libsodium's and is proved by sodiumxt.
  - sxRandomBytes is a deterministic counter, for the reason NostrXT's gate
    gives: a gate that draws real entropy cannot reproduce its own failures.

The CoinXT crypto is REAL. cxSha256, cxSchnorrSign, cxSchnorrVerify,
cxXOnlyPubkey and cxSeckeyIsValid are bound by ctypes to the committed
library a packaged extension binds:
    ../coinxt/src/code/x86_64-linux/coinxt.so
so the phase-8 signatures under test are genuine BIP-340 over genuine
libsecp256k1, and the vectors they are compared against come from an
independent implementation (nostrxt/tools/nostr_reference.py, which anchors
itself to the published BIP-340/NIP-19/BIP-173 sets at import).

TWO TIERS, so the gate is useful without the sibling binary:
  1. PURE, always: everything with no CoinXT call in it.
  2. COMPOSED, when coinxt.so is present: the whole phase-8 rail.
A missing library SKIPS tier 2 loudly; it never passes silently.

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse (the gate set)
"""
import ctypes
import hashlib
import hmac
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
SUITE = os.path.dirname(MEMBER)

SCRIPT = os.path.join(MEMBER, "src", "riptide.livecodescript")
NOSTR_SCRIPT = os.path.join(SUITE, "nostrxt", "src", "nostrxt.livecodescript")
INTERP = os.path.join(SUITE, "nostrxt", "tools", "lcs-interp.py")
COIN_SO = os.path.join(SUITE, "coinxt", "src", "code", "x86_64-linux",
                       "coinxt.so")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LCS = _load("lcs_interp", INTERP)

REF = {}
with open(os.path.join(HERE, "riptide_reference.py"), "r",
          encoding="utf-8") as _f:
    exec(compile(_f.read(), os.path.join(HERE, "riptide_reference.py"),
                 "exec"), REF)


# --------------------------------------------------------------------------
# The source rewrites. (name, why, apply) - each must fire at least once.
# --------------------------------------------------------------------------

def _rw_count_in(line):
    return re.sub(r'\bthe number of (bytes|chars|characters|lines|items|keys)'
                  r' in\b', r'the number of \1 of', line)


def _rw_one_line_if(line):
    """`if COND then STMT` on one line -> the block form.

    riptide uses this 90 times; the interpreter models only the block form.
    Equivalent by construction, and riptide never writes a one-line
    `if ... then ... else ...` (asserted below), so there is no else branch
    to lose."""
    m = re.match(r'^(\s*)if (.+?) then (.+)$', line)
    if not m or m.group(3).strip().startswith("--"):
        return line
    ind, cond, stmt = m.groups()
    return "%sif %s then\n%s   %s\n%send if" % (ind, cond, ind, stmt, ind)


def _rw_binary_encode(line):
    """binaryEncode / div / mod -> named stand-ins.

    The interpreter models neither the binaryEncode builtin nor the `div`
    and `mod` operators. These three lines are the ONLY places riptide uses
    either, and each is a pure big-endian integer packer - the stand-ins
    below do exactly what binaryEncode's "n"/"N"/"NN" formats do."""
    line = line.replace(
        'binaryEncode("NN", pNum div 4294967296, pNum mod 4294967296)',
        'rstBEu64(pNum)')
    line = re.sub(r'binaryEncode\("N", (.+?)\)$', r'rstBEu32(\1)', line)
    line = re.sub(r'binaryEncode\("n", (.+?)\)$', r'rstBEu16(\1)', line)
    return line


REWRITES = [
    ("the number of X in Y -> of Y",
     "the interpreter models only the `of` spelling of a chunk count",
     _rw_count_in),
    ("one-line `if ... then STMT` -> block form",
     "the interpreter models only the block form of `if`",
     _rw_one_line_if),
    ("binaryEncode / div / mod -> named packers",
     "the interpreter models neither the builtin nor the two operators",
     _rw_binary_encode),
]

# rsIdentityKeys, and only it, is replaced: its sxSignKeypairFromSeed is a
# command with OUT-PARAMETERS, which the interpreter cannot express. Phase-1
# code, engine-passed 2026-08-12, and not what this gate exists to check.
SHIM = """
function rsIdentityKeys pSeed
   local tOut
   if the number of bytes of pSeed is not 32 then
      return empty
   end if
   put rstEdPub(pSeed) into tOut["publicKey"]
   put pSeed into tOut["secretKey"]
   put rstEdPubHex(pSeed) into tOut["handle"]
   return tOut
end rsIdentityKeys
"""


def strip_script_header(text):
    return re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', text, count=1)


def build_source(fail):
    with open(SCRIPT, "r", encoding="utf-8") as fh:
        rip = fh.read()
    if re.search(r'^\s*if .+ then .+ else ', rip, re.M):
        fail("a one-line `if ... then ... else ...` appeared in the shipped "
             "file; the one-line rewrite would silently drop its else branch")
    hits = dict((name, 0) for name, _why, _fn in REWRITES)
    out = []
    for line in strip_script_header(rip).split("\n"):
        for name, _why, fn in REWRITES:
            new = fn(line)
            if new != line:
                hits[name] += 1
                line = new
        out.append(line)
    for name, why, _fn in REWRITES:
        if hits[name] == 0:
            fail("the rewrite %r matched NOTHING. It stands in for: %s. A "
                 "rewrite that stops applying leaves this gate testing a "
                 "file nobody ships - fix the rewrite or remove it." %
                 (name, why))
    with open(NOSTR_SCRIPT, "r", encoding="utf-8") as fh:
        core = strip_script_header(fh.read())
    return core + "\n" + "\n".join(out) + "\n" + SHIM, hits


# --------------------------------------------------------------------------
# natives
# --------------------------------------------------------------------------

def to_bytes(s):
    return str(s).encode("latin-1")


def to_str(b):
    return b.decode("latin-1")


def install_pure_natives():
    """Everything that needs no CoinXT."""
    LCS.HASHES.update({
        "tolower": lambda a: str(LCS._disp(a[0])).lower(),
        "toupper": lambda a: str(LCS._disp(a[0])).upper(),
        "rstbeu64": lambda a: to_str(int(LCS._n(a[0])).to_bytes(8, "big")),
        "rstbeu32": lambda a: to_str(int(LCS._n(a[0])).to_bytes(4, "big")),
        "rstbeu16": lambda a: to_str(int(LCS._n(a[0])).to_bytes(2, "big")),
        "sxhex2bin": lambda a: to_str(bytes.fromhex(str(LCS._disp(a[0])))),
        "sxbin2hex": lambda a: to_bytes(a[0]).hex(),
        "sxmemequal": lambda a: to_bytes(a[0]) == to_bytes(a[1]),
        "rstedpub": lambda a: to_str(REF["ed25519_publickey"](to_bytes(a[0]))),
        "rstedpubhex": lambda a: REF["ed25519_publickey"](
            to_bytes(a[0])).hex(),
        "sxsigndetached": lambda a: to_str(
            REF["ed25519_sign"](to_bytes(a[0]), to_bytes(a[1]))),
        "sxsignverifydetached": lambda a: REF["_verify_ed25519"](
            to_bytes(a[0]), to_bytes(a[1]), to_bytes(a[2])),
        "sxkdfderive": lambda a: to_str(REF["kdf_derive"](
            to_bytes(a[0]), int(str(LCS._disp(a[1]))), int(LCS._n(a[3])),
            context=to_bytes(a[2]))),
    })

    counter = [0]

    def sxrandombytes(args):
        n = int(LCS._n(args[0]))
        counter[0] += 1
        seed = hashlib.sha256(b"rs-gate-%d" % counter[0]).digest()
        return to_str((seed * (n // 32 + 1))[:n])

    def secretbox(args):
        """MODEL, not XSalsa20-Poly1305 (see the header). Nonce-prefixed and
        authenticated, so the framing and every refusal path around it is
        exercised honestly; the real cipher is sodiumxt's to prove."""
        msg, key = to_bytes(args[0]), to_bytes(args[1])
        nonce = hashlib.sha256(b"rs-nonce" + key + msg).digest()[:24]
        stream = b""
        while len(stream) < len(msg):
            stream += hashlib.sha256(key + nonce + bytes([len(stream) // 32])
                                     ).digest()
        ct = bytes(a ^ b for a, b in zip(msg, stream[:len(msg)]))
        mac = hmac.new(key, nonce + ct, hashlib.sha256).digest()[:16]
        return to_str(nonce + ct + mac)

    def secretboxopen(args):
        blob, key = to_bytes(args[0]), to_bytes(args[1])
        if len(blob) < 40:
            raise LCS.Thrown("SodiumXT: sxSecretBoxOpen: too short")
        nonce, ct, mac = blob[:24], blob[24:-16], blob[-16:]
        want = hmac.new(key, nonce + ct, hashlib.sha256).digest()[:16]
        if not hmac.compare_digest(mac, want):
            raise LCS.Thrown("SodiumXT: sxSecretBoxOpen: bad tag")
        stream = b""
        while len(stream) < len(ct):
            stream += hashlib.sha256(key + nonce + bytes([len(stream) // 32])
                                     ).digest()
        return to_str(bytes(a ^ b for a, b in zip(ct, stream[:len(ct)])))

    LCS.HASHES.update({"sxrandombytes": sxrandombytes,
                       "sxsecretbox": secretbox,
                       "sxsecretboxopen": secretboxopen})


def install_coin_natives():
    """The REAL committed CoinXT, via ctypes. Returns False when absent."""
    if not os.path.exists(COIN_SO):
        return False
    lib = ctypes.CDLL(COIN_SO)
    sigs = [
        ("cnx_sha256", [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]),
        ("cnx_seckey_verify", [ctypes.c_char_p, ctypes.c_size_t]),
        ("cnx_xonly_pubkey_from_seckey",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
          ctypes.c_size_t]),
        ("cnx_schnorr_sign",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
          ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]),
        ("cnx_schnorr_verify",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
          ctypes.c_char_p, ctypes.c_size_t]),
    ]
    for name, argtypes in sigs:
        fn = getattr(lib, name)
        fn.restype = ctypes.c_int
        fn.argtypes = argtypes

    def cxsha256(a):
        d = to_bytes(a[0])
        out = ctypes.create_string_buffer(32)
        if lib.cnx_sha256(d, len(d), out) != 0:
            raise LCS.Thrown("CoinXT: cxSha256 failed")
        return to_str(out.raw[:32])

    def cxseckeyisvalid(a):
        sk = to_bytes(a[0])
        rc = lib.cnx_seckey_verify(sk, len(sk))
        if rc == 0:
            return True
        if rc in (-1, -2, -4):
            return False
        raise LCS.Thrown("CoinXT: cxSeckeyIsValid refused the call")

    def cxxonlypubkey(a):
        sk = to_bytes(a[0])
        out = ctypes.create_string_buffer(32)
        if lib.cnx_xonly_pubkey_from_seckey(sk, len(sk), out, 32) != 0:
            raise LCS.Thrown("CoinXT: cxXOnlyPubkey failed")
        return to_str(out.raw[:32])

    def cxschnorrsign(a):
        sk, msg = to_bytes(a[0]), to_bytes(a[1])
        aux = to_bytes(a[2]) if len(a) > 2 else b""
        out = ctypes.create_string_buffer(64)
        if lib.cnx_schnorr_sign(sk, len(sk), msg, len(msg), aux, len(aux),
                                out, 64) != 0:
            raise LCS.Thrown("CoinXT: cxSchnorrSign failed")
        return to_str(out.raw[:64])

    def cxschnorrverify(a):
        pk, msg, sig = to_bytes(a[0]), to_bytes(a[1]), to_bytes(a[2])
        rc = lib.cnx_schnorr_verify(pk, len(pk), msg, len(msg), sig, len(sig))
        if rc == 0:
            return True
        if rc == -5:
            return False
        raise LCS.Thrown("CoinXT: cxSchnorrVerify refused the call")

    LCS.HASHES.update({
        "cxsha256": cxsha256, "cxseckeyisvalid": cxseckeyisvalid,
        "cxxonlypubkey": cxxonlypubkey, "cxschnorrsign": cxschnorrsign,
        "cxschnorrverify": cxschnorrverify,
    })
    return True


# --------------------------------------------------------------------------

class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.n = 0
        self.failed = 0
        self.skipped = 0

    def note(self, text):
        if not self.terse:
            print("-- %s" % text)

    def ck(self, label, got, want):
        self.n += 1
        if got == want:
            if not self.terse:
                print("  ok   %s" % label)
        else:
            self.failed += 1
            print("  FAIL %s\n       got  %r\n       want %r"
                  % (label, got, want))

    def skip(self, label, why):
        self.skipped += 1
        print("  SKIP %s (%s)" % (label, why))


MASTER = to_str(bytes([0x42] * 32))
AUX = "00" * 32


def check_pure(c, ip, V):
    c.note("tier 1: the pure paths (no CoinXT needed)")
    c.ck("the subkey registry has not shifted under the new rows",
         [ip.constants.get("kRsSubkeyIdentity"),
          ip.constants.get("kRsSubkeyDm"),
          ip.constants.get("kRsSubkeyLan"),
          ip.constants.get("kRsSubkeyNostr"),
          ip.constants.get("kRsSubkeyAppState")],
         ["1", "2", "3", "4", "5"])
    c.ck("the bridge signature domain is distinct from the LAN domains",
         len({ip.constants.get("kRsNostrDomain"),
              ip.constants.get("kRsLanDomain"),
              ip.constants.get("kRsLanSyncDomain")}), 3)
    c.ck("the RSN1 body and record lengths agree with the layout",
         [ip.constants.get("kRsNostrBridgeBody"),
          ip.constants.get("kRsNostrBridgeLen")], [148, 276])

    c.note("the app-state store: framing, caps and refusals")
    sealed = ip.call("rsSealAppState", ["hello state", MASTER])
    c.ck("a sealed store carries the RIPTAPP1 header",
         sealed[:9], "RIPTAPP1S")
    c.ck("it round trips", ip.call("rsOpenAppState", [sealed, MASTER]),
         "hello state")
    other = to_str(bytes([0x43] * 32))
    c.ck("a different master cannot open it",
         ip.call("rsOpenAppState", [sealed, other]), "")
    c.ck("a foreign magic is refused",
         ip.call("rsOpenAppState", ["XIPTAPP1S" + sealed[9:], MASTER]), "")
    c.ck("a truncated file is refused",
         ip.call("rsOpenAppState", [sealed[:8], MASTER]), "")
    tampered = sealed[:-1] + chr(ord(sealed[-1]) ^ 1)
    c.ck("a tampered store is refused",
         ip.call("rsOpenAppState", [tampered, MASTER]), "")
    c.ck("an over-cap state refuses rather than truncating",
         ip.call("rsSealAppState", ["x" * 1048577, MASTER]), "")
    c.ck("a unicode state survives the round trip",
         ip.call("rsOpenAppState",
                 [ip.call("rsSealAppState",
                          [to_str("café ✓".encode("utf-8")),
                           MASTER]), MASTER]),
         to_str("café ✓".encode("utf-8")))


def check_composed(c, ip, V):
    c.note("tier 2: the phase-8 rail, executed over the real committed CoinXT")

    c.note("the secp256k1 validity ladder")
    c.ck("a valid candidate passes through unchanged",
         ip.call("rsNostrSeckeyFrom", ["42" * 32]), "42" * 32)
    c.ck("the all-zeros candidate steps to SHA-256 of itself",
         ip.call("rsNostrSeckeyFrom", ["00" * 32]),
         hashlib.sha256(bytes(32)).hexdigest())
    order = "%064x" % REF["_NOSTR"]["N"]
    c.ck("the group order n steps forward too",
         ip.call("rsNostrSeckeyFrom", [order]),
         hashlib.sha256(bytes.fromhex(order)).hexdigest())
    c.ck("a short candidate is refused",
         ip.call("rsNostrSeckeyFrom", ["42" * 31]), "")
    c.ck("a non-hex candidate is refused",
         ip.call("rsNostrSeckeyFrom", ["zz" + "42" * 31]), "")

    c.note("the Nostr identity")
    keys = ip.call("rsNostrKeys", [MASTER])
    c.ck("the x-only public key matches the oracle",
         keys["pubkey"], V["nostrPubkey"])
    c.ck("the npub matches the oracle", keys["npub"], V["nostrNpub"])
    c.ck("rsNostrKeys hands back NO secret material",
         sorted(keys.keys()), ["npub", "pubkey"])
    c.ck("the exported secret key matches the oracle",
         ip.call("rsNostrExportSeckey", [MASTER]), V["nostrSeckey"])

    c.note("the RSN1 bridge, byte for byte")
    br = ip.call("rsBuildBridge", [1, 1754870800, MASTER, AUX])
    c.ck("the record is byte-identical to the oracle's",
         to_bytes(br).hex(), V["bridge"])
    c.ck("it is exactly 276 bytes", len(br), 276)
    rec = ip.call("rsVerifyBridge", [br, "", ""])
    c.ck("verify recovers the handle", rec["handle"], V["handle"])
    c.ck("verify recovers the nostr key", rec["nostrPub"], V["nostrPubkey"])
    c.ck("verify recovers the seq", str(rec["seq"]), "1")
    c.ck("verify recovers the timestamp", str(rec["timestamp"]), "1754870800")
    c.ck("both expectations together still verify",
         ip.call("rsVerifyBridge",
                 [br, V["handle"], V["nostrPubkey"]])["handle"], V["handle"])
    c.ck("a wrong expected handle is refused",
         ip.call("rsVerifyBridge", [br, "ab" * 32, ""]), "")
    c.ck("a wrong expected nostr key is refused",
         ip.call("rsVerifyBridge", [br, "", "ab" * 32]), "")

    c.note("every field of the signed span is load-bearing")
    for pos, what in [(5, "the handle"), (69, "the nostr key"),
                      (140, "the seq"), (148, "the timestamp"),
                      (150, "the ed25519 signature"),
                      (214, "the BIP-340 signature")]:
        bad = br[:pos - 1] + chr(ord(br[pos - 1]) ^ 1) + br[pos:]
        c.ck("a tamper in %s is refused" % what,
             ip.call("rsVerifyBridge", [bad, "", ""]), "")
    c.ck("a short record is refused", ip.call("rsParseBridge", [br[:-1]]), "")
    c.ck("a long record is refused",
         ip.call("rsParseBridge", [br + "x"]), "")
    c.ck("a foreign magic is refused",
         ip.call("rsParseBridge", ["X" + br[1:]]), "")

    c.note("the DHT seam validates everything else BEFORE the session")
    # The phase-2 decision, kept: with a dead session handle these must
    # still reach their real refusal, or the checks below can only ever run
    # on a machine that has torrentxt - which is where a harness assertion
    # quietly starts passing for the wrong reason.
    c.ck("a non-RSN1 record is refused before the session is looked at",
         ip.call("rsPublishBridge", [0, "junk", to_str(bytes(32))]), False)
    c.ck("...naming the parse, not the session",
         "RSN1" in ip.call("rsLastError", []), True)
    c.ck("a seed that is not the bridge's handle is refused",
         ip.call("rsPublishBridge", [0, br, to_str(bytes([0x43] * 32))]),
         False)
    c.ck("...naming the seed, not the session",
         "signing seed" in ip.call("rsLastError", []), True)
    c.ck("only then does the dead session become the reason",
         "session" in (ip.call("rsPublishBridge",
                               [0, br, REF["identity_seed"](
                                   bytes([0x42] * 32)).decode("latin-1")])
                       or ip.call("rsLastError", [])), True)

    c.note("kind-1 notes and the media convention")
    note = ip.call("rsNostrNoteEvent", [1754870400, "hello, riptide", ""])
    signed = ip.call("rsNostrSignEvent", [note, MASTER, AUX])
    c.ck("the note id matches the oracle", signed["id"], V["noteEventId"])
    c.ck("the note signature matches the oracle",
         signed["sig"], V["noteEventSig"])
    media = ip.call("rsNostrNoteEvent", [1754870460, "second post", "ee" * 20])
    signed_media = ip.call("rsNostrSignEvent", [media, MASTER, AUX])
    c.ck("a note with media matches the oracle's id",
         signed_media["id"], V["noteMediaEventId"])
    c.ck("its canonical serialization is byte-exact",
         ip.call("nxEventSerialize", [signed_media]), V["noteMediaEventSer"])
    c.ck("the info-hash survives the round trip through the tag",
         ip.call("rsNostrMediaTags", [signed_media]), "ee" * 20)
    c.ck("an empty note is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "", ""]), "")
    c.ck("the all-zeros info-hash is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "x", "00" * 20]), "")
    c.ck("a malformed info-hash is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "x", "zz" * 20]), "")
    c.ck("a negative timestamp is refused",
         ip.call("rsNostrNoteEvent", [-1, "x", ""]), "")
    c.ck("an `r` tag that is not a magnet URI is ignored, not fetched",
         ip.call("rsNostrMediaTags",
                 [ip.call("nxEventBuild",
                          [1, "x", {"1": {"1": "r",
                                          "2": "https://example.com/"}},
                           1754870400])]), "")

    c.note("the bridge as a NIP-78 event, and the republish attack")
    bev = ip.call("rsNostrBridgeEvent", [br, MASTER, 1754870800, AUX])
    c.ck("the bridge event id matches the oracle",
         bev["id"], V["bridgeEventId"])
    c.ck("the bridge event signature matches the oracle",
         bev["sig"], V["bridgeEventSig"])
    c.ck("its canonical serialization is byte-exact",
         ip.call("nxEventSerialize", [bev]), V["bridgeEventSer"])
    back = ip.call("rsNostrBridgeFromEvent",
                   [ip.call("nxEventToJson", [bev])])
    c.ck("the bridge comes back out of its own event",
         back["handle"], V["handle"])
    other = to_str(bytes([0x43] * 32))
    stolen = ip.call("rsNostrBridgeEvent", [br, other, 1754870800, AUX])
    c.ck("somebody else's bridge inside my signed event is REFUSED",
         ip.call("rsNostrBridgeFromEvent",
                 [ip.call("nxEventToJson", [stolen])]), "")
    c.ck("a non-bridge kind is refused",
         ip.call("rsNostrBridgeFromEvent",
                 [ip.call("nxEventToJson",
                          [ip.call("rsNostrSignEvent",
                                   [note, MASTER, AUX])])]), "")
    c.ck("garbage JSON is refused, not thrown",
         ip.call("rsNostrBridgeFromEvent", ["not json at all"]), "")


def main(argv):
    terse = "--check" in argv
    c = Checker(terse)
    failures = []

    def fail(msg):
        print("check-script-vectors: %s" % msg)
        sys.exit(1)

    src, hits = build_source(fail)
    try:
        ip = LCS.Interp(src)
    except Exception as exc:                       # noqa: BLE001
        fail("the shipped script did not parse under the interpreter: %s: %s"
             % (type(exc).__name__, exc))
    install_pure_natives()
    V = REF["golden_vectors"]()

    if not terse:
        print("-- rewrites applied: " + ", ".join(
            "%s x%d" % (n, hits[n]) for n, _w, _f in REWRITES))
    check_pure(c, ip, V)
    if install_coin_natives():
        check_composed(c, ip, V)
    else:
        c.skip("tier 2 (the whole phase-8 rail)",
               "the committed %s is not present" %
               os.path.relpath(COIN_SO, SUITE))

    if c.failed:
        print("check-script-vectors: %d of %d check(s) FAILED"
              % (c.failed, c.n))
        return 1
    print("check-script-vectors: OK (%d checks; the shipped script executed "
          "against the oracle%s)"
          % (c.n, ", %d skipped" % c.skipped if c.skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
