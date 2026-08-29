#!/usr/bin/env python3
"""export-protocol-vectors.py - the Riptide Protocol conformance bundle.

Writes docs/protocol-vectors.json: every golden vector the oracle derives
(the same set the harness and golden test pin, traced to anchors OUTSIDE
this repository) plus a set of REFUSAL vectors - records deliberately
built wrong that a conforming implementation must reject. The bundle is
what lets an implementation in any language test itself against bytes
rather than prose; the prose is docs/RIPTIDE-PROTOCOL.md at the suite
root, and the two are released together.

THE FILE IS GENERATED, DETERMINISTICALLY. The oracle's golden identity is
the fixed master seed 0x42*32, every timestamp and nonce in it is chosen,
and the tampers below are byte-arithmetic on those outputs - so `--check`
can regenerate the whole bundle and require the committed copy to match
byte-for-byte, which is the same freshness contract every generated file
in this tree carries.

`--check` also EXECUTES the bundle before comparing it:
  - every signed golden record re-verifies under the oracle's own
    verifiers (the ed25519 author signatures, both bridge signatures);
  - every DHT target in the bundle recomputes from its record's bytes;
  - every refusal vector marked executed=true is fed to the oracle
    verifier named in its `checkedBy` and must REFUSE.
A refusal the oracle cannot execute (the script layer's parsers hold it
instead) ships with executed=false and names the in-repo check that pins
it - the split is printed, because a bundle that overstates what it
proved is worse than a smaller honest one (the coinxt constant-gate
lesson).

Run from riptide/:  python3 tools/export-protocol-vectors.py [--check]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
OUT = os.path.join(MEMBER, "docs", "protocol-vectors.json")

BUNDLE_FORMAT = "riptide-protocol-vectors"
BUNDLE_VERSION = 1


def load_oracle():
    """exec-load the oracle from source (no importlib, no __pycache__ - the
    drift-oracle rule check-selftest-vectors.py already follows)."""
    path = os.path.join(HERE, "riptide_reference.py")
    ns = {}
    with open(path, "r", encoding="utf-8") as fh:
        exec(compile(fh.read(), path, "exec"), ns)
    return ns


def _flip_last(hexstr):
    """The record with its LAST byte xor 0x01 - a one-bit signature tamper."""
    raw = bytearray(bytes.fromhex(hexstr))
    raw[-1] ^= 1
    return raw.hex()


def _flip_at(hexstr, index):
    raw = bytearray(bytes.fromhex(hexstr))
    raw[index] ^= 1
    return raw.hex()


def refusal_vectors(R, g):
    """(entries, executables): the JSON rows and, keyed by name, the
    callables --check runs. Each callable returns True when the oracle
    REFUSED (the vector behaved)."""
    entries = []
    execs = {}

    def refuses(fn):
        def run():
            try:
                fn()
            except (ValueError, AssertionError):
                return True
            return False
        return run

    def add(name, spec_rule, checked_by, vector_hex, note, fn=None):
        entries.append({
            "name": name,
            "specRule": spec_rule,
            "checkedBy": checked_by,
            "vector": vector_hex,
            "executed": fn is not None,
            "note": note,
        })
        if fn is not None:
            execs[name] = refuses(fn)

    ed_verify = R["_verify_ed25519"]
    handle_pub = bytes.fromhex(g["handle"])

    # ---- author-signature tampers: the verify direction must refuse ----
    for rec_key, label in (("post1", "a kind-D post"),
                           ("postC", "a kind-C post"),
                           ("prekeyRec", "an RSK1 prekey record"),
                           ("intro", "an RSI1 intro")):
        tampered = _flip_last(g[rec_key])

        def fn(t=tampered):
            raw = bytes.fromhex(t)
            if ed_verify(raw[-64:], raw[:-64], handle_pub):
                raise RuntimeError("verified")
            raise ValueError("refused")
        add("tampered authorSig on " + label, "sig-verify",
            "oracle _verify_ed25519", tampered,
            "the last signature byte is flipped; ed25519 verification of "
            "the final 64 bytes over everything before them must fail",
            fn)

    # ---- the head's BEP44 signature over the canonical buffer ----
    tampered_buf = _flip_at(g["headBuf"], 0)

    def head_fn(t=tampered_buf):
        if ed_verify(bytes.fromhex(g["headSig"]), bytes.fromhex(t),
                     handle_pub):
            raise RuntimeError("verified")
        raise ValueError("refused")
    add("tampered BEP44 signing buffer under the head signature",
        "dht-head", "oracle _verify_ed25519", tampered_buf,
        "one flipped byte in the canonical salt/seq/v buffer; the "
        "recorded headSig must no longer verify", head_fn)

    # ---- the doubly-signed bridge: each half alone is worthless ----
    for name, idx, note in (
            ("bridge with a tampered ed25519 half", 211,
             "byte 211 (inside edSig) flipped; verify_bridge must refuse"),
            ("bridge with a tampered BIP-340 half", 275,
             "byte 275 (inside schSig) flipped; verify_bridge must refuse"),
            ("bridge with a tampered signed body", 4,
             "byte 4 (the handle's first hex char) flipped; BOTH "
             "signatures must fail over the changed preimage")):
        tampered = _flip_at(g["bridge"], idx)
        add(name, "rsn1-bridge", "oracle verify_bridge", tampered, note,
            lambda t=tampered: (R["verify_bridge"](bytes.fromhex(t)),))
    truncated = g["bridge"][:-2]
    add("bridge truncated by one byte", "rsn1-bridge",
        "oracle verify_bridge", truncated,
        "275 bytes; RSN1 is exactly 276 and a strict parser refuses "
        "before any crypto runs",
        lambda t=truncated: (R["verify_bridge"](bytes.fromhex(t)),))
    wrong_magic = "51" + g["bridge"][2:]
    add("bridge with a wrong magic", "rsn1-bridge",
        "oracle verify_bridge", wrong_magic,
        "first byte changed: not RSN1, refused on the magic",
        lambda t=wrong_magic: (R["verify_bridge"](bytes.fromhex(t)),))

    # ---- RSL1 challenge strict parse ----
    chal = g["lanChallenge"]
    short = chal[:-2]
    add("LAN challenge truncated by one byte", "rsl1-admission",
        "oracle _lan_parse_challenge", short,
        "the declared name length plus the 32-byte nonce no longer fit; "
        "a strict parser refuses on total length",
        lambda t=short: (R["_lan_parse_challenge"](bytes.fromhex(t)),))
    wrong_kind = chal[:8] + "52" + chal[10:]  # "C" -> "R"
    add("LAN challenge with kind R", "rsl1-admission",
        "oracle _lan_parse_challenge", wrong_kind,
        "the kind byte is R; a challenge parser accepts only C, byte-exact",
        lambda t=wrong_kind: (R["_lan_parse_challenge"](bytes.fromhex(t)),))

    # ---- builder-side caps: a conforming BUILDER must refuse these ----
    id_seed = bytes.fromhex(g["idSeed"])
    master = bytes.fromhex(g["master"])
    builder_cases = [
        ("a display name over 64 UTF-8 bytes", "rsh1-head",
         "oracle build_head",
         lambda: R["build_head"](1, "x" * 65, None, None, "", None)),
        ("a kind-C post with 17 chunk targets", "rsp1-post",
         "oracle build_post_chunked",
         lambda: R["build_post_chunked"](1, None, ["ab" * 20] * 17, [],
                                         id_seed)),
        ("a kind-C post with zero chunk targets", "rsp1-post",
         "oracle build_post_chunked",
         lambda: R["build_post_chunked"](1, None, [], [], id_seed)),
        ("a post with 9 media attachments", "rsp1-post",
         "oracle build_post",
         lambda: R["build_post"](1, None, "x", ["ab" * 20] * 9, id_seed)),
        ("a non-hex DHT target", "hex40",
         "oracle build_post",
         lambda: R["build_post"](1, "zz" * 20, "x", [], id_seed)),
        ("a 39-char DHT target", "hex40",
         "oracle build_post",
         lambda: R["build_post"](1, "a" * 39, "x", [], id_seed)),
        ("an RSM1 frame with an unknown kind", "rsm1-frame",
         "oracle build_dm_frame",
         lambda: R["build_dm_frame"](b"X", b"payload")),
        ("an RSM1 frame with an empty payload", "rsm1-frame",
         "oracle build_dm_frame",
         lambda: R["build_dm_frame"](b"I", b"")),
        ("an RSM1 frame over the rp1 60000-byte cap", "rsm1-frame",
         "oracle build_dm_frame",
         lambda: R["build_dm_frame"](b"M", b"x" * 60000)),
        ("a DM message with an empty body", "dm-message",
         "oracle build_dm_message",
         lambda: R["build_dm_message"](b"T", 1, "")),
        ("a lowercase DM message kind t", "dm-message",
         "oracle build_dm_message",
         lambda: R["build_dm_message"](b"t", 1, "x")),
        ("a LAN device name over 32 bytes", "rsl1-name",
         "oracle lan_build_challenge",
         lambda: R["lan_build_challenge"]("x" * 33, b"\x5a" * 32)),
        ("a LAN nonce that is not 32 bytes", "rsl1-admission",
         "oracle lan_build_challenge",
         lambda: R["lan_build_challenge"]("laptop", b"\x5a" * 31)),
        ("a draft over 4096 UTF-8 bytes", "rsl1-sync",
         "oracle lan_build_draft",
         lambda: R["lan_build_draft"]("phone", 1, "x" * 4097, master)),
        ("a media handoff with the all-zeros info-hash", "rsl1-sync",
         "oracle lan_build_handoff",
         lambda: R["lan_build_handoff"]("phone", 1, "0" * 40, "a.mp4", 1,
                                        master)),
        ("a media handoff file name over 255 bytes", "rsl1-sync",
         "oracle lan_build_handoff",
         lambda: R["lan_build_handoff"]("phone", 1, "ee" * 20, "x" * 256,
                                        1, master)),
        ("an anon feed-page title over 64 bytes", "onion-serving",
         "oracle anon_feed_page",
         lambda: R["anon_feed_page"]("x" * 65, [])),
    ]
    for name, rule, checked_by, fn in builder_cases:
        add(name, rule, checked_by, None,
            "builder-refusal case: a conforming builder must refuse "
            "these inputs (and a strict parser the resulting shape)", fn)

    # ---- pinned but held by the SCRIPT layer's parsers, not the oracle ----
    # A presence record with a reserved flag bit set, CORRECTLY signed - the
    # fail-closed rule is about unknown bits, not about forgery.
    nb = "phone".encode("utf-8")
    body = (R["LAN_MAGIC"] + b"P" + bytes([len(nb)]) + nb + bytes([2])
            + R["_u64"](4))
    signed = body + R["_lan_sync_sign"](body, master)
    add("presence record with reserved flag bit 1 set, correctly signed",
        "rsl1-sync", "script rsLanParsePresence "
        "(riptide-selftest, in the suite paste)", signed.hex(),
        "flags=0x02 under a VALID signature; a conforming parser refuses "
        "unknown flag bits fail-closed", None)
    # A 96-byte would-be key file: RIPTKEY1 is exactly 97.
    add("a 96-byte RIPTKEY1 file", "riptkey1",
        "script rsOpenMasterSeed (riptide-selftest, in the suite paste)",
        ("52 49 50 54 4b 45 59 31 45".replace(" ", "")) + "00" * 87,
        "one byte short of the exact 97; refused on length before any "
        "crypto runs", None)

    return entries, execs


def build_bundle(R):
    g = R["golden_vectors"]()
    refusals, execs = refusal_vectors(R, g)
    bundle = {
        "format": BUNDLE_FORMAT,
        "bundleVersion": BUNDLE_VERSION,
        "spec": "docs/RIPTIDE-PROTOCOL.md (at the suite root)",
        "source": "generated by riptide/tools/export-protocol-vectors.py "
                  "from riptide/tools/riptide_reference.py; regenerate "
                  "with that tool, never edit by hand",
        "anchors": [
            "sxKdfDerive semantics: the sodiumxt C KAT "
            "(sodium_smoke_test.c test_kdf)",
            "ed25519: RFC 8032 reference implementation + the "
            "cross-project BEP44 conformance seed",
            "v3 onion: a real published onion address (torproject.org)",
            "secp256k1/BIP-340/NIP-19: the published vector sets, via "
            "nostrxt/tools/nostr_reference.py (refuses to load when it "
            "cannot reproduce them)",
        ],
        "goldenIdentity": {
            "note": "every golden below derives from this fixed master; "
                    "chosen timestamps/nonces are in the vectors "
                    "themselves. Byte strings are lowercase hex.",
            "master": g["master"],
        },
        "golden": g,
        "refusals": refusals,
    }
    return bundle, execs


def render(bundle):
    return json.dumps(bundle, indent=1, sort_keys=True,
                      separators=(",", ": ")) + "\n"


def execute(R, bundle, execs):
    """Prove the bundle before shipping or trusting it. Returns
    (verified_count, executed_refusals, held_by_script)."""
    g = bundle["golden"]
    ed_verify = R["_verify_ed25519"]
    handle_pub = bytes.fromhex(g["handle"])
    checks = 0

    # every signed golden record verifies
    for key in ("post1", "post2", "postC", "prekeyRec", "intro"):
        raw = bytes.fromhex(g[key])
        assert ed_verify(raw[-64:], raw[:-64], handle_pub), key
        checks += 1
    raw = bytes.fromhex(g["anon0Prekey"])
    assert ed_verify(raw[-64:], raw[:-64],
                     bytes.fromhex(g["anon0Handle"])), "anon0Prekey"
    checks += 1
    assert ed_verify(bytes.fromhex(g["headSig"]),
                     bytes.fromhex(g["headBuf"]), handle_pub), "headSig"
    checks += 1
    assert R["verify_bridge"](bytes.fromhex(g["bridge"])) == \
        (g["handle"], g["nostrPubkey"]), "bridge"
    checks += 1

    # every target recomputes from its record
    for rec, tgt in (("post1", "post1Target"), ("post2", "post2Target"),
                     ("postC", "postCTarget"),
                     ("prekeyRec", "prekeyRecTarget"),
                     ("intro", "introTarget")):
        assert R["immutable_target"](bytes.fromhex(g[rec])) == g[tgt], tgt
        checks += 1

    # every executed refusal refuses
    ran = 0
    for entry in bundle["refusals"]:
        if not entry["executed"]:
            continue
        fn = execs[entry["name"]]
        if not fn():
            print("export-protocol-vectors: refusal vector %r did NOT "
                  "refuse - the bundle is lying" % entry["name"])
            sys.exit(1)
        ran += 1
    held = sum(1 for e in bundle["refusals"] if not e["executed"])
    return checks, ran, held


def main(argv):
    R = load_oracle()
    bundle, execs = build_bundle(R)
    checks, ran, held = execute(R, bundle, execs)
    text = render(bundle)

    if "--check" in argv:
        if not os.path.exists(OUT):
            print("export-protocol-vectors: %s does not exist; run the "
                  "tool without --check" % os.path.relpath(OUT, MEMBER))
            return 1
        with open(OUT, "r", encoding="utf-8") as fh:
            committed = fh.read()
        if committed != text:
            print("export-protocol-vectors: docs/protocol-vectors.json is "
                  "STALE - regenerate with "
                  "python3 tools/export-protocol-vectors.py")
            return 1
        print("export-protocol-vectors: OK (%d golden verifications, %d "
              "refusal vectors executed and refused, %d held by the "
              "script layer's own checks; the committed bundle matches "
              "the oracle byte-for-byte)" % (checks, ran, held))
        return 0

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("export-protocol-vectors: wrote %s (%d golden vectors, %d "
          "refusals: %d executed here, %d held by the script layer)"
          % (os.path.relpath(OUT, MEMBER), len(bundle["golden"]),
             len(bundle["refusals"]), ran, held))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
