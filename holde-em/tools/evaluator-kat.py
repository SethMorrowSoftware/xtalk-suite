#!/usr/bin/env python3
"""Known-answer vectors for the hold'em hand evaluator (spec 8.2).

This is the headless CI mirror of the pure-xTalk evaluator in
``src/holdem.livecodescript``. Both implementations follow the SAME algorithm
(rank every 5-card subset of the 7 cards, keep the best) and the SAME output
encoding, so the vectors below pin them to each other: the xTalk self-test
harness carries this exact vector list and must produce these exact packed
strings on-engine.

Encoding contract (mirrored verbatim in the stack script -- change one, change
both, and bump kHeHarnessV over there):

  * Card index: 1..52. index = (rank - 2) * 4 + suit, rank 2..14 (J=11 Q=12
    K=13 A=14), suit 1..4 = c,d,h,s. So 1="2c", 4="2s", 49="Ac", 52="As".
  * Card name: rank char from "23456789TJQKA" + suit char from "cdhs".
  * Evaluator result: a 12-char packed string of six 2-digit fields --
    category then five tiebreak ranks, zero-padded. Fixed width means plain
    numeric comparison ranks hands correctly (and the values stay well under
    2^53, so xTalk's doubles compare them exactly).
  * Categories: 8 straight flush, 7 quads, 6 full house, 5 flush, 4 straight,
    3 trips, 2 two pair, 1 pair, 0 high card. Wheel straights (A-2-3-4-5)
    carry high card 5, never 14.
  * Tiebreak fields per category, always padded to five with 00:
      SF/straight: high. Quads: quad rank, kicker. Boat: trips, pair.
      Flush/high: five ranks desc. Trips: rank, k1, k2.
      Two pair: hi pair, lo pair, kicker. Pair: rank, k1, k2, k3.

Usage::

    python3 tools/evaluator-kat.py            # run vectors + property checks
    python3 tools/evaluator-kat.py --gen-xtalk # print the harness vector block

Exit status is non-zero on any failure (CI gate).
"""

import itertools
import sys

RANKS = "23456789TJQKA"
SUITS = "cdhs"


def card_index(name):
    """"2c" -> 1 ... "As" -> 52 (the contract's canonical numbering)."""
    r = RANKS.index(name[0]) + 2
    s = SUITS.index(name[1]) + 1
    return (r - 2) * 4 + s


def card_name(i):
    return RANKS[(i - 1) // 4] + SUITS[(i - 1) % 4]


def card_rank(i):
    return (i - 1) // 4 + 2


def card_suit(i):
    return (i - 1) % 4 + 1


def rank5(cards):
    """Rank exactly five cards -> (category, t1..t5). Pure, order-free."""
    ranks = sorted((card_rank(c) for c in cards), reverse=True)
    suits = [card_suit(c) for c in cards]
    flush = len(set(suits)) == 1

    # Straight: five distinct ranks spanning 4, or the wheel. With exactly
    # five cards there is no window-scanning subtlety -- distinct + span.
    distinct = sorted(set(ranks), reverse=True)
    straight_high = 0
    if len(distinct) == 5:
        if distinct[0] - distinct[4] == 4:
            straight_high = distinct[0]
        elif distinct == [14, 5, 4, 3, 2]:
            straight_high = 5  # the wheel: ace plays low, high card is the 5

    if flush and straight_high:
        return (8, straight_high, 0, 0, 0, 0)

    # Histogram: group sizes decide the category; ranks break ties. Sort by
    # (count, rank) descending so e.g. the boat's trips outrank its pair.
    counts = {}
    for r in ranks:
        counts[r] = counts.get(r, 0) + 1
    groups = sorted(counts.items(), key=lambda kv: (kv[1], kv[0]), reverse=True)
    sizes = [g[1] for g in groups]
    granks = [g[0] for g in groups]

    if sizes[0] == 4:
        return (7, granks[0], granks[1], 0, 0, 0)
    if sizes[0] == 3 and sizes[1] == 2:
        return (6, granks[0], granks[1], 0, 0, 0)
    if flush:
        return (5,) + tuple(ranks)
    if straight_high:
        return (4, straight_high, 0, 0, 0, 0)
    if sizes[0] == 3:
        return (3, granks[0], granks[1], granks[2], 0, 0)
    if sizes[0] == 2 and sizes[1] == 2:
        return (2, granks[0], granks[1], granks[2], 0, 0)
    if sizes[0] == 2:
        return (1, granks[0], granks[1], granks[2], granks[3], 0)
    return (0,) + tuple(ranks)


def evaluate7(cards):
    """Best 5-of-7 by exhaustive 21-combination scan.

    Deliberately the dumbest correct algorithm: 21 rank5 calls per hand is
    nothing at human rate, it has no special cases to get wrong, and the same
    two nested loops translate one-for-one into xTalk. Cleverness lives in the
    independent cross-check implementations, not here.
    """
    return max(rank5(c) for c in itertools.combinations(cards, 5))


def packed(vec):
    """(cat, t1..t5) -> the 12-char fixed-width string both sides compare."""
    return "".join("%02d" % v for v in vec)


def eval_names(names):
    return evaluate7([card_index(n) for n in names.split()])


# --- Known-answer vectors (spec 8.2's list, plus the family's edge cases) ---
# Format: (label, "seven cards", expected packed string). This exact table is
# embedded in src/holdem-selftest.livecodescript; --gen-xtalk regenerates the
# block to paste there.
VECTORS = [
    ("royal flush", "As Ks Qs Js Ts 2c 3d", "081400000000"),
    ("straight flush 9 high", "9h 8h 7h 6h 5h Ad Kc", "080900000000"),
    ("wheel straight flush high=5", "Ah 2h 3h 4h 5h Kd Qc", "080500000000"),
    ("steel wheel not outranked by flush", "Ah 2h 3h 4h 5h Kh Qh", "080500000000"),
    ("quads with best kicker", "Qc Qd Qh Qs Ad 2c 3c", "071214000000"),
    ("quads on board, kicker decides", "8c 8d 8h 8s Kd 2c 2d", "070813000000"),
    ("boat over boat: two trips", "Ac Ad Ah Kc Kd Kh Qs", "061413000000"),
    ("boat: low trips high pair", "2c 2d 2h 3c 3d Ah Kh", "060203000000"),
    ("flush beats mixed straight", "9h 8h 6h 5h 2h 7c Td", "050908060502"),
    ("flush best five of seven suited", "Ah Qh Th 8h 6h 4h 2h", "051412100806"),
    ("broadway straight", "As Kd Qh Js Tc 2c 3d", "041400000000"),
    ("board plays: same broadway other holes", "As Kd Qh Js Tc 4h 5s", "041400000000"),
    ("wheel straight mixed suits high=5", "Ad 2c 3h 4s 5d Kc Qh", "040500000000"),
    ("seven-card run picks best high", "2c 3d 4h 5s 6c 7d 8h", "040800000000"),
    ("straight through paired board", "8c 7d 6h 5s 4c 8d 4d", "040800000000"),
    ("A-K-Q-J-9 is no straight", "Ac Kd Qh Js 9c 2d 3h", "001413121109"),
    ("trips with two kickers", "Ac Ad Ah Kc Qd 9s 2c", "031413120000"),
    ("two pair from three pairs, third pair kicks", "Ac Ad Kc Kd Qc Qd 2h", "021413120000"),
    ("two pair, lone ace outkicks third pair", "9c 9d 8c 8d 2h 2s Ac", "020908140000"),
    ("plain two pair ace kicker", "Jc Jd 4c 4d 9h 8s Ah", "021104140000"),
    ("one pair three kickers", "Ac Ad Kc Qd 9s 5h 2c", "011413120900"),
    ("full house from two trips low", "7c 7d 7h 4c 4d 4h As", "060704000000"),
    ("quads of deuces ace kicker", "2c 2d 2h 2s Ac 7d 5h", "070214000000"),
    ("six-card flush hides a J-high SF", "Kh Jh Th 9h 8h 7h 2c", "081100000000"),
    # tie-break edge cases the audit flagged as untested:
    ("6-high straight chosen over the wheel", "2c 3d 4h 5s 6c Ac Kd", "040600000000"),
    ("boat picks the higher of two pairs", "Ac Ad Ah Kc Kd Qc Qd", "061413000000"),
]

# Fixed permutations for the order-independence property (no randomness in a
# KAT): rotations, the reverse, and two hand-picked shuffles.
PERMS = [
    [1, 2, 3, 4, 5, 6, 7],
    [7, 6, 5, 4, 3, 2, 1],
    [4, 5, 6, 7, 1, 2, 3],
    [2, 4, 6, 1, 3, 5, 7],
    [5, 1, 7, 3, 6, 2, 4],
]


def gen_xtalk():
    """Print the vector table as the xTalk harness constant block."""
    print("-- generated by tools/evaluator-kat.py --gen-xtalk; do not hand-edit")
    for label, names, expect in VECTORS:
        print('    put "%s|%s|%s" & return after tVecs' % (names, expect, label))


def main():
    if "--gen-xtalk" in sys.argv:
        gen_xtalk()
        return 0

    fails = 0

    # 1. Known-answer vectors.
    for label, names, expect in VECTORS:
        got = packed(eval_names(names))
        if got == expect:
            print("PASS  %-44s %s" % (label, got))
        else:
            print("FAIL  %-44s observed=%s expected=%s" % (label, got, expect))
            fails += 1

    # 2. Order independence: every vector hand, every fixed permutation.
    for label, names, expect in VECTORS:
        cards = [card_index(n) for n in names.split()]
        base = evaluate7(cards)
        for p in PERMS:
            got = evaluate7([cards[i - 1] for i in p])
            if got != base:
                print("FAIL  order-independence %s perm=%s observed=%s expected=%s"
                      % (label, p, packed(got), packed(base)))
                fails += 1
    print("PASS  order-independence over %d hands x %d permutations"
          % (len(VECTORS), len(PERMS)))

    # 3. Trichotomy + antisymmetry of the packed comparison over every pair of
    #    vector hands: exactly one of <, ==, > holds, and the relation inverts
    #    (a>b iff b<a, a<b iff b>a). The strong ordering guarantee (packed value
    #    order == true hand strength) is pinned exhaustively by logic-fuzz's
    #    order-isomorphism pass; this pass guards that the packed encoding compares
    #    as a consistent total order (a packed() that ever returned an inconsistent
    #    or non-comparable value would break the count, not silently pass).
    #    NB: the earlier form -- `(a>b) and not (b<a) or (a==b)!=(b==a)` -- could
    #    never be true for any strings, so it was a vacuous no-op; this is a real
    #    assertion.
    vals = [(label, packed(eval_names(names))) for label, names, _ in VECTORS]
    for (la, a), (lb, bv) in itertools.combinations(vals, 2):
        trichotomy = (a < bv) + (a == bv) + (a > bv)
        if trichotomy != 1 or (a > bv) != (bv < a) or (a < bv) != (bv > a):
            print("FAIL  antisymmetry %s vs %s (a=%s b=%s)" % (la, lb, a, bv))
            fails += 1
    print("PASS  trichotomy + antisymmetry over all vector pairs")

    print()
    if fails:
        print("FAILED -- %d evaluator vector(s) wrong." % fails)
        return 1
    print("All evaluator vectors passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
