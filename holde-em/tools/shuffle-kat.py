#!/usr/bin/env python3
"""Known-answer vectors for the playable integer shuffle (spec 7.1 deal, the
binary-free hotseat variant shipped in v0.2.0).

Mirror of heFreshPrngState / heRngStep / heDrawInt / heShuffleDeck in
src/holdem.livecodescript. The playable deal deliberately avoids all
FFI-bridged binary (which threw double/binary conversion errors through the
OXT chunk evaluator); its randomness is Park-Miller MINSTD, a pure-integer
PRNG whose every product stays under 2^53 and is therefore exact in the
doubles LiveCode uses for numbers. This file pins the exact deck a fixed
seed produces so the xTalk and this mirror agree; the stack's self-test
carries the same seed-1 vector (kKatSeed1Deck).

MINSTD: x' = 16807 * x mod (2^31 - 1); draws are rejection-sampled to
1..n (no modulo bias); Fisher-Yates for i = 52..2 swaps deck[i], deck[j].

The cryptographic Level 0 deal (commit-reveal keyed-stream, spec 7.1) stays
pinned separately in tools/protocol-kat.py as the Phase 2 / value-path
target; this file covers only the shipped hotseat shuffle.

Usage::

    python3 tools/shuffle-kat.py

Exit status is non-zero on any failure (CI gate).
"""

import sys

RNG_MUL = 16807
RNG_MOD = 2147483647
RNG_MAX = 2147483646
RANKS = "23456789TJQKA"
SUITS = "cdhs"


def card_name(i):
    return RANKS[(i - 1) // 4] + SUITS[(i - 1) % 4]


def rng_step(state):
    return (RNG_MUL * state) % RNG_MOD


def draw_int(state, n):
    """Uniform 1..n by rejection sampling; returns (value, new_state)."""
    limit = (RNG_MAX // n) * n
    s = state
    while True:
        s = rng_step(s)
        v = s - 1
        if v < limit:
            return (v % n) + 1, s


def shuffle_deck(seed):
    deck = list(range(1, 53))
    s = seed
    # mirrors heShuffleDeck's defensive clamp: MINSTD has no 0 state (0 maps
    # to 0 forever), and Python's % would wrap the -1 draw to n where the
    # engine's sign-of-dividend mod yields 0 -- clamp so the two sides can
    # never diverge on a bad seed
    if not isinstance(s, (int, float)) or s < 1:
        s = 1
    for i in range(52, 1, -1):
        j, s = draw_int(s, i)
        deck[i - 1], deck[j - 1] = deck[j - 1], deck[i - 1]
    return deck


# The exact vector embedded in the stack's self-test (kKatSeed1Deck).
SEED1_DECK = ("8h,4d,6s,Qd,2c,2d,6d,7d,Ad,Jd,8d,5c,5d,Ts,Tc,7c,8c,Ac,3c,Js,"
              "6c,Ah,9d,Jh,2h,As,9s,Kc,8s,4c,Qc,5h,Th,7s,2s,Kh,5s,Qh,9c,4s,"
              "Jc,3d,Kd,9h,3s,Qs,3h,Td,Ks,7h,6h,4h")


def main():
    fails = 0

    got = ",".join(card_name(c) for c in shuffle_deck(1))
    if got == SEED1_DECK:
        print("PASS  seed 1 deck matches the stack's pinned vector")
    else:
        print("FAIL  seed 1 deck\n  observed=%s\n  expected=%s" % (got, SEED1_DECK))
        fails += 1

    # permutation property across a spread of seeds
    for seed in (1, 2, 42, 20260712, RNG_MAX):
        deck = shuffle_deck(seed)
        if sorted(deck) == list(range(1, 53)):
            print("PASS  seed %d deck is a permutation of 1..52" % seed)
        else:
            print("FAIL  seed %d deck is not a permutation" % seed)
            fails += 1

    # determinism: same seed reproduces the deck
    if shuffle_deck(20260712) == shuffle_deck(20260712):
        print("PASS  shuffle is deterministic for a fixed seed")
    else:
        print("FAIL  shuffle is not deterministic")
        fails += 1

    # every draw stays in range across all Fisher-Yates ranges
    bad_range = 0
    s = 1
    for n in range(2, 53):
        v, s = draw_int(s, n)
        if not (1 <= v <= n):
            bad_range += 1
    if bad_range == 0:
        print("PASS  every draw lands in 1..n")
    else:
        print("FAIL  %d draws out of range" % bad_range)
        fails += 1

    print()
    if fails:
        print("FAILED -- %d shuffle vector(s) wrong." % fails)
        return 1
    print("All shuffle vectors passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
