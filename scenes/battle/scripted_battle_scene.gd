extends Control
## 劇本式戰鬥的畫面層（設計文件 4.14）。
##
## 這個場景照著 data/scripted/ 裡的劇本一拍一拍播放：對話、出手、演出。
## 規則與狀態交給 ScriptedBattle；這裡只負責畫面與玩家的操作。
## 角色的動作經由 BattleActor.play_anim() 播放。
##
## 畫面分兩層：
## - 戰場（_stage）：背景與角色。以 1080 高為基準，跟著視窗高度等比例縮放，角色永遠站在背景的石地上。
## - 介面：直接用畫面座標。上方是隊伍、敵方氣血、提示；最下方是指令或對話框；角色站在兩者之間。

const ScriptedBattle := preload("res://core/scripted/scripted_battle.gd")
const LineWrap := preload("res://core/text/line_wrap.gd")
const BattleActor := preload("res://scenes/battle/battle_actor.gd")
const BattleFx := preload("res://scenes/battle/battle_fx.gd")
const DialogueBox := preload("res://scenes/ui/dialogue_box.gd")
const CommandPanel := preload("res://scenes/ui/command_panel.gd")
const PartyPanel := preload("res://scenes/ui/party_panel.gd")
const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Bar := preload("res://scenes/ui/bar.gd")
const Glyph := preload("res://scenes/ui/glyph.gd")

const MARGIN := 30.0
const TOP := 24.0
const BOTTOM := 24.0
const STATE_TEXT := {"guard": "STATE_GUARD", "stagger": "STATE_STAGGER", "slow": "STATE_SLOW"}

## 戰場的基準高度，以及背景圖的大小。背景比畫面略大一圈，震動時才不會露出邊緣。
const STAGE_HEIGHT := 1080.0
const BG_SIZE := Vector2(2560, 1080)
const BG_OVERSCAN := 1.04

## 蓄招在畫面上實際等待的時間 = 劇本的秒數 × 這個倍率。劇本式戰鬥不需要等滿。
const CHARGE_TIME_SCALE := 0.6

## 各角色腳底在戰場上的位置：x 是看得見的戰場寬度的比例，y 是基準高度 1080 之下的像素。
## 石地的後緣大約在 y=715；最下方 240 像素留給指令面板與對話框。
const PARTY_SPOTS := [
	{"x": 0.42, "y": 830.0},
	{"x": 0.315, "y": 780.0},
	{"x": 0.215, "y": 830.0},
	{"x": 0.11, "y": 782.0},
]
const ENEMY_SPOTS := [
	{"x": 0.775, "y": 832.0},
]

## 近身出手時，兩人身體之間留的距離（兵器與手臂會伸進這段距離）。
const MELEE_GAP := 120.0

## 共用特效還沒有圖的時候，各自用哪一種程式畫的效果頂替。
const PLACEHOLDER_FX := {
	"slash_sword": "slash", "slash_blade": "slash",
	"palm": "burst", "seal": "burst", "debuff": "burst",
	"heal": "heal", "buff": "heal",
}

## 提示的字級，以及文字離面板左右邊的距離。
const HINT_FONT := 36
const HINT_PAD := 30.0

@export var script_id: String = "prologue_final"

var _battle: ScriptedBattle = ScriptedBattle.new()
var _actors: Dictionary = {}
var _pinned: Array[String] = []
var _aborted: bool = false
var _finished: bool = false
var _waiting_subtitle: bool = false
var _line_serial: int = 0
var _scene_name: String = ""
var _stage_width: float = 1920.0
var _hint_text: String = ""

var _stage_holder: Control
var _stage: Control
var _background: Control
var _cast: Control
var _actor_layer: Control
var _overlays: Control
var _numbers: Control
var _party_panel: PartyPanel
var _enemy_panel: PanelContainer
var _enemy_bar: Bar
var _enemy_percent: Label
var _command_panel: CommandPanel
var _hint_panel: PanelContainer
var _hint_label: Label
var _move_call: Label
var _dialogue: DialogueBox
var _black: ColorRect
var _subtitle_label: Label
var _white: ColorRect
var _tint: ColorRect
var _skip_button: Button
var _end_card: Control
var _collapse_tween: Tween

signal _subtitle_advanced
signal _target_chosen(actor_id: String)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Game.data_ok:
		_show_error(Game.data.errors)
		return
	var script := Game.data.load_scripted(script_id)
	if script.is_empty():
		_show_error(Game.data.errors)
		return
	var problems := ScriptedBattle.validate(script, Game.data.characters, Game.data.moves, Game.data.texts)
	if not problems.is_empty():
		_show_error(problems)
		return
	_battle.setup(script, Game.data.characters)
	_build()
	resized.connect(_layout)
	_layout()
	_run()


# ---------------------------------------------------------------- 主流程

func _run() -> void:
	while _battle.has_next() and not _aborted:
		var beat := _battle.next_beat()
		if Game.skip_at == _battle.index:
			if Game.input_mode == "clicks":
				Game.click_at(_skip_button.get_global_rect().get_center())
			else:
				_on_skip()
		await _play_beat(beat)
	if not _aborted:
		_finish()


func _play_beat(beat: Dictionary) -> void:
	match str(beat.get("type", "")):
		"subtitle":
			await _beat_subtitle(beat)
		"narrate":
			await _beat_line("", beat)
		"say":
			await _beat_line(str(beat["who"]), beat)
		"hint":
			await _reveal_scene()
			_show_hint(Game.t(str(beat["text"])))
		"act":
			await _beat_act(beat)
		"command":
			await _beat_command(beat)
		"charge":
			await _beat_charge(beat)
		"state":
			_battle.apply(beat)
			_refresh_states()
			await _wait(0.4)
		"fx":
			await _play_fx(str(beat.get("name", "")), beat)
		"scene":
			await _beat_scene(beat)
		"end":
			pass


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_dialogue.hide_box()
	_command_panel.hide_commands()
	_hide_hint()
	_skip_button.visible = false
	_end_card.visible = true
	_end_card.modulate.a = 0.0
	create_tween().tween_property(_end_card, "modulate:a", 1.0, 0.6)
	if Game.autoplay:
		await _wait(0.8 + 2.0 * Game.read_scale)
		await Game.take_shot("end")
		if Game.replays_left > 0:
			Game.replays_left -= 1
			Game.skip_at = -1
			get_tree().reload_current_scene()
		else:
			print("序章播放完畢：%s" % ("中途跳過" if _aborted else "完整播完"))
			get_tree().quit(0)


func _on_skip() -> void:
	if _finished:
		return
	_aborted = true
	if _collapse_tween:
		_collapse_tween.kill()
	_finish()


# ---------------------------------------------------------------- 各種拍

func _beat_subtitle(beat: Dictionary) -> void:
	_dialogue.hide_box()
	_hide_hint()
	if _black.modulate.a < 1.0:
		_black.visible = true
		await _fade(_black, 1.0, 0.6)
		if _aborted:
			return
	_white.visible = false
	_white.modulate.a = 0.0
	_subtitle_label.text = Game.t(str(beat["text"]))
	_subtitle_label.modulate.a = 0.0
	_subtitle_label.visible = true
	await _fade(_subtitle_label, 1.0, 0.6)
	if _aborted:
		return
	_waiting_subtitle = true
	if Game.autoplay:
		_auto_subtitle()
	await _subtitle_advanced
	_waiting_subtitle = false
	if _aborted:
		return
	await _fade(_subtitle_label, 0.0, 0.4)
	_subtitle_label.visible = false


func _beat_line(who: String, beat: Dictionary) -> void:
	await _reveal_scene()
	if _aborted:
		return
	_command_panel.hide_commands()
	if beat.has("fx"):
		# 演出與說明文字同時進行
		_play_fx(str(beat["fx"]), beat)
	# 說話的人保持明亮，其他人稍微暗下來
	for id: String in _actors:
		(_actors[id] as BattleActor).set_dimmed(who != "" and id != who)
	_line_serial += 1
	if who == "":
		_dialogue.show_line("", Game.t(str(beat["text"])))
	else:
		var side := "enemy" if _battle.units[who]["side"] == "enemy" else "party"
		var head := UiKit.head_texture(str(beat.get("face", who)))
		_dialogue.show_line(Game.data.character_name(who), Game.t(str(beat["text"])), side, head)
	if Game.autoplay:
		_auto_dialogue(str(beat["text"]), _line_serial)
	await _dialogue.advanced
	if _aborted:
		return
	_dialogue.hide_box()
	for id: String in _actors:
		(_actors[id] as BattleActor).set_dimmed(false)


func _beat_act(beat: Dictionary) -> void:
	await _reveal_scene()
	if _aborted:
		return
	var who := str(beat["who"])
	var actor: BattleActor = _actors[who]
	var move_id := str(beat["move"])
	var move: Dictionary = Game.data.moves[move_id]
	var move_name := Game.data.move_name(move_id)
	var is_party: bool = _battle.units[who]["side"] == "party"
	var targets := _battle.resolve_targets(str(beat.get("target", "")))
	var input := _battle.required_input(beat)

	# 輪到這個人：行動條跑滿
	if is_party:
		_party_panel.set_active(who)
		actor.set_active(true)
		var fill := actor.set_gauge(1.0, 0.45)
		await fill.finished
		if _aborted:
			return
		actor.play_anim("ready")

	if not input.is_empty():
		await _wait_for_move(who, input)
		if _aborted:
			return
	_hide_hint()

	# 蓄招
	var charge := float(beat.get("charge", 0.0))
	if charge > 0.0:
		var charging := actor.show_charge(Game.t("UI_CHARGING_FMT") % move_name, charge * CHARGE_TIME_SCALE)
		await charging.finished
		if _aborted:
			return
		actor.hide_charge()
	elif _battle.units[who]["charging"] == move_id:
		# 先前已經用「蓄招」拍開始蓄了，這裡把倒數條跑完
		await actor.finish_charge(0.5).finished
		if _aborted:
			return
		actor.hide_charge()

	_show_move_call("%s　%s" % [Game.data.character_name(who), move_name])
	# 出手了：頭上的箭頭與行動條收起來
	actor.set_active(false)
	actor.set_gauge(0.0)

	# 近身招式：先衝到目標面前
	var anim := str(move["anim"])
	var melee: bool = str(move["reach"]) == "melee" and not _pinned.has(who)
	if melee and not targets.is_empty():
		var target_actor: BattleActor = _actors[targets[0]]
		var gap := target_actor.body_size.x / 2.0 + actor.body_size.x / 2.0 + MELEE_GAP
		# 往下站幾個像素，出手的人才會畫在對手的前面
		var spot := target_actor.position + Vector2(-gap * actor.facing(), 4.0)
		await actor.move_to(spot, 0.18).finished
		if _aborted:
			return

	var impact := actor.anim_impact_time(anim)
	var length := actor.play_anim(anim)
	await _wait(impact)
	if _aborted:
		return

	# 出手點：結算
	var changes := _battle.apply(beat)
	_show_move_fx(actor, move, targets)
	_show_changes(changes)
	_refresh_states()
	if beat.get("shake", false):
		_shake(18.0, 0.5)
	if beat.get("flash", false):
		_flash()
	if Game.autoplay:
		Game.take_shot("impact_%s" % move_id)

	await _wait(maxf(0.1, length - impact) + 0.15)
	if _aborted:
		return
	if melee:
		await actor.go_home(0.25).finished
		if _aborted:
			return
	if is_party:
		_command_panel.hide_commands()
		_party_panel.set_active("")
	_hide_move_call()
	await _wait(0.3)


func _beat_command(beat: Dictionary) -> void:
	await _reveal_scene()
	if _aborted:
		return
	var input := _battle.required_input(beat)
	var who := str(input.get("who", _battle.party[0]))
	if not input.is_empty():
		_party_panel.set_active(who)
		await _wait_for_command(who, input)
		if _aborted:
			return
	_hide_hint()
	_battle.apply(beat)
	_show_move_call(Game.t("CMD_GUARD"))
	for id in _battle.party:
		(_actors[id] as BattleActor).play_anim("guard")
	_refresh_states()
	_command_panel.hide_commands()
	_party_panel.set_active("")
	await _wait(0.7)
	_hide_move_call()


func _beat_charge(beat: Dictionary) -> void:
	await _reveal_scene()
	if _aborted:
		return
	_battle.apply(beat)
	var who := str(beat["who"])
	var actor: BattleActor = _actors[who]
	var move_name := Game.data.move_name(str(beat["move"]))
	_show_move_call(Game.t("UI_WARNING_FMT") % move_name, UiKit.ENEMY)
	# 倒數條先跑到七成，等玩家反應；真正出手時再跑完
	actor.show_charge(Game.t("UI_CHARGING_FMT") % move_name, float(beat["time"]) * CHARGE_TIME_SCALE * 0.5, 0.7)
	_pulse_tint(Color(0.8, 0.1, 0.1), 0.18, 0.5)
	await _wait(0.9)


func _beat_scene(beat: Dictionary) -> void:
	_scene_name = str(beat["name"])
	_dialogue.hide_box()
	_hide_hint()
	if _collapse_tween:
		_collapse_tween.kill()
		_collapse_tween = null
	_tint.modulate.a = 0.0
	_stage.position = Vector2.ZERO
	_cast.visible = false
	_party_panel.visible = false
	_enemy_panel.visible = false
	_hide_move_call()
	_command_panel.hide_commands()
	_build_background(_scene_name)
	_layout()
	await _reveal_scene()


# ---------------------------------------------------------------- 玩家操作

func _wait_for_move(who: String, input: Dictionary) -> void:
	var move_id := str(input["id"])
	var move_name := Game.data.move_name(move_id)
	var mode := str(input["mode"])
	_command_panel.show_commands(_move_list(who), "move", move_id, Game.data.character_name(who))
	var fmt := Game.t("UI_PICK_FMT") if mode == "full" else Game.t("UI_PRESS_FMT")
	_append_hint(fmt % move_name)
	if Game.autoplay:
		_auto_press("move_%s" % move_id)
	await _command_panel.move_pressed
	if _aborted:
		return
	_command_panel.lock_all()
	if mode != "full":
		return

	# 自己選目標：只有劇本指定的對象可以選
	var target_id := str(input["target"])
	var target: BattleActor = _actors[target_id]
	_show_hint(Game.t("UI_SELECT_TARGET"))
	target.set_targetable(true)
	if Game.autoplay:
		_auto_target(target_id)
	await _target_chosen
	target.set_targetable(false)


func _wait_for_command(who: String, input: Dictionary) -> void:
	var command := str(input["id"])
	_command_panel.show_commands(_move_list(who), "command", command, Game.data.character_name(who))
	_append_hint(Game.t("UI_PRESS_FMT") % Game.t(CommandPanel.COMMAND_TEXT[command]))
	if Game.autoplay:
		_auto_press("command_%s" % command)
	await _command_panel.command_pressed
	_command_panel.lock_all()


func _move_list(who: String) -> Array:
	var list: Array = []
	for move_id: String in Game.data.characters[who]["moves"]:
		list.append({
			"id": move_id,
			"name": Game.data.move_name(move_id),
			"force": str(Game.data.moves[move_id].get("force", "")),
		})
	return list


func _on_actor_clicked(actor_id: String) -> void:
	_target_chosen.emit(actor_id)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	if _waiting_subtitle:
		get_viewport().set_input_as_handled()
		_subtitle_advanced.emit()
		return
	# 選目標時，Enter 或空白鍵直接選唯一可選的對象
	for id: String in _actors:
		var actor: BattleActor = _actors[id]
		if actor.is_targetable():
			get_viewport().set_input_as_handled()
			_target_chosen.emit(id)
			return


func _on_black_input(event: InputEvent) -> void:
	if not _waiting_subtitle:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_subtitle_advanced.emit()


# ---------------------------------------------------------------- 自動播放（開發用）
# 每一次自動「按」都綁在它要按的那個東西上：真正送出之前會再確認畫面還停在那裡，
# 否則較慢的模擬點擊會按到後面的台詞。

func _auto_dialogue(label: String, serial: int) -> void:
	var on_this_line := func() -> bool: return serial == _line_serial and _dialogue.visible
	if Game.read_scale > 0.0:
		# 錄影用：等字打完，再留一段閱讀時間
		while _dialogue.is_typing():
			await get_tree().process_frame
		await _wait((0.7 + 0.06 * Game.t(label).length()) * Game.read_scale)
	elif Game.input_mode == "direct":
		# 直接呼叫時，順便走一次「第一下只是把字全部顯示出來」
		await _wait(0.05)
		if on_this_line.call() and _dialogue.is_typing():
			_dialogue.advance()
	else:
		# 模擬的點擊要到下一個畫格才會被處理，所以不搶著按，等字打完再按一下就好
		while on_this_line.call() and _dialogue.is_typing():
			await get_tree().process_frame
	if not on_this_line.call():
		return
	await Game.take_shot("line_%s" % label)
	await _auto_tap(size / 2.0, _dialogue.advance, on_this_line)


func _auto_subtitle() -> void:
	await Game.take_shot("subtitle")
	await _wait(0.05 + 2.0 * Game.read_scale)
	await _auto_tap(size / 2.0, _subtitle_advanced.emit, func() -> bool: return _waiting_subtitle)


func _auto_press(label: String) -> void:
	await _wait(0.1 + 2.2 * Game.read_scale)
	await Game.take_shot("input_%s" % label)
	await _auto_tap(_command_panel.enabled_center(), _command_panel.press_enabled, _command_panel.has_enabled)


func _auto_target(actor_id: String) -> void:
	await _wait(0.1 + 1.0 * Game.read_scale)
	await Game.take_shot("target_%s" % actor_id)
	var actor: BattleActor = _actors[actor_id]
	await _auto_tap(actor.chest_global(), _target_chosen.emit.bind(actor_id), actor.is_targetable)


## 依啟動參數決定怎麼「按」：直接呼叫、模擬滑鼠點擊，或模擬 Enter 鍵。
## 後兩種會走過真正的輸入流程，用來確認按鈕確實點得到。
func _auto_tap(pos: Vector2, direct: Callable, still_wanted: Callable) -> void:
	match Game.input_mode:
		"clicks":
			await Game.click_at(pos, still_wanted)
		"keys":
			await Game.press_accept(still_wanted)
		_:
			if still_wanted.call():
				direct.call()


# ---------------------------------------------------------------- 演出

func _play_fx(fx: String, beat: Dictionary) -> void:
	match fx:
		"shake":
			_shake(15.0, 0.5)
		"pin":
			# 幾個人同時繞到目標背後架住他：一個在遠側、一個在近側，都轉身面向目標，正面留給主角
			var target: BattleActor = _actors[str(beat["target"])]
			var who_list: Array = beat.get("who", [])
			for i in who_list.size():
				var id := str(who_list[i])
				var actor: BattleActor = _actors[id]
				var reach := target.body_size.x / 2.0 + actor.body_size.x / 2.0
				var near: bool = i % 2 == 1
				var offset := Vector2(-target.facing() * (reach + (150.0 if near else 16.0)), 16.0 if near else -72.0)
				actor.move_to(target.position + offset, 0.22)
				actor.set_flipped(true)
				_pinned.append(id)
			await _wait(0.25)
			for id in _pinned:
				(_actors[id] as BattleActor).play_anim("attack_light")
			_shake(10.0, 0.3)
			await _wait(0.5)
		"release":
			for id in _pinned:
				var actor: BattleActor = _actors[id]
				actor.set_flipped(false)
				actor.go_home(0.35)
			_pinned.clear()
			await _wait(0.4)
		"collapse":
			# 大殿崩解：持續震動，畫面泛紅
			_tint.color = Color(0.5, 0.0, 0.15)
			_collapse_tween = create_tween().set_loops()
			_collapse_tween.tween_property(_tint, "modulate:a", 0.38, 0.5)
			_collapse_tween.parallel().tween_property(_stage, "position", Vector2(9, -6), 0.08)
			_collapse_tween.tween_property(_stage, "position", Vector2(-8, 5), 0.08)
			_collapse_tween.tween_property(_stage, "position", Vector2(6, 7), 0.08)
			_collapse_tween.tween_property(_tint, "modulate:a", 0.2, 0.5)
			_collapse_tween.parallel().tween_property(_stage, "position", Vector2(-5, -7), 0.08)
		"push_out":
			# 主角把同伴震出殿外
			var hero: BattleActor = _actors[_battle.party[0]]
			hero.play_anim("attack_heavy")
			await _wait(hero.anim_impact_time("attack_heavy"))
			_flash(0.5)
			for i in range(1, _battle.party.size()):
				var actor: BattleActor = _actors[_battle.party[i]]
				actor.play_anim("hit")
				actor.move_to(Vector2(-400.0, actor.position.y), 0.45)
			await _wait(0.5)
		"walk_to_enemy":
			var hero: BattleActor = _actors[_battle.party[0]]
			var enemy: BattleActor = _actors[_battle.enemies[0]]
			hero.play_anim("walk")
			var gap := enemy.body_size.x / 2.0 + hero.body_size.x / 2.0 + MELEE_GAP
			var walking := create_tween()
			walking.tween_property(hero, "position", enemy.position - Vector2(gap, 0), 1.6)
			await walking.finished
			hero.play_anim("idle")
		"white_out":
			_white.visible = true
			await _fade(_white, 1.0, 2.2)


func _reveal_scene() -> void:
	## 字幕結束後，把黑幕與白幕淡出，露出場景。
	if _black.modulate.a <= 0.0 and _white.modulate.a <= 0.0:
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(_black, "modulate:a", 0.0, 0.8)
	tween.tween_property(_white, "modulate:a", 0.0, 0.8)
	await tween.finished
	_black.visible = false
	_white.visible = false


func _show_changes(changes: Array[Dictionary]) -> void:
	for change in changes:
		var unit_id := str(change["unit"])
		var actor: BattleActor = _actors[unit_id]
		var to := float(change["to"])
		if change["stat"] == "mp":
			_party_panel.set_mp(unit_id, to)
			continue
		var damage: bool = to < float(change["from"])
		_party_panel.set_hp(unit_id, to)
		if unit_id == _battle.enemies[0]:
			_set_enemy_hp(to, true)
		if damage:
			_spawn_number(actor, "-%d" % int(change["amount"]), UiKit.DAMAGE)
			actor.play_anim("down" if to <= 0.0 else "hit")
		else:
			_spawn_number(actor, "+%d" % int(change["amount"]), UiKit.HEAL)
			actor.play_anim("cast")


## 出手那一刻的特效。招式資料的 fx 欄位寫明它用哪一組特效（設計文件 15.9）。
## 特效圖還沒有交付，目前依 fx 換成程式畫的暫用版本：弧光、氣勁、光環，顏色用招式的勁路識別色。
func _show_move_fx(actor: BattleActor, move: Dictionary, targets: Array) -> void:
	var heavy: bool = str(move.get("anim", "")) == "attack_heavy"
	var color: Color = UiKit.FORCE_COLOR.get(str(move.get("force", "")), UiKit.PAPER)
	var drawn := str(PLACEHOLDER_FX.get(str(move.get("fx", "")), ""))
	if drawn == "":
		# 專屬特效（絕招）：治療類用光環，近身的用交叉弧光，其餘用氣勁
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


func _set_enemy_hp(ratio: float, animate: bool) -> void:
	_enemy_bar.set_ratio(ratio, animate)
	_enemy_percent.text = "%d%%" % roundi(clampf(ratio, 0.0, 1.0) * 100.0)


func _refresh_states() -> void:
	for id: String in _actors:
		var actor: BattleActor = _actors[id]
		var state := str(_battle.units[id]["state"])
		actor.set_state_tag(Game.t(STATE_TEXT[state]) if STATE_TEXT.has(state) else "")
		if state == "stagger":
			actor.play_anim("stagger")
		elif state == "" and actor.current_loop() in ["guard", "stagger"]:
			actor.play_anim("idle")


func _spawn_number(actor: BattleActor, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(UiKit.SHADE, 0.95))
	label.add_theme_constant_override("outline_size", 12)
	label.size = Vector2(360, 80)
	# 從胸口上方冒出來往上飄；不放在頭頂，免得飄進上方的介面底下
	label.position = actor.position + Vector2(-180, -actor.body_size.y * 0.8)
	_numbers.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 110.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tween.tween_callback(label.queue_free)


func _shake(strength: float, duration: float) -> void:
	if _collapse_tween:
		return
	var tween := create_tween()
	var steps := maxi(2, int(duration / 0.05))
	for i in steps:
		var falloff := 1.0 - float(i) / float(steps)
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * falloff
		tween.tween_property(_stage, "position", offset, 0.05)
	tween.tween_property(_stage, "position", Vector2.ZERO, 0.05)


func _flash(peak: float = 0.85) -> void:
	_white.visible = true
	_white.modulate.a = peak
	var tween := create_tween()
	tween.tween_property(_white, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _white.visible = false)


func _pulse_tint(color: Color, peak: float, duration: float) -> void:
	_tint.color = color
	var tween := create_tween()
	tween.tween_property(_tint, "modulate:a", peak, duration / 2.0)
	tween.tween_property(_tint, "modulate:a", 0.0, duration / 2.0)


func _fade(node: CanvasItem, alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", alpha, duration)
	await tween.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------- 提示

func _show_hint(text: String) -> void:
	_hint_text = text
	_hint_panel.visible = true
	_layout_top()


func _append_hint(text: String) -> void:
	if _hint_panel.visible and _hint_text != "":
		_show_hint("%s\n%s" % [_hint_text, text])
	else:
		_show_hint(text)


func _hide_hint() -> void:
	_hint_panel.visible = false
	_hint_text = ""
	_layout_top()


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

	# 戰場：_stage_holder 負責縮放與置中，_stage 只拿來做震動的位移
	_stage_holder = _plain()
	add_child(_stage_holder)
	_stage = _plain()
	_stage_holder.add_child(_stage)
	_background = _plain()
	_stage.add_child(_background)
	_scene_name = _battle.background
	_build_background(_scene_name)
	_cast = _plain()
	_stage.add_child(_cast)
	_actor_layer = _plain()
	_cast.add_child(_actor_layer)
	_overlays = _plain()
	_cast.add_child(_overlays)
	_numbers = _plain()
	_cast.add_child(_numbers)

	for id in _battle.party:
		_add_actor(id, false)
	for id in _battle.enemies:
		_add_actor(id, true)

	_tint = ColorRect.new()
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0.5, 0, 0)
	_tint.modulate.a = 0.0
	add_child(_tint)

	# 上方的介面
	_party_panel = PartyPanel.new()
	add_child(_party_panel)
	var members: Array = []
	for id in _battle.party:
		var c: Dictionary = Game.data.characters[id]
		members.append({
			"id": id, "name": Game.data.character_name(id),
			"hp_max": c["hp_max"], "mp_max": c["mp_max"],
		})
	_party_panel.setup(members)

	_enemy_panel = _build_enemy_panel(_battle.enemies[0])
	add_child(_enemy_panel)

	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", UiKit.panel_style(HINT_PAD, 18.0))
	_hint_label = UiKit.label("", HINT_FONT)
	_hint_panel.add_child(_hint_label)
	_hint_panel.visible = false
	add_child(_hint_panel)

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

	# 下方：指令與對話
	_command_panel = CommandPanel.new()
	add_child(_command_panel)

	_dialogue = DialogueBox.new()
	add_child(_dialogue)

	# 全畫面的黑幕、白幕與字幕
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_black.gui_input.connect(_on_black_input)
	add_child(_black)

	_white = ColorRect.new()
	_white.color = Color.WHITE
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.modulate.a = 0.0
	_white.visible = false
	add_child(_white)

	_subtitle_label = UiKit.label("", 56, UiKit.TEXT, 8)
	_subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_subtitle_label.visible = false
	add_child(_subtitle_label)

	_skip_button = Button.new()
	UiKit.style_button(_skip_button, 36)
	_skip_button.text = Game.t("UI_SKIP")
	_skip_button.size = Vector2(220, 84)
	_skip_button.pressed.connect(_on_skip)
	add_child(_skip_button)

	_end_card = _build_end_card()
	add_child(_end_card)


func _plain() -> Control:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _add_actor(id: String, enemy: bool) -> void:
	var c: Dictionary = Game.data.characters[id]
	var actor := BattleActor.new()
	_actor_layer.add_child(actor)
	actor.setup(id, Game.data.character_name(id), Color(str(c["color"])), enemy, bool(c.get("boss", false)))
	actor.attach_overlay(_overlays)
	actor.clicked.connect(_on_actor_clicked)
	_actors[id] = actor


## 敵方的氣血：記號、名字、一條長的氣血條、百分比。放在畫面上方中央。
func _build_enemy_panel(enemy_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(30.0, 16.0))
	panel.custom_minimum_size = Vector2(0, UiKit.PANEL_SLICE * 2)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var marker := Glyph.new("diamond", UiKit.ENEMY, 30.0)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(marker)
	row.add_child(UiKit.label(Game.data.character_name(enemy_id), 36))

	_enemy_bar = Bar.new()
	_enemy_bar.setup_textured(Vector2(420, 32))
	_enemy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_enemy_bar)

	_enemy_percent = UiKit.label("100%", 36)
	_enemy_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_percent.custom_minimum_size = Vector2(100, 0)
	row.add_child(_enemy_percent)
	return panel


## 場景的背景。有圖就用圖（assets/backgrounds/battle/），還沒有圖的場景先用色塊。
func _build_background(scene_name: String) -> void:
	for child in _background.get_children():
		_background.remove_child(child)
		child.queue_free()
	var path := "res://assets/backgrounds/battle/%s.jpg" % scene_name
	if ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.name = "Image"
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.texture = load(path)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_background.add_child(image)
	elif scene_name == "old_house":
		# 青石鎮舊居，還沒有圖：昏暗的屋內、一根屋樑、窗外透進來的晨光
		_add_bg_gradient("Base", [Color("#2b221b"), Color("#17110d")], false)
		_add_bg_gradient("Glow", [Color(0.93, 0.82, 0.58, 0.5), Color(0.93, 0.82, 0.58, 0.0)], true)
		_add_bg_gradient("Window", [Color(0.96, 0.88, 0.68, 0.95), Color(0.9, 0.76, 0.5, 0.75)], false)
		_add_bg_rect("WindowBarV", Color("#2a1f17"))
		_add_bg_rect("WindowBarH", Color("#2a1f17"))
		_add_bg_gradient("Beam", [Color("#4b3626"), Color("#2c1f16")], false)
		_add_bg_gradient("Floor", [Color("#211912"), Color("#0e0a08")], false)
	else:
		_add_bg_rect("Base", Color("#172329"))
		_add_bg_rect("Floor", Color("#2c3a3d"))


func _add_bg_rect(node_name: String, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	_background.add_child(rect)


## 漸層色塊：直向由上到下，或由中心向外的放射狀。
func _add_bg_gradient(node_name: String, colors: Array, radial: bool) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, colors[0])
	gradient.set_color(1, colors[1])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	if radial:
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
	else:
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	_background.add_child(rect)


func _build_end_card() -> Control:
	var card := ColorRect.new()
	card.color = Color("#0b1215")
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

	box.add_child(UiKit.label(Game.t("UI_PROLOGUE_END"), 84))
	box.add_child(UiKit.label(Game.t("UI_PROLOGUE_END_NOTE"), 40, UiKit.TEXT_DIM))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	var replay := _make_button(Game.t("UI_REPLAY"), Vector2(320, 128), 44)
	replay.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(replay)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _make_button(Game.t("UI_QUIT"), Vector2(320, 128), 44)
		quit.pressed.connect(func() -> void: get_tree().quit())
		buttons.add_child(quit)
	return card


func _show_error(messages: Array) -> void:
	var label := UiKit.label(Game.t("UI_LOAD_ERROR") + "\n\n" + "\n".join(messages), 36, UiKit.DAMAGE)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	add_child(label)
	for message: String in messages:
		push_error(message)
	if Game.autoplay:
		get_tree().quit(1)


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	UiKit.style_button(button, font_size)
	button.text = text
	button.custom_minimum_size = min_size
	button.size = min_size
	return button


# ---------------------------------------------------------------- 排版

func _layout() -> void:
	if _stage == null:
		return
	var w := size.x
	var h := size.y

	# 戰場：高度對齊視窗，寬度看得到多少算多少；比背景圖還寬的話，戰場置中、兩側留黑
	var s := h / STAGE_HEIGHT
	_stage_width = minf(w / s, BG_SIZE.x)
	_stage_holder.scale = Vector2(s, s)
	_stage_holder.position = Vector2((w - _stage_width * s) / 2.0, 0)
	_layout_background()
	for i in _battle.party.size():
		_place_actor(_battle.party[i], PARTY_SPOTS[i])
	for i in _battle.enemies.size():
		_place_actor(_battle.enemies[i], ENEMY_SPOTS[mini(i, ENEMY_SPOTS.size() - 1)])

	# 介面
	_party_panel.position = Vector2(MARGIN, TOP)
	_skip_button.position = Vector2(w - MARGIN - _skip_button.size.x, TOP)
	_command_panel.position = Vector2((w - CommandPanel.PANEL_SIZE.x) / 2.0, h - BOTTOM - CommandPanel.PANEL_SIZE.y)
	_layout_top()


## 上方中央由上而下：敵方氣血、提示、招式名。
func _layout_top() -> void:
	if _hint_panel == null:
		return
	var w := size.x
	var left := MARGIN + _party_panel.size.x + 20.0
	var right := w - MARGIN - _skip_button.size.x - 20.0
	_enemy_panel.reset_size()
	_enemy_panel.position = Vector2(_center_between(_enemy_panel.size.x, left, right), TOP)

	# 提示有好幾行高，不能蓋到敵人的頭：右邊只到敵人的頭前面為止
	var enemy: BattleActor = _actors[_battle.enemies[0]]
	var enemy_head := _stage_holder.position.x + (enemy.home.x - enemy.body_size.x * 0.45) * _stage_holder.scale.x
	var hint_right := minf(right, enemy_head - 16.0)
	var hint_w := minf(940.0, hint_right - left)
	_hint_label.text = LineWrap.balanced(_hint_text, maxi(6, int((hint_w - HINT_PAD * 2.0) / HINT_FONT)))
	_hint_panel.reset_size()
	_hint_panel.position = Vector2(_center_between(_hint_panel.size.x, left, hint_right), TOP + _enemy_panel.size.y + 12.0)

	# 招式名放在提示的下面；提示比較高的時候往下讓
	var call_y := TOP + 318.0 * size.y / STAGE_HEIGHT
	if _hint_panel.visible:
		call_y = maxf(call_y, _hint_panel.position.y + _hint_panel.size.y + 10.0)
	_move_call.reset_size()
	_move_call.position = Vector2((w - _move_call.size.x) / 2.0, call_y)


## 盡量放在畫面正中；會壓到左右兩邊的東西時，改放在兩者之間的正中。
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
	_place_bg("Base", Rect2(-pad, -pad, vw + pad * 2.0, STAGE_HEIGHT + pad * 2.0))
	if _scene_name == "old_house":
		var window := Rect2(vw * 0.63, 300, 250, 300)
		_place_bg("Glow", Rect2(window.position - Vector2(520, 380), window.size + Vector2(1040, 760)))
		_place_bg("Window", window)
		_place_bg("WindowBarV", Rect2(window.position.x + window.size.x / 2.0 - 5.0, window.position.y, 10, window.size.y))
		_place_bg("WindowBarH", Rect2(window.position.x, window.position.y + window.size.y * 0.45, window.size.x, 10))
		_place_bg("Beam", Rect2(-pad, 150, vw + pad * 2.0, 84))
		_place_bg("Floor", Rect2(-pad, 760, vw + pad * 2.0, 320 + pad))
	else:
		_place_bg("Floor", Rect2(-pad, 715, vw + pad * 2.0, 365 + pad))


func _place_actor(id: String, spot: Dictionary) -> void:
	var actor: BattleActor = _actors[id]
	var was_home := actor.position.is_equal_approx(actor.home)
	actor.home = Vector2(_stage_width * float(spot["x"]), float(spot["y"]))
	if was_home:
		actor.position = actor.home


func _place_bg(node_name: String, rect: Rect2) -> void:
	var node := _background.get_node_or_null(node_name) as Control
	if node:
		node.position = rect.position
		node.size = rect.size


## 站得愈下面（離鏡頭愈近）的人畫在愈上層。角色會移動，所以每一格都檢查。
func _process(_delta: float) -> void:
	if _actor_layer == null:
		return
	var ordered: Array = _actor_layer.get_children()
	var sorted := true
	for i in range(1, ordered.size()):
		if (ordered[i] as Control).position.y < (ordered[i - 1] as Control).position.y:
			sorted = false
			break
	if sorted:
		return
	ordered.sort_custom(func(a: Control, b: Control) -> bool: return a.position.y < b.position.y)
	for i in ordered.size():
		_actor_layer.move_child(ordered[i], i)
