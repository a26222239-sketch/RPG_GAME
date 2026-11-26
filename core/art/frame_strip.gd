extends RefCounted
## 橫排逐格圖的規則（設計文件 15.6、15.9）。只做計算，不碰圖檔。
##
## 一張圖由左到右排著等寬的正方形格子，所以格數 = 圖寬 ÷ 圖高。
## 圖可以畫成任何解析度（512、1024…），只要每一格是正方形。
## 只有一格也可以：那是一個定格的姿勢，停滿這個動作該有的時間。
## 也可以一格交一個檔（檔名加上 _01、_02…），讀檔的部分在 scenes/battle/frame_set.gd。

## 播到最後一格之後：接回第一格、停在最後一格、或是結束。
const LOOP := "loop"
const HOLD := "hold"
const ONCE := "once"

## 一張橫排圖最寬可以多少像素。再寬，顯示卡會載不進去；超過的請改成一格一個檔。
const MAX_STRIP_WIDTH := 16384


## 這張圖有幾格。尺寸不合規格時回傳 0。
static func count(width: int, height: int) -> int:
	if problem(width, height) != "":
		return 0
	return int(width / float(height))


## 尺寸哪裡不合規格。沒問題時回傳空字串。
static func problem(width: int, height: int) -> String:
	if width <= 0 or height <= 0:
		return "圖是空的"
	if width < height:
		return "圖的寬 %d 比高 %d 小，不是橫排的逐格圖" % [width, height]
	if width % height != 0:
		return "圖的寬 %d 不是高 %d 的整數倍，每一格必須是正方形" % [width, height]
	return ""


## 一格一個檔的交法：第 number 格的檔名（不含副檔名），序號兩位數、從 1 算起。
static func numbered(base: String, number: int) -> String:
	return "%s_%02d" % [base, number]


## 一格一個檔的交法：這個檔的尺寸哪裡不合規格。side 是同一組第一格的邊長。
static func single_problem(width: int, height: int, side: int) -> String:
	if width <= 0 or height <= 0:
		return "圖是空的"
	if width != height:
		return "圖是 %d×%d，一格一個檔的時候每個檔必須是正方形" % [width, height]
	if width != side:
		return "圖的邊長 %d 和同一組的第一格 %d 不一樣" % [width, side]
	return ""


## 這組圖要怎麼播。
## base_length 是這個動作預設的長度（秒）；impact_ratio 是沒有指定時，「打到」的瞬間落在整段的幾成。
## meta 是美術在 meta.json 裡寫的設定，兩個欄位都可以省略：
##   fps           每秒播幾格。沒寫的話，把所有格子平均排進 base_length。
##   impact_frame  第幾格是「打到」的瞬間，從 1 算起。
## 回傳 { fps, length, impact }，length 與 impact 的單位是秒。
static func timing(frames: int, base_length: float, impact_ratio: float, meta: Dictionary) -> Dictionary:
	var total := maxi(frames, 1)
	var fps := float(meta.get("fps", 0.0))
	if fps <= 0.0:
		fps = total / maxf(base_length, 0.05)
	var length := total / fps
	var impact := length * clampf(impact_ratio, 0.0, 1.0)
	var impact_frame := int(meta.get("impact_frame", 0))
	if impact_frame >= 1:
		impact = (mini(impact_frame, total) - 1) / fps
	return {"fps": fps, "length": length, "impact": impact}


## 播到第幾秒時該顯示第幾格（從 0 算起）。
static func frame_at(time: float, fps: float, frames: int, mode: String) -> int:
	var total := maxi(frames, 1)
	var index := int(floor(maxf(time, 0.0) * fps))
	if mode == LOOP:
		return index % total
	return mini(index, total - 1)


## 橫排圖上第 index 格的範圍（像素）。
static func region(index: int, height: int) -> Rect2:
	return Rect2(index * height, 0, height, height)
