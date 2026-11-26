"""戰鬥數值驗證用的模擬（設計階段的參考實作）。

規則對應 docs/design.md 第 4 章，角色與敵人數值對應 13.2、13.3，
輸出就是第 14 章那張表的來源。雙方都由簡單的腳本自動出招。

用法（在專案根目錄）：
    python3 tools/balance_sim.py            # 聰明打法，四種遭遇各 400 場
    python3 tools/balance_sim.py naive      # 無腦打法：不理會敵人蓄招
    python3 tools/balance_sim.py log 3 7    # 印出第 3 種遭遇（從 0 算起）、種子 7 的完整過程
    python3 tools/balance_sim.py boss_hp=3.0 stagger_time=4   # 臨時覆寫數值

M1 完成後，這支程式會被遊戲本身的自動測試取代。
"""
import random, statistics, sys, json

TICK = 1 / 30
REL = {("柔", "剛"): 1.25, ("剛", "快"): 1.25, ("快", "柔"): 1.25,
       ("剛", "柔"): 0.8, ("快", "剛"): 0.8, ("柔", "快"): 0.8}
ATTR_OF = {"剛": "筋骨", "柔": "內息", "快": "身法"}

P = dict(  # 可調參數
    hp_base=200, hp_jg=15, hp_nx=5,
    mp_base=50, mp_nx=8,
    ps_base=60, ps_jg=2, ps_nx=1,
    atk_base=20, atk_mul=2,
    spd_base=12, spd_sf=0.4,
    crit_base=0.05, crit_wx=0.002, crit_mul=1.5,
    dodge_base=0.05, dodge_sf=0.003, dodge_max=0.30,
    stagger_time=5.0, stagger_dmg=1.5, stagger_grow=1.25,
    ps_regen=0.02, guard_dmg=0.6, guard_ps=0.4, guard_ps_heal=0.30, guard_gauge=30,
    rest_mp=0.25, rest_ps=0.20, intercept=2.5, charge_open=1.5,
)

class Move:
    def __init__(s, name, kind="攻", type="剛", cost=0, mult=1.0, ps=0, charge=0.0, rec=0.3,
                 target="敵單", tags=(), effect=None):
        s.__dict__.update(locals()); del s.__dict__["s"]

class Unit:
    def __init__(s, name, side, jg, nx, sf, wx, art_type, guard_val=0, regen=1.0, moves=(),
                 hp_mul=1.0, boss=False, role=None, ai=None):
        s.name, s.side, s.boss, s.role, s.ai = name, side, boss, role, ai
        s.a = {"筋骨": jg, "內息": nx, "身法": sf, "悟性": wx}
        s.art_type, s.guard_val, s.regen = art_type, guard_val, regen
        s.moves = list(moves)
        s.max_hp = round((P["hp_base"] + jg * P["hp_jg"] + nx * P["hp_nx"]) * hp_mul)
        s.max_mp = P["mp_base"] + nx * P["mp_nx"]
        s.max_ps = P["ps_base"] + jg * P["ps_jg"] + nx * P["ps_nx"]
        s.hp, s.mp, s.ps = s.max_hp, s.max_mp, s.max_ps
        s.gauge = 0.0; s.state = "fill"; s.timer = 0.0; s.pending = None
        s.guard = False; s.fx = {}  # 狀態名 -> 剩餘秒 (中毒為 [秒, 層])
        s.acts = 0
    alive = property(lambda s: s.hp > 0)
    def speed(s):
        v = P["spd_base"] + s.a["身法"] * P["spd_sf"]
        if "輕身" in s.fx: v *= 1.3
        if "遲緩" in s.fx: v *= 0.7
        return v
    def atk(s, t):
        v = P["atk_base"] + s.a[ATTR_OF[t]] * P["atk_mul"]
        if "運功" in s.fx: v *= 1.25
        return v
    def defense(s): return s.a["筋骨"] + s.a["內息"] + s.guard_val

class Battle:
    def __init__(s, party, enemies, seed, log=False):
        s.rng = random.Random(seed); s.units = party + enemies
        s.t = 0.0; s.log = log; s.stats = dict(staggers=0, interrupts=0, heals=0)
    def side(s, side, alive=True):
        return [u for u in s.units if u.side == side and (u.alive or not alive)]
    def say(s, *a):
        if s.log: print(f"{s.t:6.2f}", *a)

    def hit(s, src, tgt, m):
        if not tgt.alive: return
        if tgt.state not in ("stagger", "stun"):
            dodge = P["dodge_base"] + (tgt.a["身法"] - src.a["身法"]) * P["dodge_sf"]
            if s.rng.random() < max(0, min(P["dodge_max"], dodge)):
                s.say(f"  {tgt.name} 閃過 {m.name}"); return
        rel = REL.get((m.type, tgt.art_type), 1.0)
        d = src.atk(m.type) * m.mult * 100 / (100 + tgt.defense()) * rel
        if tgt.state == "stagger": d *= P["stagger_dmg"]
        if tgt.guard: d *= P["guard_dmg"]
        if "護體" in tgt.fx: d *= 0.75
        crit = s.rng.random() < min(0.4, P["crit_base"] + src.a["悟性"] * P["crit_wx"])
        if crit: d *= P["crit_mul"]
        d = round(d * s.rng.uniform(0.95, 1.05))
        tgt.hp = max(0, tgt.hp - d)
        psd = m.ps * rel
        if tgt.state == "charge": psd *= P["intercept"] if "截招" in m.tags else P["charge_open"]
        if tgt.guard: psd *= P["guard_ps"]
        s.say(f"  {src.name} {m.name} -> {tgt.name} {d}{'!' if crit else ''} (氣血 {tgt.hp}/{tgt.max_hp})")
        if tgt.alive and tgt.state != "stagger":
            tgt.ps -= psd
            if tgt.ps <= 0:
                if tgt.state == "charge":
                    s.stats["interrupts"] += 1; tgt.pending = None
                    s.say(f"  >> {tgt.name} 蓄招被打斷")
                tgt.state, tgt.timer, tgt.guard = "stagger", P["stagger_time"], False
                s.stats["staggers"] += 1; s.say(f"  >> {tgt.name} 破綻")
        if tgt.alive and m.effect:
            name, chance, dur = m.effect
            if tgt.boss and name == "點穴": chance, dur = chance * 0.5, dur * 0.5
            if s.rng.random() < chance:
                if name == "點穴":
                    if tgt.state == "fill": tgt.state, tgt.timer = "stun", dur
                elif name == "中毒":
                    cur = tgt.fx.get("中毒", [0, 0]); tgt.fx["中毒"] = [dur, min(3, cur[1] + 1)]
                else: tgt.fx[name] = dur

    def resolve(s, u, m, tgt):
        u.acts += 1
        if m.kind == "攻":
            tgts = s.side("E" if u.side == "P" else "P") if m.target == "敵全" else [tgt]
            if m.target == "敵單" and not tgt.alive:
                foes = s.side("E" if u.side == "P" else "P")
                if not foes: return
                tgts = [min(foes, key=lambda x: x.hp)]
            for x in tgts: s.hit(u, x, m)
        elif m.kind == "治":
            if not tgt.alive: tgt = min(s.side(u.side), key=lambda x: x.hp / x.max_hp)
            amt = round(u.atk("柔") * m.mult); tgt.hp = min(tgt.max_hp, tgt.hp + amt)
            s.stats["heals"] += 1; s.say(f"  {u.name} {m.name} -> {tgt.name} +{amt}")
        elif m.kind == "益":
            name, _, dur = m.effect
            for x in (s.side(u.side) if m.target == "我全" else [tgt if tgt.alive else u]): x.fx[name] = dur
            s.say(f"  {u.name} {m.name}")

    def act(s, u):
        if not s.side("E" if u.side == "P" else "P"): return
        u.guard = False
        choice = u.ai(s, u)
        kind = choice[0]
        if kind == "守":
            u.acts += 1; u.guard = True; u.ps = min(u.max_ps, u.ps + u.max_ps * P["guard_ps_heal"])
            u.gauge = P["guard_gauge"]; u.state = "fill"; s.say(f"  {u.name} 守勢"); return
        if kind == "息":
            u.acts += 1; u.mp = min(u.max_mp, u.mp + u.max_mp * P["rest_mp"])
            u.ps = min(u.max_ps, u.ps + u.max_ps * P["rest_ps"]); u.gauge = 0; u.state = "fill"
            s.say(f"  {u.name} 調息"); return
        _, m, tgt = choice
        cost = m.cost * (1.25 if "內傷" in u.fx else 1)
        u.mp -= cost; u.pending = (m, tgt)
        if m.charge > 0:
            u.state, u.timer = "charge", m.charge; s.say(f"  {u.name} 開始蓄招 {m.name} ({m.charge}s)")
        else: s.finish(u)

    def finish(s, u):
        m, tgt = u.pending; u.pending = None
        if not s.side("E" if u.side == "P" else "P"): u.state = "fill"; return
        s.resolve(u, m, tgt); u.gauge = 0; u.state, u.timer = "recover", m.rec

    def run(s, limit=600):
        acc = 0.0
        while s.t < limit:
            if not s.side("P"): return "敗"
            if not s.side("E"): return "勝"
            s.t += TICK; acc += TICK
            sec = acc >= 1.0
            if sec: acc -= 1.0
            for u in s.units:
                if not u.alive: continue
                if sec:
                    if "內傷" not in u.fx: u.mp = min(u.max_mp, u.mp + u.regen)
                    if u.state != "stagger": u.ps = min(u.max_ps, u.ps + u.max_ps * P["ps_regen"])
                    if "流血" in u.fx: u.hp = max(0, u.hp - round(u.max_hp * (0.0075 if u.boss else 0.015)))
                    if "中毒" in u.fx: u.hp = max(0, u.hp - round(u.max_hp * 0.01 * u.fx["中毒"][1] * (0.5 if u.boss else 1)))
                    if not u.alive: continue
                for k in list(u.fx):
                    if k == "中毒":
                        u.fx[k][0] -= TICK
                        if u.fx[k][0] <= 0: del u.fx[k]
                    else:
                        u.fx[k] -= TICK
                        if u.fx[k] <= 0: del u.fx[k]
                if u.state == "fill":
                    u.gauge += u.speed() * TICK
                    if u.gauge >= 100: s.act(u)
                elif u.state == "charge":
                    u.timer -= TICK
                    if u.timer <= 0: s.finish(u)
                elif u.state == "recover":
                    u.timer -= TICK
                    if u.timer <= 0: u.state = "fill"
                elif u.state in ("stagger", "stun"):
                    u.timer -= TICK
                    if u.timer <= 0:
                        if u.state == "stagger":
                            if u.boss: u.max_ps = round(u.max_ps * P["stagger_grow"])
                            u.ps = u.max_ps
                        u.state = "fill"
        return "逾時"

# ---------- AI ----------
def can(u, m): return u.mp >= m.cost * (1.25 if "內傷" in u.fx else 1)
def mv(u, name): return next(m for m in u.moves if m.name == name)
def foes(b, u): return b.side("E" if u.side == "P" else "P")
def focus(b, u):
    f = foes(b, u)
    st = [x for x in f if x.state == "stagger"]
    return min(st or f, key=lambda x: x.hp)
NAIVE = False
def threat(b, u):
    """正在蓄大招的敵人"""
    if NAIVE: return None
    c = [x for x in foes(b, u) if x.state == "charge" and x.pending and "大招" in x.pending[0].tags]
    return max(c, key=lambda x: x.pending[0].mult) if c else None
def should_guard(b, u, best_ps):
    th = threat(b, u)
    if not th or th.pending[0].target != "敵全": return False
    return th.timer < 2.2 and th.ps > best_ps * 1.5 * 1.3
def low_mp_rest(u):
    return u.mp < 0.15 * u.max_mp

def ai_hero(b, u):
    th = threat(b, u)
    if should_guard(b, u, 28): return ("守",)
    if th and th.timer > 0.4:
        return ("招", mv(u, "迴風斬") if can(u, mv(u, "迴風斬")) else mv(u, "直刺"), th)
    t = focus(b, u)
    if "運功" not in u.fx and can(u, mv(u, "凝氣")) and u.mp > 0.5 * u.max_mp and len(foes(b, u)) > 1: return ("招", mv(u, "凝氣"), u)
    big = mv(u, "歸一")
    if t.state == "stagger" and t.timer > big.charge + 0.2 and can(u, big): return ("招", big, t)
    if can(u, mv(u, "迴風斬")): return ("招", mv(u, "迴風斬"), t)
    if low_mp_rest(u): return ("息",)
    return ("招", mv(u, "直刺"), t)

def ai_sword(b, u):
    th = threat(b, u)
    if should_guard(b, u, 22 * 2.5 / 1.5): return ("守",)
    if th and can(u, mv(u, "斷流")): return ("招", mv(u, "斷流"), th)
    c = [] if NAIVE else [x for x in foes(b, u) if x.state == "charge"]
    if c and can(u, mv(u, "斷流")): return ("招", mv(u, "斷流"), c[0])
    if len(foes(b, u)) >= 3 and can(u, mv(u, "雲棧飛花")): return ("招", mv(u, "雲棧飛花"), focus(b, u))
    if "輕身" not in u.fx and can(u, mv(u, "輕身訣")) and u.mp > 0.6 * u.max_mp: return ("招", mv(u, "輕身訣"), u)
    if low_mp_rest(u): return ("息",)
    return ("招", mv(u, "點星"), focus(b, u))

def ai_blade(b, u):
    th = threat(b, u)
    if should_guard(b, u, 18): return ("守",)
    if th and can(u, mv(u, "崩山")) and th.timer > 1.1: return ("招", mv(u, "崩山"), th)
    t = focus(b, u)
    big = mv(u, "斷岳")
    if t.state == "stagger" and t.timer > big.charge + 0.2 and can(u, big): return ("招", big, t)
    if t.state != "stagger" and can(u, mv(u, "崩山")) and t.hp > 0.35 * t.max_hp: return ("招", mv(u, "崩山"), t)
    if can(u, mv(u, "血刃")) and "流血" not in t.fx and t.hp > 0.4 * t.max_hp: return ("招", mv(u, "血刃"), t)
    if low_mp_rest(u): return ("息",)
    return ("招", mv(u, "橫斬"), t)

def ai_healer(b, u):
    al = b.side("P"); low = min(al, key=lambda x: x.hp / x.max_hp)
    if low.hp < 0.55 * low.max_hp and can(u, mv(u, "回春針")): return ("招", mv(u, "回春針"), low)
    th = threat(b, u)
    if should_guard(b, u, 12) and low.hp >= 0.4 * low.max_hp: return ("守",)
    if th and th.ps < 20: return ("招", mv(u, "點脈手"), th)
    if th and "護體" not in low.fx and can(u, mv(u, "護心訣")): return ("招", mv(u, "護心訣"), low)
    if low_mp_rest(u): return ("息",)
    return ("招", mv(u, "點脈手"), focus(b, u))

def ai_enemy(b, u):
    al = foes(b, u)
    opts = [m for m in u.moves if can(u, m)]
    w = [getattr(m, "weight", 1) for m in opts]
    m = b.rng.choices(opts, weights=w)[0]
    return ("招", m, b.rng.choice(al))

def W(m, w): m.weight = w; return m

# ---------- 內容 ----------
def party():
    hero = Unit("主角", "P", 18, 18, 18, 25, "柔", guard_val=10, regen=2.0, ai=ai_hero, moves=[
        Move("直刺", type="快", mult=1.0, ps=12, rec=0.3),
        Move("迴風斬", type="剛", cost=18, mult=1.6, ps=28, rec=0.8),
        Move("凝氣", kind="益", cost=20, target="自身", effect=("運功", 1, 12), rec=0.3),
        Move("歸一", type="柔", cost=45, mult=3.2, ps=30, charge=2.5, rec=1.0)])
    sword = Unit("沈清禾", "P", 14, 14, 26, 16, "快", guard_val=6, regen=1.5, ai=ai_sword, moves=[
        Move("點星", type="快", mult=0.9, ps=10, rec=0.2),
        Move("斷流", type="快", cost=14, mult=0.9, ps=22, rec=0.3, tags=("截招",)),
        Move("雲棧飛花", type="快", cost=30, mult=0.9, ps=12, charge=1.5, rec=0.8, target="敵全"),
        Move("輕身訣", kind="益", cost=15, target="自身", effect=("輕身", 1, 12), rec=0.2)])
    blade = Unit("霍嶽", "P", 26, 12, 12, 10, "剛", guard_val=12, regen=1.0, ai=ai_blade, moves=[
        Move("橫斬", type="剛", mult=1.1, ps=18, rec=0.5),
        Move("崩山", type="剛", cost=25, mult=1.5, ps=45, charge=1.0, rec=1.0),
        Move("血刃", type="剛", cost=20, mult=1.3, ps=20, rec=0.6, effect=("流血", 0.7, 6)),
        Move("斷岳", type="剛", cost=50, mult=3.5, ps=40, charge=3.0, rec=1.5)])
    healer = Unit("溫蘅", "P", 12, 24, 14, 20, "柔", guard_val=8, regen=2.5, ai=ai_healer, moves=[
        Move("點脈手", type="柔", mult=0.8, ps=10, rec=0.3),
        Move("回春針", kind="治", cost=22, mult=2.2, charge=0.5, rec=0.3, target="我單"),
        Move("護心訣", kind="益", cost=18, target="我單", effect=("護體", 1, 12), rec=0.3),
        Move("封穴", type="柔", cost=28, mult=0.6, ps=10, charge=1.0, rec=0.5, effect=("點穴", 0.6, 3))])
    return [hero, sword, blade, healer]

def grunt(i): return Unit(f"嘍囉{i}", "E", 12, 6, 10, 5, "剛", hp_mul=CFG["grunt_hp"], ai=ai_enemy, moves=[
    W(Move("亂砍", type="剛", mult=1.0, ps=12, rec=0.5), 3),
    W(Move("猛劈", type="剛", mult=1.6, ps=22, charge=1.5, rec=0.8), 1)])
def archer(i): return Unit(f"弓手{i}", "E", 8, 6, 18, 5, "快", hp_mul=CFG["archer_hp"], ai=ai_enemy, moves=[
    W(Move("冷箭", type="快", mult=1.1, ps=8, rec=0.4), 3),
    W(Move("連珠箭", type="快", mult=0.7, ps=6, charge=1.5, rec=0.8, target="敵全"), 1)])
def chief(): return Unit("山賊頭目", "E", 24, 10, 12, 8, "剛", guard_val=8, hp_mul=CFG["chief_hp"], ai=ai_enemy, moves=[
    W(Move("重斧", type="剛", mult=1.3, ps=20, rec=0.6), 3),
    W(Move("開山", type="剛", mult=CFG["chief_big"], ps=40, charge=3.0, rec=1.2, tags=("大招",)), 2)])
def boss(): return Unit("黑水寨三當家", "E", 28, 22, CFG["boss_sf"], 12, "剛", guard_val=15, regen=3, hp_mul=CFG["boss_hp"], boss=True, ai=ai_enemy, moves=[
    W(Move("怒濤刀", type="剛", mult=CFG["boss_basic"], ps=22, rec=0.5), 4),
    W(Move("毒砂", type="快", mult=0.6, ps=8, rec=0.5, target="敵全", effect=("中毒", 0.6, 10)), 2),
    W(Move("震脈掌", type="柔", mult=1.2, ps=25, charge=1.0, rec=0.6, effect=("內傷", 0.7, 8)), 2),
    W(Move("覆海", type="剛", mult=CFG["boss_big"], ps=35, charge=4.0, rec=1.5, target="敵全", tags=("大招",)), 2)])

CFG = dict(grunt_hp=0.65, archer_hp=0.55, chief_hp=1.8, chief_big=3.4, boss_hp=2.6, boss_big=3.6, boss_basic=1.6, boss_sf=30)

ENC = {
    "普通：嘍囉×2 弓手×1": lambda: [grunt(1), grunt(2), archer(1)],
    "普通：嘍囉×3 弓手×1": lambda: [grunt(1), grunt(2), grunt(3), archer(1)],
    "精英：頭目 嘍囉×2": lambda: [chief(), grunt(1), grunt(2)],
    "首領：三當家 嘍囉×1 弓手×1": lambda: [boss(), grunt(1), archer(1)],
}

def trial(name, n=400, anim=1.0):
    res = []
    for seed in range(n):
        p = party(); b = Battle(p, ENC[name](), seed); r = b.run()
        pa = sum(u.acts for u in p); ea = sum(u.acts for u in b.units if u.side == "E")
        res.append(dict(r=r, t=b.t, pa=pa, ea=ea, hp=sum(u.hp for u in p) / sum(u.max_hp for u in p),
                        down=sum(1 for u in p if not u.alive), **b.stats))
    win = sum(1 for x in res if x["r"] == "勝") / n
    med = lambda k: statistics.median(x[k] for x in res)
    real = statistics.median(x["t"] + (x["pa"] + x["ea"]) * anim for x in res)
    print(f"{name:<24} 勝率 {win:5.1%} | 邏輯秒 {med('t'):5.1f} | 我方行動 {med('pa'):4.0f} 敵方行動 {med('ea'):4.0f} | "
          f"估實際秒 {real:5.0f} | 剩餘氣血 {med('hp'):4.0%} 倒下 {statistics.mean(x['down'] for x in res):.2f} | "
          f"破綻 {med('staggers'):.0f} 打斷 {statistics.mean(x['interrupts'] for x in res):.2f} 治療 {med('heals'):.0f}")

if __name__ == "__main__":
    for a in sys.argv[1:]:
        if "=" in a:
            k, v = a.split("="); (CFG if k in CFG else P)[k] = float(v)
    if "naive" in sys.argv: NAIVE = True; print("== 無腦打法 ==")
    if len(sys.argv) > 1 and sys.argv[1] == "log":
        name = list(ENC)[int(sys.argv[2])]; b = Battle(party(), ENC[name](), int(sys.argv[3]), log=True); print(b.run())
    else:
        for u in party(): print(f"{u.name}: 氣血 {u.max_hp} 內力 {u.max_mp} 架勢 {u.max_ps} 行動間隔 {100/u.speed():.1f}s 防禦 {u.defense()}")
        for k in ENC: trial(k)
