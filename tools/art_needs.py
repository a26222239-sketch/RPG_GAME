#!/usr/bin/env python3
"""列出一場劇本式戰鬥用到哪些美術素材，以及哪些還沒有。

    python3 tools/art_needs.py              序章的完整清單（Markdown 表格）
    python3 tools/art_needs.py --missing    只列還沒有的
    python3 tools/art_needs.py 劇本識別碼   換一份劇本

清單是從遊戲資料算出來的：劇本裡誰出了什麼招、誰挨打、誰倒下、換了哪些場景。
所以劇本一改，重跑一次就知道要補畫什麼。張數讀 tools/anim_spec.json（docs/animation_spec.md 的規格）。

狀態的意思：
    有　　　已經在 assets/ 的正式位置，而且通過 tools/check_frames.py 的允收檢查
    有，未達標　已經在遊戲裡，但沒通過允收檢查，要重交
    待驗收　放在 assets/incoming/ 裡，還沒驗收
    缺　　　還沒有；遊戲目前用程式畫的暫用版本頂替

路徑都是相對於 assets/ 的正式位置。交付時放在 assets/incoming/{批次}/ 底下同樣的路徑。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
DATA = ROOT / "data"

SPEC = json.loads((ROOT / "tools" / "anim_spec.json").read_text(encoding="utf-8"))
# 動畫契約的順序（設計文件 12.4）
ANIMS = ["idle", "ready", "charge", "attack_light", "attack_heavy", "cast", "hit", "hit_heavy", "guard", "stagger", "down", "victory", "walk"]
SHARED_FX_TEXT = {
    "slash_sword": "劍光", "slash_blade": "刀光", "palm": "掌勁", "seal": "點穴", "heal": "治療", "buff": "增益", "debuff": "減益",
    "hit_spark": "受擊火花", "charge_aura": "蓄招氣場（循環）", "guard": "守勢", "stagger_mark": "破綻標記",
}
# 招式分級對應的反應：被普攻打中是輕的受擊，被小招、大招打中是重的（遊戲裡的 HIT_REACTION）
HIT_REACTION = {"basic": "hit", "skill": "hit_heavy", "ultimate": "hit_heavy"}
# 劇本裡的演出對應到哪一組特效：大殿崩解就是殷九淵的「萬魔歸墟」
STAGE_FX = {"collapse": "tianmo_guixu"}
FORCE_TEXT = {"gang": "剛", "rou": "柔", "kuai": "快"}
STATE_TEXT = {"guard": "守勢", "stagger": "破綻", "slow": "遲緩"}

# 介面：不是從劇本算的，是戰鬥畫面固定會用到的（設計文件 15.9 的元件尺寸表）
BUTTON_SPEC = "320×128，九宮格，四邊各 28"
BAR_SPEC = "384×20，左右各 20 是不拉伸的端頭"
UI_FILES = [
    ("ui/button_disabled.png", BUTTON_SPEC, "按鈕的停用狀態：還沒輪到、不能按的招式與指令"),
    ("ui/button_pressed.png", BUTTON_SPEC, "按鈕按下去的那一瞬間"),
    ("ui/button_active.png", BUTTON_SPEC, "現在可以按的那一個按鈕（目前是把一般狀態調亮並閃爍）"),
    ("ui/mp_track.png", BAR_SPEC, "內力條的底槽"),
    ("ui/mp_fill.png", BAR_SPEC, "內力條的填充"),
    ("ui/gauge_track.png", BAR_SPEC, "行動條與蓄招倒數條的底槽"),
    ("ui/gauge_fill.png", BAR_SPEC, "行動條與蓄招倒數條的填充"),
]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


_checked: dict[str, bool] | None = None


def passed_check(relative: str) -> bool:
    """逐格的圖要再過允收檢查（tools/check_frames.py）。"""
    global _checked
    if _checked is None:
        sys.path.insert(0, str(ROOT / "tools"))
        import check_frames
        _checked = {report.subject: report.passed for report in check_frames.collect(ASSETS, None)}
    parts = relative.rsplit(".", 1)[0].split("/")
    if parts[0] == "vfx":
        subject = f"vfx/{parts[1]}"
    elif parts[0] == "characters" and parts[2] == "frames":
        subject = f"{parts[1]}/{parts[3]}"
    elif parts[0] == "characters" and parts[2] == "cutin":
        subject = f"{parts[1]}/cutin/{parts[3].removesuffix('_01')}"
    else:
        return True
    return _checked.get(subject, True)


def status(relative: str) -> str:
    stem = relative.rsplit(".", 1)[0]
    # 逐格圖也可以一格一個檔（名稱_01.png 起），有第一格就算有交
    endings = (".png", ".jpg", "_01.png")
    for ending in endings:
        if (ASSETS / (stem + ending)).exists():
            return "有" if passed_check(relative) else "有，未達標"
    incoming = ASSETS / "incoming"
    if incoming.exists():
        for ending in endings:
            if any(incoming.glob("**/" + stem + ending)):
                return "待驗收"
    return "缺"


def add(table: dict, key: str, reason: str) -> None:
    reasons = table.setdefault(key, [])
    if reason not in reasons:
        reasons.append(reason)


def main() -> int:
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    only_missing = "--missing" in sys.argv[1:]
    script_id = arguments[0] if arguments else "prologue_final"

    script = load(DATA / "scripted" / f"{script_id}.json")
    characters = load(DATA / "characters.json")
    moves = load(DATA / "moves.json")
    texts = load(DATA / "text" / "zh_TW.json")
    texts = texts.get("texts", texts)
    vfx = load(DATA / "vfx.json")  # 特效的格子大小、建議格數、循環與否，和遊戲用的是同一份設定

    def name_of(unit_id: str) -> str:
        return texts.get(characters[unit_id]["name"], unit_id)

    def move_name(move_id: str) -> str:
        return texts.get(moves[move_id]["name"], move_id)

    party, enemies = script["party"], script["enemies"]
    units = party + enemies
    anims = {unit: {} for unit in units}  # 角色 → {動畫: [用在哪裡]}
    effects: dict[str, list[str]] = {}
    cutins: dict[tuple[str, str], list[str]] = {}
    scenes: dict[str, list[str]] = {script["background"]: ["開場"]}
    forces: dict[str, list[str]] = {}
    states: dict[str, list[str]] = {}
    hp = {unit: 1.0 for unit in units}

    for unit in units:
        add(anims[unit], "idle", "一直都在")
        for move_id in characters[unit]["moves"]:
            force = moves[move_id].get("force", "")
            if unit in party and force:
                add(forces, force, f"{name_of(unit)}的招式按鈕")

    def targets_of(target: str) -> list[str]:
        if target == "party":
            return party
        if target == "enemies":
            return enemies
        return [target] if target in units else []

    for beat in script["beats"]:
        kind = beat.get("type")
        who = beat.get("who")
        if kind == "act":
            move = moves[beat["move"]]
            label = f"{name_of(who)}「{move_name(beat['move'])}」"
            if who in party:
                add(anims[who], "ready", "輪到自己、等玩家選招")
            if beat.get("charge", 0) > 0:
                add(anims[who], "charge", label)
                add(effects, "charge_aura", label)
            if move.get("class") == "ultimate":
                # 大招：自己專屬的動作，出手前播特寫
                add(anims[who], beat["move"], label)
                add(cutins, (who, beat["move"]), label)
            else:
                add(anims[who], move["anim"], label)
            add(effects, move["fx"], label)
            for target, change in beat.get("result", {}).items():
                if "hp_to" not in change:
                    continue
                if change["hp_to"] < hp[target]:
                    reaction = HIT_REACTION.get(move.get("class", "basic"), "hit")
                    add(anims[target], "down" if change["hp_to"] <= 0 else reaction, f"被{label}打中")
                    add(effects, "hit_spark", f"{name_of(target)}被{label}打中")
                hp[target] = change["hp_to"]
        elif kind == "charge":
            label = f"{name_of(who)}「{move_name(beat['move'])}」"
            add(anims[who], "charge", label)
            add(effects, "charge_aura", label)
        elif kind == "command" and beat.get("command") == "guard":
            for unit in party:
                add(anims[unit], "guard", "全隊守勢")
            add(effects, "guard", "全隊守勢")
            add(states, "guard", "全隊守勢")
        elif kind == "state" and beat.get("set"):
            add(states, beat["set"], f"{name_of(who)}進入這個狀態")
            if beat["set"] == "stagger":
                add(anims[who], "stagger", "被架住、露出破綻")
                add(effects, "stagger_mark", f"{name_of(who)}露出破綻")
        elif kind == "scene":
            add(scenes, beat["name"], "中途換場景")
        fx = beat.get("name") if kind == "fx" else beat.get("fx")
        if fx == "pin":
            for unit in beat.get("who", []):
                add(anims[unit], "attack_light", "搶上去架住對手")
        elif fx == "push_out":
            add(anims[party[0]], "attack_heavy", "雙掌把同伴震出殿外")
            add(effects, "palm", f"{name_of(party[0])}雙掌把同伴震出殿外")
            for unit in party[1:]:
                add(anims[unit], "hit_heavy", "被震出殿外")
        elif fx == "walk_to_enemy":
            add(anims[party[0]], "walk", "走向對手")
        elif fx in STAGE_FX:
            label = f"{name_of(enemies[0])}發動「{move_name(STAGE_FX[fx])}」，大殿崩解"
            add(effects, STAGE_FX[fx], label)
            add(cutins, (enemies[0], STAGE_FX[fx]), label)

    def action_spec(anim: str) -> dict:
        if anim in SPEC["actions"]:
            return SPEC["actions"][anim]
        return SPEC["actions"]["ultimate"]

    def count_text(spec: dict) -> str:
        text = f"至少 {spec['min']} 張（建議 {spec['rec']}）"
        if spec.get("entry"):
            return text + f"，前 {spec['entry']} 張進場、之後循環"
        return text + ("，循環" if spec.get("loop") else "")

    totals = {"actions": [0, 0], "vfx": [0, 0], "cutin": [0, 0]}

    sections: list[tuple[str, list[tuple[str, str, str]]]] = []

    rows = [(f"backgrounds/battle/{scene}.jpg", "2560×1080", "、".join(reasons)) for scene, reasons in scenes.items()]
    sections.append(("背景", rows))

    rows = []
    for unit in units:
        cell = 768 if characters[unit].get("boss") else 512
        order = [a for a in ANIMS if a in anims[unit]] + [a for a in anims[unit] if a not in ANIMS]
        for anim in order:
            spec = action_spec(anim)
            where = "；".join(anims[unit][anim][:3]) + ("…" if len(anims[unit][anim]) > 3 else "")
            title = spec["title"] if anim in SPEC["actions"] else f"大招「{move_name(anim)}」"
            rows.append((f"characters/{unit}/frames/{anim}.png", f"{count_text(spec)}，每格 {cell}×{cell}", f"{name_of(unit)}・{title}：{where}"))
            totals["actions"][0] += spec["min"]
            totals["actions"][1] += spec["rec"]
    sections.append((f"角色動作（共 {len(rows)} 條，至少 {totals['actions'][0]} 張、建議 {totals['actions'][1]} 張）", rows))

    rows = []
    for (unit, move_id), reasons in cutins.items():
        spec = SPEC["cutin"]
        width, height = spec["size"]
        rows.append((f"characters/{unit}/cutin/{move_id}_01.png", f"{count_text(spec)}，每張 {width}×{height}，一張一個檔（_01 起）",
                     f"{name_of(unit)}・大招特寫：{'；'.join(reasons)}"))
        totals["cutin"][0] += spec["min"]
        totals["cutin"][1] += spec["rec"]
    sections.append((f"大招特寫（共 {len(rows)} 組，至少 {totals['cutin'][0]} 張、建議 {totals['cutin'][1]} 張）", rows))

    rows = []
    for effect in list(SHARED_FX_TEXT) + sorted(e for e in effects if e not in SHARED_FX_TEXT):
        if effect not in effects:
            continue
        shared = effect in SHARED_FX_TEXT
        title = SHARED_FX_TEXT[effect] if shared else f"大招「{move_name(effect)}」" if moves.get(effect, {}).get("class") == "ultimate" else f"「{move_name(effect)}」"
        where = "；".join(effects[effect][:3]) + ("…" if len(effects[effect]) > 3 else "")
        setting = vfx[effect]
        spec = SPEC["vfx"][SPEC["vfx_kinds"].get(effect, "ultimate")]
        rows.append((f"vfx/{effect}.png", f"{count_text(spec)}，每格 {setting['frame']}×{setting['frame']}", f"{title}：{where}"))
        totals["vfx"][0] += spec["min"]
        totals["vfx"][1] += spec["rec"]
    sections.append((f"特效（共 {len(rows)} 組，至少 {totals['vfx'][0]} 張、建議 {totals['vfx'][1]} 張）", rows))

    # 2026-11-27 owner decision: force/state labels are text only; no UI icons.
    rows = list(UI_FILES)
    sections.append(("介面", rows))

    counts = {"有": 0, "有，未達標": 0, "待驗收": 0, "缺": 0}
    for title, rows in sections:
        shown = [(path, spec, where, status(path)) for path, spec, where in rows]
        for row in shown:
            counts[row[3]] += 1
        if only_missing:
            shown = [row for row in shown if row[3] != "有"]
        if not shown:
            continue
        print(f"### {title}\n")
        print("| 檔案 | 規格 | 用在哪裡 | 狀態 |")
        print("| --- | --- | --- | --- |")
        for path, spec, where, state in shown:
            print(f"| `{path}` | {spec} | {where} | {state} |")
        print()
    print(f"合計：有 {counts['有']}，有但未達標 {counts['有，未達標']}，待驗收 {counts['待驗收']}，缺 {counts['缺']}。")
    low = sum(v[0] for v in totals.values())
    high = sum(v[1] for v in totals.values())
    print(f"\n逐格的圖（角色動作、特寫、特效）至少 {low} 張，照建議畫是 {high} 張。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

