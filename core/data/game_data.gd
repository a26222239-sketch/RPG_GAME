extends RefCounted
## 遊戲內容資料：角色、招式、文字、特效設定，以及 M1 戰鬥用的內功、狀態、敵人、遭遇。
## 這一層不碰畫面，可以在無視窗模式下載入與驗證。

const JsonLoader := preload("res://core/data/json_loader.gd")

const CHARACTERS_PATH := "res://data/characters.json"
const MOVES_PATH := "res://data/moves.json"
const TEXT_PATH := "res://data/text/zh_TW.json"
const VFX_PATH := "res://data/vfx.json"
const INNER_ARTS_PATH := "res://data/inner_arts.json"
const STATUSES_PATH := "res://data/statuses.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENCOUNTERS_PATH := "res://data/encounters.json"
const SCRIPTED_DIR := "res://data/scripted/"

const SIDES := ["party", "enemy"]
const MOVE_KINDS := ["attack", "heal", "buff", "control"]
const FORCES := ["gang", "rou", "kuai", ""]
const ANIMS := [
	"idle", "ready", "charge", "attack_light", "attack_heavy", "cast",
	"hit", "hit_heavy", "guard", "stagger", "down", "victory", "walk",
]
## 招式的分級：普攻、小招、大招。決定對手挨打的反應（輕或重的受擊）、命中時畫面停多久、大招出手前播特寫。
const MOVE_CLASSES := ["basic", "skill", "ultimate"]
const REACHES := ["melee", "ranged", "self"]
## 戰鬥用的招式欄位（設計文件 5.5）。劇本式戰鬥用的招式不需要這些。
const TARGETS := ["enemy_single", "enemy_all", "ally_single", "ally_all", "self"]
## 招式標籤：interrupt 截招（打蓄招中的人，架勢傷害 ×2.5）；big 大招（敵人蓄這一招時畫面出警示）。
const MOVE_TAGS := ["interrupt", "big"]
const BATTLE_NUMBERS := ["cost", "charge", "recover", "power", "posture"]
const ATTRS := ["jingu", "neixi", "shenfa", "wuxing"]
## 敵人選目標的方式（4.10）。
const TARGETING := ["random", "lowest_hp", "charging"]
## 敵人的條件規則能看的條件。
const RULE_CONDITIONS := ["self_hp_below", "foe_charging"]
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
var vfx: Dictionary = {}
## M1 戰鬥（設計文件第 4、13 章）。
var inner_arts: Dictionary = {}
var statuses: Dictionary = {}
var enemies: Dictionary = {}
var encounters: Dictionary = {}
var errors: Array[String] = []


## 載入全部資料並驗證。有任何問題就回傳 false，細節在 errors。
func load_all() -> bool:
	errors.clear()
	characters = _load_dict(CHARACTERS_PATH)
	moves = _load_dict(MOVES_PATH)
	texts = _load_dict(TEXT_PATH)
	vfx = _load_dict(VFX_PATH)
	inner_arts = _load_dict(INNER_ARTS_PATH)
	statuses = _load_dict(STATUSES_PATH)
	enemies = _load_dict(ENEMIES_PATH)
	encounters = _load_dict(ENCOUNTERS_PATH)
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


func enemy_name(enemy_id: String) -> String:
	var e: Dictionary = enemies.get(enemy_id, {})
	return text(str(e.get("name", enemy_id)))


## 這個角色有沒有能力值，能不能上真正的戰鬥（M1 的測試角色有；序章的全盛造型只演劇本）。
func is_fighter(char_id: String) -> bool:
	var c: Variant = characters.get(char_id)
	return c is Dictionary and (c as Dictionary).has("attrs")


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
		_require_enum(m, "class", MOVE_CLASSES, where)
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
		if c.has("attrs"):
			# 真正戰鬥用的角色：氣血、內力由能力值算出來（3.2）
			_require_attrs(c, where)
			if not inner_arts.has(c.get("inner_art")):
				errors.append("%s：找不到內功心法 %s" % [where, str(c.get("inner_art"))])
		else:
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
			elif c.has("attrs"):
				_require_battle_move(str(move_id), where)

	_validate_battle()


## M1 戰鬥用的資料：內功、狀態、敵人、遭遇。
func _validate_battle() -> void:
	for art_id: String in inner_arts:
		var a: Variant = inner_arts[art_id]
		var where := "內功 %s" % art_id
		if not a is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(a, "name", where)
		_require_inner_art(a, where)

	for status_id: String in statuses:
		var st: Variant = statuses[status_id]
		var where := "狀態 %s" % status_id
		if not st is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(st, "name", where)
		_require_number(st, "duration", where, 0.01)

	for enemy_id: String in enemies:
		var e: Variant = enemies[enemy_id]
		var where := "敵人 %s" % enemy_id
		if not e is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(e, "name", where)
		if not e.get("color") is String or not Color.html_is_valid(str(e.get("color"))):
			errors.append("%s：color 必須是 #rrggbb" % where)
		_require_attrs(e, where)
		if not e.get("inner_art") is Dictionary:
			errors.append("%s：inner_art 必須是物件（force、guard、regen）" % where)
		else:
			_require_inner_art(e["inner_art"], where)
		_require_number(e, "hp_scale", where, 0.01)
		_require_enum(e, "targeting", TARGETING, where)
		var own: Array = []
		if not e.get("moves") is Array or (e["moves"] as Array).is_empty():
			errors.append("%s：moves 必須是非空的陣列" % where)
		else:
			for entry: Variant in e["moves"]:
				if not entry is Dictionary or not moves.has(entry.get("move")):
					errors.append("%s：招式表裡有找不到的招式 %s" % [where, str(entry)])
					continue
				own.append(entry["move"])
				_require_battle_move(str(entry["move"]), where)
				_require_number(entry, "weight", where, 0.01)
		if not e.get("rules", []) is Array or (e.get("rules", []) as Array).size() > 2:
			errors.append("%s：rules 必須是陣列，最多兩條" % where)
			continue
		for rule: Variant in e.get("rules", []):
			if not rule is Dictionary or not rule.get("when") is Dictionary:
				errors.append("%s：規則要有 when 與 use" % where)
				continue
			for condition: String in rule["when"]:
				if not RULE_CONDITIONS.has(condition):
					errors.append("%s：規則的條件 %s 不在 %s" % [where, condition, str(RULE_CONDITIONS)])
			var use := str(rule.get("use", ""))
			if use != "guard" and not own.has(use):
				errors.append("%s：規則用的 %s 不是 guard，也不在自己的招式表裡" % [where, use])

	for encounter_id: String in encounters:
		var enc: Variant = encounters[encounter_id]
		var where := "遭遇 %s" % encounter_id
		if not enc is Dictionary:
			errors.append("%s：必須是物件" % where)
			continue
		_require_text(enc, "name", where)
		if not enc.get("background") is String:
			errors.append("%s：缺少 background" % where)
		var party: Variant = enc.get("party")
		if not party is Array or (party as Array).is_empty() or (party as Array).size() > 4:
			errors.append("%s：party 必須是 1 到 4 人" % where)
		else:
			for member: Variant in party:
				if not is_fighter(str(member)):
					errors.append("%s：%s 不是能上真正戰鬥的角色（要有 attrs）" % [where, str(member)])
		var foes: Variant = enc.get("enemies")
		if not foes is Array or (foes as Array).is_empty() or (foes as Array).size() > 5:
			errors.append("%s：enemies 必須是 1 到 5 個" % where)
		else:
			for foe: Variant in foes:
				if not enemies.has(foe):
					errors.append("%s：找不到敵人 %s" % [where, str(foe)])


func _require_attrs(d: Dictionary, where: String) -> void:
	var attrs: Variant = d.get("attrs")
	if not attrs is Dictionary:
		errors.append("%s：attrs 必須是物件" % where)
		return
	for attr: String in ATTRS:
		_require_number(attrs, attr, "%s 的 attrs" % where, 0.0)


func _require_inner_art(a: Dictionary, where: String) -> void:
	_require_enum(a, "force", ["gang", "rou", "kuai"], where)
	_require_number(a, "guard", where, 0.0)
	_require_number(a, "regen", where, 0.0)


## 上真正戰鬥的招式要有目標與數值。
func _require_battle_move(move_id: String, owner: String) -> void:
	var m: Dictionary = moves[move_id]
	var where := "%s 的招式 %s" % [owner, move_id]
	_require_enum(m, "target", TARGETS, where)
	for field: String in BATTLE_NUMBERS:
		_require_number(m, field, where, 0.0)
	for tag: Variant in m.get("tags", []):
		if not MOVE_TAGS.has(tag):
			errors.append("%s：標籤 %s 不在 %s" % [where, str(tag), str(MOVE_TAGS)])
	for effect: Variant in m.get("effects", []):
		if not effect is Dictionary or not statuses.has(effect.get("status")):
			errors.append("%s：附加效果 %s 的狀態不存在" % [where, str(effect)])
		elif not (effect.get("chance") is float or effect.get("chance") is int) or float(effect["chance"]) <= 0.0 or float(effect["chance"]) > 1.0:
			errors.append("%s：附加效果的 chance 必須在 0 到 1 之間" % where)


func _require_number(d: Dictionary, field: String, where: String, minimum: float) -> void:
	var value: Variant = d.get(field)
	if not (value is float or value is int) or float(value) < minimum:
		errors.append("%s：%s 必須是不小於 %s 的數字" % [where, field, str(minimum)])


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
