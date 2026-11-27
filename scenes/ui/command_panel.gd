extends Control
## 指令面板：上排 6 個招式按鈕，下排是守勢、調息、道具、逃跑。
## 橫放在畫面最下方，角色站在它的上面。
## 劇本式戰鬥中，一次只有劇本指定的那一個按鈕可以按（show_commands）。
## 自由戰鬥中，這個人能用的招式與指令都可以按（show_choices），招式按鈕多一行內力消耗與蓄招時間。

signal move_pressed(move_id: String)
signal command_pressed(command_id: String)

const UiKit := preload("res://scenes/ui/ui_kit.gd")

const MOVE_SLOTS := 6
const COMMANDS := ["guard", "rest", "item", "flee"]
const COMMAND_TEXT := {"guard": "CMD_GUARD", "rest": "CMD_REST", "item": "CMD_ITEM", "flee": "CMD_FLEE"}
const FORCE_TEXT := {"gang": "FORCE_GANG", "rou": "FORCE_ROU", "kuai": "FORCE_KUAI"}
const MOVE_SIZE := Vector2(300, 104)
const COMMAND_SIZE := Vector2(222, 92)
const GAP := 12.0
const ROW_GAP := 10.0
const TAG_SIZE := Vector2(82, 56)
## 有第二行（內力、蓄招）時，勁路標籤縮小移到右上角。
const SMALL_TAG_SIZE := Vector2(64, 44)
const DETAIL_TOP := 52.0

## 整個面板需要的大小，給外層排版用。
const PANEL_SIZE := Vector2(300 * 6 + 12 * 5, 104 + 10 + 92)

var _move_buttons: Array[Button] = []
var _move_ids: Array[String] = []
var _command_buttons: Dictionary = {}
var _owner_label: Label
var _enabled_button: Button
## 自由戰鬥的模式：不只一個按鈕能按。
var _choice_mode: bool = false
var _selected: String = ""


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
	_choice_mode = false
	_selected = ""
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
			_layout_slot(button, "")
			_set_force_tag(button, str(move.get("force", "")), not button.disabled)
			if not button.disabled:
				_enabled_button = button
		else:
			_move_ids.append("")
			button.text = "—"
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.disabled = true
			_layout_slot(button, "")
			_set_force_tag(button, "", false)
	for command: String in COMMANDS:
		var button: Button = _command_buttons[command]
		button.disabled = not (enabled_kind == "command" and enabled_id == command)
		if not button.disabled:
			_enabled_button = button
	_start_pulse()


## 自由戰鬥：顯示某個角色的所有選項，能用的都可以按。
## moves 是 [{ id, name, force, detail, enabled }]，detail 是第二行（內力消耗、蓄招時間）；
## commands 是能按的指令（"guard"、"rest"）。
func show_choices(moves: Array, commands: Array, owner_name: String = "") -> void:
	visible = true
	_choice_mode = true
	_selected = ""
	_stop_pulse()
	_enabled_button = null
	_move_ids.clear()
	set_note(owner_name)
	for i in MOVE_SLOTS:
		var button := _move_buttons[i]
		if i < moves.size():
			var move: Dictionary = moves[i]
			_move_ids.append(str(move["id"]))
			button.text = str(move["name"])
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = not bool(move.get("enabled", true))
			_layout_slot(button, str(move.get("detail", "")))
			_set_force_tag(button, str(move.get("force", "")), not button.disabled)
		else:
			_move_ids.append("")
			button.text = "—"
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.disabled = true
			_layout_slot(button, "")
			_set_force_tag(button, "", false)
	for command: String in COMMANDS:
		(_command_buttons[command] as Button).disabled = not commands.has(command)


## 下排左邊那一格的文字。劇本式戰鬥寫招式的主人；自由戰鬥拿來寫提示（「燕回　選擇招式」）。
func set_note(text: String) -> void:
	_owner_label.text = text
	_owner_label.visible = text != ""
	_owner_label.reset_size()


## 自由戰鬥：選了招式、正在選目標時，那一顆按鈕保持亮著。空字串表示取消。
func set_selected(move_id: String) -> void:
	_selected = move_id
	for i in _move_buttons.size():
		UiKit.set_button_active(_move_buttons[i], move_id != "" and i < _move_ids.size() and _move_ids[i] == move_id)


func selected() -> String:
	return _selected


## 開發用（自動播放）：直接按某一個招式或指令。按不了時回傳 false。
func press_move(move_id: String) -> bool:
	var slot := _move_ids.find(move_id)
	if not visible or slot < 0 or _move_buttons[slot].disabled:
		return false
	_move_buttons[slot].pressed.emit()
	return true


func press_command(command: String) -> bool:
	var button: Button = _command_buttons.get(command)
	if not visible or button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


func can_press_move(move_id: String) -> bool:
	var slot := _move_ids.find(move_id)
	return visible and slot >= 0 and not _move_buttons[slot].disabled


func can_press_command(command: String) -> bool:
	return visible and _command_buttons.has(command) and not (_command_buttons[command] as Button).disabled


func move_center(move_id: String) -> Vector2:
	var slot := _move_ids.find(move_id)
	return _move_buttons[slot].get_global_rect().get_center() if slot >= 0 else Vector2.ZERO


func command_center(command: String) -> Vector2:
	return (_command_buttons[command] as Button).get_global_rect().get_center()


func hide_commands() -> void:
	_stop_pulse()
	_enabled_button = null
	_choice_mode = false
	_selected = ""
	visible = false


## 全部鎖住（玩家按完之後、演出進行中）。
func lock_all() -> void:
	_stop_pulse()
	_enabled_button = null
	for button in _move_buttons:
		button.disabled = true
		(button.get_node("Tag") as Control).modulate = Color(1, 1, 1, 0.45)
		(button.get_node("Detail") as Control).modulate = Color(1, 1, 1, 0.45)
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
	if _choice_mode and visible:
		# 自由戰鬥：數字鍵 1–6 按對應的招式格
		if event is InputEventKey and event.pressed and not event.echo:
			var choice_slot := (event as InputEventKey).keycode - KEY_1
			if choice_slot >= 0 and choice_slot < MOVE_SLOTS and not _move_buttons[choice_slot].disabled:
				get_viewport().set_input_as_handled()
				_move_buttons[choice_slot].pressed.emit()
		return
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


## 按鈕右側的勁路標籤：一個字（剛、柔、快），顏色照風格指南。沒有勁路的招式不顯示。
## 2026-11-27 擁有者決定不用圖示，原本程式畫的記號（方印、雙弧、雙斜筆）也一併拿掉。
func _set_force_tag(button: Button, force: String, enabled: bool) -> void:
	var tag := button.get_node("Tag") as Control
	tag.visible = FORCE_TEXT.has(force)
	if not tag.visible:
		return
	var color: Color = UiKit.FORCE_COLOR[force]
	var label := tag.get_node("Text") as Label
	label.text = Game.t(FORCE_TEXT[force])
	label.add_theme_color_override("font_color", color)
	tag.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)


## 招式格的排法。detail 是第二行的文字；空字串時名字置中，勁路標籤放在右側正中（劇本式戰鬥的樣子）。
func _layout_slot(button: Button, detail: String) -> void:
	var detail_label := button.get_node("Detail") as Label
	var tag := button.get_node("Tag") as Control
	var two_rows := detail != ""
	detail_label.text = detail
	detail_label.visible = two_rows
	detail_label.modulate = Color(1, 1, 1, 0.45) if button.disabled else Color.WHITE
	var styles: Array = [button.get_meta("style_normal"), button.get_meta("style_active"),
		button.get_theme_stylebox("pressed"), button.get_theme_stylebox("disabled")]
	for style: StyleBoxTexture in styles:
		# 兩行時名字往上移到第一行；8 是 UiKit.button_style 的預設邊距
		style.content_margin_bottom = MOVE_SIZE.y - DETAIL_TOP if two_rows else 8.0
		style.content_margin_top = 6.0 if two_rows else 8.0
	var tag_size := SMALL_TAG_SIZE if two_rows else TAG_SIZE
	tag.size = tag_size
	tag.position = Vector2(MOVE_SIZE.x - tag_size.x - 12.0, 7.0 if two_rows else (MOVE_SIZE.y - tag_size.y) / 2.0)
	var text := tag.get_node("Text") as Label
	text.size = tag_size


## 現在該按的那一個按鈕換成「可按」的圖（GPT 畫的，邊框亮起來）。不再用閃爍。
func _start_pulse() -> void:
	if _enabled_button:
		UiKit.set_button_active(_enabled_button, true)


func _stop_pulse() -> void:
	for button in _move_buttons:
		UiKit.set_button_active(button, false)
	for command: String in _command_buttons:
		UiKit.set_button_active(_command_buttons[command], false)


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
		var detail := UiKit.label("", 36, UiKit.JADE)
		detail.name = "Detail"
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		detail.position = Vector2(22, DETAIL_TOP - 4.0)
		detail.size = Vector2(MOVE_SIZE.x - 34.0, MOVE_SIZE.y - DETAIL_TOP)
		detail.visible = false
		button.add_child(detail)
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
	var text := UiKit.label("", 36)
	text.name = "Text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.position = Vector2.ZERO
	text.size = TAG_SIZE
	tag.add_child(text)
	return tag
