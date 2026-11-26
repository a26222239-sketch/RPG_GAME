extends Control
## 戰鬥角色的佔位版本：色塊加名字。
##
## 對外介面是設計文件 12.4 的動畫契約：play_anim(動畫名)。
## 節點底下如果有 AnimationPlayer 而且有同名動畫，就播那個動畫（正式美術用）；
## 沒有的話，用位移、縮放、閃爍做出佔位的動作。
## 這個節點的原點是角色的腳底中央。

signal clicked(actor_id: String)

const BAR_W := 180.0
const COLOR_TEXT := Color("#f2ead8")
const COLOR_HP_PARTY := Color("#5fbf6a")
const COLOR_HP_ENEMY := Color("#d04a4a")
const COLOR_GAUGE := Color("#e0c060")
const COLOR_BAR_BACK := Color(0, 0, 0, 0.65)
const COLOR_HIGHLIGHT := Color("#ffd84a")

## 各動畫的大致長度（秒）與出手點（比例）。
const ANIM_INFO := {
	"idle": {"length": 1.2, "impact": 0.0},
	"ready": {"length": 0.4, "impact": 0.0},
	"charge": {"length": 1.0, "impact": 0.0},
	"attack_light": {"length": 0.45, "impact": 0.5},
	"attack_heavy": {"length": 0.8, "impact": 0.6},
	"cast": {"length": 0.7, "impact": 0.6},
	"hit": {"length": 0.3, "impact": 0.0},
	"guard": {"length": 0.3, "impact": 0.0},
	"stagger": {"length": 0.5, "impact": 0.0},
	"down": {"length": 0.7, "impact": 0.0},
	"victory": {"length": 1.0, "impact": 0.0},
	"walk": {"length": 0.8, "impact": 0.0},
}

var actor_id: String = ""
var is_enemy: bool = false
var home: Vector2 = Vector2.ZERO
var body_size: Vector2 = Vector2(120, 250)

var _color: Color = Color.WHITE
var _visual: Control
var _body: Panel
var _head: Panel
var _weapon: ColorRect
var _name_label: Label
var _hp_fill: ColorRect
var _gauge_back: ColorRect
var _gauge_fill: ColorRect
var _charge_box: Control
var _charge_label: Label
var _charge_fill: ColorRect
var _state_label: Label
var _target_marker: Label
var _target_button: Button
var _outline: Panel
var _loop_tween: Tween
var _anim_tween: Tween
var _move_tween: Tween
var _marker_tween: Tween
var _current_loop: String = ""


func setup(id: String, display_name: String, color: Color, enemy: bool, size_scale: float = 1.0) -> void:
	actor_id = id
	is_enemy = enemy
	_color = color
	body_size = Vector2(120, 250) * size_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build(display_name)
	play_anim("idle")


## 面向：我方朝右是 1，敵方朝左是 -1。
func facing() -> float:
	return -1.0 if is_enemy else 1.0


func head_position() -> Vector2:
	return global_position + Vector2(0, -body_size.y - 70)


func chest_position() -> Vector2:
	return global_position + Vector2(0, -body_size.y * 0.55)


func set_hp(ratio: float, animate: bool = true) -> void:
	_tween_bar(_hp_fill, ratio, animate)
	var base := COLOR_HP_ENEMY if is_enemy else COLOR_HP_PARTY
	if not is_enemy and ratio <= 0.35:
		base = Color("#d9a13b") if ratio > 0.2 else COLOR_HP_ENEMY
	_hp_fill.color = base


func set_gauge(ratio: float, duration: float = 0.0) -> Tween:
	var target_w := BAR_W * clampf(ratio, 0.0, 1.0)
	if duration <= 0.0:
		_gauge_fill.size.x = target_w
		return null
	var tween := create_tween()
	tween.tween_property(_gauge_fill, "size:x", target_w, duration)
	return tween


func set_gauge_visible(on: bool) -> void:
	_gauge_back.visible = on


## 顯示蓄招：頭上出現招式名與一條會跑的倒數條。duration 為 0 時只顯示不跑。
func show_charge(text: String, duration: float = 0.0, hold_ratio: float = 1.0) -> Tween:
	_charge_label.text = text
	_charge_fill.size.x = 0.0
	_charge_box.visible = true
	play_anim("charge")
	if duration <= 0.0:
		return null
	var tween := create_tween()
	tween.tween_property(_charge_fill, "size:x", (BAR_W + 60.0) * hold_ratio, duration)
	return tween


func finish_charge(duration: float) -> Tween:
	var tween := create_tween()
	tween.tween_property(_charge_fill, "size:x", BAR_W + 60.0, duration)
	return tween


func hide_charge() -> void:
	_charge_box.visible = false


func set_state_tag(text: String) -> void:
	_state_label.text = text
	_state_label.visible = text != ""


func set_targetable(on: bool) -> void:
	_target_button.visible = on
	_target_marker.visible = on
	_outline.visible = on
	if _marker_tween:
		_marker_tween.kill()
		_marker_tween = null
	if on:
		_marker_tween = create_tween().set_loops()
		_marker_tween.tween_property(_target_marker, "position:y", _target_marker.position.y - 14.0, 0.4)
		_marker_tween.tween_property(_target_marker, "position:y", _target_marker.position.y, 0.4)


func is_targetable() -> bool:
	return _target_button.visible


## 目前正在循環播放的動畫名稱；沒有的話是空字串。
func current_loop() -> String:
	return _current_loop


func set_dimmed(on: bool) -> void:
	modulate = Color(0.55, 0.55, 0.6, 1.0) if on else Color.WHITE


func set_speaking(on: bool) -> void:
	_name_label.add_theme_color_override("font_color", COLOR_HIGHLIGHT if on else COLOR_TEXT)


func move_to(target: Vector2, duration: float) -> Tween:
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return _move_tween


func go_home(duration: float = 0.25) -> Tween:
	return move_to(home, duration)


func anim_length(anim: String) -> float:
	return float(ANIM_INFO.get(anim, {"length": 0.4})["length"])


## 從動畫開始到「打到」的時間。
func anim_impact_time(anim: String) -> float:
	var info: Dictionary = ANIM_INFO.get(anim, {"length": 0.4, "impact": 0.5})
	return float(info["length"]) * float(info["impact"])


## 播放動畫。回傳動畫長度（秒）。
func play_anim(anim: String) -> float:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(anim):
		player.play(anim)
		return player.get_animation(anim).length

	_stop_tweens()
	_reset_visual()
	_current_loop = ""
	var d := facing()
	match anim:
		"idle":
			_current_loop = anim
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.02), 0.6).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
		"ready":
			_current_loop = anim
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "position:y", -10.0, 0.2)
			_loop_tween.tween_property(_visual, "position:y", 0.0, 0.2)
		"charge":
			_current_loop = anim
			_visual.scale = Vector2(1.04, 0.96)
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "modulate", Color(1.6, 1.6, 1.3), 0.35)
			_loop_tween.tween_property(_visual, "modulate", Color.WHITE, 0.35)
		"attack_light":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", 50.0 * d, 0.2).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.25)
			_anim_tween.parallel().tween_property(_weapon, "rotation", 0.0, 0.25).from(-1.2 * d)
			_anim_tween.tween_callback(_back_to_idle)
		"attack_heavy":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -40.0 * d, 0.3).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "scale", Vector2(1.08, 0.94), 0.3)
			_anim_tween.tween_property(_visual, "position:x", 90.0 * d, 0.15).set_ease(Tween.EASE_IN)
			_anim_tween.parallel().tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.15)
			_anim_tween.parallel().tween_property(_weapon, "rotation", 0.0, 0.3).from(-1.8 * d)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.3)
			_anim_tween.tween_callback(_back_to_idle)
		"cast":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "scale", Vector2(1.1, 1.1), 0.4).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color(1.5, 1.7, 1.5), 0.4)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.3)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.3)
			_anim_tween.tween_callback(_back_to_idle)
		"hit":
			_visual.modulate = Color(2.2, 1.2, 1.2)
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -28.0 * d, 0.08)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.2)
			_anim_tween.tween_callback(_back_to_idle)
		"guard":
			_current_loop = anim
			_visual.modulate = Color(0.75, 0.85, 1.15)
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "scale", Vector2(1.06, 0.9), 0.2)
		"stagger":
			_current_loop = anim
			_visual.modulate = Color(1.1, 0.8, 0.8)
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "rotation", 0.16 * d, 0.5).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "rotation", 0.08 * d, 0.5).set_trans(Tween.TRANS_SINE)
		"down":
			_current_loop = anim
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "scale", Vector2(1.1, 0.6), 0.5).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color(0.6, 0.6, 0.6), 0.5)
		"victory":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:y", -50.0, 0.25).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
			_anim_tween.tween_callback(_back_to_idle)
		"walk":
			_current_loop = anim
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "position:y", -8.0, 0.2)
			_loop_tween.tween_property(_visual, "position:y", 0.0, 0.2)
		_:
			push_warning("%s 沒有動畫 %s" % [actor_id, anim])
	return anim_length(anim)


func _back_to_idle() -> void:
	play_anim("idle")


func _stop_tweens() -> void:
	for tween: Tween in [_loop_tween, _anim_tween]:
		if tween:
			tween.kill()
	_loop_tween = null
	_anim_tween = null


func _reset_visual() -> void:
	_visual.position = Vector2.ZERO
	_visual.scale = Vector2.ONE
	_visual.rotation = 0.0
	_visual.modulate = Color.WHITE
	_weapon.rotation = 0.0


func _tween_bar(fill: ColorRect, ratio: float, animate: bool) -> void:
	var target_w := BAR_W * clampf(ratio, 0.0, 1.0)
	if not animate:
		fill.size.x = target_w
		return
	var tween := create_tween()
	tween.tween_property(fill, "size:x", target_w, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build(display_name: String) -> void:
	var w := body_size.x
	var h := body_size.y
	var head_d := w * 0.62

	_visual = Control.new()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)

	# 選取時的外框
	_outline = Panel.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.position = Vector2(-w / 2.0 - 14, -h - head_d - 14)
	_outline.size = Vector2(w + 28, h + head_d + 28)
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color(1, 0.85, 0.3, 0.08)
	outline_style.border_color = COLOR_HIGHLIGHT
	outline_style.set_border_width_all(5)
	outline_style.set_corner_radius_all(18)
	_outline.add_theme_stylebox_override("panel", outline_style)
	_outline.visible = false
	_visual.add_child(_outline)

	# 兵器：一根指向前方的長條，讓人看得出面向
	_weapon = ColorRect.new()
	_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon.color = _color.lightened(0.45)
	_weapon.size = Vector2(w * 0.95, 10)
	_weapon.pivot_offset = Vector2(0, 5)
	_weapon.position = Vector2(0, -h * 0.62)
	if is_enemy:
		_weapon.scale.x = -1.0
	_visual.add_child(_weapon)

	_body = Panel.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.position = Vector2(-w / 2.0, -h)
	_body.size = Vector2(w, h)
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = _color
	body_style.set_corner_radius_all(int(w * 0.22))
	body_style.border_color = _color.darkened(0.35)
	body_style.set_border_width_all(4)
	_body.add_theme_stylebox_override("panel", body_style)
	_visual.add_child(_body)

	_head = Panel.new()
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.position = Vector2(-head_d / 2.0, -h - head_d + 8)
	_head.size = Vector2(head_d, head_d)
	var head_style := StyleBoxFlat.new()
	head_style.bg_color = _color.lightened(0.25)
	head_style.set_corner_radius_all(int(head_d / 2.0))
	head_style.border_color = _color.darkened(0.35)
	head_style.set_border_width_all(4)
	_head.add_theme_stylebox_override("panel", head_style)
	_visual.add_child(_head)

	var top := -h - head_d - 8.0

	_name_label = _make_label(display_name, 36)
	_name_label.position = Vector2(-150, 8)
	_name_label.size = Vector2(300, 44)
	add_child(_name_label)

	# 氣血條
	var hp_back := ColorRect.new()
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_back.color = COLOR_BAR_BACK
	hp_back.position = Vector2(-BAR_W / 2.0 - 3, top - 28)
	hp_back.size = Vector2(BAR_W + 6, 22)
	add_child(hp_back)
	_hp_fill = ColorRect.new()
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.color = COLOR_HP_ENEMY if is_enemy else COLOR_HP_PARTY
	_hp_fill.position = Vector2(3, 3)
	_hp_fill.size = Vector2(BAR_W, 16)
	hp_back.add_child(_hp_fill)

	# 行動條
	_gauge_back = ColorRect.new()
	_gauge_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_back.color = COLOR_BAR_BACK
	_gauge_back.position = Vector2(-BAR_W / 2.0 - 3, top - 4)
	_gauge_back.size = Vector2(BAR_W + 6, 12)
	add_child(_gauge_back)
	_gauge_fill = ColorRect.new()
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_fill.color = COLOR_GAUGE
	_gauge_fill.position = Vector2(3, 3)
	_gauge_fill.size = Vector2(0, 6)
	_gauge_back.add_child(_gauge_fill)

	# 狀態標籤
	_state_label = _make_label("", 36)
	_state_label.add_theme_color_override("font_color", COLOR_HIGHLIGHT)
	_state_label.position = Vector2(-150, top - 74)
	_state_label.size = Vector2(300, 40)
	_state_label.visible = false
	add_child(_state_label)

	# 蓄招顯示
	_charge_box = Control.new()
	_charge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var charge_w := BAR_W + 60.0
	var side_x := (w / 2.0 + 30.0) if not is_enemy else (-w / 2.0 - 30.0 - charge_w)
	_charge_box.position = Vector2(side_x, -h * 0.8)
	_charge_box.visible = false
	add_child(_charge_box)
	var charge_back := ColorRect.new()
	charge_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_back.color = Color(0.1, 0.05, 0.05, 0.85)
	charge_back.size = Vector2(BAR_W + 60.0, 64)
	_charge_box.add_child(charge_back)
	_charge_fill = ColorRect.new()
	_charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_fill.color = Color("#d9603b")
	_charge_fill.position = Vector2(0, 54)
	_charge_fill.size = Vector2(0, 10)
	_charge_box.add_child(_charge_fill)
	_charge_label = _make_label("", 36)
	_charge_label.size = Vector2(BAR_W + 60.0, 52)
	_charge_box.add_child(_charge_label)

	# 選目標用的箭頭與透明按鈕
	_target_marker = _make_label("▼", 56)
	_target_marker.add_theme_color_override("font_color", COLOR_HIGHLIGHT)
	_target_marker.position = Vector2(-60, top - 130)
	_target_marker.size = Vector2(120, 70)
	_target_marker.visible = false
	add_child(_target_marker)

	_target_button = Button.new()
	_target_button.flat = true
	_target_button.focus_mode = Control.FOCUS_NONE
	_target_button.position = Vector2(-w / 2.0 - 40, top - 40)
	_target_button.size = Vector2(w + 80, h + head_d + 110)
	_target_button.visible = false
	_target_button.pressed.connect(_on_target_pressed)
	add_child(_target_button)


func _on_target_pressed() -> void:
	clicked.emit(actor_id)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label
