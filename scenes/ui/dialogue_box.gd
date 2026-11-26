extends Control
## 對話框。蓋住整個畫面來接點擊：第一下把字全部顯示出來，第二下才往下走。

signal advanced

const COLOR_TEXT := Color("#f2ead8")
const COLOR_NARRATION := Color("#c9bfa8")
const COLOR_PANEL := Color(0.06, 0.05, 0.08, 1.0)
const COLOR_BORDER := Color("#6b5a40")
const CHARS_PER_SECOND := 45.0
const BOX_HEIGHT := 340.0
const MARGIN := 32.0

var _panel: Panel
var _name_plate: Panel
var _name_label: Label
var _text_label: Label
var _arrow: Label
var _type_tween: Tween
var _arrow_tween: Tween
var _typing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


## 顯示一段話。speaker 為空字串時是旁白。
func show_line(speaker: String, speaker_color: Color, text: String) -> void:
	visible = true
	var narration := speaker == ""
	_name_plate.visible = not narration
	_name_label.text = speaker
	if not narration:
		var style := _name_plate.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = speaker_color.darkened(0.35)
		style.border_color = speaker_color.lightened(0.2)
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", COLOR_NARRATION if narration else COLOR_TEXT)
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if narration else HORIZONTAL_ALIGNMENT_LEFT
	_text_label.visible_ratio = 0.0
	_arrow.visible = false
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
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = -(BOX_HEIGHT + MARGIN)
	_panel.offset_bottom = -MARGIN
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_name_plate = Panel.new()
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.position = Vector2(36, -34)
	_name_plate.size = Vector2(300, 68)
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color("#333333")
	plate_style.border_color = Color("#888888")
	plate_style.set_border_width_all(4)
	plate_style.set_corner_radius_all(10)
	_name_plate.add_theme_stylebox_override("panel", plate_style)
	_panel.add_child(_name_plate)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 42)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_name_plate.add_child(_name_label)

	_text_label = Label.new()
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.anchor_right = 1.0
	_text_label.anchor_bottom = 1.0
	_text_label.offset_left = 56
	_text_label.offset_right = -56
	_text_label.offset_top = 52
	_text_label.offset_bottom = -40
	_text_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.add_theme_font_size_override("font_size", 48)
	_text_label.add_theme_constant_override("line_spacing", 14)
	_panel.add_child(_text_label)

	_arrow = Label.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.text = "▼"
	_arrow.anchor_left = 1.0
	_arrow.anchor_right = 1.0
	_arrow.anchor_top = 1.0
	_arrow.anchor_bottom = 1.0
	_arrow.offset_left = -90
	_arrow.offset_right = -30
	_arrow.offset_top = -70
	_arrow.offset_bottom = -14
	_arrow.add_theme_font_size_override("font_size", 36)
	_arrow.add_theme_color_override("font_color", Color("#ffd84a"))
	_panel.add_child(_arrow)
	_arrow_tween = create_tween().set_loops()
	_arrow_tween.tween_property(_arrow, "modulate:a", 0.25, 0.5)
	_arrow_tween.tween_property(_arrow, "modulate:a", 1.0, 0.5)
