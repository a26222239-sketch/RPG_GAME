extends RefCounted
## 戰鬥規則（設計文件第 4 章）。只算規則，不碰畫面，可以在無視窗模式下跑完一整場。
##
## 用法：
##   var sim := BattleSim.new()
##   sim.setup(Game.data, "test_a", 種子)
##   每一拍呼叫 step()，回傳這一拍發生的事件（陣列，可能是空的）。
##   waiting() 不是空的，表示有我方手動角色的行動條滿了，在等玩家下指令：
##     這時 step() 不會讓時間前進（等待模式，4.3），玩家選好之後呼叫 command()。
##   finished 為真時戰鬥結束，result 是 "win" 或 "lose"。
##
## 時間是固定步長，每秒 30 拍；亂數只用 setup 給的種子。
## 同樣的種子加上同樣的指令，結果一定相同（12.3）。
##
## 數值與 tools/balance_sim.py（設計階段的參考實作）相同；那支程式的輸出是設計文件第 14 章的來源。

const GameData := preload("res://core/data/game_data.gd")

const TICKS_PER_SECOND := 30
## 可調的數值（設計文件 3.2、4.2–4.9）。
const P := {
	"hp_base": 200.0, "hp_jingu": 15.0, "hp_neixi": 5.0,
	"mp_base": 50.0, "mp_neixi": 8.0,
	"posture_base": 60.0, "posture_jingu": 2.0, "posture_neixi": 1.0,
	"attack_base": 20.0, "attack_mul": 2.0,
	"speed_base": 12.0, "speed_shenfa": 0.4,
	"crit_base": 0.05, "crit_wuxing": 0.002, "crit_max": 0.4, "crit_mul": 1.5,
	"dodge_base": 0.05, "dodge_shenfa": 0.003, "dodge_max": 0.3,
	"stagger_time": 5.0, "stagger_damage": 1.5, "stagger_grow": 1.25,
	"posture_regen": 0.02,
	"guard_damage": 0.6, "guard_posture": 0.4, "guard_heal": 0.3, "guard_gauge": 30.0,
	"rest_mp": 0.25, "rest_posture": 0.2,
	"interrupt": 2.5, "charge_open": 1.5,
	"matchup_win": 1.25, "matchup_lose": 0.8,
	"bleed": 0.015, "poison": 0.01, "boss_dot": 0.5, "boss_seal": 0.5,
	"internal_cost": 1.25, "slow": 0.7, "light": 1.3, "empower": 1.25, "protect": 0.75,
	"variance": 0.05,
	"time_limit": 900.0,
}
## 勁路對應的能力值，以及相剋（攻方勁路 → 被它剋的心法勁路）。
const FORCE_ATTR := {"gang": "jingu", "rou": "neixi", "kuai": "shenfa"}
const BEATS := {"gang": "kuai", "rou": "gang", "kuai": "rou"}


## 戰場上的一個人。
class Unit:
	var id: String
	var source: String           # characters.json 或 enemies.json 的識別碼
	var side: String             # "party" 或 "enemy"
	var display_name: String
	var boss: bool = false
	var attrs: Dictionary = {}
	var force: String = ""       # 心法的勁路，決定防守時的相剋
	var guard_value: float = 0.0 # 心法護體值
	var regen: float = 0.0       # 每秒回幾點內力
	var moves: Array = []        # 招式識別碼
	var weights: Dictionary = {} # 敵人：招式 → 權重
	var rules: Array = []
	var targeting: String = "random"
	var hp_max: int = 1
	var mp_max: int = 0
	var posture_max: float = 1.0
	var hp: int = 1
	var mp: float = 0.0
	var posture: float = 1.0
	var gauge: float = 0.0
	## fill 跑行動條、wait 等玩家下指令、charge 蓄招、recover 收招、stagger 破綻、stun 被點穴、down 倒下
	var state: String = "fill"
	var timer: int = 0           # 目前狀態還剩幾拍
	var pending: Dictionary = {} # 蓄招中：{ move, target }
	var guarding: bool = false   # 守勢，直到自己下一次行動
	var statuses: Dictionary = {} # 狀態 → { ticks, stacks }
	var auto: String = ""        # 我方：空字串是玩家手動，否則是自動戰術（attack、support）
	var actions: int = 0

	func alive() -> bool:
		return state != "down"

	func has_status(status: String) -> bool:
		return statuses.has(status)


var data: GameData
var encounter_id: String = ""
var units: Array[Unit] = []
var tick: int = 0
var finished: bool = false
var result: String = ""
var stats: Dictionary = {"staggers": 0, "interrupts": 0, "heals": 0, "dodges": 0, "crits": 0}

var _rng := RandomNumberGenerator.new()
var _waiting: Array[String] = []
var _events: Array[Dictionary] = []
var _by_id: Dictionary = {}


## 建立一場戰鬥。encounter 是 encounters.json 的識別碼。
func setup(game_data: GameData, encounter: String, seed_value: int) -> void:
	data = game_data
	encounter_id = encounter
	_rng.seed = seed_value
	units.clear()
	_by_id.clear()
	var enc: Dictionary = data.encounters[encounter]
	for char_id: String in enc["party"]:
		_add(_make_hero(char_id))
	var counts: Dictionary = {}
	for enemy_id: String in enc["enemies"]:
		counts[enemy_id] = int(counts.get(enemy_id, 0)) + 1
	var seen: Dictionary = {}
	for enemy_id: String in enc["enemies"]:
		seen[enemy_id] = int(seen.get(enemy_id, 0)) + 1
		var suffix := "" if int(counts[enemy_id]) == 1 else "甲乙丙丁戊"[int(seen[enemy_id]) - 1]
		_add(_make_enemy(enemy_id, "%s#%d" % [enemy_id, seen[enemy_id]], suffix))


func unit(unit_id: String) -> Unit:
	return _by_id.get(unit_id)


func side_units(side: String, alive_only: bool = true) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.side == side and (u.alive() or not alive_only):
			out.append(u)
	return out


func foes_of(u: Unit) -> Array[Unit]:
	return side_units("enemy" if u.side == "party" else "party")


func allies_of(u: Unit) -> Array[Unit]:
	return side_units(u.side)


## 在等玩家下指令的我方角色（照輪到的順序）。
func waiting() -> Array[String]:
	return _waiting.duplicate()


func seconds() -> float:
	return tick / float(TICKS_PER_SECOND)


## 前進一拍。等玩家下指令或戰鬥結束時，時間不前進，回傳空陣列。
func step() -> Array[Dictionary]:
	_events = []
	if finished or not _waiting.is_empty():
		return _events
	tick += 1
	var new_second := tick % TICKS_PER_SECOND == 0
	var ready: Array[Unit] = []
	for u in units:
		if not u.alive():
			continue
		if new_second:
			_per_second(u)
			if not u.alive():
				continue
		_tick_statuses(u)
		match u.state:
			"fill":
				u.gauge += speed(u) / TICKS_PER_SECOND
				if u.gauge >= 100.0:
					u.gauge = 100.0
					ready.append(u)
			"charge":
				u.timer -= 1
				if u.timer <= 0:
					_finish(u)
			"recover":
				u.timer -= 1
				if u.timer <= 0:
					u.state = "fill"
			"stagger":
				u.timer -= 1
				if u.timer <= 0:
					if u.boss:
						u.posture_max = roundf(u.posture_max * P["stagger_grow"])
					u.posture = u.posture_max
					u.state = "fill"
					_emit({"type": "stagger_end", "unit": u.id})
			"stun":
				u.timer -= 1
				if u.timer <= 0:
					u.state = "fill"
					_emit({"type": "status_end", "unit": u.id, "status": "seal"})
		if _check_end():
			return _events
	# 同一拍有多人行動條滿時，身法高的先動
	ready.sort_custom(func(a: Unit, b: Unit) -> bool: return float(a.attrs["shenfa"]) > float(b.attrs["shenfa"]))
	for u in ready:
		if _check_end():
			break
		if not u.alive() or u.state != "fill":
			continue
		if u.side == "party" and u.auto == "":
			u.state = "wait"
			_waiting.append(u.id)
			_emit({"type": "ready", "unit": u.id})
		else:
			_act(u, decide(u))
	_check_end()
	if tick >= int(P["time_limit"]) * TICKS_PER_SECOND and not finished:
		finished = true
		result = "timeout"
		_emit({"type": "end", "result": result})
	return _events


## 玩家下指令。choice 是 { type: "move", move, target } 或 { type: "guard" } 或 { type: "rest" }。
## 指令不合規則時回傳 null，什麼都不改；否則回傳這個指令立刻造成的事件。
func command(unit_id: String, choice: Dictionary) -> Variant:
	var u := unit(unit_id)
	if u == null or not _waiting.has(unit_id) or not is_valid(u, choice):
		return null
	_waiting.erase(unit_id)
	u.state = "fill"
	_events = []
	_act(u, choice)
	_check_end()
	return _events


## 這個指令現在能不能下。
func is_valid(u: Unit, choice: Dictionary) -> bool:
	match str(choice.get("type", "")):
		"guard", "rest":
			return true
		"move":
			var move_id := str(choice.get("move", ""))
			if not u.moves.has(move_id) or not can_afford(u, move_id):
				return false
			var target := unit(str(choice.get("target", "")))
			return valid_target(u, move_id, target)
	return false


func can_afford(u: Unit, move_id: String) -> bool:
	return u.mp + 0.0001 >= cost_of(u, move_id)


func cost_of(u: Unit, move_id: String) -> float:
	if u.side == "enemy":
		return 0.0  # 原型中敵人的招式不耗內力（13.3）
	var cost := float(data.moves[move_id]["cost"])
	return cost * (float(P["internal_cost"]) if u.has_status("internal") else 1.0)


## 招式要不要選目標，以及這個目標合不合法。全體與自身的招式，目標填誰都可以（不用選）。
func needs_target(move_id: String) -> bool:
	return str(data.moves[move_id]["target"]) in ["enemy_single", "ally_single"]


func valid_target(u: Unit, move_id: String, target: Unit) -> bool:
	var kind := str(data.moves[move_id]["target"])
	if kind == "enemy_single":
		return target != null and target.alive() and target.side != u.side
	if kind == "ally_single":
		return target != null and target.alive() and target.side == u.side
	return true


## 自動的一方怎麼選（敵人的權重與規則、我方的自動戰術）。寫在 battle_ai.gd。
func decide(u: Unit) -> Dictionary:
	return preload("res://core/battle/battle_ai.gd").decide(self, u)


func random_float() -> float:
	return _rng.randf()


## 依權重抽一個。
func weighted_pick(options: Array, weights: Array) -> Variant:
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := _rng.randf() * total
	for i in options.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


func random_pick(options: Array) -> Variant:
	return options[_rng.randi_range(0, options.size() - 1)]


# ---------------------------------------------------------------- 公式（3.2、4.5–4.8）

func speed(u: Unit) -> float:
	var v := float(P["speed_base"]) + float(u.attrs["shenfa"]) * float(P["speed_shenfa"])
	if u.has_status("light"):
		v *= float(P["light"])
	if u.has_status("slow"):
		v *= float(P["slow"])
	return v


func attack_value(u: Unit, force: String) -> float:
	var attr := str(FORCE_ATTR.get(force, "neixi"))
	var v := float(P["attack_base"]) + float(u.attrs[attr]) * float(P["attack_mul"])
	if u.has_status("empower"):
		v *= float(P["empower"])
	return v


func defense(u: Unit) -> float:
	return float(u.attrs["jingu"]) + float(u.attrs["neixi"]) + u.guard_value


func matchup(move_force: String, target_force: String) -> float:
	if move_force == "" or target_force == "":
		return 1.0
	if BEATS.get(move_force) == target_force:
		return float(P["matchup_win"])
	if BEATS.get(target_force) == move_force:
		return float(P["matchup_lose"])
	return 1.0


func crit_rate(u: Unit) -> float:
	return minf(float(P["crit_max"]), float(P["crit_base"]) + float(u.attrs["wuxing"]) * float(P["crit_wuxing"]))


func dodge_rate(attacker: Unit, target: Unit) -> float:
	var v := float(P["dodge_base"]) + (float(target.attrs["shenfa"]) - float(attacker.attrs["shenfa"])) * float(P["dodge_shenfa"])
	return clampf(v, 0.0, float(P["dodge_max"]))


## 不含會心與浮動的傷害（自動戰術估算用）。
func expected_damage(attacker: Unit, move_id: String, target: Unit) -> float:
	var m: Dictionary = data.moves[move_id]
	var d := attack_value(attacker, str(m["force"])) * float(m["power"]) * 100.0 / (100.0 + defense(target))
	d *= matchup(str(m["force"]), target.force)
	if target.state == "stagger":
		d *= float(P["stagger_damage"])
	if target.guarding:
		d *= float(P["guard_damage"])
	if target.has_status("protect"):
		d *= float(P["protect"])
	return d


# ---------------------------------------------------------------- 行動

func _act(u: Unit, choice: Dictionary) -> void:
	if foes_of(u).is_empty():
		return
	u.guarding = false
	u.actions += 1
	match str(choice.get("type", "")):
		"guard":
			u.guarding = true
			u.posture = minf(u.posture_max, u.posture + u.posture_max * float(P["guard_heal"]))
			u.gauge = float(P["guard_gauge"])
			u.state = "fill"
			_emit({"type": "guard", "unit": u.id})
		"rest":
			u.mp = minf(u.mp_max, u.mp + u.mp_max * float(P["rest_mp"]))
			u.posture = minf(u.posture_max, u.posture + u.posture_max * float(P["rest_posture"]))
			u.gauge = 0.0
			u.state = "fill"
			_emit({"type": "rest", "unit": u.id})
		"move":
			var move_id := str(choice["move"])
			var m: Dictionary = data.moves[move_id]
			u.mp = maxf(0.0, u.mp - cost_of(u, move_id))
			u.pending = {"move": move_id, "target": str(choice.get("target", ""))}
			var charge := int(roundf(float(m["charge"]) * TICKS_PER_SECOND))
			if charge > 0:
				u.state = "charge"
				u.timer = charge
				_emit({"type": "charge", "unit": u.id, "move": move_id, "target": u.pending["target"], "seconds": float(m["charge"])})
			else:
				_finish(u)


## 出招：結算招式，然後收招。
func _finish(u: Unit) -> void:
	var move_id := str(u.pending["move"])
	var target := unit(str(u.pending["target"]))
	u.pending = {}
	var m: Dictionary = data.moves[move_id]
	u.gauge = 0.0
	var recover := int(roundf(float(m["recover"]) * TICKS_PER_SECOND))
	u.state = "recover" if recover > 0 else "fill"
	u.timer = recover
	if foes_of(u).is_empty():
		u.state = "fill"
		return
	var targets := _resolve_targets(u, move_id, target)
	var ids: Array[String] = []
	for t in targets:
		ids.append(t.id)
	_emit({"type": "act", "unit": u.id, "move": move_id, "targets": ids})
	match str(m["kind"]):
		"attack", "control":
			for t in targets:
				_hit(u, t, move_id)
		"heal":
			for t in targets:
				var amount := int(roundf(attack_value(u, "rou") * float(m["power"])))
				var before := t.hp
				t.hp = mini(t.hp_max, t.hp + amount)
				stats["heals"] += 1
				_emit({"type": "heal", "unit": t.id, "source": u.id, "amount": t.hp - before, "hp": t.hp})
				_apply_effects(u, t, m)
		"buff":
			for t in targets:
				_apply_effects(u, t, m)


func _resolve_targets(u: Unit, move_id: String, target: Unit) -> Array[Unit]:
	var kind := str(data.moves[move_id]["target"])
	var out: Array[Unit] = []
	match kind:
		"enemy_all":
			out = foes_of(u)
		"ally_all":
			out = allies_of(u)
		"self":
			out = [u]
		"enemy_single":
			if target != null and target.alive() and target.side != u.side:
				out = [target]
			else:
				# 目標已經倒下：改打氣血最少的
				var foes := foes_of(u)
				foes.sort_custom(func(a: Unit, b: Unit) -> bool: return a.hp < b.hp)
				out = [foes[0]]
		"ally_single":
			if target != null and target.alive() and target.side == u.side:
				out = [target]
			else:
				var allies := allies_of(u)
				allies.sort_custom(func(a: Unit, b: Unit) -> bool: return a.hp / float(a.hp_max) < b.hp / float(b.hp_max))
				out = [allies[0]]
	return out


## 打中一個人（4.5、4.7）。
func _hit(src: Unit, tgt: Unit, move_id: String) -> void:
	if not tgt.alive():
		return
	var m: Dictionary = data.moves[move_id]
	if tgt.state != "stagger" and tgt.state != "stun" and _rng.randf() < dodge_rate(src, tgt):
		stats["dodges"] += 1
		_emit({"type": "dodge", "unit": tgt.id, "source": src.id})
		return
	var rel := matchup(str(m["force"]), tgt.force)
	var d := expected_damage(src, move_id, tgt)
	var crit := _rng.randf() < crit_rate(src)
	if crit:
		d *= float(P["crit_mul"])
		stats["crits"] += 1
	var variance := float(P["variance"])
	var amount := int(roundf(d * _rng.randf_range(1.0 - variance, 1.0 + variance)))
	tgt.hp = maxi(0, tgt.hp - amount)
	_emit({"type": "damage", "unit": tgt.id, "source": src.id, "amount": amount, "hp": tgt.hp, "crit": crit, "matchup": rel})

	# 架勢
	if tgt.hp > 0 and tgt.state != "stagger":
		var posture_damage := float(m["posture"]) * rel
		if tgt.state == "charge":
			posture_damage *= float(P["interrupt"]) if "interrupt" in m.get("tags", []) else float(P["charge_open"])
		if tgt.guarding:
			posture_damage *= float(P["guard_posture"])
		tgt.posture = maxf(0.0, tgt.posture - posture_damage)
		_emit({"type": "posture", "unit": tgt.id, "value": tgt.posture, "max": tgt.posture_max})
		if tgt.posture <= 0.0:
			if tgt.state == "charge":
				stats["interrupts"] += 1
				_emit({"type": "interrupt", "unit": tgt.id, "move": str(tgt.pending.get("move", ""))})
				tgt.pending = {}
			tgt.state = "stagger"
			tgt.timer = int(float(P["stagger_time"]) * TICKS_PER_SECOND)
			tgt.guarding = false
			stats["staggers"] += 1
			_emit({"type": "stagger", "unit": tgt.id, "seconds": float(P["stagger_time"])})

	if tgt.hp <= 0:
		_down(tgt)
		return
	_apply_effects(src, tgt, m)


func _apply_effects(src: Unit, tgt: Unit, m: Dictionary) -> void:
	for effect: Dictionary in m.get("effects", []):
		var status := str(effect["status"])
		var chance := float(effect["chance"])
		var seconds_left := float(data.statuses[status]["duration"])
		if status == "seal" and tgt.boss:
			chance *= float(P["boss_seal"])
			seconds_left *= float(P["boss_seal"])
		if chance < 1.0 and _rng.randf() >= chance:
			continue
		var ticks := int(roundf(seconds_left * TICKS_PER_SECOND))
		if status == "seal":
			# 點穴：行動條停止；對蓄招、收招、破綻中的人無效
			if tgt.state != "fill":
				continue
			tgt.state = "stun"
			tgt.timer = ticks
		var stacks := 1
		if tgt.statuses.has(status):
			stacks = int(tgt.statuses[status]["stacks"])
			if status == "poison":
				stacks = mini(int(data.statuses[status].get("max_stacks", 1)), stacks + 1)
		if status != "seal":
			tgt.statuses[status] = {"ticks": ticks, "stacks": stacks}
		_emit({"type": "status", "unit": tgt.id, "status": status, "stacks": stacks, "seconds": seconds_left, "source": src.id})


func _per_second(u: Unit) -> void:
	if not u.has_status("internal"):
		u.mp = minf(u.mp_max, u.mp + u.regen)
	if u.state != "stagger":
		u.posture = minf(u.posture_max, u.posture + u.posture_max * float(P["posture_regen"]))
	var dot := 0
	if u.has_status("bleed"):
		dot += int(roundf(u.hp_max * float(P["bleed"]) * (float(P["boss_dot"]) if u.boss else 1.0)))
	if u.has_status("poison"):
		dot += int(roundf(u.hp_max * float(P["poison"]) * int(u.statuses["poison"]["stacks"]) * (float(P["boss_dot"]) if u.boss else 1.0)))
	if dot > 0:
		u.hp = maxi(0, u.hp - dot)
		_emit({"type": "dot", "unit": u.id, "amount": dot, "hp": u.hp})
		if u.hp <= 0:
			_down(u)


func _tick_statuses(u: Unit) -> void:
	for status: String in u.statuses.keys():
		var entry: Dictionary = u.statuses[status]
		entry["ticks"] = int(entry["ticks"]) - 1
		if int(entry["ticks"]) <= 0:
			u.statuses.erase(status)
			_emit({"type": "status_end", "unit": u.id, "status": status})


func _down(u: Unit) -> void:
	u.state = "down"
	u.hp = 0
	u.pending = {}
	u.guarding = false
	u.statuses.clear()
	_waiting.erase(u.id)
	_emit({"type": "down", "unit": u.id})


func _check_end() -> bool:
	if finished:
		return true
	if side_units("party").is_empty():
		finished = true
		result = "lose"
	elif side_units("enemy").is_empty():
		finished = true
		result = "win"
	if finished:
		_waiting.clear()
		_emit({"type": "end", "result": result})
	return finished


func _emit(event: Dictionary) -> void:
	event["tick"] = tick
	_events.append(event)


# ---------------------------------------------------------------- 建立角色

func _add(u: Unit) -> void:
	units.append(u)
	_by_id[u.id] = u


func _make_hero(char_id: String) -> Unit:
	var c: Dictionary = data.characters[char_id]
	var art: Dictionary = data.inner_arts[str(c["inner_art"])]
	var u := Unit.new()
	u.id = char_id
	u.source = char_id
	u.side = "party"
	u.display_name = data.character_name(char_id)
	u.attrs = (c["attrs"] as Dictionary).duplicate()
	u.force = str(art["force"])
	u.guard_value = float(art["guard"])
	u.regen = float(art["regen"])
	u.moves = (c["moves"] as Array).duplicate()
	_derive(u, 1.0)
	return u


func _make_enemy(enemy_id: String, unit_id: String, suffix: String) -> Unit:
	var e: Dictionary = data.enemies[enemy_id]
	var u := Unit.new()
	u.id = unit_id
	u.source = enemy_id
	u.side = "enemy"
	u.display_name = data.enemy_name(enemy_id) + suffix
	u.boss = bool(e.get("boss", false))
	u.attrs = (e["attrs"] as Dictionary).duplicate()
	u.force = str(e["inner_art"]["force"])
	u.guard_value = float(e["inner_art"]["guard"])
	u.regen = float(e["inner_art"]["regen"])
	for entry: Dictionary in e["moves"]:
		u.moves.append(str(entry["move"]))
		u.weights[str(entry["move"])] = float(entry["weight"])
	u.rules = e.get("rules", [])
	u.targeting = str(e.get("targeting", "random"))
	_derive(u, float(e["hp_scale"]))
	return u


## 衍生數值（3.2）。
func _derive(u: Unit, hp_scale: float) -> void:
	var jingu := float(u.attrs["jingu"])
	var neixi := float(u.attrs["neixi"])
	u.hp_max = int(roundf((float(P["hp_base"]) + jingu * float(P["hp_jingu"]) + neixi * float(P["hp_neixi"])) * hp_scale))
	u.mp_max = int(float(P["mp_base"]) + neixi * float(P["mp_neixi"]))
	u.posture_max = float(P["posture_base"]) + jingu * float(P["posture_jingu"]) + neixi * float(P["posture_neixi"])
	u.hp = u.hp_max
	u.mp = u.mp_max
	u.posture = u.posture_max
