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
const BattleSim := preload("res://core/battle/battle_sim.gd")

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
	_test_anim_spec_sync()
	_test_move_classes()
	_test_vfx_settings()
	_test_delivered_strips()
	if _failed == 0:
		_test_battle_numbers()
		_test_battle_hits()
		_test_battle_statuses()
		_test_battle_commands()
		_test_battle_waits_for_player()
		_test_battle_ai()
		_test_battle_is_repeatable()
		_test_battle_encounters_finish()
		_test_battle_validator()
	print("\n測試結果：通過 %d，失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- 測試

func _test_data_loads() -> void:
	var ok := _data.load_all()
	_check(ok, "資料載入並通過驗證", "；".join(_data.errors))
	var actors := 0
	for char_id: String in _data.characters:
		if not _data.is_fighter(char_id):
			actors += 1
	_check(actors == 5, "序章有 5 個只演劇本的角色", str(actors))
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

	# 沒有另外指定：6 格平均排進 0.6 秒，出手點在整段的六成
	var plain := FrameStrip.timing(6, 0.6, 0.6, {})
	_check(is_equal_approx(plain["length"], 0.6) and is_equal_approx(plain["impact"], 0.36) and is_equal_approx(plain["ends"][0], 0.1),
		"沒有指定時，格子平均排進預設的長度", str(plain))
	# 美術指定了每秒幾格與出手的那一格（從 1 算起）
	var written := FrameStrip.timing(8, 0.9, 0.6, {"fps": 16, "impact_frame": 5})
	_check(is_equal_approx(written["length"], 0.5) and is_equal_approx(written["impact"], 0.25),
		"照美術寫的每秒格數與出手格來播", str(written))
	# 美術指定了每一格各停多久，出手格從 0 算起（批次 1 沈清禾出劍的寫法）
	var uneven := FrameStrip.timing(6, 0.5, 0.5, {"timings_ms": [60, 80, 60, 90, 130, 130], "impact_frame": 3}, 0)
	_check(is_equal_approx(uneven["length"], 0.55) and is_equal_approx(uneven["impact"], 0.2),
		"每格停多久可以不一樣，出手格也可以從 0 算起", str(uneven))
	var shown: Array = []
	for moment: float in [0.0, 0.059, 0.061, 0.139, 0.141, 0.21, 0.3, 0.5, 0.56, 9.0]:
		shown.append(FrameStrip.frame_at(moment, uneven["ends"], FrameStrip.ONCE))
	_check(shown == [0, 0, 1, 1, 2, 3, 4, 5, 5, 5], "照每格的時間換格", str(shown))
	var timed := FrameStrip.timing(3, 0.3, 0.0, {"timings_ms": [45, 155, 120], "impact_frame": 1, "impact_time": 0.05}, 0)
	_check(is_equal_approx(timed["impact"], 0.05), "同時寫了出手的秒數與格數時，用秒數", str(timed))
	var ignored := FrameStrip.timing(4, 0.4, 0.5, {"timings_ms": [100, 100]})
	_check(is_equal_approx(ignored["length"], 0.4), "每格時間的數量和格數對不上時，改用預設的速度", str(ignored))
	# 只有一格：定格，停滿預設的長度
	var still := FrameStrip.timing(1, 0.5, 0.6, {})
	_check(is_equal_approx(still["length"], 0.5) and is_equal_approx(still["impact"], 0.3), "只有一格的圖停滿這個動作的時間", str(still))

	var even: Array = FrameStrip.timing(4, 0.4, 0.0, {})["ends"]
	var looped: Array = []
	var held: Array = []
	for step in 7:
		looped.append(FrameStrip.frame_at(step * 0.1 + 0.01, even, FrameStrip.LOOP))
		held.append(FrameStrip.frame_at(step * 0.1 + 0.01, even, FrameStrip.HOLD))
	_check(looped == [0, 1, 2, 3, 0, 1, 2], "循環的動作播完接回第一格", str(looped))
	_check(held == [0, 1, 2, 3, 3, 3, 3], "不循環的動作停在最後一格", str(held))
	# 前兩格是進場，之後從第三格（從 1 算起）開始循環
	var entry := FrameStrip.timing(5, 0.5, 0.0, {"loop_from": 3})
	var entered: Array = []
	for step in 10:
		entered.append(FrameStrip.frame_at(step * 0.1 + 0.01, entry["ends"], FrameStrip.LOOP, entry["loop_start"]))
	_check(entry["has_loop_from"] and entered == [0, 1, 2, 3, 4, 2, 3, 4, 2, 3], "進場只播一次，之後從指定的那一格起循環", str(entered))
	_check(FrameStrip.region(2, 512) == Rect2(1024, 0, 512, 512), "第三格的位置在兩格寬之後")


## 遊戲裡各動作預設的長度，要和規格檔 tools/anim_spec.json 寫的一樣；動畫契約也要對得上。
func _test_anim_spec_sync() -> void:
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/anim_spec.json"))
	if not spec is Dictionary:
		_check(false, "讀得到動作規格 tools/anim_spec.json")
		return
	var actor := load("res://scenes/battle/battle_actor.gd")
	var lengths: Dictionary = actor.STRIP_LENGTH
	var wrong: Array[String] = []
	for anim: String in spec["actions"]:
		var expected := float(spec["actions"][anim]["default"])
		var have: float = float(lengths[anim]) if lengths.has(anim) else float(actor.CLASS_LENGTH.get(spec["actions"][anim].get("class", ""), -1.0))
		if not is_equal_approx(have, expected):
			wrong.append("%s：遊戲 %s、規格 %s" % [anim, have, expected])
	_check(wrong.is_empty(), "各動作預設的長度和動作規格一致", "；".join(wrong))
	var missing: Array[String] = []
	for anim: String in GameData.ANIMS:
		if not (spec["actions"] as Dictionary).has(anim):
			missing.append(anim)
	_check(missing.is_empty(), "動畫契約裡的每個動作在規格裡都有張數", "缺：" + "、".join(missing))


## 每個招式都有分級；寫錯會被抓出來。
func _test_move_classes() -> void:
	var classes: Dictionary = {}
	for move_id: String in _data.moves:
		classes[str(_data.moves[move_id].get("class", ""))] = true
	_check(classes.has("basic") and classes.has("skill") and classes.has("ultimate") and classes.size() == 3,
		"招式分成普攻、小招、大招三級", str(classes.keys()))
	var checker := GameData.new()
	checker.load_all()
	checker.moves["shen_dianxing"]["class"] = "big"
	checker.errors.clear()
	checker._validate()
	_check(checker.errors.size() == 1 and "class" in checker.errors[0], "抓得到寫錯的招式分級", "；".join(checker.errors))


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


# ---------------------------------------------------------------- 戰鬥規則（第 4 章）

## 新的一場戰鬥。manual 為真時我方全部手動，否則照預設戰術自動。
func _new_battle(encounter: String, seed_value: int = 1, manual: bool = false) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(_data, encounter, seed_value)
	if not manual:
		for u in sim.side_units("party", false):
			u.auto = "support" if u.id == "wen" else "attack"
	return sim


## 讓 src 打 tgt 一下，保證不會閃避（暫時把守方的身法壓低，打完還原）。回傳傷害事件。
func _clean_hit(sim: BattleSim, src: BattleSim.Unit, tgt: BattleSim.Unit, move_id: String) -> Dictionary:
	var shenfa: float = tgt.attrs["shenfa"]
	tgt.attrs["shenfa"] = float(src.attrs["shenfa"]) - 100.0
	sim._events = []
	sim._hit(src, tgt, move_id)
	tgt.attrs["shenfa"] = shenfa
	for e in sim._events:
		if e["type"] == "damage":
			return e
	return {}


## 衍生數值與 13.2、13.3 的表一致，算例與 4.5 一致。
func _test_battle_numbers() -> void:
	var sim := _new_battle("test_d")
	var expect := {
		"yanhui": [560, 194, 114, 19.2], "shen": [480, 162, 102, 22.4],
		"huo": [650, 146, 124, 16.8], "wen": [500, 242, 108, 17.6],
	}
	var wrong: Array[String] = []
	for id: String in expect:
		var u := sim.unit(id)
		var e: Array = expect[id]
		if u.hp_max != e[0] or u.mp_max != e[1] or roundi(u.posture_max) != e[2] or not is_equal_approx(sim.speed(u), e[3]):
			wrong.append("%s %d/%d/%d/%.1f" % [id, u.hp_max, u.mp_max, u.posture_max, sim.speed(u)])
	_check(wrong.is_empty(), "四人的氣血、內力、架勢、速度和 13.2 的表一致", "、".join(wrong))
	var boss := sim.unit("third_chief#1")
	_check(boss != null and boss.boss and abs(boss.hp_max - 1898) <= 1, "三當家氣血約 1,898，是首領", str(boss.hp_max if boss else -1))
	var a := _new_battle("test_a")
	var bandit := a.unit("bandit#1")
	_check(abs(bandit.hp_max - 266) <= 1 and abs(a.unit("archer#1").hp_max - 193) <= 1, "嘍囉約 266、弓手約 193", "%d %d" % [bandit.hp_max, a.unit("archer#1").hp_max])
	var b := _new_battle("test_b")
	var names: Array[String] = []
	for u in b.side_units("enemy"):
		names.append(u.display_name)
	_check(names[0].ends_with("甲") and names[2].ends_with("丙") and not names[3].ends_with("甲"), "同種敵人有好幾個時名字後面加甲乙丙", "、".join(names))
	var expected := a.expected_damage(a.unit("yanhui"), "yanhui_huifeng", bandit)
	_check(roundi(expected) == 76, "算例：燕回迴風斬打嘍囉約 76", "%.2f" % expected)
	_check(is_equal_approx(a.matchup("gang", "kuai"), 1.25) and is_equal_approx(a.matchup("kuai", "gang"), 0.8)
		and is_equal_approx(a.matchup("rou", "gang"), 1.25) and is_equal_approx(a.matchup("kuai", "rou"), 1.25)
		and is_equal_approx(a.matchup("gang", "gang"), 1.0), "勁路相剋：剛剋快、柔剋剛、快剋柔")


## 出手：傷害浮動、破綻、截招、守勢、閃避。
func _test_battle_hits() -> void:
	var sim := _new_battle("test_a")
	var yanhui := sim.unit("yanhui")
	var bandit := sim.unit("bandit#1")
	var base := sim.expected_damage(yanhui, "yanhui_huifeng", bandit)
	var e := _clean_hit(sim, yanhui, bandit, "yanhui_huifeng")
	var scale := 1.5 if not e.is_empty() and e["crit"] else 1.0
	_check(not e.is_empty() and e["amount"] >= floori(base * scale * 0.95) and e["amount"] <= ceili(base * scale * 1.05), "傷害落在 ±5% 的浮動內（會心 ×1.5）", str(e))
	_check(is_equal_approx(bandit.posture, bandit.posture_max - 28), "架勢傷害照招式架勢值扣", str(bandit.posture))

	# 架勢打空 → 破綻 5 秒；破綻中傷害 ×1.5，不再扣架勢
	bandit.posture = 5
	_clean_hit(sim, yanhui, bandit, "yanhui_zhici")
	_check(bandit.state == "stagger" and bandit.timer == 150, "架勢歸零進入破綻 5 秒", "%s %d" % [bandit.state, bandit.timer])
	var plain := sim.expected_damage(yanhui, "yanhui_zhici", sim.unit("bandit#2"))
	_check(is_equal_approx(sim.expected_damage(yanhui, "yanhui_zhici", bandit), plain * 1.5), "破綻中受到的傷害 ×1.5")
	for i in 150:
		sim.step()
	_check(bandit.state != "stagger" and is_equal_approx(bandit.posture, bandit.posture_max), "破綻結束後架勢回滿", "%s %.1f" % [bandit.state, bandit.posture])

	# 截招：對蓄招中的人，帶截招的招式架勢傷害 ×2.5，一般招式 ×1.5；打空就打斷
	var c := _new_battle("test_c")
	var chief := c.unit("bandit_chief#1")
	var shen := c.unit("shen")
	chief.state = "charge"
	chief.timer = 90
	chief.pending = {"move": "chief_kaishan", "target": "huo"}
	var before := chief.posture
	_clean_hit(c, shen, chief, "shen_duanliu")
	var cut := before - chief.posture
	_check(is_equal_approx(cut, 22 * 0.8 * 2.5), "截招打蓄招中的人：架勢傷害 ×2.5（快打剛被剋 ×0.8）", "%.2f" % cut)
	before = chief.posture
	_clean_hit(c, shen, chief, "shen_dianxing")
	_check(is_equal_approx(before - chief.posture, 10 * 0.8 * 1.5), "一般招式打蓄招中的人：架勢傷害 ×1.5", "%.2f" % (before - chief.posture))
	chief.posture = 1
	c._events = []
	c._hit(shen, chief, "shen_duanliu")
	var interrupted := c._events.any(func(x: Dictionary) -> bool: return x["type"] == "interrupt")
	_check(interrupted and chief.state == "stagger" and chief.pending.is_empty() and c.stats["interrupts"] == 1, "蓄招中架勢歸零：招式被打斷並露出破綻")

	# 守勢：傷害 ×0.6、架勢傷害 ×0.4
	var g := _new_battle("test_a")
	var huo := g.unit("huo")
	var archer := g.unit("archer#1")
	var open_damage := g.expected_damage(archer, "archer_shot", huo)
	huo.guarding = true
	_check(is_equal_approx(g.expected_damage(archer, "archer_shot", huo), open_damage * 0.6), "守勢中受到的傷害 ×0.6")
	before = huo.posture
	_clean_hit(g, archer, huo, "archer_shot")
	_check(is_equal_approx(before - huo.posture, 8 * 0.8 * 0.4), "守勢中架勢傷害 ×0.4（快打剛被剋 ×0.8）", "%.2f" % (before - huo.posture))

	# 閃避：破綻中閃不掉；閃避率上限 30%
	var d := _new_battle("test_a")
	var fast := d.unit("shen")
	var slow := d.unit("bandit#1")
	fast.attrs["shenfa"] = 500
	_check(is_equal_approx(d.dodge_rate(slow, fast), 0.3), "閃避率最多 30%")
	slow.state = "stagger"
	var dodged := 0
	for i in 40:
		d._events = []
		d._hit(fast, slow, "shen_dianxing")
		if d._events.any(func(x: Dictionary) -> bool: return x["type"] == "dodge"):
			dodged += 1
	_check(dodged == 0, "破綻中無法閃避")


## 狀態效果（4.8）。
func _test_battle_statuses() -> void:
	var sim := _new_battle("test_d")
	var boss := sim.unit("third_chief#1")
	var huo := sim.unit("huo")
	var wen := sim.unit("wen")
	var always := func(status: String) -> Dictionary: return {"effects": [{"status": status, "chance": 1.0}]}

	sim._apply_effects(boss, huo, always.call("poison"))
	sim._apply_effects(boss, huo, always.call("poison"))
	sim._apply_effects(boss, huo, always.call("poison"))
	sim._apply_effects(boss, huo, always.call("poison"))
	_check(int(huo.statuses["poison"]["stacks"]) == 3, "中毒最多疊 3 層", str(huo.statuses["poison"]))
	var hp := huo.hp
	sim._per_second(huo)
	_check(hp - huo.hp == roundi(650 * 0.01 * 3), "中毒每秒損失氣血上限 1% × 層數", str(hp - huo.hp))
	sim._apply_effects(huo, boss, always.call("bleed"))
	hp = boss.hp
	sim._per_second(boss)
	_check(hp - boss.hp == roundi(boss.hp_max * 0.015 * 0.5), "首領流血減半", str(hp - boss.hp))

	sim._apply_effects(boss, wen, always.call("internal"))
	var mp := wen.mp - 50
	wen.mp = mp
	sim._per_second(wen)
	_check(is_equal_approx(wen.mp, mp) and is_equal_approx(sim.cost_of(wen, "wen_huichun"), 22 * 1.25), "內傷：內力不回復、消耗 ×1.25")

	var shen := sim.unit("shen")
	var speed := sim.speed(shen)
	sim._apply_effects(shen, shen, always.call("light"))
	_check(is_equal_approx(sim.speed(shen), speed * 1.3), "輕身：速度 ×1.3")
	var atk := sim.attack_value(sim.unit("yanhui"), "gang")
	sim._apply_effects(sim.unit("yanhui"), sim.unit("yanhui"), always.call("empower"))
	_check(is_equal_approx(sim.attack_value(sim.unit("yanhui"), "gang"), atk * 1.25), "運功：攻擊值 ×1.25")
	var plain := sim.expected_damage(boss, "third_nutao", huo)
	sim._apply_effects(wen, huo, always.call("protect"))
	_check(is_equal_approx(sim.expected_damage(boss, "third_nutao", huo), plain * 0.75), "護體：受到的傷害 ×0.75")

	# 點穴：行動條停止 3 秒；對蓄招中的人無效
	var bandit := sim.unit("bandit#1")
	bandit.state = "fill"
	sim._apply_effects(wen, bandit, always.call("seal"))
	_check(bandit.state == "stun" and bandit.timer == 90, "點穴：對行動條在跑的人有效，3 秒", "%s %d" % [bandit.state, bandit.timer])
	var archer := sim.unit("archer#1")
	archer.state = "charge"
	archer.timer = 30
	archer.pending = {"move": "archer_volley", "target": "huo"}
	sim._apply_effects(wen, archer, always.call("seal"))
	_check(archer.state == "charge", "點穴：對蓄招中的人無效")
	boss.state = "fill"
	sim._apply_effects(wen, boss, always.call("seal"))
	_check(boss.state == "stun" and boss.timer == 45, "點穴：首領的持續時間減半", "%s %d" % [boss.state, boss.timer])

	# 狀態到時間會消失
	var s2 := _new_battle("test_a")
	var y := s2.unit("yanhui")
	s2._apply_effects(y, y, always.call("empower"))
	for i in 12 * 30 - 1:
		s2._tick_statuses(y)
	var still := y.has_status("empower")
	s2._tick_statuses(y)
	_check(still and not y.has_status("empower"), "運功持續 12 秒後消失")


## 守勢、調息、出招扣內力、蓄招與收招。
func _test_battle_commands() -> void:
	var sim := _new_battle("test_a", 1, true)
	var y := sim.unit("yanhui")
	y.posture = 50
	sim._act(y, {"type": "guard"})
	_check(y.guarding and is_equal_approx(y.posture, 50 + 114 * 0.3) and is_equal_approx(y.gauge, 30), "守勢：回 30% 架勢，行動條從 30 開始")
	y.mp = 100
	sim._act(y, {"type": "rest"})
	_check(not y.guarding and is_equal_approx(y.mp, 100 + 194 * 0.25) and y.gauge == 0.0, "調息：回 25% 內力，守勢解除，行動條從 0 開始")
	y.mp = 194
	sim._act(y, {"type": "move", "move": "yanhui_guiyi", "target": "bandit#1"})
	_check(y.state == "charge" and y.timer == 75 and is_equal_approx(y.mp, 194 - 45), "蓄招：先扣內力，蓄 2.5 秒", "%s %d %.0f" % [y.state, y.timer, y.mp])
	y.timer = 1
	sim._events = []
	sim.step()
	_check(y.state == "recover" and y.timer == 30 and y.gauge == 0.0, "出招後收招 1 秒，行動條從 0 開始", "%s %d" % [y.state, y.timer])
	var shen := sim.unit("shen")
	shen.mp = 10
	_check(not sim.is_valid(shen, {"type": "move", "move": "shen_feihua", "target": "bandit#1"}), "內力不夠的招式不能用")
	_check(not sim.is_valid(shen, {"type": "move", "move": "shen_dianxing", "target": "yanhui"}), "攻擊招式不能打自己人")
	_check(sim.is_valid(sim.unit("wen"), {"type": "move", "move": "wen_huxin", "target": "huo"}), "護體可以給隊友")
	_check(not sim.is_valid(shen, {"type": "move", "move": "huo_hengzhan", "target": "bandit#1"}), "不能用別人的招式")


## 等待模式：我方手動角色的行動條滿了，時間停下來等指令。
func _test_battle_waits_for_player() -> void:
	var sim := _new_battle("test_a", 5, true)
	var guard := 0
	while sim.waiting().is_empty() and guard < 3000:
		sim.step()
		guard += 1
	var who := sim.waiting()[0] if not sim.waiting().is_empty() else ""
	_check(who == "shen", "身法最高的沈清禾最先輪到", who)
	var tick := sim.tick
	var empty := sim.step()
	_check(empty.is_empty() and sim.tick == tick, "等玩家下指令時時間不前進")
	_check(not sim.needs_target("shen_feihua") and sim.needs_target("wen_huxin") and not sim.needs_target("yanhui_ningqi"), "全體與自身的招式不用選目標")
	var events: Variant = sim.command("yanhui", {"type": "guard"})
	_check(events == null, "沒輪到的人不能下指令")
	events = sim.command(who, {"type": "move", "move": "shen_dianxing", "target": "bandit#1"})
	_check(events != null and (events as Array).any(func(e: Dictionary) -> bool: return e["type"] == "act"), "輪到的人下指令後立刻出招")
	sim.step()
	_check(sim.tick == tick + 1 or not sim.waiting().is_empty(), "下完指令時間繼續走")
	# 手動打完一整場：每次都用普攻打第一個敵人
	var full := _new_battle("test_a", 9, true)
	var steps := 0
	while not full.finished and steps < 100000:
		for id in full.waiting():
			var foes := full.foes_of(full.unit(id))
			var basic: String = full.unit(id).moves[0]
			full.command(id, {"type": "move", "move": basic, "target": foes[0].id})
		full.step()
		steps += 1
	_check(full.finished and full.result == "win", "全手動也能打完試煉甲", "%s %s" % [full.result, full.seconds()])


## 自動出招：敵人的條件規則、我方的兩種戰術。
func _test_battle_ai() -> void:
	var BattleAI := preload("res://core/battle/battle_ai.gd")
	var sim := _new_battle("test_d")
	var wen := sim.unit("wen")
	var huo := sim.unit("huo")
	huo.hp = 200
	var choice := BattleAI.decide(sim, wen)
	_check(choice.get("move") == "wen_huichun" and choice.get("target") == "huo", "支援優先：隊友氣血低於一半時先治療", str(choice))
	huo.hp = huo.hp_max
	var boss := sim.unit("third_chief#1")
	boss.state = "charge"
	boss.pending = {"move": "third_fuhai", "target": "huo"}
	choice = BattleAI.decide(sim, wen)
	_check(choice.get("move") == "wen_huxin", "支援優先：敵人蓄大招時先給隊友上護體", str(choice))
	boss.state = "fill"
	boss.pending = {}
	var archer := sim.unit("archer#1")
	archer.state = "stagger"
	archer.timer = 150
	choice = BattleAI.decide(sim, huo)
	_check(choice.get("target") == archer.id, "全力進攻：先打破綻中的敵人", str(choice))
	_check(choice.get("move") == "huo_duanyue", "全力進攻：用預估傷害最高的招式", str(choice))
	var y := sim.unit("yanhui")
	y.mp = 0
	choice = BattleAI.decide(sim, y)
	_check(choice.get("move") == "yanhui_zhici", "內力不夠時只用不耗內力的招式", str(choice))

	# 敵人的條件規則：我方有人蓄招時，三當家有一半機會對他用震脈掌
	var hits := 0
	var to_charger := 0
	for i in 200:
		var s := _new_battle("test_d", i)
		s.unit("yanhui").state = "charge"
		s.unit("yanhui").pending = {"move": "yanhui_guiyi", "target": "third_chief#1"}
		var c := BattleAI.decide(s, s.unit("third_chief#1"))
		if c.get("move") == "third_zhenmai":
			hits += 1
			if c.get("target") == "yanhui":
				to_charger += 1
	_check(hits > 100 and hits < 160 and to_charger > 85, "條件規則：我方蓄招時三當家約一半機會用震脈掌打蓄招的人", "%d/%d" % [to_charger, hits])
	var weights: Dictionary = {}
	for i in 400:
		var s := _new_battle("test_a", i)
		var c := BattleAI.decide(s, s.unit("bandit#1"))
		weights[c["move"]] = int(weights.get(c["move"], 0)) + 1
	var ratio := float(weights.get("bandit_hack", 0)) / 400.0
	_check(ratio > 0.68 and ratio < 0.82, "權重表：嘍囉亂砍 3、猛劈 1，大約七成五用亂砍", "%.2f" % ratio)


## 同一個種子重跑結果完全相同（12.3、13.5）。
func _test_battle_is_repeatable() -> void:
	var logs: Array[String] = []
	for run in 3:
		var sim := _new_battle("test_d", 7 if run < 2 else 8)
		var log := PackedStringArray()
		while not sim.finished:
			for e in sim.step():
				log.append(JSON.stringify(e))
		logs.append("\n".join(log))
	_check(logs[0] == logs[1] and logs[0].length() > 1000, "同一個種子跑兩次，每一拍的事件完全相同")
	_check(logs[0] != logs[2], "換一個種子，經過不同")


## 四場測試遭遇用自動戰術都能分出勝負（13.5）。
func _test_battle_encounters_finish() -> void:
	var results: Array[String] = []
	var ok := true
	for enc: String in ["test_a", "test_b", "test_c", "test_d"]:
		var sim := _new_battle(enc, 3)
		while not sim.finished:
			sim.step()
		results.append("%s %s %.0f 秒" % [enc, sim.result, sim.seconds()])
		ok = ok and sim.result in ["win", "lose"]
	_check(ok, "四場測試遭遇都能打到分出勝負", "；".join(results))


## 驗證器抓得到戰鬥資料寫錯的地方。
func _test_battle_validator() -> void:
	var checker := GameData.new()
	checker.load_all()
	checker.moves["huo_bengshan"]["charge"] = -1
	checker.moves["shen_duanliu"]["tags"] = ["cut"]
	checker.enemies["bandit"]["moves"][0]["move"] = "no_such_move"
	checker.encounters["test_a"]["enemies"].append("ghost")
	checker.errors.clear()
	checker._validate()
	_check(checker.errors.size() == 4, "抓得到寫錯的蓄招時間、標籤、敵人招式、遭遇裡的敵人", "；".join(checker.errors))


func _check(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  通過　%s" % name)
	else:
		_failed += 1
		print("  失敗　%s%s" % [name, ("　→ " + detail) if detail != "" else ""])
