#!/usr/bin/env python3
# riptide_golden_test.py - pins the riptide pure-compute layer byte-for-byte.
#
# Pure reference, runs anywhere, no engine and no built library needed - the
# same shape as torrentxt/tests/record_golden_test.py. The expected values
# below are INLINE LITERALS, deliberately: the oracle (tools/riptide_reference.py)
# computes each vector and this file compares it against a hand-pinned copy, so
# a drift in the oracle fails here instead of silently re-pinning itself. The
# same literals appear as constants in tests/riptide-selftest.livecodescript,
# and tools/check-selftest-vectors.py proves THAT copy matches the oracle too -
# so the Python model, this test, and the script harness all hold one set of
# bytes.
#
# The oracle is exec-loaded from source rather than imported: importlib
# consults __pycache__, and a stale .pyc is exactly the failure mode a drift
# gate must not have (the coinxt check-selftest-vectors.py lesson).

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.join(_HERE, "..", "tools", "riptide_reference.py")

ref = {}
with open(_REF, "r", encoding="utf-8") as f:
    exec(compile(f.read(), _REF, "exec"), ref)

FAILURES = []


def check(name, got, want):
    if got != want:
        FAILURES.append("%s:\n  got  %r\n  want %r" % (name, got, want))


def check_raises(name, fn):
    try:
        fn()
    except (ValueError, AssertionError):
        return
    FAILURES.append("%s: expected a refusal, got none" % name)


# --- the KDF subkey tree (master 0x42 * 32) --------------------------------

MASTER = bytes([0x42] * 32)

check("idSeed", ref["identity_seed"](MASTER).hex(),
      "9c7b6be59e0884a1923505cf1390a1d01b5b7a258c582d9518e722c07bd8650c")
check("dmSeed", ref["dm_seed"](MASTER).hex(),
      "4dca52e87fa8919a5699fd35f79d6e4a417bdf0cf3e16d5c549aac6cd8c2b391")
check("lanKey", ref["lan_key"](MASTER).hex(),
      "fb9441aca42ca2212b3b16ea0b615d70e6d8c5ab3f6ac9a90a5e648fd58ac85f")
check("anon0Seed", ref["anon_seed"](MASTER, 0).hex(),
      "6940ca2dc794eb4c533feb196481c0547b1257d3837925affe35dae97682c68a")

# distinct roles must yield distinct keys
_subkeys = [ref["identity_seed"](MASTER), ref["dm_seed"](MASTER),
            ref["lan_key"](MASTER), ref["anon_seed"](MASTER, 0),
            ref["anon_seed"](MASTER, 1)]
check("subkeys distinct", len(set(_subkeys)), len(_subkeys))

# --- identity -> handle -> onion -------------------------------------------

ID_SEED = ref["identity_seed"](MASTER)
HANDLE = "5a546e4fef5d1b76f94dc1b2eded75c44bffc900af7461a26d8427453a92f22d"
ONION = "ljkg4t7plunxn6knygzo33lvyrf77siav52gditnqqtukous6iwwe6yd.onion"

check("handle", ref["handle_from_identity_seed"](ID_SEED), HANDLE)
check("onion", ref["onion_from_pubkey"](bytes.fromhex(HANDLE)), ONION)
check("onion inverse", ref["pubkey_from_onion"](ONION).hex(), HANDLE)

# the cross-project conformance seed ties riptide's handle derivation to the
# vector bep44_golden_test.py already pins
check("conformance pub",
      ref["ed25519_publickey"](bytes.fromhex(
          "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7"
      )).hex(),
      "672e8e0b259627f15c772ec0d61f15cd786ce2bc7244549255f9d6cfaac300b2")

# --- rendezvous derivations ------------------------------------------------

CONF_PUB = "672e8e0b259627f15c772ec0d61f15cd786ce2bc7244549255f9d6cfaac300b2"

check("inboxId", ref["inbox_id"](HANDLE),
      "3cf4170b3e7253387f351af14eb1071224d0140e")
check("roomId", ref["room_id"](HANDLE, CONF_PUB, b"golden-salt"),
      "3a57d3ad644536e20a4486d31bde5ecb3902d3a5")
# a room id must not depend on who derives it
check("roomId symmetric",
      ref["room_id"](CONF_PUB, HANDLE, b"golden-salt"),
      ref["room_id"](HANDLE, CONF_PUB, b"golden-salt"))

# --- RSP1 posts and the tamper-evident chain -------------------------------

ZERO = "0" * 40

POST1_HEX = (
    "5253503100000000689932803030303030303030303030303030303030303030"
    "303030303030303030303030303030303030303044000e68656c6c6f2c207269"
    "70746964650084b56e15631b88e780a74e22241c00efc34b63e50fd645ba651b"
    "b27dc41cac5953396ae8f848ef9b81711b08baa5b764fc5746bfd02122f36ac5"
    "a17f87a88f01")
POST1_TARGET = "a161e3add5a4d78080db9219583e6a988954705c"
POST2_HEX = (
    "5253503100000000689932bc6131363165336164643561346437383038306462"
    "393231393538336536613938383935343730356344000b7365636f6e6420706f"
    "7374016565656565656565656565656565656565656565656565656565656565"
    "65656565656565656565654d29a287d8ac5360688b548ee342f7754287e3ddc6"
    "04fe2a5160263ce1ef7a5526f9a750dc05d0edf2c317ea0b3dca062e745d0e2f"
    "b6c1b381225c7d19dba10f")
POST2_TARGET = "21d0180855ef47084fd8a9825f4ec8516608161a"

post1 = ref["build_post"](1754870400, ZERO, "hello, riptide", [], ID_SEED)
check("post1 bytes", post1.hex(), POST1_HEX)
check("post1 target", ref["immutable_target"](post1), POST1_TARGET)

post2 = ref["build_post"](1754870460, POST1_TARGET, "second post",
                          ["ee" * 20], ID_SEED)
check("post2 bytes", post2.hex(), POST2_HEX)
check("post2 target", ref["immutable_target"](post2), POST2_TARGET)

# the chain property itself: post2 embeds post1's target at a fixed offset
# (magic 4 + timestamp 8), so altering post1 breaks the walk
check("chain link", post2[12:52], POST1_TARGET.encode("ascii"))

# the signature really is ed25519 over everything before it
body, sig = post2[:-64], post2[-64:]
check("post2 sig", sig, ref["ed25519_sign"](body, ID_SEED))

# a chunked post carries its chunk list in order
chunked = ref["build_post_chunked"](1754870500, POST2_TARGET,
                                    ["11" * 20, "22" * 20], [], ID_SEED)
check("chunked kind", chunked[52:53], b"C")
check("chunked count", chunked[53], 2)
check("chunked first", chunked[54:94], ("11" * 20).encode("ascii"))

# --- RSH1 head -------------------------------------------------------------

HEAD_HEX = (
    "5253483100000000000000070752697074696465323164303138303835356566"
    "3437303834666438613938323566346563383531363630383136316161626162"
    "6162616261626162616261626162616261626162616261626162616261626162"
    "616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c76797266"
    "3737736961763532676469746e717174756b6f757336697777653679642e6f6e"
    "696f6e6364636463646364636463646364636463646364636463646364636463"
    "6463646364636463646364")
HEAD_SIG = (
    "6d4560c6c20794dfbb71e4592679c242472d459728051a90bcedb123ec2404a5"
    "44882525242888eda72dcd3c820a5538a80b9fb63e09d4c1bc3487db67730b0f")

head = ref["build_head"](7, "Riptide", POST2_TARGET, "ab" * 20, ONION,
                         "cd" * 20)
check("head bytes", head.hex(), HEAD_HEX)
check("head size fits BEP44", len(head) <= 1000, True)

head_v = ref["bencode_bytes"](head)
check("head value prefix", head_v[:4], b"203:")
# the exact canonical buffer the head's BEP44 signature covers - pinned as an
# assembly rule (prefix + the already-pinned head bytes) so the salt segment,
# the seq encoding, and the value framing are each held to fixed bytes; the
# script layer's rsBep44SignBuf pins the same bytes as kRsGoldHeadBufHex
check("head buf",
      ref["bep44_signbuf"](b"riptide-head", 7, head_v),
      b"4:salt12:riptide-head3:seqi7e1:v203:" + bytes.fromhex(HEAD_HEX))
check("head sig",
      ref["ed25519_sign"](
          ref["bep44_signbuf"](b"riptide-head", 7, head_v), ID_SEED).hex(),
      HEAD_SIG)

# the head names post2 as latest: offset = magic 4 + seq 8 + nameLen 1 + name 7
check("head latest field", head[20:60], POST2_TARGET.encode("ascii"))

# --- caps refuse instead of truncating -------------------------------------

check_raises("name over cap", lambda: ref["build_head"](
    1, "x" * 65, ZERO, ZERO, "", ZERO))
check_raises("bad onion length", lambda: ref["build_head"](
    1, "a", ZERO, ZERO, "short.onion", ZERO))
check_raises("bad target", lambda: ref["build_post"](
    1, "zz" * 20, "hi", [], ID_SEED))
check_raises("media over cap", lambda: ref["build_post"](
    1, ZERO, "hi", ["aa" * 20] * 9, ID_SEED))
check_raises("chunk count zero", lambda: ref["build_post_chunked"](
    1, ZERO, [], [], ID_SEED))
check_raises("text over budget", lambda: ref["build_post"](
    1, ZERO, "x" * 881, [], ID_SEED))
check_raises("kdf wrong master len", lambda: ref["kdf_derive"](
    b"\x01" * 31, 1, 32))
check_raises("kdf wrong ctx len", lambda: ref["kdf_derive"](
    b"\x01" * 32, 1, 32, context=b"short"))

# --- BEP44 anchors reused from the torrentxt golden ------------------------

check("signbuf salted",
      ref["bep44_signbuf"](b"rp-prekeys", 1, b"2:hi"),
      b"4:salt10:rp-prekeys3:seqi1e1:v2:hi")
check("signbuf saltless",
      ref["bep44_signbuf"](b"", 7, b"2:hi"),
      b"3:seqi7e1:v2:hi")
check("bencode empty", ref["bencode_bytes"](b""), b"0:")

# --- phase 4: X25519 / crypto_kx (anchored against real libsodium by
# --- tools/emit-kx-anchor.py; see the oracle's self-check provenance) ------

DM_KX_PUB = "d946190585386568c3123a6fa706f94f5140fdfe647ab51fdf76e3f6e5799d3c"
CONF_KX_PUB = "9cf14a375404bd5f3fc048647215af20b506717fdab3f6e7df50c64e837f2059"
SESSION_RX = "0cf0c702142da300ac5d769dff39a1b4aabe4842b617cdf4a624815290b4ba38"
SESSION_TX = "2f8bb162c5e2d4346eadcf2a47804458428840336303e629d1ac20e8375dfe83"

dm_kx_pk, dm_kx_sk = ref["kx_seed_keypair"](ref["dm_seed"](MASTER))
conf_kx_pk, conf_kx_sk = ref["kx_seed_keypair"](bytes.fromhex(
    "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7"))
check("dm kx pub", dm_kx_pk.hex(), DM_KX_PUB)
check("conf kx pub", conf_kx_pk.hex(), CONF_KX_PUB)
# role rule: the golden handle (5a54...) sorts below the conformance pub
# (672e...), so the golden side is the kx CLIENT
rx, tx = ref["kx_client_session_keys"](dm_kx_pk, dm_kx_sk, conf_kx_pk)
check("session rx", rx.hex(), SESSION_RX)
check("session tx", tx.hex(), SESSION_TX)
srx, stx = ref["kx_server_session_keys"](conf_kx_pk, conf_kx_sk, dm_kx_pk)
check("session cross-match rx", srx.hex(), SESSION_TX)
check("session cross-match tx", stx.hex(), SESSION_RX)
check_raises("kx bad seed len", lambda: ref["kx_seed_keypair"](b"\x01" * 31))

# --- phase 4: the DM wire records (RSK1 / RSI1 / RSM1 / inner message) -----

PREKEY_REC_HEX = (
    "52534b31643934363139303538353338363536386333313233613666613730366639"
    "3466353134306664666536343761623531666466373665336636653537393964336"
    "34af78ee3dc74534030feac4a92bf540c17cd9fb992c8e3e0eeb9af2822c9d6c40d"
    "f10e2880b8a395bfe1cf076d8a325c00d9fbb046987657c080faff77a98609")
PREKEY_REC_TARGET = "5b92cd531aa0537e43def0f737e2a61c48673008"
INTRO_TARGET = "2906ed430af1a60385dc2bc70bd99d621d238d4d"
DM_MSG_HEX = "54000000006899333468656c6c6f2c20646d"

prekey_rec = ref["build_prekey"](DM_KX_PUB, ID_SEED)
check("prekey bytes", prekey_rec.hex(), "".join(PREKEY_REC_HEX.split()))
check("prekey length", len(prekey_rec), 132)
check("prekey target", ref["immutable_target"](prekey_rec), PREKEY_REC_TARGET)
# the trailing 64 bytes really are ed25519 by the identity key over the rest
check("prekey sig", prekey_rec[-64:],
      ref["ed25519_sign"](prekey_rec[:-64], ID_SEED))

intro = ref["build_intro"](HANDLE, DM_KX_PUB, CONF_PUB, 1754870520, ID_SEED)
check("intro length", len(intro), 268)
check("intro target", ref["immutable_target"](intro), INTRO_TARGET)
check("intro magic", intro[:4], b"RSI1")
check("intro sender", intro[4:68], HANDLE.encode("ascii"))
check("intro kx pub", intro[68:132], DM_KX_PUB.encode("ascii"))
check("intro recipient", intro[132:196], CONF_PUB.encode("ascii"))
check("intro sig", intro[-64:], ref["ed25519_sign"](intro[:-64], ID_SEED))

frame = ref["build_dm_frame"](b"I", intro)
check("frame magic+kind", frame[:5], b"RSM1I")
check("frame payload", frame[5:], intro)

msg = ref["build_dm_message"](b"T", 1754870580, "hello, dm")
check("dm message bytes", msg.hex(), DM_MSG_HEX)
check("dm message kind", msg[:1], b"T")

check_raises("prekey bad hex", lambda: ref["build_prekey"]("zz" * 32, ID_SEED))
check_raises("intro bad handle", lambda: ref["build_intro"](
    "zz" * 32, DM_KX_PUB, CONF_PUB, 1, ID_SEED))
check_raises("frame bad kind", lambda: ref["build_dm_frame"](b"X", b"x"))
check_raises("frame empty payload", lambda: ref["build_dm_frame"](b"M", b""))
check_raises("frame over cap", lambda: ref["build_dm_frame"](
    b"M", b"x" * 60000))
check_raises("message bad kind", lambda: ref["build_dm_message"](
    b"X", 1, "hi"))
check_raises("message empty body", lambda: ref["build_dm_message"](
    b"T", 1, ""))

# --- phase 6: LAN mesh admission (fixed nonce -> deterministic) ------------

LAN_PUB = "2008657949f2e06e9786315cde35ecf4aa419152787e4fa1670f189dc07285d9"
LAN_NONCE = "5a" * 32
LAN_CHALLENGE_HEX = (
    "52534c3143066c6170746f70" + "5a" * 32)
LAN_RESPONSE_HEX = (
    "52534c31520570686f6e65"
    "8941d7087e125898cb16acdc61f814e91ea4cd861d133fdd5f38e611ea8416958b"
    "2e5a1a96540afdbe6f979f475abf77b235d8c1c06ca8306c3e04f0bec7ae08")

lan_pub, lan_seed = ref["lan_keys"](MASTER)
check("lan pub", lan_pub.hex(), LAN_PUB)
challenge = ref["lan_build_challenge"]("laptop", bytes.fromhex(LAN_NONCE))
check("lan challenge bytes", challenge.hex(), LAN_CHALLENGE_HEX)
response = ref["lan_build_response"](challenge, "phone", MASTER)
check("lan response bytes", response.hex(), LAN_RESPONSE_HEX)
# the response really is a valid signature under the LAN public, and the
# name binding really holds (a signature made for "phone" does not verify
# as "laptop")
check("lan response verifies",
      ref["_verify_ed25519"](response[-64:],
                             ref["lan_sig_message"](bytes.fromhex(LAN_NONCE),
                                                    "phone"), lan_pub),
      True)
check("lan name binding",
      ref["_verify_ed25519"](response[-64:],
                             ref["lan_sig_message"](bytes.fromhex(LAN_NONCE),
                                                    "laptop"), lan_pub),
      False)
check_raises("lan name over cap", lambda: ref["lan_build_challenge"](
    "x" * 33, bytes.fromhex(LAN_NONCE)))
check_raises("lan bad nonce len", lambda: ref["lan_build_challenge"](
    "a", b"\x00" * 31))

# the W welcome: mutual auth back to the joiner, bound to THIS handshake by
# the joiner's own response signature
LAN_WELCOME_HEX = (
    "52534c3157066c6170746f7006c1a710d7dd13ac6ade03ec0a853563c1c50692"
    "3a042d38473d15abb29761c9699a013070c4f4a24527cafde5fb30ea0375d56a"
    "e85e53a1726f91612cf2b805")

welcome = ref["lan_build_welcome"](response, "laptop", MASTER)
check("lan welcome bytes", welcome.hex(), LAN_WELCOME_HEX)
check("lan welcome verifies",
      ref["_verify_ed25519"](
          welcome[-64:],
          ref["lan_welcome_sig_message"](response[-64:], "laptop"), lan_pub),
      True)
# a welcome is bound to ONE handshake: against a different response's
# signature it must fail (the replay the binding exists to stop)
response2 = ref["lan_build_response"](
    ref["lan_build_challenge"]("laptop", b"\x11" * 32), "phone", MASTER)
check("lan welcome handshake binding",
      ref["_verify_ed25519"](
          welcome[-64:],
          ref["lan_welcome_sig_message"](response2[-64:], "laptop"), lan_pub),
      False)
check_raises("lan welcome bad resp sig len",
             lambda: ref["lan_welcome_sig_message"](b"\x00" * 63, "x"))

# --- phase 7: the anon persona + BTXO framing ------------------------------

ANON0_HANDLE = "e051209271559dbd241ae6d14d60cd8e6ffd84f682ee96129146e6209d0106e9"
ANON0_ONION = "4bisbetrkwo32ja243iu2ygnrzx73bhwqlxjmeuri3tcbhiba3u2abyd.onion"
BTXO_HEADER_HEX = "4254584f0100000a7365637265742e747874000000000000000b"
BTXO_FRAME_HEX = "0000000b68656c6c6f20776f726c64"

check("anon0 handle", ref["anon_handle"](MASTER, 0), ANON0_HANDLE)
check("anon0 onion", ref["anon_onion"](MASTER, 0), ANON0_ONION)
# the anon handle is the anon SEED's ed25519 public, and the anon onion is
# that key as a v3 address - so the onion decodes back to the handle, which
# is what makes an anon .onion self-authenticating (spec 8.1)
check("anon onion inverts to handle",
      ref["pubkey_from_onion"](ANON0_ONION).hex(), ANON0_HANDLE)
# distinct personas are distinct keys
check("anon personas differ",
      ref["anon_handle"](MASTER, 0) != ref["anon_handle"](MASTER, 1), True)

check("btxo header bytes", ref["btxo_header"]("secret.txt", 11, 0).hex(),
      BTXO_HEADER_HEX)
check("btxo data frame", ref["btxo_data_frame"](b"hello world").hex(),
      BTXO_FRAME_HEX)
check("btxo terminator", ref["btxo_terminator"](), bytes.fromhex("00000000"))
# the frame really is length-prefixed: the u32 prefix equals the payload len
check("btxo frame prefix",
      ref["btxo_data_frame"](b"hello world")[:4],
      (11).to_bytes(4, "big"))
check_raises("btxo empty frame", lambda: ref["btxo_data_frame"](b""))

# ---------------------------------------------------------------------------

if FAILURES:
    print("riptide_golden_test: %d FAILURE(S)" % len(FAILURES))
    for f in FAILURES:
        print(f)
    sys.exit(1)
print("riptide_golden_test: OK (all vectors pinned)")
