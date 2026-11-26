extends SceneTree
## 自動測試：資料驗證與劇本式戰鬥的規則層。不開視窗。
##
## 執行方式（在專案根目錄）：
##   godot --headless --path . -s res://tests/run_tests.gd
## 全部通過時結束碼為 0，有失敗為 1。

const GameData := preload("res://core/data/game_data.gd")
const ScriptedBattle := preload("res://core/scripted/scripted_battle.gd")
const LineWrap := preload("res://core/text/line_wrap.gd")
const FrameStrip := preload("res://core/art/frame_strip.gd")

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
		_test_prologue_art_exists()
	_test_line_wrap()
	_test_frame_strip()
	_test_vfx_settings()
	_test_delivered_strips()
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

	broken = base.duplicate(true)
	broken["beats"][_find_beat(broken, "say", "yanhui_peak")]["face"] = "Yan Hui"
	_check(_has_problem(broken), "抓得到寫錯格式的頭像造型")


## 序章用到的圖都在：每個角色的站姿與頭像、台詞另外指定的頭像、戰鬥背景。
func _test_prologue_art_exists() -> void:
	var script := _data.load_scripted("prologue_final")
	var missing: Array[String] = []
	var looks: Array = (script["party"] as Array) + (script["enemies"] as Array)
	for unit_id: String in looks:
		var stand := "res://assets/characters/%s/frames/stand.png" % unit_id
		if not FileAccess.file_exists(stand):
			missing.append(stand)
	for beat: Dictionary in script["beats"]:
		if beat.get("type") == "say" and beat.has("face") and not looks.has(beat["face"]):
			looks.append(beat["face"])
	for look: String in looks:
		var head := "res://assets/characters/%s/portrait/head.png" % look
		if not FileAccess.file_exists(head):
			missing.append(head)
	var background := "res://assets/backgrounds/battle/%s.jpg" % str(script["background"])
	if not FileAccess.file_exists(background):
		missing.append(background)
	_check(missing.is_empty(), "序章的站姿、頭像與戰鬥背景都有圖", "缺：" + "、".join(missing))


func _test_line_wrap() -> void:
	var charge := "威力大的招式要先蓄力，也會消耗內力。"
	_check(LineWrap.balanced(charge, 16) == "威力大的招式要先蓄力，\n也會消耗內力。", "提示在逗號後面換行，不留一兩個字自成一行",
		LineWrap.balanced(charge, 16))
	_check(LineWrap.balanced("選擇目標", 16) == "選擇目標", "放得下的文字不換行")
	_check(LineWrap.balanced("一二三四五六\n七八", 4) == "一二三\n四五六\n七八", "沒有標點時平均分行，原本的換行保留",
		LineWrap.balanced("一二三四五六\n七八", 4))

	# 所有提示在各種寬度下：不超寬、標點不在行首、內容不變
	var problems: Array[String] = []
	for key: String in _data.texts:
		if not key.begins_with("TUT_"):
			continue
		var text := str(_data.texts[key])
		for width in range(6, 31):
			var wrapped := LineWrap.balanced(text, width)
			if wrapped.replace("\n", "") != text:
				problems.append("%s 寬 %d：內容變了" % [key, width])
			for line in wrapped.split("\n"):
				if line.length() > width:
					problems.append("%s 寬 %d：「%s」超寬" % [key, width, line])
				if line != "" and LineWrap.BREAK_AFTER.contains(line[0]):
					problems.append("%s 寬 %d：「%s」以標點開頭" % [key, width, line])
	_check(problems.is_empty(), "四則教學提示在每行 6 到 30 個字的寬度下都排得正確", "；".join(problems.slice(0, 5)))


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


## 逐格圖的規則：幾格、播多快、第幾秒顯示第幾格。
func _test_frame_strip() -> void:
	_check(FrameStrip.count(3072, 512) == 6 and FrameStrip.count(1024, 1024) == 1 and FrameStrip.count(8192, 1024) == 8,
		"逐格圖的格數是寬除以高，只有一格也算")
	_check(FrameStrip.problem(3000, 512) != "" and FrameStrip.problem(512, 768) != "" and FrameStrip.count(3000, 512) == 0,
		"格子不是正方形的圖會被擋下來")

	# 沒有另外指定：6 格平均排進 0.5 秒，出手點在整段的六成
	var plain := FrameStrip.timing(6, 0.5, 0.6, {})
	_check(is_equal_approx(plain["fps"], 12.0) and is_equal_approx(plain["length"], 0.5) and is_equal_approx(plain["impact"], 0.3),
		"沒有指定時，格子平均排進預設的長度", str(plain))
	# 美術指定了速度與出手的那一格
	var written := FrameStrip.timing(8, 0.9, 0.6, {"fps": 16, "impact_frame": 5})
	_check(is_equal_approx(written["length"], 0.5) and is_equal_approx(written["impact"], 0.25),
		"照美術寫的每秒格數與出手格來播", str(written))
	# 只有一格：定格，停滿預設的長度
	var still := FrameStrip.timing(1, 0.5, 0.6, {})
	_check(is_equal_approx(still["length"], 0.5) and is_equal_approx(still["impact"], 0.3), "只有一格的圖停滿這個動作的時間", str(still))

	var looped: Array = []
	var held: Array = []
	for step in 7:
		looped.append(FrameStrip.frame_at(step * 0.1 + 0.01, 10.0, 4, FrameStrip.LOOP))
		held.append(FrameStrip.frame_at(step * 0.1 + 0.01, 10.0, 4, FrameStrip.HOLD))
	_check(looped == [0, 1, 2, 3, 0, 1, 2], "循環的動作播完接回第一格", str(looped))
	_check(held == [0, 1, 2, 3, 3, 3, 3], "不循環的動作停在最後一格", str(held))
	_check(FrameStrip.region(2, 512) == Rect2(1024, 0, 512, 512), "第三格的位置在兩格寬之後")


## 特效的播放設定：每個招式用的特效、戰鬥畫面固定會用的特效，都要有設定。
func _test_vfx_settings() -> void:
	var missing: Array[String] = []
	for fx_id: String in GameData.SHARED_FX + ["hit_spark", "charge_aura", "guard", "stagger_mark", "tianmo_guixu"]:
		if not _data.vfx.has(fx_id):
			missing.append(fx_id)
	_check(missing.is_empty(), "共用特效與戰鬥畫面固定用的特效都有播放設定", "缺：" + "、".join(missing))
	var loops_on_body := true
	for fx_id: String in _data.vfx:
		var f: Dictionary = _data.vfx[fx_id]
		if f.get("loop", false) and f["anchor"] != "body":
			loops_on_body = false
	_check(loops_on_body, "循環播放的特效都是套在人身上的")

	var broken := _data.vfx.duplicate(true)
	broken["slash_sword"]["anchor"] = "sky"
	broken["palm"]["tint"] = "blue"
	var checker := GameData.new()
	checker.load_all()
	checker.vfx = broken
	checker.errors.clear()
	checker._validate()
	_check(checker.errors.size() == 2, "抓得到寫錯的對位與染色", "；".join(checker.errors))


## 已經放進正式資料夾的動作圖與特效圖，尺寸都要合規格（每格正方形、不超過顯示卡載得進去的寬度）。
## 檔名對不上任何動作或特效的也列出來，多半是打錯字。
func _test_delivered_strips() -> void:
	var problems: Array[String] = []
	var total := 0
	for character_id: String in DirAccess.get_directories_at("res://assets/characters"):
		var folder := "res://assets/characters/%s/frames" % character_id
		var names: Array = GameData.ANIMS + _data.moves.keys()
		total += _check_frame_folder(folder, names, ["stand.png"], "不是動畫契約裡的動作，也不是招式識別碼", problems)
	if DirAccess.dir_exists_absolute("res://assets/vfx"):
		total += _check_frame_folder("res://assets/vfx", _data.vfx.keys(), [], "data/vfx.json 沒有這一組特效", problems)
	_check(problems.is_empty(), "已交付的動作圖與特效圖都合規格（目前 %d 張）" % total, "；".join(problems))


## 檢查一個資料夾裡的逐格圖，回傳檢查了幾張。names 是允許的名稱（動作或特效）。
func _check_frame_folder(folder: String, names: Array, skip: Array, unknown: String, problems: Array[String]) -> int:
	var total := 0
	var sides: Dictionary = {}
	for file: String in DirAccess.get_files_at(folder):
		if not file.ends_with(".png") or skip.has(file):
			continue
		total += 1
		var path := "%s/%s" % [folder, file]
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null:
			problems.append("%s：讀不到" % path)
			continue
		var base := file.get_basename()
		var problem := ""
		if names.has(base):
			problem = FrameStrip.problem(image.get_width(), image.get_height())
			if problem == "" and image.get_width() > FrameStrip.MAX_STRIP_WIDTH:
				problem = "橫排圖寬 %d，超過 %d；請改成一格一個檔" % [image.get_width(), FrameStrip.MAX_STRIP_WIDTH]
		else:
			# 一格一個檔：名稱_兩位數序號
			var cut := base.rfind("_")
			var owner := base.substr(0, maxi(cut, 0))
			if cut < 0 or not base.substr(cut + 1).is_valid_int() or base.length() - cut - 1 != 2 or not names.has(owner):
				problem = unknown
			else:
				if not sides.has(owner):
					sides[owner] = image.get_width()
				problem = FrameStrip.single_problem(image.get_width(), image.get_height(), int(sides[owner]))
		if problem != "":
			problems.append("%s：%s" % [path, problem])
	return total


func _check(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  通過　%s" % name)
	else:
		_failed += 1
		print("  失敗　%s%s" % [name, ("　→ " + detail) if detail != "" else ""])
