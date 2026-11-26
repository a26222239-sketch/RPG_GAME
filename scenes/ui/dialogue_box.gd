extends Control
## 對話框。蓋住整個畫面來接點擊：第一下把字全部顯示出來，第二下才往下走。
## 說話的人有頭像時顯示頭像：我方在左，敵方在右並左右翻轉，讓雙方面對面。

signal advanced

const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Glyph := preload("res://scenes/ui/glyph.gd")

const CHARS_PER_SECOND := 45.0
const BOX_HEIGHT := 212.0
const MARGIN := 30.0
const PAD := 16.0
const PORTRAIT := 180.0
const NAME_HEIGHT := 44.0
const COLOR_NARRATION := Color("#C7D6CE")

var _panel: Panel
var _frame: Panel
var _portrait: TextureRect
var _marker: Glyph
var _name_label: Label
var _text_label: Label
var _arrow: Label
var _type_tween: Tween
var _arrow_tween: Tween
var _typing: bool = false
var _side: String = ""
var _has_portrait: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	resized.connect(_layout)


## 顯示一段話。speaker 為空字串時是旁白。
## side 是 "party" 或 "enemy"，決定名字的顏色、記號與頭像放哪一邊；head 是頭像，可以沒有。
func show_line(speaker: String, text: String, side: String = "", head: Texture2D = null) -> void:
	visible = true
	var narration := speaker == ""
	_side = "" if narration else side
	_has_portrait = not narration and head != null
	_frame.visible = _has_portrait
	_portrait.texture = head
	_portrait.flip_h = side == "enemy"
	_marker.visible = not narration
	_name_label.visible = not narration
	if not narration:
		var color := UiKit.ENEMY if side == "enemy" else UiKit.PARTY
		_marker.kind = "diamond" if side == "enemy" else "dot"
		_marker.color = color
		_name_label.text = speaker
		_name_label.add_theme_color_override("font_color", color)
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", COLOR_NARRATION if narration else UiKit.TEXT)
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if narration else HORIZONTAL_ALIGNMENT_LEFT
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if narration else VERTICAL_ALIGNMENT_TOP
	_text_label.visible_ratio = 0.0
	_arrow.visible = false
	_layout()
	_typing = true
	if _type_tween:
		_type_tween.kill()
	var duration := maxf(0.15, float(text.length()) / CHARS_PER_SECOND)
	_type_tween = create_tween()
	_type_tween.tween_property(_text_label, "visible_ratio", 1.0, duration)
	_type_tween.tween_callback(_finish_typing)


func hide_box() -> void:
	visible = false
	if _type_tween:
		_type_tween.kill()
	_typing = false


## 玩家按了一下（也給自動播放呼叫）。
func advance() -> void:
	if not visible:
		return
	if _typing:
		if _type_tween:
			_type_tween.kill()
		_finish_typing()
	else:
		advanced.emit()


func is_typing() -> bool:
	return _typing


func _finish_typing() -> void:
	_typing = false
	_text_label.visible_ratio = 1.0
	_arrow.visible = true


func _gui_input(event: InputEvent) -> void:
	# 觸控會由引擎轉成滑鼠事件（專案設定 emulate_mouse_from_touch），所以只處理滑鼠。
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		advance()


func _build() -> void:
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	add_child(_panel)

	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = Vector2(PORTRAIT, PORTRAIT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiKit.TEAL
	frame_style.border_color = UiKit.BRONZE
	frame_style.set_border_width_all(3)
	_frame.add_theme_stylebox_override("panel", frame_style)
	_panel.add_child(_frame)

	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait.position = Vector2(3, 3)
	_portrait.size = Vector2(PORTRAIT - 6.0, PORTRAIT - 6.0)
	_frame.add_child(_portrait)

	_marker = Glyph.new("dot", UiKit.PARTY, 30.0)
	_panel.add_child(_marker)

	_name_label = UiKit.label("", 40)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_panel.add_child(_name_label)

	_text_label = UiKit.label("", 44)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_text_label.add_theme_constant_override("line_spacing", 6)
	_panel.add_child(_text_label)

	_arrow = UiKit.label("▼", 30, UiKit.HIGHLIGHT)
	_arrow.size = Vector2(44, 40)
	_panel.add_child(_arrow)
	_arrow_tween = create_tween().set_loops()
	_arrow_tween.tween_property(_arrow, "modulate:a", 0.25, 0.5)
	_arrow_tween.tween_property(_arrow, "modulate:a", 1.0, 0.5)
	_layout()


func _layout() -> void:
	if _panel == null:
		return
	var box := Vector2(size.x - MARGIN * 2.0, BOX_HEIGHT)
	_panel.position = Vector2(MARGIN, size.y - MARGIN - BOX_HEIGHT)
	_panel.size = box

	# 文字區：扣掉頭像那一側
	var left := PAD + 22.0
	var right := box.x - PAD - 22.0
	if _has_portrait:
		if _side == "enemy":
			_frame.position = Vector2(box.x - PAD - PORTRAIT, PAD)
			right = _frame.position.x - 28.0
		else:
			_frame.position = Vector2(PAD, PAD)
			left = PAD + PORTRAIT + 28.0

	if _side == "":
		_text_label.position = Vector2(left, PAD)
		_text_label.size = Vector2(right - left, box.y - PAD * 2.0)
	else:
		_marker.position = Vector2(left, PAD + (NAME_HEIGHT - 30.0) / 2.0 - 2.0)
		_name_label.position = Vector2(left + 40.0, PAD - 2.0)
		_name_label.size = Vector2(right - left - 40.0, NAME_HEIGHT)
		_text_label.position = Vector2(left, PAD + NAME_HEIGHT + 2.0)
		_text_label.size = Vector2(right - left, box.y - PAD * 2.0 - NAME_HEIGHT - 2.0)
	_arrow.position = Vector2(right - 40.0, box.y - PAD - 38.0)
