#!/usr/bin/env python3
"""檢查角色動作、特效、大招特寫合不合允收標準（docs/animation_spec.md 第 8 節）。

用法（在專案根目錄）：
    python3 tools/check_frames.py                         檢查遊戲正式資料夾 assets/ 裡的圖
    python3 tools/check_frames.py assets/incoming/batch_02 檢查一批交付；資料夾結構和 assets/ 相同
    python3 tools/check_frames.py --only shen_peak        只看某個角色（或某組特效）
    python3 tools/check_frames.py --md                    輸出成 Markdown 表格

會看的檔案：
    characters/{識別碼}/frames/{動作}.png（或 {動作}_01.png 起），以及同一個資料夾的 meta.json
    vfx/{特效}.png（或 {特效}_01.png 起），以及 vfx/meta.json
    characters/{識別碼}/cutin/{招式識別碼}_01.png 起

張數與門檻寫在 tools/anim_spec.json。只檢查量得出來的項目；
動作順不順、像不像本人、手指有沒有多，要看錄影（文件第 8.2 節）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPEC = json.loads((ROOT / "tools" / "anim_spec.json").read_text(encoding="utf-8"))
MOVES = json.loads((ROOT / "data" / "moves.json").read_text(encoding="utf-8"))
CHARACTERS = json.loads((ROOT / "data" / "characters.json").read_text(encoding="utf-8"))
VFX = json.loads((ROOT / "data" / "vfx.json").read_text(encoding="utf-8"))

FEET_MARGIN = 32
SAME = 0.005  # 人形範圍內不同的像素少於這個比例，就當成同一張圖


# ---------------------------------------------------------------- 讀圖

def load_set(folder: Path, name: str) -> tuple[list[np.ndarray], str]:
    """讀一組逐格圖：橫排圖 {name}.png，或一格一個檔 {name}_01.png 起。回傳每一格（RGBA，0–255 浮點）。"""
    strip = folder / f"{name}.png"
    if strip.exists():
        image = np.asarray(Image.open(strip).convert("RGBA")).astype(np.float32)
        side = image.shape[0]
        if image.shape[1] % side != 0:
            raise ValueError(f"圖寬 {image.shape[1]} 不是高 {side} 的整數倍，格子不是正方形")
        return [image[:, k * side:(k + 1) * side] for k in range(image.shape[1] // side)], strip.name
    frames = []
    number = 1
    while (folder / f"{name}_{number:02d}.png").exists():
        frames.append(np.asarray(Image.open(folder / f"{name}_{number:02d}.png").convert("RGBA")).astype(np.float32))
        number += 1
    if not frames:
        raise FileNotFoundError(name)
    return frames, f"{name}_01.png 到 _{number - 1:02d}.png"


def set_names(folder: Path) -> list[str]:
    """資料夾裡有哪幾組逐格圖（去掉 _01 這類序號）。"""
    names = set()
    for path in folder.glob("*.png"):
        match = re.fullmatch(r"(.+)_(\d\d)", path.stem)
        names.add(match.group(1) if match else path.stem)
    return sorted(names)


def read_meta(folder: Path) -> dict:
    path = folder / "meta.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return {"_error": str(error)}


# ---------------------------------------------------------------- 量測

def opaque(frame: np.ndarray) -> np.ndarray:
    return frame[..., 3] > 128


def change(a: np.ndarray, b: np.ndarray) -> float:
    """兩張圖的人形輪廓變化：1 − 重疊的比例。0 是完全一樣，1 是完全不重疊。"""
    ma, mb = opaque(a), opaque(b)
    union = (ma | mb).sum()
    return 0.0 if union == 0 else float(1.0 - (ma & mb).sum() / union)


def same(a: np.ndarray, b: np.ndarray) -> bool:
    if a.shape != b.shape:
        return False
    union = (a[..., 3] > 0) | (b[..., 3] > 0) if a.shape[2] == 4 and a[..., 3].min() < 255 else np.ones(a.shape[:2], bool)
    if not union.any():
        return True
    differs = np.abs(a - b).max(axis=2) > 8
    return float(differs[union].mean()) < SAME


def unique_count(frames: list[np.ndarray]) -> int:
    kept: list[np.ndarray] = []
    for frame in frames:
        if not any(same(frame, other) for other in kept):
            kept.append(frame)
    return len(kept)


def feet_row(frame: np.ndarray) -> int | None:
    rows = np.where(opaque(frame).any(axis=1))[0]
    return None if rows.size == 0 else int(rows.max()) + 1


def top_row(frame: np.ndarray) -> int | None:
    rows = np.where(opaque(frame).any(axis=1))[0]
    return None if rows.size == 0 else int(rows.min())


def brightness(frame: np.ndarray) -> float:
    rgb = frame[..., :3].mean(axis=2)
    return float((rgb * frame[..., 3] / 255.0).sum())


def timing(count: int, default_length: float, meta: dict, base: int) -> tuple[list[float], float | None, str]:
    """和遊戲的播放規則相同（core/art/frame_strip.gd）：每格的秒數，以及出手點（秒）。"""
    steps: list[float] = []
    note = ""
    written = meta.get("timings_ms")
    if isinstance(written, list) and len(written) == count and all(isinstance(v, (int, float)) and v > 0 for v in written):
        steps = [v / 1000.0 for v in written]
        note = "照 timings_ms"
    elif isinstance(meta.get("fps"), (int, float)) and meta["fps"] > 0:
        steps = [1.0 / meta["fps"]] * count
        note = f"照 fps {meta['fps']}"
    else:
        steps = [default_length / count] * count
        note = f"沒寫速度，平均排進預設的 {default_length} 秒"
        if isinstance(written, list):
            note = f"timings_ms 有 {len(written)} 個數字、圖有 {count} 張，對不上，" + note
    impact = None
    if isinstance(meta.get("impact_time"), (int, float)):
        impact = float(meta["impact_time"])
    elif isinstance(meta.get("impact_frame"), int):
        index = min(max(meta["impact_frame"] - base, 0), count - 1)
        impact = sum(steps[:index])
    return steps, impact, note


def frame_index_at(steps: list[float], moment: float) -> int:
    clock = 0.0
    for index, step in enumerate(steps):
        clock += step
        if moment < clock - 1e-9:
            return index
    return len(steps) - 1


def listed(meta: dict, key: str, base: int) -> set[int]:
    values = meta.get(key, [])
    return {int(v) - base for v in values if isinstance(v, int)} if isinstance(values, list) else set()


# ---------------------------------------------------------------- 檢查

@dataclass
class Report:
    subject: str
    source: str
    summary: str = ""
    results: list[tuple[str, bool, str]] = field(default_factory=list)

    def add(self, name: str, ok: bool, detail: str = "") -> None:
        self.results.append((name, ok, detail))

    @property
    def passed(self) -> bool:
        return all(ok for _, ok, _ in self.results)


def classify(name: str) -> tuple[str, dict] | None:
    actions = SPEC["actions"]
    if name in actions:
        return name, actions[name]
    move = MOVES.get(name)
    if move:
        kind = {"ultimate": "ultimate", "skill": "attack_heavy", "basic": "attack_light"}.get(move.get("class", ""), "attack_heavy")
        return kind, actions[kind]
    return None


def check_action(character: str, folder: Path, name: str, meta_all: dict, reference: np.ndarray | None) -> Report:
    found = classify(name)
    try:
        frames, source = load_set(folder, name)
    except (ValueError, FileNotFoundError) as error:
        report = Report(f"{character}/{name}", name)
        report.add("讀得到", False, str(error))
        return report
    report = Report(f"{character}/{name}", source)
    if found is None:
        report.add("檔名", False, "不是動畫契約裡的動作，也不是招式識別碼")
        return report
    kind, spec = found
    base = int(meta_all.get("frame_index_base", 1))
    meta = meta_all.get(name, {}) if isinstance(meta_all.get(name), dict) else {}
    standard = 768 if CHARACTERS.get(character, {}).get("boss") else 512
    side = frames[0].shape[0]
    scale = side / standard
    count = len(frames)
    drawings = unique_count(frames)
    steps, impact, note = timing(count, float(spec["default"]), meta, base)
    length = sum(steps)
    report.summary = f"{spec['title']}：{count} 格、{drawings} 張不同的圖、{length:.2f} 秒（{note}）"

    # 1. 規格
    ok = all(f.shape[0] == f.shape[1] == side for f in frames) and side in (standard, standard * 2)
    report.add("格子尺寸", ok, f"每格 {side}×{frames[0].shape[1]}，規格是 {standard} 或 {standard * 2} 的正方形")
    corners = [f[0, 0, 3] for f in frames] + [f[0, -1, 3] for f in frames]
    report.add("真的透明", max(corners) == 0, "格子的四角要完全透明")

    # 2. 張數
    report.add("張數", drawings >= spec["min"], f"{drawings} 張不同的圖，至少 {spec['min']} 張（建議 {spec['rec']}）")
    repeats = [f"第 {i + 1}、{i + 2} 格" for i in range(count - 1) if same(frames[i], frames[i + 1])]
    report.add("沒有連續重複的格", not repeats, "、".join(repeats) + " 是同一張圖；要停久一點請改 timings_ms，或畫成會動的停頓" if repeats else "")

    # 3. 時間
    slow = [i + 1 for i, step in enumerate(steps) if step * 1000 > SPEC["frame_ms"]["max"] + 0.5]
    report.add("每張停的時間", not slow, f"最長 {max(steps) * 1000:.0f} 毫秒，上限 {SPEC['frame_ms']['max']}" + (f"；超過的是第 {'、'.join(map(str, slow))} 格" if slow else ""))
    low, high = spec["length"]
    loop_part = length
    entry = int(spec.get("entry", 0))
    if spec.get("loop") and entry:
        loop_part = sum(steps[entry:]) if count > entry else length
    report.add("總長度", low - 0.01 <= loop_part <= high + 0.01, f"{loop_part:.2f} 秒，範圍 {low}–{high}" + ("（只算循環的那一段）" if entry else ""))

    # 4. 連貫
    continuity = SPEC["continuity"]
    smears = listed(meta, "smear_frames", base)
    jumps = []
    smear_used = 0
    pairs = list(range(count - 1))
    loop_from = int(meta.get("loop_from", base + entry)) - base if spec.get("loop") else None
    for i in pairs:
        value = change(frames[i], frames[i + 1])
        limit = continuity["normal"]
        if i in smears or i + 1 in smears:
            limit = continuity["smear"]
            if value > continuity["normal"]:
                smear_used += 1
        if value > limit + 1e-6:
            jumps.append(f"第 {i + 1}→{i + 2} 格 {value:.2f}")
    if loop_from is not None and count > 1:
        value = change(frames[-1], frames[loop_from])
        if value > continuity["normal"] + 1e-6:
            jumps.append(f"最後一格接回第 {loop_from + 1} 格 {value:.2f}")
    worst = max((change(frames[i], frames[i + 1]) for i in pairs), default=0.0)
    report.add("相鄰兩張不跳", not jumps and smear_used <= continuity["smear_pairs"],
               f"最大變化 {worst:.2f}，上限 {continuity['normal']}（拖影 {continuity['smear']}）" + ("；跳太大：" + "、".join(jumps) if jumps else "") +
               (f"；拖影用了 {smear_used} 對，最多 {continuity['smear_pairs']}" if smear_used > continuity["smear_pairs"] else ""))

    # 5. 腳底、大小、不出格
    airborne = listed(meta, "airborne_frames", base)
    expected = (standard - FEET_MARGIN) * scale
    tolerance = SPEC["feet_tolerance"] * scale
    off = []
    for i, frame in enumerate(frames):
        row = feet_row(frame)
        if i not in airborne and (row is None or abs(row - expected) > tolerance):
            off.append(f"第 {i + 1} 格 {row}")
    report.add("腳底在同一條線上", not off, f"應該在 {expected:.0f}±{tolerance:.0f}" + ("；偏掉的：" + "、".join(off[:6]) if off else ""))
    margin = int(SPEC["edge_margin"] * scale)
    touching = [i + 1 for i, f in enumerate(frames) if opaque(f)[:margin].any() or opaque(f)[:, :margin].any() or opaque(f)[:, -margin:].any()]
    report.add("沒有超出格子", not touching, "碰到格子上緣或左右兩邊：第 " + "、".join(map(str, touching)) + " 格" if touching else "")
    if name in ("idle", "ready") and reference is not None:
        ref_height = feet_row(reference) - top_row(reference)
        heights = [feet_row(f) - top_row(f) for f in frames if feet_row(f) is not None]
        worst_ratio = max(abs(h / ref_height - 1.0) for h in heights) if heights else 1.0
        report.add("人的大小和站姿一致", worst_ratio <= SPEC["height_tolerance"] + 1e-6,
                   f"身高最多差 {worst_ratio * 100:.1f}%，上限 {SPEC['height_tolerance'] * 100:.0f}%")

    # 6. 首尾銜接
    if reference is not None and reference.shape == frames[0].shape:
        limit = continuity["return"]
        if spec.get("impact_first"):
            away = [change(f, reference) for f in frames]
            strongest = int(np.argmax(away))
            report.add("第一格就是挨打最重的一下", strongest <= 1 and away[0] >= continuity["normal"],
                       f"離待機最遠的是第 {strongest + 1} 格；第一格和待機差 {away[0]:.2f}，至少 {continuity['normal']}")
        if spec.get("starts_idle"):
            value = change(frames[0], reference)
            report.add("第一格接得上待機", value <= limit, f"和待機第一格差 {value:.2f}，上限 {limit}")
        if spec.get("ends_idle"):
            value = change(frames[-1], reference)
            report.add("最後一格回到待機", value <= limit, f"和待機第一格差 {value:.2f}，上限 {limit}")

    # 7. 出手點
    if "before" in spec:
        if impact is None:
            report.add("標了出手點", False, "meta.json 要寫 impact_frame 或 impact_time")
        else:
            index = frame_index_at(steps, impact)
            before = unique_count(frames[:index])
            after = unique_count(frames[index + 1:])
            report.add("出手前後的張數", before >= spec["before"] and after >= spec["after"],
                       f"出手點在第 {index + 1} 格；之前 {before} 張（至少 {spec['before']}），之後 {after} 張（至少 {spec['after']}）")
    return report


def check_vfx(folder: Path, name: str, meta_all: dict) -> Report:
    try:
        frames, source = load_set(folder, name)
    except (ValueError, FileNotFoundError) as error:
        report = Report(f"vfx/{name}", name)
        report.add("讀得到", False, str(error))
        return report
    report = Report(f"vfx/{name}", source)
    settings = VFX.get(name)
    if settings is None:
        report.add("檔名", False, "data/vfx.json 沒有這一組特效")
        return report
    kind = SPEC["vfx_kinds"].get(name, "ultimate")
    spec = SPEC["vfx"][kind]
    base = int(meta_all.get("frame_index_base", 1))
    meta = meta_all.get(name, {}) if isinstance(meta_all.get(name), dict) else {}
    count = len(frames)
    drawings = unique_count(frames)
    if "impact_frame" not in meta and "impact_time" not in meta and "impact_frame" in settings:
        meta = dict(meta, impact_frame=int(settings["impact_frame"]) - 1 + base)
    steps, impact, note = timing(count, float(settings["length"]), meta, base)
    report.summary = f"{spec['title']}：{count} 格、{drawings} 張不同的圖、{sum(steps):.2f} 秒（{note}）"

    side = frames[0].shape[0]
    standard = int(settings["frame"])
    report.add("格子尺寸", side in (standard, standard * 2), f"每格 {side}，規格是 {standard} 或 {standard * 2} 的正方形")
    report.add("張數", drawings >= spec["min"], f"{drawings} 張不同的圖，至少 {spec['min']} 張（建議 {spec['rec']}）")
    slow = [i + 1 for i, step in enumerate(steps) if step * 1000 > SPEC["frame_ms"]["max"] + 0.5]
    report.add("每張停的時間", not slow, f"最長 {max(steps) * 1000:.0f} 毫秒，上限 {SPEC['frame_ms']['max']}")
    low, high = spec["length"]
    report.add("總長度", low - 0.01 <= sum(steps) <= high + 0.01, f"{sum(steps):.2f} 秒，範圍 {low}–{high}")

    light = [brightness(f) for f in frames]
    peak = int(np.argmax(light))
    if not spec.get("loop"):
        if impact is not None and settings["anchor"] == "hit":
            index = frame_index_at(steps, impact)
            report.add("最亮的一格在命中點", abs(peak - index) <= 1, f"最亮的是第 {peak + 1} 格，命中點是第 {index + 1} 格，要在前後一格以內")
        ratio = light[-1] / max(light[peak], 1e-6)
        report.add("最後淡出", ratio <= SPEC["vfx_fade"], f"最後一格的亮度是最亮時的 {ratio * 100:.0f}%，上限 {SPEC['vfx_fade'] * 100:.0f}%")
    else:
        diffs = [float(np.abs(frames[i] - frames[i + 1]).mean()) for i in range(count - 1)]
        seam = float(np.abs(frames[-1] - frames[0]).mean())
        typical = float(np.median(diffs)) if diffs else 0.0
        report.add("循環接得上", seam <= typical * 1.5 + 0.5, f"最後一格接回第一格的變化 {seam:.1f}，一般相鄰兩格約 {typical:.1f}")
    return report


def check_cutin(character: str, folder: Path, name: str) -> Report:
    try:
        frames, source = load_set(folder, name)
    except (ValueError, FileNotFoundError) as error:
        report = Report(f"{character}/cutin/{name}", name)
        report.add("讀得到", False, str(error))
        return report
    spec = SPEC["cutin"]
    report = Report(f"{character}/cutin/{name}", source)
    count = len(frames)
    drawings = unique_count(frames)
    report.summary = f"大招特寫：{count} 格、{drawings} 張不同的圖"
    height, width = frames[0].shape[:2]
    want_w, want_h = spec["size"]
    report.add("尺寸", width >= want_w and abs(width / height - want_w / want_h) < 0.01, f"{width}×{height}，規格 {want_w}×{want_h}（可以更大，比例相同）")
    report.add("每張一樣大", all(f.shape == frames[0].shape for f in frames))
    report.add("不透明", all(f[..., 3].min() >= 250 for f in frames), "特寫是一整條畫面，不要留透明")
    report.add("張數", drawings >= spec["min"], f"{drawings} 張不同的圖，至少 {spec['min']} 張（建議 {spec['rec']}）")
    if count > 2:
        diffs = [float(np.abs(frames[i] - frames[i + 1]).mean()) for i in range(count - 1)]
        seam = float(np.abs(frames[-1] - frames[0]).mean())
        typical = float(np.median(diffs))
        report.add("循環接得上", seam <= typical * 1.5 + 0.5, f"最後一張接回第一張的變化 {seam:.1f}，一般相鄰兩張約 {typical:.1f}")
    return report


# ---------------------------------------------------------------- 主程式

def reference_for(root: Path, character: str) -> np.ndarray | None:
    """首尾銜接與大小的基準：這一批有交待機就用待機第一格，否則用遊戲裡的站姿圖。"""
    for folder in (root / "characters" / character / "frames", ROOT / "assets" / "characters" / character / "frames"):
        try:
            frames, _ = load_set(folder, "idle")
            return frames[0]
        except (ValueError, FileNotFoundError):
            continue
    stand = ROOT / "assets" / "characters" / character / "frames" / "stand.png"
    if not stand.exists():
        return None
    return np.asarray(Image.open(stand).convert("RGBA")).astype(np.float32)


def matching_reference(reference: np.ndarray | None, side: int) -> np.ndarray | None:
    if reference is None or reference.shape[0] == side:
        return reference
    image = Image.fromarray(reference.astype(np.uint8), "RGBA").resize((side, side), Image.LANCZOS)
    return np.asarray(image).astype(np.float32)


def collect(root: Path, only: str | None) -> list[Report]:
    reports: list[Report] = []
    for folder in sorted((root / "characters").glob("*/frames")) if (root / "characters").exists() else []:
        character = folder.parent.name
        if only and only != character:
            continue
        meta = read_meta(folder)
        reference = reference_for(root, character)
        for name in set_names(folder):
            if name == "stand":
                continue
            try:
                side = load_set(folder, name)[0][0].shape[0]
            except (ValueError, FileNotFoundError):
                side = 0
            reports.append(check_action(character, folder, name, meta, matching_reference(reference, side)))
    for folder in sorted((root / "characters").glob("*/cutin")) if (root / "characters").exists() else []:
        character = folder.parent.name
        if only and only != character:
            continue
        for name in set_names(folder):
            reports.append(check_cutin(character, folder, name))
    vfx = root / "vfx"
    if vfx.exists():
        meta = read_meta(vfx)
        for name in set_names(vfx):
            if only and only != name:
                continue
            reports.append(check_vfx(vfx, name, meta))
    return reports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", nargs="?", default=str(ROOT / "assets"), help="資料夾結構和 assets/ 相同的根目錄")
    parser.add_argument("--only", help="只檢查這個角色或這組特效")
    parser.add_argument("--md", action="store_true", help="輸出 Markdown 表格")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    reports = collect(root, args.only)
    if not reports:
        print(f"{root} 底下沒有動作圖、特效圖或特寫。")
        return 0
    failed = 0
    for report in reports:
        failed += 0 if report.passed else 1
        if args.md:
            print(f"**`{report.subject}`** {'通過' if report.passed else '不通過'}　{report.summary}\n")
            print("| 項目 | 結果 | 說明 |\n| --- | --- | --- |")
            for name, ok, detail in report.results:
                print(f"| {name} | {'通過' if ok else '**不通過**'} | {detail} |")
            print()
        else:
            print(f"{'✓' if report.passed else '✗'} {report.subject}（{report.source}）　{report.summary}")
            for name, ok, detail in report.results:
                print(f"    {'通過' if ok else '不通過'}　{name}　{detail}")
    print(f"合計 {len(reports)} 組，通過 {len(reports) - failed}，不通過 {failed}。")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
