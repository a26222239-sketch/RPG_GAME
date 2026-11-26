"""檢查序章的劇本文件與遊戲資料是否一致。

docs/prologue.md 是給人讀、給人改的劇本；
data/scripted/prologue_final.json 與 data/text/zh_TW.json 是遊戲實際讀的資料。
這支程式逐句比對兩邊的台詞、旁白、字幕、提示與氣血變化，改了一邊忘了另一邊時會指出來。

用法（在專案根目錄）：
    python3 tools/check_prologue.py
全部一致時結束碼為 0。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MD = ROOT / "docs" / "prologue.md"
SCRIPT = ROOT / "data" / "scripted" / "prologue_final.json"
TEXTS = ROOT / "data" / "text" / "zh_TW.json"
CHARACTERS = ROOT / "data" / "characters.json"


def norm(text: str) -> str:
    """比對時不計較句尾有沒有句號，也不計較空白。"""
    return re.sub(r"\s+", "", text).rstrip("。")


def parse_markdown(md: str):
    """把劇本文件拆成 (種類, 說話的人, 文字) 的清單，以及氣血變化的清單。"""
    body = md.split("\n---\n")[1]  # 只看第一條分隔線之後、素材清單之前的劇本本體
    lines, hp_changes = [], []
    for raw in body.split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        said = re.match(r"^\*\*(.+?)\*\*：(.+)$", line)
        if said:
            lines.append(("say", said.group(1), said.group(2)))
        elif line.startswith("〔字幕〕"):
            lines.append(("subtitle", "", line[4:]))
        elif line.startswith("〔提示〕"):
            lines.append(("hint", "", line[4:]))
        elif line.startswith("〔演出〕"):
            lines.append(("narrate", "", line[4:]))
        elif line.startswith("（") and line.endswith("）"):
            lines.append(("narrate", "", line[1:-1]))
        elif line.startswith("〔戰鬥〕"):
            for who, _, to in re.findall(r"(天魔|燕回|沈清禾|霍嶽|溫蘅)[（ ]*(\d+)% → (\d+)%?", line):
                hp_changes.append((who, int(to)))
    return lines, hp_changes


def main() -> int:
    texts = json.loads(TEXTS.read_text(encoding="utf-8"))
    script = json.loads(SCRIPT.read_text(encoding="utf-8"))
    characters = json.loads(CHARACTERS.read_text(encoding="utf-8"))
    md_lines, md_hp = parse_markdown(MD.read_text(encoding="utf-8"))

    name_of = {cid: texts[c["name"]] for cid, c in characters.items()}
    md_name = {"殷九淵": "天魔"}  # 劇本的〔戰鬥〕行用「天魔」稱呼殷九淵

    data_lines, data_hp = [], []
    for beat in script["beats"]:
        kind = beat["type"]
        if kind in ("say", "subtitle", "hint", "narrate"):
            speaker = name_of[beat["who"]] if kind == "say" else ""
            data_lines.append((kind, speaker, texts[beat["text"]]))
        elif kind == "act":
            for unit, change in beat.get("result", {}).items():
                name = name_of[unit]
                data_hp.append((md_name.get(name, name), round(change["hp_to"] * 100)))

    problems = []
    for i in range(max(len(md_lines), len(data_lines))):
        a = md_lines[i] if i < len(md_lines) else None
        b = data_lines[i] if i < len(data_lines) else None
        if a is None or b is None or a[0] != b[0] or a[1] != b[1] or norm(a[2]) != norm(b[2]):
            problems.append(f"第 {i + 1} 句不一致\n    劇本文件：{a}\n    遊戲資料：{b}")
            break  # 第一處不一致之後的錯位沒有參考價值

    # 治療那一拍，劇本只寫「四人回到 80% 上下」，沒有逐人數字，比對時略過。
    heal = {
        (name_of[unit], round(change["hp_to"] * 100))
        for beat in script["beats"]
        if beat["type"] == "act" and beat.get("move") == "wen_bianzhao"
        for unit, change in beat["result"].items()
    }
    data_hp_checked = [x for x in data_hp if x not in heal]
    if md_hp != data_hp_checked:
        problems.append(f"氣血變化不一致\n    劇本文件：{md_hp}\n    遊戲資料：{data_hp_checked}")

    print(f"台詞、旁白、字幕、提示：劇本文件 {len(md_lines)} 句，遊戲資料 {len(data_lines)} 句")
    print(f"氣血變化：劇本文件 {len(md_hp)} 筆，遊戲資料 {len(data_hp_checked)} 筆（另有治療 {len(heal)} 筆不逐一比對）")
    if problems:
        print("\n發現不一致：")
        for p in problems:
            print("  " + p)
        return 1
    print("劇本文件與遊戲資料一致。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
