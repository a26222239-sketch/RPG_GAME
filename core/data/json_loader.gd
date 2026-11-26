extends RefCounted
## 讀取 JSON 資料檔。
## 讀不到或格式有錯時回傳 null，原因放在 last_error。

static var last_error: String = ""


static func load_file(path: String) -> Variant:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "找不到檔案：%s" % path
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "無法開啟：%s" % path
		return null
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		last_error = "%s 第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()]
		return null
	return json.data
