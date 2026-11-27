extends PanelContainer
## 隊伍面板：每人一列，顯示頭像、名字、氣血、內力。輪到的人會亮起來。
## 放在畫面左上角。
##
## 自由戰鬥另外用兩種變化（setup 的 options）：
## - enemy：敵方的列表。頭像換成敵方的菱形記號，第二條改成架勢，名字欄比較寬（「山賊嘍囉甲」）。
## - modes：每列右邊多一格「手動／進攻／支援」，點那一列可以切換（row_pressed）。

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
const MODE_W := 96.0
## 氣血低於這個比例時，數字改用警示色。
const LOW_HP := 0.35

signal row_pressed(unit_id: String)

var _rows: Dictionary = {}
var _list: VBoxContainer
var _options: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.panel_style(22.0, 15.0))


## members 是 [{ id, name, hp_max, mp_max }]；敵方的列表另外可以有 art（頭像用哪個角色的圖）。
## options：enemy（敵方列表）、name_w（名字欄寬）、bar_w（氣血條寬）、modes（每列多一格模式，可以點）。
func setup(members: Array, options: Dictionary = {}) -> void:
	if _list:
		_list.queue_free()
	_rows.clear()
	_options = options
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


## 第二條的另一個名字：敵方的列表裡那一條是架勢。
func set_posture(unit_id: String, ratio: float, animate: bool = true) -> void:
	set_mp(unit_id, ratio, animate)


## 倒下的人整列變暗。
func set_down(unit_id: String, down: bool) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if not row.is_empty():
		(row["row"] as Control).modulate = Color(1, 1, 1, 0.4) if down else Color.WHITE


## 每列右邊那一格的文字（手動、進攻、支援）。
func set_mode(unit_id: String, text: String, highlight: bool = false) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if row.is_empty() or not row.has("mode"):
		return
	var label: Label = row["mode"]
	label.text = text
	label.add_theme_color_override("font_color", UiKit.HIGHLIGHT if highlight else UiKit.TEXT_DIM)


## 某一列在畫面上的中心點（開發用的模擬點擊會用到）。
func row_center(unit_id: String) -> Vector2:
	var row: Dictionary = _rows.get(unit_id, {})
	return (row["row"] as Control).get_global_rect().get_center() if not row.is_empty() else Vector2.ZERO


func set_active(unit_id: String) -> void:
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var active: bool = id == unit_id
		(row["name"] as Label).add_theme_color_override("font_color", UiKit.HIGHLIGHT if active else UiKit.TEXT)
		(row["back"] as ColorRect).color = Color(UiKit.PINE, 0.55) if active else Color(0, 0, 0, 0)
		(row["frame_style"] as StyleBoxFlat).border_color = UiKit.HIGHLIGHT if active else UiKit.BRONZE


func _build_row(m: Dictionary) -> Dictionary:
	var enemy := bool(_options.get("enemy", false))
	var name_w := float(_options.get("name_w", NAME_W))
	var bar_w := float(_options.get("bar_w", BAR_W))
	var modes := bool(_options.get("modes", false))
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := HEAD_SIZE + 14.0 + name_w + 10.0 + bar_w + 8.0 + NUMBER_W + (MODE_W + 8.0 if modes else 0.0)
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
	var texture := UiKit.head_texture(str(m.get("art", m["id"])))
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
		var dot := Glyph.new("diamond" if enemy else "dot", UiKit.ENEMY if enemy else UiKit.PARTY, 30.0)
		dot.position = Vector2((HEAD_SIZE - 30.0) / 2.0, head_top + (HEAD_SIZE - 30.0) / 2.0)
		row.add_child(dot)

	var x := HEAD_SIZE + 14.0
	var name_label := UiKit.label(str(m["name"]), 36)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.position = Vector2(x, 0)
	name_label.size = Vector2(name_w, ROW_HEIGHT)
	name_label.clip_text = true
	row.add_child(name_label)

	x += name_w + 10.0
	var hp := Bar.new()
	hp.setup_textured(Vector2(bar_w, HP_BAR_H))
	hp.position = Vector2(x, 7)
	row.add_child(hp)
	var mp := Bar.new()
	if enemy:
		# 架勢：還沒有圖，先用練白的平塗條
		mp.setup_flat(Vector2(bar_w - 4.0, MP_BAR_H), Color(UiKit.PAPER, 0.92))
	else:
		mp.setup_textured(Vector2(bar_w - 4.0, MP_BAR_H), UiKit.MP_TRACK_TEXTURE, UiKit.MP_FILL_TEXTURE)
	mp.position = Vector2(x + 2.0, 7.0 + HP_BAR_H + 4.0)
	row.add_child(mp)

	var hp_text := UiKit.label(str(int(m["hp_max"])), 36)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_text.position = Vector2(x + bar_w + 8.0, 0)
	hp_text.size = Vector2(NUMBER_W, ROW_HEIGHT - 12.0)
	row.add_child(hp_text)

	var entry := {
		"row": row, "name": name_label, "back": back, "frame_style": frame_style,
		"hp": hp, "mp": mp, "hp_text": hp_text, "hp_max": int(m["hp_max"]),
	}
	if modes:
		var mode := UiKit.label("", 36, UiKit.TEXT_DIM)
		mode.add_theme_stylebox_override("normal", UiKit.tag_style(UiKit.BRONZE, 0.7))
		mode.position = Vector2(x + bar_w + 8.0 + NUMBER_W + 8.0, (ROW_HEIGHT - 50.0) / 2.0)
		mode.size = Vector2(MODE_W, 50)
		row.add_child(mode)
		entry["mode"] = mode
		# 整列都可以點
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.position = Vector2(-8, -3)
		button.size = Vector2(width + 16.0, ROW_HEIGHT + 6.0)
		button.pressed.connect(func() -> void: row_pressed.emit(str(m["id"])))
		row.add_child(button)
	return entry
