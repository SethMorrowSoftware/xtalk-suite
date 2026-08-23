#!/usr/bin/env python3
"""
nostr-kat.py - known-answer vectors for NostrXT's pure-compute paths.

NostrXT itself adds NO cryptography (CLAUDE.md rule 1): SHA-256, BIP-340
Schnorr, x-only keys and ECDH are CoinXT calls, randomness and constant-time
compare are SodiumXT calls. What NostrXT DOES own in pure script is exactly the
checksummed byte shuffling family law allows there: the NIP-01 canonical JSON
serialization (interop-visible byte for byte), bech32/NIP-19 entities, the
NIP-44 key schedule and padding, and RFC 6455 client framing. Every one of
those has a known answer worth pinning, so this tool sweeps the FULL published
vector sets through tools/nostr_reference.py (the independent oracle; it
anchors a subset of the same vectors at import so a broken transcription fails
loudly) and prints the exact constants the member harness pins.

What it sweeps:
  1. BIP-340: the complete official test-vectors.csv, signing rows and
     verification rows including every negative.
     source: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
  2. NIP-44 v2: the complete official vector set - conversation keys (valid
     and invalid), message keys, calc_padded_len, encrypt/decrypt including
     the long-message sha256 rows, invalid decrypt payloads, and the invalid
     plaintext lengths (0 and 65536+ refuse: the published vectors pin the
     u16 prefix only, so NostrXT refuses longer plaintexts, fail closed).
     source: https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json
  3. bech32: the BIP-173 valid and invalid strings. The one deliberate
     deviation is documented inline: NIP-19 waives the 90-character cap for
     TLV entities, so the "overall max length exceeded" vector DECODES here
     and the KAT asserts that it does, on purpose.
     source: https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
  4. NIP-19: the published npub/nsec/nprofile examples and TLV round-trips.
     source: https://github.com/nostr-protocol/nips/blob/master/19.md
  5. NIP-01: canonical serialization fixtures (the escape set exercised
     character by character) cross-checked against python json.dumps where
     the two definitions agree, plus sign/verify round trips.
     source: https://github.com/nostr-protocol/nips/blob/master/01.md
  6. NIP-13: the published difficulty-36 example id.
     source: https://github.com/nostr-protocol/nips/blob/master/13.md
  7. RFC 6455 client pieces: Sec-WebSocket-Accept and frame masking. The RFC
     text hosts are unreachable from this environment's egress proxy, so the
     GUID is anchored to the python-websockets reference implementation and
     every value here is DERIVED, never quoted from memory.
     source: https://github.com/python-websockets/websockets/blob/main/src/websockets/utils.py

Pure standard library only. Usage:
  python3 tools/nostr-kat.py            # print the harness vector constants
  python3 tools/nostr-kat.py --check    # sweep everything, exit non-zero on failure
"""

import base64
import csv
import hashlib
import importlib.util
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "nostr_reference", os.path.join(HERE, "nostr_reference.py"))
REF = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(REF)


# ---------------------------------------------------------------- the fixtures
# The member's own deterministic fixtures. The harness builds these same events
# in livecodescript and asserts the library reproduces every derived value; the
# gate tools/check-selftest-vectors.py re-derives the pinned constants from the
# definitions HERE, so a transcription slip in either direction fails a build.

FIX_SECKEY = "0000000000000000000000000000000000000000000000000000000000000003"

# Event A exercises every character NIP-01 escapes, one of each, plus plain text.
EVENT_A = {
    "created_at": 1700000000,
    "kind": 1,
    "tags": [["e", "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36",
              "wss://nostr.example.com"],
             ["p", "f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca"]],
    "content": "Nostr \"quoted\" back\\slash\nline\rret\ttab\x08bs\x0cff end",
}

# Event B pins the empty-tags, empty-content edge.
EVENT_B = {"created_at": 1700000001, "kind": 0, "tags": [], "content": ""}

# Event C pins UTF-8 pass-through: euro sign, space, purple heart (as bytes,
# because the livecodescript harness must stay pure ASCII and builds the
# content with textDecode over these exact bytes).
CONTENT_C_HEX = "e282ac20f09f929c"
EVENT_C = {"created_at": 1700000002, "kind": 1, "tags": [],
           "content": bytes.fromhex(CONTENT_C_HEX).decode("utf-8")}

AUX_ZERO = "00" * 32

# NIP-19 fixtures beyond the published examples.
FIX_RELAY = "wss://nostr.example.com"
FIX_NADDR_IDENT = "nostrxt"
FIX_NADDR_KIND = 30023

# NIP-13 published example (difficulty 36).
# source: https://github.com/nostr-protocol/nips/blob/master/13.md
POW_ID = "000000000e9d97a1ab09fc381030b346cdd7a142ad57e6df0b46dc9bef6c7e2d"
POW_BITS = 36

# RFC 6455 sample handshake key and the section 5.7 masking key; every derived
# value below comes out of the oracle, not out of a remembered byte listing.
WS_SAMPLE_KEY = "dGhlIHNhbXBsZSBub25jZQ=="
WS_SAMPLE_MASK = "37fa213d"


def pow_difficulty(id_hex):
    bits = 0
    for ch in id_hex:
        v = int(ch, 16)
        if v == 0:
            bits += 4
            continue
        while v < 8:
            bits += 1
            v <<= 1
        break
    return bits


def harness_vectors():
    """Every constant the member harness pins, derived in one place."""
    pub = REF.pubkey_xonly(bytes.fromhex(FIX_SECKEY)).hex()
    out = []
    out.append(("kNxVecSeckey", FIX_SECKEY))
    out.append(("kNxVecTagEventId", EVENT_A["tags"][0][1]))
    out.append(("kNxVecTagPubkey", EVENT_A["tags"][1][1]))
    out.append(("kNxVecPubkey", pub))
    ser_a = REF.serialize_event(pub, EVENT_A["created_at"], EVENT_A["kind"],
                                EVENT_A["tags"], EVENT_A["content"])
    id_a = REF.event_id(pub, EVENT_A["created_at"], EVENT_A["kind"],
                        EVENT_A["tags"], EVENT_A["content"])
    sig_a = REF.schnorr_sign(bytes.fromhex(id_a), bytes.fromhex(FIX_SECKEY),
                             bytes.fromhex(AUX_ZERO)).hex()
    # The canonical strings contain double quotes, which a livecodescript
    # literal cannot hold (xTalk strings have no escapes), so they pin as hex
    # of their UTF-8 bytes and the harness compares through nxHexEncode.
    out.append(("kNxVecSerializedAHex", ser_a.encode("utf-8").hex()))
    out.append(("kNxVecIdA", id_a))
    out.append(("kNxVecSigA", sig_a))
    ser_b = REF.serialize_event(pub, EVENT_B["created_at"], EVENT_B["kind"],
                                EVENT_B["tags"], EVENT_B["content"])
    id_b = REF.event_id(pub, EVENT_B["created_at"], EVENT_B["kind"],
                        EVENT_B["tags"], EVENT_B["content"])
    out.append(("kNxVecSerializedBHex", ser_b.encode("utf-8").hex()))
    out.append(("kNxVecIdB", id_b))
    out.append(("kNxVecContentCHex", CONTENT_C_HEX))
    id_c = REF.event_id(pub, EVENT_C["created_at"], EVENT_C["kind"],
                        EVENT_C["tags"], EVENT_C["content"])
    out.append(("kNxVecIdC", id_c))
    # NIP-19: published bare examples, then entities derived from the fixtures.
    out.append(("kNxVecNpubHex", REF._N19_PUB_HEX))
    out.append(("kNxVecNpub", REF._N19_NPUB))
    out.append(("kNxVecNsecHex", REF._N19_SEC_HEX))
    out.append(("kNxVecNsec", REF._N19_NSEC))
    out.append(("kNxVecNote", REF.nip19_encode("note", bytes.fromhex(id_a))))
    out.append(("kNxVecNprofile", REF._N19_NPROFILE))
    out.append(("kNxVecNprofileHex", REF._N19_PUB_HEX))
    out.append(("kNxVecNevent", REF.nevent_encode(id_a, [FIX_RELAY], pub, 1)))
    out.append(("kNxVecNaddr", REF.naddr_encode(FIX_NADDR_IDENT, pub,
                                                FIX_NADDR_KIND, [])))
    # NIP-44: the sec1=1/sec2=2 conversation-key row and message-keys row 0
    # of the official vectors, re-derived rather than copied.
    n44 = json.loads(NIP44_JSON)["v2"]["valid"]
    sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    pub2 = REF.pubkey_xonly(bytes.fromhex(sec2)).hex()
    conv = REF.nip44_conversation_key(bytes.fromhex(sec1),
                                      bytes.fromhex(pub2)).hex()
    out.append(("kNxVecN44Sec1", sec1))
    out.append(("kNxVecN44Pub2", pub2))
    out.append(("kNxVecN44Conv", conv))
    ed0 = n44["encrypt_decrypt"][0]
    out.append(("kNxVecN44Sec2", sec2))
    out.append(("kNxVecN44Nonce", ed0["nonce"]))
    out.append(("kNxVecN44Payload", ed0["payload"]))
    mk = n44["get_message_keys"]
    row0 = mk["keys"][0]
    ck, cn, hk = REF.nip44_message_keys(bytes.fromhex(mk["conversation_key"]),
                                        bytes.fromhex(row0["nonce"]))
    out.append(("kNxVecN44MkConv", mk["conversation_key"]))
    out.append(("kNxVecN44MkNonce", row0["nonce"]))
    out.append(("kNxVecN44MkChaKey", ck.hex()))
    out.append(("kNxVecN44MkChaNonce", cn.hex()))
    out.append(("kNxVecN44MkHmacKey", hk.hex()))
    pads = n44["calc_padded_len"]
    out.append(("kNxVecN44PadIns", ",".join(str(a) for a, b in pads)))
    out.append(("kNxVecN44PadOuts", ",".join(str(b) for a, b in pads)))
    # RFC 6455 client pieces, derived by the oracle.
    out.append(("kNxVecWsKey", WS_SAMPLE_KEY))
    out.append(("kNxVecWsAccept", REF.ws_accept(WS_SAMPLE_KEY)))
    out.append(("kNxVecWsMask", WS_SAMPLE_MASK))
    out.append(("kNxVecWsFrameHello",
                REF.ws_frame_client(1, b"Hello",
                                    bytes.fromhex(WS_SAMPLE_MASK)).hex()))
    # NIP-13 published example.
    out.append(("kNxVecPowId", POW_ID))
    return out


# ------------------------------------------------------------------ the sweeps


def check_bip340():
    failures = []
    rows = list(csv.DictReader(io.StringIO(BIP340_CSV)))
    if len(rows) < 19:
        failures.append("BIP-340 csv transcription lost rows")
    for row in rows:
        idx = row["index"]
        msg = bytes.fromhex(row["message"]) if row["message"] else b""
        pub = bytes.fromhex(row["public key"])
        sig = bytes.fromhex(row["signature"])
        expect = row["verification result"] == "TRUE"
        if row["secret key"]:
            sec = bytes.fromhex(row["secret key"])
            aux = bytes.fromhex(row["aux_rand"])
            if REF.pubkey_xonly(sec) != pub:
                failures.append(f"BIP-340 row {idx}: pubkey mismatch")
            if REF.schnorr_sign(msg, sec, aux) != sig:
                failures.append(f"BIP-340 row {idx}: signature mismatch")
        if REF.schnorr_verify(msg, pub, sig) != expect:
            failures.append(f"BIP-340 row {idx}: verify != {expect}")
    return failures


def check_nip44():
    failures = []
    v2 = json.loads(NIP44_JSON)["v2"]
    for i, row in enumerate(v2["valid"]["get_conversation_key"]):
        got = REF.nip44_conversation_key(bytes.fromhex(row["sec1"]),
                                         bytes.fromhex(row["pub2"])).hex()
        if got != row["conversation_key"]:
            failures.append(f"NIP-44 conversation_key row {i} mismatch")
    mk = v2["valid"]["get_message_keys"]
    conv = bytes.fromhex(mk["conversation_key"])
    for i, row in enumerate(mk["keys"]):
        ck, cn, hk = REF.nip44_message_keys(conv, bytes.fromhex(row["nonce"]))
        if (ck.hex(), cn.hex(), hk.hex()) != (row["chacha_key"],
                                              row["chacha_nonce"],
                                              row["hmac_key"]):
            failures.append(f"NIP-44 message_keys row {i} mismatch")
    for ulen, want in v2["valid"]["calc_padded_len"]:
        if REF.nip44_calc_padded_len(ulen) != want:
            failures.append(f"NIP-44 calc_padded_len({ulen}) != {want}")
    for i, row in enumerate(v2["valid"]["encrypt_decrypt"]):
        conv = REF.nip44_conversation_key(
            bytes.fromhex(row["sec1"]),
            REF.pubkey_xonly(bytes.fromhex(row["sec2"])))
        if conv.hex() != row["conversation_key"]:
            failures.append(f"NIP-44 encrypt_decrypt row {i}: conversation key")
            continue
        payload = REF.nip44_encrypt_with_nonce(conv, bytes.fromhex(row["nonce"]),
                                               row["plaintext"])
        if payload != row["payload"]:
            failures.append(f"NIP-44 encrypt_decrypt row {i}: payload mismatch")
        if REF.nip44_decrypt(conv, row["payload"]) != row["plaintext"]:
            failures.append(f"NIP-44 encrypt_decrypt row {i}: decrypt mismatch")
    for i, row in enumerate(v2["valid"]["encrypt_decrypt_long_msg"]):
        conv = bytes.fromhex(row["conversation_key"])
        plaintext = row["pattern"] * row["repeat"]
        if hashlib.sha256(plaintext.encode()).hexdigest() != row["plaintext_sha256"]:
            failures.append(f"NIP-44 long row {i}: plaintext sha256")
            continue
        payload = REF.nip44_encrypt_with_nonce(conv, bytes.fromhex(row["nonce"]),
                                               plaintext)
        if hashlib.sha256(payload.encode()).hexdigest() != row["payload_sha256"]:
            failures.append(f"NIP-44 long row {i}: payload sha256")
        if REF.nip44_decrypt(conv, payload) != plaintext:
            failures.append(f"NIP-44 long row {i}: decrypt")
    for i, row in enumerate(v2["invalid"]["get_conversation_key"]):
        try:
            REF.nip44_conversation_key(bytes.fromhex(row["sec1"]),
                                       bytes.fromhex(row["pub2"]))
            failures.append(f"NIP-44 invalid conversation_key row {i} accepted "
                            f"({row.get('note', '')})")
        except (ValueError, Exception):
            pass
    for i, row in enumerate(v2["invalid"]["decrypt"]):
        try:
            REF.nip44_decrypt(bytes.fromhex(row["conversation_key"]),
                              row["payload"])
            failures.append(f"NIP-44 invalid decrypt row {i} accepted "
                            f"({row.get('note', '')})")
        except (ValueError, Exception):
            pass
    for ulen in v2["invalid"]["encrypt_msg_lengths"]:
        try:
            REF.nip44_pad("x" * ulen)
            failures.append(f"NIP-44 pad accepted invalid length {ulen}")
        except ValueError:
            pass
    return failures


def check_bech32():
    failures = []
    for text in BECH32_VALID:
        try:
            REF.bech32_decode(text)
        except ValueError as exc:
            failures.append(f"bech32 valid string refused: {text!r} ({exc})")
    for text in BECH32_INVALID:
        try:
            REF.bech32_decode(text)
            failures.append(f"bech32 invalid string accepted: {text!r}")
        except ValueError:
            pass
    # The deliberate deviation, asserted on purpose: BIP-173 calls this string
    # invalid ("overall max length exceeded"); NIP-19 waives the cap, NostrXT
    # follows NIP-19, and this KAT pins that choice so it cannot drift silently.
    try:
        REF.bech32_decode(BECH32_OVERLONG)
    except ValueError:
        failures.append("the over-90-chars vector must DECODE here: NIP-19 "
                        "waives the BIP-173 cap and NostrXT follows NIP-19")
    return failures


def check_nip19():
    failures = []
    # Published examples anchor at oracle import; here pin the derived entities'
    # round trips (encode -> decode -> fields).
    pub = REF.pubkey_xonly(bytes.fromhex(FIX_SECKEY)).hex()
    id_a = REF.event_id(pub, EVENT_A["created_at"], EVENT_A["kind"],
                        EVENT_A["tags"], EVENT_A["content"])
    nevent = REF.nevent_encode(id_a, [FIX_RELAY], pub, 1)
    hrp, payload = REF.nip19_decode(nevent)
    tlv = REF.tlv_decode(payload)
    if hrp != "nevent" or tlv[0][1].hex() != id_a:
        failures.append("nevent round trip lost the id")
    if [v.decode() for t, v in tlv if t == 1] != [FIX_RELAY]:
        failures.append("nevent round trip lost the relay")
    if [v.hex() for t, v in tlv if t == 2] != [pub]:
        failures.append("nevent round trip lost the author")
    if [int.from_bytes(v, "big") for t, v in tlv if t == 3] != [1]:
        failures.append("nevent round trip lost the kind")
    naddr = REF.naddr_encode(FIX_NADDR_IDENT, pub, FIX_NADDR_KIND, [])
    hrp, payload = REF.nip19_decode(naddr)
    tlv = REF.tlv_decode(payload)
    if (hrp != "naddr" or tlv[0][1].decode() != FIX_NADDR_IDENT or
            [int.from_bytes(v, "big") for t, v in tlv if t == 3] != [FIX_NADDR_KIND]):
        failures.append("naddr round trip lost a field")
    return failures


def check_nip01():
    failures = []
    pub = REF.pubkey_xonly(bytes.fromhex(FIX_SECKEY)).hex()
    for name, ev in (("A", EVENT_A), ("B", EVENT_B), ("C", EVENT_C)):
        ser = REF.serialize_event(pub, ev["created_at"], ev["kind"],
                                  ev["tags"], ev["content"])
        # Where NIP-01 escaping and JSON escaping agree (no exotic control
        # characters), the canonical string must BE valid JSON with the exact
        # field values - an independent parse of our own serializer.
        arr = json.loads(ser)
        if arr != [0, pub, ev["created_at"], ev["kind"], ev["tags"],
                   ev["content"]]:
            failures.append(f"event {name}: canonical form does not parse back")
        signed = REF.sign_event(FIX_SECKEY, ev["created_at"], ev["kind"],
                                ev["tags"], ev["content"], AUX_ZERO)
        if not REF.verify_event(signed):
            failures.append(f"event {name}: sign/verify round trip failed")
        tampered = dict(signed)
        tampered["content"] = signed["content"] + "!"
        if REF.verify_event(tampered):
            failures.append(f"event {name}: tampered content still verifies")
    # A control byte OUTSIDE the escape set stays verbatim (the rule that makes
    # json.dumps unusable as the canonical serializer).
    raw = REF.json_escape("a\x01b")
    if raw != "a\x01b":
        failures.append("json_escape must pass 0x01 through verbatim")
    if REF.json_escape("\"\\\n\r\t\x08\x0c") != "\\\"\\\\\\n\\r\\t\\b\\f":
        failures.append("json_escape escape set mismatch")
    return failures


def check_nip13():
    if pow_difficulty(POW_ID) != POW_BITS:
        return [f"NIP-13 example id difficulty != {POW_BITS}"]
    return []


def check_ws():
    failures = []
    accept = REF.ws_accept(WS_SAMPLE_KEY)
    raw = base64.b64decode(accept)
    if raw != hashlib.sha1((WS_SAMPLE_KEY + REF.WS_GUID).encode()).digest():
        failures.append("ws_accept does not match sha1(key+GUID)")
    mask = bytes.fromhex(WS_SAMPLE_MASK)
    frame = REF.ws_frame_client(1, b"Hello", mask)
    if frame[0] != 0x81 or frame[1] != 0x85 or frame[2:6] != mask:
        failures.append("client Hello frame header mismatch")
    if REF.ws_mask(frame[6:], mask) != b"Hello":
        failures.append("client Hello frame unmask mismatch")
    long_frame = REF.ws_frame_client(1, b"x" * 300, mask)
    if long_frame[1] != 0xFE or int.from_bytes(long_frame[2:4], "big") != 300:
        failures.append("extended 16-bit length frame mismatch")
    huge = REF.ws_frame_client(2, b"y" * 70000, mask)
    if huge[1] != 0xFF or int.from_bytes(huge[2:10], "big") != 70000:
        failures.append("extended 64-bit length frame mismatch")
    return failures


def main(argv):
    failures = []
    for check in (check_bip340, check_nip44, check_bech32, check_nip19,
                  check_nip01, check_nip13, check_ws):
        failures.extend(check())
    if failures:
        for f in failures:
            print("FAIL:", f)
        return 1
    if "--check" in argv:
        print("nostr-kat: self-check OK (BIP-340 full csv, NIP-44 full vector "
              "set, BIP-173, NIP-19, NIP-01 fixtures, NIP-13, RFC 6455 pieces)")
        return 0

    print("# NostrXT known-answer vectors (generated by tools/nostr-kat.py)")
    print("# These are the constants examples/nostrxt-tests.livecodescript pins;")
    print("# tools/check-selftest-vectors.py re-derives each one by NAME, so edit")
    print("# the fixture here, re-run this tool, and paste - never hand-edit a hex.")
    print()
    for name, value in harness_vectors():
        print(f'constant {name} = "{value}"')
    return 0


# ------------------------------------------------- transcribed vector payloads
# Verbatim transcriptions; the source URLs are in the module docstring. Kept at
# the bottom of the file so the code reads first.

BIP340_CSV = r'''index,secret key,public key,aux_rand,message,signature,verification result,comment
0,0000000000000000000000000000000000000000000000000000000000000003,F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9,0000000000000000000000000000000000000000000000000000000000000000,0000000000000000000000000000000000000000000000000000000000000000,E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0,TRUE,
1,B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,0000000000000000000000000000000000000000000000000000000000000001,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A,TRUE,
2,C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9,DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8,C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906,7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C,5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7,TRUE,
3,0B432B2677937381AEF05BB02A66ECD012773062CF3FA2549E44F58ED2401710,25D1DFF95105F5253C4022F628A996AD3A0D95FBF21D468A1B33F8C160D8F517,FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,7EB0509757E246F19449885651611CB965ECC1A187DD51B64FDA1EDC9637D5EC97582B9CB13DB3933705B32BA982AF5AF25FD78881EBB32771FC5922EFC66EA3,TRUE,test fails if msg is reduced modulo p or n
4,,D69C3509BB99E412E68B0FE8544E72837DFA30746D8BE2AA65975F29D22DC7B9,,4DF3C3F68FCC83B27E9D42C90431A72499F17875C81A599B566C9889B9696703,00000000000000000000003B78CE563F89A0ED9414F5AA28AD0D96D6795F9C6376AFB1548AF603B3EB45C9F8207DEE1060CB71C04E80F593060B07D28308D7F4,TRUE,
5,,EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B,FALSE,public key not on the curve
6,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,FFF97BD5755EEEA420453A14355235D382F6472F8568A18B2F057A14602975563CC27944640AC607CD107AE10923D9EF7A73C643E166BE5EBEAFA34B1AC553E2,FALSE,has_even_y(R) is false
7,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,1FA62E331EDBC21C394792D2AB1100A7B432B013DF3F6FF4F99FCB33E0E1515F28890B3EDB6E7189B630448B515CE4F8622A954CFE545735AAEA5134FCCDB2BD,FALSE,negated message
8,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769961764B3AA9B2FFCB6EF947B6887A226E8D7C93E00C5ED0C1834FF0D0C2E6DA6,FALSE,negated s value
9,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,0000000000000000000000000000000000000000000000000000000000000000123DDA8328AF9C23A94C1FEECFD123BA4FB73476F0D594DCB65C6425BD186051,FALSE,sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 0
10,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,00000000000000000000000000000000000000000000000000000000000000017615FBAF5AE28864013C099742DEADB4DBA87F11AC6754F93780D5A1837CF197,FALSE,sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 1
11,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,4A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B,FALSE,sig[0:32] is not an X coordinate on the curve
12,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B,FALSE,sig[0:32] is equal to field size
13,,DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141,FALSE,sig[32:64] is equal to curve order
14,,FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30,,243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89,6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B,FALSE,public key is not a valid X coordinate because it exceeds the field size
15,0340034003400340034003400340034003400340034003400340034003400340,778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117,0000000000000000000000000000000000000000000000000000000000000000,,71535DB165ECD9FBBC046E5FFAEA61186BB6AD436732FCCC25291A55895464CF6069CE26BF03466228F19A3A62DB8A649F2D560FAC652827D1AF0574E427AB63,TRUE,message of size 0 (added 2022-12)
16,0340034003400340034003400340034003400340034003400340034003400340,778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117,0000000000000000000000000000000000000000000000000000000000000000,11,08A20A0AFEF64124649232E0693C583AB1B9934AE63B4C3511F3AE1134C6A303EA3173BFEA6683BD101FA5AA5DBC1996FE7CACFC5A577D33EC14564CEC2BACBF,TRUE,message of size 1 (added 2022-12)
17,0340034003400340034003400340034003400340034003400340034003400340,778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117,0000000000000000000000000000000000000000000000000000000000000000,0102030405060708090A0B0C0D0E0F1011,5130F39A4059B43BC7CAC09A19ECE52B5D8699D1A71E3C52DA9AFDB6B50AC370C4A482B77BF960F8681540E25B6771ECE1E5A37FD80E5A51897C5566A97EA5A5,TRUE,message of size 17 (added 2022-12)
18,0340034003400340034003400340034003400340034003400340034003400340,778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117,0000000000000000000000000000000000000000000000000000000000000000,99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999,403B12B0D8555A344175EA7EC746566303321E5DBFA8BE6F091635163ECA79A8585ED3E3170807E7C03B720FC54C7B23897FCBA0E9D0B4A06894CFD249F22367,TRUE,message of size 100 (added 2022-12)
'''

NIP44_JSON = r'''{
  "v2": {
    "valid": {
      "get_conversation_key": [
        {
          "sec1": "315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268",
          "pub2": "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133",
          "conversation_key": "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1"
        },
        {
          "sec1": "a1e37752c9fdc1273be53f68c5f74be7c8905728e8de75800b94262f9497c86e",
          "pub2": "03bb7947065dde12ba991ea045132581d0954f042c84e06d8c00066e23c1a800",
          "conversation_key": "4d14f36e81b8452128da64fe6f1eae873baae2f444b02c950b90e43553f2178b"
        },
        {
          "sec1": "98a5902fd67518a0c900f0fb62158f278f94a21d6f9d33d30cd3091195500311",
          "pub2": "aae65c15f98e5e677b5050de82e3aba47a6fe49b3dab7863cf35d9478ba9f7d1",
          "conversation_key": "9c00b769d5f54d02bf175b7284a1cbd28b6911b06cda6666b2243561ac96bad7"
        },
        {
          "sec1": "86ae5ac8034eb2542ce23ec2f84375655dab7f836836bbd3c54cefe9fdc9c19f",
          "pub2": "59f90272378089d73f1339710c02e2be6db584e9cdbe86eed3578f0c67c23585",
          "conversation_key": "19f934aafd3324e8415299b64df42049afaa051c71c98d0aa10e1081f2e3e2ba"
        },
        {
          "sec1": "2528c287fe822421bc0dc4c3615878eb98e8a8c31657616d08b29c00ce209e34",
          "pub2": "f66ea16104c01a1c532e03f166c5370a22a5505753005a566366097150c6df60",
          "conversation_key": "c833bbb292956c43366145326d53b955ffb5da4e4998a2d853611841903f5442"
        },
        {
          "sec1": "49808637b2d21129478041813aceb6f2c9d4929cd1303cdaf4fbdbd690905ff2",
          "pub2": "74d2aab13e97827ea21baf253ad7e39b974bb2498cc747cdb168582a11847b65",
          "conversation_key": "4bf304d3c8c4608864c0fe03890b90279328cd24a018ffa9eb8f8ccec06b505d"
        },
        {
          "sec1": "af67c382106242c5baabf856efdc0629cc1c5b4061f85b8ceaba52aa7e4b4082",
          "pub2": "bdaf0001d63e7ec994fad736eab178ee3c2d7cfc925ae29f37d19224486db57b",
          "conversation_key": "a3a575dd66d45e9379904047ebfb9a7873c471687d0535db00ef2daa24b391db"
        },
        {
          "sec1": "0e44e2d1db3c1717b05ffa0f08d102a09c554a1cbbf678ab158b259a44e682f1",
          "pub2": "1ffa76c5cc7a836af6914b840483726207cb750889753d7499fb8b76aa8fe0de",
          "conversation_key": "a39970a667b7f861f100e3827f4adbf6f464e2697686fe1a81aeda817d6b8bdf"
        },
        {
          "sec1": "5fc0070dbd0666dbddc21d788db04050b86ed8b456b080794c2a0c8e33287bb6",
          "pub2": "31990752f296dd22e146c9e6f152a269d84b241cc95bb3ff8ec341628a54caf0",
          "conversation_key": "72c21075f4b2349ce01a3e604e02a9ab9f07e35dd07eff746de348b4f3c6365e"
        },
        {
          "sec1": "1b7de0d64d9b12ddbb52ef217a3a7c47c4362ce7ea837d760dad58ab313cba64",
          "pub2": "24383541dd8083b93d144b431679d70ef4eec10c98fceef1eff08b1d81d4b065",
          "conversation_key": "dd152a76b44e63d1afd4dfff0785fa07b3e494a9e8401aba31ff925caeb8f5b1"
        },
        {
          "sec1": "df2f560e213ca5fb33b9ecde771c7c0cbd30f1cf43c2c24de54480069d9ab0af",
          "pub2": "eeea26e552fc8b5e377acaa03e47daa2d7b0c787fac1e0774c9504d9094c430e",
          "conversation_key": "770519e803b80f411c34aef59c3ca018608842ebf53909c48d35250bd9323af6"
        },
        {
          "sec1": "cffff919fcc07b8003fdc63bc8a00c0f5dc81022c1c927c62c597352190d95b9",
          "pub2": "eb5c3cca1a968e26684e5b0eb733aecfc844f95a09ac4e126a9e58a4e4902f92",
          "conversation_key": "46a14ee7e80e439ec75c66f04ad824b53a632b8409a29bbb7c192e43c00bb795"
        },
        {
          "sec1": "64ba5a685e443e881e9094647ddd32db14444bb21aa7986beeba3d1c4673ba0a",
          "pub2": "50e6a4339fac1f3bf86f2401dd797af43ad45bbf58e0801a7877a3984c77c3c4",
          "conversation_key": "968b9dbbfcede1664a4ca35a5d3379c064736e87aafbf0b5d114dff710b8a946"
        },
        {
          "sec1": "dd0c31ccce4ec8083f9b75dbf23cc2878e6d1b6baa17713841a2428f69dee91a",
          "pub2": "b483e84c1339812bed25be55cff959778dfc6edde97ccd9e3649f442472c091b",
          "conversation_key": "09024503c7bde07eb7865505891c1ea672bf2d9e25e18dd7a7cea6c69bf44b5d"
        },
        {
          "sec1": "af71313b0d95c41e968a172b33ba5ebd19d06cdf8a7a98df80ecf7af4f6f0358",
          "pub2": "2a5c25266695b461ee2af927a6c44a3c598b8095b0557e9bd7f787067435bc7c",
          "conversation_key": "fe5155b27c1c4b4e92a933edae23726a04802a7cc354a77ac273c85aa3c97a92"
        },
        {
          "sec1": "6636e8a389f75fe068a03b3edb3ea4a785e2768e3f73f48ffb1fc5e7cb7289dc",
          "pub2": "514eb2064224b6a5829ea21b6e8f7d3ea15ff8e70e8555010f649eb6e09aec70",
          "conversation_key": "ff7afacd4d1a6856d37ca5b546890e46e922b508639214991cf8048ddbe9745c"
        },
        {
          "sec1": "94b212f02a3cfb8ad147d52941d3f1dbe1753804458e6645af92c7b2ea791caa",
          "pub2": "f0cac333231367a04b652a77ab4f8d658b94e86b5a8a0c472c5c7b0d4c6a40cc",
          "conversation_key": "e292eaf873addfed0a457c6bd16c8effde33d6664265697f69f420ab16f6669b"
        },
        {
          "sec1": "aa61f9734e69ae88e5d4ced5aae881c96f0d7f16cca603d3bed9eec391136da6",
          "pub2": "4303e5360a884c360221de8606b72dd316da49a37fe51e17ada4f35f671620a6",
          "conversation_key": "8e7d44fd4767456df1fb61f134092a52fcd6836ebab3b00766e16732683ed848"
        },
        {
          "sec1": "5e914bdac54f3f8e2cba94ee898b33240019297b69e96e70c8a495943a72fc98",
          "pub2": "5bd097924f606695c59f18ff8fd53c174adbafaaa71b3c0b4144a3e0a474b198",
          "conversation_key": "f5a0aecf2984bf923c8cd5e7bb8be262d1a8353cb93959434b943a07cf5644bc"
        },
        {
          "sec1": "8b275067add6312ddee064bcdbeb9d17e88aa1df36f430b2cea5cc0413d8278a",
          "pub2": "65bbbfca819c90c7579f7a82b750a18c858db1afbec8f35b3c1e0e7b5588e9b8",
          "conversation_key": "2c565e7027eb46038c2263563d7af681697107e975e9914b799d425effd248d6"
        },
        {
          "sec1": "1ac848de312285f85e0f7ec208aac20142a1f453402af9b34ec2ec7a1f9c96fc",
          "pub2": "45f7318fe96034d23ee3ddc25b77f275cc1dd329664dd51b89f89c4963868e41",
          "conversation_key": "b56e970e5057a8fd929f8aad9248176b9af87819a708d9ddd56e41d1aec74088"
        },
        {
          "sec1": "295a1cf621de401783d29d0e89036aa1c62d13d9ad307161b4ceb535ba1b40e6",
          "pub2": "840115ddc7f1034d3b21d8e2103f6cb5ab0b63cf613f4ea6e61ae3d016715cdd",
          "conversation_key": "b4ee9c0b9b9fef88975773394f0a6f981ca016076143a1bb575b9ff46e804753"
        },
        {
          "sec1": "a28eed0fe977893856ab9667e06ace39f03abbcdb845c329a1981be438ba565d",
          "pub2": "b0f38b950a5013eba5ab4237f9ed29204a59f3625c71b7e210fec565edfa288c",
          "conversation_key": "9d3a802b45bc5aeeb3b303e8e18a92ddd353375710a31600d7f5fff8f3a7285b"
        },
        {
          "sec1": "7ab65af72a478c05f5c651bdc4876c74b63d20d04cdbf71741e46978797cd5a4",
          "pub2": "f1112159161b568a9cb8c9dd6430b526c4204bcc8ce07464b0845b04c041beda",
          "conversation_key": "943884cddaca5a3fef355e9e7f08a3019b0b66aa63ec90278b0f9fdb64821e79"
        },
        {
          "sec1": "95c79a7b75ba40f2229e85756884c138916f9d103fc8f18acc0877a7cceac9fe",
          "pub2": "cad76bcbd31ca7bbda184d20cc42f725ed0bb105b13580c41330e03023f0ffb3",
          "conversation_key": "81c0832a669eea13b4247c40be51ccfd15bb63fcd1bba5b4530ce0e2632f301b"
        },
        {
          "sec1": "baf55cc2febd4d980b4b393972dfc1acf49541e336b56d33d429bce44fa12ec9",
          "pub2": "0c31cf87fe565766089b64b39460ebbfdedd4a2bc8379be73ad3c0718c912e18",
          "conversation_key": "37e2344da9ecdf60ae2205d81e89d34b280b0a3f111171af7e4391ded93b8ea6"
        },
        {
          "sec1": "6eeec45acd2ed31693c5256026abf9f072f01c4abb61f51cf64e6956b6dc8907",
          "pub2": "e501b34ed11f13d816748c0369b0c728e540df3755bab59ed3327339e16ff828",
          "conversation_key": "afaa141b522ddb27bb880d768903a7f618bb8b6357728cae7fb03af639b946e6"
        },
        {
          "sec1": "261a076a9702af1647fb343c55b3f9a4f1096273002287df0015ba81ce5294df",
          "pub2": "b2777c863878893ae100fb740c8fab4bebd2bf7be78c761a75593670380a6112",
          "conversation_key": "76f8d2853de0734e51189ced523c09427c3e46338b9522cd6f74ef5e5b475c74"
        },
        {
          "sec1": "ed3ec71ca406552ea41faec53e19f44b8f90575eda4b7e96380f9cc73c26d6f3",
          "pub2": "86425951e61f94b62e20cae24184b42e8e17afcf55bafa58645efd0172624fae",
          "conversation_key": "f7ffc520a3a0e9e9b3c0967325c9bf12707f8e7a03f28b6cd69ae92cf33f7036"
        },
        {
          "sec1": "5a788fc43378d1303ac78639c59a58cb88b08b3859df33193e63a5a3801c722e",
          "pub2": "a8cba2f87657d229db69bee07850fd6f7a2ed070171a06d006ec3a8ac562cf70",
          "conversation_key": "7d705a27feeedf78b5c07283362f8e361760d3e9f78adab83e3ae5ce7aeb6409"
        },
        {
          "sec1": "63bffa986e382b0ac8ccc1aa93d18a7aa445116478be6f2453bad1f2d3af2344",
          "pub2": "b895c70a83e782c1cf84af558d1038e6b211c6f84ede60408f519a293201031d",
          "conversation_key": "3a3b8f00d4987fc6711d9be64d9c59cf9a709c6c6481c2cde404bcc7a28f174e"
        },
        {
          "sec1": "e4a8bcacbf445fd3721792b939ff58e691cdcba6a8ba67ac3467b45567a03e5c",
          "pub2": "b54053189e8c9252c6950059c783edb10675d06d20c7b342f73ec9fa6ed39c9d",
          "conversation_key": "7b3933b4ef8189d347169c7955589fc1cfc01da5239591a08a183ff6694c44ad"
        },
        {
          "sec1": "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139",
          "pub2": "0000000000000000000000000000000000000000000000000000000000000002",
          "conversation_key": "8b6392dbf2ec6a2b2d5b1477fc2be84d63ef254b667cadd31bd3f444c44ae6ba",
          "note": "sec1 = n-2, pub2: random, 0x02"
        },
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000002",
          "pub2": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdeb",
          "conversation_key": "be234f46f60a250bef52a5ee34c758800c4ca8e5030bf4cc1a31d37ba2104d43",
          "note": "sec1 = 2, pub2: rand"
        },
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000001",
          "pub2": "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
          "conversation_key": "3b4610cb7189beb9cc29eb3716ecc6102f1247e8f3101a03a1787d8908aeb54e",
          "note": "sec1 == pub2"
        }
      ],
      "get_message_keys": {
        "conversation_key": "a1a3d60f3470a8612633924e91febf96dc5366ce130f658b1f0fc652c20b3b54",
        "keys": [
          {
            "nonce": "e1e6f880560d6d149ed83dcc7e5861ee62a5ee051f7fde9975fe5d25d2a02d72",
            "chacha_key": "f145f3bed47cb70dbeaac07f3a3fe683e822b3715edb7c4fe310829014ce7d76",
            "chacha_nonce": "c4ad129bb01180c0933a160c",
            "hmac_key": "027c1db445f05e2eee864a0975b0ddef5b7110583c8c192de3732571ca5838c4"
          },
          {
            "nonce": "e1d6d28c46de60168b43d79dacc519698512ec35e8ccb12640fc8e9f26121101",
            "chacha_key": "e35b88f8d4a8f1606c5082f7a64b100e5d85fcdb2e62aeafbec03fb9e860ad92",
            "chacha_nonce": "22925e920cee4a50a478be90",
            "hmac_key": "46a7c55d4283cb0df1d5e29540be67abfe709e3b2e14b7bf9976e6df994ded30"
          },
          {
            "nonce": "cfc13bef512ac9c15951ab00030dfaf2626fdca638dedb35f2993a9eeb85d650",
            "chacha_key": "020783eb35fdf5b80ef8c75377f4e937efb26bcbad0e61b4190e39939860c4bf",
            "chacha_nonce": "d3594987af769a52904656ac",
            "hmac_key": "237ec0ccb6ebd53d179fa8fd319e092acff599ef174c1fdafd499ef2b8dee745"
          },
          {
            "nonce": "ea6eb84cac23c5c1607c334e8bdf66f7977a7e374052327ec28c6906cbe25967",
            "chacha_key": "ff68db24b34fa62c78ac5ffeeaf19533afaedf651fb6a08384e46787f6ce94be",
            "chacha_nonce": "50bb859aa2dde938cc49ec7a",
            "hmac_key": "06ff32e1f7b29753a727d7927b25c2dd175aca47751462d37a2039023ec6b5a6"
          },
          {
            "nonce": "8c2e1dd3792802f1f9f7842e0323e5d52ad7472daf360f26e15f97290173605d",
            "chacha_key": "2f9daeda8683fdeede81adac247c63cc7671fa817a1fd47352e95d9487989d8b",
            "chacha_nonce": "400224ba67fc2f1b76736916",
            "hmac_key": "465c05302aeeb514e41c13ed6405297e261048cfb75a6f851ffa5b445b746e4b"
          },
          {
            "nonce": "05c28bf3d834fa4af8143bf5201a856fa5fac1a3aee58f4c93a764fc2f722367",
            "chacha_key": "1e3d45777025a035be566d80fd580def73ed6f7c043faec2c8c1c690ad31c110",
            "chacha_nonce": "021905b1ea3afc17cb9bf96f",
            "hmac_key": "74a6e481a89dcd130aaeb21060d7ec97ad30f0007d2cae7b1b11256cc70dfb81"
          },
          {
            "nonce": "5e043fb153227866e75a06d60185851bc90273bfb93342f6632a728e18a07a17",
            "chacha_key": "1ea72c9293841e7737c71567d8120145a58991aaa1c436ef77bf7adb83f882f1",
            "chacha_nonce": "72f69a5a5f795465cee59da8",
            "hmac_key": "e9daa1a1e9a266ecaa14e970a84bce3fbbf329079bbccda626582b4e66a0d4c9"
          },
          {
            "nonce": "7be7338eaf06a87e274244847fe7a97f5c6a91f44adc18fcc3e411ad6f786dbf",
            "chacha_key": "881e7968a1f0c2c80742ee03cd49ea587e13f22699730f1075ade01931582bf6",
            "chacha_nonce": "6e69be92d61c04a276021565",
            "hmac_key": "901afe79e74b19967c8829af23617d7d0ffbf1b57190c096855c6a03523a971b"
          },
          {
            "nonce": "94571c8d590905bad7becd892832b472f2aa5212894b6ce96e5ba719c178d976",
            "chacha_key": "f80873dd48466cb12d46364a97b8705c01b9b4230cb3ec3415a6b9551dc42eef",
            "chacha_nonce": "3dda53569cfcb7fac1805c35",
            "hmac_key": "e9fc264345e2839a181affebc27d2f528756e66a5f87b04bf6c5f1997047051e"
          },
          {
            "nonce": "13a6ee974b1fd759135a2c2010e3cdda47081c78e771125e4f0c382f0284a8cb",
            "chacha_key": "bc5fb403b0bed0d84cf1db872b6522072aece00363178c98ad52178d805fca85",
            "chacha_nonce": "65064239186e50304cc0f156",
            "hmac_key": "e872d320dde4ed3487958a8e43b48aabd3ced92bc24bb8ff1ccb57b590d9701a"
          },
          {
            "nonce": "082fecdb85f358367b049b08be0e82627ae1d8edb0f27327ccb593aa2613b814",
            "chacha_key": "1fbdb1cf6f6ea816349baf697932b36107803de98fcd805ebe9849b8ad0e6a45",
            "chacha_nonce": "2e605e1d825a3eaeb613db9c",
            "hmac_key": "fae910f591cf3c7eb538c598583abad33bc0a03085a96ca4ea3a08baf17c0eec"
          },
          {
            "nonce": "4c19020c74932c30ec6b2d8cd0d5bb80bd0fc87da3d8b4859d2fb003810afd03",
            "chacha_key": "1ab9905a0189e01cda82f843d226a82a03c4f5b6dbea9b22eb9bc953ba1370d4",
            "chacha_nonce": "cbb2530ea653766e5a37a83a",
            "hmac_key": "267f68acac01ac7b34b675e36c2cef5e7b7a6b697214add62a491bedd6efc178"
          },
          {
            "nonce": "67723a3381497b149ce24814eddd10c4c41a1e37e75af161930e6b9601afd0ff",
            "chacha_key": "9ecbd25e7e2e6c97b8c27d376dcc8c5679da96578557e4e21dba3a7ef4e4ac07",
            "chacha_nonce": "ef649fcf335583e8d45e3c2e",
            "hmac_key": "04dbbd812fa8226fdb45924c521a62e3d40a9e2b5806c1501efdeba75b006bf1"
          },
          {
            "nonce": "42063fe80b093e8619b1610972b4c3ab9e76c14fd908e642cd4997cafb30f36c",
            "chacha_key": "211c66531bbcc0efcdd0130f9f1ebc12a769105eb39608994bcb188fa6a73a4a",
            "chacha_nonce": "67803605a7e5010d0f63f8c8",
            "hmac_key": "e840e4e8921b57647369d121c5a19310648105dbdd008200ebf0d3b668704ff8"
          },
          {
            "nonce": "b5ac382a4be7ac03b554fe5f3043577b47ea2cd7cfc7e9ca010b1ffbb5cf1a58",
            "chacha_key": "b3b5f14f10074244ee42a3837a54309f33981c7232a8b16921e815e1f7d1bb77",
            "chacha_nonce": "4e62a0073087ed808be62469",
            "hmac_key": "c8efa10230b5ea11633816c1230ca05fa602ace80a7598916d83bae3d3d2ccd7"
          },
          {
            "nonce": "e9d1eba47dd7e6c1532dc782ff63125db83042bb32841db7eeafd528f3ea7af9",
            "chacha_key": "54241f68dc2e50e1db79e892c7c7a471856beeb8d51b7f4d16f16ab0645d2f1a",
            "chacha_nonce": "a963ed7dc29b7b1046820a1d",
            "hmac_key": "aba215c8634530dc21c70ddb3b3ee4291e0fa5fa79be0f85863747bde281c8b2"
          },
          {
            "nonce": "a94ecf8efeee9d7068de730fad8daf96694acb70901d762de39fa8a5039c3c49",
            "chacha_key": "c0565e9e201d2381a2368d7ffe60f555223874610d3d91fbbdf3076f7b1374dd",
            "chacha_nonce": "329bb3024461e84b2e1c489b",
            "hmac_key": "ac42445491f092481ce4fa33b1f2274700032db64e3a15014fbe8c28550f2fec"
          },
          {
            "nonce": "533605ea214e70c25e9a22f792f4b78b9f83a18ab2103687c8a0075919eaaa53",
            "chacha_key": "ab35a5e1e54d693ff023db8500d8d4e79ad8878c744e0eaec691e96e141d2325",
            "chacha_nonce": "653d759042b85194d4d8c0a7",
            "hmac_key": "b43628e37ba3c31ce80576f0a1f26d3a7c9361d29bb227433b66f49d44f167ba"
          },
          {
            "nonce": "7f38df30ceea1577cb60b355b4f5567ff4130c49e84fed34d779b764a9cc184c",
            "chacha_key": "a37d7f211b84a551a127ff40908974eb78415395d4f6f40324428e850e8c42a3",
            "chacha_nonce": "b822e2c959df32b3cb772a7c",
            "hmac_key": "1ba31764f01f69b5c89ded2d7c95828e8052c55f5d36f1cd535510d61ba77420"
          },
          {
            "nonce": "11b37f9dbc4d0185d1c26d5f4ed98637d7c9701fffa65a65839fa4126573a4e5",
            "chacha_key": "964f38d3a31158a5bfd28481247b18dd6e44d69f30ba2a40f6120c6d21d8a6ba",
            "chacha_nonce": "5f72c5b87c590bcd0f93b305",
            "hmac_key": "2fc4553e7cedc47f29690439890f9f19c1077ef3e9eaeef473d0711e04448918"
          },
          {
            "nonce": "8be790aa483d4cdd843189f71f135b3ec7e31f381312c8fe9f177aab2a48eafa",
            "chacha_key": "95c8c74d633721a131316309cf6daf0804d59eaa90ea998fc35bac3d2fbb7a94",
            "chacha_nonce": "409a7654c0e4bf8c2c6489be",
            "hmac_key": "21bb0b06eb2b460f8ab075f497efa9a01c9cf9146f1e3986c3bf9da5689b6dc4"
          },
          {
            "nonce": "19fd2a718ea084827d6bd73f509229ddf856732108b59fc01819f611419fd140",
            "chacha_key": "cc6714b9f5616c66143424e1413d520dae03b1a4bd202b82b0a89b0727f5cdc8",
            "chacha_nonce": "1b7fd2534f015a8f795d8f32",
            "hmac_key": "2bef39c4ce5c3c59b817e86351373d1554c98bc131c7e461ed19d96cfd6399a0"
          },
          {
            "nonce": "3c2acd893952b2f6d07d8aea76f545ca45961a93fe5757f6a5a80811d5e0255d",
            "chacha_key": "c8de6c878cb469278d0af894bc181deb6194053f73da5014c2b5d2c8db6f2056",
            "chacha_nonce": "6ffe4f1971b904a1b1a81b99",
            "hmac_key": "df1cd69dd3646fca15594284744d4211d70e7d8472e545d276421fbb79559fd4"
          },
          {
            "nonce": "7dbea4cead9ac91d4137f1c0a6eebb6ba0d1fb2cc46d829fbc75f8d86aca6301",
            "chacha_key": "c8e030f6aa680c3d0b597da9c92bb77c21c4285dd620c5889f9beba7446446b0",
            "chacha_nonce": "a9b5a67d081d3b42e737d16f",
            "hmac_key": "355a85f551bc3cce9a14461aa60994742c9bbb1c81a59ca102dc64e61726ab8e"
          },
          {
            "nonce": "45422e676cdae5f1071d3647d7a5f1f5adafb832668a578228aa1155a491f2f3",
            "chacha_key": "758437245f03a88e2c6a32807edfabff51a91c81ca2f389b0b46f2c97119ea90",
            "chacha_nonce": "263830a065af33d9c6c5aa1f",
            "hmac_key": "7c581cf3489e2de203a95106bfc0de3d4032e9d5b92b2b61fb444acd99037e17"
          },
          {
            "nonce": "babc0c03fad24107ad60678751f5db2678041ff0d28671ede8d65bdf7aa407e9",
            "chacha_key": "bd68a28bd48d9ffa3602db72c75662ac2848a0047a313d2ae2d6bc1ac153d7e9",
            "chacha_nonce": "d0f9d2a1ace6c758f594ffdd",
            "hmac_key": "eb435e3a642adfc9d59813051606fc21f81641afd58ea6641e2f5a9f123bb50a"
          },
          {
            "nonce": "7a1b8aac37d0d20b160291fad124ab697cfca53f82e326d78fef89b4b0ea8f83",
            "chacha_key": "9e97875b651a1d30d17d086d1e846778b7faad6fcbc12e08b3365d700f62e4fe",
            "chacha_nonce": "ccdaad5b3b7645be430992eb",
            "hmac_key": "6f2f55cf35174d75752f63c06cc7cbc8441759b142999ed2d5a6d09d263e1fc4"
          },
          {
            "nonce": "8370e4e32d7e680a83862cab0da6136ef607014d043e64cdf5ecc0c4e20b3d9a",
            "chacha_key": "1472bed5d19db9c546106de946e0649cd83cc9d4a66b087a65906e348dcf92e2",
            "chacha_nonce": "ed02dece5fc3a186f123420b",
            "hmac_key": "7b3f7739f49d30c6205a46b174f984bb6a9fc38e5ccfacef2dac04fcbd3b184e"
          },
          {
            "nonce": "9f1c5e8a29cd5677513c2e3a816551d6833ee54991eb3f00d5b68096fc8f0183",
            "chacha_key": "5e1a7544e4d4dafe55941fcbdf326f19b0ca37fc49c4d47e9eec7fb68cde4975",
            "chacha_nonce": "7d9acb0fdc174e3c220f40de",
            "hmac_key": "e265ab116fbbb86b2aefc089a0986a0f5b77eda50c7410404ad3b4f3f385c7a7"
          },
          {
            "nonce": "c385aa1c37c2bfd5cc35fcdbdf601034d39195e1cabff664ceb2b787c15d0225",
            "chacha_key": "06bf4e60677a13e54c4a38ab824d2ef79da22b690da2b82d0aa3e39a14ca7bdd",
            "chacha_nonce": "26b450612ca5e905b937e147",
            "hmac_key": "22208152be2b1f5f75e6bfcc1f87763d48bb7a74da1be3d102096f257207f8b3"
          },
          {
            "nonce": "3ff73528f88a50f9d35c0ddba4560bacee5b0462d0f4cb6e91caf41847040ce4",
            "chacha_key": "850c8a17a23aa761d279d9901015b2bbdfdff00adbf6bc5cf22bd44d24ecabc9",
            "chacha_nonce": "4a296a1fb0048e5020d3b129",
            "hmac_key": "b1bf49a533c4da9b1d629b7ff30882e12d37d49c19abd7b01b7807d75ee13806"
          },
          {
            "nonce": "2dcf39b9d4c52f1cb9db2d516c43a7c6c3b8c401f6a4ac8f131a9e1059957036",
            "chacha_key": "17f8057e6156ba7cc5310d01eda8c40f9aa388f9fd1712deb9511f13ecc37d27",
            "chacha_nonce": "a8188daff807a1182200b39d",
            "hmac_key": "47b89da97f68d389867b5d8a2d7ba55715a30e3d88a3cc11f3646bc2af5580ef"
          }
        ]
      },
      "calc_padded_len": [
        [16, 32],
        [32, 32],
        [33, 64],
        [37, 64],
        [45, 64],
        [49, 64],
        [64, 64],
        [65, 96],
        [100, 128],
        [111, 128],
        [200, 224],
        [250, 256],
        [320, 320],
        [383, 384],
        [384, 384],
        [400, 448],
        [500, 512],
        [512, 512],
        [515, 640],
        [700, 768],
        [800, 896],
        [900, 1024],
        [1020, 1024],
        [65536, 65536]
      ],
      "encrypt_decrypt": [
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000001",
          "sec2": "0000000000000000000000000000000000000000000000000000000000000002",
          "conversation_key": "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d",
          "nonce": "0000000000000000000000000000000000000000000000000000000000000001",
          "plaintext": "a",
          "payload": "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"
        },
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000002",
          "sec2": "0000000000000000000000000000000000000000000000000000000000000001",
          "conversation_key": "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d",
          "nonce": "f00000000000000000000000000000f00000000000000000000000000000000f",
          "plaintext": "🍕🫃",
          "payload": "AvAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAPSKSK6is9ngkX2+cSq85Th16oRTISAOfhStnixqZziKMDvB0QQzgFZdjLTPicCJaV8nDITO+QfaQ61+KbWQIOO2Yj"
        },
        {
          "sec1": "5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a",
          "sec2": "4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d",
          "conversation_key": "3e2b52a63be47d34fe0a80e34e73d436d6963bc8f39827f327057a9986c20a45",
          "nonce": "b635236c42db20f021bb8d1cdff5ca75dd1a0cc72ea742ad750f33010b24f73b",
          "plaintext": "表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀",
          "payload": "ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs="
        },
        {
          "sec1": "8f40e50a84a7462e2b8d24c28898ef1f23359fff50d8c509e6fb7ce06e142f9c",
          "sec2": "b9b0a1e9cc20100c5faa3bbe2777303d25950616c4c6a3fa2e3e046f936ec2ba",
          "conversation_key": "d5a2f879123145a4b291d767428870f5a8d9e5007193321795b40183d4ab8c2b",
          "nonce": "b20989adc3ddc41cd2c435952c0d59a91315d8c5218d5040573fc3749543acaf",
          "plaintext": "ability🤝的 ȺȾ",
          "payload": "ArIJia3D3cQc0sQ1lSwNWakTFdjFIY1QQFc/w3SVQ6yvbG2S0x4Yu86QGwPTy7mP3961I1XqB6SFFTzqDZZavhxoWMj7mEVGMQIsh2RLWI5EYQaQDIePSnXPlzf7CIt+voTD"
        },
        {
          "sec1": "875adb475056aec0b4809bd2db9aa00cff53a649e7b59d8edcbf4e6330b0995c",
          "sec2": "9c05781112d5b0a2a7148a222e50e0bd891d6b60c5483f03456e982185944aae",
          "conversation_key": "3b15c977e20bfe4b8482991274635edd94f366595b1a3d2993515705ca3cedb8",
          "nonce": "8d4442713eb9d4791175cb040d98d6fc5be8864d6ec2f89cf0895a2b2b72d1b1",
          "plaintext": "pepper👀їжак",
          "payload": "Ao1EQnE+udR5EXXLBA2Y1vxb6IZNbsL4nPCJWisrctGxY3AduCS+jTUgAAnfvKafkmpy15+i9YMwCdccisRa8SvzW671T2JO4LFSPX31K4kYUKelSAdSPwe9NwO6LhOsnoJ+"
        },
        {
          "sec1": "eba1687cab6a3101bfc68fd70f214aa4cc059e9ec1b79fdb9ad0a0a4e259829f",
          "sec2": "dff20d262bef9dfd94666548f556393085e6ea421c8af86e9d333fa8747e94b3",
          "conversation_key": "4f1538411098cf11c8af216836444787c462d47f97287f46cf7edb2c4915b8a5",
          "nonce": "2180b52ae645fcf9f5080d81b1f0b5d6f2cd77ff3c986882bb549158462f3407",
          "plaintext": "( ͡° ͜ʖ ͡°)",
          "payload": "AiGAtSrmRfz59QgNgbHwtdbyzXf/PJhogrtUkVhGLzQHv4qhKQwnFQ54OjVMgqCea/Vj0YqBSdhqNR777TJ4zIUk7R0fnizp6l1zwgzWv7+ee6u+0/89KIjY5q1wu6inyuiv"
        },
        {
          "sec1": "d5633530f5bcfebceb5584cfbbf718a30df0751b729dd9a789b9f30c0587d74e",
          "sec2": "b74e6a341fb134127272b795a08b59250e5fa45a82a2eb4095e4ce9ed5f5e214",
          "conversation_key": "75fe686d21a035f0c7cd70da64ba307936e5ca0b20710496a6b6b5f573377bdd",
          "nonce": "e4cd5f7ce4eea024bc71b17ad456a986a74ac426c2c62b0a15eb5c5c8f888b68",
          "plaintext": "مُنَاقَشَةُ سُبُلِ اِسْتِخْدَامِ اللُّغَةِ فِي النُّظُمِ الْقَائِمَةِ وَفِيم يَخُصَّ التَّطْبِيقَاتُ الْحاسُوبِيَّةُ،",
          "payload": "AuTNX3zk7qAkvHGxetRWqYanSsQmwsYrChXrXFyPiItoIBsWu1CB+sStla2M4VeANASHxM78i1CfHQQH1YbBy24Tng7emYW44ol6QkFD6D8Zq7QPl+8L1c47lx8RoODEQMvNCbOk5ffUV3/AhONHBXnffrI+0025c+uRGzfqpYki4lBqm9iYU+k3Tvjczq9wU0mkVDEaM34WiQi30MfkJdRbeeYaq6kNvGPunLb3xdjjs5DL720d61Flc5ZfoZm+CBhADy9D9XiVZYLKAlkijALJur9dATYKci6OBOoc2SJS2Clai5hOVzR0yVeyHRgRfH9aLSlWW5dXcUxTo7qqRjNf8W5+J4jF4gNQp5f5d0YA4vPAzjBwSP/5bGzNDslKfcAH"
        },
        {
          "sec1": "d5633530f5bcfebceb5584cfbbf718a30df0751b729dd9a789b9f30c0587d74e",
          "sec2": "b74e6a341fb134127272b795a08b59250e5fa45a82a2eb4095e4ce9ed5f5e214",
          "conversation_key": "75fe686d21a035f0c7cd70da64ba307936e5ca0b20710496a6b6b5f573377bdd",
          "nonce": "38d1ca0abef9e5f564e89761a86cee04574b6825d3ef2063b10ad75899e4b023",
          "plaintext": "الكل في المجمو عة (5)",
          "payload": "AjjRygq++eX1ZOiXYahs7gRXS2gl0+8gY7EK11iZ5LAjbOTrlfrxak5Lki42v2jMPpLSicy8eHjsWkkMtF0i925vOaKG/ZkMHh9ccQBdfTvgEGKzztedqDCAWb5TP1YwU1PsWaiiqG3+WgVvJiO4lUdMHXL7+zKKx8bgDtowzz4QAwI="
        },
        {
          "sec1": "d5633530f5bcfebceb5584cfbbf718a30df0751b729dd9a789b9f30c0587d74e",
          "sec2": "b74e6a341fb134127272b795a08b59250e5fa45a82a2eb4095e4ce9ed5f5e214",
          "conversation_key": "75fe686d21a035f0c7cd70da64ba307936e5ca0b20710496a6b6b5f573377bdd",
          "nonce": "4f1a31909f3483a9e69c8549a55bbc9af25fa5bbecf7bd32d9896f83ef2e12e0",
          "plaintext": "𝖑𝖆𝖟𝖞 社會科學院語學研究所",
          "payload": "Ak8aMZCfNIOp5pyFSaVbvJryX6W77Pe9MtmJb4PvLhLgh/TsxPLFSANcT67EC1t/qxjru5ZoADjKVEt2ejdx+xGvH49mcdfbc+l+L7gJtkH7GLKpE9pQNQWNHMAmj043PAXJZ++fiJObMRR2mye5VHEANzZWkZXMrXF7YjuG10S1pOU="
        },
        {
          "sec1": "d5633530f5bcfebceb5584cfbbf718a30df0751b729dd9a789b9f30c0587d74e",
          "sec2": "b74e6a341fb134127272b795a08b59250e5fa45a82a2eb4095e4ce9ed5f5e214",
          "conversation_key": "75fe686d21a035f0c7cd70da64ba307936e5ca0b20710496a6b6b5f573377bdd",
          "nonce": "a3e219242d85465e70adcd640b564b3feff57d2ef8745d5e7a0663b2dccceb54",
          "plaintext": "🙈 🙉 🙊 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 Powerلُلُصّبُلُلصّبُررً ॣ ॣh ॣ ॣ冗",
          "payload": "AqPiGSQthUZecK3NZAtWSz/v9X0u+HRdXnoGY7LczOtUf05aMF89q1FLwJvaFJYICZoMYgRJHFLwPiOHce7fuAc40kX0wXJvipyBJ9HzCOj7CgtnC1/cmPCHR3s5AIORmroBWglm1LiFMohv1FSPEbaBD51VXxJa4JyWpYhreSOEjn1wd0lMKC9b+osV2N2tpbs+rbpQem2tRen3sWflmCqjkG5VOVwRErCuXuPb5+hYwd8BoZbfCrsiAVLd7YT44dRtKNBx6rkabWfddKSLtreHLDysOhQUVOp/XkE7OzSkWl6sky0Hva6qJJ/V726hMlomvcLHjE41iKmW2CpcZfOedg=="
        }
      ],
      "encrypt_decrypt_long_msg": [
        {
          "conversation_key": "8fc262099ce0d0bb9b89bac05bb9e04f9bc0090acc181fef6840ccee470371ed",
          "nonce": "326bcb2c943cd6bb717588c9e5a7e738edf6ed14ec5f5344caa6ef56f0b9cff7",
          "pattern": "x",
          "repeat": 65535,
          "plaintext_sha256": "09ab7495d3e61a76f0deb12cb0306f0696cbb17ffc12131368c7a939f12f56d3",
          "payload_sha256": "90714492225faba06310bff2f249ebdc2a5e609d65a629f1c87f2d4ffc55330a"
        },
        {
          "conversation_key": "56adbe3720339363ab9c3b8526ffce9fd77600927488bfc4b59f7a68ffe5eae0",
          "nonce": "ad68da81833c2a8ff609c3d2c0335fd44fe5954f85bb580c6a8d467aa9fc5dd0",
          "pattern": "!",
          "repeat": 65535,
          "plaintext_sha256": "6af297793b72ae092c422e552c3bb3cbc310da274bd1cf9e31023a7fe4a2d75e",
          "payload_sha256": "8013e45a109fad3362133132b460a2d5bce235fe71c8b8f4014793fb52a49844"
        },
        {
          "conversation_key": "7fc540779979e472bb8d12480b443d1e5eb1098eae546ef2390bee499bbf46be",
          "nonce": "34905e82105c20de9a2f6cd385a0d541e6bcc10601d12481ff3a7575dc622033",
          "pattern": "🦄",
          "repeat": 16383,
          "plaintext_sha256": "a249558d161b77297bc0cb311dde7d77190f6571b25c7e4429cd19044634a61f",
          "payload_sha256": "b3348422471da1f3c59d79acfe2fe103f3cd24488109e5b18734cdb5953afd15"
        }
      ]
    },
    "invalid": {
      "encrypt_msg_lengths": [0, 65536, 100000, 10000000],
      "get_conversation_key": [
        {
          "sec1": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "pub2": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
          "note": "sec1 higher than curve.n"
        },
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000000",
          "pub2": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
          "note": "sec1 is 0"
        },
        {
          "sec1": "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139",
          "pub2": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "note": "pub2 is invalid, no sqrt, all-ff"
        },
        {
          "sec1": "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
          "pub2": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
          "note": "sec1 == curve.n"
        },
        {
          "sec1": "0000000000000000000000000000000000000000000000000000000000000002",
          "pub2": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
          "note": "pub2 is invalid, no sqrt"
        },
        {
          "sec1": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
          "pub2": "0000000000000000000000000000000000000000000000000000000000000000",
          "note": "pub2 is point of order 3 on twist"
        },
        {
          "sec1": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
          "pub2": "eb1f7200aecaa86682376fb1c13cd12b732221e774f553b0a0857f88fa20f86d",
          "note": "pub2 is point of order 13 on twist"
        },
        {
          "sec1": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
          "pub2": "709858a4c121e4a84eb59c0ded0261093c71e8ca29efeef21a6161c447bcaf9f",
          "note": "pub2 is point of order 3319 on twist"
        }
      ],
      "decrypt": [
        {
          "conversation_key": "ca2527a037347b91bea0c8a30fc8d9600ffd81ec00038671e3a0f0cb0fc9f642",
          "nonce": "daaea5ca345b268e5b62060ca72c870c48f713bc1e00ff3fc0ddb78e826f10db",
          "plaintext": "n o b l e",
          "payload": "#Atqupco0WyaOW2IGDKcshwxI9xO8HgD/P8Ddt46CbxDbrhdG8VmJdU0MIDf06CUvEvdnr1cp1fiMtlM/GrE92xAc1K5odTpCzUB+mjXgbaqtntBUbTToSUoT0ovrlPwzGjyp",
          "note": "unknown encryption version"
        },
        {
          "conversation_key": "36f04e558af246352dcf73b692fbd3646a2207bd8abd4b1cd26b234db84d9481",
          "nonce": "ad408d4be8616dc84bb0bf046454a2a102edac937c35209c43cd7964c5feb781",
          "plaintext": "⚠️",
          "payload": "AK1AjUvoYW3IS7C/BGRUoqEC7ayTfDUgnEPNeWTF/reBZFaha6EAIRueE9D1B1RuoiuFScC0Q94yjIuxZD3JStQtE8JMNacWFs9rlYP+ZydtHhRucp+lxfdvFlaGV/sQlqZz",
          "note": "unknown encryption version 0"
        },
        {
          "conversation_key": "ca2527a037347b91bea0c8a30fc8d9600ffd81ec00038671e3a0f0cb0fc9f642",
          "nonce": "daaea5ca345b268e5b62060ca72c870c48f713bc1e00ff3fc0ddb78e826f10db",
          "plaintext": "n o s t r",
          "payload": "Atфupco0WyaOW2IGDKcshwxI9xO8HgD/P8Ddt46CbxDbrhdG8VmJZE0UICD06CUvEvdnr1cp1fiMtlM/GrE92xAc1EwsVCQEgWEu2gsHUVf4JAa3TpgkmFc3TWsax0v6n/Wq",
          "note": "invalid base64"
        },
        {
          "conversation_key": "cff7bd6a3e29a450fd27f6c125d5edeb0987c475fd1e8d97591e0d4d8a89763c",
          "nonce": "09ff97750b084012e15ecb84614ce88180d7b8ec0d468508a86b6d70c0361a25",
          "plaintext": "¯\\_(ツ)_/¯",
          "payload": "Agn/l3ULCEAS4V7LhGFM6IGA17jsDUaFCKhrbXDANholyySBfeh+EN8wNB9gaLlg4j6wdBYh+3oK+mnxWu3NKRbSvQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
          "note": "invalid MAC"
        },
        {
          "conversation_key": "cfcc9cf682dfb00b11357f65bdc45e29156b69db424d20b3596919074f5bf957",
          "nonce": "65b14b0b949aaa7d52c417eb753b390e8ad6d84b23af4bec6d9bfa3e03a08af4",
          "plaintext": "🥎",
          "payload": "AmWxSwuUmqp9UsQX63U7OQ6K1thLI69L7G2b+j4DoIr0oRWQ8avl4OLqWZiTJ10vIgKrNqjoaX+fNhE9RqmR5g0f6BtUg1ijFMz71MO1D4lQLQfW7+UHva8PGYgQ1QpHlKgR",
          "note": "invalid MAC"
        },
        {
          "conversation_key": "5254827d29177622d40a7b67cad014fe7137700c3c523903ebbe3e1b74d40214",
          "nonce": "7ab65dbb8bbc2b8e35cafb5745314e1f050325a864d11d0475ef75b3660d91c1",
          "plaintext": "elliptic-curve cryptography",
          "payload": "Anq2XbuLvCuONcr7V0UxTh8FAyWoZNEdBHXvdbNmDZHB573MI7R7rrTYftpqmvUpahmBC2sngmI14/L0HjOZ7lWGJlzdh6luiOnGPc46cGxf08MRC4CIuxx3i2Lm0KqgJ7vA",
          "note": "invalid padding"
        },
        {
          "conversation_key": "fea39aca9aa8340c3a78ae1f0902aa7e726946e4efcd7783379df8096029c496",
          "nonce": "7d4283e3b54c885d6afee881f48e62f0a3f5d7a9e1cb71ccab594a7882c39330",
          "plaintext": "noble",
          "payload": "An1Cg+O1TIhdav7ogfSOYvCj9dep4ctxzKtZSniCw5MwRrrPJFyAQYZh5VpjC2QYzny5LIQ9v9lhqmZR4WBYRNJ0ognHVNMwiFV1SHpvUFT8HHZN/m/QarflbvDHAtO6pY16",
          "note": "invalid padding"
        },
        {
          "conversation_key": "0c4cffb7a6f7e706ec94b2e879f1fc54ff8de38d8db87e11787694d5392d5b3f",
          "nonce": "6f9fd72667c273acd23ca6653711a708434474dd9eb15c3edb01ce9a95743e9b",
          "plaintext": "censorship-resistant and global social network",
          "payload": "Am+f1yZnwnOs0jymZTcRpwhDRHTdnrFcPtsBzpqVdD6b2NZDaNm/TPkZGr75kbB6tCSoq7YRcbPiNfJXNch3Tf+o9+zZTMxwjgX/nm3yDKR2kHQMBhVleCB9uPuljl40AJ8kXRD0gjw+aYRJFUMK9gCETZAjjmrsCM+nGRZ1FfNsHr6Z",
          "note": "invalid padding"
        },
        {
          "conversation_key": "5cd2d13b9e355aeb2452afbd3786870dbeecb9d355b12cb0a3b6e9da5744cd35",
          "nonce": "b60036976a1ada277b948fd4caa065304b96964742b89d26f26a25263a5060bd",
          "plaintext": "0",
          "payload": "",
          "note": "invalid payload length: 0"
        },
        {
          "conversation_key": "d61d3f09c7dfe1c0be91af7109b60a7d9d498920c90cbba1e137320fdd938853",
          "nonce": "1a29d02c8b4527745a2ccb38bfa45655deb37bc338ab9289d756354cea1fd07c",
          "plaintext": "1",
          "payload": "Ag==",
          "note": "invalid payload length: 4"
        },
        {
          "conversation_key": "873bb0fc665eb950a8e7d5971965539f6ebd645c83c08cd6a85aafbad0f0bc47",
          "nonce": "c826d3c38e765ab8cc42060116cd1464b2a6ce01d33deba5dedfb48615306d4a",
          "plaintext": "2",
          "payload": "AqxgToSh3H7iLYRJjoWAM+vSv/Y1mgNlm6OWWjOYUClrFF8=",
          "note": "invalid payload length: 48"
        },
        {
          "conversation_key": "9f2fef8f5401ac33f74641b568a7a30bb19409c76ffdc5eae2db6b39d2617fbe",
          "nonce": "9ff6484642545221624eaac7b9ea27133a4cc2356682a6033aceeef043549861",
          "plaintext": "3",
          "payload": "Ap/2SEZCVFIhYk6qx7nqJxM6TMI1ZoKmAzrO7vBDVJhhuZXWiM20i/tIsbjT0KxkJs2MZjh1oXNYMO9ggfk7i47WQA==",
          "note": "invalid payload length: 92"
        }
      ]
    }
  }
}
'''

# BIP-173 "Test vectors" section, valid strings.
BECH32_VALID = [
    "A12UEL5L",
    "a12uel5l",
    "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcluded"
    "charactersbio1tt5tgs",
    "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
    "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
    "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
    "?1ezyfcl",
]

# BIP-173 invalid strings, MINUS the length-cap one (deliberately moved to
# BECH32_OVERLONG below: NIP-19 waives the cap and check_bech32 asserts the
# waiver on purpose).
BECH32_INVALID = [
    "\x201nwldj5",          # HRP character out of range
    "\x7f1axkwrx",          # HRP character out of range
    "\x801eym55h",          # HRP character out of range
    "pzry9x0s0muk",         # no separator character
    "1pzry9x0s0muk",        # empty HRP
    "x1b4n0q5v",            # invalid data character
    "li1dgmt3",             # too short checksum
    "de1lg7wt\xff",         # invalid character in checksum
    "A1G7SGD8",             # checksum calculated with uppercase form of HRP
    "10a06t8",              # empty HRP
    "1qzzfhee",             # empty HRP
]

BECH32_OVERLONG = ("an84characterslonghumanreadablepartthatcontainsthenumber1"
                   "andtheexcludedcharactersbio1569pvx")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
