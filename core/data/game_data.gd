extends RefCounted
## 遊戲內容資料：角色、招式、文字。
## 這一層不碰畫面，可以在無視窗模式下載入與驗證。

const JsonLoader := preload("res://core/data/json_loader.gd")

const CHARACTERS_PATH := "res://data/characters.json"
const MOVES_PATH := "res://data/moves.json"
const TEXT_PATH := "res://data/text/zh_TW.json"
const VFX_PATH := "res://data/vfx.json"
const SCRIPTED_DIR := "res://data/scripted/"

const SIDES := ["party", "enemy"]
const MOVE_KINDS := ["attack", "heal", "buff", "control"]
const FORCES := ["gang", "rou", "kuai", ""]
const ANIMS := [
	"idle", "ready", "charge", "attack_light", "attack_heavy", "cast",
	"hit", "guard", "stagger", "down", "victory", "walk",
]
const REACHES := ["melee", "ranged", "self"]
## 多個招式共用的特效（設計文件 15.9）。招式的 fx 欄位填這裡的其中一個；
## 有專屬特效的招式（絕招）則填招式自己的識別碼。
const SHARED_FX := ["slash_sword", "slash_blade", "palm", "seal", "heal", "buff", "debuff"]
## 特效怎麼對位。hit：格子正中對準命中點。body：照角色格子的對位，套在一個人身上。
const VFX_ANCHORS := ["hit", "body"]

var characters: Dictionary = {}
var moves: Dictionary = {}
var texts: Dictionary = {}
## 特效的播放設定（data/vfx.json）。這是程式這一邊的設定；特效圖本身在 assets/vfx/。
##   frame         一格在畫面上的邊長（設計解析度的像素）
##   anchor        對位，見 VFX_ANCHORS
##   length        播一輪的秒數
##   loop          循環播放（省略就是播一次）
##   tint          染色：force 用招式勁路的顏色，none 不染，或直接寫 #rrggbb
##   impact_frame  第幾格是命中的瞬間（從 1 算起，可省略）；美術可以在 assets/vfx/meta.json 改寫
##   own_size      套在人身上的特效預設會跟著那個人的格子放大（首領是 1.5 倍）；
##                 為某一個人量身畫的填 true，照原尺寸顯示
##   frames        建議的格數，只給需求清單用
var vfx: Dictionary = {}
var errors: Array[String] = []


## 載入全部資料並驗證。有任何問題就回傳 false，細節在 errors。
func load_all() -> bool:
	errors.clear()
	characters = _load_dict(CHARACTERS_PATH)
	moves = _load_dict(MOVES_PATH)
	texts = _load_dict(TEXT_PATH)
	vfx = _load_dict(VFX_PATH)
	if not errors.is_empty():
		return false
	_validate()
	return errors.is_empty()


func load_scripted(script_id: String) -> Dictionary:
	var path := SCRIPTED_DIR + script_id + ".json"
	var data: Variant = JsonLoader.load_file(path)
	if data == null:
		errors.append(JsonLoader.last_error)
		return {}
	if not data is Dictionary:
		errors.append("%s 的最外層必須是物件" % path)
		return {}
	return data


func has_text(key: String) -> bool:
	return texts.has(key)


## 找不到鍵時回傳鍵本身，畫面上一眼就看得出缺了哪一筆。
func text(key: String) -> String:
	return str(texts.get(key, key))


func character_name(char_id: String) -> String:
	var c: Dictionary = characters.get(char_id, {})
	return text(str(c.get("name", char_id)))


func move_name(move_id: String) -> String:
	var m: Dictionary = moves.get(move_id, {})
	return text(str(m.get("name", move_id)))


func _load_dict(path: String) -> Dictionary:
	var data: Variant = JsonLoader.load_file(path)
	if data == null:
		errors.append(JsonLoader.last_error)
		return {}
	if not data is Dictionary:
		errors.append("%s 的最外層必須是物件" % path)
		return {}
	return data


func _validate() -> void:
	for key: String in texts:
		if not texts[key] is String:
			errors.append("文字表：%s 的內容必須是字串" % key)

	for move_id: String in moves:
		var m: Variant = moves[move_id]
		var where := "招式 %s" % move_id
		if not m is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(m, "name", where)
		_require_enum(m, "kind", MOVE_KINDS, where)
		_require_enum(m, "force", FORCES, where)
		_require_enum(m, "anim", ANIMS, where)
		_require_enum(m, "reach", REACHES, where)
		if not SHARED_FX.has(m.get("fx")) and m.get("fx") != move_id:
			errors.append("%s：fx 必須是共用特效 %s 之一，或是招式自己的識別碼" % [where, str(SHARED_FX)])
		elif not vfx.has(m.get("fx")):
			errors.append("%s：特效 %s 沒有寫在 %s" % [where, str(m.get("fx")), VFX_PATH])

	for fx_id: String in vfx:
		var f: Variant = vfx[fx_id]
		var where := "特效 %s" % fx_id
		if not f is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_enum(f, "anchor", VFX_ANCHORS, where)
		for field: String in ["frame", "length"]:
			if not (f.get(field) is float or f.get(field) is int) or float(f.get(field)) <= 0.0:
				errors.append("%s：%s 必須是正數" % [where, field])
		var tint: Variant = f.get("tint")
		if not tint is String or not (tint in ["force", "none"] or Color.html_is_valid(str(tint))):
			errors.append("%s：tint 必須是 force、none 或 #rrggbb" % where)

	for char_id: String in characters:
		var c: Variant = characters[char_id]
		var where := "角色 %s" % char_id
		if not c is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(c, "name", where)
		_require_enum(c, "side", SIDES, where)
		if not c.get("color") is String or not Color.html_is_valid(str(c.get("color"))):
			errors.append("%s：color 必須是 #rrggbb" % where)
		for field: String in ["hp_max", "mp_max"]:
			if not (c.get(field) is float or c.get(field) is int) or float(c.get(field)) <= 0.0:
				errors.append("%s：%s 必須是正數" % [where, field])
		if not c.get("moves") is Array:
			errors.append("%s：moves 必須是陣列" % where)
			continue
		if (c["moves"] as Array).size() > 6:
			errors.append("%s：出戰招式最多 6 個" % where)
		for move_id: Variant in c["moves"]:
			if not moves.has(move_id):
				errors.append("%s：找不到招式 %s" % [where, str(move_id)])


func _require_text(d: Dictionary, field: String, where: String) -> void:
	var key: Variant = d.get(field)
	if not key is String:
		errors.append("%s：缺少 %s" % [where, field])
	elif not texts.has(key):
		errors.append("%s：文字表裡沒有 %s" % [where, key])


func _require_enum(d: Dictionary, field: String, allowed: Array, where: String) -> void:
	var value: Variant = d.get(field, "")
	if not allowed.has(value):
		errors.append("%s：%s 的值「%s」不在允許範圍 %s" % [where, field, str(value), str(allowed)])
