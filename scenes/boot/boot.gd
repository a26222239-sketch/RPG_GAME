extends Control
## 啟動畫面：遊戲名稱與「開始」。目前開始之後直接進入序章。

const UiKit := preload("res://scenes/ui/ui_kit.gd")

const PROLOGUE_SCENE := "res://scenes/battle/scripted_battle_scene.tscn"
const BACKGROUND := "res://assets/backgrounds/battle/tianmo_hall.jpg"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var base := ColorRect.new()
	base.color = Color("#0b1215")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# 還沒有標題畫面的圖，先借天魔殿的背景，壓暗當底
	if ResourceLoader.exists(BACKGROUND):
		var image := TextureRect.new()
		image.texture = load(BACKGROUND)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		image.modulate = Color(0.42, 0.46, 0.5)
		add_child(image)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 44)
	add_child(box)

	box.add_child(UiKit.label(Game.t("UI_GAME_TITLE"), 96, UiKit.TEXT, 14))
	box.add_child(UiKit.label(Game.t("UI_TITLE_SUB"), 48, UiKit.BRONZE, 10))

	if not Game.data_ok:
		box.add_child(UiKit.label(Game.t("UI_LOAD_ERROR") + "\n" + "\n".join(Game.data.errors), 36, UiKit.DAMAGE, 8))
		return

	var start := Button.new()
	UiKit.style_button(start, 52)
	start.text = Game.t("UI_START")
	start.custom_minimum_size = Vector2(360, 128)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_start)
	box.add_child(start)

	if Game.autoplay:
		# 場景還在建立中，不能馬上換場景；先等一格
		await get_tree().process_frame
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
