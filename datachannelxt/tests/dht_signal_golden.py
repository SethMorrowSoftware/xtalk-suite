#!/usr/bin/env python3
"""dht_signal_golden.py - pure-Python reference for the signaling PARSE BOUNDARY of
examples/datachannel-dht-chat.livecodescript: the decompressed body's split, the
offer/answer NONCE, and the two dedup rules the nonce drives. A PURE reference: no
engine, no DHT, no libdatachannel.

WHY THIS EXISTS (2026-09-27, the suite work plan's datachannelxt coding #9). The body
is `nonce LF type LF sdp`, and wxApplyRemote took whatever preceded the first LF as the
nonce. wxApplyOffer dedups with ("n" & nonce) is ("n" & last answered): a letter on
each side keeps `is` off its number path, which is sound only for hex, and nothing
checked the nonce was hex. A nonce "an" spells "nan", which C's strtod reads as a NaN,
unequal to everything, itself included (a Linux engine read two "nan" texts built that
way unequal on 2026-09-26: the suite's engine note 2.11), so one offer delivered again
was answered again, and the peer rebuilt, on every delivery. The demo now refuses any
nonce but 8 LOWERCASE hex at the split (wxNonceValid), the shape wxRandomNonce mints.

Mirrors these LiveCodeScript handlers:
  wxNonceValid   -> nonce_valid()   (exactly 8 chars, each 0-9 or a-f; case-exact)
  wxApplyRemote  -> split_body()    (split on the FIRST TWO LFs; the nonce checked at
                                     the split; the SDP keeps its own line breaks)
  wxApplyOffer   -> join_answers()  (the join side: an "offer" is answered unless it
                                     repeats the nonce last answered)
  wxApplyAnswer  -> host_applies()  (the host side: an "answer" is applied only if it
                                     echoes the CURRENT offer's nonce, and once)
  wxTryHead      -> fetches()       (a "C" head's chunk list starts a fetch unless it
                                     is, as TEXT, the list already being fetched)

The last is the same class met at the head (found 2026-09-27 beside #9): a one-chunk
list is one 40-hex target, and wxTryHead compared it with the running list by bare
`is`, which reads two different digits-e-digits targets as one +inf.

tools/check-script-vectors.py holds each mirror to the SHIPPED demo through the family
interpreter (riptide's runner), on the rows below: the chain is vector -> mirror (here),
mirror -> script (there). Nothing here promotes the demo past "verified statically;
needs an OXT pass".

    python3 tests/dht_signal_golden.py     # exit 0 = OK, 1 = mismatch
"""
import sys

_fail = []


def check(name, got, want):
    if got != want:
        _fail.append("%s:\n    got  %r\n    want %r" % (name, got, want))


NONCE_DIGITS = "0123456789abcdef"


def nonce_valid(s):
    """Mirror wxNonceValid: exactly 8 characters, each a LOWERCASE hex digit. Case-exact
    on purpose (the script judges code points, not a folding `is in`)."""
    return len(s) == 8 and all(c in NONCE_DIGITS for c in s)


def split_body(body):
    """Mirror wxApplyRemote's split of a DECOMPRESSED body (text): (nonce, kind, sdp) on
    the first two LFs only, or None when an LF is missing or the nonce is refused. Where
    the nonce is judged (before or after the second LF is found) does not change an
    outcome: every refusal drops the blob whole."""
    a = body.find("\n")
    if a < 0:
        return None
    nonce, rest = body[:a], body[a + 1:]
    if not nonce_valid(nonce):
        return None
    b = rest.find("\n")
    if b < 0:
        return None
    return (nonce, rest[:b], rest[b + 1:])


def join_answers(bodies):
    """Mirror the join side, wxApplyRemote -> wxApplyOffer, over a delivery sequence:
    the (nonce, sdp) of every offer ANSWERED, in order. An offer repeating the nonce
    last answered is dropped (a DHT lookup returns whatever nodes still hold, so the
    same offer arrives many times); a new nonce is followed, which is how a host's
    Reconnect under the same room code reaches the joiner."""
    seen, out = "", []
    for body in bodies:
        parts = split_body(body)
        if parts is None or parts[1] != "offer":
            continue
        nonce, _, sdp = parts
        if nonce == seen:
            continue
        seen = nonce
        out.append((nonce, sdp))
    return out


def host_applies(bodies, current):
    """Mirror the host side, wxApplyRemote -> wxApplyAnswer: the (nonce, sdp) of every
    answer APPLIED. Only an answer echoing `current` (the host's own offer nonce) counts,
    and only once."""
    applied, out = "", []
    for body in bodies:
        parts = split_body(body)
        if parts is None or parts[1] != "answer":
            continue
        nonce, _, sdp = parts
        if nonce != current or nonce == applied:
            continue
        applied = nonce
        out.append((nonce, sdp))
    return out


def fetches(lists):
    """Mirror wxTryHead's "C" branch over a sequence of chunk lists (the decoded head
    text, a comma list of targets): every list that STARTS a fetch, in order. A list
    equal, as text, to the one being fetched is left to its retries."""
    running, out = "", []
    for lst in lists:
        if lst == running:
            continue
        running = lst
        out.append(lst)
    return out


# The nonce rows (text, pinned answer). Every shape a remote can put before the first LF
# that a letter-prefixed compare would misread, and the edges of the one it may carry.
NONCE_ROWS = [
    ("0123abcd", True), ("deadbeef", True), ("00000000", True), ("ffffffff", True),
    ("1e999999", True),            # digits-e-digits: hex, compared behind a letter
    ("12345678", True),            # all digits: hex too, and behind a letter never a number
    ("an", False),                 # "n" & "an" spells "nan": THE row (datachannelxt #9)
    ("an(1234)", False),           # 8 chars, "nan(...)" is a NaN to C99 strtod
    ("anananan", False),           # 8 chars, not hex
    ("nan", False), ("inf", False), ("NaN", False), ("AN", False),
    ("", False),                   # an empty nonce: nothing minted it
    ("0123ABCD", False),           # upper case is not what the demo mints
    ("0123abcD", False),
    ("0123abc", False), ("0123abcde", False),      # 7 and 9
    ("0123abcg", False), ("0x23abcd", False), ("+123abcd", False), ("-123abcd", False),
    (" 123abcd", False), ("0123abc ", False), ("0123abc\r", False), ("0123abc\t", False),
    ("0123.bcd", False), ("0123\u00e9bcd", False), ("\u0660123abcd"[:8], False),
]

SDP = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\n"
GOOD, GOOD2 = "0123abcd", "1e999999"
# (label, [body, ...]) - each list a delivery sequence for one fresh joiner
JOIN_SEQUENCES = [
    ("one offer", [GOOD + "\noffer\n" + SDP]),
    ("the same offer twice (DHT redelivery)", [GOOD + "\noffer\n" + SDP] * 2),
    ("a new nonce is followed (Reconnect)", [GOOD + "\noffer\n" + SDP,
                                             GOOD2 + "\noffer\n" + SDP + "a=x\r\n"]),
    ("offer 'an' twice", ["an\noffer\n" + SDP] * 2),
    ("offer 'an(1234)' twice", ["an(1234)\noffer\n" + SDP] * 2),
    ("offer 'nan' twice", ["nan\noffer\n" + SDP] * 2),
    ("offer '0123ABCD' twice", ["0123ABCD\noffer\n" + SDP] * 2),
    ("an empty nonce", ["\noffer\n" + SDP]),
    ("a refused nonce then a good one", ["an\noffer\n" + SDP, GOOD + "\noffer\n" + SDP]),
    ("an answer is not an offer", [GOOD + "\nanswer\n" + SDP]),
    ("no second LF", [GOOD + "\noffer"]),
    ("no LF at all", [GOOD]),
    ("an SDP keeps its own LFs", [GOOD + "\noffer\nv=0\nline two\nline three"]),
    # two DIFFERENT nonces that one number reads the same (both are 1): the 2026-09-25
    # letter prefix is what keeps the second from being dropped as already answered
    ("two nonces that are one number (00000001, 1e000000)",
     ["00000001\noffer\n" + SDP, "1e000000\noffer\n" + SDP]),
]
T_A, T_B = "a" * 40, "b" * 40
T_INF1, T_INF2 = "1e" + "9" * 38, "2e" + "9" * 38     # two targets, each +inf to strtod
T_ONE1, T_ONE2 = "1e" + "0" * 38, "0" * 39 + "1"      # two targets, each the number 1
# (label, [chunk list, ...]) - each a sequence of "C" heads for one fresh fetch state
FETCH_SEQUENCES = [
    ("one list", [T_A + "," + T_B]),
    ("the same list twice (DHT redelivery)", [T_A + "," + T_B] * 2),
    ("a different list replaces the fetch", [T_A, T_B]),
    ("two one-chunk lists that are both +inf", [T_INF1, T_INF2]),
    ("two one-chunk lists that are both the number 1", [T_ONE1, T_ONE2]),
    ("the same +inf list twice", [T_INF1, T_INF1]),
]
HOST_CURRENT = "0123abcd"
# (label, the host's current offer nonce, [body, ...])
HOST_SEQUENCES = [
    ("the answer to the current offer", HOST_CURRENT, [HOST_CURRENT + "\nanswer\n" + SDP]),
    ("the same answer twice", HOST_CURRENT, [HOST_CURRENT + "\nanswer\n" + SDP] * 2),
    ("an answer to a previous offer", HOST_CURRENT, ["deadbeef\nanswer\n" + SDP]),
    ("answer 'an' twice", HOST_CURRENT, ["an\nanswer\n" + SDP] * 2),
    ("answer '0123ABCD' (the current nonce, upper-cased)", HOST_CURRENT,
     ["0123ABCD\nanswer\n" + SDP]),
    ("an offer is not an answer", HOST_CURRENT, [HOST_CURRENT + "\noffer\n" + SDP]),
    # an answer to ANOTHER offer whose nonce one number reads the same as the current one
    ("an answer echoing 1e000000 to the offer 00000001", "00000001",
     ["1e000000\nanswer\n" + SDP]),
    ("the answer to the offer 1e000000", "1e000000", ["1e000000\nanswer\n" + SDP]),
]


def main():
    for text, want in NONCE_ROWS:
        check("nonce_valid(%r)" % text, nonce_valid(text), want)
    check("split_body keeps the SDP's own LFs",
          split_body("0123abcd\noffer\nv=0\na\nb"), ("0123abcd", "offer", "v=0\na\nb"))
    check("split_body refuses a bad nonce whole", split_body("an\noffer\nv=0"), None)
    check("split_body wants the second LF", split_body("0123abcd\noffer"), None)
    check("split_body wants the first LF", split_body("0123abcd"), None)
    check("split_body: an empty SDP is still a split", split_body("0123abcd\noffer\n"),
          ("0123abcd", "offer", ""))
    # the sequences, pinned by count (the mirror's own logic is what the gate reuses)
    pinned_join = {"one offer": 1, "the same offer twice (DHT redelivery)": 1,
                   "a new nonce is followed (Reconnect)": 2, "offer 'an' twice": 0,
                   "offer 'an(1234)' twice": 0, "offer 'nan' twice": 0,
                   "offer '0123ABCD' twice": 0, "an empty nonce": 0,
                   "a refused nonce then a good one": 1, "an answer is not an offer": 0,
                   "no second LF": 0, "no LF at all": 0, "an SDP keeps its own LFs": 1,
                   "two nonces that are one number (00000001, 1e000000)": 2}
    for label, bodies in JOIN_SEQUENCES:
        check("join_answers %s" % label, len(join_answers(bodies)), pinned_join[label])
    pinned_host = {"the answer to the current offer": 1, "the same answer twice": 1,
                   "an answer to a previous offer": 0, "answer 'an' twice": 0,
                   "answer '0123ABCD' (the current nonce, upper-cased)": 0,
                   "an offer is not an answer": 0,
                   "an answer echoing 1e000000 to the offer 00000001": 0,
                   "the answer to the offer 1e000000": 1}
    for label, current, bodies in HOST_SEQUENCES:
        check("host_applies %s" % label, len(host_applies(bodies, current)),
              pinned_host[label])
    pinned_fetch = {"one list": 1, "the same list twice (DHT redelivery)": 1,
                    "a different list replaces the fetch": 2,
                    "two one-chunk lists that are both +inf": 2,
                    "two one-chunk lists that are both the number 1": 2,
                    "the same +inf list twice": 1}
    for label, lists in FETCH_SEQUENCES:
        check("fetches %s" % label, len(fetches(lists)), pinned_fetch[label])
    check("join_answers carries the SDP whole",
          join_answers([GOOD + "\noffer\nv=0\nline two"]), [(GOOD, "v=0\nline two")])
    if _fail:
        print("dht_signal_golden: FAIL\n" + "\n".join(_fail))
        return 1
    print("dht_signal_golden: OK (nonce shape, body split, join dedup, host echo, "
          "chunk-list fetch all match)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
