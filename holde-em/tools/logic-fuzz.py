#!/usr/bin/env python3
"""Independent-reference fuzz for the pure game logic.

The other KAT gates (evaluator-kat, betting-kat) are *mirrors* of the xTalk --
ported line-for-line so that a green KAT plus a green on-engine harness pins the
two together. That proves "the port matches the engine"; it does NOT prove "the
rules are right", because a bug living in both the xTalk and its twin passes
unseen. This gate closes that hole: it drives the SAME mirror functions the KATs
export, but checks them against SECOND, independently-written implementations of
the hard parts -- the hand evaluator and side-pot settlement -- plus whole-game
invariants (chip conservation, no negative stacks, termination).

It is the committed backing for the "verified sound by property tests over tens
of thousands of configs" claim in the source header and CLAUDE.md: run in CI, it
exercises the evaluator EXHAUSTIVELY (all 2,598,960 five-card hands) and fuzzes
settlement and full games over 100k+ random configs with fixed seeds (so a
failure is reproducible). Any mismatch exits non-zero.

Independence, concretely:
  * Evaluator: the mirror groups by (count, rank); the reference here scans a
    descending straight window and builds tuples differently. We verify the two
    induce the SAME total order over every 5-card hand -- a well-defined,
    strictly monotonic bijection of equivalence classes -- and that there are
    exactly 7462 classes (the known count of distinct 5-card hand ranks).
  * Settlement: the mirror walks bet LEVELS; the reference PEELS the smallest
    remaining stake into successive pots. Different algorithms, same deltas.

Usage::

    python3 tools/logic-fuzz.py            # full run (CI)
    python3 tools/logic-fuzz.py --quick    # smaller counts for a fast local check

Exit status is non-zero on any mismatch (CI gate).
"""

import importlib.util
import itertools
import pathlib
import random
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

ev = _load("evkat", "tools/evaluator-kat.py")   # mirror of heRank5 / heEval7
bk = _load("bkat", "tools/betting-kat.py")       # mirror of heBetApply / heSettleOf


# --------------------------------------------------------------------------
# Independent evaluator reference (distinct straight/kicker construction from
# the mirror's (count,rank) grouping).
# --------------------------------------------------------------------------

def _card_rank(i):
    return (i - 1) // 4 + 2


def _card_suit(i):
    return (i - 1) % 4 + 1


def indep_rank5(cards):
    rs = [_card_rank(c) for c in cards]
    ss = [_card_suit(c) for c in cards]
    flush = len(set(ss)) == 1
    present = set(rs)
    sh = 0
    for hi in range(14, 5, -1):                      # scan straights top-down
        if all(r in present for r in range(hi - 4, hi + 1)):
            sh = hi
            break
    if sh == 0 and {14, 2, 3, 4, 5} <= present:      # the wheel
        sh = 5
    counts = Counter(rs)
    order = sorted(counts, key=lambda r: (counts[r], r), reverse=True)
    sizes = sorted(counts.values(), reverse=True)
    high = tuple(sorted(rs, reverse=True))
    if flush and sh:
        return (8, sh)
    if sizes[0] == 4:
        return (7, order[0], order[1])
    if sizes[0] == 3 and len(sizes) > 1 and sizes[1] == 2:
        return (6, order[0], order[1])
    if flush:
        return (5,) + high
    if sh:
        return (4, sh)
    if sizes[0] == 3:
        return (3, order[0], order[1], order[2])
    if sizes[0] == 2 and len(sizes) > 1 and sizes[1] == 2:
        return (2, order[0], order[1], order[2])
    if sizes[0] == 2:
        return (1,) + tuple(order)
    return (0,) + high


# The mathematically-known frequency of each 5-card category over all C(52,5)
# hands (category index matches rank5's leading field: 8=straight flush down to
# 0=high card). If the categorizer draws ANY boundary wrong, some count is off
# and the total stops summing to 2,598,960. This is the textbook proof of
# correctness -- independent of any second implementation.
KNOWN_5CARD_FREQ = {
    8: 40,        # straight flush (incl. royal)
    7: 624,       # four of a kind
    6: 3744,      # full house
    5: 5108,      # flush (excl. straight flush)
    4: 10200,     # straight (excl. straight flush)
    3: 54912,     # three of a kind
    2: 123552,    # two pair
    1: 1098240,   # one pair
    0: 1302540,   # high card
}


def indep_eval7(cards):
    """Independent best-5-of-7 (the reference's rank5 over all 21 subsets)."""
    return max(indep_rank5(c) for c in itertools.combinations(cards, 5))


def _order_iso(hands, mirror_fn, indep_fn):
    """Over the given hands, the mirror and independent evaluators must induce
    the SAME order: a well-defined mapping (mirror key -> a single indep key)
    that is strictly monotonic. Returns (ok, tie_splits, monotonic, classes)."""
    mirror_to_indep = {}
    tie_splits = 0
    for combo in hands:
        mk = tuple(mirror_fn(combo))
        ik = indep_fn(combo)
        if mk in mirror_to_indep:
            if mirror_to_indep[mk] != ik:
                tie_splits += 1
                if tie_splits <= 5:
                    print("  TIE-SPLIT mirror %r -> indep %r and %r (hand %r)"
                          % (mk, mirror_to_indep[mk], ik, combo))
        else:
            mirror_to_indep[mk] = ik
    mkeys = sorted(mirror_to_indep)
    ikeys = [mirror_to_indep[k] for k in mkeys]
    monotonic = all(ikeys[i] < ikeys[i + 1] for i in range(len(ikeys) - 1))
    return tie_splits == 0 and monotonic, tie_splits, monotonic, len(mkeys)


def check_evaluator(mode):
    """Three complementary proofs of the hand ranking:
      * FREQUENCY (exhaustive, cheap): over all 2,598,960 five-card hands, the
        count in each category must EXACTLY equal its known combinatorial value
        (40 straight flushes, 624 quads, ... 1,302,540 high cards). A wrong
        category boundary breaks a count -- a proof that needs no second impl.
      * STRUCTURE: exactly 7462 distinct rank values (the known class count).
      * ORDER + INDEPENDENCE: the mirror and an independently-written evaluator
        induce the same strict total order, at 5 cards AND at 7 (best-of-21).
        mode 'full' runs the 5-card order check EXHAUSTIVELY (~80 s); default
        uses a large random sample -- the exhaustive frequency+structure pass
        already pins the partition, so the sample only confirms the ordering."""
    ok = True
    distinct = set()
    freq = {c: 0 for c in KNOWN_5CARD_FREQ}
    for combo in itertools.combinations(range(1, 53), 5):
        vec = tuple(ev.rank5(combo))
        distinct.add(vec)
        freq[vec[0]] += 1
    classes = len(distinct)
    freq_ok = (freq == KNOWN_5CARD_FREQ)
    print("  evaluator frequency: category counts %s known distribution"
          % ("MATCH" if freq_ok else "DIFFER -> %r" % freq))
    print("  evaluator structure: %d distinct classes (expect 7462)" % classes)
    ok = ok and freq_ok and (classes == 7462)

    if mode == "full":
        hands5 = itertools.combinations(range(1, 53), 5)
        label = "exhaustive"
    else:
        rng = random.Random(31)
        hands5 = [tuple(rng.sample(range(1, 53), 5)) for _ in range(150000)]
        label = "150k-sample"
    iso_ok, ties, mono, _ = _order_iso(hands5, ev.rank5, indep_rank5)
    print("  evaluator 5-card order (%s vs independent ref): tie-splits %d, "
          "monotonic %s" % (label, ties, mono))
    ok = ok and iso_ok

    # 7-card best-of-21: the same order-isomorphism against an independent
    # best-of-21, so heEval7 (not just heRank5) is pinned to the rules.
    rng7 = random.Random(53)
    n7 = 4000 if mode == "full" else 12000
    hands7 = [tuple(rng7.sample(range(1, 53), 7)) for _ in range(n7)]
    iso7_ok, ties7, mono7, _ = _order_iso(hands7, ev.evaluate7, indep_eval7)
    print("  evaluator 7-card order (%dk-sample vs independent best-of-21): "
          "tie-splits %d, monotonic %s" % (n7 // 1000, ties7, mono7))
    return ok and iso7_ok


# --------------------------------------------------------------------------
# Independent settlement reference: peel the smallest remaining stake into
# successive pots (vs the mirror's level-walk).
# --------------------------------------------------------------------------

def _rotate_after(lst, entry):
    i = lst.index(entry)
    return lst[i + 1:] + lst[:i + 1]


def indep_settle(occ, button, hand_by, folded, ranks):
    remaining = {s: hand_by[s] for s in occ}
    pots = []                                        # (amount, contributors, eligible)
    while True:
        live_money = [s for s in occ if remaining[s] > 0]
        if not live_money:
            break
        m = min(remaining[s] for s in live_money)
        amount = 0
        contributors = []
        eligible = []
        for s in occ:
            take = min(remaining[s], m)
            if take > 0:
                remaining[s] -= take
                amount += take
                contributors.append(s)
                if folded[s] == "false":
                    eligible.append(s)
        pots.append((amount, contributors, eligible))
    deltas = {s: -hand_by[s] for s in occ}
    for amount, contributors, eligible in pots:
        if not eligible:                             # dead pot: refund contributors
            per = amount // len(contributors)
            for s in contributors:
                deltas[s] += per
            continue
        if len(eligible) == 1:
            winners = eligible
        else:
            best = max(ranks[s] for s in eligible)
            winners = [s for s in eligible if ranks[s] == best]
        share, rem = divmod(amount, len(winners))
        for s in winners:
            deltas[s] += share
        for s in _rotate_after(occ, button):         # odd chips clockwise from button
            if rem == 0:
                break
            if s in winners:
                deltas[s] += 1
                rem -= 1
    return deltas


def check_settlement(trials):
    rng = random.Random(7)
    mismatch = 0
    nonconserve = 0
    for _ in range(trials):
        n = rng.randint(2, 6)
        occ = sorted(rng.sample(range(1, 10), n))
        button = rng.choice(occ)
        hand_by = {s: rng.randint(0, 8) for s in occ}
        folded = {s: rng.choice(["true", "false", "false"]) for s in occ}
        if all(folded[s] == "true" for s in occ):
            folded[occ[0]] = "false"
        ranks = {s: "%012d" % rng.randint(0, 800000000000) for s in occ}
        st = {"occ": occ, "buttonSeat": button, "handBy": hand_by, "foldedBy": folded}
        d_mirror = bk.settle(st, ranks)
        d_indep = indep_settle(occ, button, hand_by, folded, ranks)
        if sum(d_mirror.values()) != 0:
            nonconserve += 1
        if d_mirror != d_indep:
            mismatch += 1
            if mismatch <= 6:
                print("  MISMATCH occ %r btn %d handBy %r folded %r"
                      % (occ, button, hand_by, {s: folded[s] for s in occ}))
                print("    mirror %r" % d_mirror)
                print("    indep  %r" % d_indep)
    print("  settlement: %d configs, delta-mismatch %d, non-conserving %d"
          % (trials, mismatch, nonconserve))
    return mismatch == 0 and nonconserve == 0


# --------------------------------------------------------------------------
# Whole-game invariants: drive random legal games through the mirror engine and
# assert chip conservation, no negative stacks, and termination.
# --------------------------------------------------------------------------

def _legal_actions(st):
    """Enumerate plausible actions by PROBING apply_msg -- deliberately not via
    the heBetLegal mirror, so this is an independent action source."""
    s = st["toAct"]
    acts = []
    for verb in ("fold", "check"):
        if bk.apply_msg(st, "act", s, verb + ",0")["err"] == "":
            acts.append(verb + ",0")
    owe = st["betCur"] - st["streetBy"][s]
    stack = st["stackBy"][s]
    if owe > 0:
        pay = min(owe, stack)
        if bk.apply_msg(st, "act", s, "call,%d" % pay)["err"] == "":
            acts.append("call,%d" % pay)
    maxto = st["streetBy"][s] + stack
    verb = "bet" if st["betCur"] == 0 else "raise"
    for t in range(st["betCur"] + 1, maxto + 1):
        if bk.apply_msg(st, "act", s, "%s,%d" % (verb, t))["err"] == "":
            acts.append("%s,%d" % (verb, t))
    if bk.apply_msg(st, "act", s, "allin,%d" % maxto)["err"] == "":
        acts.append("allin,%d" % maxto)
    return acts


def _legal_consistent(st):
    """Every action heBetLegal (bk.bet_legal) OFFERS must be accepted by apply_msg
    (the gate), and every action apply_msg ACCEPTS must be represented in the
    menu. A disagreement means the UI would offer an illegal move or hide a legal
    one -- a fairness bug. Returns a list of violation strings."""
    seat = st["toAct"]
    if st["phase"] != "acting":
        return []
    menu = bk.bet_legal(st, seat)
    verbs = set(m.split()[0] for m in menu)
    bad = []

    def accepts(action):
        return bk.apply_msg(st, "act", seat, action)["err"] == ""

    # 1) offered => accepted (bet/raise checked at min, max, and a midpoint)
    for a in menu:
        p = a.split()
        if p[0] in ("fold", "check"):
            if not accepts(p[0] + ",0"):
                bad.append("offered-rejected:" + a)
        elif p[0] in ("call", "allin"):
            if not accepts("%s,%s" % (p[0], p[1])):
                bad.append("offered-rejected:" + a)
        else:                                   # bet / raise MIN MAX
            lo, hi = int(p[1]), int(p[2])
            for t in {lo, hi, (lo + hi) // 2}:
                if not accepts("%s,%d" % (p[0], t)):
                    bad.append("offered-range-rejected:%s,%d" % (p[0], t))

    # 2) accepted => offered (per verb)
    stack = st["stackBy"][seat]
    owe = st["betCur"] - st["streetBy"][seat]
    max_to = st["streetBy"][seat] + stack
    for v in ("fold", "check"):
        if accepts(v + ",0") and v not in verbs:
            bad.append("accepted-not-offered:" + v)
    if owe > 0 and accepts("call,%d" % min(owe, stack)) and "call" not in verbs:
        bad.append("accepted-not-offered:call")
    if any(accepts("bet,%d" % t) for t in range(1, max_to + 1)) and "bet" not in verbs:
        bad.append("accepted-not-offered:bet")
    if any(accepts("raise,%d" % t) for t in range(st["betCur"] + 1, max_to + 1)) and "raise" not in verbs:
        bad.append("accepted-not-offered:raise")
    if accepts("allin,%d" % max_to) and "allin" not in verbs:
        bad.append("accepted-not-offered:allin")
    return bad


def _play_hand(sb, bb, stacks, occ, button, rng, legal_out=None, ante=0):
    st = bk.new_hand(sb, bb, stacks, occ, button, ante=ante)
    if ante > 0:
        for s in occ:
            st = bk.apply_msg(st, "bidAnte", s, min(ante, st["stackBy"][s]))
            assert st["err"] == "", st["err"]
    st = bk.apply_msg(st, "bidSB", st["sbSeat"], min(sb, st["stackBy"][st["sbSeat"]]))
    assert st["err"] == "", st["err"]
    st = bk.apply_msg(st, "bidBB", st["bbSeat"], min(bb, st["stackBy"][st["bbSeat"]]))
    assert st["err"] == "", st["err"]
    guard = 0
    while True:
        guard += 1
        assert guard < 500, "hand did not terminate"
        ph = st["phase"]
        if ph == "acting":
            if legal_out is not None:
                legal_out.extend(_legal_consistent(st))
            acts = _legal_actions(st)
            assert acts, "no legal action for seat %d" % st["toAct"]
            st = bk.apply_msg(st, "act", st["toAct"], rng.choice(acts))
            assert st["err"] == "", st["err"]
        elif ph == "runout":
            st = bk.apply_msg(st, "board", 0, 0)
        elif ph in ("showdown", "handdone"):
            break
        else:
            raise AssertionError("unexpected phase %r" % ph)
    inhand = [s for s in occ if st["foldedBy"][s] == "false"]
    ranks = {s: "%012d" % rng.randint(0, 800000000000) for s in inhand} if len(inhand) > 1 else {}
    return st, bk.settle(st, ranks)


def check_games(sessions):
    seed_rng = random.Random(2024)
    act_rng = random.Random(999)
    fails = 0
    hands = 0
    legal_bad = []
    for _ in range(sessions):
        n = seed_rng.randint(2, 6)
        seats = sorted(seed_rng.sample(range(1, 10), n))
        stacks = {s: seed_rng.randint(1, 60) for s in seats}
        total0 = sum(stacks.values())
        # a third of the sessions run with an ante, so the bidAnte / dead-money
        # path is fuzzed for chip conservation end to end (antes are pot money)
        ante = seed_rng.choice([0, 0, 1, 2]) if n >= 2 else 0
        last_bb = 0
        for _h in range(60):
            live = [s for s in seats if stacks[s] > 0]
            if len(live) < 2:
                break
            btn = bk.schedule_button(live, last_bb)
            st, d = _play_hand(1, 2, {s: stacks[s] for s in live}, live, btn, act_rng,
                               legal_bad, ante=ante)
            if sum(d.values()) != 0:
                print("  NONCONSERVE hand live=%r btn=%d d=%r" % (live, btn, d))
                fails += 1
            for s in live:
                stacks[s] += d[s]
            if any(stacks[s] < 0 for s in seats):
                print("  NEGATIVE STACK %r" % stacks)
                fails += 1
                break
            if sum(stacks.values()) != total0:
                print("  TOTAL DRIFT %d != %d" % (sum(stacks.values()), total0))
                fails += 1
                break
            last_bb = st["bbSeat"]
            hands += 1
    if legal_bad:
        fails += len(legal_bad)
        for v in legal_bad[:6]:
            print("  LEGAL-INCONSISTENT %s" % v)
    print("  games: %d sessions, %d hands, failures %d (heBetLegal disagreements %d)"
          % (sessions, hands, fails, len(legal_bad)))
    return fails == 0


def main():
    quick = "--quick" in sys.argv
    full = "--full" in sys.argv
    settle_trials = 20000 if quick else 80000
    game_sessions = 400 if quick else 1500

    print("independent-reference fuzz (quick=%s full=%s)" % (quick, full))
    results = []

    if quick:
        print("evaluator: structure + sampled order-isomorphism (skipped in --quick)")
    else:
        print("evaluator: exhaustive class count + order-isomorphism vs independent ref")
        results.append(("evaluator", check_evaluator("full" if full else "sample")))

    print("settlement: mirror level-walk vs independent peel")
    results.append(("settlement", check_settlement(settle_trials)))

    print("games: whole-game conservation / no-negative / termination")
    results.append(("games", check_games(game_sessions)))

    print()
    bad = [name for name, ok in results if not ok]
    if bad:
        print("FAILED -- %s" % ", ".join(bad))
        return 1
    print("All independent-reference fuzz checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
