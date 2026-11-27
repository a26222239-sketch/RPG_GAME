extends RefCounted
## 自動出招（設計文件 4.10、4.11）：敵人的權重表與條件規則，以及我方隊友的自動戰術。
## 只讀戰鬥的狀態、回傳一個指令，不改任何東西；亂數用戰鬥本身的種子。
##
## 我方的戰術（M1 做兩種）：
##   attack   全力進攻：用預估傷害最高、內力付得起的招式，打破綻中或氣血最少的敵人
##   support  支援優先：有人氣血低於一半先治療；有人沒有護體、敵人在蓄大招時先上護體；
##            自己的增益沒開時先開；其餘和全力進攻相同

const HEAL_BELOW := 0.5
const LOW_MP := 0.15


static func decide(sim: RefCounted, u: RefCounted) -> Dictionary:
	if sim.foes_of(u).is_empty():
		return {"type": "guard"}
	if u.side == "enemy":
		return _enemy(sim, u)
	if u.auto == "support":
		return _support(sim, u)
	return _attack(sim, u)


# ---------------------------------------------------------------- 敵人

static func _enemy(sim: RefCounted, u: RefCounted) -> Dictionary:
	var foes: Array = sim.foes_of(u)
	for rule: Dictionary in u.rules:
		if not _rule_matches(sim, u, rule):
			continue
		if rule.has("chance") and sim.random_float() >= float(rule["chance"]):
			continue
		var use := str(rule["use"])
		if use == "guard":
			return {"type": "guard"}
		return {"type": "move", "move": use, "target": _enemy_target(sim, u, use, str(rule.get("target", u.targeting)))}
	var options: Array = []
	var weights: Array = []
	for move_id: String in u.moves:
		if sim.can_afford(u, move_id):
			options.append(move_id)
			weights.append(float(u.weights.get(move_id, 1.0)))
	var move_id := str(sim.weighted_pick(options, weights))
	return {"type": "move", "move": move_id, "target": _enemy_target(sim, u, move_id, u.targeting)}


static func _rule_matches(sim: RefCounted, u: RefCounted, rule: Dictionary) -> bool:
	var when: Dictionary = rule["when"]
	if when.has("self_hp_below") and u.hp / float(u.hp_max) >= float(when["self_hp_below"]):
		return false
	if when.get("foe_charging", false):
		var charging := false
		for foe: RefCounted in sim.foes_of(u):
			if foe.state == "charge":
				charging = true
		if not charging:
			return false
	return true


static func _enemy_target(sim: RefCounted, u: RefCounted, move_id: String, how: String) -> String:
	if not sim.needs_target(move_id):
		return u.id
	var pool: Array = sim.foes_of(u) if str(sim.data.moves[move_id]["target"]) == "enemy_single" else sim.allies_of(u)
	match how:
		"lowest_hp":
			pool.sort_custom(func(a: RefCounted, b: RefCounted) -> bool: return a.hp < b.hp)
			return pool[0].id
		"charging":
			for foe: RefCounted in pool:
				if foe.state == "charge":
					return foe.id
	return sim.random_pick(pool).id


# ---------------------------------------------------------------- 我方

static func _attack(sim: RefCounted, u: RefCounted) -> Dictionary:
	var target: RefCounted = _focus(sim, u)
	var best := ""
	var best_score := -1.0
	for move_id: String in u.moves:
		var m: Dictionary = sim.data.moves[move_id]
		if not (str(m["kind"]) in ["attack", "control"]) or not sim.can_afford(u, move_id):
			continue
		var score := 0.0
		if str(m["target"]) == "enemy_all":
			for foe: RefCounted in sim.foes_of(u):
				score += sim.expected_damage(u, move_id, foe)
		else:
			score = sim.expected_damage(u, move_id, target)
		# 打不到就白費的蓄招：對手的破綻撐不過蓄招時間時不放
		var charge := float(m["charge"])
		if charge > 0.0 and target.state == "stagger" and target.timer / 30.0 < charge:
			score *= 0.5
		if score > best_score:
			best_score = score
			best = move_id
	if best == "":
		return {"type": "rest"} if u.mp < u.mp_max * LOW_MP else {"type": "guard"}
	return {"type": "move", "move": best, "target": target.id}


static func _support(sim: RefCounted, u: RefCounted) -> Dictionary:
	var allies: Array = sim.allies_of(u)
	allies.sort_custom(func(a: RefCounted, b: RefCounted) -> bool: return a.hp / float(a.hp_max) < b.hp / float(b.hp_max))
	var lowest: RefCounted = allies[0]
	var big_coming := false
	for foe: RefCounted in sim.foes_of(u):
		if foe.state == "charge" and "big" in sim.data.moves[str(foe.pending.get("move", ""))].get("tags", []):
			big_coming = true
	for move_id: String in u.moves:
		var m: Dictionary = sim.data.moves[move_id]
		if not sim.can_afford(u, move_id):
			continue
		match str(m["kind"]):
			"heal":
				if lowest.hp < lowest.hp_max * HEAL_BELOW:
					return {"type": "move", "move": move_id, "target": lowest.id}
			"buff":
				var status := str((m.get("effects", []) as Array)[0]["status"]) if not (m.get("effects", []) as Array).is_empty() else ""
				if str(m["target"]) == "self":
					if not u.has_status(status) and u.mp > u.mp_max * 0.5:
						return {"type": "move", "move": move_id, "target": u.id}
				elif big_coming:
					for ally: RefCounted in allies:
						if not ally.has_status(status):
							return {"type": "move", "move": move_id, "target": ally.id}
	if u.mp < u.mp_max * LOW_MP:
		return {"type": "rest"}
	return _attack(sim, u)


## 打誰：破綻中的優先，其次氣血最少的。
static func _focus(sim: RefCounted, u: RefCounted) -> RefCounted:
	var foes: Array = sim.foes_of(u)
	var staggered: Array = foes.filter(func(f: RefCounted) -> bool: return f.state == "stagger")
	var pool: Array = staggered if not staggered.is_empty() else foes
	pool.sort_custom(func(a: RefCounted, b: RefCounted) -> bool: return a.hp < b.hp)
	return pool[0]
