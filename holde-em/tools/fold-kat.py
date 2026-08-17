#!/usr/bin/env python3
"""Transcript-fold known-answer test: replay-as-audit, independently.

heFoldTranscript is the audit engine: it replays a signed transcript, RE-DERIVES
engine state / showdown ranks / settlement, and verifies the logged settle line
against the recomputation -- so a completed hand is "provably legitimate" only
because anyone can replay the transcript and reach the same payout (or catch a
tampered one). The on-engine harness pins heFoldTranscript against one canned
session, but the expected outcome (final stacks 442/394/364, per-hand deltas,
the caught tamper) was a magic number confirmed by no independent code.

This gate closes that: it replays the SAME canned transcript through an
INDEPENDENT fold (its own parser + replay loop, distinct orchestration from the
xTalk), driving the already-cross-checked betting/evaluator mirrors, and asserts
the final stacks, the per-hand deltas, the folded hand-history summary (board,
pot, winner, showdown hand names), and that a tampered settle line and an
illegal action are both caught on replay. Green here + green on-engine pins the
fold's logic the same way the other KATs pin the rules.

Usage::

    python3 tools/fold-kat.py

Exit status is non-zero on any mismatch (CI gate).
"""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

bk = _load("bkat", "tools/betting-kat.py")
ev = _load("evkat", "tools/evaluator-kat.py")
pk = _load("pkat", "tools/protocol-kat.py")   # deal machinery (spec 7.1)

CATEGORY = {8: "straight flush", 7: "four of a kind", 6: "full house",
            5: "flush", 4: "straight", 3: "three of a kind", 2: "two pair",
            1: "one pair", 0: "high card"}


# --------------------------------------------------------------------------
# The canned session, mirroring heTKatLog(pTamper) line for line: holes
# s1=3d5d s2=Ac5h s3=KcKh, board 3h2h5c4hTc; folds to 442/394/364.
# --------------------------------------------------------------------------

def transcript(tamper=""):
    L = []
    def log(hand, frm, typ, body):
        L.append((hand, frm, typ, body))
    log(0, "table", "cfg", "sb=1,bb=2,seats=1|2|3,stacks=400|400|400,button=1")
    log(1, "table", "handStart", "seats=1|2|3,button=1")
    log(1, "table", "holeDeliver", "seat=1,cards=3d|5d")
    log(1, "table", "holeDeliver", "seat=2,cards=Ac|5h")
    log(1, "table", "holeDeliver", "seat=3,cards=Kc|Kh")
    log(1, "seat2", "bidSB", "amount=1")
    log(1, "seat3", "bidBB", "amount=2")
    log(1, "seat1", "act", "verb=raise,amount=6")
    log(1, "seat2", "act", "verb=call,amount=5")
    if tamper == "badact":
        log(1, "seat3", "act", "verb=call,amount=7")
    log(1, "seat3", "act", "verb=call,amount=4")
    log(1, "table", "board", "street=flop,cards=3h|2h|5c")
    log(1, "seat2", "act", "verb=check,amount=0")
    log(1, "seat3", "act", "verb=bet,amount=10")
    log(1, "seat1", "act", "verb=call,amount=10")
    log(1, "seat2", "act", "verb=fold,amount=0")
    log(1, "table", "board", "street=turn,cards=4h")
    log(1, "seat3", "act", "verb=check,amount=0")
    log(1, "seat1", "act", "verb=check,amount=0")
    log(1, "table", "board", "street=river,cards=Tc")
    log(1, "seat3", "act", "verb=bet,amount=20")
    log(1, "seat1", "act", "verb=call,amount=20")
    # 2e display choice: the winner shows, the caller mucks its losing kings
    # (annotated "(mucked)" in the history line; mirror of heTKatLog)
    log(1, "seat1", "show", "seat=1")
    log(1, "seat3", "muck", "seat=3")
    if tamper == "settle":
        log(1, "table", "settle", "deltas=1:52|2:-16|3:-36")
    else:
        log(1, "table", "settle", "deltas=1:42|2:-6|3:-36")
    return L


def ante_transcript():
    # 3-handed, ante 2 each, blinds 1/2. Everyone antes (dead money), then folds
    # to the BB. Commitments are 2 / 3 / 4 (nine chips), but the AWARDED POT IS
    # 8: the BB's blind is uncalled by 1 chip -- the SB folded after putting in
    # 1 of the 2 -- and that chip is returned. The BB collects 8 against a
    # matched outlay of 3, netting the +5 the settle line records.
    #
    # This comment used to say "Pot = ... = 9" and "nets +7", and BOTH were
    # wrong in the same way the shipped history line was: they counted
    # commitments rather than the pot. Nothing caught it because no assertion
    # pinned the figure -- only the deltas, which reconcile under either
    # reading. Found 2026-08-17 while fixing the same defect in an all-in hand;
    # the ante case is the smaller, older instance of it.
    #
    # The fold must re-derive all of this from the bidAnte lines alone -- if it
    # ignored antes the settle would mismatch.
    L = []
    L.append((0, "table", "cfg",
              "sb=1,bb=2,ante=2,seats=1|2|3,stacks=400|400|400,button=1,levelMode=off,speed=normal"))
    L.append((1, "table", "handStart", "seats=1|2|3,button=1"))
    L.append((1, "table", "holeDeliver", "seat=1,cards=3d|5d"))
    L.append((1, "table", "holeDeliver", "seat=2,cards=Ac|5h"))
    L.append((1, "table", "holeDeliver", "seat=3,cards=Kc|Kh"))
    L.append((1, "seat1", "bidAnte", "amount=2"))
    L.append((1, "seat2", "bidAnte", "amount=2"))
    L.append((1, "seat3", "bidAnte", "amount=2"))
    L.append((1, "seat2", "bidSB", "amount=1"))
    L.append((1, "seat3", "bidBB", "amount=2"))
    L.append((1, "seat1", "act", "verb=fold,amount=0"))
    L.append((1, "seat2", "act", "verb=fold,amount=0"))
    # pot 9: seat1 -2 (ante), seat2 -3 (ante+SB), seat3 +5 (ante+BB back, +5 net)
    L.append((1, "table", "settle", "deltas=1:-2|2:-3|3:5"))
    return L


def uncalled_transcript():
    # HEADS-UP ALL-IN WHERE THE BIG STACK'S EXCESS IS UNCALLED -- the shape a
    # 2026-08-17 hotseat transcript found reported wrong. Seat 1 (2008) shoves;
    # seat 2 (392) calls all-in. Seat 1's 1616 excess is UNCALLED and returned,
    # so the awarded pot is 392 + 392 = 784, NOT the 2400 that summing handBy
    # gives. Seat 2 wins with the better hand.
    #
    # Why no existing case caught this: the two sessions above never leave an
    # uncalled bet on the table, so every seat's commitment equals the matched
    # level and sum(handBy) happens to BE the pot. The betting engine's own
    # "uncalled raise returned" check tests the RETURN; nothing tested the
    # reported POT. The deltas here are correct either way, which is exactly
    # why settle-verified passed beside a wrong pot figure.
    L = []
    L.append((0, "table", "cfg",
              "sb=1,bb=2,seats=1|2,stacks=2008|392,button=1,levelMode=off,speed=normal"))
    L.append((1, "table", "handStart", "seats=1|2,button=1"))
    L.append((1, "table", "holeDeliver", "seat=1,cards=2c|7h"))
    L.append((1, "table", "holeDeliver", "seat=2,cards=Kd|Kh"))
    L.append((1, "seat1", "bidSB", "amount=1"))
    L.append((1, "seat2", "bidBB", "amount=2"))
    L.append((1, "seat1", "act", "verb=raise,amount=2008"))
    # `call` carries the INCREMENT, not the total: seat 2 has already posted
    # the BB of 2, so 390 more takes it to its 392 all-in.
    L.append((1, "seat2", "act", "verb=call,amount=390"))
    L.append((1, "table", "board", "street=flop,cards=9d|3h|Kc"))
    L.append((1, "table", "board", "street=turn,cards=6s"))
    L.append((1, "table", "board", "street=river,cards=Ah"))
    L.append((1, "seat1", "show", "seat=1"))
    L.append((1, "seat2", "show", "seat=2"))
    L.append((1, "table", "settle", "deltas=1:-392|2:392"))
    return L


def _kv(body):
    return dict(part.split("=", 1) for part in body.split(","))


def independent_fold(tx):
    """A from-scratch replay: distinct parsing/orchestration from the xTalk's
    heFoldTranscript, driving the cross-checked betting/evaluator mirrors."""
    stacks = {}
    sb = bb = ante = 0
    st = None
    holes = {}
    board = []                       # card indices, in dealt order
    show_choice = {}                 # 2e display choice per seat, per hand
    history = []
    errors = []
    stacks_final = None
    for hand, frm, typ, body in tx:
        d = _kv(body) if body else {}
        if typ == "cfg":
            sb, bb = int(d["sb"]), int(d["bb"])
            ante = int(d.get("ante", 0))
            seats = [int(x) for x in d["seats"].split("|")]
            stk = [int(x) for x in d["stacks"].split("|")]
            stacks = {s: stk[i] for i, s in enumerate(seats)}
        elif typ == "level":
            sb, bb = int(d["sb"]), int(d["bb"])
            ante = int(d.get("ante", 0))
        elif typ == "handStart":
            occ = [int(x) for x in d["seats"].split("|")]
            btn = int(d["button"])
            st = bk.new_hand(sb, bb, {s: stacks[s] for s in occ}, occ, btn, ante=ante)
            holes, board = {}, []
            show_choice = {}
        elif typ == "holeDeliver":
            c = d["cards"].split("|")
            holes[int(d["seat"])] = [ev.card_index(c[0]), ev.card_index(c[1])]
        elif typ == "board":
            for c in d["cards"].split("|"):
                board.append(ev.card_index(c))
            st = bk.apply_msg(st, "board", 0, 0)
        elif typ in ("bidAnte", "bidSB", "bidBB"):
            st = bk.apply_msg(st, typ, int(frm[4:]), int(d["amount"]))
        elif typ == "act":
            st = bk.apply_msg(st, "act", int(frm[4:]), d["verb"] + "," + d["amount"])
            if st["err"]:
                errors.append("engine-rejected:" + st["err"])
        elif typ in ("show", "muck"):
            # 2e display choice: recorded ahead of the settle; annotates the
            # audited showdown, never changes it (mirror of heFoldTranscript)
            show_choice[int(d["seat"])] = typ
        elif typ == "settle":
            inhand = [s for s in st["occ"] if st["foldedBy"][s] == "false"]
            ranks = {}
            if len(inhand) > 1:
                # mirrors heFoldTranscript's settle guard: a contested showdown
                # needs 5 in-range board cards and a valid hole pair per
                # unfolded seat -- a truncated or hand-edited transcript is
                # named and skipped, never a crash mid-audit
                bad = len(board) != 5 or not all(1 <= c <= 52 for c in board)
                for s in inhand:
                    hp = holes.get(s, [])
                    if len(hp) != 2 or not all(1 <= c <= 52 for c in hp):
                        bad = True
                if bad:
                    errors.append("settle-bad-cards-hand-" + str(hand))
                    continue
                for s in inhand:
                    ranks[s] = ev.evaluate7(holes[s] + board)
            deltas = bk.settle(st, ranks)
            dtxt = "|".join("%d:%d" % (s, deltas[s]) for s in st["occ"])
            verified = (d["deltas"] == dtxt)
            if not verified:
                errors.append("settle-mismatch")
            for s in st["occ"]:
                stacks[s] += deltas[s]
            # THE AWARDED POT, NOT THE SUM OF COMMITMENTS (fixed 2026-08-17,
            # mirroring holdem.livecodescript). A bet nobody called is
            # RETURNED, so it was never in the pot - summing handBy reported
            # "pot 2400" for a real pot of 784 in a heads-up all-in (392 called
            # by a 2008 stack). The deltas were right throughout; only the
            # reported figure was wrong, which is why settle-verified passed
            # beside it. A seat's chips enter the pot only up to the largest
            # amount ANY OTHER seat committed.
            _amts = [st["handBy"][s] for s in st["occ"]]
            _hi1 = max(_amts, default=0)
            _hi2 = max(sorted(_amts)[:-1], default=0) if len(_amts) > 1 else 0
            pot = sum(a if a < _hi1 else _hi2 for a in _amts)
            winners = [s for s in st["occ"] if deltas[s] > 0]
            shown = []
            for s in st["occ"]:
                if s in ranks:
                    n1 = ev.card_name(holes[s][0])
                    n2 = ev.card_name(holes[s][1])
                    piece = "%d=%s %s %s" % (s, n1, n2, CATEGORY[ranks[s][0]])
                    # 2e: a seat that declined to show is annotated -- the
                    # transcript knows the cards, the table was never shown
                    if show_choice.get(s) == "muck":
                        piece += " (mucked)"
                    shown.append(piece)
            line = ("hand %s: board %s; pot %d; winner seat %s"
                    % (hand, " ".join(ev.card_name(c) for c in board), pot,
                       ",".join(str(w) for w in winners)))
            if shown:
                line += "; showdown " + ", ".join(shown)
            line += "; deltas " + dtxt + ("; settle-verified" if verified
                                          else "; settle-MISMATCH")
            history.append(line)
            stacks_final = dict(stacks)
    return {"stacks": stacks_final if stacks_final else stacks,
            "history": history, "errors": errors}


# --------------------------------------------------------------------------
# Level 0 committed-deal audit from a transcript (spec 7.1). Mirrors the xTalk
# heAuditDealsFromLog / heAuditDealLog: re-derive the deck from the REVEALED
# seeds in the transcript and confirm the committed shuffle produced exactly
# the cards that were dealt. Proves the transcript carries everything needed to
# prove the deal was not stacked -- and that a tampered seed is caught.
# --------------------------------------------------------------------------

def build_level0_transcript(tamper=""):
    table = pk.TABLE
    hand = 1
    occ = [1, 2, 3]
    button = 1
    seeds = list(pk.DEAL_SEEDS)
    commits = [pk.seed_commit(s) for s in seeds]
    deck = pk.shuffle_from_stream(pk.stream_bytes(pk.stream_key(table, hand, pk.xor_seeds(seeds)), 16))
    holes, flop, turn, river, _ = pk.assign_deal(deck, occ, button)
    L = []
    L.append((0, "table", "cfg", "sb=1,bb=2,seats=1|2|3,stacks=400|400|400,button=1"))
    L.append((1, "table", "handStart", "seats=1|2|3,button=1"))
    L.append((1, "table", "dealLevel", "level=0,table=%s,count=3" % table.hex()))
    for i, c in enumerate(commits, 1):
        L.append((1, "seat%d" % occ[i - 1], "seedCommit", "pos=%d,commit=%s" % (i, c.hex())))
    revealed = [s.hex() for s in seeds]
    if tamper == "seed":                                  # flip a bit of a revealed seed
        revealed[1] = "%064x" % (int(revealed[1], 16) ^ 1)
    for i, sd in enumerate(revealed, 1):
        L.append((1, "seat%d" % occ[i - 1], "seedReveal", "pos=%d,seed=%s" % (i, sd)))
    for s in occ:
        L.append((1, "table", "holeDeliver",
                  "seat=%d,cards=%s|%s" % (s, pk.card_name(holes[s][0]), pk.card_name(holes[s][1]))))
    L.append((1, "table", "board", "street=flop,cards=%s|%s|%s"
              % tuple(pk.card_name(c) for c in flop)))
    L.append((1, "table", "board", "street=turn,cards=%s" % pk.card_name(turn)))
    L.append((1, "table", "board", "street=river,cards=%s" % pk.card_name(river)))
    L.append((1, "table", "settle", "deltas=1:0|2:0|3:0"))
    return L


def _audit_one_deal(table, hand, seeds, commits, count, occ, button, holes, board):
    for pos in range(1, count + 1):
        if pk.seed_commit(bytes.fromhex(seeds[pos])).hex() != commits[pos]:
            return "fail:commit-mismatch-position-%d" % pos
    xr = pk.xor_seeds([bytes.fromhex(seeds[p]) for p in range(1, count + 1)])
    deck = pk.shuffle_from_stream(pk.stream_bytes(pk.stream_key(table, hand, xr), 16))
    ch_holes, ch_flop, ch_turn, ch_river, _ = pk.assign_deal(deck, occ, button)
    for s in occ:
        if ch_holes[s] != holes[s]:
            return "fail:hole-mismatch-seat-%d" % s
    if len(board) >= 3 and board[0:3] != ch_flop:
        return "fail:flop-mismatch"
    if len(board) >= 4 and board[3] != ch_turn:
        return "fail:turn-mismatch"
    if len(board) >= 5 and board[4] != ch_river:
        return "fail:river-mismatch"
    return "pass"


def audit_deals_from_log(tx):
    seeds, commits, holes, board = {}, {}, {}, []
    table, count, occ, button, hand, level0 = None, 0, [], 0, 0, False
    verified, total, lines = 0, 0, []
    for h, frm, typ, body in tx:
        d = dict(p.split("=", 1) for p in body.split(",")) if body else {}
        if typ == "handStart":
            occ = [int(x) for x in d["seats"].split("|")]
            button = int(d["button"])
            hand = h
            level0, seeds, commits, holes, board = False, {}, {}, {}, []
        elif typ == "dealLevel":
            level0 = True
            table = bytes.fromhex(d["table"])
            count = int(d["count"])
        elif typ == "seedCommit":
            commits[int(d["pos"])] = d["commit"]
        elif typ == "seedReveal":
            seeds[int(d["pos"])] = d["seed"]
        elif typ == "holeDeliver":
            c = d["cards"].split("|")
            holes[int(d["seat"])] = [ev.card_index(c[0]), ev.card_index(c[1])]
        elif typ == "board":
            for c in d["cards"].split("|"):
                board.append(ev.card_index(c))
        elif typ == "settle" and level0:
            total += 1
            v = _audit_one_deal(table, hand, seeds, commits, count, occ, button, holes, board)
            if v == "pass":
                verified += 1
                lines.append("hand %d: deal-verified" % hand)
            else:
                lines.append("hand %d: deal-FAILED %s" % (hand, v))
    return verified, total, lines


def main():
    fails = 0

    def check(label, got, expect):
        nonlocal fails
        if got == expect:
            print("PASS  %s" % label)
        else:
            print("FAIL  %s\n  observed=%r\n  expected=%r" % (label, got, expect))
            fails += 1

    def contains(label, hay, needle):
        nonlocal fails
        if needle in hay:
            print("PASS  %s" % label)
        else:
            print("FAIL  %s\n  observed=%r\n  expected to contain=%r"
                  % (label, hay, needle))
            fails += 1

    clean = independent_fold(transcript())
    st = clean["stacks"]
    check("final stacks 442/394/364",
          "%d/%d/%d" % (st[1], st[2], st[3]), "442/394/364")
    check("no replay errors on the honest transcript", clean["errors"], [])
    contains("history: board/pot/winner", clean["history"][0],
             "hand 1: board 3h 2h 5c 4h Tc; pot 78; winner seat 1")
    contains("history: winning hand named", clean["history"][0], "1=3d 5d two pair")
    contains("history: losing showdown named", clean["history"][0], "3=Kc Kh one pair")
    contains("history: mucked hand annotated (2e)", clean["history"][0],
             "3=Kc Kh one pair (mucked)")
    contains("history: settlement verified", clean["history"][0], "settle-verified")

    tampered = independent_fold(transcript("settle"))
    contains("tampered settle caught", " ".join(tampered["errors"]), "settle-mismatch")
    contains("tampered settle marked MISMATCH", tampered["history"][0], "settle-MISMATCH")

    bad = independent_fold(transcript("badact"))
    contains("illegal action rejected on replay",
             " ".join(bad["errors"]), "engine-rejected")

    # a truncated transcript (missing a board line before a contested settle)
    # is named and skipped, never a crash mid-audit
    tx = transcript()
    ridx = max(i for i, e in enumerate(tx) if e[2] == "board")
    shortres = independent_fold(tx[:ridx] + tx[ridx + 1:])
    contains("truncated board caught (settle-bad-cards)",
             " ".join(shortres["errors"]), "settle-bad-cards")

    # antes: the fold re-derives the pot from the bidAnte lines and verifies it
    anteres = independent_fold(ante_transcript())
    ast = anteres["stacks"]
    check("ante fold: final stacks 398/397/405",
          "%d/%d/%d" % (ast[1], ast[2], ast[3]), "398/397/405")
    check("ante fold: no replay errors (settle re-derived from antes)",
          anteres["errors"], [])
    check("ante fold: chips conserved across the hand",
          ast[1] + ast[2] + ast[3], 1200)
    contains("ante fold: settlement verified", anteres["history"][0], "settle-verified")
    # The awarded pot is 8, not the 9 committed: the BB's blind is uncalled by
    # 1 chip and returned. Pinned because it was wrong here for as long as this
    # session has existed, and only the deltas were ever checked.
    contains("ante fold: the awarded pot is 8, not the 9 committed",
             anteres["history"][0], "pot 8;")

    # UNCALLED-BET POT: the awarded pot excludes a bet nobody called.
    # Regression for the 2026-08-17 hotseat finding - a 392 all-in called by a
    # 2008 stack reported "pot 2400" for a pot of 784. The deltas were correct
    # throughout, so chip conservation and settle-verified both passed while
    # the reported figure was inflated by exactly the returned 1616.
    uncres = independent_fold(uncalled_transcript())
    ust = uncres["stacks"]
    check("uncalled: no replay errors", uncres["errors"], [])
    check("uncalled: final stacks 1616/784", "%d/%d" % (ust[1], ust[2]), "1616/784")
    check("uncalled: chips conserved", ust[1] + ust[2], 2400)
    contains("uncalled: settlement verified", uncres["history"][0], "settle-verified")
    contains("uncalled: the AWARDED pot is 784, not the 2400 committed",
             uncres["history"][0], "pot 784;")
    check("uncalled: and 2400 appears nowhere in the history line",
          "2400" in uncres["history"][0], False)
    contains("uncalled: the short stack wins with kings",
             uncres["history"][0], "2=Kd Kh three of a kind")

    # Level 0 committed-deal audit from the transcript
    v, t, lines = audit_deals_from_log(build_level0_transcript())
    check("deal audit: honest Level 0 deal verifies (1/1)", (v, t), (1, 1))
    contains("deal audit: hand marked deal-verified", " ".join(lines), "deal-verified")
    v2, t2, lines2 = audit_deals_from_log(build_level0_transcript("seed"))
    check("deal audit: tampered seed fails (0/1)", (v2, t2), (0, 1))
    contains("deal audit: tampered seed named commit-mismatch",
             " ".join(lines2), "commit-mismatch")

    print()
    if fails:
        print("FAILED -- %d fold check(s) wrong." % fails)
        return 1
    print("All transcript-fold checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
