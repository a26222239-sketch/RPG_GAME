extends SceneTree
## 自動測試：資料驗證與劇本式戰鬥的規則層。不開視窗。
##
## 執行方式（在專案根目錄）：
##   godot --headless --path . -s res://tests/run_tests.gd
## 全部通過時結束碼為 0，有失敗為 1。

const GameData := preload("res://core/data/game_data.gd")
const ScriptedBattle := preload("res://core/scripted/scripted_battle.gd")

var _passed: int = 0
var _failed: int = 0
var _data: GameData


func _initialize() -> void:
	_data = GameData.new()
	_test_data_loads()
	if _failed == 0:
		_test_prologue_is_valid()
		_test_prologue_plays_through()
		_test_prologue_inputs()
		_test_prologue_text_is_all_used()
		_test_validator_catches_mistakes()
	print("\n測試結果：通過 %d，失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- 測試

func _test_data_loads() -> void:
	var ok := _data.load_all()
	_check(ok, "資料載入並通過驗證", "；".join(_data.errors))
	_check(_data.characters.size() == 5, "序章有 5 個角色")
	_check(_data.text("NO_SUCH_KEY") == "NO_SUCH_KEY", "找不到的文字鍵會原樣回傳")


func _test_prologue_is_valid() -> void:
	var script := _data.load_scripted("prologue_final")
	_check(not script.is_empty(), "讀得到序章劇本", "；".join(_data.errors))
	var problems := ScriptedBattle.validate(script, _data.characters, _data.moves, _data.texts)
	_check(problems.is_empty(), "序章劇本通過驗證", "；".join(problems))


func _test_prologue_plays_through() -> void:
	var battle := _new_prologue()
	var tianmo_hp: Array[float] = []
	var first_amount := -1
	var guard_seen := false
	var after_big_hit := {}
	var after_heal := {}
	var slow_seen := false
	var stagger_seen := false

	while battle.has_next():
		var beat := battle.next_beat()
		var changes := battle.apply(beat)
		for change in changes:
			if change["unit"] == "tianmo" and change["stat"] == "hp":
				tianmo_hp.append(float(change["to"]))
				if first_amount < 0:
					first_amount = int(change["amount"])
		match str(beat.get("type", "")):
			"command":
				guard_seen = _all_party_state(battle, "guard")
			"state":
				if beat.get("set") == "slow":
					slow_seen = battle.units["tianmo"]["state"] == "slow"
				if beat.get("set") == "stagger":
					stagger_seen = battle.units["tianmo"]["state"] == "stagger"
			"act":
				if beat.get("move") == "tianmo_fushi":
					after_big_hit = _party_hp(battle)
					_check(_all_party_state(battle, ""), "受擊之後守勢解除")
				if beat.get("move") == "wen_bianzhao":
					after_heal = _party_hp(battle)

	_check(_same_floats(tianmo_hp, [0.95, 0.91, 0.86, 0.68, 0.46, 0.4, 0.0]),
		"天魔的氣血依序是 95、91、86、68、46、40、0", str(tianmo_hp))
	_check(first_amount == 3400, "第一擊的傷害數字是 68000 的 5%，也就是 3400", str(first_amount))
	_check(guard_seen, "按下守勢後，我方四人都進入守勢")
	_check(slow_seen and stagger_seen, "天魔先後進入遲緩與破綻")
	_check(_same_dict(after_big_hit, {"yanhui_peak": 0.3, "shen_peak": 0.22, "huo_peak": 0.35, "wen_peak": 0.28}),
		"九淵覆世之後四人的氣血是 30、22、35、28", str(after_big_hit))
	_check(_same_dict(after_heal, {"yanhui_peak": 0.8, "shen_peak": 0.78, "huo_peak": 0.82, "wen_peak": 0.75}),
		"回春之後四人回到八成上下", str(after_heal))
	_check(is_equal_approx(battle.hp_of("tianmo"), 0.0), "結束時天魔的氣血是 0")
	_check(battle.units["tianmo"]["state"] == "", "倒下之後不再有破綻狀態")
	_check(is_equal_approx(battle.mp_of("wen_peak"), 0.1), "溫蘅用完兩招後內力只剩一成", str(battle.mp_of("wen_peak")))
	_check(not battle.has_next(), "劇本播到最後一拍")


func _test_prologue_inputs() -> void:
	var battle := _new_prologue()
	var inputs: Array[String] = []
	while battle.has_next():
		var beat := battle.next_beat()
		var input := battle.required_input(beat)
		if not input.is_empty():
			inputs.append("%s:%s:%s:%s" % [input["who"], input["kind"], input["id"], input["mode"]])
		battle.apply(beat)
	var expected: Array[String] = [
		"yanhui_peak:move:yanhui_zhici:full",
		"shen_peak:move:shen_qianren:tap",
		"huo_peak:move:huo_duanyue:tap",
		"wen_peak:move:wen_fengxue:tap",
		"yanhui_peak:command:guard:tap",
		"wen_peak:move:wen_bianzhao:tap",
		"yanhui_peak:move:yanhui_wanfa:tap",
	]
	_check(inputs == expected, "玩家要按的七個指令與順序正確", str(inputs))


func _test_prologue_text_is_all_used() -> void:
	var script := _data.load_scripted("prologue_final")
	var used := {}
	for beat: Dictionary in script["beats"]:
		if beat.has("text"):
			used[beat["text"]] = true
	var unused: Array[String] = []
	for key: String in _data.texts:
		if (key.begins_with("PRO_") or key.begins_with("TUT_")) and not used.has(key):
			unused.append(key)
	_check(unused.is_empty(), "文字表裡的序章台詞與提示都有被劇本用到", str(unused))


func _test_validator_catches_mistakes() -> void:
	var base := _data.load_scripted("prologue_final")

	var broken: Dictionary = base.duplicate(true)
	broken["beats"][2]["text"] = "NO_SUCH_TEXT"
	_check(_has_problem(broken), "抓得到不存在的文字鍵")

	broken = base.duplicate(true)
	var enemy_act := _find_beat(broken, "act", "tianmo")
	broken["beats"][enemy_act]["input"] = "tap"
	_check(_has_problem(broken), "抓得到要玩家替敵人按指令")

	broken = base.duplicate(true)
	var heal := _find_move(broken, "wen_bianzhao")
	broken["beats"][heal]["result"]["yanhui_peak"]["hp_to"] = 0.1
	_check(_has_problem(broken), "抓得到治療之後氣血反而變少")

	broken = base.duplicate(true)
	var hit := _find_move(broken, "yanhui_zhici")
	broken["beats"][hit]["result"]["tianmo"]["hp_to"] = 1.0
	_check(_has_problem(broken), "抓得到攻擊之後氣血沒有減少")

	broken = base.duplicate(true)
	broken["beats"][hit]["move"] = "huo_duanyue"
	_check(_has_problem(broken), "抓得到用了不屬於自己的招式")

	broken = base.duplicate(true)
	(broken["beats"] as Array).pop_back()
	_check(_has_problem(broken), "抓得到劇本沒有以 end 結尾")

	broken = base.duplicate(true)
	(broken["party"] as Array).append("tianmo")
	_check(_has_problem(broken), "抓得到把敵人放進我方隊伍")


# ---------------------------------------------------------------- 工具

func _new_prologue() -> ScriptedBattle:
	var battle := ScriptedBattle.new()
	battle.setup(_data.load_scripted("prologue_final"), _data.characters)
	return battle


func _has_problem(script: Dictionary) -> bool:
	return not ScriptedBattle.validate(script, _data.characters, _data.moves, _data.texts).is_empty()


func _find_beat(script: Dictionary, type: String, who: String) -> int:
	var beats: Array = script["beats"]
	for i in beats.size():
		if beats[i].get("type") == type and beats[i].get("who") == who:
			return i
	return -1


func _find_move(script: Dictionary, move_id: String) -> int:
	var beats: Array = script["beats"]
	for i in beats.size():
		if beats[i].get("type") == "act" and beats[i].get("move") == move_id:
			return i
	return -1


func _party_hp(battle: ScriptedBattle) -> Dictionary:
	var result := {}
	for id in battle.party:
		result[id] = battle.hp_of(id)
	return result


func _all_party_state(battle: ScriptedBattle, state: String) -> bool:
	for id in battle.party:
		if battle.units[id]["state"] != state:
			return false
	return true


func _same_floats(a: Array[float], b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(a[i], float(b[i])):
			return false
	return true


func _same_dict(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in b:
		if not a.has(key) or not is_equal_approx(float(a[key]), float(b[key])):
			return false
	return true


func _check(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  通過　%s" % name)
	else:
		_failed += 1
		print("  失敗　%s%s" % [name, ("　→ " + detail) if detail != "" else ""])
