extends Control
## 指令面板：上排 6 個招式按鈕，下排是守勢、調息、道具、逃跑。
## 橫放在畫面最下方，角色站在它的上面。
## 劇本式戰鬥中，一次只有劇本指定的那一個按鈕可以按。

signal move_pressed(move_id: String)
signal command_pressed(command_id: String)

const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Glyph := preload("res://scenes/ui/glyph.gd")

const MOVE_SLOTS := 6
const COMMANDS := ["guard", "rest", "item", "flee"]
const COMMAND_TEXT := {"guard": "CMD_GUARD", "rest": "CMD_REST", "item": "CMD_ITEM", "flee": "CMD_FLEE"}
const FORCE_TEXT := {"gang": "FORCE_GANG", "rou": "FORCE_ROU", "kuai": "FORCE_KUAI"}
const MOVE_SIZE := Vector2(300, 104)
const COMMAND_SIZE := Vector2(222, 92)
const GAP := 12.0
const ROW_GAP := 10.0
const TAG_SIZE := Vector2(82, 56)

## 整個面板需要的大小，給外層排版用。
const PANEL_SIZE := Vector2(300 * 6 + 12 * 5, 104 + 10 + 92)

var _move_buttons: Array[Button] = []
var _move_ids: Array[String] = []
var _command_buttons: Dictionary = {}
var _owner_label: Label
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
## owner_name 是這些招式的主人，顯示在下排左邊。
func show_commands(moves: Array, enabled_kind: String, enabled_id: String, owner_name: String = "") -> void:
	visible = true
	_stop_pulse()
	_enabled_button = null
	_move_ids.clear()
	_owner_label.text = owner_name
	_owner_label.visible = owner_name != ""
	for i in MOVE_SLOTS:
		var button := _move_buttons[i]
		if i < moves.size():
			var move: Dictionary = moves[i]
			_move_ids.append(str(move["id"]))
			button.text = str(move["name"])
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = not (enabled_kind == "move" and enabled_id == str(move["id"]))
			_set_force_tag(button, str(move.get("force", "")), not button.disabled)
			if not button.disabled:
				_enabled_button = button
		else:
			_move_ids.append("")
			button.text = "—"
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.disabled = true
			_set_force_tag(button, "", false)
	for command: String in COMMANDS:
		var button: Button = _command_buttons[command]
		button.disabled = not (enabled_kind == "command" and enabled_id == command)
		if not button.disabled:
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
		(button.get_node("Tag") as Control).modulate = Color(1, 1, 1, 0.45)
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


## 按鈕右側的勁路標籤：記號加一個字，顏色照風格指南。沒有勁路的招式不顯示。
func _set_force_tag(button: Button, force: String, enabled: bool) -> void:
	var tag := button.get_node("Tag") as Control
	tag.visible = FORCE_TEXT.has(force)
	if not tag.visible:
		return
	var color: Color = UiKit.FORCE_COLOR[force]
	(tag.get_node("Glyph") as Glyph).kind = force
	(tag.get_node("Glyph") as Glyph).color = color
	var label := tag.get_node("Text") as Label
	label.text = Game.t(FORCE_TEXT[force])
	label.add_theme_color_override("font_color", color)
	tag.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)


func _start_pulse() -> void:
	if _enabled_button == null:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_enabled_button, "modulate", Color(1.45, 1.38, 1.1), 0.45)
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
		UiKit.style_button(button, 36)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			(button.get_theme_stylebox(state) as StyleBoxTexture).content_margin_left = 22
		button.clip_text = true
		button.position = Vector2((MOVE_SIZE.x + GAP) * i, 0)
		button.size = MOVE_SIZE
		button.pressed.connect(_on_move_button.bind(i))
		add_child(button)
		button.add_child(_build_force_tag())
		_move_buttons.append(button)

	var y := MOVE_SIZE.y + ROW_GAP
	var commands_w := COMMAND_SIZE.x * COMMANDS.size() + GAP * (COMMANDS.size() - 1)
	var x0 := PANEL_SIZE.x - commands_w
	for i in COMMANDS.size():
		var command: String = COMMANDS[i]
		var button := Button.new()
		UiKit.style_button(button, 36)
		button.text = Game.t(COMMAND_TEXT[command])
		button.position = Vector2(x0 + (COMMAND_SIZE.x + GAP) * i, y)
		button.size = COMMAND_SIZE
		button.disabled = true
		button.pressed.connect(_on_command_button.bind(command))
		add_child(button)
		_command_buttons[command] = button

	# 下排左邊：這一排招式是誰的
	_owner_label = UiKit.label("", 36, UiKit.HIGHLIGHT)
	_owner_label.add_theme_stylebox_override("normal", UiKit.tag_style(UiKit.BRONZE, 0.86))
	_owner_label.position = Vector2(0, y + (COMMAND_SIZE.y - 60.0) / 2.0)
	_owner_label.custom_minimum_size = Vector2(0, 60)
	add_child(_owner_label)


func _build_force_tag() -> Control:
	var tag := Panel.new()
	tag.name = "Tag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.position = Vector2(MOVE_SIZE.x - TAG_SIZE.x - 12.0, (MOVE_SIZE.y - TAG_SIZE.y) / 2.0)
	tag.size = TAG_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.INK
	style.set_corner_radius_all(4)
	tag.add_theme_stylebox_override("panel", style)
	var glyph := Glyph.new("kuai", Color.WHITE, 26.0)
	glyph.name = "Glyph"
	glyph.position = Vector2(6, (TAG_SIZE.y - 26.0) / 2.0)
	tag.add_child(glyph)
	var text := UiKit.label("", 36)
	text.name = "Text"
	text.position = Vector2(34, 0)
	text.size = Vector2(TAG_SIZE.x - 36.0, TAG_SIZE.y)
	tag.add_child(text)
	return tag
