extends RefCounted
## 讀一組逐格圖（角色的一個動作，或一組特效），整理成一格一張的貼圖。
##
## 美術可以用兩種方式交（設計文件 15.6）：
##   {名稱}.png          一張橫排圖：格子由左到右是播放順序，每格是正方形
##   {名稱}_01.png 起    一格一個檔：序號兩位數、從 01 開始、中間不跳號，每個檔是同樣大小的正方形
## 兩種都有的話用橫排圖。

const FrameStrip := preload("res://core/art/frame_strip.gd")

const MAX_FRAMES := 99


## base 是不含副檔名的路徑，例如 res://assets/vfx/slash_sword。
## 沒有圖時回傳空陣列。圖不合規格時也回傳空陣列，原因寫進警告訊息。
static func load_frames(base: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var strip_path := base + ".png"
	if ResourceLoader.exists(strip_path):
		var strip: Texture2D = load(strip_path)
		if strip == null:
			return frames
		var problem := FrameStrip.problem(strip.get_width(), strip.get_height())
		if problem != "":
			push_warning("%s：%s" % [strip_path, problem])
			return frames
		for index in FrameStrip.count(strip.get_width(), strip.get_height()):
			var cell := AtlasTexture.new()
			cell.atlas = strip
			cell.region = FrameStrip.region(index, strip.get_height())
			cell.filter_clip = true
			frames.append(cell)
		return frames

	for number in range(1, MAX_FRAMES + 1):
		var path := FrameStrip.numbered(base, number) + ".png"
		if not ResourceLoader.exists(path):
			break
		var texture: Texture2D = load(path)
		if texture == null:
			return []
		var first := Vector2i(texture.get_size()) if frames.is_empty() else Vector2i(frames[0].get_size())
		var problem := FrameStrip.single_problem(texture.get_width(), texture.get_height(), first.x)
		if problem != "":
			push_warning("%s：%s" % [path, problem])
			return []
		frames.append(texture)
	return frames
