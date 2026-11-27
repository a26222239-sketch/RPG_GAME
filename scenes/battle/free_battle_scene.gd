extends Control
## 自由戰鬥（M1 的戰鬥試煉）的畫面層。規則全部在 core/battle/battle_sim.gd，這裡只管畫面與操作。
##
## 流程：每一格依經過的時間讓規則前進（每秒 30 拍）。某一拍有人出手、蓄招、守勢或調息，
## 就先停下規則，把這一拍的事件照順序演完再繼續；演出期間戰鬥時間不前進（設計文件 4.3）。
## 我方手動的人行動條滿了，規則會自己停下來等（等待模式），這裡打開指令面板讓玩家選。
##
## 畫面的排法照序章（10.2）：左上是隊伍，上方中央是敵方（每人一列，有氣血與架勢），右上是「返回」，
## 指令面板在最下方。和序章不同的是：人多，頭上的東西會碰到上方的提示，所以
## 提示寫在指令面板左下那一格，招式名在出手時出現在指令面板的位置（那時面板是收起來的）。
## 點隊伍面板的某一列，可以把那個人切換成手動、全力進攻、支援優先（4.11）。
##
## 操作：滑鼠或觸控點按；鍵盤是數字鍵 1–6 選招式、G 守勢、R 調息，
## 選目標時 ←／→ 切換、Enter 確定、Esc 取消。

const BattleSim := preload("res://core/battle/battle_sim.gd")
const BattleAI := preload("res://core/battle/battle_ai.gd")
const BattleActor := preload("res://scenes/battle/battle_actor.gd")
const BattleFx := preload("res://scenes/battle/battle_fx.gd")
const StripFx := preload("res://scenes/battle/strip_fx.gd")
const Cutin := preload("res://scenes/battle/cutin.gd")
const CommandPanel := preload("res://scenes/ui/command_panel.gd")
const PartyPanel := preload("res://scenes/ui/party_panel.gd")
const UiKit := preload("res://scenes/ui/ui_kit.gd")

const MARGIN := 30.0
const TOP := 24.0
const BOTTOM := 24.0
const STAGE_HEIGHT := 1080.0
const BG_SIZE := Vector2(2560, 1080)
const BG_OVERSCAN := 1.04
const TICK := 1.0 / BattleSim.TICKS_PER_SECOND

## 腳底的位置：x 是看得見的戰場寬度的比例，y 是基準高度 1080 之下的像素（和序章相同）。
const PARTY_SPOTS := [
	{"x": 0.42, "y": 830.0},
	{"x": 0.315, "y": 780.0},
	{"x": 0.215, "y": 830.0},
	{"x": 0.11, "y": 782.0},
]
## 敵方照遭遇資料的順序站。首領比較高，頭會伸進上方的介面，所以站到右後方、敵方面板的右邊。
const ENEMY_SPOTS := [
	{"x": 0.62, "y": 832.0},
	{"x": 0.72, "y": 782.0},
	{"x": 0.81, "y": 834.0},
	{"x": 0.9, "y": 786.0},
]
const BOSS_SPOT := {"x": 0.85, "y": 838.0}
const MELEE_GAP := 120.0

const HIT_STOP := {"basic": 0.06, "skill": 0.09, "ultimate": 0.14}
const HIT_REACTION := {"basic": "hit", "skill": "hit_heavy", "ultimate": "hit_heavy"}
const PLACEHOLDER_FX := {
	"slash_sword": "slash", "slash_blade": "slash",
	"palm": "burst", "seal": "burst", "debuff": "burst",
	"heal": "heal", "buff": "heal",
}
const STATUS_ORDER := ["bleed", "poison", "internal", "slow", "empower", "protect", "light"]
## 隊伍面板那一格的文字：手動、全力進攻、支援優先。點一下換下一個。
const MODES := ["", "attack", "support"]
const MODE_TEXT := {"": "UI_MANUAL", "attack": "UI_TACTIC_SHORT_ATTACK", "support": "UI_TACTIC_SHORT_SUPPORT"}
## 自動播放（開發用）替手動的人選招時用哪一種戰術。
const AUTOPLAY_TACTIC := {"wen": "support"}

var _sim: BattleSim
var _encounter: String = ""
var _seed: int = 0
var _actors: Dictionary = {}
var _busy: bool = false
var _ended: bool = false
var _accum: float = 0.0
## 正在下指令的人、選好的招式（還在選目標）、鍵盤選目標時停在誰身上。
var _picking: String = ""
var _pick_move: String = ""
var _focus: String = ""
var _charge_total: Dictionary = {}
var _last_state: Dictionary = {}
var _stage_width: float = 1920.0
var _time_scale: float = 1.0

var _stage_holder: Control
var _stage: Control
var _background: Control
var _actor_layer: Control
var _overlays: Control
var _numbers: Control
var _party_panel: PartyPanel
var _enemy_panel: PartyPanel
var _command_panel: CommandPanel
var _move_call: Label
var _back_button: Button
var _clock: Label
var _white: ColorRect
var _cutin: Cutin
var _result_card: Control
var _result_title: Label
var _result_line: Label
var _retry_button: Button
var _menu_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_encounter = Game.pending_encounter if Game.pending_encounter != "" else "test_a"
	if not Game.data_ok or not Game.data.encounters.has(_encounter):
		_show_error(Game.data.errors if not Game.data_ok else ["沒有這一場遭遇：%s" % _encounter])
		return
	_seed = Game.dev_seed if Game.dev_seed >= 0 else randi()
	_sim = BattleSim.new()
	_sim.setup(Game.data, _encounter, _seed)
	print("戰鬥試煉 %s，種子 %d" % [_encounter, _seed])
	if Game.auto_party:
		for u in _sim.side_units("party", false):
			u.auto = str(AUTOPLAY_TACTIC.get(u.id, "attack"))
	_time_scale = Engine.time_scale
	_build()
	resized.connect(_layout)
	_layout()
	_refresh_live()
	if Game.autoplay:
		_autoplay_start()


func _exit_tree() -> void:
	Engine.time_scale = _time_scale


# ---------------------------------------------------------------- 主迴圈

func _process(delta: float) -> void:
	_sort_actors()
	if _sim == null or _ended:
		return
	if _busy or _picking != "":
		return
	_accum = minf(_accum + delta, 0.25)
	while _accum >= TICK:
		_accum -= TICK
		var events := _sim.step()
		_refresh_live()
		if not events.is_empty():
			_play(events)
			return
		if not _sim.waiting().is_empty():
			_begin_pick()
			return


## 把一拍（或一個指令）造成的事件照順序演出來。演完之後：戰鬥結束就出結算，有人在等指令就打開指令面板。
func _play(events: Array[Dictionary]) -> void:
	_busy = true
	var i := 0
	while i < events.size():
		var e: Dictionary = events[i]
		match str(e["type"]):
			"act":
				# 出招，連同它造成的結果（傷害、架勢、破綻、狀態、倒下）一起演
				var group: Array[Dictionary] = [e]
				i += 1
				while i < events.size() and not (str(events[i]["type"]) in ["act", "charge", "guard", "rest", "ready", "end"]):
					group.append(events[i])
					i += 1
				await _play_act(group)
				continue
			"charge":
				await _play_charge(e)
			"guard", "rest":
				await _play_command(e)
			_:
				_apply_light(e)
		i += 1
	_refresh_live()
	_busy = false
	if _sim.finished:
		_show_result()
	elif not _sim.waiting().is_empty():
		_begin_pick()


# ---------------------------------------------------------------- 演出

func _play_act(group: Array[Dictionary]) -> void:
	var e: Dictionary = group[0]
	var who := str(e["unit"])
	var u: BattleSim.Unit = _sim.unit(who)
	var actor: BattleActor = _actors[who]
	var move_id := str(e["move"])
	var move: Dictionary = Game.data.moves[move_id]
	var move_class := str(move.get("class", "basic"))
	var targets: Array = e["targets"]

	if actor.is_charging():
		await actor.finish_charge(0.15).finished
		actor.hide_charge()
	if move_class == "ultimate":
		await _play_cutin(u, move_id)
	_show_move_call("%s　%s" % [u.display_name, Game.data.move_name(move_id)], UiKit.ENEMY if u.side == "enemy" else UiKit.TEXT)
	actor.update_gauge(0.0)

	var anim := move_id if actor.has_art(move_id) else str(move["anim"])
	var single := str(move["target"]) in ["enemy_single", "ally_single"]
	var melee: bool = str(move["reach"]) == "melee" and single and not targets.is_empty() and str(targets[0]) != who
	if melee:
		var target_actor: BattleActor = _actors[str(targets[0])]
		var gap := target_actor.body_size.x / 2.0 + actor.body_size.x / 2.0 + MELEE_GAP
		var spot := target_actor.position + Vector2(-gap * actor.facing(), 4.0)
		await actor.move_to(spot, 0.18).finished

	var impact := actor.anim_impact_time(anim)
	var length := actor.play_anim(anim)
	var fx_id := str(move.get("fx", ""))
	var fx_drawn := StripFx.exists(fx_id)
	var lead := minf(StripFx.lead_time(fx_id), impact) if fx_drawn else 0.0
	if impact - lead > 0.0:
		await _wait(impact - lead)
	if fx_drawn:
		_show_strip_fx(actor, move, targets)
		if lead > 0.0:
			await _wait(lead)

	# 出手點：把規則已經算好的結果顯示出來
	if not fx_drawn:
		_show_move_fx(actor, move, targets)
	var heavy := false
	for i in range(1, group.size()):
		heavy = _apply_result(group[i], move_class) or heavy
	_refresh_live()
	if heavy:
		_shake(12.0, 0.35)
	if Game.autoplay:
		Game.take_shot("impact_%s" % move_id)
	await _hit_stop(float(HIT_STOP.get(move_class, 0.0)))

	await _wait(maxf(0.1, length - impact) + 0.12)
	if melee:
		await actor.go_home(0.22).finished
	_hide_move_call()
	await _wait(0.12)


func _play_charge(e: Dictionary) -> void:
	var who := str(e["unit"])
	var u: BattleSim.Unit = _sim.unit(who)
	var actor: BattleActor = _actors[who]
	var move_id := str(e["move"])
	var move: Dictionary = Game.data.moves[move_id]
	_charge_total[who] = maxi(1, roundi(float(e["seconds"]) * BattleSim.TICKS_PER_SECOND))
	actor.update_gauge(0.0)
	actor.show_charge(Game.t("UI_CHARGING_FMT") % Game.data.move_name(move_id), 0.0, 1.0, _force_color(move))
	actor.set_charge_progress(0.0)
	# 敵人蓄帶「大招」標籤的招式：警示
	if u.side == "enemy" and "big" in move.get("tags", []):
		_show_move_call(Game.t("UI_WARNING_FMT") % Game.data.move_name(move_id), UiKit.ENEMY)
		_flash_tint()
		if Game.autoplay:
			Game.take_shot("warning_%s" % move_id)
		await _wait(0.9)
		_hide_move_call()
	else:
		await _wait(0.25)


func _play_command(e: Dictionary) -> void:
	var who := str(e["unit"])
	var u: BattleSim.Unit = _sim.unit(who)
	var actor: BattleActor = _actors[who]
	actor.update_gauge(0.0)
	var command := str(e["type"])
	_show_move_call("%s　%s" % [u.display_name, Game.t("CMD_GUARD" if command == "guard" else "CMD_REST")])
	if command == "guard":
		_last_state.erase(who)
		_refresh_live()
	else:
		actor.play_anim("cast")
		_spawn_number(actor, Game.t("CMD_REST"), UiKit.MP)
	await _wait(0.55)
	_hide_move_call()


## 出手造成的一個結果。回傳這個結果夠不夠重、要不要震一下畫面。
func _apply_result(e: Dictionary, move_class: String) -> bool:
	var unit_id := str(e.get("unit", ""))
	if not _actors.has(unit_id):
		return false
	var actor: BattleActor = _actors[unit_id]
	var u: BattleSim.Unit = _sim.unit(unit_id)
	match str(e["type"]):
		"damage":
			_set_hp(u, int(e["hp"]))
			var text := "-%d" % int(e["amount"])
			if e["crit"]:
				text = "%s %s" % [Game.t("UI_CRIT"), text]
			_spawn_number(actor, text, UiKit.HIGHLIGHT if e["crit"] else UiKit.DAMAGE, 76 if e["crit"] else 64)
			StripFx.spawn(_numbers, "hit_spark", actor.chest_position())
			if int(e["hp"]) > 0:
				actor.play_anim(str(HIT_REACTION.get(move_class, "hit")))
			return move_class == "ultimate" or bool(e["crit"])
		"dodge":
			_spawn_number(actor, Game.t("UI_MISS"), UiKit.TEXT_DIM)
		"heal":
			_set_hp(u, int(e["hp"]))
			_spawn_number(actor, "+%d" % int(e["amount"]), UiKit.HEAL)
		"posture":
			if u.side == "enemy":
				_enemy_panel.set_posture(unit_id, float(e["value"]) / float(e["max"]))
		"stagger":
			_spawn_number(actor, Game.t("STATE_STAGGER"), UiKit.HIGHLIGHT, 72, 0.25)
			return true
		"interrupt":
			actor.hide_charge()
			_spawn_number(actor, Game.t("UI_INTERRUPT"), UiKit.HIGHLIGHT, 72, 0.5)
			return true
		"status":
			_spawn_number(actor, Game.t("STATE_" + str(e["status"]).to_upper()), UiKit.JADE, 48, 0.4)
		"down":
			_show_down(u)
			return true
		_:
			_apply_light(e)
	return false


## 不需要停下來演的事件：每秒的流血中毒、狀態結束、破綻結束。
func _apply_light(e: Dictionary) -> void:
	var unit_id := str(e.get("unit", ""))
	if not _actors.has(unit_id):
		return
	var actor: BattleActor = _actors[unit_id]
	var u: BattleSim.Unit = _sim.unit(unit_id)
	match str(e["type"]):
		"dot":
			_set_hp(u, int(e["hp"]))
			_spawn_number(actor, "-%d" % int(e["amount"]), Color(UiKit.DAMAGE, 0.8), 48)
		"posture":
			if u.side == "enemy":
				_enemy_panel.set_posture(unit_id, float(e["value"]) / float(e["max"]))
		"stagger_end":
			if u.side == "enemy":
				_enemy_panel.set_posture(unit_id, 1.0)
		"down":
			_show_down(u)


func _show_down(u: BattleSim.Unit) -> void:
	var actor: BattleActor = _actors[u.id]
	_set_hp(u, 0)
	actor.hide_charge()
	actor.update_gauge(0.0)
	actor.set_state_tag("")
	actor.set_aura("guard", false)
	actor.set_aura("stagger_mark", false)
	actor.set_targetable(false)
	actor.set_rest_anim("down")
	actor.play_anim("down")
	_last_state[u.id] = "down"
	if u.side == "party":
		_party_panel.set_down(u.id, true)
	else:
		_enemy_panel.set_down(u.id, true)


func _set_hp(u: BattleSim.Unit, hp: int) -> void:
	var ratio := hp / float(u.hp_max)
	if u.side == "party":
		_party_panel.set_hp(u.id, ratio)
	else:
		_enemy_panel.set_hp(u.id, ratio)


## 每一拍之後，把會持續變化的東西照規則的狀態更新：行動條、蓄招倒數、內力、頭上的狀態標籤。
func _refresh_live() -> void:
	_clock.text = Game.t("UI_TIME_FMT") % int(_sim.seconds())
	for u in _sim.units:
		if not u.alive():
			continue
		var actor: BattleActor = _actors[u.id]
		var gauge := 0.0
		if u.state == "fill":
			gauge = u.gauge / 100.0
		elif u.state == "wait":
			gauge = 1.0
		actor.update_gauge(gauge)
		if u.state == "charge" and actor.is_charging():
			actor.set_charge_progress(1.0 - float(u.timer) / float(_charge_total.get(u.id, 1)))
		elif actor.is_charging() and u.state != "charge":
			actor.hide_charge()
		if u.side == "party":
			_party_panel.set_mp(u.id, u.mp / float(u.mp_max), false)
		var key := "%s|%s|%s" % [u.state, u.guarding, _status_text(u)]
		if key != str(_last_state.get(u.id, "")):
			_last_state[u.id] = key
			_apply_state(u, actor)


func _apply_state(u: BattleSim.Unit, actor: BattleActor) -> void:
	var parts: Array[String] = []
	if u.state == "stagger":
		parts.append(Game.t("STATE_STAGGER"))
	elif u.state == "stun":
		parts.append(Game.t("STATE_SEAL"))
	if u.guarding:
		parts.append(Game.t("STATE_GUARD"))
	var statuses := _status_text(u)
	if statuses != "":
		parts.append(statuses)
	if not actor.is_targetable() or _pick_move == "":
		actor.set_state_tag("・".join(parts))
	actor.set_aura("guard", u.guarding)
	actor.set_aura("stagger_mark", u.state == "stagger")
	actor.set_rest_anim("stagger" if u.state == "stagger" else ("guard" if u.guarding else "idle"))


func _status_text(u: BattleSim.Unit) -> String:
	var parts: Array[String] = []
	for status: String in STATUS_ORDER:
		if not u.statuses.has(status):
			continue
		var label := Game.t("STATE_" + status.to_upper())
		var stacks := int(u.statuses[status]["stacks"])
		if stacks > 1:
			label += str(stacks)
		parts.append(label)
	if parts.size() > 2:
		return "・".join(parts.slice(0, 2)) + "…"
	return "・".join(parts)


# ---------------------------------------------------------------- 玩家下指令

func _begin_pick() -> void:
	var waiting := _sim.waiting()
	if waiting.is_empty() or _ended:
		return
	var who: String = waiting[0]
	var u: BattleSim.Unit = _sim.unit(who)
	if u.auto != "":
		# 等指令的時候被切成自動了：直接照戰術出手
		_submit(who, BattleAI.decide(_sim, u))
		return
	_picking = who
	_pick_move = ""
	var actor: BattleActor = _actors[who]
	actor.set_active(true)
	actor.play_anim("ready")
	_party_panel.set_active(who)
	_command_panel.show_choices(_move_list(u), ["guard", "rest"], Game.t("UI_PICK_MOVE_FMT") % u.display_name)
	if Game.autoplay:
		_autoplay_pick(who)


func _move_list(u: BattleSim.Unit) -> Array:
	var list: Array = []
	for move_id: String in u.moves:
		var m: Dictionary = Game.data.moves[move_id]
		var parts: Array[String] = []
		var cost := _sim.cost_of(u, move_id)
		if cost > 0.0:
			parts.append(Game.t("UI_COST_SHORT_FMT") % roundi(cost))
		if float(m["charge"]) > 0.0:
			parts.append(Game.t("UI_CHARGE_SHORT_FMT") % str(snappedf(float(m["charge"]), 0.1)))
		list.append({
			"id": move_id,
			"name": Game.data.move_name(move_id),
			"force": str(m.get("force", "")),
			"detail": "・".join(parts) if not parts.is_empty() else Game.t("UI_NO_COST"),
			"enabled": _sim.can_afford(u, move_id),
		})
	return list


func _on_move_pressed(move_id: String) -> void:
	if _picking == "" or _busy:
		return
	var u: BattleSim.Unit = _sim.unit(_picking)
	if not _sim.needs_target(move_id):
		_submit(_picking, {"type": "move", "move": move_id, "target": _picking})
		return
	if _pick_move == move_id:
		# 再按一次同一招：取消，回到選招式
		_end_targeting()
		_command_panel.set_note(Game.t("UI_PICK_MOVE_FMT") % u.display_name)
		return
	_end_targeting()
	_pick_move = move_id
	_command_panel.set_selected(move_id)
	var force := str(Game.data.moves[move_id].get("force", ""))
	for t in _sim.units:
		if not _sim.valid_target(u, move_id, t):
			continue
		var actor: BattleActor = _actors[t.id]
		actor.set_targetable(true)
		# 目標是敵人時，標出這一招剋不剋他（10.2）
		var rel := _sim.matchup(force, t.force) if t.side != u.side else 1.0
		if rel > 1.0:
			actor.set_state_tag(Game.t("UI_MATCHUP_WIN"))
		elif rel < 1.0:
			actor.set_state_tag(Game.t("UI_MATCHUP_LOSE"))
	_command_panel.set_note(Game.t("UI_TARGET_HINT"))


func _on_command_pressed(command: String) -> void:
	if _picking == "" or _busy or not (command in ["guard", "rest"]):
		return
	_submit(_picking, {"type": command})


func _on_actor_clicked(actor_id: String) -> void:
	if _picking == "" or _pick_move == "" or _busy:
		return
	var actor: BattleActor = _actors[actor_id]
	if actor.is_targetable():
		_submit(_picking, {"type": "move", "move": _pick_move, "target": actor_id})


func _end_targeting() -> void:
	_pick_move = ""
	_focus = ""
	_command_panel.set_selected("")
	for id: String in _actors:
		var actor: BattleActor = _actors[id]
		if actor.is_targetable():
			actor.set_targetable(false)
		actor.set_dimmed(false)
		# 剋制、被剋的標籤收起來，換回原本的狀態
		if _last_state.get(id, "") != "down":
			_last_state.erase(id)
	_refresh_live()


func _submit(who: String, choice: Dictionary) -> void:
	_end_targeting()
	_command_panel.hide_commands()
	var actor: BattleActor = _actors[who]
	actor.set_active(false)
	_party_panel.set_active("")
	_picking = ""
	var events: Variant = _sim.command(who, choice)
	if events == null:
		push_warning("指令不合規則：%s %s" % [who, choice])
		_begin_pick()
		return
	actor.set_rest_anim("idle")
	actor.play_anim("idle")
	_play(events)


func _on_row_pressed(unit_id: String) -> void:
	var u: BattleSim.Unit = _sim.unit(unit_id)
	if u == null or not u.alive() or _ended:
		return
	u.auto = MODES[(MODES.find(u.auto) + 1) % MODES.size()]
	_refresh_modes()
	if _picking == unit_id and u.auto != "":
		_command_panel.hide_commands()
		(_actors[unit_id] as BattleActor).set_active(false)
		_party_panel.set_active("")
		_end_targeting()
		_picking = ""
		_submit(unit_id, BattleAI.decide(_sim, u))


func _refresh_modes() -> void:
	for u in _sim.side_units("party", false):
		_party_panel.set_mode(u.id, Game.t(MODE_TEXT[u.auto]), u.auto != "")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if _ended:
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_retry()
		elif event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_to_menu()
		return
	if _picking == "":
		return
	if _pick_move == "":
		if key == KEY_G:
			get_viewport().set_input_as_handled()
			_on_command_pressed("guard")
		elif key == KEY_R:
			get_viewport().set_input_as_handled()
			_on_command_pressed("rest")
		return
	# 選目標
	var choices := _targetable_ids()
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_end_targeting()
		_command_panel.set_note(Game.t("UI_PICK_MOVE_FMT") % _sim.unit(_picking).display_name)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		var step := 1 if event.is_action_pressed("ui_right") else -1
		var at := choices.find(_focus)
		_focus = choices[(at + step + choices.size()) % choices.size()] if at >= 0 else choices[0]
		for id in choices:
			(_actors[id] as BattleActor).set_dimmed(id != _focus)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		var target := _focus if _focus != "" else choices[0]
		_submit(_picking, {"type": "move", "move": _pick_move, "target": target})


## 可以選的目標，由左到右。
func _targetable_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _actors:
		if (_actors[id] as BattleActor).is_targetable():
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return (_actors[a] as Control).position.x < (_actors[b] as Control).position.x)
	return ids


# ---------------------------------------------------------------- 結算

func _show_result() -> void:
	if _ended:
		return
	_ended = true
	_command_panel.hide_commands()
	_hide_move_call()
	var party_actions := 0
	var hp := 0
	var hp_max := 0
	for u in _sim.side_units("party", false):
		party_actions += u.actions
		hp += u.hp
		hp_max += u.hp_max
	var key := str({"win": "UI_WIN", "lose": "UI_LOSE"}.get(_sim.result, "UI_TIMEOUT"))
	_result_title.text = Game.t(key)
	_result_title.add_theme_color_override("font_color", UiKit.HIGHLIGHT if _sim.result == "win" else UiKit.ENEMY)
	_result_line.text = Game.t("UI_RESULT_FMT") % [roundi(_sim.seconds()), party_actions, roundi(hp * 100.0 / hp_max)]
	print("戰鬥試煉 %s 結束：%s，%s（種子 %d）" % [_encounter, _sim.result, _result_line.text, _seed])
	if _sim.result == "win":
		for u in _sim.side_units("party"):
			(_actors[u.id] as BattleActor).play_anim("victory")
	await _wait(0.9)
	_result_card.visible = true
	_result_card.modulate.a = 0.0
	create_tween().tween_property(_result_card, "modulate:a", 1.0, 0.4)
	if Game.autoplay:
		await _wait(0.6 + 2.0 * Game.read_scale)
		await Game.take_shot("result")
		if Game.replays_left > 0:
			Game.replays_left -= 1
			await _auto_tap(_retry_button.get_global_rect().get_center(), _retry, func() -> bool: return true, KEY_ENTER)
		else:
			get_tree().quit(0)


func _retry() -> void:
	if Game.dev_seed >= 0:
		Game.dev_seed += 1
	get_tree().reload_current_scene()


func _to_menu() -> void:
	Game.open_trials = true
	get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")


# ---------------------------------------------------------------- 自動播放（開發用）
# 手動的人一樣經過指令面板與目標：依 --input 直接呼叫、模擬滑鼠點擊或模擬按鍵。
# 招式由遊戲內的自動戰術決定（燕回、沈清禾、霍嶽全力進攻，溫蘅支援優先）。

func _autoplay_start() -> void:
	await _wait(0.3)
	await Game.take_shot("start")
	# 試一次隊伍面板的切換：霍嶽改成全力進攻，其他人留手動
	if not Game.auto_party:
		await _auto_tap(_party_panel.row_center("huo"), _on_row_pressed.bind("huo"), func() -> bool: return true, KEY_NONE)


func _autoplay_pick(who: String) -> void:
	await _wait(0.15 + 1.5 * Game.read_scale)
	var still := func() -> bool: return _picking == who and not _busy
	if not still.call():
		return
	var u: BattleSim.Unit = _sim.unit(who)
	var saved := u.auto
	u.auto = str(AUTOPLAY_TACTIC.get(who, "attack"))
	var choice := BattleAI.decide(_sim, u)
	u.auto = saved
	await Game.take_shot("pick_%s" % who)
	match str(choice["type"]):
		"guard", "rest":
			var command := str(choice["type"])
			await _auto_tap(_command_panel.command_center(command), _on_command_pressed.bind(command), still, KEY_G if command == "guard" else KEY_R)
			return
	var move_id := str(choice["move"])
	var slot := u.moves.find(move_id)
	await _auto_tap(_command_panel.move_center(move_id), _command_panel.press_move.bind(move_id), still, (KEY_1 + slot) as Key)
	if not _sim.needs_target(move_id):
		return
	var target := str(choice["target"])
	var picking_target := func() -> bool: return _picking == who and _pick_move == move_id
	# 等目標亮起來
	for i in 20:
		if picking_target.call():
			break
		await get_tree().process_frame
	await _wait(0.1 + 0.8 * Game.read_scale)
	await Game.take_shot("target_%s" % who)
	if Game.input_mode == "keys":
		# 用 → 移到要選的目標，再按 Enter
		var ids := _targetable_ids()
		for i in ids.find(target) + 1:
			await Game.press_key(KEY_RIGHT, picking_target)
		await Game.press_key(KEY_ENTER, picking_target)
		return
	var actor: BattleActor = _actors[target]
	await _auto_tap(actor.chest_global(), _on_actor_clicked.bind(target), picking_target, KEY_NONE)


func _auto_tap(pos: Vector2, direct: Callable, still_wanted: Callable, key: Key) -> void:
	match Game.input_mode:
		"clicks":
			await Game.click_at(pos, still_wanted)
		"keys":
			if key != KEY_NONE:
				await Game.press_key(key, still_wanted)
			elif still_wanted.call():
				direct.call()
		_:
			if still_wanted.call():
				direct.call()


# ---------------------------------------------------------------- 效果

func _play_cutin(u: BattleSim.Unit, move_id: String) -> void:
	_hide_move_call()
	_cutin.play(u.source, move_id, u.side == "party", _force_color(Game.data.moves[move_id]), Game.data.move_name(move_id), u.display_name)
	if Game.autoplay:
		await _wait(0.55)
		Game.take_shot("cutin_%s" % move_id)
	if _cutin.visible:
		await _cutin.finished


func _hit_stop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	Engine.time_scale = _time_scale * 0.02
	await get_tree().create_timer(seconds / _time_scale, true, false, true).timeout
	Engine.time_scale = _time_scale


func _force_color(move: Dictionary) -> Color:
	return UiKit.FORCE_COLOR.get(str(move.get("force", "")), Color.WHITE)


## 特效有圖就播圖（和序章相同的規則）：共用特效每個目標一份，招式專屬的大型特效只播一份、放在目標的正中。
func _show_strip_fx(actor: BattleActor, move: Dictionary, targets: Array) -> void:
	if targets.is_empty():
		return
	var fx_id := str(move["fx"])
	var color := _force_color(move)
	var on_body: bool = str(Game.data.vfx[fx_id]["anchor"]) == "body"
	if not Game.data.SHARED_FX.has(fx_id) and not on_body:
		var center := Vector2.ZERO
		for target_id: String in targets:
			center += (_actors[target_id] as BattleActor).chest_position()
		StripFx.spawn(_numbers, fx_id, center / float(targets.size()), color, actor.facing())
		return
	for target_id: String in targets:
		var target: BattleActor = _actors[target_id]
		var at := target.position if on_body else target.chest_position()
		StripFx.spawn(_numbers, fx_id, at, color, actor.facing(), target.frame_size())


## 特效圖還沒交時用程式畫的暫用特效（和序章相同）。
func _show_move_fx(actor: BattleActor, move: Dictionary, targets: Array) -> void:
	var heavy: bool = str(move.get("anim", "")) == "attack_heavy"
	var color: Color = UiKit.FORCE_COLOR.get(str(move.get("force", "")), UiKit.PAPER)
	var drawn := str(PLACEHOLDER_FX.get(str(move.get("fx", "")), ""))
	if drawn == "":
		if str(move.get("kind", "")) == "heal":
			drawn = "heal"
		else:
			drawn = "slash" if str(move.get("reach", "")) == "melee" else "burst"
	for target_id: String in targets:
		var target: BattleActor = _actors[target_id]
		var at := target.chest_position()
		match drawn:
			"heal":
				BattleFx.spawn(_numbers, at, "heal", UiKit.HEAL, target.body_size.y * 0.42)
			"slash":
				BattleFx.spawn(_numbers, at, "slash_heavy" if heavy else "slash", color, 210.0 if heavy else 160.0, actor.facing())
			_:
				BattleFx.spawn(_numbers, at, "burst", color, 170.0 if heavy else 110.0)


func _spawn_number(actor: BattleActor, text: String, color: Color, font_size: int = 64, delay: float = 0.0) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(UiKit.SHADE, 0.95))
	label.add_theme_constant_override("outline_size", 12)
	label.size = Vector2(420, font_size + 16)
	label.position = actor.position + Vector2(-210, -actor.body_size.y * 0.8 - (font_size - 64) * 0.5 - (60.0 if delay > 0.0 else 0.0))
	label.modulate.a = 0.0 if delay > 0.0 else 1.0
	_numbers.add_child(label)
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
		tween.tween_property(label, "modulate:a", 1.0, 0.05)
	tween.tween_property(label, "position:y", label.position.y - 110.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tween.tween_callback(label.queue_free)


func _shake(strength: float, duration: float) -> void:
	var tween := create_tween()
	var steps := maxi(2, int(duration / 0.05))
	for i in steps:
		var falloff := 1.0 - float(i) / float(steps)
		tween.tween_property(_stage, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * falloff, 0.05)
	tween.tween_property(_stage, "position", Vector2.ZERO, 0.05)


## 大招警示：畫面邊緣閃一下紅。
func _flash_tint() -> void:
	_white.color = Color(0.8, 0.1, 0.1)
	_white.visible = true
	_white.modulate.a = 0.18
	var tween := create_tween()
	tween.tween_property(_white, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _white.visible = false)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------- 招式名

func _show_move_call(text: String, color: Color = UiKit.TEXT) -> void:
	_move_call.text = text
	_move_call.add_theme_color_override("font_color", color)
	(_move_call.get_theme_stylebox("normal") as StyleBoxFlat).border_color = UiKit.BRONZE if color == UiKit.TEXT else color
	_move_call.visible = true
	_layout_top()


func _hide_move_call() -> void:
	_move_call.visible = false


# ---------------------------------------------------------------- 建立畫面

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color("#0b1215")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_stage_holder = _plain()
	add_child(_stage_holder)
	_stage = _plain()
	_stage_holder.add_child(_stage)
	_background = _plain()
	_stage.add_child(_background)
	_build_background(str(Game.data.encounters[_encounter].get("background", "")))
	var cast := _plain()
	_stage.add_child(cast)
	_actor_layer = _plain()
	cast.add_child(_actor_layer)
	_overlays = _plain()
	cast.add_child(_overlays)
	_numbers = _plain()
	cast.add_child(_numbers)

	for u in _sim.units:
		var actor := BattleActor.new()
		_actor_layer.add_child(actor)
		var color := Color(str((Game.data.characters if u.side == "party" else Game.data.enemies)[u.source]["color"]))
		actor.setup(u.id, u.display_name, color, u.side == "enemy", u.boss, u.source)
		# 敵人有好幾個，蓄招的倒數條放頭上才不會互相蓋住；首領例外，他的頭已經頂到上方的介面
		actor.charge_above = not u.boss
		actor.attach_overlay(_overlays)
		actor.clicked.connect(_on_actor_clicked)
		_actors[u.id] = actor

	_party_panel = PartyPanel.new()
	add_child(_party_panel)
	var members: Array = []
	for u in _sim.side_units("party", false):
		members.append({"id": u.id, "name": u.display_name, "hp_max": u.hp_max, "mp_max": u.mp_max})
	_party_panel.setup(members, {"modes": true})
	_party_panel.row_pressed.connect(_on_row_pressed)

	_enemy_panel = PartyPanel.new()
	add_child(_enemy_panel)
	var foes: Array = []
	for u in _sim.side_units("enemy", false):
		foes.append({"id": u.id, "name": u.display_name, "hp_max": u.hp_max, "art": u.source})
	_enemy_panel.setup(foes, {"enemy": true, "name_w": 216.0, "bar_w": 220.0})

	_move_call = UiKit.label("", 46)
	var call_style := UiKit.tag_style(UiKit.BRONZE, 0.84)
	call_style.content_margin_left = 44
	call_style.content_margin_right = 44
	call_style.border_width_left = 0
	call_style.border_width_right = 0
	call_style.set_corner_radius_all(0)
	_move_call.add_theme_stylebox_override("normal", call_style)
	_move_call.visible = false
	add_child(_move_call)

	_command_panel = CommandPanel.new()
	add_child(_command_panel)
	_command_panel.move_pressed.connect(_on_move_pressed)
	_command_panel.command_pressed.connect(_on_command_pressed)

	_back_button = Button.new()
	UiKit.style_button(_back_button, 36)
	_back_button.text = Game.t("UI_BACK")
	_back_button.size = Vector2(220, 84)
	_back_button.pressed.connect(_to_menu)
	add_child(_back_button)

	_clock = UiKit.label("", 36, UiKit.TEXT_DIM, 8)
	_clock.size = Vector2(220, 48)
	add_child(_clock)

	_cutin = Cutin.new()
	_cutin.visible = false
	add_child(_cutin)

	_white = ColorRect.new()
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.visible = false
	add_child(_white)

	_result_card = _build_result_card()
	add_child(_result_card)
	_refresh_modes()
	for u in _sim.side_units("enemy", false):
		_enemy_panel.set_posture(u.id, 1.0, false)


func _plain() -> Control:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _build_background(scene_name: String) -> void:
	var path := "res://assets/backgrounds/battle/%s.jpg" % scene_name
	if not ResourceLoader.exists(path):
		path = path.get_basename() + ".png"
	if scene_name != "" and ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.name = "Image"
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.texture = load(path)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_background.add_child(image)
		return
	# 還沒有圖：暗色的天空與一塊石地
	for entry: Array in [["Base", Color("#172329")], ["Floor", Color("#2c3a3d")]]:
		var rect := ColorRect.new()
		rect.name = entry[0]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.color = entry[1]
		_background.add_child(rect)


func _build_result_card() -> Control:
	var card := ColorRect.new()
	card.color = Color(UiKit.SHADE, 0.82)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 36)
	card.add_child(box)
	box.add_child(UiKit.label(Game.t(str(Game.data.encounters[_encounter]["name"])), 44, UiKit.BRONZE, 8))
	_result_title = UiKit.label("", 96, UiKit.HIGHLIGHT, 14)
	box.add_child(_result_title)
	_result_line = UiKit.label("", 40, UiKit.TEXT, 8)
	box.add_child(_result_line)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	_retry_button = _make_button(Game.t("UI_RETRY"))
	_retry_button.pressed.connect(_retry)
	buttons.add_child(_retry_button)
	_menu_button = _make_button(Game.t("UI_TO_MENU"))
	_menu_button.pressed.connect(_to_menu)
	buttons.add_child(_menu_button)
	return card


func _make_button(text: String) -> Button:
	var button := Button.new()
	UiKit.style_button(button, 44)
	button.text = text
	button.custom_minimum_size = Vector2(320, 128)
	return button


func _show_error(messages: Array) -> void:
	var label := UiKit.label(Game.t("UI_LOAD_ERROR") + "\n\n" + "\n".join(messages), 36, UiKit.DAMAGE)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	add_child(label)
	for message: String in messages:
		push_error(message)
	if Game.autoplay:
		get_tree().quit(1)


# ---------------------------------------------------------------- 排版

func _layout() -> void:
	if _stage == null:
		return
	var w := size.x
	var h := size.y
	var s := h / STAGE_HEIGHT
	_stage_width = minf(w / s, BG_SIZE.x)
	_stage_holder.scale = Vector2(s, s)
	_stage_holder.position = Vector2((w - _stage_width * s) / 2.0, 0)
	_layout_background()
	var party := _sim.side_units("party", false)
	for i in party.size():
		_place_actor(party[i].id, PARTY_SPOTS[i])
	var spot := 0
	for u in _sim.side_units("enemy", false):
		if u.boss:
			_place_actor(u.id, BOSS_SPOT)
		else:
			_place_actor(u.id, ENEMY_SPOTS[mini(spot, ENEMY_SPOTS.size() - 1)])
			spot += 1

	_party_panel.position = Vector2(MARGIN, TOP)
	_back_button.position = Vector2(w - MARGIN - _back_button.size.x, TOP)
	_clock.position = Vector2(w - MARGIN - _clock.size.x, TOP + _back_button.size.y + 6.0)
	_command_panel.position = Vector2((w - CommandPanel.PANEL_SIZE.x) / 2.0, h - BOTTOM - CommandPanel.PANEL_SIZE.y)
	_layout_top()


## 上方中央是敵方面板；招式名出現在指令面板的位置。
func _layout_top() -> void:
	if _enemy_panel == null:
		return
	var w := size.x
	var left := MARGIN + _party_panel.size.x + 20.0
	var right := w - MARGIN - _back_button.size.x - 20.0
	_enemy_panel.reset_size()
	_enemy_panel.position = Vector2(_center_between(_enemy_panel.size.x, left, right), TOP)
	if _enemy_panel.position.x < left:
		# 窄的螢幕：敵方面板改放右上，在「返回」的下面
		_enemy_panel.position = Vector2(w - MARGIN - _enemy_panel.size.x, TOP + _back_button.size.y + 60.0)
	_move_call.reset_size()
	_move_call.position = Vector2((w - _move_call.size.x) / 2.0, size.y - BOTTOM - CommandPanel.PANEL_SIZE.y / 2.0 - _move_call.size.y / 2.0)


func _center_between(width: float, left: float, right: float) -> float:
	var x := (size.x - width) / 2.0
	if x < left or x + width > right:
		x = left + (right - left - width) / 2.0
	return x


func _layout_background() -> void:
	var vw := _stage_width
	var image := _background.get_node_or_null("Image") as TextureRect
	if image:
		image.size = BG_SIZE * BG_OVERSCAN
		image.position = Vector2((vw - image.size.x) / 2.0, (STAGE_HEIGHT - image.size.y) / 2.0)
		return
	var pad := 240.0
	for entry: Array in [["Base", Rect2(-pad, -pad, vw + pad * 2.0, STAGE_HEIGHT + pad * 2.0)], ["Floor", Rect2(-pad, 715, vw + pad * 2.0, 365 + pad)]]:
		var node := _background.get_node_or_null(str(entry[0])) as Control
		if node:
			node.position = (entry[1] as Rect2).position
			node.size = (entry[1] as Rect2).size


func _place_actor(id: String, spot: Dictionary) -> void:
	var actor: BattleActor = _actors[id]
	var was_home := actor.position.is_equal_approx(actor.home)
	actor.home = Vector2(_stage_width * float(spot["x"]), float(spot["y"]))
	if was_home:
		actor.position = actor.home


## 站得愈下面（離鏡頭愈近）的人畫在愈上層。
func _sort_actors() -> void:
	if _actor_layer == null:
		return
	var ordered: Array = _actor_layer.get_children()
	for i in range(1, ordered.size()):
		if (ordered[i] as Control).position.y < (ordered[i - 1] as Control).position.y:
			ordered.sort_custom(func(a: Control, b: Control) -> bool: return a.position.y < b.position.y)
			for j in ordered.size():
				_actor_layer.move_child(ordered[j], j)
			return
