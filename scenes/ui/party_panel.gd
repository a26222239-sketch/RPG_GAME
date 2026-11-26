extends Control
## 隊伍面板：每人一列，顯示名字、氣血、內力。輪到的人會亮起來。

const COLOR_TEXT := Color("#f2ead8")
const COLOR_HIGHLIGHT := Color("#ffd84a")
const COLOR_HP := Color("#5fbf6a")
const COLOR_HP_LOW := Color("#d9a13b")
const COLOR_HP_DANGER := Color("#d04a4a")
const COLOR_MP := Color("#4a8fd0")
const COLOR_BAR_BACK := Color(0, 0, 0, 0.6)
const ROW_SIZE := Vector2(820, 76)
const GAP := 9.0
const NAME_W := 190.0
const HP_W := 330.0
const MP_W := 200.0

var _rows: Dictionary = {}
var _order: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## members 是 [{ id, name, color, hp_max, mp_max }]。
func setup(members: Array) -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_order.clear()
	for i in members.size():
		var m: Dictionary = members[i]
		_order.append(str(m["id"]))
		_rows[m["id"]] = _build_row(m, i)
	custom_minimum_size = panel_size(members.size())
	size = custom_minimum_size


static func panel_size(member_count: int) -> Vector2:
	return Vector2(ROW_SIZE.x, ROW_SIZE.y * member_count + GAP * maxi(0, member_count - 1))


func set_hp(unit_id: String, ratio: float, animate: bool = true) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if row.is_empty():
		return
	var fill: ColorRect = row["hp_fill"]
	ratio = clampf(ratio, 0.0, 1.0)
	fill.color = COLOR_HP if ratio > 0.35 else (COLOR_HP_LOW if ratio > 0.2 else COLOR_HP_DANGER)
	(row["hp_text"] as Label).text = str(roundi(ratio * int(row["hp_max"])))
	_set_bar(fill, HP_W * ratio, animate)


func set_mp(unit_id: String, ratio: float, animate: bool = true) -> void:
	var row: Dictionary = _rows.get(unit_id, {})
	if row.is_empty():
		return
	ratio = clampf(ratio, 0.0, 1.0)
	(row["mp_text"] as Label).text = str(roundi(ratio * int(row["mp_max"])))
	_set_bar(row["mp_fill"], MP_W * ratio, animate)


func set_active(unit_id: String) -> void:
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var active: bool = id == unit_id
		var style := (row["panel"] as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = COLOR_HIGHLIGHT if active else Color("#4a4034")
		style.bg_color = Color(0.2, 0.17, 0.1, 0.95) if active else Color(0.08, 0.07, 0.1, 0.88)
		(row["name"] as Label).add_theme_color_override("font_color", COLOR_HIGHLIGHT if active else COLOR_TEXT)


func _set_bar(fill: ColorRect, width: float, animate: bool) -> void:
	if not animate:
		fill.size.x = width
		return
	var tween := create_tween()
	tween.tween_property(fill, "size:x", width, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_row(m: Dictionary, row_index: int) -> Dictionary:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(0, (ROW_SIZE.y + GAP) * row_index)
	panel.size = ROW_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.88)
	style.border_color = Color("#4a4034")
	style.set_border_width_all(3)
	style.border_width_left = 12
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.color = m["color"]
	swatch.position = Vector2(20, 16)
	swatch.size = Vector2(14, ROW_SIZE.y - 32)
	panel.add_child(swatch)

	var name_label := _label(str(m["name"]), 40, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.position = Vector2(46, 0)
	name_label.size = Vector2(NAME_W, ROW_SIZE.y)
	panel.add_child(name_label)

	var x := 46.0 + NAME_W
	var hp := _bar(panel, Vector2(x, 12), HP_W, 52, COLOR_HP, Game.t("UI_HP"))
	x += HP_W + 28.0
	var mp := _bar(panel, Vector2(x, 12), MP_W, 52, COLOR_MP, Game.t("UI_MP"))

	(hp["text"] as Label).text = str(int(m["hp_max"]))
	(mp["text"] as Label).text = str(int(m["mp_max"]))
	return {
		"panel": panel, "name": name_label,
		"hp_fill": hp["fill"], "hp_text": hp["text"], "hp_max": int(m["hp_max"]),
		"mp_fill": mp["fill"], "mp_text": mp["text"], "mp_max": int(m["mp_max"]),
	}


## 一條有標題與數字的橫條。回傳 { fill, text }。
func _bar(parent: Control, pos: Vector2, width: float, height: float, color: Color, caption: String) -> Dictionary:
	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = COLOR_BAR_BACK
	back.position = pos
	back.size = Vector2(width, height)
	parent.add_child(back)

	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = color
	fill.size = Vector2(width, height)
	back.add_child(fill)

	var caption_label := _label(caption, 36, HORIZONTAL_ALIGNMENT_LEFT)
	caption_label.position = Vector2(10, 0)
	caption_label.size = Vector2(width, height)
	back.add_child(caption_label)

	var text := _label("", 36, HORIZONTAL_ALIGNMENT_RIGHT)
	text.position = Vector2(0, 0)
	text.size = Vector2(width - 10, height)
	back.add_child(text)
	return {"fill": fill, "text": text}


func _label(text: String, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	return label
