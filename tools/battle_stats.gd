extends SceneTree
## 用遊戲本身的戰鬥規則與隊友自動戰術，把四場測試遭遇各跑很多場，印出統計（設計文件第 14 章）。
## 不開視窗。
##
## 執行方式（在專案根目錄）：
##   godot --headless --path . -s res://tools/battle_stats.gd
##   godot --headless --path . -s res://tools/battle_stats.gd -- --runs=400 --tactics=attack,attack,attack,support --md
##
## --tactics 依序是燕回、沈清禾、霍嶽、溫蘅的戰術（attack 全力進攻、support 支援優先）。
## 估計時間 = 戰鬥邏輯時間 + 每次行動 1 秒的演出（和 tools/balance_sim.py 相同的算法）。

const GameData := preload("res://core/data/game_data.gd")
const BattleSim := preload("res://core/battle/battle_sim.gd")

const ENCOUNTERS := ["test_a", "test_b", "test_c", "test_d"]
const SHOW_SECONDS := 1.0


func _initialize() -> void:
	var args := {"runs": "400", "tactics": "attack,attack,attack,support"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
		elif arg.begins_with("--"):
			args[arg.substr(2)] = "1"
	var data := GameData.new()
	if not data.load_all():
		printerr("；".join(data.errors))
		quit(1)
		return
	var runs := int(args["runs"])
	var tactics: PackedStringArray = str(args["tactics"]).split(",")
	var md := args.has("md")
	if args.has("log"):
		# 印出一場的完整經過：--log=test_d --seed=3
		_print_log(data, str(args["log"]), int(args.get("seed", "0")), tactics)
		quit(0)
		return
	print("戰術：%s，每種遭遇 %d 場" % [", ".join(tactics), runs])
	if md:
		print("| 遭遇 | 勝率 | 我方行動 | 敵方行動 | 估計時間 | 戰後氣血 | 平均倒下人數 | 破綻 | 打斷 |")
		print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for enc in ENCOUNTERS:
		var rows: Array[Dictionary] = []
		for seed_value in runs:
			rows.append(_run(data, enc, seed_value, tactics))
		var wins := rows.filter(func(r: Dictionary) -> bool: return r["result"] == "win").size()
		var line := [
			data.text(str(data.encounters[enc]["name"])),
			"%d%%" % roundi(wins * 100.0 / runs),
			"%d" % roundi(_median(rows, "party_actions")),
			"%d" % roundi(_median(rows, "enemy_actions")),
			"%d 秒" % roundi(_median(rows, "est_seconds")),
			"%d%%" % roundi(_median(rows, "hp_left") * 100.0),
			"%.2f" % _mean(rows, "downs"),
			"%d" % roundi(_median(rows, "staggers")),
			"%.2f" % _mean(rows, "interrupts"),
		]
		if md:
			print("| " + " | ".join(line) + " |")
		else:
			print("%s　勝率 %s　我方 %s 次　敵方 %s 次　%s　剩餘氣血 %s　倒下 %s　破綻 %s　打斷 %s" % line)
	quit(0)


func _run(data: GameData, enc: String, seed_value: int, tactics: PackedStringArray) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(data, enc, seed_value)
	var party := sim.side_units("party", false)
	for i in party.size():
		party[i].auto = tactics[mini(i, tactics.size() - 1)]
	while not sim.finished:
		sim.step()
	var party_actions := 0
	var enemy_actions := 0
	var hp := 0
	var hp_max := 0
	var downs := 0
	for u in sim.units:
		if u.side == "party":
			party_actions += u.actions
			hp += u.hp
			hp_max += u.hp_max
			if not u.alive():
				downs += 1
		else:
			enemy_actions += u.actions
	return {
		"result": sim.result,
		"party_actions": party_actions,
		"enemy_actions": enemy_actions,
		"est_seconds": sim.seconds() + (party_actions + enemy_actions) * SHOW_SECONDS,
		"hp_left": hp / float(hp_max),
		"downs": downs,
		"staggers": sim.stats["staggers"],
		"interrupts": sim.stats["interrupts"],
	}


func _print_log(data: GameData, enc: String, seed_value: int, tactics: PackedStringArray) -> void:
	var sim := BattleSim.new()
	sim.setup(data, enc, seed_value)
	var party := sim.side_units("party", false)
	for i in party.size():
		party[i].auto = tactics[mini(i, tactics.size() - 1)]
	for u in sim.units:
		print("%s　氣血 %d　內力 %d　架勢 %d　速度 %.1f" % [u.display_name, u.hp_max, u.mp_max, u.posture_max, sim.speed(u)])
	while not sim.finished:
		for e in sim.step():
			print("%6.2f 秒　%s" % [e["tick"] / 30.0, _describe(sim, e)])


func _describe(sim: BattleSim, e: Dictionary) -> String:
	var who := ""
	if e.has("unit") and sim.unit(str(e["unit"])) != null:
		who = sim.unit(str(e["unit"])).display_name
	var src := ""
	if e.has("source") and sim.unit(str(e["source"])) != null:
		src = sim.unit(str(e["source"])).display_name
	match str(e["type"]):
		"charge":
			return "%s 開始蓄 %s（%.1f 秒）" % [who, sim.data.move_name(str(e["move"])), e["seconds"]]
		"act":
			return "%s 出招 %s" % [who, sim.data.move_name(str(e["move"]))]
		"damage":
			return "　%s 受到 %d%s（剩 %d）" % [who, e["amount"], "（會心）" if e["crit"] else "", e["hp"]]
		"heal":
			return "　%s 回復 %d（%s）" % [who, e["amount"], src]
		"posture":
			return "　%s 架勢 %d/%d" % [who, e["value"], e["max"]]
		"dodge":
			return "　%s 閃過" % who
		"stagger":
			return "　%s 露出破綻" % who
		"interrupt":
			return "　%s 的 %s 被打斷" % [who, sim.data.move_name(str(e["move"]))]
		"status":
			return "　%s 中了 %s（%d 層）" % [who, e["status"], e["stacks"]]
		"dot":
			return "　%s 流失 %d（剩 %d）" % [who, e["amount"], e["hp"]]
		"down":
			return "　%s 倒下" % who
		"end":
			return "結束：%s" % e["result"]
	return "%s %s" % [who, e["type"]]


func _median(rows: Array[Dictionary], key: String) -> float:
	var values: Array = rows.map(func(r: Dictionary) -> float: return float(r[key]))
	values.sort()
	var n := values.size()
	return values[n / 2] if n % 2 == 1 else (values[n / 2 - 1] + values[n / 2]) / 2.0


func _mean(rows: Array[Dictionary], key: String) -> float:
	var total := 0.0
	for r in rows:
		total += float(r[key])
	return total / rows.size()
