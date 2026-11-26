extends Control
## 劇本式戰鬥的畫面層（設計文件 4.14）。
##
## 這個場景照著 data/scripted/ 裡的劇本一拍一拍播放：對話、出手、演出。
## 規則與狀態交給 ScriptedBattle；這裡只負責畫面與玩家的操作。
## 所有角色都是色塊佔位，動作經由 BattleActor.play_anim() 播放。

const ScriptedBattle := preload("res://core/scripted/scripted_battle.gd")
const BattleActor := preload("res://scenes/battle/battle_actor.gd")
const DialogueBox := preload("res://scenes/ui/dialogue_box.gd")
const CommandPanel := preload("res://scenes/ui/command_panel.gd")
const PartyPanel := preload("res://scenes/ui/party_panel.gd")

const MARGIN := 40.0
const BOTTOM_ZONE := 400.0
const COLOR_TEXT := Color("#f2ead8")
const COLOR_HIGHLIGHT := Color("#ffd84a")
const COLOR_DAMAGE := Color("#ff6b5a")
const COLOR_HEAL := Color("#7be08a")
const STATE_TEXT := {"guard": "STATE_GUARD", "stagger": "STATE_STAGGER", "slow": "STATE_SLOW"}

## 蓄招在畫面上實際等待的時間 = 劇本的秒數 × 這個倍率。劇本式戰鬥不需要等滿。
const CHARGE_TIME_SCALE := 0.6

## 各角色腳底的位置：x 是畫面寬度的比例，lift 是離下方面板區的高度。
const PARTY_SPOTS := [
	{"x": 0.38, "lift": 80.0},
	{"x": 0.30, "lift": 160.0},
	{"x": 0.20, "lift": 60.0},
	{"x": 0.10, "lift": 120.0},
]
const ENEMY_SPOTS := [
	{"x": 0.74, "lift": 50.0},
]

@export var script_id: String = "prologue_final"

var _battle: ScriptedBattle = ScriptedBattle.new()
var _actors: Dictionary = {}
var _pinned: Array[String] = []
var _aborted: bool = false
var _finished: bool = false
var _waiting_subtitle: bool = false
var _line_serial: int = 0
var _scene_name: String = ""

var _background: Control
var _stage: Control
var _numbers: Control
var _bottom_strip: ColorRect
var _party_panel: PartyPanel
var _command_panel: CommandPanel
var _hint_panel: PanelContainer
var _hint_label: Label
var _move_call: Label
var _title_label: Label
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
			await _beat_line("", Color.WHITE, beat)
		"say":
			var who := str(beat["who"])
			var color := Color(str(Game.data.characters[who]["color"]))
			await _beat_line(who, color, beat)
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


func _beat_line(who: String, color: Color, beat: Dictionary) -> void:
	await _reveal_scene()
	if _aborted:
		return
	_command_panel.hide_commands()
	if beat.has("fx"):
		# 演出與說明文字同時進行
		_play_fx(str(beat["fx"]), beat)
	for id: String in _actors:
		var actor: BattleActor = _actors[id]
		actor.set_speaking(id == who)
	var speaker := "" if who == "" else Game.data.character_name(who)
	_line_serial += 1
	_dialogue.show_line(speaker, color, Game.t(str(beat["text"])))
	if Game.autoplay:
		_auto_dialogue(str(beat["text"]), _line_serial)
	await _dialogue.advanced
	if _aborted:
		return
	_dialogue.hide_box()
	for id: String in _actors:
		(_actors[id] as BattleActor).set_speaking(false)


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

	# 近身招式：先衝到目標面前
	var anim := str(move["anim"])
	var melee: bool = str(move["reach"]) == "melee" and not _pinned.has(who)
	if melee and not targets.is_empty():
		var target_actor: BattleActor = _actors[targets[0]]
		var gap := target_actor.body_size.x / 2.0 + actor.body_size.x / 2.0 + 50.0
		var spot := target_actor.position + Vector2(-gap * actor.facing(), 0)
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
	_show_changes(changes)
	_refresh_states()
	if beat.get("shake", false):
		_shake(22.0, 0.5)
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
		actor.set_gauge(0.0)
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
	_show_move_call(Game.t("UI_WARNING_FMT") % move_name, COLOR_DAMAGE)
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
	_stage.visible = false
	_numbers.visible = false
	_bottom_strip.visible = false
	_party_panel.visible = false
	_command_panel.hide_commands()
	_title_label.visible = false
	_build_background(_scene_name)
	_layout()
	await _reveal_scene()


# ---------------------------------------------------------------- 玩家操作

func _wait_for_move(who: String, input: Dictionary) -> void:
	var move_id := str(input["id"])
	var move_name := Game.data.move_name(move_id)
	var mode := str(input["mode"])
	_command_panel.show_commands(_move_list(who), "move", move_id)
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
	_command_panel.show_commands(_move_list(who), "command", command)
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
	await _auto_tap(actor.global_position - Vector2(0, actor.body_size.y / 2.0),
		_target_chosen.emit.bind(actor_id), actor.is_targetable)


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
			_shake(18.0, 0.5)
		"pin":
			# 幾個人同時搶上，架住目標
			var target: BattleActor = _actors[str(beat["target"])]
			var who_list: Array = beat.get("who", [])
			for i in who_list.size():
				var id := str(who_list[i])
				var actor: BattleActor = _actors[id]
				var offset_y := -70.0 if i % 2 == 0 else -5.0
				var gap := target.body_size.x / 2.0 + actor.body_size.x / 2.0 + (0.0 if i % 2 == 0 else 50.0)
				actor.move_to(target.position + Vector2(gap * actor.facing(), offset_y), 0.22)
				_pinned.append(id)
			await _wait(0.25)
			for id in _pinned:
				(_actors[id] as BattleActor).play_anim("attack_light")
			_shake(12.0, 0.3)
			await _wait(0.5)
		"release":
			for id in _pinned:
				(_actors[id] as BattleActor).go_home(0.35)
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
			var gap := enemy.body_size.x / 2.0 + hero.body_size.x / 2.0 + 60.0
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
		actor.set_hp(to)
		_party_panel.set_hp(unit_id, to)
		if damage:
			_spawn_number(actor, "-%d" % int(change["amount"]), COLOR_DAMAGE)
			actor.play_anim("down" if to <= 0.0 else "hit")
		else:
			_spawn_number(actor, "+%d" % int(change["amount"]), COLOR_HEAL)
			actor.play_anim("cast")


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
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 12)
	label.size = Vector2(360, 80)
	label.position = actor.position + Vector2(-180, -actor.body_size.y - 40)
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
	_hint_label.text = text
	_hint_panel.visible = true
	_title_label.visible = false
	_layout_hint()


func _append_hint(text: String) -> void:
	if _hint_panel.visible and _hint_label.text != "":
		_show_hint("%s\n%s" % [_hint_label.text, text])
	else:
		_show_hint(text)


func _hide_hint() -> void:
	_hint_panel.visible = false
	_hint_label.text = ""
	_title_label.visible = _stage.visible


func _show_move_call(text: String, color: Color = COLOR_TEXT) -> void:
	_move_call.text = text
	_move_call.add_theme_color_override("font_color", color)
	_move_call.visible = true


func _hide_move_call() -> void:
	_move_call.visible = false


# ---------------------------------------------------------------- 建立畫面

func _build() -> void:
	_background = Control.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)
	_scene_name = _battle.background
	_build_background(_scene_name)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	for i in _battle.party.size():
		_add_actor(_battle.party[i], false, 0.88)
	for i in _battle.enemies.size():
		var boss: bool = Game.data.characters[_battle.enemies[i]].get("boss", false)
		_add_actor(_battle.enemies[i], true, 1.15 if boss else 0.88)

	_numbers = Control.new()
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_numbers)

	_tint = ColorRect.new()
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0.5, 0, 0)
	_tint.modulate.a = 0.0
	add_child(_tint)

	_bottom_strip = ColorRect.new()
	_bottom_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_strip.color = Color(0.04, 0.035, 0.06, 0.82)
	add_child(_bottom_strip)

	_party_panel = PartyPanel.new()
	add_child(_party_panel)
	var members: Array = []
	for id in _battle.party:
		var c: Dictionary = Game.data.characters[id]
		members.append({
			"id": id, "name": Game.data.character_name(id), "color": Color(str(c["color"])),
			"hp_max": c["hp_max"], "mp_max": c["mp_max"],
		})
	_party_panel.setup(members)

	_command_panel = CommandPanel.new()
	add_child(_command_panel)

	_move_call = _make_label("", 46)
	_move_call.visible = false
	add_child(_move_call)

	_title_label = _make_label(Game.t(_battle.title_key) if _battle.title_key != "" else "", 36)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.add_theme_color_override("font_color", Color("#a39a88"))
	add_child(_title_label)

	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.13, 0.11, 0.05, 0.95)
	hint_style.border_color = COLOR_HIGHLIGHT
	hint_style.set_border_width_all(4)
	hint_style.set_corner_radius_all(12)
	hint_style.content_margin_left = 32
	hint_style.content_margin_right = 32
	hint_style.content_margin_top = 16
	hint_style.content_margin_bottom = 16
	_hint_panel.add_theme_stylebox_override("panel", hint_style)
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 38)
	_hint_label.add_theme_color_override("font_color", COLOR_TEXT)
	_hint_panel.add_child(_hint_label)
	_hint_panel.visible = false
	add_child(_hint_panel)

	_dialogue = DialogueBox.new()
	add_child(_dialogue)

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

	_subtitle_label = _make_label("", 56)
	_subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_subtitle_label.visible = false
	add_child(_subtitle_label)

	_skip_button = _make_button(Game.t("UI_SKIP"), Vector2(260, 76), 36)
	_skip_button.pressed.connect(_on_skip)
	add_child(_skip_button)

	_end_card = _build_end_card()
	add_child(_end_card)


func _add_actor(id: String, enemy: bool, size_scale: float) -> void:
	var c: Dictionary = Game.data.characters[id]
	var actor := BattleActor.new()
	_stage.add_child(actor)
	actor.setup(id, Game.data.character_name(id), Color(str(c["color"])), enemy, size_scale)
	actor.set_gauge_visible(not enemy)
	actor.clicked.connect(_on_actor_clicked)
	_actors[id] = actor


func _build_background(scene_name: String) -> void:
	for child in _background.get_children():
		child.queue_free()
	var base := ColorRect.new()
	base.name = "Base"
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.add_child(base)
	if scene_name == "old_house":
		# 青石鎮舊居：昏黃的屋內、一根屋樑、一扇透光的窗
		base.color = Color("#2a2018")
		_add_bg_rect("Beam", Color("#4a3524"))
		_add_bg_rect("Window", Color("#d9c48a"))
		_add_bg_rect("Floor", Color("#1e1711"))
	else:
		# 天魔殿：暗色大殿、幾根柱子、一片地面
		base.color = Color("#17131d")
		for i in 5:
			_add_bg_rect("Pillar%d" % i, Color("#221b2b"))
		_add_bg_rect("Floor", Color("#2a2233"))
		_add_bg_rect("FloorLine", Color("#3a3046"))


func _add_bg_rect(node_name: String, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	_background.add_child(rect)


func _build_end_card() -> Control:
	var card := ColorRect.new()
	card.color = Color(0.03, 0.03, 0.05, 1.0)
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

	var title := _make_label(Game.t("UI_PROLOGUE_END"), 84)
	box.add_child(title)
	var note := _make_label(Game.t("UI_PROLOGUE_END_NOTE"), 40)
	note.add_theme_color_override("font_color", Color("#a39a88"))
	box.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	var replay := _make_button(Game.t("UI_REPLAY"), Vector2(320, 110), 44)
	replay.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(replay)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _make_button(Game.t("UI_QUIT"), Vector2(320, 110), 44)
		quit.pressed.connect(func() -> void: get_tree().quit())
		buttons.add_child(quit)
	return card


func _show_error(messages: Array) -> void:
	var label := _make_label(Game.t("UI_LOAD_ERROR") + "\n\n" + "\n".join(messages), 36)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	add_child(label)
	for message: String in messages:
		push_error(message)
	if Game.autoplay:
		get_tree().quit(1)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.1, 0.14, 0.9)
		if state == "hover":
			style.bg_color = Color(0.2, 0.17, 0.22, 0.95)
		elif state == "pressed":
			style.bg_color = Color(0.3, 0.25, 0.18, 0.95)
		style.border_color = Color("#6b5a40")
		style.set_border_width_all(3)
		style.set_corner_radius_all(10)
		button.add_theme_stylebox_override(state, style)
	return button


# ---------------------------------------------------------------- 排版

func _layout() -> void:
	if _stage == null:
		return
	var w := size.x
	var h := size.y
	var floor_top := h - BOTTOM_ZONE - 190.0

	# 背景
	if _scene_name == "old_house":
		_place_bg("Beam", Rect2(0, h * 0.16, w, 70))
		_place_bg("Window", Rect2(w * 0.62, h * 0.3, w * 0.16, h * 0.22))
		_place_bg("Floor", Rect2(0, h * 0.72, w, h * 0.28))
	else:
		for i in 5:
			_place_bg("Pillar%d" % i, Rect2(w * (0.06 + 0.22 * i), 0, w * 0.045, floor_top))
		_place_bg("Floor", Rect2(0, floor_top, w, h - floor_top))
		_place_bg("FloorLine", Rect2(0, floor_top, w, 6))

	# 角色
	for i in _battle.party.size():
		_place_actor(_battle.party[i], PARTY_SPOTS[i], w, h)
	for i in _battle.enemies.size():
		_place_actor(_battle.enemies[i], ENEMY_SPOTS[mini(i, ENEMY_SPOTS.size() - 1)], w, h)
	var ordered: Array = _actors.values()
	ordered.sort_custom(func(a: BattleActor, b: BattleActor) -> bool: return a.home.y < b.home.y)
	for i in ordered.size():
		_stage.move_child(ordered[i], i)
	_stage.move_child(_numbers, _stage.get_child_count() - 1)

	# 下方面板
	var strip_top := h - BOTTOM_ZONE + 24.0
	_bottom_strip.position = Vector2(0, strip_top)
	_bottom_strip.size = Vector2(w, h - strip_top)
	_party_panel.position = Vector2(MARGIN, h - MARGIN - _party_panel.size.y)
	_command_panel.position = Vector2(w - MARGIN - CommandPanel.PANEL_SIZE.x, h - MARGIN - CommandPanel.PANEL_SIZE.y)

	# 上方
	_title_label.position = Vector2(MARGIN, 28)
	_title_label.size = Vector2(320, 60)
	_skip_button.position = Vector2(w - MARGIN - _skip_button.size.x, 24)
	_move_call.position = Vector2(w * 0.53 - 280, h - BOTTOM_ZONE - 500.0)
	_move_call.size = Vector2(560, 70)
	_layout_hint()


func _layout_hint() -> void:
	if _hint_panel == null:
		return
	var w := size.x
	var hint_w := w - MARGIN - (_skip_button.size.x + MARGIN) - 30.0
	_hint_label.custom_minimum_size = Vector2(hint_w - 64.0, 0)
	_hint_panel.position = Vector2(MARGIN, 22)
	_hint_panel.reset_size()


func _place_actor(id: String, spot: Dictionary, w: float, h: float) -> void:
	var actor: BattleActor = _actors[id]
	var was_home := actor.position.is_equal_approx(actor.home)
	actor.home = Vector2(w * float(spot["x"]), h - BOTTOM_ZONE - float(spot["lift"]))
	if was_home:
		actor.position = actor.home


func _place_bg(node_name: String, rect: Rect2) -> void:
	var node := _background.get_node_or_null(node_name) as ColorRect
	if node:
		node.position = rect.position
		node.size = rect.size
