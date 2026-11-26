extends RefCounted
## 劇本式戰鬥的規則層（設計文件 4.14）。
##
## 整場戰鬥是一份照順序播放的劇本，結果寫在劇本裡，不經過戰鬥規則的計算。
## 這個類別只負責：驗證劇本、逐拍推進、記錄每個人的氣血與內力、
## 告訴畫面層「這一拍玩家該按什麼」。它不碰任何畫面。

const BEAT_TYPES := [
	"subtitle", "narrate", "say", "hint", "act", "command",
	"charge", "state", "fx", "scene", "end",
]
const INPUT_MODES := ["", "full", "tap"]
const COMMANDS := ["guard", "rest", "item", "flee"]
const STATES := ["", "slow", "stagger", "guard"]
const FX_NAMES := ["pin", "release", "collapse", "push_out", "walk_to_enemy", "white_out", "shake"]
const SCENES := ["tianmo_hall", "old_house"]
const TARGET_PARTY := "party"
const TARGET_ENEMIES := "enemies"

var script_id: String = ""
var title_key: String = ""
var background: String = ""
var party: Array[String] = []
var enemies: Array[String] = []
var beats: Array = []
var index: int = -1

## 單位狀態：id -> { hp, mp（0 到 1 的比例）, hp_max, mp_max, side, state, charging }
var units: Dictionary = {}


## 驗證劇本。回傳問題清單，空陣列代表沒有問題。
static func validate(script: Dictionary, characters: Dictionary, moves: Dictionary, texts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var sid := str(script.get("id", "?"))
	var where := "劇本 %s" % sid

	if script.get("mode") != "scripted":
		errors.append("%s：mode 必須是 scripted" % where)
	if not SCENES.has(script.get("background", "")):
		errors.append("%s：background 不在允許範圍 %s" % [where, str(SCENES)])
	if script.has("title") and not texts.has(script["title"]):
		errors.append("%s：文字表裡沒有 %s" % [where, str(script["title"])])

	var sides := {"party": "party", "enemies": "enemy"}
	var unit_ids: Array[String] = []
	for field: String in sides:
		var list: Variant = script.get(field)
		if not list is Array or (list as Array).is_empty():
			errors.append("%s：%s 必須是非空的陣列" % [where, field])
			continue
		for unit_id: Variant in list:
			if not characters.has(unit_id):
				errors.append("%s：%s 裡的 %s 不存在" % [where, field, str(unit_id)])
			elif characters[unit_id].get("side") != sides[field]:
				errors.append("%s：%s 的陣營不是 %s" % [where, str(unit_id), sides[field]])
			else:
				unit_ids.append(str(unit_id))
	if script.get("party") is Array and (script["party"] as Array).size() > 4:
		errors.append("%s：我方最多 4 人" % where)

	var beat_list: Variant = script.get("beats")
	if not beat_list is Array or (beat_list as Array).is_empty():
		errors.append("%s：beats 必須是非空的陣列" % where)
		return errors

	# 一邊檢查一邊模擬氣血，確認攻擊會扣血、治療會補血。
	var hp := {}
	for unit_id in unit_ids:
		hp[unit_id] = 1.0

	var count: int = (beat_list as Array).size()
	for i in count:
		var beat: Variant = beat_list[i]
		var at := "%s 第 %d 拍" % [where, i + 1]
		if not beat is Dictionary:
			errors.append("%s：必須是物件" % at)
			continue
		var type := str(beat.get("type", ""))
		if not BEAT_TYPES.has(type):
			errors.append("%s：不認得的種類「%s」" % [at, type])
			continue
		if type == "end" and i != count - 1:
			errors.append("%s：end 只能放在最後" % at)

		if type in ["subtitle", "narrate", "say", "hint"]:
			var key: Variant = beat.get("text")
			if not key is String or not texts.has(key):
				errors.append("%s：文字表裡沒有 %s" % [at, str(key)])
		if type in ["say", "act", "charge", "state"]:
			if not unit_ids.has(str(beat.get("who", ""))):
				errors.append("%s：who「%s」不在這場戰鬥裡" % [at, str(beat.get("who", ""))])
				continue
		if type == "say" and beat.has("face"):
			# 對話框的頭像預設用說話者自己的；face 可以指定換成另一套造型（例如重生後的燕回）
			var face: Variant = beat["face"]
			if not face is String or not _is_identifier(face):
				errors.append("%s：face 必須是造型的識別碼（英文小寫、數字、底線）" % at)
		if type == "narrate" and beat.has("fx") and not FX_NAMES.has(beat["fx"]):
			errors.append("%s：不認得的演出「%s」" % [at, str(beat["fx"])])

		match type:
			"act":
				_validate_act(beat, at, characters, moves, unit_ids, script, hp, errors)
			"command":
				if not COMMANDS.has(beat.get("command", "")):
					errors.append("%s：不認得的指令「%s」" % [at, str(beat.get("command", ""))])
				if not INPUT_MODES.has(beat.get("input", "")) or beat.get("input", "") == "full":
					errors.append("%s：指令的 input 只能是 tap 或不寫" % at)
			"charge":
				var who := str(beat["who"])
				if not (characters[who].get("moves") as Array).has(beat.get("move")):
					errors.append("%s：%s 沒有招式 %s" % [at, who, str(beat.get("move"))])
				if float(beat.get("time", 0.0)) <= 0.0:
					errors.append("%s：time 必須大於 0" % at)
			"state":
				if not STATES.has(beat.get("set", "?")):
					errors.append("%s：不認得的狀態「%s」" % [at, str(beat.get("set", "?"))])
			"fx":
				if not FX_NAMES.has(beat.get("name", "")):
					errors.append("%s：不認得的演出「%s」" % [at, str(beat.get("name", ""))])
				if beat.get("name") == "pin":
					for unit_id: Variant in beat.get("who", []):
						if not unit_ids.has(str(unit_id)):
							errors.append("%s：who 裡的 %s 不在這場戰鬥裡" % [at, str(unit_id)])
					if not unit_ids.has(str(beat.get("target", ""))):
						errors.append("%s：target 不在這場戰鬥裡" % at)
			"scene":
				if not SCENES.has(beat.get("name", "")):
					errors.append("%s：不認得的場景「%s」" % [at, str(beat.get("name", ""))])

	if (beat_list[count - 1] as Dictionary).get("type") != "end":
		errors.append("%s：最後一拍必須是 end" % where)
	return errors


static func _is_identifier(text: String) -> bool:
	if text == "":
		return false
	for i in text.length():
		var code := text.unicode_at(i)
		var ok := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95
		if not ok:
			return false
	return true


static func _validate_act(beat: Dictionary, at: String, characters: Dictionary, moves: Dictionary,
		unit_ids: Array[String], script: Dictionary, hp: Dictionary, errors: Array[String]) -> void:
	var who := str(beat["who"])
	var move_id := str(beat.get("move", ""))
	if not (characters[who].get("moves") as Array).has(move_id):
		errors.append("%s：%s 沒有招式 %s" % [at, who, move_id])
		return
	var input := str(beat.get("input", ""))
	if not INPUT_MODES.has(input):
		errors.append("%s：input 只能是 full、tap 或不寫" % at)
	elif input != "" and characters[who].get("side") != "party":
		errors.append("%s：只有我方的行動可以等玩家操作" % at)

	var target := str(beat.get("target", ""))
	if target != TARGET_PARTY and target != TARGET_ENEMIES and not unit_ids.has(target):
		errors.append("%s：target「%s」不在這場戰鬥裡" % [at, target])
	if input == "full" and (target == TARGET_PARTY or target == TARGET_ENEMIES):
		errors.append("%s：input 為 full 時，target 必須是單一對象" % at)
	if float(beat.get("charge", 0.0)) < 0.0 or float(beat.get("cost", 0.0)) < 0.0 or float(beat.get("cost", 0.0)) > 1.0:
		errors.append("%s：charge 不可為負，cost 必須在 0 到 1 之間" % at)

	var result: Variant = beat.get("result", {})
	if not result is Dictionary:
		errors.append("%s：result 必須是物件" % at)
		return
	var kind := str(moves[move_id].get("kind", ""))
	for unit_id: String in result:
		if not unit_ids.has(unit_id):
			errors.append("%s：result 裡的 %s 不在這場戰鬥裡" % [at, unit_id])
			continue
		var change: Variant = result[unit_id]
		if not change is Dictionary or not change.has("hp_to"):
			errors.append("%s：result.%s 需要 hp_to" % [at, unit_id])
			continue
		var to := float(change["hp_to"])
		if to < 0.0 or to > 1.0:
			errors.append("%s：hp_to 必須在 0 到 1 之間" % at)
			continue
		var from := float(hp[unit_id])
		if kind == "heal" and to <= from:
			errors.append("%s：治療之後 %s 的氣血沒有增加（%.2f → %.2f）" % [at, unit_id, from, to])
		if kind != "heal" and to >= from:
			errors.append("%s：受擊之後 %s 的氣血沒有減少（%.2f → %.2f）" % [at, unit_id, from, to])
		hp[unit_id] = to


## 以通過驗證的劇本建立戰鬥。
func setup(script: Dictionary, characters: Dictionary) -> void:
	script_id = str(script.get("id", ""))
	title_key = str(script.get("title", ""))
	background = str(script.get("background", ""))
	party.assign(script.get("party", []))
	enemies.assign(script.get("enemies", []))
	beats = script.get("beats", [])
	index = -1
	units.clear()
	for unit_id: String in party + enemies:
		var c: Dictionary = characters[unit_id]
		units[unit_id] = {
			"hp": 1.0,
			"mp": 1.0,
			"hp_max": int(c["hp_max"]),
			"mp_max": int(c["mp_max"]),
			"side": str(c["side"]),
			"state": "",
			"charging": "",
		}


func has_next() -> bool:
	return index + 1 < beats.size()


func next_beat() -> Dictionary:
	index += 1
	return beats[index]


## 這一拍要玩家做什麼。不需要操作時回傳空字典。
## 回傳 { who, kind: "move" 或 "command", id, mode: "full" 或 "tap", target }
func required_input(beat: Dictionary) -> Dictionary:
	var mode := str(beat.get("input", ""))
	if mode == "":
		return {}
	match str(beat.get("type", "")):
		"act":
			return {
				"who": str(beat["who"]),
				"kind": "move",
				"id": str(beat["move"]),
				"mode": mode,
				"target": str(beat.get("target", "")),
			}
		"command":
			return {
				"who": party[0],
				"kind": "command",
				"id": str(beat["command"]),
				"mode": "tap",
				"target": "",
			}
	return {}


## 把「party」、「enemies」或單一識別碼展開成單位清單。
func resolve_targets(target: String) -> Array[String]:
	if target == TARGET_PARTY:
		return party.duplicate()
	if target == TARGET_ENEMIES:
		return enemies.duplicate()
	var one: Array[String] = [target]
	return one


## 套用這一拍對狀態的改動。
## 回傳改動清單，每筆是 { unit, stat, from, to, amount }；amount 是畫面上要跳的數字。
func apply(beat: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	match str(beat.get("type", "")):
		"act":
			var who := str(beat["who"])
			var actor: Dictionary = units[who]
			actor["charging"] = ""
			var cost := float(beat.get("cost", 0.0))
			if cost > 0.0:
				var mp_from := float(actor["mp"])
				var mp_to := maxf(0.0, mp_from - cost)
				actor["mp"] = mp_to
				changes.append({
					"unit": who, "stat": "mp", "from": mp_from, "to": mp_to,
					"amount": roundi((mp_from - mp_to) * int(actor["mp_max"])),
				})
			var result: Dictionary = beat.get("result", {})
			for unit_id: String in result:
				var unit: Dictionary = units[unit_id]
				var from := float(unit["hp"])
				var to := float(result[unit_id]["hp_to"])
				unit["hp"] = to
				if to <= 0.0:
					# 倒下的人不再有其他狀態
					unit["state"] = ""
					unit["charging"] = ""
				changes.append({
					"unit": unit_id, "stat": "hp", "from": from, "to": to,
					"amount": roundi(absf(from - to) * int(unit["hp_max"])),
				})
			# 守勢只撐到下一次受擊。
			for unit_id: String in result:
				if units[unit_id]["state"] == "guard":
					units[unit_id]["state"] = ""
		"command":
			if beat.get("command") == "guard":
				for unit_id in party:
					units[unit_id]["state"] = "guard"
		"charge":
			units[str(beat["who"])]["charging"] = str(beat["move"])
		"state":
			units[str(beat["who"])]["state"] = str(beat.get("set", ""))
	return changes


func hp_of(unit_id: String) -> float:
	return float(units[unit_id]["hp"])


func mp_of(unit_id: String) -> float:
	return float(units[unit_id]["mp"])
