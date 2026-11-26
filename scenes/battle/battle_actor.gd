extends Control
## 戰鬥中的一個角色。這個節點的原點是角色的腳底中央。
##
## 對外介面是設計文件 12.4 的動畫契約：play_anim(動畫名)。依序找：
## 1. 節點底下有 AnimationPlayer 而且有同名動畫，就播那個動畫。
## 2. 美術交了這個動作的圖 assets/characters/{識別碼}/frames/{動畫名}.png，就照著播。
##    圖是橫排的逐格圖，每格是正方形；只有一格的話就是定格的姿勢。也可以一格一個檔（{動畫名}_01.png 起）。
##    每格停多久、哪一格是「打到」的瞬間，美術可以寫在同一個資料夾的 meta.json（欄位見 core/art/frame_strip.gd）。
## 3. 都沒有的話，拿站姿圖用位移、傾斜、明暗做出暫用的動作。
##
## 動作的畫面全部來自美術的圖，這裡只決定什麼時候播、播多快，
## 以及不需要圖的演出：受擊時閃一下並往後退、還沒有特效圖時的明暗變化。
##
## 站姿圖放在 assets/characters/{識別碼}/frames/stand.png，由 tools/prepare_art.py 從設定圖產生，
## 擺法照設計文件 15.6 的逐格圖規格：一般角色的格子是 512×512、首領 768×768，
## 腳底在離格子底邊 32 像素的線上、水平置中。圖的實際解析度可以比格子大。
## 還沒有圖的角色，畫成寫著名字的色塊。

signal clicked(actor_id: String)

const UiKit := preload("res://scenes/ui/ui_kit.gd")
const Bar := preload("res://scenes/ui/bar.gd")
const FrameStrip := preload("res://core/art/frame_strip.gd")
const FrameSet := preload("res://scenes/battle/frame_set.gd")
const StripFx := preload("res://scenes/battle/strip_fx.gd")
const JsonLoader := preload("res://core/data/json_loader.gd")

const FRAME_NORMAL := 512.0
const FRAME_BOSS := 768.0
const FEET_MARGIN := 32.0
const GAUGE_SIZE := Vector2(132, 10)
const CHARGE_W := 250.0

## 暫用動作（沒有圖的時候）各動畫的大致長度（秒）與出手點（比例）。
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
## 美術交的圖，各動作預設播多久（秒，設計文件 15.5 的建議長度）。美術沒有在 meta.json 寫速度時，
## 格子平均排進這段時間，所以畫幾格都可以。招式專屬的動作沒列在這裡，用 SPECIAL_LENGTH。
const STRIP_LENGTH := {
	"idle": 1.2, "ready": 0.8, "charge": 1.0, "attack_light": 0.5, "attack_heavy": 0.9, "cast": 0.7,
	"hit": 0.3, "guard": 0.4, "stagger": 1.0, "down": 0.8, "victory": 1.2, "walk": 0.8,
}
const SPECIAL_LENGTH := 0.9
## 循環播放的動作，以及播完停在最後一格的動作。其餘的播完回到平常的姿勢。
const LOOP_ANIMS := ["idle", "ready", "charge", "stagger", "walk"]
const HOLD_ANIMS := ["guard", "down"]

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
var _frame: float = FRAME_NORMAL
var _visual: Control
## 站姿圖（或色塊）。播美術交的動作圖時藏起來。
var _still: Control
var _sprite: Sprite2D
## 美術交的動作圖：動畫名 → 圖與播放資訊；沒有圖的記成空字典。
var _strips: Dictionary = {}
var _strip_meta: Dictionary = {}
var _strip_sprite: Sprite2D
var _strip: Dictionary = {}
var _strip_time: float = 0.0
## 身上持續播放的特效：特效識別碼 → 節點。
var _auras: Dictionary = {}
## 沒有別的動作時回到哪個動畫：平常是待機，守勢、破綻時是那個姿勢。
var _rest_anim: String = "idle"
## 正在播一個播完才回到平常姿勢的動作（出手、受擊）。
var _busy: bool = false
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
	_frame = FRAME_BOSS if boss else FRAME_NORMAL
	body_size = Vector2(_frame * 0.24, _frame * 0.78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meta: Variant = JsonLoader.load_file("res://assets/characters/%s/frames/meta.json" % actor_id)
	if meta is Dictionary:
		_strip_meta = meta
	_build(display_name, _frame)
	set_process(false)
	play_anim("idle")


## 這個角色的格子邊長（設計解析度的像素）：一般角色 512，首領 768。
func frame_size() -> float:
	return _frame


## 面向：朝右是 1，朝左是 -1。我方預設朝右，敵方預設朝左。
func facing() -> float:
	return -1.0 if is_enemy != _flipped else 1.0


## 轉身面向另一邊（繞到對手背後時用）。
func set_flipped(on: bool) -> void:
	_flipped = on
	if _sprite:
		_sprite.flip_h = is_enemy != _flipped
	_strip_sprite.flip_h = is_enemy != _flipped


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
## force_color 是這一招勁路的顏色，蓄招氣場的特效會染成這個顏色。
func show_charge(text: String, duration: float = 0.0, hold_ratio: float = 1.0, force_color: Color = Color.WHITE) -> Tween:
	_charge_label.text = text
	_charge_bar.set_ratio(0.0, false)
	_charge_box.visible = true
	_charge_box.reset_size()
	_layout_overhead()
	set_aura("charge_aura", true, force_color)
	play_anim("charge")
	if duration <= 0.0:
		return null
	return _charge_bar.set_ratio(hold_ratio, true, duration, true)


func finish_charge(duration: float) -> Tween:
	return _charge_bar.set_ratio(1.0, true, duration, true)


func hide_charge() -> void:
	_charge_box.visible = false
	set_aura("charge_aura", false)
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


## 美術有沒有交這個動作的圖。招式專屬的動作（名稱是招式識別碼）用這個問。
func has_art(anim: String) -> bool:
	return not _strip_for(anim).is_empty()


func anim_length(anim: String) -> float:
	var strip := _strip_for(anim)
	if not strip.is_empty():
		return float(strip["length"])
	return float(ANIM_INFO.get(anim, {"length": 0.4})["length"])


## 從動畫開始到「打到」的時間。
func anim_impact_time(anim: String) -> float:
	var strip := _strip_for(anim)
	if not strip.is_empty():
		return float(strip["impact"])
	var info: Dictionary = ANIM_INFO.get(anim, {"length": 0.4, "impact": 0.5})
	return float(info["length"]) * float(info["impact"])


## 設定平常的姿勢：沒有別的動作時回到哪個動畫。守勢、破綻這種會持續一陣子的狀態用。
## 原本就在平常的姿勢時立刻換過去；正在做別的事（準備出手、蓄招、出手、受擊）則等它結束。
## 破綻例外：它會打斷準備與蓄招，只等出手或受擊播完。倒下的人不再換姿勢。
func set_rest_anim(anim: String) -> void:
	if _rest_anim == anim:
		return
	var resting := _current_loop == _rest_anim
	_rest_anim = anim
	if _current_loop == "down":
		return
	if resting or (anim == "stagger" and not _busy):
		play_anim(anim)


## 在身上開或關一組持續播放的特效（蓄招氣場、守勢、破綻標記）。
## 特效圖還沒交的話什麼都不做，回傳 false。
func set_aura(fx_id: String, on: bool, force_color: Color = Color.WHITE) -> bool:
	if _auras.has(fx_id):
		if on:
			return true
		(_auras[fx_id] as Node).queue_free()
		_auras.erase(fx_id)
		return false
	if not on:
		return false
	var fx := StripFx.spawn(self, fx_id, Vector2.ZERO, force_color, facing(), _frame)
	if fx == null:
		return false
	_auras[fx_id] = fx
	return true


## 播放動畫。回傳動畫長度（秒）。
func play_anim(anim: String) -> float:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(anim):
		player.play(anim)
		return player.get_animation(anim).length

	_stop_tweens()
	_reset_visual()
	_current_loop = anim if LOOP_ANIMS.has(anim) or HOLD_ANIMS.has(anim) else ""
	_busy = _current_loop == ""
	var strip := _strip_for(anim)
	if strip.is_empty():
		_show_still()
		_play_placeholder(anim)
	else:
		_show_strip(strip)
		_play_drawn(anim)
	return anim_length(anim)


## 美術交了圖的動作：畫面照圖播，這裡只加不需要圖的演出。
func _play_drawn(anim: String) -> void:
	var d := facing()
	match anim:
		"charge":
			_pulse_charge()
		"hit":
			_visual.modulate = Color(2.0, 1.3, 1.25)
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -26.0 * d, 0.08)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.2)
		"guard":
			_tint_guard()


## 還沒有圖的動作：拿站姿圖用位移、傾斜、明暗頂替。
func _play_placeholder(anim: String) -> void:
	var d := facing()
	match anim:
		"idle":
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.012), 1.1).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 1.1).set_trans(Tween.TRANS_SINE)
		"ready":
			_visual.rotation = 0.02 * d
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "modulate", Color(1.16, 1.16, 1.1), 0.4).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE)
		"charge":
			_visual.scale = Vector2(1.02, 0.98)
			_pulse_charge()
		"attack_light":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", 64.0 * d, 0.2).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.06 * d, 0.2)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.25)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.25)
			_anim_tween.tween_callback(_back_to_rest)
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
			_anim_tween.tween_callback(_back_to_rest)
		"cast":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "scale", Vector2(1.03, 1.04), 0.4).set_ease(Tween.EASE_OUT)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color(1.3, 1.45, 1.3), 0.4)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.3)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.3)
			_anim_tween.tween_callback(_back_to_rest)
		"hit":
			_visual.modulate = Color(2.0, 1.3, 1.25)
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:x", -26.0 * d, 0.08)
			_anim_tween.parallel().tween_property(_visual, "rotation", -0.05 * d, 0.08)
			_anim_tween.tween_property(_visual, "position:x", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.2)
			_anim_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, 0.2)
			_anim_tween.tween_callback(_back_to_rest)
		"guard":
			_tint_guard()
			var lean := create_tween().set_parallel()
			lean.tween_property(_visual, "rotation", -0.04 * d, 0.2)
			lean.tween_property(_visual, "scale", Vector2(1.02, 0.97), 0.2)
			_loop_tween = lean
		"stagger":
			_visual.modulate = Color(1.08, 0.86, 0.86)
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "rotation", -0.075 * d, 0.5).set_trans(Tween.TRANS_SINE)
			_loop_tween.tween_property(_visual, "rotation", -0.03 * d, 0.5).set_trans(Tween.TRANS_SINE)
		"down":
			_anim_tween = create_tween().set_parallel()
			_anim_tween.tween_property(_visual, "rotation", 0.11 * d, 0.5).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "scale", Vector2(1.0, 0.93), 0.5).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "modulate", Color(0.62, 0.6, 0.66), 0.5)
		"victory":
			_anim_tween = create_tween()
			_anim_tween.tween_property(_visual, "position:y", -40.0, 0.25).set_ease(Tween.EASE_OUT)
			_anim_tween.tween_property(_visual, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
			_anim_tween.tween_callback(_back_to_rest)
		"walk":
			_loop_tween = create_tween().set_loops()
			_loop_tween.tween_property(_visual, "position:y", -7.0, 0.2)
			_loop_tween.parallel().tween_property(_visual, "rotation", 0.02 * d, 0.2)
			_loop_tween.tween_property(_visual, "position:y", 0.0, 0.2)
			_loop_tween.parallel().tween_property(_visual, "rotation", 0.0, 0.2)
		_:
			push_warning("%s 沒有動畫 %s" % [actor_id, anim])
			_busy = false


## 蓄招時忽明忽暗。有蓄招氣場的特效圖時由特效表現，這裡就不做。
func _pulse_charge() -> void:
	if _auras.has("charge_aura"):
		return
	_loop_tween = create_tween().set_loops()
	_loop_tween.tween_property(_visual, "modulate", Color(1.4, 1.38, 1.22), 0.35)
	_loop_tween.tween_property(_visual, "modulate", Color.WHITE, 0.35)


## 守勢時身體偏藍。有守勢的特效圖時由特效表現，這裡就不做。
func _tint_guard() -> void:
	if _auras.has("guard"):
		return
	_anim_tween = create_tween()
	_anim_tween.tween_property(_visual, "modulate", Color(0.78, 0.9, 1.18), 0.2)


func _back_to_rest() -> void:
	play_anim(_rest_anim)


# ---------------------------------------------------------------- 美術交的動作圖

func _strip_for(anim: String) -> Dictionary:
	if not _strips.has(anim):
		_strips[anim] = _load_strip(anim)
	return _strips[anim]


func _load_strip(anim: String) -> Dictionary:
	if anim == "stand":
		return {}
	var frames := FrameSet.load_frames("res://assets/characters/%s/frames/%s" % [actor_id, anim])
	if frames.is_empty():
		return {}
	var info: Dictionary = ANIM_INFO.get(anim, {"impact": 0.6})
	var written: Variant = _strip_meta.get(anim)
	var strip := FrameStrip.timing(frames.size(), float(STRIP_LENGTH.get(anim, SPECIAL_LENGTH)), float(info["impact"]),
		written if written is Dictionary else {}, int(_strip_meta.get("frame_index_base", 1)))
	strip["frames"] = frames
	strip["mode"] = FrameStrip.LOOP if LOOP_ANIMS.has(anim) else (FrameStrip.HOLD if HOLD_ANIMS.has(anim) else FrameStrip.ONCE)
	return strip


func _show_strip(strip: Dictionary) -> void:
	_strip = strip
	_strip_time = 0.0
	var first: Texture2D = (strip["frames"] as Array)[0]
	_strip_sprite.texture = first
	_strip_sprite.scale = Vector2.ONE * (_frame / float(first.get_height()))
	_strip_sprite.visible = true
	_still.visible = false
	set_process(true)


func _show_still() -> void:
	_strip = {}
	_strip_sprite.visible = false
	_still.visible = true
	set_process(false)


func _process(delta: float) -> void:
	if _strip.is_empty():
		return
	_strip_time += delta
	var mode := str(_strip["mode"])
	if mode == FrameStrip.ONCE and _strip_time >= float(_strip["length"]):
		_back_to_rest()
		return
	var frames: Array = _strip["frames"]
	_strip_sprite.texture = frames[FrameStrip.frame_at(_strip_time, _strip["ends"], mode)]


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
	_still = Control.new()
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_still)
	_strip_sprite = Sprite2D.new()
	_strip_sprite.centered = false
	_strip_sprite.flip_h = is_enemy != _flipped
	_strip_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_strip_sprite.position = Vector2(-frame / 2.0, -(frame - FEET_MARGIN))
	_strip_sprite.visible = false
	_visual.add_child(_strip_sprite)

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
		_still.add_child(_sprite)
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
	_still.add_child(body)

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
	_still.add_child(head)

	# 一根指向前方的長條，讓人看得出面向
	var weapon := ColorRect.new()
	weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon.color = _color.lightened(0.45)
	weapon.size = Vector2(w * 0.95, 10)
	weapon.position = Vector2(0.0 if not is_enemy else -w * 0.95, -h * 0.6)
	_still.add_child(weapon)

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
