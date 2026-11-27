extends PanelContainer
## 隊伍面板：每人一列，顯示頭像、名字、氣血、內力。輪到的人會亮起來。
## 放在畫面左上角。

const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Bar := preload("res://scenes/ui/bar.gd")
const Glyph := preload("res://scenes/ui/glyph.gd")

const ROW_HEIGHT := 56.0
const ROW_GAP := 4.0
const HEAD_SIZE := 50.0
const NAME_W := 116.0
const BAR_W := 250.0
const HP_BAR_H := 27.0
const MP_BAR_H := 12.0
const NUMBER_W := 104.0
## 氣血低於這個比例時，數字改用警示色。
const LOW_HP := 0.35

var _rows: Dictionary = {}
var _list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.panel_style(22.0, 15.0))


## members 是 [{ id, name, hp_max, mp_max }]。
func setup(members: Array) -> void:
	if _list:
		_list.queue_free()
	_rows.clear()
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", int(ROW_GAP))
	add_child(_list)
	for m: Dictionary in members:
		_rows[m["id"]] = _build_row(m)
	reset_size()


func set_hp(unit_id: String, ratio: float, animate: bool = true) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if row.is_empty():
		return
	ratio = clampf(ratio, 0.0, 1.0)
	var number: Label = row["hp_text"]
	number.text = str(roundi(ratio * int(row["hp_max"])))
	number.add_theme_color_override("font_color", UiKit.ENEMY if ratio <= LOW_HP else UiKit.TEXT)
	(row["hp"] as Bar).set_ratio(ratio, animate)


func set_mp(unit_id: String, ratio: float, animate: bool = true) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if row.is_empty():
		return
	(row["mp"] as Bar).set_ratio(ratio, animate)


func set_active(unit_id: String) -> void:
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var active: bool = id == unit_id
		(row["name"] as Label).add_theme_color_override("font_color", UiKit.HIGHLIGHT if active else UiKit.TEXT)
		(row["back"] as ColorRect).color = Color(UiKit.PINE, 0.55) if active else Color(0, 0, 0, 0)
		(row["frame_style"] as StyleBoxFlat).border_color = UiKit.HIGHLIGHT if active else UiKit.BRONZE


func _build_row(m: Dictionary) -> Dictionary:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := HEAD_SIZE + 14.0 + NAME_W + 10.0 + BAR_W + 8.0 + NUMBER_W
	row.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	_list.add_child(row)

	# 輪到這個人時亮起來的底色
	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = Color(0, 0, 0, 0)
	back.position = Vector2(-8, -3)
	back.size = Vector2(width + 16.0, ROW_HEIGHT + 6.0)
	row.add_child(back)

	# 頭像；還沒有圖的角色用我方的圓點代替
	var head_top := (ROW_HEIGHT - HEAD_SIZE) / 2.0
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2(0, head_top)
	frame.size = Vector2(HEAD_SIZE, HEAD_SIZE)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiKit.TEAL
	frame_style.border_color = UiKit.BRONZE
	frame_style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(frame)
	var texture := UiKit.head_texture(str(m["id"]))
	if texture:
		var head := TextureRect.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.texture = texture
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_SCALE
		head.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		head.position = Vector2(2, head_top + 2.0)
		head.size = Vector2(HEAD_SIZE - 4.0, HEAD_SIZE - 4.0)
		row.add_child(head)
	else:
		var dot := Glyph.new("dot", UiKit.PARTY, 30.0)
		dot.position = Vector2((HEAD_SIZE - 30.0) / 2.0, head_top + (HEAD_SIZE - 30.0) / 2.0)
		row.add_child(dot)

	var x := HEAD_SIZE + 14.0
	var name_label := UiKit.label(str(m["name"]), 36)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.position = Vector2(x, 0)
	name_label.size = Vector2(NAME_W, ROW_HEIGHT)
	row.add_child(name_label)

	x += NAME_W + 10.0
	var hp := Bar.new()
	hp.setup_textured(Vector2(BAR_W, HP_BAR_H))
	hp.position = Vector2(x, 7)
	row.add_child(hp)
	var mp := Bar.new()
	mp.setup_textured(Vector2(BAR_W - 4.0, MP_BAR_H), UiKit.MP_TRACK_TEXTURE, UiKit.MP_FILL_TEXTURE)
	mp.position = Vector2(x + 2.0, 7.0 + HP_BAR_H + 4.0)
	row.add_child(mp)

	var hp_text := UiKit.label(str(int(m["hp_max"])), 36)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_text.position = Vector2(x + BAR_W + 8.0, 0)
	hp_text.size = Vector2(NUMBER_W, ROW_HEIGHT - 12.0)
	row.add_child(hp_text)

	return {
		"name": name_label, "back": back, "frame_style": frame_style,
		"hp": hp, "mp": mp, "hp_text": hp_text, "hp_max": int(m["hp_max"]),
	}
