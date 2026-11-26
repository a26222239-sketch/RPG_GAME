extends Control
## 戰鬥中的一個角色。這個節點的原點是角色的腳底中央。
##
## 對外介面是設計文件 12.4 的動畫契約：play_anim(動畫名)。
## 節點底下如果有 AnimationPlayer 而且有同名動畫，就播那個動畫（正式的逐格動畫用）；
## 沒有的話，拿站姿圖用位移、傾斜、明暗做出暫用的動作。
##
## 站姿圖放在 assets/characters/{識別碼}/frames/stand.png，由 tools/prepare_art.py 從設定圖產生，
## 擺法照設計文件 15.6 的逐格圖規格：一般角色的格子是 512×512、首領 768×768，
## 腳底在離格子底邊 32 像素的線上、水平置中。圖的實際解析度可以比格子大。
## 還沒有圖的角色，畫成寫著名字的色塊。

signal clicked(actor_id: String)

const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Bar := preload("res://scenes/ui/bar.gd")

const FRAME_NORMAL := 512.0
const FRAME_BOSS := 768.0
const FEET_MARGIN := 32.0
const GAUGE_SIZE := Vector2(132, 10)
const CHARGE_W := 250.0

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

static var _shadow_texture: GradientTexture2D

var actor_id: String = ""
var is_enemy: bool = false
var home: Vector2 = Vector2.ZERO
## 身體的寬與高（不含兵器、披肩），用來決定頭頂介面的位置與近身時要站多近。
var body_size: Vector2 = Vector2(120, 400)

## 頭上的東西（行動條、狀態、蓄招、箭頭）放在這個節點裡。
## 戰鬥畫面會把它移到所有角色的上一層，才不會被站在前面的人擋住。
var overlay: Control

var _color: Color = Color.WHITE
var _flipped: bool = false
var _visual: Control
var _sprite: Sprite2D
var _shadow: Sprite2D
var _ring: Panel
var _gauge: Bar
var _charge_box: PanelContainer
var _charge_label: Label
var _charge_bar: Bar
var _state_label: Label
var _marker: Label
var _target_button: Button
var _loop_tween: Tween
var _anim_tween: Tween
var _move_tween: Tween
var _marker_tween: Tween
var _dim_tween: Tween
var _current_loop: String = ""
var _targetable: bool = false
var _active: bool = false


func setup(id: String, display_name: String, color: Color, enemy: bool, boss: bool = false) -> void:
	actor_id = id
	is_enemy = enemy
	_color = color
	var frame := FRAME_BOSS if boss else FRAME_NORMAL
	body_size = Vector2(frame * 0.24, frame * 0.78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build(display_name, frame)
	play_anim("idle")


## 面向：朝右是 1，朝左是 -1。我方預設朝右，敵方預設朝左。
func facing() -> float:
	return -1.0 if is_enemy != _flipped else 1.0


## 轉身面向另一邊（繞到對手背後時用）。
func set_flipped(on: bool) -> void:
	_flipped = on
	if _sprite:
		_sprite.flip_h = is_enemy != _flipped


## 把頭上的介面移到指定的節點底下，之後跟著角色移動。
func attach_overlay(parent: Node) -> void:
	overlay.reparent(parent, false)
	overlay.position = position
	item_rect_changed.connect(func() -> void: overlay.position = position)


## 胸口在畫面上的位置（模擬點擊、特效用）。
func chest_global() -> Vector2:
	return get_global_transform() * Vector2(0, -body_size.y * 0.55)


## 胸口在父節點座標裡的位置。
func chest_position() -> Vector2:
	return position + Vector2(0, -body_size.y * 0.55)


func set_gauge(ratio: float, duration: float = 0.0) -> Tween:
	_gauge.visible = ratio > 0.0
	_layout_overhead()
	return _gauge.set_ratio(ratio, duration > 0.0, duration, true)


## 顯示蓄招：身旁出現招式名與一條會跑的倒數條。duration 為 0 時只顯示不跑。
func show_charge(text: String, duration: float = 0.0, hold_ratio: float = 1.0) -> Tween:
	_charge_label.text = text
	_charge_bar.set_ratio(0.0, false)
	_charge_box.visible = true
	_charge_box.reset_size()
	_layout_overhead()
	play_anim("charge")
	if duration <= 0.0:
		return null
	return _charge_bar.set_ratio(hold_ratio, true, duration, true)


func finish_charge(duration: float) -> Tween:
	return _charge_bar.set_ratio(1.0, true, duration, true)


func hide_charge() -> void:
	_charge_box.visible = false
	_layout_overhead()


func set_state_tag(text: String) -> void:
	_state_label.text = text
	_state_label.visible = text != ""
	_state_label.reset_size()
	_layout_overhead()


## 輪到這個人行動時，頭上出現標記。
func set_active(on: bool) -> void:
	_active = on
	_refresh_marker()


func set_targetable(on: bool) -> void:
	_targetable = on
	_target_button.visible = on
	_ring.visible = on
	_refresh_marker()


func is_targetable() -> bool:
	return _targetable


## 目前正在循環播放的動畫名稱；沒有的話是空字串。
func current_loop() -> String:
	return _current_loop


## 對話時，沒在說話的人稍微暗下來。
func set_dimmed(on: bool) -> void:
	if _dim_tween:
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate", Color(0.62, 0.64, 0.7) if on else Color.WHITE, 0.18)


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
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.012), 1.1).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 1.1).set_trans(Tween.TRANS_SINE)
		"ready":
			_current_loop = anim
			_visual.rotation = 0.02 * d
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "modulate", Color(1.16, 1.16, 1.1), 0.4).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE)
		"charge":
			_current_loop = anim
			_visual.scale = Vector2(1.02, 0.98)
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "modulate", Color(1.4, 1.38, 1.22), 0.35)
			_loop_tween.tween_property(_visual, "modulate", Color.WHITE, 0.35)
		"attack_light":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", 64.0 * d, 0.2).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.06 * d, 0.2)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.25)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.25)
			_anim_tween.tween_callback(_back_to_idle)
		"attack_heavy":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -38.0 * d, 0.32).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "rotation", -0.07 * d, 0.32)
			_anim_tween.parallel().tween_property(_visual, "scale", Vector2(1.03, 0.97), 0.32)
			_anim_tween.tween_property(_visual, "position:x", 104.0 * d, 0.14).set_ease(Tween.EASE_IN)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.1 * d, 0.14)
			_anim_tween.parallel().tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.14)
			_anim_tween.tween_interval(0.08)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.26)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.26)
			_anim_tween.tween_callback(_back_to_idle)
		"cast":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "scale", Vector2(1.03, 1.04), 0.4).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color(1.3, 1.45, 1.3), 0.4)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.3)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.3)
			_anim_tween.tween_callback(_back_to_idle)
		"hit":
			_visual.modulate = Color(2.0, 1.3, 1.25)
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -26.0 * d, 0.08)
			_anim_tween.parallel().tween_property(_visual, "rotation", -0.05 * d, 0.08)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.2)
			_anim_tween.tween_callback(_back_to_idle)
		"guard":
			_current_loop = anim
			_anim_tween = create_tween().set_parallel()
			_anim_tween.tween_property(_visual, "modulate", Color(0.78, 0.9, 1.18), 0.2)
			_anim_tween.tween_property(_visual, "rotation", -0.04 * d, 0.2)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.02, 0.97), 0.2)
		"stagger":
			_current_loop = anim
			_visual.modulate = Color(1.08, 0.86, 0.86)
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "rotation", -0.075 * d, 0.5).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "rotation", -0.03 * d, 0.5).set_trans(Tween.TRANS_SINE)
		"down":
			_current_loop = anim
			_anim_tween = create_tween().set_parallel()
			_anim_tween.tween_property(_visual, "rotation", 0.11 * d, 0.5).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.0, 0.93), 0.5).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "modulate", Color(0.62, 0.6, 0.66), 0.5)
		"victory":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:y", -40.0, 0.25).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
			_anim_tween.tween_callback(_back_to_idle)
		"walk":
			_current_loop = anim
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "position:y", -7.0, 0.2)
			_loop_tween.parallel().tween_property(_visual, "rotation", 0.02 * d, 0.2)
			_loop_tween.tween_property(_visual, "position:y", 0.0, 0.2)
			_loop_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.2)
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


func _refresh_marker() -> void:
	_marker.add_theme_color_override("font_color", UiKit.HIGHLIGHT if _targetable else UiKit.PARTY)
	_layout_overhead()


## 把頭上看得見的東西由下往上疊好：行動條、狀態、蓄招、箭頭。
## 敵方的蓄招框改放在身旁靠戰場中央的一側，不佔頭頂（頭頂上方是提示與敵方氣血）。
func _layout_overhead() -> void:
	if _marker_tween:
		_marker_tween.kill()
		_marker_tween = null
	var charging := _charge_box.visible
	var y := -body_size.y - 14.0
	if _gauge.visible and not charging:
		y -= GAUGE_SIZE.y
		_gauge.position = Vector2(-GAUGE_SIZE.x / 2.0, y)
		y -= 8.0
	_gauge.modulate.a = 0.0 if charging else 1.0
	if _state_label.visible:
		y -= _state_label.size.y
		_state_label.position = Vector2(-_state_label.size.x / 2.0, y)
		y -= 8.0
	if charging:
		if is_enemy:
			var half := body_size.x / 2.0 + 44.0
			_charge_box.position = Vector2(-half - _charge_box.size.x, -body_size.y * 0.66)
		else:
			y -= _charge_box.size.y
			_charge_box.position = Vector2(-_charge_box.size.x / 2.0, y)
			y -= 8.0
	_marker.visible = (_targetable or _active) and not (charging and not is_enemy)
	if _marker.visible:
		var base_y := y - _marker.size.y + 8.0
		_marker.position = Vector2(-_marker.size.x / 2.0, base_y)
		_marker_tween = create_tween().set_loops()
		_marker_tween.tween_property(_marker, "position:y", base_y - 8.0, 0.4).set_trans(Tween.TRANS_SINE)
		_marker_tween.tween_property(_marker, "position:y", base_y, 0.4).set_trans(Tween.TRANS_SINE)


func _on_target_pressed() -> void:
	clicked.emit(actor_id)


# ---------------------------------------------------------------- 建立

func _build(display_name: String, frame: float) -> void:
	var w := body_size.x
	var h := body_size.y

	# 地上的影子：留在原地，不跟著身體傾斜
	_shadow = Sprite2D.new()
	_shadow.texture = _get_shadow_texture()
	_shadow.scale = Vector2(w * 1.7, w * 0.36) / 64.0
	_shadow.position = Vector2(0, 2)
	add_child(_shadow)

	# 可以選為目標時，腳下亮起一圈
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(w * 1.8, w * 0.38)
	_ring.position = Vector2(-_ring.size.x / 2.0, -_ring.size.y / 2.0 + 2.0)
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(UiKit.HIGHLIGHT, 0.16)
	ring_style.border_color = UiKit.HIGHLIGHT
	ring_style.set_border_width_all(4)
	ring_style.set_corner_radius_all(int(_ring.size.y / 2.0))
	ring_style.corner_detail = 16
	_ring.add_theme_stylebox_override("panel", ring_style)
	_ring.visible = false
	add_child(_ring)

	_visual = Control.new()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)

	var path := "res://assets/characters/%s/frames/stand.png" % actor_id
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		_sprite = Sprite2D.new()
		_sprite.texture = texture
		_sprite.centered = false
		_sprite.flip_h = is_enemy != _flipped
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sprite.scale = Vector2.ONE * (frame / float(texture.get_height()))
		_sprite.position = Vector2(-frame / 2.0, -(frame - FEET_MARGIN))
		_visual.add_child(_sprite)
	else:
		_build_blocks(display_name)

	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# 行動條：只有在跑的時候才出現
	_gauge = Bar.new()
	_gauge.setup_flat(GAUGE_SIZE, UiKit.GAUGE)
	_gauge.set_ratio(0.0, false)
	_gauge.visible = false
	overlay.add_child(_gauge)

	_state_label = UiKit.label("", 36, UiKit.HIGHLIGHT)
	_state_label.add_theme_stylebox_override("normal", UiKit.tag_style(UiKit.HIGHLIGHT, 0.88))
	_state_label.visible = false
	overlay.add_child(_state_label)

	# 蓄招顯示
	_charge_box = PanelContainer.new()
	_charge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_box.add_theme_stylebox_override("panel", UiKit.tag_style(UiKit.FORCE_COLOR["gang"], 0.92))
	_charge_box.visible = false
	overlay.add_child(_charge_box)
	var charge_rows := VBoxContainer.new()
	charge_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_rows.add_theme_constant_override("separation", 6)
	_charge_box.add_child(charge_rows)
	_charge_label = UiKit.label("", 36)
	_charge_label.custom_minimum_size = Vector2(CHARGE_W, 0)
	charge_rows.add_child(_charge_label)
	_charge_bar = Bar.new()
	_charge_bar.setup_flat(Vector2(CHARGE_W, 10), UiKit.FORCE_COLOR["gang"])
	charge_rows.add_child(_charge_bar)

	# 頭上的箭頭：輪到自己，或可以被選為目標
	_marker = UiKit.label("▼", 40, UiKit.PARTY, 8)
	_marker.size = Vector2(120, 50)
	_marker.visible = false
	overlay.add_child(_marker)

	_target_button = Button.new()
	_target_button.flat = true
	_target_button.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_target_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_target_button.position = Vector2(-w * 1.1, -h - 60.0)
	_target_button.size = Vector2(w * 2.2, h + 100.0)
	_target_button.visible = false
	_target_button.pressed.connect(_on_target_pressed)
	add_child(_target_button)


## 沒有圖的角色：色塊加名字。
func _build_blocks(display_name: String) -> void:
	var w := body_size.x
	var h := body_size.y
	var head_d := w * 0.62
	var body := Panel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(-w / 2.0, -h + head_d)
	body.size = Vector2(w, h - head_d)
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = _color
	body_style.set_corner_radius_all(int(w * 0.22))
	body_style.border_color = _color.darkened(0.35)
	body_style.set_border_width_all(4)
	body.add_theme_stylebox_override("panel", body_style)
	_visual.add_child(body)

	var head := Panel.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.position = Vector2(-head_d / 2.0, -h)
	head.size = Vector2(head_d, head_d)
	var head_style := StyleBoxFlat.new()
	head_style.bg_color = _color.lightened(0.25)
	head_style.set_corner_radius_all(int(head_d / 2.0))
	head_style.border_color = _color.darkened(0.35)
	head_style.set_border_width_all(4)
	head.add_theme_stylebox_override("panel", head_style)
	_visual.add_child(head)

	# 一根指向前方的長條，讓人看得出面向
	var weapon := ColorRect.new()
	weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon.color = _color.lightened(0.45)
	weapon.size = Vector2(w * 0.95, 10)
	weapon.position = Vector2(0.0 if not is_enemy else -w * 0.95, -h * 0.6)
	_visual.add_child(weapon)

	var name_label := UiKit.label(display_name, 36, UiKit.TEXT, 8)
	name_label.position = Vector2(-150, 8)
	name_label.size = Vector2(300, 44)
	add_child(name_label)


static func _get_shadow_texture() -> GradientTexture2D:
	if _shadow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.02, 0.05, 0.06, 0.66))
		gradient.set_color(1, Color(0.02, 0.05, 0.06, 0))
		gradient.add_point(0.6, Color(0.02, 0.05, 0.06, 0.5))
		_shadow_texture = GradientTexture2D.new()
		_shadow_texture.gradient = gradient
		_shadow_texture.width = 64
		_shadow_texture.height = 64
		_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
		_shadow_texture.fill_from = Vector2(0.5, 0.5)
		_shadow_texture.fill_to = Vector2(1.0, 0.5)
	return _shadow_texture
