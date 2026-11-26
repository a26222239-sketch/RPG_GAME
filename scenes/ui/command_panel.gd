extends Control
## 指令面板：6 個招式按鈕，加上守勢、調息、道具、逃跑。
## 劇本式戰鬥中，一次只有劇本指定的那一個按鈕可以按。

signal move_pressed(move_id: String)
signal command_pressed(command_id: String)

const MOVE_SLOTS := 6
const COMMANDS := ["guard", "rest", "item", "flee"]
const COMMAND_TEXT := {"guard": "CMD_GUARD", "rest": "CMD_REST", "item": "CMD_ITEM", "flee": "CMD_FLEE"}
const FORCE_TEXT := {"gang": "FORCE_GANG", "rou": "FORCE_ROU", "kuai": "FORCE_KUAI"}
const FORCE_COLOR := {
	"gang": Color("#d9603b"),
	"rou": Color("#3fa796"),
	"kuai": Color("#d9b13b"),
	"": Color("#8a8a8a"),
}
const COLOR_TEXT := Color("#f2ead8")
const COLOR_DISABLED := Color("#6f6a60")
const COLOR_HIGHLIGHT := Color("#ffd84a")
const MOVE_SIZE := Vector2(300, 104)
const COMMAND_SIZE := Vector2(222, 84)
const GAP := 12.0
const FORCE_STRIP := 58
const COMMAND_STRIP := 10

## 整個面板需要的大小，給外層排版用。
const PANEL_SIZE := Vector2(300 * 3 + 12 * 2, 104 * 2 + 12 * 2 + 84)

var _move_buttons: Array[Button] = []
var _move_ids: Array[String] = []
var _command_buttons: Dictionary = {}
var _pulse_tween: Tween
var _enabled_button: Button


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


## 顯示某個角色的指令。
## moves 是 [{ id, name, force }]；enabled_kind 是 "move" 或 "command"，enabled_id 是唯一能按的那個。
func show_commands(moves: Array, enabled_kind: String, enabled_id: String) -> void:
	visible = true
	_stop_pulse()
	_enabled_button = null
	_move_ids.clear()
	for i in MOVE_SLOTS:
		var button := _move_buttons[i]
		if i < moves.size():
			var move: Dictionary = moves[i]
			var force := str(move.get("force", ""))
			_move_ids.append(str(move["id"]))
			button.text = str(move["name"])
			var enabled: bool = enabled_kind == "move" and enabled_id == str(move["id"])
			_style_button(button, FORCE_COLOR.get(force, FORCE_COLOR[""]), enabled, FORCE_STRIP)
			_set_force_label(button, Game.t(FORCE_TEXT[force]) if FORCE_TEXT.has(force) else "", enabled)
			if enabled:
				_enabled_button = button
		else:
			_move_ids.append("")
			button.text = "—"
			_style_button(button, FORCE_COLOR[""], false, FORCE_STRIP)
			_set_force_label(button, "", false)
	for command: String in COMMANDS:
		var button: Button = _command_buttons[command]
		var enabled: bool = enabled_kind == "command" and enabled_id == command
		_style_button(button, Color("#7a6c55"), enabled, COMMAND_STRIP)
		if enabled:
			_enabled_button = button
	_start_pulse()


func hide_commands() -> void:
	_stop_pulse()
	_enabled_button = null
	visible = false


## 全部鎖住（玩家按完之後、演出進行中）。
func lock_all() -> void:
	_stop_pulse()
	_enabled_button = null
	for button in _move_buttons:
		button.disabled = true
	for command: String in _command_buttons:
		(_command_buttons[command] as Button).disabled = true


## 鍵盤或自動播放用：按下目前唯一亮著的按鈕。
func press_enabled() -> bool:
	if _enabled_button == null or not visible:
		return false
	_enabled_button.pressed.emit()
	return true


func has_enabled() -> bool:
	return visible and _enabled_button != null


## 目前亮著的按鈕在畫面上的中心點（開發用的模擬點擊會用到）。
func enabled_center() -> Vector2:
	if _enabled_button == null:
		return Vector2.ZERO
	return _enabled_button.get_global_rect().get_center()


func _unhandled_key_input(event: InputEvent) -> void:
	if not has_enabled():
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		press_enabled()
		return
	# 數字鍵 1–6 對應六個招式格
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := (event as InputEventKey).keycode - KEY_1
		if slot >= 0 and slot < MOVE_SLOTS and _move_buttons[slot] == _enabled_button:
			get_viewport().set_input_as_handled()
			press_enabled()


func _on_move_button(slot: int) -> void:
	if slot < _move_ids.size() and _move_ids[slot] != "":
		move_pressed.emit(_move_ids[slot])


func _on_command_button(command: String) -> void:
	command_pressed.emit(command)


func _set_force_label(button: Button, text: String, enabled: bool) -> void:
	var label := button.get_node("Force") as Label
	label.text = text
	label.add_theme_color_override("font_color", Color("#1a1408") if enabled else Color(0, 0, 0, 0.55))


func _style_button(button: Button, accent: Color, enabled: bool, strip: int) -> void:
	button.disabled = not enabled
	button.modulate = Color.WHITE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.border_width_left = strip
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		if enabled:
			style.bg_color = Color(0.2, 0.17, 0.12, 0.98)
			style.border_color = accent
			if state == "hover":
				style.bg_color = Color(0.28, 0.24, 0.16, 0.98)
			elif state == "pressed":
				style.bg_color = Color(0.36, 0.3, 0.18, 0.98)
		else:
			style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
			style.border_color = accent.darkened(0.55)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_HIGHLIGHT)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)


func _start_pulse() -> void:
	if _enabled_button == null:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_enabled_button, "modulate", Color(1.5, 1.4, 1.0), 0.45)
	_pulse_tween.tween_property(_enabled_button, "modulate", Color.WHITE, 0.45)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	for button in _move_buttons:
		button.modulate = Color.WHITE
	for command: String in _command_buttons:
		(_command_buttons[command] as Button).modulate = Color.WHITE


func _build() -> void:
	for i in MOVE_SLOTS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.position = Vector2((MOVE_SIZE.x + GAP) * (i % 3), (MOVE_SIZE.y + GAP) * int(i / 3.0))
		button.size = MOVE_SIZE
		button.add_theme_font_size_override("font_size", 40)
		button.pressed.connect(_on_move_button.bind(i))
		add_child(button)
		var force_label := Label.new()
		force_label.name = "Force"
		force_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		force_label.position = Vector2.ZERO
		force_label.size = Vector2(FORCE_STRIP, MOVE_SIZE.y)
		force_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		force_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		force_label.add_theme_font_size_override("font_size", 38)
		button.add_child(force_label)
		_move_buttons.append(button)

	var y := (MOVE_SIZE.y + GAP) * 2
	for i in COMMANDS.size():
		var command: String = COMMANDS[i]
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.text = Game.t(COMMAND_TEXT[command])
		button.position = Vector2((COMMAND_SIZE.x + GAP) * i, y)
		button.size = COMMAND_SIZE
		button.add_theme_font_size_override("font_size", 38)
		button.pressed.connect(_on_command_button.bind(command))
		add_child(button)
		_command_buttons[command] = button
		_style_button(button, Color("#7a6c55"), false, COMMAND_STRIP)
