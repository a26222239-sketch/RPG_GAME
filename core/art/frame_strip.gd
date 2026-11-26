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


## 這組圖要怎麼播。動作的節奏由美術決定，寫在 meta.json；沒寫的才用預設值。
## base_length 是這個動作預設的長度（秒）；impact_ratio 是沒有指定時，「打到」的瞬間落在整段的幾成。
## meta 是美術為這個動作寫的設定，每個欄位都可以省略：
##   timings_ms    每一格各停幾毫秒，一格一個數字。有這個就照它播，快慢可以不平均。
##   fps           每秒播幾格（每格一樣久）。沒有 timings_ms 時才看這個。
##   impact_time   「打到」的瞬間是開始後第幾秒。
##   impact_frame  或者寫第幾格是「打到」的瞬間；程式取那一格開始的時間。
## 兩種速度都沒寫的話，把所有格子平均排進 base_length。
## index_base 是 impact_frame 從幾算起：1（第一格是 1）或 0（第一格是 0）。
## 回傳 { length, impact, ends }：length 與 impact 的單位是秒；ends[i] 是第 i 格播完的時間。
static func timing(frames: int, base_length: float, impact_ratio: float, meta: Dictionary, index_base: int = 1) -> Dictionary:
	var total := maxi(frames, 1)
	var steps: Array[float] = []
	var written: Variant = meta.get("timings_ms")
	if written is Array and (written as Array).size() == total:
		for value: Variant in written:
			if (value is float or value is int) and float(value) > 0.0:
				steps.append(float(value) / 1000.0)
	if steps.size() != total:
		var fps := float(meta.get("fps", 0.0))
		var step := 1.0 / fps if fps > 0.0 else maxf(base_length, 0.05) / total
		steps.clear()
		for index in total:
			steps.append(step)
	var ends: Array[float] = []
	var clock := 0.0
	for step in steps:
		clock += step
		ends.append(clock)
	var impact := clock * clampf(impact_ratio, 0.0, 1.0)
	if meta.get("impact_time") is float or meta.get("impact_time") is int:
		impact = clampf(float(meta["impact_time"]), 0.0, clock)
	elif meta.get("impact_frame") is float or meta.get("impact_frame") is int:
		var index := clampi(int(meta["impact_frame"]) - index_base, 0, total - 1)
		impact = 0.0 if index == 0 else ends[index - 1]
	return {"length": clock, "impact": impact, "ends": ends}


## 播到第幾秒時該顯示第幾格（從 0 算起）。ends 是 timing() 回傳的每格結束時間。
static func frame_at(time: float, ends: Array, mode: String) -> int:
	if ends.is_empty():
		return 0
	var length: float = ends[ends.size() - 1]
	var clock := maxf(time, 0.0)
	if mode == LOOP:
		clock = fmod(clock, length)
	for index in ends.size():
		if clock < float(ends[index]):
			return index
	return ends.size() - 1


## 橫排圖上第 index 格的範圍（像素）。
static func region(index: int, height: int) -> Rect2:
	return Rect2(index * height, 0, height, height)
