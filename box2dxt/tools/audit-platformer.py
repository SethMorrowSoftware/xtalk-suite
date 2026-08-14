#!/usr/bin/env python3
"""Geometric layout audit for the platformer demo.

Static, OXT-free sanity pass over examples/box2dxt-platformer.livecodescript:
parses each level's Scene+Cast builders and cross-checks placements that the
script-layer checker (smart quotes / handler balance) cannot see -- buried or
out-of-bounds coins, enemies that patrol off a ground edge into a pit, walkers
sharing a path (gotcha 18), and flag/checkpoint grounding. Findings are advisory
(some "beats" intentionally sit a coin in an enemy's path); read each with the
level's intent in mind. Not a CI gate -- a spotlight for the polish pass.
"""
import re, sys, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "examples" / "box2dxt-platformer.livecodescript"
text = SRC.read_text().splitlines()

# ---- carve the per-level builder regions (Scene start .. next Scene/the harvest) ----
marks = {}
for i, ln in enumerate(text):
    m = re.match(r"\s*command (pfL(\d)(Scene|Cast))\b", ln)
    if m:
        marks.setdefault(int(m.group(2)), [None, None])
        marks[int(m.group(2))][0 if m.group(3) == "Scene" else 1] = i

# find where the last cast ends (the pfGainCoin marker after L5Cast)
end_all = next(i for i, ln in enumerate(text) if re.match(r"\s*command pfGainCoin\b", ln))

def region(level):
    s = marks[level][0]
    # region runs to the next level's Scene, or to pfGainCoin for L5
    nxt = marks.get(level + 1, [end_all])[0] or end_all
    return text[s:nxt]

NUM = r"(-?\d+(?:\.\d+)?)"
def nums(line):
    # strip trailing comment + quoted names/kinds (a slab name like "pf_ground1"
    # or a colour "150,140,150" carries digits we must NOT read as coordinates)
    line = line.split("--", 1)[0]
    line = re.sub(r'"[^"]*"', " ", line)
    return [float(x) for x in re.findall(NUM, line)]

class Level:
    def __init__(self, n):
        self.n = n
        self.slabs = []      # (name,L,T,R,B) solid walkable rects
        self.clouds = []     # (L,R,y) one-way platform solid spans
        self.spikes = []     # (L,R)
        self.lava = []       # (L,R)
        self.water = []      # (L,T,R,B) swim basins -- coins inside are underwater pickups
        self.coins = []      # (x,y)
        self.gems = []       # (x,y) bonus pickups
        self.stars = []      # (x,y) the hidden star (one per level, a distinct collectible)
        self.enemies = []    # (kind,idx,x,minx,maxx,topy,halfw)
        self.thwomps = []    # (idx,x)
        self.barnacles = []  # (idx,x,y)
        self.spiders = []    # (idx,x,minx,maxx,hangy)
        self.decor = []      # (frame,cx,cy) scenery tiles
        self.checkpoint = None
        self.goal = None
        self.bridge = None
        self.conveyors = []  # (pL,pR,dir)
        self.edgeL = 64
        self.edgeR = None
        self.vertical = False  # a VERTICAL climbing level (pfBoundsV): the y=576 ground model doesn't apply

def parse():
    levels = {}
    for n in sorted(marks):
        L = Level(n)
        for ln in region(n):
            s = ln.strip()
            if s.startswith("--"):
                continue
            mk = re.match(r"(pf\w+|b2kSmoothGround|b2kPlayerAddLadder)\b", s)
            if not s or not (mk or "pfBounds" in s):
                continue
            if s.startswith("pfBoundsV"):   # MUST precede the pfBounds test (startswith overlap)
                L.vertical = True
                continue
            if s.startswith("pfBounds"):
                v = nums(s)
                # kPfEdgeL=64, kPfEndCap=40 -> right arg literal + 40
                if v:
                    L.edgeR = v[0] + 40
                else:  # "kPfEdgeL, 8520 + kPfEndCap"
                    m = re.search(r",\s*(\d+)\s*\+", s)
                    if m: L.edgeR = int(m.group(1)) + 40
                continue
            if s.startswith("pfSlab"):
                nm = re.search(r'"([^"]+)"', s).group(1)
                v = nums(s)
                if len(v) >= 4:
                    L.slabs.append((nm, v[0], v[1], v[2], v[3]))
                continue
            if s.startswith("b2kSmoothGround"):
                # drop the handler name FIRST: the "2" in "b2kSmoothGround" is a
                # digit the NUM regex would otherwise capture as a coordinate,
                # shifting every x,y pair by one (a latent bug exposed by the star
                # surface check -- nothing read cloud spans before it).
                body = s[len("b2kSmoothGround"):]
                xs = [float(x) for x in re.findall(NUM, body)]
                # points are "x,y" pairs; solid span = inner xs (ghost rule)
                pts = list(zip(xs[0::2], xs[1::2]))
                xsv = sorted(p[0] for p in pts)
                if len(xsv) >= 4:
                    L.clouds.append((xsv[1], xsv[-2], pts[0][1]))
                continue
            if s.startswith("pfMakeSpikes"):
                v = nums(s); L.spikes.append((v[0], v[1])); continue
            if s.startswith("pfMakeLava"):
                v = nums(s); L.lava.append((v[0], v[1])); continue
            if s.startswith("pfMakeSlimePool"):   # Phase E goo pool = a lava-like surface hazard
                v = nums(s); L.lava.append((v[0], v[1])); continue
            if s.startswith("pfMakeWater"):
                v = nums(s); L.water.append((v[0], v[1], v[2], v[3])); continue
            if s.startswith("pfMakeCoin"):
                v = nums(s); L.coins.append((v[0], v[1])); continue
            if s.startswith("pfMakeGem"):
                v = nums(s); L.gems.append((v[0], v[1])); continue
            if s.startswith("pfMakeStar"):
                v = nums(s); L.stars.append((v[0], v[1])); continue
            mt = re.match(r'pfTile "([^"]+)",\s*' + NUM + r',\s*' + NUM, s)
            if mt and mt.group(1) in ("cactus","rock","bush","fence","fence_broken",
                    "mushroom_brown","mushroom_red","sign","grass_purple"):
                L.decor.append((mt.group(1), float(mt.group(2)) + 32, float(mt.group(3)) + 32))
                continue
            if s.startswith("pfMakeSlime"):
                v = nums(s)  # idx, "kind", x, minx, maxx, topy
                L.enemies.append(("slime", v[0], v[1], v[2], v[3], v[4], 24)); continue
            if s.startswith("pfMakeCritter"):
                v = nums(s)  # idx,"kind",x,minx,maxx,topy,speed,...,halfw,fullh,...
                L.enemies.append(("critter", v[0], v[1], v[2], v[3], v[4], v[6])); continue
            if s.startswith("pfMakeSnail"):
                v = nums(s)  # idx,x,minx,maxx
                L.enemies.append(("snail", v[0], v[1], v[2], v[3], 576, 24)); continue
            if s.startswith("pfMakeFrog"):
                v = nums(s)  # idx,x,minx,maxx,topy
                L.enemies.append(("frog", v[0], v[1], v[2], v[3], v[4], 22)); continue
            if s.startswith("pfMakeBlockSlime"):
                v = nums(s)  # idx,x,minx,maxx,topy  (a hopping cube; patrols its band)
                L.enemies.append(("block", v[0], v[1], v[2], v[3], v[4], 24)); continue
            if s.startswith("pfMakeConveyor"):
                v = nums(s)  # pL,pR,dir
                L.conveyors.append((v[0], v[1], v[2])); continue
            if s.startswith("pfMakeThwomp"):
                body = s.split("--", 1)[0]
                # chained = the weight+chain look: no tile-face string, not a faced block
                chained = ('"' not in body) and ("true" not in body)
                v = nums(s); L.thwomps.append((v[0], v[1], chained)); continue
            if s.startswith("pfMakeBarnacle"):
                v = nums(s); L.barnacles.append((v[0], v[1], v[2])); continue
            if s.startswith("pfMakeSpider"):
                v = nums(s); L.spiders.append((v[0], v[1], v[2], v[3], v[4])); continue
            if s.startswith("pfMakeCheckpoint"):
                v = nums(s); L.checkpoint = v[0]; continue
            if s.startswith("pfMakeGoal"):
                v = nums(s); L.goal = (v[0], v[1]); continue
            if s.startswith("pfMakeBridge"):
                v = nums(s); L.bridge = (v[0], v[1], v[2]); continue
        levels[n] = L
    return levels

# ---- terrain helpers -------------------------------------------------------
GROUND_NAMES = ("pf_ground", "pf_plat", "pf_pond", "pf_liftped", "pf_dune", "pf_lavastep")

def solid_top_at(L, x, y_tol_top=8):
    """Return the highest solid TOP surface at column x (slabs + clouds), or None."""
    tops = []
    for nm, l, t, r, b in L.slabs:
        if any(nm.startswith(g) for g in GROUND_NAMES) and l <= x <= r:
            tops.append(t)
    for cl, cr, cy in L.clouds:
        if cl <= x <= cr:
            tops.append(cy)
    if L.bridge and L.bridge[0] <= x <= L.bridge[1]:
        tops.append(L.bridge[2])
    return min(tops) if tops else None   # min y = highest surface

def inside_solid(L, x, y, pad=6):
    for nm, l, t, r, b in L.slabs:
        if l + pad <= x <= r - pad and t + pad <= y <= b - pad:
            return nm
    return None

def ground_top_at(L, x):
    """The MAIN ground/platform top at x (ignores clouds), or None over a pit."""
    tops = []
    for nm, l, t, r, b in L.slabs:
        if any(nm.startswith(g) for g in ("pf_ground", "pf_plat", "pf_pond", "pf_liftped")) and l <= x <= r:
            tops.append(t)
    return min(tops) if tops else None

# ---- the checks ------------------------------------------------------------
def audit(L):
    import math
    out = []
    def flag(sev, msg):
        out.append((sev, msg))

    # A VERTICAL climbing level (pfBoundsV) uses the full height as play space and
    # the camera scrolls; the horizontal y=576 ground model (coins-near-a-surface,
    # walkers-on-ground, pit widths) does not apply, so skip the geometry checks
    # here and lean on the OXT pass + check-livecodescript for it.
    if L.vertical:
        flag("INFO", "vertical climbing level - geometry audit skipped (the y=576 ground model does not apply; verify in OXT)")
        return out

    # bounds
    lo, hi = L.edgeL, L.edgeR

    # coins
    for (x, y) in L.coins:
        if x < lo or x > hi:
            flag("ERR", f"coin {x:.0f},{y:.0f} OUTSIDE play bounds [{lo:.0f}..{hi:.0f}]")
        nm = inside_solid(L, x, y)
        if nm:
            flag("ERR", f"coin {x:.0f},{y:.0f} BURIED inside slab '{nm}'")
        # underwater coins (inside a swim basin) are intentional dives -- the
        # basin has no solid floor (the kill floor is under it), so skip the
        # surface check for them
        in_water = any(wl <= x <= wr and wt <= y <= wb for (wl, wt, wr, wb) in L.water)
        # ground-level coin (y>=492) needs a real surface below within a jump
        if y >= 492 and not in_water:
            gt = solid_top_at(L, x)
            if gt is None:
                flag("ERR", f"coin {x:.0f},{y:.0f} hangs over a PIT (no surface under it)")
            elif gt - y > 120:
                flag("WARN", f"coin {x:.0f},{y:.0f} sits {gt-y:.0f}px above its surface (high for a 'ground' coin)")

    # gems: bonus mid-air pickups -- must be in-bounds, not buried, and clear of
    # coins and the goal flag (they are a distinct collectible, not a coin)
    for (x, y) in L.gems:
        if x < lo or x > hi:
            flag("ERR", f"gem {x:.0f},{y:.0f} OUTSIDE play bounds [{lo:.0f}..{hi:.0f}]")
        nm = inside_solid(L, x, y)
        if nm:
            flag("ERR", f"gem {x:.0f},{y:.0f} BURIED inside slab '{nm}'")
        for (cx, cy) in L.coins:
            if math.hypot(x - cx, y - cy) < 46:
                flag("WARN", f"gem {x:.0f},{y:.0f} overlaps coin ({cx:.0f},{cy:.0f})")
        if L.goal and math.hypot(x - L.goal[0], y - (L.goal[1] + 16)) < 48:
            flag("ERR", f"gem {x:.0f},{y:.0f} overlaps the goal flag")

    # stars: the hidden challenge pickup -- the user's hard rule is REACHABILITY,
    # so each star must sit ON a surface the player provably stands on (a cloud /
    # slab / stepping-stone top ~56px below it, the pickup convention), be in
    # bounds, not buried, and clear of coins/gems/goal (a distinct collectible).
    # A star with no surface ~24-110px below it is flagged: it would be a bare
    # mid-air grab (the reachability risk).
    for (x, y) in L.stars:
        if x < lo or x > hi:
            flag("ERR", f"star {x:.0f},{y:.0f} OUTSIDE play bounds [{lo:.0f}..{hi:.0f}]")
        nm = inside_solid(L, x, y)
        if nm:
            flag("ERR", f"star {x:.0f},{y:.0f} BURIED inside slab '{nm}'")
        gt = solid_top_at(L, x)
        if gt is None or not (y + 20 <= gt <= y + 110):
            flag("ERR", f"star {x:.0f},{y:.0f} has NO surface to stand on ~56px below it (nearest top {gt}) -- a bare mid-air grab, may be unreachable")
        for (cx, cy) in L.coins:
            if math.hypot(x - cx, y - cy) < 48:
                flag("WARN", f"star {x:.0f},{y:.0f} overlaps coin ({cx:.0f},{cy:.0f})")
        for (cx, cy) in L.gems:
            if math.hypot(x - cx, y - cy) < 48:
                flag("WARN", f"star {x:.0f},{y:.0f} overlaps gem ({cx:.0f},{cy:.0f})")
        if L.goal and math.hypot(x - L.goal[0], y - (L.goal[1] + 16)) < 48:
            flag("ERR", f"star {x:.0f},{y:.0f} overlaps the goal flag")

    # enemies: patrol must stay on a continuous ground top at ~topy
    walkers = [e for e in L.enemies if e[0] in ("slime", "critter", "snail", "frog")]
    for kind, idx, x, mn, mx, topy, hw in walkers:
        # sample the patrol span; any column with no ground (or wrong height) = walk-off
        offs = []
        step = max(8, (mx - mn) / 12) if mx > mn else 8
        xx = mn
        while xx <= mx + 0.1:
            gt = ground_top_at(L, xx)
            if gt is None:
                offs.append(xx)
            xx += step
        if offs:
            flag("ERR", f"{kind} #{idx:.0f} (x{x:.0f}) patrols {mn:.0f}..{mx:.0f} but x~{offs[0]:.0f} is over a PIT (walks off)")
        # patrol surface height vs declared topy (spikes/lava gaps aside)
        gt = ground_top_at(L, x)
        if gt is not None and topy not in (gt,) and kind in ("slime", "critter", "frog") and abs(gt - topy) > 1:
            flag("WARN", f"{kind} #{idx:.0f} topY {topy:.0f} != ground top {gt:.0f} at x{x:.0f}")

    # walkers sharing a path (overlapping swept ranges at same level) -> gotcha 18 jitter
    spans = [(e[2], e[3]-e[6], e[4]+e[6], e[0], e[1]) for e in walkers]
    for a in range(len(spans)):
        for b in range(a+1, len(spans)):
            xa, la, ra, ka, ia = spans[a]
            xb, lb, rb, kb, ib = spans[b]
            if ia == ib:
                continue   # same index = a conditional reskin (if gSpooksOK ... else ...), one foe, not two
            if la <= rb and lb <= ra:
                flag("WARN", f"{ka}#{ia:.0f} ({la:.0f}..{ra:.0f}) and {kb}#{ib:.0f} ({lb:.0f}..{rb:.0f}) patrol RANGES overlap (collision/jitter risk)")

    # checkpoint grounding + hazard proximity
    if L.checkpoint is not None:
        cx = L.checkpoint
        if cx < lo or cx > hi:
            flag("ERR", f"checkpoint x{cx:.0f} OUTSIDE bounds [{lo:.0f}..{hi:.0f}]")
        gt = ground_top_at(L, cx)
        if gt is None:
            flag("ERR", f"checkpoint x{cx:.0f} is over a PIT (respawn would drop into it)")
        for (sl, sr) in L.spikes + L.lava:
            if sl - 60 <= cx <= sr + 60:
                flag("WARN", f"checkpoint x{cx:.0f} is within 60px of a hazard pit {sl:.0f}..{sr:.0f}")

    # goal grounding + bounds
    if L.goal:
        gx, gy = L.goal
        if gx < lo or gx > hi:
            flag("ERR", f"goal flag x{gx:.0f} OUTSIDE bounds [{lo:.0f}..{hi:.0f}]")
        gt = ground_top_at(L, gx)
        if gt is None:
            flag("ERR", f"goal flag x{gx:.0f} is over a PIT")
        elif gy + 32 > gt + 4:
            flag("WARN", f"goal flag base (y{gy+32:.0f}) sits below its ground top (y{gt:.0f}) at x{gx:.0f}")
        # a coin must not overlap the goal flag sprite (64px frame, planted)
        for (cx, cy) in L.coins:
            if math.hypot(cx - gx, cy - (gy + 16)) < 48:
                flag("ERR", f"coin ({cx:.0f},{cy:.0f}) overlaps the goal flag at x{gx:.0f}")

    # SPIKES must align with a real gap in the MAIN ground (a spike PIT); lava
    # may be either a bridged pit OR an intentional SURFACE grinder on solid
    # ground (the L2 lift bay), so it is not gap-checked here.
    for (hl, hr) in L.spikes:
        mid = (hl + hr) / 2
        if ground_top_at(L, mid) is not None:
            flag("WARN", f"spikes {hl:.0f}..{hr:.0f} overlap solid ground (mid x{mid:.0f}) -- expected an open pit")
        # pfMakeSpikes tiles the row pL..pR-64 (top-lefts), so it fills the pit
        # FLUSH only when the width is a 64px multiple; otherwise a partial tile
        # is left (the pit "doesn't fit its spikes").
        if (hr - hl) % 64 != 0:
            flag("WARN", f"spike pit {hl:.0f}..{hr:.0f} width {hr-hl:.0f} is not a 64px multiple -- the spike row won't fill it flush")

    # CONVEYOR: a belt carries the GROUNDED hero, so every column must be solid
    # ground (a belt over a pit would convey him into thin air), and its width
    # must be a 64px multiple to tile flush.
    for (cl, cr, cdir) in L.conveyors:
        gap = None
        x = cl
        while x <= cr:
            if ground_top_at(L, x) is None:
                gap = x; break
            x += 32
        if gap is not None:
            flag("ERR", f"conveyor {cl:.0f}..{cr:.0f} runs over a pit (no ground at x{gap:.0f})")
        if (cr - cl) % 64 != 0:
            flag("WARN", f"conveyor {cl:.0f}..{cr:.0f} width {cr-cl:.0f} is not a 64px multiple -- the belt tiles won't fill it flush")

    # WALKER vs THWOMP: a walker asserts its velocity every frame; if its swept
    # range gets within a few px of a crusher's body (x +/- 30) the two fight the
    # solver and the walker STICKS to the block (gotcha 17/18). Keep a margin.
    for (kind, idx, x, mn, mx, topy, hw) in walkers:
        wl, wr = mn - hw, mx + hw
        for (ti, tx, chained) in L.thwomps:
            bl, br = tx - 30, tx + 30
            gap = max(bl - wr, wl - br)   # horizontal gap swept-range <-> block body
            if gap < 24:
                flag("WARN", f"{kind}#{idx:.0f} sweep ({wl:.0f}..{wr:.0f}) is only {max(gap,0):.0f}px from thwomp#{ti:.0f} body ({bl:.0f}..{br:.0f}) -- may stick to the crusher")

    # COIN IN A CHAIN COLUMN: a chained crusher hangs a chain at its column
    # (x +/- ~32) spanning y~44..172. A coin parked in that column at chain
    # height draws BEHIND the chain art (obscured). Coins BELOW the chain (ground
    # level) are fine -- those are the "dash under it" beats.
    for (ti, tx, chained) in L.thwomps:
        if not chained:
            continue
        for (cx, cy) in L.coins:
            if abs(cx - tx) <= 36 and 20 <= cy <= 180:
                flag("WARN", f"coin ({cx:.0f},{cy:.0f}) sits in thwomp#{ti:.0f}'s chain column (x{tx:.0f}, chain y44..172) -- obscured by the chain art")

    # barnacle/spider grounding sanity
    for (idx, bx, by) in L.barnacles:
        if ground_top_at(L, bx) is None:
            flag("ERR", f"barnacle #{idx:.0f} x{bx:.0f} over a PIT")

    # VISUAL CROWDING. Decor (scenery) must stay clear of the BEATS (the
    # layout law): a tuft/mushroom must not sit inside an enemy's patrol SWEEP
    # (the enemy passes through it), on a coin, on a barnacle, or on another
    # decor tile. Coin-on-enemy-beat is INTENTIONAL (a coin in a patrol path).
    import math
    DH = 32   # decor sprite half-width (64px tiles)
    for (fr, cx, cy) in L.decor:
        for (kind, idx, x, mn, mx, topy, hw) in walkers:
            sl, sr = mn - 8, mx + 8   # decor sitting ON the patrol path (the "on the beat" smell)
            if sl <= cx <= sr and abs(cy - (topy - 18)) < 60:
                flag("WARN", f"decor:{fr} (x{cx:.0f}) sits in {kind}#{idx:.0f}'s patrol sweep ({mn:.0f}..{mx:.0f})")
        for (cnx, cny) in L.coins:
            if math.hypot(cx - cnx, cy - cny) < 50:
                flag("WARN", f"decor:{fr} (x{cx:.0f}) overlaps coin ({cnx:.0f},{cny:.0f})")
        for (bi, bx, by) in L.barnacles:
            if math.hypot(cx - bx, cy - by) < 52:
                flag("WARN", f"decor:{fr} (x{cx:.0f}) overlaps barnacle #{bi:.0f}")
        # decor must not overlap the checkpoint or goal flag (both 64px sprites,
        # ground-planted): a sign on the flag reads as one tangled object
        if L.checkpoint is not None and abs(cx - L.checkpoint) < 64:
            flag("WARN", f"decor:{fr} (x{cx:.0f}) overlaps the checkpoint flag (x{L.checkpoint:.0f})")
        if L.goal and abs(cx - L.goal[0]) < 64 and abs(cy - (L.goal[1] + 16)) < 80:
            flag("WARN", f"decor:{fr} (x{cx:.0f}) overlaps the goal flag (x{L.goal[0]:.0f})")
    # decor-on-decor
    for a in range(len(L.decor)):
        for b in range(a + 1, len(L.decor)):
            fa, xa, ya = L.decor[a]; fb, xb, yb = L.decor[b]
            if math.hypot(xa - xb, ya - yb) < 50:
                flag("WARN", f"decor:{fa} (x{xa:.0f}) overlaps decor:{fb} (x{xb:.0f})")
    # coin-on-coin (two pickups visually merged)
    for a in range(len(L.coins)):
        for b in range(a + 1, len(L.coins)):
            xa, ya = L.coins[a]; xb, yb = L.coins[b]
            if math.hypot(xa - xb, ya - yb) < 46:
                flag("WARN", f"coin ({xa:.0f},{ya:.0f}) overlaps coin ({xb:.0f},{yb:.0f})")
    return out

def main():
    levels = parse()
    total = 0
    for n in sorted(levels):
        L = levels[n]
        res = audit(L)
        if L.vertical:
            head = f"===== LEVEL {n}  (VERTICAL climb, {len(L.coins)} coins) ====="
        else:
            head = f"===== LEVEL {n}  (bounds {L.edgeL:.0f}..{L.edgeR:.0f}, {len(L.coins)} coins, {len(L.enemies)} walkers) ====="
        print(head)
        if not res:
            print("   (clean)")
        for sev, msg in sorted(res, key=lambda r: (r[0] != "ERR", r[1])):
            print(f"   {sev:4} {msg}")
            if sev != "INFO":
                total += 1
        print()
    print(f"{total} finding(s) across {len(levels)} levels.")

if __name__ == "__main__":
    main()
