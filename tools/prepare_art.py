#!/usr/bin/env python3
"""把角色設定圖整理成遊戲用的圖。

    python3 tools/prepare_art.py            檢查設定圖，並重新產生遊戲用的圖
    python3 tools/prepare_art.py --check    只檢查，不寫檔

讀取（原圖，不會被修改）：
    assets/characters/{識別碼}/design/main.png    全身主視圖
    assets/characters/{識別碼}/design/face.png    臉部特寫

產生：
    assets/characters/{識別碼}/frames/stand.png   戰鬥用的站姿，一格
    assets/characters/{識別碼}/portrait/head.png  對話框用的頭像

站姿圖依設計文件 15.6 的逐格圖規格擺放，解析度是規格的兩倍：
一般角色的格子 1024×1024（規格 512），首領 1536×1536（規格 768）；
腳底落在離格子底邊 64 像素（規格 32）的水平線上，雙腳的中點對齊格子的水平正中。
正式的逐格動畫交付之後，同一個資料夾會多出 idle.png、attack_light.png 等檔案，
stand.png 只在某個動作還沒有圖的時候拿來頂替。

需要 Pillow 與 NumPy。
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CHARACTERS = ROOT / "assets" / "characters"

DESIGN_SIZE = (1024, 1536)
SCALE = 2  # 產出的解析度是設計文件規格的幾倍
FEET_MARGIN = 32  # 規格：腳底離格子底邊的距離
HEAD_SIZE = 384  # 頭像輸出的邊長

# height：站姿在 1080p 畫面上的高度（像素）。四位主角之間的高矮差在這裡決定。
# frame：格子在規格中的邊長，512 是一般角色，768 是首領。
# head：頭像在臉部特寫上的裁切範圍（左, 上, 邊長），單位是原圖像素。
CONFIG = {
    "yanhui_peak": {"height": 400, "frame": 512, "head": (164, 140, 860)},
    "shen_peak": {"height": 392, "frame": 512, "head": (164, 140, 860)},
    "huo_peak": {"height": 412, "frame": 512, "head": (150, 120, 860)},
    "wen_peak": {"height": 382, "frame": 512, "head": (140, 70, 860)},
    "tianmo": {"height": 590, "frame": 768, "head": (164, 140, 860)},
    "yanhui": {"height": 400, "frame": 512, "head": (150, 170, 860)},
    "shen": {"height": 392, "frame": 512, "head": (150, 170, 860)},
    "huo": {"height": 412, "frame": 512, "head": (150, 140, 860)},
    "wen": {"height": 382, "frame": 512, "head": (140, 70, 860)},
}


def check_design(path: Path, full_body: bool) -> list[str]:
    """檢查一張設定圖是否符合設計文件 15.2 的規格。回傳問題清單，空的代表通過。"""
    problems: list[str] = []
    if not path.exists():
        return ["找不到檔案"]
    image = Image.open(path)
    if image.size != DESIGN_SIZE:
        problems.append(f"尺寸是 {image.size[0]}×{image.size[1]}，應為 {DESIGN_SIZE[0]}×{DESIGN_SIZE[1]}")
    if image.mode != "RGBA":
        return problems + [f"色彩模式是 {image.mode}，沒有透明通道"]
    alpha = np.asarray(image.getchannel("A"))
    clear = float((alpha == 0).mean())
    if clear < 0.10:
        problems.append(f"完全透明的面積只有 {clear:.0%}，背景可能不是真的透明")
    if full_body:
        height = alpha.shape[0]
        corners = [int(alpha[0, 0]), int(alpha[0, -1]), int(alpha[-1, 0]), int(alpha[-1, -1])]
        if max(corners) > 8:
            problems.append(f"四個角不透明（{corners}），角色可能貼到圖邊")
        rows = np.where((alpha >= 128).any(axis=1))[0]
        if rows.size == 0:
            return problems + ["整張圖都是透明的"]
        if height - 1 - int(rows[-1]) < 2:
            problems.append("腳底貼到圖的下緣，沒有留白")
    return problems


def clean_alpha(image: Image.Image) -> Image.Image:
    """清掉輪廓外極淡的殘留像素：離實心區域超過 2 像素的地方一律設為全透明。"""
    alpha = image.getchannel("A")
    solid = alpha.point(lambda v: 255 if v >= 128 else 0)
    near = solid.filter(ImageFilter.MaxFilter(5))
    cleaned = Image.composite(alpha, Image.new("L", image.size, 0), near)
    result = image.copy()
    result.putalpha(cleaned)
    return result


def feet_anchor(alpha: np.ndarray) -> tuple[float, int, int]:
    """找出雙腳的中點（x）、腳底（y）與頭頂（y）。"""
    solid = alpha >= 128
    rows = np.where(solid.any(axis=1))[0]
    top, bottom = int(rows[0]), int(rows[-1])
    # 腳底往上取身高的 2.5%，這一段裡有東西的最左與最右取中點
    band = solid[bottom - int((bottom - top) * 0.025) : bottom + 1]
    columns = np.where(band.any(axis=0))[0]
    return (float(columns[0]) + float(columns[-1])) / 2.0, bottom, top


def make_stand(design: Image.Image, height: int, frame: int) -> Image.Image:
    cleaned = clean_alpha(design)
    alpha = np.asarray(cleaned.getchannel("A"))
    center_x, bottom, top = feet_anchor(alpha)
    ratio = (height * SCALE) / float(bottom - top + 1)
    size = (round(cleaned.width * ratio), round(cleaned.height * ratio))
    # Pillow 縮放 RGBA 時會先乘上透明度，邊緣不會出現白邊或黑邊
    scaled = cleaned.resize(size, Image.LANCZOS)
    side = frame * SCALE
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    left = round(side / 2.0 - center_x * ratio)
    upper = round(side - FEET_MARGIN * SCALE - (bottom + 1) * ratio)
    canvas.alpha_composite(scaled, (left, upper))
    box = canvas.getchannel("A").getbbox()
    if box[0] <= 0 or box[2] >= side or box[1] <= 0:
        raise ValueError("角色超出格子，請調整 CONFIG 裡的高度")
    return canvas


def make_head(face: Image.Image, crop: tuple[int, int, int]) -> Image.Image:
    left, upper, side = crop
    region = clean_alpha(face).crop((left, upper, left + side, upper + side))
    return region.resize((HEAD_SIZE, HEAD_SIZE), Image.LANCZOS)


def main() -> int:
    check_only = "--check" in sys.argv[1:]
    failed = False
    for character_id, config in CONFIG.items():
        folder = CHARACTERS / character_id
        report = {
            "main.png": check_design(folder / "design" / "main.png", True),
            "back.png": check_design(folder / "design" / "back.png", True),
            "face.png": check_design(folder / "design" / "face.png", False),
        }
        problems = [f"{name}：{text}" for name, texts in report.items() for text in texts]
        if problems:
            failed = True
            print(f"✗ {character_id}")
            for line in problems:
                print(f"    {line}")
            continue
        if check_only:
            print(f"✓ {character_id}　設定圖三張符合規格")
            continue
        stand = make_stand(Image.open(folder / "design" / "main.png").convert("RGBA"), config["height"], config["frame"])
        head = make_head(Image.open(folder / "design" / "face.png").convert("RGBA"), config["head"])
        (folder / "frames").mkdir(exist_ok=True)
        (folder / "portrait").mkdir(exist_ok=True)
        stand.save(folder / "frames" / "stand.png", optimize=True)
        head.save(folder / "portrait" / "head.png", optimize=True)
        box = stand.getchannel("A").getbbox()
        print(
            f"✓ {character_id}　站姿 {stand.width}×{stand.height}，角色高 {box[3] - box[1]} 像素"
            f"（畫面上 {config['height']}），左右佔 {box[0]}–{box[2]}；頭像 {head.width}×{head.height}"
        )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
