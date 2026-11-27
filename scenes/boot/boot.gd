extends Control
## 啟動畫面：遊戲名稱、「開始」（進入序章）與「戰鬥試煉」（M1 的四場測試遭遇）。
##
## 鍵盤：標題畫面 Enter 或 1 是開始、2 是戰鬥試煉；試煉清單 1–4 選一場，Esc 返回。

const UiKit := preload("res://scenes/ui/ui_kit.gd")

const PROLOGUE_SCENE := "res://scenes/battle/scripted_battle_scene.tscn"
const FREE_BATTLE_SCENE := "res://scenes/battle/free_battle_scene.tscn"
const BACKGROUND := "res://assets/backgrounds/battle/tianmo_hall.jpg"
const TRIALS := ["test_a", "test_b", "test_c", "test_d"]

var _title_box: VBoxContainer
var _trials_box: VBoxContainer
var _start_button: Button
var _trials_button: Button
var _trial_buttons: Dictionary = {}


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

	_title_box = _centered_box(44)
	_title_box.add_child(UiKit.label(Game.t("UI_GAME_TITLE"), 96, UiKit.TEXT, 14))
	_title_box.add_child(UiKit.label(Game.t("UI_TITLE_SUB"), 48, UiKit.BRONZE, 10))

	if not Game.data_ok:
		_title_box.add_child(UiKit.label(Game.t("UI_LOAD_ERROR") + "\n" + "\n".join(Game.data.errors), 36, UiKit.DAMAGE, 8))
		return

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	_title_box.add_child(buttons)
	_start_button = _make_button(Game.t("UI_START"), Vector2(360, 128), 52)
	_start_button.pressed.connect(_start)
	buttons.add_child(_start_button)
	_trials_button = _make_button(Game.t("UI_TRIALS"), Vector2(360, 128), 52)
	_trials_button.pressed.connect(_show_trials)
	buttons.add_child(_trials_button)

	_build_trials()
	if Game.open_trials:
		Game.open_trials = false
		_show_trials()

	if Game.autoplay:
		# 場景還在建立中，不能馬上換場景；先等一格
		await get_tree().process_frame
		await Game.take_shot("title")
		if Game.read_scale > 0.0:
			await get_tree().create_timer(1.5 * Game.read_scale).timeout
		if Game.dev_encounter == "":
			_start()
			return
		await _auto_tap(_trials_button, _show_trials)
		while not _trials_box.visible:
			await get_tree().process_frame
		await Game.take_shot("trials")
		if not _trial_buttons.has(Game.dev_encounter):
			printerr("沒有這一場戰鬥試煉：%s" % Game.dev_encounter)
			get_tree().quit(1)
			return
		await _auto_tap(_trial_buttons[Game.dev_encounter], _start_trial.bind(Game.dev_encounter))


func _unhandled_key_input(event: InputEvent) -> void:
	if not Game.data_ok or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if _title_box.visible:
		if event.is_action_pressed("ui_accept") or key == KEY_1:
			get_viewport().set_input_as_handled()
			_start()
		elif key == KEY_2:
			get_viewport().set_input_as_handled()
			_show_trials()
	elif _trials_box.visible:
		var index := key - KEY_1
		if index >= 0 and index < TRIALS.size():
			get_viewport().set_input_as_handled()
			_start_trial(TRIALS[index])
		elif event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_show_title()


func _start() -> void:
	get_tree().change_scene_to_file(PROLOGUE_SCENE)


func _start_trial(encounter: String) -> void:
	Game.pending_encounter = encounter
	get_tree().change_scene_to_file(FREE_BATTLE_SCENE)


func _show_trials() -> void:
	_title_box.visible = false
	_trials_box.visible = true


func _show_title() -> void:
	_trials_box.visible = false
	_title_box.visible = true


## 戰鬥試煉的清單：每一場一個按鈕，寫名字與用途。
func _build_trials() -> void:
	_trials_box = _centered_box(26)
	_trials_box.visible = false
	_trials_box.add_child(UiKit.label(Game.t("UI_TRIALS"), 72, UiKit.TEXT, 12))
	_trials_box.add_child(UiKit.label(Game.t("UI_TRIALS_SUB"), 36, UiKit.BRONZE, 8))
	for i in TRIALS.size():
		var encounter: String = TRIALS[i]
		var info: Dictionary = Game.data.encounters[encounter]
		# 兩行：上面是名字，下面是這一場要練什麼
		var button := _make_button("%d　%s" % [i + 1, Game.t(str(info["name"]))], Vector2(1200, 140), 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for style: StyleBoxTexture in [button.get_meta("style_normal"), button.get_meta("style_active"),
				button.get_theme_stylebox("pressed"), button.get_theme_stylebox("disabled")]:
			style.content_margin_left = 40
			style.content_margin_top = 10
			style.content_margin_bottom = 70
		var note := UiKit.label(Game.t(str(info["note"])), 36, UiKit.JADE)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		note.position = Vector2(40, 72)
		note.size = Vector2(1120, 52)
		button.add_child(note)
		button.pressed.connect(_start_trial.bind(encounter))
		_trials_box.add_child(button)
		_trial_buttons[encounter] = button
	var back := _make_button(Game.t("UI_BACK"), Vector2(260, 104), 40)
	back.pressed.connect(_show_title)
	_trials_box.add_child(back)


func _centered_box(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	add_child(box)
	return box


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	UiKit.style_button(button, font_size)
	button.text = text
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


## 開發用：依啟動參數決定怎麼按（直接呼叫或模擬滑鼠點擊；模擬按鍵時用數字鍵）。
func _auto_tap(button: Button, direct: Callable) -> void:
	await get_tree().create_timer(0.2 + 1.0 * Game.read_scale).timeout
	match Game.input_mode:
		"clicks":
			await Game.click_at(button.get_global_rect().get_center())
		"keys":
			if button == _trials_button:
				await Game.press_key(KEY_2)
			else:
				await Game.press_key((KEY_1 + TRIALS.find(Game.dev_encounter)) as Key)
		_:
			# 換場景之後這個節點就不在場景樹上了，不能再用 get_tree()
			direct.call()
