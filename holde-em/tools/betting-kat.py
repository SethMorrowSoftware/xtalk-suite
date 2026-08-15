#!/usr/bin/env python3
"""Known-answer cases for the betting engine + settlement (spec 8.1, 8.3).

A faithful Python mirror of the pure xTalk state machine in
``src/holdem.livecodescript`` (heBetNewHand / heBetApply / heSettleOf /
heShowdownOrderOf): same state keys, same error strings, same notes, same
transitions, ported line-for-line so a rules bug shows up in CI instead of on
an OXT pass. The self-test harness runs these exact scenarios on-engine and
must observe these exact outcomes.

The rules pinned here (all classic, all fiddly, spec 8.1):

  * min-raise = size of the largest prior full bet/raise of the street
  * an all-in below the min-raise does NOT reopen betting for players who
    already acted since the last full raise (they may call or fold only)
  * side pots layer by all-in amounts; each layer awarded independently
  * heads-up: the button posts the small blind, acts first pre-flop and
    last post-flop
  * showdown order: last aggressor of the final street first, then clockwise
  * odd chips go to the first winner clockwise from the button

Usage::

    python3 tools/betting-kat.py

Exit status is non-zero on any failure (CI gate).
"""

import sys

FAILS = []


def check(label, observed, expected):
    if observed == expected:
        print("PASS  %-52s %s" % (label, observed))
    else:
        print("FAIL  %-52s observed=%r expected=%r" % (label, observed, expected))
        FAILS.append(label)


# --------------------------------------------------------------------------
# The engine mirror. State keys and semantics match the xTalk exactly;
# booleans are the strings "true"/"false" like xTalk custom-property law.
# --------------------------------------------------------------------------

def new_hand(sb, bb, stacks, occ, button, ante=0):
    st = {
        "sb": sb, "bb": bb, "ante": ante, "occ": list(occ), "buttonSeat": button,
        "street": "preflop", "phase": "blinds", "toAct": 0,
        "betCur": 0, "raiseFull": bb, "aggressor": 0, "sdFirst": 0,
        "err": "", "note": "",
        "stackBy": {s: stacks[s] for s in occ},
        "streetBy": {s: 0 for s in occ},
        "handBy": {s: 0 for s in occ},
        "foldedBy": {s: "false" for s in occ},
        "allinBy": {s: "false" for s in occ},
        "actedBy": {s: "false" for s in occ},
    }
    if len(occ) == 2:
        st["sbSeat"] = button           # heads-up: the button IS the SB
    else:
        st["sbSeat"] = _next_in(occ, button)
    st["bbSeat"] = _next_in(occ, st["sbSeat"])
    return st


def _next_in(lst, entry):
    i = lst.index(entry)
    return lst[(i + 1) % len(lst)]


def _rotate_after(lst, entry):
    i = lst.index(entry)
    return lst[i + 1:] + lst[:i + 1]


def _in_hand(st):
    return [s for s in st["occ"] if st["foldedBy"][s] == "false"]


def _pending(st, s):
    if st["foldedBy"][s] == "true" or st["allinBy"][s] == "true":
        return False
    if st["streetBy"][s] < st["betCur"]:
        return True
    return st["actedBy"][s] == "false"


def _next_pending(st, after):
    for s in _rotate_after(st["occ"], after):
        if _pending(st, s):
            return s
    return 0


def _live_count(st):
    return len([s for s in st["occ"]
                if st["foldedBy"][s] == "false" and st["allinBy"][s] == "false"])


def _pay(st, s, amount):
    st["stackBy"][s] -= amount
    st["streetBy"][s] += amount
    st["handBy"][s] += amount
    if st["stackBy"][s] == 0:
        st["allinBy"][s] = "true"


def _pay_dead(st, s, amount):
    # antes: pot (handBy) only, never the street bet
    st["stackBy"][s] -= amount
    st["handBy"][s] += amount
    if st["stackBy"][s] == 0:
        st["allinBy"][s] = "true"


def _first_in_hand_after(st, after):
    for s in _rotate_after(st["occ"], after):
        if st["foldedBy"][s] == "false":
            return s
    return 0


def _close_street(st):
    if st["aggressor"] > 0:
        st["sdFirst"] = st["aggressor"]
    else:
        st["sdFirst"] = _first_in_hand_after(st, st["buttonSeat"])
    for s in st["occ"]:
        st["streetBy"][s] = 0
        st["actedBy"][s] = "false"
    st["betCur"] = 0
    st["raiseFull"] = st["bb"]
    st["aggressor"] = 0
    if st["street"] == "river":
        st["phase"] = "showdown"
        st["toAct"] = 0
        st["note"] += "showdown\n"
        return st
    if _live_count(st) <= 1:
        st["phase"] = "runout"
        st["toAct"] = 0
        st["note"] += "runout\n"
        return st
    st["street"] = {"preflop": "flop", "flop": "turn", "turn": "river"}[st["street"]]
    st["toAct"] = _next_pending(st, st["buttonSeat"])
    st["phase"] = "acting"
    st["note"] += "advance:%s\n" % st["street"]
    return st


def _after_action(st, s):
    nxt = _next_pending(st, s)
    if nxt == 0:
        return _close_street(st)
    st["toAct"] = nxt
    return st


def apply_msg(state, mtype, seat, amount):
    import copy
    st = copy.deepcopy(state)
    st["err"] = ""
    st["note"] = ""

    if mtype == "bidAnte":
        if st["phase"] != "blinds":
            st["err"] = "bidAnte-out-of-phase"
            return st
        # replay-as-audit hardening (mirrors heBetApply): a seat outside the
        # hand, or a repeated ante, is engine-rejected -- otherwise an edited
        # transcript replays an illegal posting sequence clean
        if seat not in st["occ"]:
            st["err"] = "bidAnte-wrong-seat"
            return st
        if st.get("antePostedBy", {}).get(seat) == "true":
            st["err"] = "bidAnte-duplicate"
            return st
        pay = min(st["ante"], st["stackBy"][seat])
        if amount != pay:
            st["err"] = "bidAnte-wrong-amount"
            return st
        _pay_dead(st, seat, pay)
        st.setdefault("antePostedBy", {})[seat] = "true"
        return st

    if mtype == "bidSB":
        if st["phase"] != "blinds":
            st["err"] = "bidSB-out-of-phase"
            return st
        if seat != st["sbSeat"]:
            st["err"] = "bidSB-wrong-seat"
            return st
        # phase stays "blinds" until the BB posts, so without this flag a
        # transcript with two bidSB lines double-charges the small blind
        if st.get("sbPosted") == "true":
            st["err"] = "bidSB-duplicate"
            return st
        pay = min(st["sb"], st["stackBy"][seat])
        if amount != pay:
            st["err"] = "bidSB-wrong-amount"
            return st
        _pay(st, seat, pay)
        st["sbPosted"] = "true"
        return st

    if mtype == "bidBB":
        if st["phase"] != "blinds":
            st["err"] = "bidBB-out-of-phase"
            return st
        if seat != st["bbSeat"]:
            st["err"] = "bidBB-wrong-seat"
            return st
        pay = min(st["bb"], st["stackBy"][seat])
        if amount != pay:
            st["err"] = "bidBB-wrong-amount"
            return st
        _pay(st, seat, pay)
        st["betCur"] = st["bb"]      # the BB is the opening bet even if short
        st["raiseFull"] = st["bb"]
        st["phase"] = "acting"
        return _after_action(st, seat)

    if mtype == "board":
        if st["phase"] == "runout":
            st["street"] = {"preflop": "flop", "flop": "turn", "turn": "river"}.get(
                st["street"], st["street"])
            if st["street"] == "river":
                st["phase"] = "showdown"
                st["note"] += "showdown\n"
        return st

    if mtype != "act":
        st["err"] = "unknown-message:" + mtype
        return st

    verb, amt = (amount.split(",") + ["0"])[:2]
    # the amount is TEXT on the engine side (UI box / Phase 2 wire): keep it
    # numeric-or-None here so the compares below mirror xTalk's behavior (a
    # non-number simply mismatches; it must not crash the mirror)
    if amt in ("", None):
        amt = 0
    else:
        try:
            amt = float(amt)
        except ValueError:
            amt = None
    if st["phase"] != "acting":
        st["err"] = "act-out-of-phase"
        return st
    if seat != st["toAct"]:
        st["err"] = "act-out-of-turn"
        return st

    if verb == "fold":
        st["foldedBy"][seat] = "true"
        st["actedBy"][seat] = "true"
        if len(_in_hand(st)) == 1:
            st["phase"] = "handdone"
            st["toAct"] = 0
            st["note"] += "foldwin:%d\n" % _in_hand(st)[0]
            return st
        return _after_action(st, seat)

    if verb == "check":
        if st["streetBy"][seat] < st["betCur"]:
            st["err"] = "check-facing-bet"
            return st
        st["actedBy"][seat] = "true"
        return _after_action(st, seat)

    if verb == "call":
        owe = st["betCur"] - st["streetBy"][seat]
        if owe <= 0:
            st["err"] = "call-nothing-to-call"
            return st
        pay = min(owe, st["stackBy"][seat])
        if amt != pay:
            st["err"] = "call-wrong-amount"
            return st
        _pay(st, seat, pay)
        st["actedBy"][seat] = "true"
        return _after_action(st, seat)

    if verb in ("bet", "raise", "allin"):
        if verb == "allin":
            target = st["streetBy"][seat] + st["stackBy"][seat]
            if amt != target:
                st["err"] = "allin-wrong-amount"
                return st
            if target <= st["betCur"]:
                _pay(st, seat, st["stackBy"][seat])
                st["actedBy"][seat] = "true"
                return _after_action(st, seat)
        else:
            # integer-only wagers (mirrors heBetApply's act-bad-amount guard):
            # a fractional target would flow into settle()'s div/mod chip
            # accounting and mint chips at settlement
            if amt is None or amt != int(amt):
                st["err"] = "act-bad-amount"
                return st
            target = int(amt)
            if verb == "bet" and st["betCur"] > 0:
                st["err"] = "bet-facing-bet-use-raise"
                return st
            if verb == "raise" and st["betCur"] == 0:
                st["err"] = "raise-nothing-to-raise-use-bet"
                return st
        if target <= st["betCur"]:
            st["err"] = "raise-not-above-bet"
            return st
        pay = target - st["streetBy"][seat]
        if pay > st["stackBy"][seat]:
            st["err"] = "raise-beyond-stack"
            return st
        is_allin = pay == st["stackBy"][seat]
        increment = target - st["betCur"]
        if increment < st["raiseFull"] and not is_allin:
            st["err"] = "raise-below-minimum"
            return st
        if st["actedBy"][seat] == "true":
            st["err"] = "raise-not-reopened"
            return st
        _pay(st, seat, pay)
        st["betCur"] = target
        st["aggressor"] = seat
        st["actedBy"][seat] = "true"
        if increment >= st["raiseFull"]:
            st["raiseFull"] = increment
            for s in st["occ"]:
                if s != seat:
                    st["actedBy"][s] = "false"
        return _after_action(st, seat)

    st["err"] = "unknown-verb:" + verb
    return st


def showdown_order(st):
    first = st["sdFirst"]
    if first == 0 or st["foldedBy"][first] == "true":
        first = _first_in_hand_after(st, st["buttonSeat"])
    order = [first] + _rotate_after(st["occ"], first)
    out = []
    for s in order:
        if st["foldedBy"][s] == "false" and s not in out:
            out.append(s)
    return out


def settle(st, ranks):
    deltas = {s: -st["handBy"][s] for s in st["occ"]}
    levels = sorted({st["handBy"][s] for s in st["occ"] if st["handBy"][s] > 0})
    prev = 0
    for level in levels:
        layer = sum(max(0, min(st["handBy"][s], level) - prev) for s in st["occ"])
        eligible = [s for s in st["occ"]
                    if st["foldedBy"][s] == "false" and st["handBy"][s] >= level]
        if not eligible:
            for s in st["occ"]:
                c = min(st["handBy"][s], level) - prev
                if c > 0:
                    deltas[s] += c
            prev = level
            continue
        if len(eligible) == 1:
            winners = eligible
        else:
            best = max(ranks[s] for s in eligible)
            winners = [s for s in eligible if ranks[s] == best]
        share, rem = divmod(layer, len(winners))
        for s in winners:
            deltas[s] += share
        for s in _rotate_after(st["occ"], st["buttonSeat"]):
            if rem == 0:
                break
            if s in winners:
                deltas[s] += 1
                rem -= 1
        prev = level
    return deltas


def bet_legal(st, seat):
    """Mirror of heBetLegal: the legal-action menu for `seat`, one entry each of
    "fold" / "check" / "call N" / "bet MIN MAX" / "raise MINTO MAXTO" /
    "allin N". Empty unless it is `seat`'s turn to act. logic-fuzz.py checks that
    what this offers is EXACTLY what apply_msg (the gate) accepts."""
    out = []
    if st["phase"] != "acting" or st["toAct"] != seat:
        return out
    owe = st["betCur"] - st["streetBy"][seat]
    out.append("fold")
    if owe <= 0:
        out.append("check")
    else:
        out.append("call %d" % min(owe, st["stackBy"][seat]))
    max_to = st["streetBy"][seat] + st["stackBy"][seat]
    if st["actedBy"][seat] == "false" and max_to > st["betCur"]:
        min_to = min(st["betCur"] + st["raiseFull"], max_to)
        if st["betCur"] == 0:
            out.append("bet %d %d" % (min_to, max_to))
        else:
            out.append("raise %d %d" % (min_to, max_to))
    if st["actedBy"][seat] == "false" or max_to <= st["betCur"]:
        out.append("allin %d" % max_to)
    return out


def quick_amount(st, seat, kind):
    """Mirror of heQuickAmountOf: the raise-TO the Min / 1/2 Pot / Pot buttons
    put in the amount box, clamped to [minTo, maxTo].

    Pot-limit sizing, the standard definition: the maximum raise is "the pot
    after you call" -- everything already committed plus the amount you must
    first put in to call -- and that is the raise INCREMENT, laid on top of the
    current bet. So raiseTo = betCur + (committed + owe). Adding `owe` a second
    time (as the xTalk did before v0.14.1) counts the call twice, because
    betCur already equals streetBy + owe."""
    owe = st["betCur"] - st["streetBy"][seat]
    pot_after = sum(st["handBy"][s] for s in st["occ"]) + owe
    max_to = st["streetBy"][seat] + st["stackBy"][seat]
    min_to = min(st["betCur"] + st["raiseFull"], max_to)
    if kind == "half":
        to = st["betCur"] + pot_after // 2
    elif kind == "pot":
        to = st["betCur"] + pot_after
    else:
        to = min_to
    return max(min_to, min(to, max_to))


# --------------------------------------------------------------------------
# The pinned scenarios (each one is duplicated on-engine in the harness)
# --------------------------------------------------------------------------

def run_blinds(st):
    st = apply_msg(st, "bidSB", st["sbSeat"], min(st["sb"], st["stackBy"][st["sbSeat"]]))
    assert st["err"] == "", st["err"]
    st = apply_msg(st, "bidBB", st["bbSeat"], min(st["bb"], st["stackBy"][st["bbSeat"]]))
    assert st["err"] == "", st["err"]
    return st


def case_min_raise():
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    check("preflop first to act is left of BB", st["toAct"], 1)
    bad = apply_msg(st, "act", 1, "raise,3")
    check("raise to 3 under min (bb=2) rejected", bad["err"], "raise-below-minimum")
    st = apply_msg(st, "act", 1, "raise,4")
    check("raise to 4 (min) accepted", st["err"], "")
    bad = apply_msg(st, "act", 2, "raise,5")
    check("re-raise to 5 under min rejected", bad["err"], "raise-below-minimum")
    st = apply_msg(st, "act", 2, "raise,6")
    check("re-raise to 6 (last full raise = 2) accepted", st["err"], "")
    check("raiseFull tracks the full raise", st["raiseFull"], 2)


def case_under_raise_no_reopen():
    # flop: seat2 checks, seat3 bets 10 (full), seat1 calls, seat2 goes all-in
    # for 11 (under-raise): action does NOT reopen for seat3 or seat1
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 13, 3: 100}, [1, 2, 3], 1))
    for seat, msg in ((1, "call,2"), (2, "call,1"), (3, "check,0")):
        st = apply_msg(st, "act", seat, msg)
        assert st["err"] == "", st["err"]
    check("flop reached", st["street"], "flop")
    check("flop first to act", st["toAct"], 2)
    st = apply_msg(st, "act", 2, "check,0")
    st = apply_msg(st, "act", 3, "bet,10")
    check("flop bet of 10 accepted", st["err"], "")
    st = apply_msg(st, "act", 1, "call,10")
    st = apply_msg(st, "act", 2, "allin,11")
    check("under-raise all-in accepted", st["err"], "")
    check("betCur moves to 11", st["betCur"], 11)
    check("raiseFull stays 10 after under-raise", st["raiseFull"], 10)
    bad = apply_msg(st, "act", 3, "raise,25")
    check("seat3 already acted: raise rejected", bad["err"], "raise-not-reopened")
    st = apply_msg(st, "act", 3, "call,1")
    bad = apply_msg(st, "act", 1, "raise,25")
    check("seat1 already acted: raise rejected", bad["err"], "raise-not-reopened")
    st = apply_msg(st, "act", 1, "call,1")
    check("street closes to turn", st["street"], "turn")


def case_three_way_side_pots():
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 50, 3: 20}, [1, 2, 3], 1))
    st = apply_msg(st, "act", 1, "allin,100")
    check("open shove accepted", st["err"], "")
    st = apply_msg(st, "act", 2, "allin,50")
    check("short call-allin accepted", st["err"], "")
    st = apply_msg(st, "act", 3, "allin,20")
    check("shorter call-allin accepted", st["err"], "")
    check("hand runs out (no more betting)", st["phase"], "runout")
    for _ in range(3):
        st = apply_msg(st, "board", 0, 0)
    check("board runout reaches showdown", st["phase"], "showdown")
    # seat3 best, seat2 middle, seat1 worst
    deltas = settle(st, {1: "011413120900", 2: "021104140000", 3: "031413120000"})
    check("main pot 60 to seat3, side 60 to seat2, 50 back",
          deltas, {1: -50, 2: 10, 3: 40})


def case_heads_up_order():
    st = new_hand(1, 2, {2: 100, 5: 100}, [2, 5], 2)
    check("heads-up: button posts SB", st["sbSeat"], 2)
    check("heads-up: other seat posts BB", st["bbSeat"], 5)
    st = run_blinds(st)
    check("heads-up: button acts first preflop", st["toAct"], 2)
    st = apply_msg(st, "act", 2, "call,1")
    st = apply_msg(st, "act", 5, "check,0")
    check("heads-up flop", st["street"], "flop")
    check("heads-up: non-button acts first postflop", st["toAct"], 5)


def case_bb_option():
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    st = apply_msg(st, "act", 1, "call,2")
    st = apply_msg(st, "act", 2, "call,1")
    check("action returns to the BB (option)", st["toAct"], 3)
    st = apply_msg(st, "act", 3, "raise,6")
    check("BB may raise its option", st["err"], "")
    check("limpers must respond", st["toAct"], 1)


def case_fold_win_uncalled():
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100}, [1, 2], 1))
    st = apply_msg(st, "act", 1, "raise,6")
    st = apply_msg(st, "act", 2, "fold,0")
    check("fold ends the hand", st["phase"], "handdone")
    deltas = settle(st, {})
    check("uncalled raise returned to the winner", deltas, {1: 2, 2: -2})


def case_split_odd_chip_and_order():
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    for seat, msg in ((1, "call,2"), (2, "call,1"), (3, "check,0")):
        st = apply_msg(st, "act", seat, msg)
    st = apply_msg(st, "act", 2, "bet,9")
    st = apply_msg(st, "act", 3, "call,9")
    st = apply_msg(st, "act", 1, "call,9")
    for seat in (2, 3, 1):
        st = apply_msg(st, "act", seat, "check,0")   # turn
    st = apply_msg(st, "act", 2, "check,0")          # river: 3 bets, others call
    st = apply_msg(st, "act", 3, "bet,2")
    st = apply_msg(st, "act", 1, "call,2")
    st = apply_msg(st, "act", 2, "call,2")
    check("river close reaches showdown", st["phase"], "showdown")
    check("river aggressor shows first", showdown_order(st), [3, 1, 2])
    # seats 1 and 2 split (identical rank), seat 3 worse; pot = 39
    deltas = settle(st, {1: "041400000000", 2: "041400000000", 3: "011413120900"})
    check("odd chip to first winner after the button",
          deltas, {1: 6, 2: 7, 3: -13})


def case_blind_allin_runout():
    st = new_hand(1, 2, {4: 1, 6: 2}, [4, 6], 4)
    st = apply_msg(st, "bidSB", 4, 1)
    check("short SB posts all-in", st["allinBy"][4], "true")
    st = apply_msg(st, "bidBB", 6, 2)
    check("both blinds all-in: instant runout", st["phase"], "runout")


def case_check_around():
    st = run_blinds(new_hand(1, 2, {1: 30, 2: 30, 3: 30}, [1, 2, 3], 1))
    for seat, msg in ((1, "call,2"), (2, "call,1"), (3, "check,0")):
        st = apply_msg(st, "act", seat, msg)
    for seat in (2, 3, 1):
        st = apply_msg(st, "act", seat, "check,0")
    check("checked-around flop advances to turn", st["street"], "turn")
    bad = apply_msg(st, "act", 3, "check,0")
    check("out-of-turn check rejected", bad["err"], "act-out-of-turn")


# --------------------------------------------------------------------------
# Dead-button-aware blind schedule (mirror of heScheduleButton). The BB
# advances to the next live seat each hand, so eliminations never double- or
# skip-charge a blind. SB = prev live before BB; button = prev live before SB
# (heads-up: button IS the SB). Pins the audit's elimination scenarios.
# --------------------------------------------------------------------------

def _next_live_after_pos(live, pos):
    for s in live:
        if s > pos:
            return s
    return live[0]


def _prev_live_before_pos(live, pos):
    prev = live[-1]
    for s in live:
        if s < pos:
            prev = s
    return prev


def schedule_button(live, last_bb):
    if last_bb == 0:
        return live[0]
    bb = _next_live_after_pos(live, last_bb)
    sb = _prev_live_before_pos(live, bb)
    if len(live) == 2:
        return sb
    return _prev_live_before_pos(live, sb)


def case_blind_schedule():
    # button and BB each advance exactly one seat/hand with no busts
    seq = []
    lb = 0
    for _ in range(4):
        btn = schedule_button([1, 2, 3], lb)
        st = new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], btn)
        seq.append((btn, st["sbSeat"], st["bbSeat"]))
        lb = st["bbSeat"]
    check("schedule: 3-handed no-bust button/SB/BB rotation", seq,
          [(1, 2, 3), (2, 3, 1), (3, 1, 2), (1, 2, 3)])

    # seat 1 busts after button=1/BB=3 -> heads-up; seat 3 must NOT post BB twice
    btn = schedule_button([2, 3], 3)
    st = new_hand(1, 2, {2: 100, 3: 100}, [2, 3], btn)
    check("schedule: bust-to-HU no double BB (button/SB/BB)",
          (btn, st["sbSeat"], st["bbSeat"]), (3, 3, 2))

    # seats 2,3 bust after button=1/BB=3 -> BB advances to the next survivor (4)
    btn = schedule_button([1, 4, 5, 6], 3)
    st = new_hand(1, 2, {1: 100, 4: 100, 5: 100, 6: 100}, [1, 4, 5, 6], btn)
    check("schedule: double-bust BB advances to survivor",
          (btn, st["sbSeat"], st["bbSeat"]), (6, 1, 4))


# --------------------------------------------------------------------------
# Antes (dead money) + the tournament blind-level schedule. Mirrors of
# heBetPayDead / the bidAnte case, and heLevelFor. Antes go into the pot but
# NOT the street bet, so a seat still owes the full blind to call; settlement
# treats ante money like any other contribution, so side pots and chip
# conservation just work. Duplicated on-engine in heTestAnteRun/heTestLevelRun.
# --------------------------------------------------------------------------

def post_antes(st):
    for s in st["occ"]:
        st = apply_msg(st, "bidAnte", s, min(st["ante"], st["stackBy"][s]))
        assert st["err"] == "", st["err"]
    return st


def level_for_period(period_idx, levels_txt):
    # the level "sb,bb,ante" for a 1-based period index, clamped to the last level
    levels = levels_txt.split(";")
    if len(levels) < 1:
        return "1,2,0"
    idx = period_idx
    if idx > len(levels):
        idx = len(levels)
    if idx < 1:
        idx = 1
    return levels[idx - 1].replace("/", ",")


def level_for(hand_num, levels_txt, hands_per_level):
    every = hands_per_level if hands_per_level >= 1 else 1
    idx = (hand_num - 1) // every + 1
    return level_for_period(idx, levels_txt)


def case_antes():
    # 3-handed, ante 1 each, blinds 1/2. Antes are dead money: everyone antes,
    # then the SB still owes the full small blind, the BB the full big blind.
    st = new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1, ante=1)
    st = post_antes(st)
    check("ante: all three posted dead money (handBy)",
          [st["handBy"][s] for s in (1, 2, 3)], [1, 1, 1])
    check("ante: dead money not on the street bet",
          [st["streetBy"][s] for s in (1, 2, 3)], [0, 0, 0])
    st = run_blinds(st)
    check("ante: SB seat total = ante + small blind", st["handBy"][2], 2)
    check("ante: BB seat total = ante + big blind", st["handBy"][3], 3)
    check("ante: still owe the full BB to call", st["betCur"] - st["streetBy"][1], 2)
    # everyone folds to the BB: pot = 3 antes + SB + BB = 6; BB nets +3
    st = apply_msg(st, "act", 1, "fold,0")
    st = apply_msg(st, "act", 2, "fold,0")
    check("ante: fold-around ends the hand", st["phase"], "handdone")
    deltas = settle(st, {})
    check("ante: dead money folds into the pot the winner takes",
          deltas, {1: -1, 2: -2, 3: 3})


def case_ante_short_allin():
    # a seat with fewer chips than the ante posts what it has and is all-in
    st = new_hand(1, 2, {1: 100, 2: 100, 3: 1}, [1, 2, 3], 1, ante=5)
    st = post_antes(st)
    check("ante: short seat posts what it has", st["handBy"][3], 1)
    check("ante: short seat is all-in for the ante", st["allinBy"][3], "true")
    check("ante: full-stack seats posted the whole ante", st["handBy"][1], 5)


def case_ante_conservation():
    # antes + an all-in runout must conserve chips exactly (0-sum deltas). Each
    # seat's ante (2) comes out of its 200 first, so the all-in is for 198, not
    # 200 -- a common off-by-ante the engine must get right.
    st = new_hand(5, 10, {1: 200, 2: 200, 3: 200}, [1, 2, 3], 1, ante=2)
    st = post_antes(st)
    st = run_blinds(st)
    st = apply_msg(st, "act", 1, "allin,198")
    st = apply_msg(st, "act", 2, "allin,198")
    st = apply_msg(st, "act", 3, "allin,198")
    check("ante: three-way all-in runs out", st["phase"], "runout")
    for _ in range(3):
        st = apply_msg(st, "board", 0, 0)
    deltas = settle(st, {1: "011413120900", 2: "021104140000", 3: "081400000000"})
    check("ante: settlement is zero-sum (chip conservation)",
          sum(deltas.values()), 0)
    # each seat put in ante(2) + all-in(198) = its whole 200, so the pot is 600
    check("ante: winner scoops the whole 600 pot (all-in, best hand)",
          deltas[3], 400)


def case_levels():
    lv = "1/2/0;2/4/0;3/6/0;5/10/0;10/20/0;15/30/0;25/50/0;50/100/10"
    check("level: hand 1 is level 1", level_for(1, lv, 8), "1,2,0")
    check("level: last hand of level 1", level_for(8, lv, 8), "1,2,0")
    check("level: first hand of level 2", level_for(9, lv, 8), "2,4,0")
    check("level: hand 20 is level 3", level_for(20, lv, 8), "3,6,0")
    check("level: hand 25 is level 4", level_for(25, lv, 8), "5,10,0")
    check("level: top level carries an ante", level_for(57, lv, 8), "50,100,10")
    check("level: clamps at the final level", level_for(9999, lv, 8), "50,100,10")
    check("level: every=1 advances each hand", level_for(3, lv, 1), "3,6,0")
    # the period->level mapping is shared by the hands and timer schedules
    check("level: period 1 is level 1", level_for_period(1, lv), "1,2,0")
    check("level: period 4 is level 4", level_for_period(4, lv), "5,10,0")
    check("level: period clamps at the top", level_for_period(999, lv), "50,100,10")


def case_quick_amounts():
    """Pot / half-pot / min sizing (heQuickAmountOf), including the case the
    v0.14.1 fix was about: facing a bet, where the old formula double-counted
    the call and over-sized every quick raise."""
    # 3-handed 1/2, folded to the button preflop: pot 3, button owes 2.
    # Pot-limit max raise = pot after the call (3+2=5) on top of betCur (2) -> 7.
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    check("quick: pot raise facing the BB is a true pot raise", quick_amount(st, 1, "pot"), 7)
    check("quick: half-pot facing the BB", quick_amount(st, 1, "half"), 4)
    check("quick: min is the min legal raise-to", quick_amount(st, 1, "min"), 4)
    # the chips actually pushed = call + pot-after-call
    check("quick: pot raise pushes owe + potAfterCall", 7 - st["streetBy"][1], 2 + 5)

    # Opening a street with no bet in front: pot-sized BET = the pot. (This case
    # was always right -- owe is 0, so the double-count vanished. It pins that
    # the fix did NOT change it.)
    st2 = apply_msg(st, "act", 1, "call,2")
    st2 = apply_msg(st2, "act", 2, "call,1")
    st2 = apply_msg(st2, "act", 3, "check,0")
    check("quick: flop opened", st2["street"], "flop")
    check("quick: pot-sized opening bet is the pot", quick_amount(st2, st2["toAct"], "pot"), 6)
    check("quick: half-pot opening bet", quick_amount(st2, st2["toAct"], "half"), 3)

    # Clamped by the stack: a short seat's pot raise is capped at all-in.
    st3 = run_blinds(new_hand(1, 2, {1: 5, 2: 100, 3: 100}, [1, 2, 3], 1))
    check("quick: pot raise clamps to all-in on a short stack", quick_amount(st3, 1, "pot"), 5)
    # ...and never below the minimum legal raise-to.
    st4 = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    check("quick: half-pot never under the min raise", quick_amount(st4, 1, "half") >= 4, True)


def case_bad_amounts():
    # act-bad-amount (mirrors heBetApply): wagers are integer-only. A
    # fractional target would mint chips in settle()'s div/mod accounting; a
    # non-number would throw mid-arithmetic on the engine. Duplicated
    # on-engine in heTestLegalRun.
    st = run_blinds(new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1))
    bad = apply_msg(st, "act", 1, "raise,4.5")
    check("bad-amount: fractional raise rejected", bad["err"], "act-bad-amount")
    bad = apply_msg(st, "act", 1, "raise,abc")
    check("bad-amount: non-numeric raise rejected", bad["err"], "act-bad-amount")
    st2 = apply_msg(st, "act", 1, "call,2")
    st2 = apply_msg(st2, "act", 2, "call,1")
    st2 = apply_msg(st2, "act", 3, "check,0")
    bad = apply_msg(st2, "act", st2["toAct"], "bet,2.5")
    check("bad-amount: fractional bet rejected", bad["err"], "act-bad-amount")
    # a whole-valued decimal is trunc-equal on the engine and stays legal
    ok = apply_msg(st, "act", 1, "raise,4.0")
    check("bad-amount: whole-valued decimal accepted", ok["err"], "")


def case_duplicate_posts():
    # replay-as-audit: an edited transcript repeating a blind/ante post, or
    # anteing a seat outside the hand, must be engine-rejected -- phase stays
    # "blinds" until the BB posts, so without the posted flags a double bidSB
    # (or any number of repeated bidAnte lines) replayed clean AND audited
    # clean. Duplicated on-engine in heTestAnteRun.
    st = new_hand(1, 2, {1: 100, 2: 100, 3: 100}, [1, 2, 3], 1, ante=1)
    st = post_antes(st)
    bad = apply_msg(st, "bidAnte", 1, 1)
    check("dup-post: repeated ante rejected", bad["err"], "bidAnte-duplicate")
    bad = apply_msg(st, "bidAnte", 4, 1)
    check("dup-post: ante from a seat outside the hand rejected",
          bad["err"], "bidAnte-wrong-seat")
    st = apply_msg(st, "bidSB", st["sbSeat"], 1)
    check("dup-post: first SB accepted", st["err"], "")
    bad = apply_msg(st, "bidSB", st["sbSeat"], 1)
    check("dup-post: repeated SB rejected", bad["err"], "bidSB-duplicate")


def case_short_sb_ante():
    # mirror of the on-engine P0 regression pin (heTestAnteRun): a blind seat
    # short AFTER its ante posts from the POST-ante stack. Seat 2 = SB, starts
    # 55, ante 10 -> post-ante stack 45, so its all-in small blind is 45; the
    # old pre-ante cap min(50, 55) is exactly what the engine rejects.
    st = new_hand(50, 100, {1: 400, 2: 55, 3: 400}, [1, 2, 3], 1, ante=10)
    st = post_antes(st)
    check("short-sb-ante: SB is short after its ante", st["stackBy"][2], 45)
    ok = apply_msg(st, "bidSB", 2, min(50, st["stackBy"][2]))
    check("short-sb-ante: post-ante cap accepted", ok["err"], "")
    check("short-sb-ante: all-in for ante + short blind", ok["handBy"][2], 55)
    bad = apply_msg(st, "bidSB", 2, min(50, 55))
    check("short-sb-ante: the pre-ante cap is rejected",
          bad["err"], "bidSB-wrong-amount")


def case_level_count():
    # mirror of heLevelCount (pinned on-engine in heTestLevelRun): the default
    # schedule is 8 ";"-separated levels
    lv = "1/2/0;2/4/0;3/6/0;5/10/0;10/20/0;15/30/0;25/50/0;50/100/10"
    check("level: the default schedule counts 8 levels", len(lv.split(";")), 8)


def main():
    case_blind_schedule()
    case_quick_amounts()
    case_min_raise()
    case_under_raise_no_reopen()
    case_three_way_side_pots()
    case_heads_up_order()
    case_bb_option()
    case_fold_win_uncalled()
    case_split_odd_chip_and_order()
    case_blind_allin_runout()
    case_check_around()
    case_antes()
    case_ante_short_allin()
    case_ante_conservation()
    case_levels()
    case_bad_amounts()
    case_duplicate_posts()
    case_short_sb_ante()
    case_level_count()
    print()
    if FAILS:
        print("FAILED -- %d betting case(s) wrong." % len(FAILS))
        return 1
    print("All betting cases passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
