extends Control
## 啟動畫面：遊戲名稱與「開始」。目前開始之後直接進入序章。

const PROLOGUE_SCENE := "res://scenes/battle/scripted_battle_scene.tscn"
const COLOR_TEXT := Color("#f2ead8")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color("#0d0b11")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 48)
	add_child(box)

	box.add_child(_label(Game.t("UI_GAME_TITLE"), 96, COLOR_TEXT))
	box.add_child(_label(Game.t("UI_TITLE_SUB"), 48, Color("#a39a88")))

	if not Game.data_ok:
		box.add_child(_label(Game.t("UI_LOAD_ERROR") + "\n" + "\n".join(Game.data.errors), 36, Color("#ff6b5a")))
		return

	var start := Button.new()
	start.text = Game.t("UI_START")
	start.focus_mode = Control.FOCUS_NONE
	start.custom_minimum_size = Vector2(360, 120)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 52)
	start.add_theme_color_override("font_color", COLOR_TEXT)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.12, 0.16) if state == "normal" else Color(0.26, 0.22, 0.16)
		style.border_color = Color("#6b5a40")
		style.set_border_width_all(4)
		style.set_corner_radius_all(12)
		start.add_theme_stylebox_override(state, style)
	start.pressed.connect(_start)
	box.add_child(start)

	if Game.autoplay:
		await Game.take_shot("title")
		if Game.read_scale > 0.0:
			await get_tree().create_timer(1.5 * Game.read_scale).timeout
		_start()


func _unhandled_key_input(event: InputEvent) -> void:
	if Game.data_ok and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_start()


func _start() -> void:
	get_tree().change_scene_to_file(PROLOGUE_SCENE)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
