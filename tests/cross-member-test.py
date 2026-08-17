#!/usr/bin/env python3
"""
cross-member-test.py - prove the suite's CROSS-MEMBER invariants headlessly,
against the real built shims, with no engine involved.

WHY THIS EXISTS. tests/suite-selftest.livecodescript asserts four things that
span two members each, and they are the suite's actual product claims. But that
harness is a .livecodescript: OXT is a GUI runtime, so until a human sits at an
engine, every one of those claims is "verified statically" - a claim about what
the code READS as. That is an uncomfortable place for the marquee assertion of
the whole suite to sit, because most of it is not a script question at all. "Do
libsodium and libtorrent derive the same ed25519 public key from one seed?" is a
question about two C libraries, and two C libraries are exactly what this
container has.

STATUS 2026-08-08: the engine pass has now happened, and the suite selftest
reported all four of these invariants green THROUGH THE SCRIPT LAYER as well.
That does not retire this file - it promotes it. This is the only check of the
four that can run headlessly at all, so it is the regression net: if a future
shim change breaks one of these invariants, CI says so here in seconds rather
than waiting for the next human at an engine.

CORRECTED 2026-08-17. The paragraph above used to say "runs headlessly on every
push", and that was false for as long as it stood. This file's ONE caller is
tools/build-all.sh, BELOW its `--gates` early exit - and both CI invocations
(suite-gates.yml, release-binaries.yml) pass --gates. So it ran in no lane at
all; it ran only when a human did a full local walk. Worse, the shape of the
skip meant that even when someone did run it without the shims built, it
printed the two header checks, a SKIP line, and then "every cross-member
invariant holds (measured natively, not reasoned)" and exited 0 - a green run
of a file whose entire value is the word "natively". Both halves are fixed:
CROSSMEMBER_REQUIRE_ALL (see report()) makes a skip a FAILURE where a skip is
indistinguishable from a pass, and suite-gates.yml gained a scoped job that
does the full walk and sets it. The lesson is the tree's own, from the root
CLAUDE.md: shipped is not run, and a docstring asserting a lane exists is not
that lane.

So this file takes the cross-member claims that do NOT depend on the script
layer and settles them where they can actually be settled: ctypes against the
built .so files. What remains for the engine pass is then honestly narrowed - it
is the FFI/marshalling layer and the script plumbing, not the cryptography.

WHAT IT PROVES (each mirrors a section of suite-selftest.livecodescript):

  1. ONE SEED, ONE IDENTITY. sxt_sign_keypair_from_seed and btx_dht_keypair,
     given the same 32 bytes, must produce the same ed25519 public key. If they
     ever diverge, every DHT mailbox the suite mints is addressed to a key its
     owner cannot sign for - the failure would be silent and total.
  2. THE TWO SECRET-KEY SPELLINGS. libsodium's "secret key" is seed || pk;
     libtorrent's DHT secret key is the EXPANDED SHA-512(seed) clamped form.
     sxt_sign_seed_to_expanded_key is the documented bridge between them, and
     this asserts it really is the right bridge rather than a plausible one.
  3. SODIUMXT SIGNS A BEP44 ITEM LIBTORRENT ACCEPTS. btx_dht_bep44_signbuf
     builds the canonical bytes with no secret key crossing the ABI; libsodium
     signs them; btx_dht_put_signed VERIFIES that foreign signature before
     storing. Two independent ed25519 implementations agreeing on one signature
     over one canonical buffer is the entire point of that seam. The negative
     matters as much: a well-formed signature made for a DIFFERENT seq must be
     refused, which proves the check binds the whole (salt, seq, value) tuple
     and not merely the hex shape.
  4. THE SHARED 60000-BYTE BUDGET. ENX_MAX_MESSAGE and DCX_MAX_MESSAGE must be
     equal. An app that switches transports at runtime - the whole premise of
     shipping both - would silently start losing messages if they drifted apart,
     and neither member's own tests can see the other's constant.

WHAT IT DELIBERATELY DOES NOT PROVE. Nothing about the .lcb layer: buffer
marshalling, UIntSize widths, Data bridging, handler dispatch. Those need the
engine and this file makes no claim about them. It also does not touch the
network: check 3 hands a put to a live session, which queues it into the
ordinary public DHT exactly as any client would, and nothing waits on a reply.

SKIPS, LOUDLY, when a shim has not been built. It drives the artifacts that
tools/build-all.sh produces, so it runs in the FULL walk, not in --gates.
Set CROSSMEMBER_REQUIRE_ALL=1 to turn every such skip into a failure; CI does,
because there a skip and a pass print almost the same thing and exit 0 alike.
"""

import ctypes
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The record wire format (torrentxt/src/btx_record.h, pinned by that member's
# own record_golden_test.py): u16 field count, then per field
# fid(1) ftype(1) len(u16) value. Big-endian throughout.
F_DHT_PUBLIC_KEY = 106
F_DHT_SECRET_KEY = 112
F_DHT_SEED = 113

failures = []
notes = []

# The LEGS, at the granularity at which this file can actually stop running -
# which is five, not the docstring's four. The BEP44 invariant splits at the
# session boundary: building the canonical bytes and signing them needs only
# the two shims, while the half that gives it its meaning (a SECOND ed25519
# implementation verifying that signature, and refusing one made for another
# seq) needs a live libtorrent session on top. Counting it as one leg would
# report "4 of 4" for a run that proved libsodium can sign - which nobody
# doubted - and never asked libtorrent whether it agreed.
LEGS = [
    "the shared 60000-byte budget",
    "one seed, one identity (the same ed25519 public key)",
    "the two secret-key spellings (seed||pk vs the expanded form)",
    "SodiumXT signs BEP44 canonical bytes",
    "libtorrent VERIFIES that foreign signature (and refuses a wrong-seq one)",
]
ran_legs = []


def leg(name):
    """Mark a leg as having actually executed. Called at the point its checks
    run, not where they are declared: the difference is the whole point of the
    summary line, which otherwise reports intent rather than coverage."""
    assert name in LEGS, f"cross-member-test: unknown leg {name!r}"
    ran_legs.append(name)


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        failures.append(name)
        print(f"  FAIL  {name}" + (f"\n        {detail}" if detail else ""))


def decode_kvrecord(buf):
    """{fid: value_bytes} from one packed record."""
    count, off = struct.unpack_from(">H", buf, 0)[0], 2
    out = {}
    for _ in range(count):
        fid, _ftype = buf[off], buf[off + 1]
        off += 2
        ln = struct.unpack_from(">H", buf, off)[0]
        off += 2
        out[fid] = buf[off:off + ln]
        off += ln
    return out


def load(path, names):
    lib = ctypes.CDLL(path)
    for n, restype, argtypes in names:
        f = getattr(lib, n)
        f.restype = restype
        f.argtypes = argtypes
    return lib


def out_buf(n):
    return ctypes.create_string_buffer(n)


def define_ints(header, *macros):
    """Read #define <macro> <int> out of a C header, so the constants this test
    compares are the SHIPPED ones and not a copy that can rot independently."""
    src = open(os.path.join(ROOT, header), encoding="utf-8").read()
    vals = {}
    for m in macros:
        hit = re.search(rf"^\s*#\s*define\s+{re.escape(m)}\s+(\d+)\s*$", src, re.M)
        if hit is None:
            sys.exit(f"cross-member-test: no #define {m} in {header}")
        vals[m] = int(hit.group(1))
    return vals


def main():
    print("cross-member-test: the invariants that span two members")

    # ---- 4. the shared budget (pure header read; no build needed) -----------
    print("\n== the 60000-byte budget both real-time transports enforce ==")
    enx = define_ints("enetxt/src/enx_abi.h", "ENX_MAX_MESSAGE")
    dcx = define_ints("datachannelxt/src/dcx_abi.h", "DCX_MAX_MESSAGE")
    check("ENX_MAX_MESSAGE == DCX_MAX_MESSAGE",
          enx["ENX_MAX_MESSAGE"] == dcx["DCX_MAX_MESSAGE"],
          f"enetxt says {enx['ENX_MAX_MESSAGE']}, datachannelxt says "
          f"{dcx['DCX_MAX_MESSAGE']}; an app that switches transports at runtime "
          f"would silently lose messages between those two numbers")
    check("the shared budget is 60000", enx["ENX_MAX_MESSAGE"] == 60000)
    leg(LEGS[0])

    sod_path = os.path.join(ROOT, "sodiumxt", "build", "sodiumxt.so")
    tor_path = os.path.join(ROOT, "torrentxt", "build", "torrentxt.so")
    if not (os.path.exists(sod_path) and os.path.exists(tor_path)):
        notes.append("SKIP the ed25519 and BEP44 checks: they need the built "
                     "sodiumxt and torrentxt shims (run tools/build-all.sh)")
        return report()

    sod = load(sod_path, [
        ("sxt_init", ctypes.c_int, []),
        ("sxt_sign_publickeybytes", ctypes.c_int, []),
        ("sxt_sign_secretkeybytes", ctypes.c_int, []),
        ("sxt_sign_seedbytes", ctypes.c_int, []),
        ("sxt_sign_bytes", ctypes.c_int, []),
        ("sxt_sign_expandedkeybytes", ctypes.c_int, []),
        ("sxt_sign_keypair_from_seed", ctypes.c_int,
         [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
          ctypes.c_char_p, ctypes.c_int]),
        ("sxt_sign_seed_to_expanded_key", ctypes.c_int,
         [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]),
        ("sxt_sign_detached", ctypes.c_int,
         [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
          ctypes.c_char_p, ctypes.c_int]),
    ])
    tor = load(tor_path, [
        ("btx_dht_keypair", ctypes.c_int, [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]),
        ("btx_dht_bep44_signbuf", ctypes.c_int,
         [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
          ctypes.c_char_p, ctypes.c_int]),
        ("btx_dht_put_signed", ctypes.c_int,
         [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
          ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p]),
        ("btx_session_new", ctypes.c_int, []),
        ("btx_session_free", ctypes.c_int, [ctypes.c_int]),
        ("btx_set_bool", ctypes.c_int, [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]),
        ("btx_last_error", ctypes.c_int, [ctypes.c_char_p, ctypes.c_int]),
    ])
    if sod.sxt_init() < 0:
        sys.exit("cross-member-test: sxt_init failed")

    def last_error():
        b = out_buf(1024)
        n = tor.btx_last_error(b, 1024)
        return b.raw[:n].decode("utf-8", "replace") if n > 0 else "(none)"

    # A fixed seed, not a random one: a failure here must be reproducible from
    # the log alone, and the invariant is not seed-dependent.
    seed = bytes(range(32))
    seed_hex = seed.hex()

    # ---- 1 and 2. one seed, one identity ------------------------------------
    print("\n== one seed: a SodiumXT identity AND a TorrentXT DHT identity ==")
    pk_len = sod.sxt_sign_publickeybytes()
    sk_len = sod.sxt_sign_secretkeybytes()
    exp_len = sod.sxt_sign_expandedkeybytes()
    check("libsodium reports a 32-byte seed", sod.sxt_sign_seedbytes() == 32)

    pk, sk = out_buf(pk_len), out_buf(sk_len)
    rc = sod.sxt_sign_keypair_from_seed(pk, pk_len, sk, sk_len, seed, len(seed))
    check("sxt_sign_keypair_from_seed succeeded", rc >= 0)
    sod_pk = pk.raw[:pk_len]

    rec = out_buf(4096)
    n = tor.btx_dht_keypair(seed_hex.encode(), rec, 4096)
    check("btx_dht_keypair succeeded", n > 0, last_error())
    fields = decode_kvrecord(rec.raw[:n]) if n > 0 else {}
    bt_pk_hex = fields.get(F_DHT_PUBLIC_KEY, b"").decode()
    bt_sk_hex = fields.get(F_DHT_SECRET_KEY, b"").decode()
    bt_seed_hex = fields.get(F_DHT_SEED, b"").decode()

    check("btx_dht_keypair echoes the seed it was given", bt_seed_hex == seed_hex,
          f"gave {seed_hex}, got {bt_seed_hex}")
    # THE headline invariant of the whole suite.
    check("libsodium and libtorrent derive the SAME ed25519 public key",
          sod_pk.hex() == bt_pk_hex,
          f"libsodium {sod_pk.hex()}\n        libtorrent {bt_pk_hex}")
    leg(LEGS[1])

    exp = out_buf(exp_len)
    rc = sod.sxt_sign_seed_to_expanded_key(exp, exp_len, seed, len(seed))
    check("sxt_sign_seed_to_expanded_key succeeded", rc >= 0)
    check("libtorrent's DHT secret key IS SodiumXT's EXPANDED key",
          exp.raw[:exp_len].hex() == bt_sk_hex,
          f"expanded  {exp.raw[:exp_len].hex()}\n        libtorrent {bt_sk_hex}")
    # And the negative that gives the one above its meaning: libsodium's OWN
    # secret key (seed || pk) is a different 64 bytes, so "they are both 64
    # bytes" is not what is being asserted.
    check("...and NOT libsodium's own seed||pk secret key",
          sk.raw[:sk_len].hex() != bt_sk_hex)
    leg(LEGS[2])

    # ---- 3. SodiumXT signs a BEP44 item libtorrent accepts -------------------
    print("\n== SodiumXT signs a BEP44 item TorrentXT verifies ==")
    value = b"18:oxt-suite-selftest"     # already bencoded; stored verbatim
    salt, seq, wrong_seq = b"oxt", b"7", b"8"

    def signbuf(sq):
        b = out_buf(4096)
        k = tor.btx_dht_bep44_signbuf(salt, sq, value, len(value), b, 4096)
        return (b.raw[:k] if k > 0 else None), k

    buf, k = signbuf(seq)
    check("btx_dht_bep44_signbuf produced the canonical bytes", buf is not None,
          last_error())
    buf2, _ = signbuf(seq)
    check("btx_dht_bep44_signbuf is deterministic", buf == buf2)
    # Pin the documented layout rather than trusting the shape: the salt segment,
    # the seq integer, and the verbatim value must all be in there.
    if buf is not None:
        check("the canonical buffer has BEP44's documented layout",
              buf == b"4:salt%d:%s" % (len(salt), salt) + b"3:seqi%se" % seq + b"1:v" + value,
              repr(buf))

    sig_len = sod.sxt_sign_bytes()
    sig = out_buf(sig_len)
    rc = sod.sxt_sign_detached(sig, sig_len, buf, len(buf), sk, sk_len)
    check("SodiumXT signed those exact bytes", rc >= 0 and sig_len == 64)
    leg(LEGS[3])

    wbuf, _ = signbuf(wrong_seq)
    wsig = out_buf(sig_len)
    sod.sxt_sign_detached(wsig, sig_len, wbuf, len(wbuf), sk, sk_len)

    s = tor.btx_session_new()
    if s <= 0:
        notes.append(f"SKIP the put_signed leg: no libtorrent session ({last_error()})")
    else:
        try:
            tor.btx_set_bool(s, b"enable_dht", 1)
            rc = tor.btx_dht_put_signed(s, bt_pk_hex.encode(), salt, seq,
                                        value, len(value),
                                        sig.raw[:sig_len].hex().encode())
            check("libtorrent ACCEPTS the libsodium signature", rc == 0, last_error())
            # The sharpest available negative: well-formed, correct length, and
            # valid - for another seq. Refusing it proves the verify binds the
            # whole (salt, seq, value) tuple.
            rc = tor.btx_dht_put_signed(s, bt_pk_hex.encode(), salt, seq,
                                        value, len(value),
                                        wsig.raw[:sig_len].hex().encode())
            check("libtorrent REFUSES a signature made for another seq", rc < 0)
            leg(LEGS[4])
        finally:
            tor.btx_session_free(s)

    return report()


def report():
    for n in notes:
        print(f"\ncross-member-test: {n}")

    # SAY WHAT RAN. Without this line the only difference between a full run
    # and one that measured two #defines and stopped is a SKIP paragraph three
    # lines above a sentence containing the word "natively" - and the eye reads
    # the sentence. The count is the honest headline, and it names the missing
    # legs rather than only counting them, so the reader does not have to know
    # what the five are to see which one is gone.
    missing = [n for n in LEGS if n not in ran_legs]
    print(f"\ncross-member-test: {len(ran_legs)} of {len(LEGS)} invariant legs ran")
    for n in missing:
        print(f"                   NOT run: {n}")

    if failures:
        print(f"\ncross-member-test: {len(failures)} FAILED: {failures}")
        return 1

    # A skip is right for a contributor who has not built the shims; it is
    # WRONG for CI, where "the native half silently did not run" and "the
    # native half passed" print almost the same thing and exit 0 either way.
    # Same split, and the same env-var shape, as coinxt's
    # COINXT_REQUIRE_CROSSCHECK (coinxt/tools/coin-kat.py,
    # coinxt/tools/check-selftest-vectors.py). Checked HERE rather than at each
    # skip site because the skips are appended from two places and a future
    # third would otherwise have to remember to opt in - which is the shape of
    # the omission that left this file uncalled in the first place.
    if notes and os.environ.get("CROSSMEMBER_REQUIRE_ALL"):
        print(f"\ncross-member-test: CROSSMEMBER_REQUIRE_ALL is set and "
              f"{len(notes)} leg group(s) were SKIPPED, so this run settled less "
              f"than it claims - build the shims (tools/build-all.sh) or unset "
              f"the variable")
        return 1

    if missing:
        # Reachable only without CROSSMEMBER_REQUIRE_ALL: still exit 0 (a
        # contributor's partial run is not a failure), but do not let the
        # closing sentence overstate what was measured.
        print("\ncross-member-test: the invariants that RAN hold "
              "(measured natively, not reasoned); the rest were not settled")
        return 0
    print("\ncross-member-test: every cross-member invariant holds "
          "(measured natively, not reasoned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
