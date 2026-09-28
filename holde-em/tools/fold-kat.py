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

import hashlib
import importlib.util
import pathlib
import re
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


def _stack_max_seats():
    """kHeMaxSeats, READ out of src/holdem.livecodescript rather than copied
    here (a hand-copied number goes stale silently, root CLAUDE.md): the seat
    bound heCanonIdx checks seats against, and (+1, the oracle's position)
    the contributor count's. A parse that stops matching FAILS, never
    defaults."""
    text = (ROOT / "src" / "holdem.livecodescript").read_text(encoding="utf-8")
    m = re.search(r'^constant kHeMaxSeats = (\d+)[ \t]*$', text, re.M)
    if not m:
        raise AssertionError("kHeMaxSeats not found in src/holdem.livecodescript")
    return int(m.group(1))


MAX_SEATS = _stack_max_seats()

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


def transcript_turns(replay=False):
    """The canned session ONLINE-shaped (v0.25.6; mirror of the harness's
    heTKatTurnLog): each act carries the turn= key its sender signed. With
    replay, seat 3's turn-8 check is REPLAYED at the river just ahead of its
    real turn-10 bet -- legal there (it is seat 3's turn), so without the
    turn binding the fold takes it and the real bet then fails out of turn."""
    out, n, replay_row = [], 0, None
    for hand, frm, typ, body in transcript():
        if typ == "act":
            n += 1
            if replay and n == 10:
                out.append(replay_row)
            row = (hand, frm, typ, body + ",turn=%d" % n)
            if n == 8:
                replay_row = row
            out.append(row)
        else:
            out.append((hand, frm, typ, body))
    return out


def transcript_timeouts():
    """A canned ONLINE-shaped heads-up session of HOST TIMEOUTS (v0.25.6,
    2026-09-26; mirror of the harness's heTKatTimeoutLog, holde-em WORK-PLAN
    row 16c): the table refuses a timeout whose check-or-fold prescription or
    bank flag its folded state does not allow (heTimeoutRuleOk), and History
    must skip exactly those. A seat's accepted stand and sit-return ride as
    "stand" / "sit" lines; misses sit a seat out at the cfg's miss=; a
    voluntary act resets them. Each hand turns on one rule (see the
    harness's comment); the honest fold ends 394/406, five settles
    verified."""
    L = []
    def log(hand, frm, typ, body):
        L.append((hand, frm, typ, body))
    t = "timeout=1"
    log(0, "table", "cfg", "sb=1,bb=2,seats=1|2,stacks=400|400,button=1,miss=2")
    log(1, "table", "handStart", "seats=1|2,button=1")
    log(1, "seat1", "bidSB", "amount=1")
    log(1, "seat2", "bidBB", "amount=2")
    log(1, "seat1", "act", "verb=check,amount=0,seat=1,%s,bank=1,turn=1" % t)
    log(1, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=0,turn=1" % t)
    log(1, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=1,turn=1" % t)
    log(1, "table", "settle", "deltas=1:-1|2:1")
    log(2, "table", "handStart", "seats=1|2,button=2")
    log(2, "seat2", "bidSB", "amount=1")
    log(2, "seat1", "bidBB", "amount=2")
    log(2, "seat2", "act", "verb=call,amount=1,turn=1")
    log(2, "seat1", "act", "verb=check,amount=0,turn=2")
    log(2, "seat1", "act", "verb=bet,amount=2,turn=3")
    log(2, "seat2", "act", "verb=raise,amount=6,turn=4")
    log(2, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=1,turn=5" % t)
    log(2, "table", "settle", "deltas=1:-4|2:4")
    log(3, "table", "handStart", "seats=1|2,button=1")
    log(3, "seat1", "bidSB", "amount=1")
    log(3, "seat2", "bidBB", "amount=2")
    log(3, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=1,turn=1" % t)
    log(3, "table", "settle", "deltas=1:-1|2:1")
    log(4, "table", "handStart", "seats=1|2,button=2")
    log(4, "seat2", "bidSB", "amount=1")
    log(4, "seat1", "bidBB", "amount=2")
    log(4, "seat2", "act", "verb=raise,amount=4,turn=1")
    log(4, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=0,turn=2" % t)
    log(4, "table", "settle", "deltas=1:-2|2:2")
    log(4, "seat1", "sit", "seat=1")
    log(4, "seat2", "stand", "seat=2")
    log(5, "table", "handStart", "seats=1|2,button=1")
    log(5, "seat1", "bidSB", "amount=1")
    log(5, "seat2", "bidBB", "amount=2")
    log(5, "seat1", "act", "verb=fold,amount=0,seat=1,%s,bank=0,turn=1" % t)
    log(5, "seat1", "act", "verb=call,amount=1,turn=1")
    log(5, "seat2", "act", "verb=check,amount=0,seat=2,%s,bank=0,turn=2" % t)
    log(5, "seat2", "act", "verb=check,amount=0,seat=2,%s,bank=0,turn=3" % t)
    log(5, "seat1", "act", "verb=bet,amount=2,turn=4")
    log(5, "seat2", "act", "verb=fold,amount=0,seat=2,%s,bank=0,turn=5" % t)
    log(5, "table", "settle", "deltas=1:2|2:-2")
    return L


def transcript_late_join(drop_seat_line=False):
    """A canned ONLINE-shaped session with a LATE JOINER (v0.25.6 fix pass,
    round 2, 2026-09-26; mirror of the harness's heTKatLateJoinLog), as
    heNetLogToHotseat now translates one: the opening cfg gives stacks to the
    first hand's two seats only, and seat 3 -- seated between the hands on a
    stack= the host had re-signed to 250 -- gets a cfg line of its own,
    listing just its seat and stack, ahead of the first handStart that deals
    it. Hand 2 is three-handed (button 2: seat 3 posts the SB, seat 1 the
    BB) and folds to the big blind: 400/401/249, two settles verified.
    drop_seat_line leaves that line out, as History wrote it before: seat 3
    has no stack and its blind is engine-rejected."""
    L = []
    def log(hand, frm, typ, body):
        L.append((hand, frm, typ, body))
    log(0, "table", "cfg", "sb=1,bb=2,ante=0,seats=1|2,stacks=400|400,button=1,miss=2")
    log(1, "table", "handStart", "seats=1|2,button=1")
    log(1, "seat1", "bidSB", "amount=1")
    log(1, "seat2", "bidBB", "amount=2")
    log(1, "seat1", "act", "verb=fold,amount=0,turn=1")
    log(1, "table", "settle", "deltas=1:-1|2:1")
    if not drop_seat_line:
        log(2, "table", "cfg", "seats=3,stacks=250")
    log(2, "table", "handStart", "seats=1|2|3,button=2")
    log(2, "seat3", "bidSB", "amount=1")
    log(2, "seat1", "bidBB", "amount=2")
    log(2, "seat2", "act", "verb=fold,amount=0,turn=1")
    log(2, "seat3", "act", "verb=fold,amount=0,turn=2")
    log(2, "table", "settle", "deltas=1:1|2:0|3:-1")
    return L


def timeout_verb_of(st, seat):
    """heTimeoutVerbOf: check when the seat owes nothing this street."""
    return "fold" if st["betCur"] - st["streetBy"][seat] > 0 else "check"


def timeout_post_of(st):
    """heTimeoutPostOf: the pending forced post, antes first, then SB, BB."""
    if st["phase"] != "blinds":
        return ""
    if st["ante"] > 0:
        for s in st["occ"]:
            if st.get("antePostedBy", {}).get(s) != "true":
                return "bidAnte,%d,%d" % (s, min(st["ante"], st["stackBy"][s]))
    if st.get("sbPosted") != "true":
        return "bidSB,%d,%d" % (st["sbSeat"], min(st["sb"], st["stackBy"][st["sbSeat"]]))
    return "bidBB,%d,%d" % (st["bbSeat"], min(st["bb"], st["stackBy"][st["bbSeat"]]))


def timeout_rule_ok(st, d, seat, kind, amt, bank_used, sit_out):
    """heTimeoutRuleOk: "" when the timeout's prescription and bank flag are
    the ones the folded state allows, else the reason."""
    if kind == "act":
        if d.get("verb") != timeout_verb_of(st, seat) or str(amt) != "0":
            return "wrong prescription (%s)" % d.get("verb")
    elif timeout_post_of(st) != "%s,%d,%s" % (kind, seat, amt):
        return "wrong forced post"
    if d.get("bank") == "1":
        if bank_used or sit_out:
            return "bank already spent"
    elif not bank_used and not sit_out:
        return "bank denied (unspent bank needs bank=1)"
    return ""


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
    # v0.25.6 (row 16c): the online liveness state the timeout replay reads
    sit_out, misses, bank_used, miss_max = set(), {}, set(), 2
    for hand, frm, typ, body in tx:
        d = _kv(body) if body else {}
        if typ == "cfg":
            # a cfg line sets only what it LISTS (v0.25.6 fix pass, round 2,
            # 2026-09-26; mirror of heFoldTranscript): the opening cfg lists
            # everything, and History's translation also writes one listing
            # ONLY a late joiner's seat and stack, which moves no stake, no
            # miss limit and no other seat's stack. (This mirror REPLACED the
            # whole stack table on every cfg until then; the xTalk always
            # set only the listed seats.) ante starts at 0 above, so an
            # opening cfg without ante= still means none.
            if d.get("sb", "") != "":
                sb = int(d["sb"])
            if d.get("bb", "") != "":
                bb = int(d["bb"])
            if d.get("ante", "") != "":
                ante = int(d["ante"])
            if d.get("seats", "") != "":
                seats = [int(x) for x in d["seats"].split("|")]
                stk = [int(x) for x in d["stacks"].split("|")]
                for i, s in enumerate(seats):
                    stacks[s] = stk[i]
            if d.get("miss", "").isdigit():
                miss_max = int(d["miss"])
        elif typ in ("stand", "sit"):
            # an online seat's accepted sit-out / return (the translation
            # emits only what the table accepted): read by the timeout rule
            seat = int(frm[4:])
            if typ == "stand":
                sit_out.add(seat)
            else:
                sit_out.discard(seat)
                misses[seat] = 0
        elif typ == "level":
            sb, bb = int(d["sb"]), int(d["bb"])
            ante = int(d.get("ante", 0))
            # the fix pass's review (2026-09-26): History's translation writes
            # a level line for a cfg the host re-signed mid-game, carrying its
            # miss=, which the table applies at its next timeout (a hotseat
            # level carries none)
            if d.get("miss", "").isdigit():
                miss_max = int(d["miss"])
        elif typ == "handStart":
            occ = [int(x) for x in d["seats"].split("|")]
            btn = int(d["button"])
            # a dealt seat no cfg line gave a stack reads as 0 (the xTalk's
            # empty stack in arithmetic), so its blind is engine-rejected --
            # what History did to a late joiner before round 2
            st = bk.new_hand(sb, bb, {s: stacks.get(s, 0) for s in occ}, occ, btn, ante=ante)
            holes, board = {}, []
            show_choice = {}
            bank_used = set()          # one time-bank per hand per seat
        elif typ == "holeDeliver":
            c = d["cards"].split("|")
            holes[int(d["seat"])] = [ev.card_index(c[0]), ev.card_index(c[1])]
        elif typ == "board":
            for c in d["cards"].split("|"):
                board.append(ev.card_index(c))
            st = bk.apply_msg(st, "board", 0, 0)
        elif typ in ("bidAnte", "bidSB", "bidBB", "act"):
            seat = int(frm[4:])
            # v0.25.6 (holde-em WORK-PLAN coding #13): an ONLINE act names its
            # turn and replays only there (heActTurnOk, mirrored as
            # bk.act_turn_ok) -- a re-sequenced earlier act is skipped, as
            # the table refused it; a hotseat act carries no key
            if typ == "act" and d.get("turn", "") != "" and bk.act_turn_ok(d["turn"], st):
                continue
            # v0.25.6 (row 16c): a HOST TIMEOUT replays the table's
            # transcript-derived checks (timeout_rule_ok) and is skipped when
            # the table refused it; an act timeout folds with amount 0
            timed_out = d.get("timeout") == "1"
            if timed_out:
                amt = "0" if typ == "act" else d["amount"]
                if timeout_rule_ok(st, d, seat, typ, amt, seat in bank_used, seat in sit_out):
                    continue
            if typ == "act":
                st = bk.apply_msg(st, "act", seat,
                                  d["verb"] + "," + ("0" if timed_out else d["amount"]))
            else:
                st = bk.apply_msg(st, typ, seat, int(d["amount"]))
            # a rejected BID is named too, as heFoldTranscript names it (this
            # mirror named only acts until 2026-09-26, when a late joiner's
            # rejected blind was the whole symptom)
            if st["err"]:
                errors.append("engine-rejected:" + st["err"])
                continue
            if timed_out:
                if d.get("bank") == "1":
                    bank_used.add(seat)
                misses[seat] = misses.get(seat, 0) + 1
                if misses[seat] >= miss_max:
                    sit_out.add(seat)
            elif typ == "act":
                misses[seat] = 0     # a voluntary act is presence
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
                # named and skipped, never a crash mid-audit. (heIsCardList's
                # whole-number test is `is an integer` since v0.25.4, exact;
                # card_index returns Python ints, so the range test is the
                # whole mirror of it.)
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
                stacks[s] = stacks.get(s, 0) + deltas[s]
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
    count_txt = "03" if tamper == "count03" else "3"   # a non-canonical count (v0.25.5)
    L.append((1, "table", "dealLevel", "level=0,table=%s,count=%s" % (table.hex(), count_txt)))
    for i, c in enumerate(commits, 1):
        L.append((1, "seat%d" % occ[i - 1], "seedCommit", "pos=%d,commit=%s" % (i, c.hex())))
    if tamper == "alias":
        # an ALIAS of position 1 after the canonical commit: dropped by the
        # canonical keying, so the real commit stands (v0.25.5)
        L.append((1, "seat1", "seedCommit", "pos=01,commit=%s" % ("ab" * 32)))
    revealed = [s.hex() for s in seeds]
    if tamper == "seed":                                  # flip a bit of a revealed seed
        revealed[1] = "%064x" % (int(revealed[1], 16) ^ 1)
    if tamper == "nothex":                                # a hand-edited, non-hex seed
        revealed[1] = "nothex"
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


def canon_idx(txt, max_=None):
    """heCanonIdx's mirror (v0.25.5, 2026-09-25): the canonical text of a
    positive whole number read off a wire, or "" when txt is not one. A
    non-empty run of ASCII digits, no leading zero, at most 14 of them, and
    at most max_ when given -- tested as TEXT, before anything reads it as a
    number, because the engine reads "03", "3.0", "+3", " 3" and "3e0" all
    as the number 3 while an array key keeps the raw text (the position-
    alias attack, holde-em WORK-PLAN coding #11)."""
    txt = "" if txt is None else str(txt)
    if not 1 <= len(txt) <= 14:
        return ""
    if any(c not in "0123456789" for c in txt):
        return ""
    if txt[0] == "0":
        return ""
    if max_ is not None and str(max_) != "":
        # `pMax is not a number` refuses outright; a numeric pMax in any
        # spelling ("03") bounds as its value, as the engine reads it
        try:
            bound = float(str(max_).strip())
        except ValueError:
            return ""
        if int(txt) > bound:
            return ""
    return txt


def _is_hex(txt, n):
    """heIsHex's mirror: even-length hex, exactly n chars when n > 0."""
    txt = "" if txt is None else str(txt)
    if not txt or len(txt) % 2 or (n and len(txt) != n):
        return False
    return all(c in "0123456789abcdefABCDEF" for c in txt)


def _audit_one_deal(table, hand, seeds, commits, count, occ, button, holes, board):
    # heAuditDealLog's guards (v0.25.5, 2026-09-25, coding #12): a hand-edited
    # transcript names what is malformed -- the count, the table id, a seed --
    # instead of throwing out of the History audit
    if canon_idx(count, MAX_SEATS + 1) == "":
        return "fail:count-malformed"
    if not _is_hex(table, 64):
        return "fail:table-malformed"
    table = bytes.fromhex(table)
    count = int(count)
    for pos in range(1, count + 1):
        if not _is_hex(seeds.get(pos), 64):
            return "fail:seed-malformed-position-%d" % pos
        # heAuditDealLog compares through heHexEq since v0.25.4 (2026-09-25):
        # a letter prefix and both sides lowercased, so TEXT, case-blind and
        # never numbers (the suite's engine note 2.11). Lowercasing the
        # transcript's side here is that rule, as protocol-kat's twins do.
        if pk.seed_commit(bytes.fromhex(seeds[pos])).hex() != commits.get(pos, "").lower():
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
    # table and count start EMPTY, as the xTalk's locals do: an empty bound is
    # no bound (heCanonIdx), and an empty count is named count-malformed
    table, count, occ, button, hand, level0 = "", "", [], 0, 0, False
    verified, total, lines = 0, 0, []
    for h, frm, typ, body in tx:
        d = dict(p.split("=", 1) for p in body.split(",")) if body else {}
        if typ == "handStart":
            occ = [int(x) for x in d["seats"].split("|")]
            button = int(d["button"])
            hand = h
            level0, seeds, commits, holes, board = False, {}, {}, {}, []
        elif typ == "dealLevel":
            # kept as TEXT, as heAuditDealsFromLog keeps them: the audit names
            # a malformed table id or count (v0.25.5) instead of raising here
            level0 = True
            table = d.get("table", "")
            count = d.get("count", "")
        # positions and seats key by their CANONICAL text (heCanonIdx's
        # mirror, v0.25.5): an alias line ("pos=03") is dropped, last
        # canonical line wins, exactly as heAuditDealsFromLog stores them
        elif typ == "seedCommit":
            p = canon_idx(d.get("pos"), count)
            if p:
                commits[int(p)] = d["commit"]
        elif typ == "seedReveal":
            p = canon_idx(d.get("pos"), count)
            if p:
                seeds[int(p)] = d["seed"]
        elif typ == "holeDeliver":
            c = d["cards"].split("|")
            s = canon_idx(d.get("seat"), MAX_SEATS)
            if s:
                holes[int(s)] = [ev.card_index(c[0]), ev.card_index(c[1])]
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


# --------------------------------------------------------------------------
# AN ENGINE-RECORDED SESSION. Every transcript above is canned: written here
# or built by the mirrors, so it can only show that the fold and the mirrors
# agree with each other. This one is the ENGINE's: a six-seat hotseat session
# the maintainer played on the standalone stack and pasted back on the evening
# of the 2026-09-26 Windows pass ("here's a sample hold-em game in the gotseat
# transcript"). Windows, by the maintainer's account (the next message, which
# also carried that stack's heRunSelftest at v0.25.6 / harness 48, 929/0/5);
# that the hands were dealt by that same build is presumable, not stated.
# Four hands, sb 1 / bb 2, 400 each, the Level 0 deal: seat 5 wins all 2400,
# with the dead button twice (hands 2 and 4) and a three-way all-in with a side
# pot and an uncalled remainder (hand 4).
#
# What it pins that nothing canned can: the engine's sxHash (SodiumXT) deal,
# betting engine and settlement agreeing with these mirrors on a session a
# person played. A mirror or rule change that would have dealt, scheduled,
# accepted or settled that session differently now fails here. Its limit:
# hand 4's winner holds the best hand in every layer, so this session cannot
# tell a layered settlement from a winner-takes-all one (a mirror broken that
# way passes here); betting-kat's three-way side-pot case is what pins the
# layers. The uncalled 386 IS pinned here (the awarded pot 2014, not 2400).
#
# Held VERBATIM: the paste's tab separators are written as single spaces (no
# field contains one) and RECORDED_HOTSEAT_SHA256 is the SHA-256 of the
# original tab-separated text, so an edit to the copy fails before anything
# folds it.
# --------------------------------------------------------------------------

RECORDED_HOTSEAT_SHA256 = "84800841f6b14edc180e1f4739849a6ab2d5078f0c5702c3145c5c13c385902b"

RECORDED_HOTSEAT = """\
0 table cfg sb=1,bb=2,ante=0,seats=1|2|3|4|5|6,stacks=400|400|400|400|400|400,button=1,levelMode=off,speed=normal
1 table handStart seats=1|2|3|4|5|6,button=1
1 table dealLevel level=0,table=a3562279f122d2e581339c02dc495b7d0b20dc95f7cca6315614d0b451d03e1a,count=6
1 seat1 seedCommit pos=1,commit=b8b34463a76e71af3540281f38af64846eddbd301ede8853f49d226a606bbb5d
1 seat2 seedCommit pos=2,commit=1959fc4fc29b2ae1e1f81df609baeda0cb6a3d484982bc08843807826e50e56f
1 seat3 seedCommit pos=3,commit=e362040e9c520036f7f086172e077f0e9f24ffb673f86d840717f2e56dcd5322
1 seat4 seedCommit pos=4,commit=cb0e24b5e2ae497e19840c72267db0a453619c614e2c1b1daa3155dc727eed2c
1 seat5 seedCommit pos=5,commit=5dcc36e7b441e5323b414914c0794a56c5510d587e58013cfb6308d08bd7688b
1 seat6 seedCommit pos=6,commit=625008c32d8f14087378bc6806718bd518e3dccbbff34813e6c59a69f6af84bb
1 seat1 seedReveal pos=1,seed=487c1a4d3f2f65041eee2a911b0065d49d791b3f6469c80c2bfb92e78ea59c1e
1 seat2 seedReveal pos=2,seed=ef87b4db771e80b64303641bdcdf609d2ee48faf13152f55ce439aa44aa08092
1 seat3 seedReveal pos=3,seed=10d5b6dded63322b012c66751ca1bba765b60a694c9ab977059b728b9de19792
1 seat4 seedReveal pos=4,seed=1fe068242d85c3f0de2e83528403b82cc64a810ac6b8029d3f33eecac1f83eee
1 seat5 seedReveal pos=5,seed=15c8810b6300e5d92c6ab8a1cf28de7c2630b0f7e0113d2337c5a7476ddd6ef8
1 seat6 seedReveal pos=6,seed=19e2a876c6d6a86223cd855b6509d3eca3beb25d6d565d1f9bd40d3ce344ef89
1 table holeDeliver seat=1,cards=6h|Kh
1 table holeDeliver seat=2,cards=3d|2h
1 table holeDeliver seat=3,cards=Qc|Qh
1 table holeDeliver seat=4,cards=8h|9s
1 table holeDeliver seat=5,cards=7d|3s
1 table holeDeliver seat=6,cards=Qs|8c
1 seat2 bidSB amount=1
1 seat3 bidBB amount=2
1 seat4 act verb=call,amount=2
1 seat5 act verb=call,amount=2
1 seat6 act verb=call,amount=2
1 seat1 act verb=raise,amount=4
1 seat2 act verb=allin,amount=400
1 seat3 act verb=call,amount=398
1 seat4 act verb=fold,amount=0
1 seat5 act verb=fold,amount=0
1 seat6 act verb=fold,amount=0
1 seat1 act verb=fold,amount=0
1 table board street=flop,cards=Ah|Jc|2d
1 table board street=turn,cards=6c
1 table board street=river,cards=Kd
1 table settle deltas=1:-4|2:-400|3:410|4:-2|5:-2|6:-2
2 table handStart seats=1|3|4|5|6,button=1
2 table dealLevel level=0,table=a3562279f122d2e581339c02dc495b7d0b20dc95f7cca6315614d0b451d03e1a,count=5
2 seat1 seedCommit pos=1,commit=6ef2fc848b34505eb69a616d51edce489cd0fb0e99f79bd7078e623cc5a4db58
2 seat3 seedCommit pos=2,commit=4f8306fd5942433a1ec152248ee586baed668d9d62284194365932cd1dacd716
2 seat4 seedCommit pos=3,commit=5edb07e600651e81b8478bdb1b0ebe8a8a7c4483e6a2b67326fc236bdc2348ee
2 seat5 seedCommit pos=4,commit=e910c1fc1dd949fc4bbc82d39afe522e91cc797d7e389ca514eae7ac9c477022
2 seat6 seedCommit pos=5,commit=337b67dda69764ec6cf23cf255d1f7328b077daa2ac7187d6904aee97327a65e
2 seat1 seedReveal pos=1,seed=5b131bc4466e2c9fa8fcce68e679e090d30447a8dd03aaea717ed2eae38de246
2 seat3 seedReveal pos=2,seed=e4885b8f46a66c6d5595df60e85f6281844a92ce0d4cfb1378b2e37e985b53df
2 seat4 seedReveal pos=3,seed=a867b9b1cc1c90247a864fb949bf74eaf9e32f25963e817790bccb9213ce71dc
2 seat5 seedReveal pos=4,seed=543dd8b6803827ca43d245282a564fad2c81aec6e08c039f102fc68aafd09bc7
2 seat6 seedReveal pos=5,seed=8d8f36e60689ec6e3767eca6ffeeb05c64c923527f704efcbfd8020b3b68b8e2
2 table holeDeliver seat=1,cards=7c|Jc
2 table holeDeliver seat=3,cards=Jh|3d
2 table holeDeliver seat=4,cards=Ts|Qs
2 table holeDeliver seat=5,cards=4c|5c
2 table holeDeliver seat=6,cards=Ac|3c
2 seat3 bidSB amount=1
2 seat4 bidBB amount=2
2 seat5 act verb=raise,amount=4
2 seat6 act verb=call,amount=4
2 seat1 act verb=fold,amount=0
2 seat3 act verb=fold,amount=0
2 seat4 act verb=call,amount=2
2 table board street=flop,cards=8c|Ah|7h
2 seat4 act verb=bet,amount=2
2 seat5 act verb=call,amount=2
2 seat6 act verb=raise,amount=4
2 seat4 act verb=call,amount=2
2 seat5 act verb=call,amount=2
2 table board street=turn,cards=Tc
2 seat4 act verb=bet,amount=2
2 seat5 act verb=raise,amount=4
2 seat6 act verb=allin,amount=390
2 seat4 act verb=fold,amount=0
2 seat5 act verb=call,amount=386
2 table board street=river,cards=6d
2 table settle deltas=1:0|3:-1|4:-10|5:409|6:-398
3 table handStart seats=1|3|4|5,button=3
3 table dealLevel level=0,table=a3562279f122d2e581339c02dc495b7d0b20dc95f7cca6315614d0b451d03e1a,count=4
3 seat1 seedCommit pos=1,commit=f46143ed00802111eff3efeeb4f804e7a76833abd57fe5e0e103c1297f36004c
3 seat3 seedCommit pos=2,commit=50370e6461cb1086c136c5af1979542fd3a9509a474aecc533bc8b43a3727c25
3 seat4 seedCommit pos=3,commit=7cc40eb35919c03971607cace8a3d1c5c78c9eaa3f440bc2683b33d90bd87028
3 seat5 seedCommit pos=4,commit=1372e33b8e98ae11f1daec6a5172f5bfcaa06566b1727893030175bba7a4bae4
3 seat1 seedReveal pos=1,seed=f11fec8c7be69ea277e04e841ba4ed7a897ea0abc562b22f86c38566cdf47528
3 seat3 seedReveal pos=2,seed=0fbe9ecece819269fd8217ffd190e2cb323e6d62020fef2ba240b7e524c93bb5
3 seat4 seedReveal pos=3,seed=f925ed9106468a303a1de8edec9b78f62477ce01263865c9b7febebe66fb4c5c
3 seat5 seedReveal pos=4,seed=bb2f9c068b208338c2303fd157fb2fa32a456e175dfd9f9e9aeb75081f3d5a37
3 table holeDeliver seat=1,cards=2c|3d
3 table holeDeliver seat=3,cards=Jh|5c
3 table holeDeliver seat=4,cards=3h|Jc
3 table holeDeliver seat=5,cards=8d|8c
3 seat4 bidSB amount=1
3 seat5 bidBB amount=2
3 seat1 act verb=fold,amount=0
3 seat3 act verb=fold,amount=0
3 seat4 act verb=call,amount=1
3 seat5 act verb=check,amount=0
3 table board street=flop,cards=Tc|9h|8s
3 seat4 act verb=allin,amount=386
3 seat5 act verb=call,amount=386
3 table board street=turn,cards=5h
3 table board street=river,cards=2d
3 table settle deltas=1:0|3:0|4:-388|5:388
4 table handStart seats=1|3|5,button=3
4 table dealLevel level=0,table=a3562279f122d2e581339c02dc495b7d0b20dc95f7cca6315614d0b451d03e1a,count=3
4 seat1 seedCommit pos=1,commit=07d62765b461f90e801c71a1768ac5dc28cfc715795e02f4d03b0a88e3617281
4 seat3 seedCommit pos=2,commit=c5915eea426549f7476f33ea66beb4e5c6b6ae582f0c7566bfeda20bf75b3632
4 seat5 seedCommit pos=3,commit=ab2812a3dd7e59b544dd3997b9fc1374acf3b05f9dc00f01199210589266ce40
4 seat1 seedReveal pos=1,seed=a67ee8aced0e492b1fe9c6ae07682c8bf64ebb5e56ed9290bc656e202fd6bdb8
4 seat3 seedReveal pos=2,seed=8bf390db8f188f0be5e3064eaada462769f36a119de089bd71581dcd1b4398ac
4 seat5 seedReveal pos=3,seed=5389fdd2ed223dd88533170624a2b15fbb61eecceb50ae02b0648f099a365ae5
4 table holeDeliver seat=1,cards=6c|Td
4 table holeDeliver seat=3,cards=6s|3c
4 table holeDeliver seat=5,cards=9h|2c
4 seat5 bidSB amount=1
4 seat1 bidBB amount=2
4 seat3 act verb=allin,amount=809
4 seat5 act verb=raise,amount=1195
4 seat1 act verb=call,amount=394
4 table board street=flop,cards=8s|Ac|7h
4 table board street=turn,cards=5s
4 table board street=river,cards=2s
4 table settle deltas=1:-396|3:-809|5:1205
"""


def recorded_hotseat_text():
    """The maintainer's paste as it was pasted: tab-separated, one line each,
    a final newline."""
    return "".join("\t".join(line.split(" ", 3)) + "\n"
                   for line in RECORDED_HOTSEAT.strip("\n").split("\n"))


def recorded_hotseat(edit=None):
    """The recorded session as fold tuples; `edit` (a function of one tuple,
    returning a tuple) plants a tamper for the negative checks."""
    tx = []
    for line in recorded_hotseat_text().splitlines():
        h, frm, typ, body = line.split("\t")
        e = (int(h), frm, typ, body)
        tx.append(edit(e) if edit else e)
    return tx


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

    # v0.25.6: turn-bound online acts fold as the hotseat session does, and
    # an act re-sequenced at a later turn is skipped (the harness's section
    # 8 pins, heTKatTurnLog)
    tb = independent_fold(transcript_turns())
    check("turns: acts carrying their turns fold to 442/394/364, no errors",
          ("%d/%d/%d" % (tb["stacks"][1], tb["stacks"][2], tb["stacks"][3]), tb["errors"]),
          ("442/394/364", []))
    rp = independent_fold(transcript_turns(replay=True))
    check("turns: an act replayed at a later turn is skipped, not folded",
          ("%d/%d/%d" % (rp["stacks"][1], rp["stacks"][2], rp["stacks"][3]), rp["errors"]),
          ("442/394/364", []))
    contains("turns: ...and the hand still settles verified", rp["history"][0],
             "settle-verified")

    # v0.25.6 (row 16c): host timeouts replay the table's transcript-derived
    # checks -- prescription, bank, sit-out from stands and misses, returns,
    # the miss reset -- and skip what the table refused (the harness's
    # section 8 pins, heTKatTimeoutLog)
    to = independent_fold(transcript_timeouts())
    check("timeouts: replayed as the table took them (394/406, no errors)",
          ("%d/%d" % (to["stacks"][1], to["stacks"][2]), to["errors"]), ("394/406", []))
    check("timeouts: all five settles verify",
          sum(1 for h in to["history"] if h.endswith("; settle-verified")), 5)
    # ...and each rule is load-bearing: folding every timeout the table
    # refused (no rule) breaks the replay, which is what History did before
    tx = [(h, f, t, b) for (h, f, t, b) in transcript_timeouts()]
    naive = independent_fold([(h, f, t, b.replace("timeout=1", "timeout=0"))
                              for (h, f, t, b) in tx])
    check("timeouts: without the rule the same transcript does NOT replay clean",
          naive["errors"] != [] or sum(1 for h in naive["history"]
                                       if h.endswith("; settle-verified")) < 5, True)

    # v0.25.6 fix pass, round 2 (2026-09-26): a LATE JOINER's own cfg line
    # (its seat and the stack its sit gave it) seats it in the fold, and a
    # cfg line sets only what it lists, so the stakes stay 1/2 (the
    # harness's section 8 pins, heTKatLateJoinLog). Without the line --
    # History before round 2 -- the joiner's blind is engine-rejected.
    lj = independent_fold(transcript_late_join())
    # (.get: a fold that lost the joiner's seat must read as a FAIL, not a KeyError)
    check("latejoin: its own cfg line seats it and moves no stake (400/401/249, no errors)",
          ("/".join(str(lj["stacks"].get(s)) for s in (1, 2, 3)), lj["errors"]),
          ("400/401/249", []))
    check("latejoin: both settles verify",
          sum(1 for h in lj["history"] if h.endswith("; settle-verified")), 2)
    ljd = independent_fold(transcript_late_join(drop_seat_line=True))
    check("latejoin: without the line the joiner's blind is engine-rejected (1 settle verified)",
          (any(e.startswith("engine-rejected") for e in ljd["errors"]),
           sum(1 for h in ljd["history"] if h.endswith("; settle-verified"))), (True, 1))
    # ...and the line must not move the stakes: a cfg case that re-read sb
    # and bb from every line (what "sets only what it lists" forbids) would
    # fold the joiner's hand on no blinds at all
    ljs = independent_fold([(h, f, t, b if t != "cfg" or h == 0 else
                             "sb=0,bb=0,ante=0," + b) for (h, f, t, b) in transcript_late_join()])
    check("latejoin: a seat line that DID move the stakes breaks the replay",
          ljs["errors"] != [] or sum(1 for h in ljs["history"]
                                     if h.endswith("; settle-verified")) < 2, True)

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

    # THE ENGINE-RECORDED SESSION (see RECORDED_HOTSEAT): what the engine
    # dealt, accepted and settled, held against the mirrors.
    check("recorded: the embedded copy is the maintainer's paste byte for byte",
          hashlib.sha256(recorded_hotseat_text().encode("ascii")).hexdigest(),
          RECORDED_HOTSEAT_SHA256)
    rec = independent_fold(recorded_hotseat())
    check("recorded: the session folds with no replay errors", rec["errors"], [])
    check("recorded: seat 5 ends with all 2400 chips",
          {s: v for s, v in rec["stacks"].items() if v}, {5: 2400})
    check("recorded: all four settle lines verify",
          sum(1 for h in rec["history"] if h.endswith("; settle-verified")), 4)
    for n, (pot, win) in enumerate(((810, 3), (807, 5), (776, 5), (2014, 5)), 1):
        contains("recorded: hand %d's awarded pot and winner" % n,
                 rec["history"][n - 1] if len(rec["history"]) >= n else "",
                 "pot %d; winner seat %d;" % (pot, win))
    # hand 4: seat 3 all-in 809, seat 5 all-in 1195, seat 1 all-in 394 on its
    # BB: a side pot, and seat 5's uncalled 386 comes back (pot 2014, not 2400)
    contains("recorded: hand 4 is a three-way showdown over a side pot",
             rec["history"][3] if len(rec["history"]) >= 4 else "",
             "showdown 1=6c Td high card, 3=6s 3c high card, 5=9h 2c one pair")
    v, t, lines = audit_deals_from_log(recorded_hotseat())
    check("recorded: every deal re-derives from its revealed seeds (4/4)", (v, t), (4, 4))
    # the dead button (spec 8.1): the engine's buttons, hand by hand, against
    # the mirror's schedule over the seats still funded -- seat 1 keeps the
    # button after seat 2 busts, seat 3 after seat 4 does
    seen, want, last_bb, funded = [], [], 0, {}
    for h, frm, typ, body in recorded_hotseat():
        d = _kv(body)
        if typ == "cfg":
            funded = dict(zip((int(x) for x in d["seats"].split("|")),
                              (int(x) for x in d["stacks"].split("|"))))
        elif typ == "handStart":
            occ = [int(x) for x in d["seats"].split("|")]
            want.append(bk.schedule_button([s for s in sorted(funded) if funded[s] > 0], last_bb))
            seen.append(int(d["button"]))
            last_bb = bk.new_hand(1, 2, funded, occ, int(d["button"]))["bbSeat"]
        elif typ == "settle":
            for part in d["deltas"].split("|"):
                s, dv = part.split(":")
                funded[int(s)] += int(dv)
    check("recorded: the engine's buttons are the dead-button schedule's",
          (seen, want), ([1, 1, 3, 3], [1, 1, 3, 3]))

    # ...and the recorded session is not a blind spot: each planted tamper
    # is caught by the check that owns it
    def _swap(hand, typ, old, new):
        def edit(e):
            if e[0] == hand and e[2] == typ and old in e[3]:
                return (e[0], e[1], e[2], e[3].replace(old, new, 1))
            return e
        return edit
    ts = independent_fold(recorded_hotseat(_swap(3, "settle", "4:-388|5:388", "4:-387|5:387")))
    contains("recorded tamper: a moved chip in hand 3's settle is caught",
             " ".join(ts["errors"]), "settle-mismatch")
    ta = independent_fold(recorded_hotseat(_swap(4, "act", "verb=call,amount=394", "verb=call,amount=395")))
    contains("recorded tamper: a wrong call amount in hand 4 is engine-rejected",
             " ".join(ta["errors"]), "engine-rejected")
    v, t, lines = audit_deals_from_log(recorded_hotseat(
        _swap(2, "seedReveal", "seed=a867b9b1", "seed=a867b9b0")))
    check("recorded tamper: a revealed seed off by one bit fails hand 2's audit (3/4)",
          (v, t, [l for l in lines if "FAILED" in l]),
          (3, 4, ["hand 2: deal-FAILED fail:commit-mismatch-position-3"]))
    v, t, lines = audit_deals_from_log(recorded_hotseat(
        _swap(1, "holeDeliver", "seat=3,cards=Qc|Qh", "seat=3,cards=Qc|Qd")))
    check("recorded tamper: a substituted hole card fails hand 1's audit (3/4)",
          (v, t, [l for l in lines if "FAILED" in l]),
          (3, 4, ["hand 1: deal-FAILED fail:hole-mismatch-seat-3"]))

    # v0.25.5 (2026-09-25): wire indices are CANONICAL text -- heCanonIdx,
    # mirrored as canon_idx over the same vectors the harness pins (section
    # 21) -- and a hand-edited transcript NAMES what is malformed instead of
    # throwing (holde-em WORK-PLAN coding #11 and #12)
    check("canon: every alias of 3 is refused",
          [canon_idx(a, 9) for a in ("03", "3.0", "+3", " 3", "3e0", "3 ")],
          [""] * 6)
    check("canon: zero, a sign, empty text and a value past the max are refused",
          [canon_idx("0", 9), canon_idx("-3", 9), canon_idx("", 9), canon_idx("10", 9)],
          [""] * 4)
    check("canon: a canonical index is kept, bounded or not",
          [canon_idx("3", 9), canon_idx("9", 9), canon_idx("12")], ["3", "9", "12"])
    check("canon: 14 digits at most (below where the engine blurs integers)",
          [canon_idx("9" * 14), canon_idx("1" + "0" * 14)], ["9" * 14, ""])
    v3, t3, lines3 = audit_deals_from_log(build_level0_transcript("alias"))
    check("deal audit: an alias commit line is dropped; the canonical one stands (1/1)",
          (v3, t3), (1, 1))
    v4, t4, lines4 = audit_deals_from_log(build_level0_transcript("nothex"))
    contains("deal audit: a non-hex seed is NAMED, not raised",
             " ".join(lines4), "deal-FAILED fail:seed-malformed-position-2")
    v5, t5, lines5 = audit_deals_from_log(build_level0_transcript("count03"))
    contains("deal audit: a non-canonical contributor count is named",
             " ".join(lines5), "deal-FAILED fail:count-malformed")

    print()
    if fails:
        print("FAILED -- %d fold check(s) wrong." % fails)
        return 1
    print("All transcript-fold checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
