# 人物與立繪對照

四位主角各有初期與全盛造型，天魔殷九淵有一套，共五人、九套。初期對應重生後的三年前，全盛對應序章的最終戰。

![五位人物與九套立繪](character_overview.jpg)

點選下表的圖片可開啟 1024 × 1536 透明 PNG 原圖。沈清禾採用深梅衣裝與燕尾銀簪的新版，溫蘅採用清麗眉眼、杏花金釵與花瓣針匣的新版。

| 人物與身分 | 初期・三年前 | 全盛・序章 |
| --- | --- | --- |
| **燕回**<br>主角・歸元訣・劍 | [![燕回・初期](previews/yanhui.jpg)](../characters/yanhui/design/main.png)<br>`yanhui` | [![燕回・全盛](previews/yanhui_peak.jpg)](../characters/yanhui_peak/design/main.png)<br>`yanhui_peak` |
| **沈清禾**<br>華山派劍客・快・劍 | [![沈清禾・初期](previews/shen.jpg)](../characters/shen/design/main.png)<br>`shen` | [![沈清禾・全盛](previews/shen_peak.jpg)](../characters/shen_peak/design/main.png)<br>`shen_peak` |
| **霍嶽**<br>黑水寨刀客・剛・刀 | [![霍嶽・初期](previews/huo.jpg)](../characters/huo/design/main.png)<br>`huo` | [![霍嶽・全盛](previews/huo_peak.jpg)](../characters/huo_peak/design/main.png)<br>`huo_peak` |
| **溫蘅**<br>杏林谷醫者・柔・針 | [![溫蘅・初期](previews/wen.jpg)](../characters/wen/design/main.png)<br>`wen` | [![溫蘅・全盛](previews/wen_peak.jpg)](../characters/wen_peak/design/main.png)<br>`wen_peak` |
| **殷九淵**<br>天魔神教教主・掌 | — | [![殷九淵・序章](previews/tianmo.jpg)](../characters/tianmo/design/main.png)<br>`tianmo` |

## 設定與交接

- [素材索引與配色](characters.md)列出九套造型各自的全身、背面、臉部特寫與色票，共 27 張角色原圖。
- [六頁角色設定冊](rpg_character_art_v02.pdf)收錄各角度、色碼與隊伍合成。
- [天魔殿隊伍預覽](tianmo_party_16_9.jpg)呈現四名同伴與天魔的靜態站位。

人物姓名對應專案的 `CHAR_YANHUI`、`CHAR_SHEN`、`CHAR_HUO`、`CHAR_WEN`、`CHAR_TIANMO`。序章造型識別碼與 `data/characters.json` 一致，初期造型沿用設計文件約定的識別碼。

本目錄收錄風格指南與角色設定的說明。遊戲內的動畫與表情立繪依[設計文件第 15 章](../../docs/design.md#15-gpt-負責的工作)接續製作與驗收。這批原圖已於 2026-11-26 驗收，從 `assets/incoming/` 移到 `assets/characters/{識別碼}/design/`，並接進序章；經過與結果見[設計文件 15.14](../../docs/design.md#1514-驗收紀錄)。設定圖與本目錄各有 `.gdignore`，不會被 Godot 匯入；遊戲用的站姿與頭像由 `tools/prepare_art.py` 從設定圖產生。
