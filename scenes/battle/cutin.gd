extends Control
## 大招特寫（設計文件 15.9、docs/animation_spec.md 第 6 節）。
##
## 大招出手前：畫面暗下來，一條橫幅從出手的人那一側滑進來，上面是他的特寫，另一側寫招式名；
## 停一下，再往前滑出去，接著才播大招的動作。
##
## 特寫的圖是美術交的：assets/characters/{角色}/cutin/{招式}_01.png 起，每張 2560×720，一張一格循環播放。
## 圖一律畫成面向右；敵人的特寫由程式左右翻轉。圖裡不放字，招式名由程式寫上去。
## 還沒有圖的時候用暫用的畫面：勁路顏色的橫幅、幾道流光，加上對話框用的頭像。
##
## 程式對圖只做顯示上的處理：等比例縮放、置中、裁在橫幅裡、慢慢推近、翻轉。

const FrameSet := preload("res://scenes/battle/frame_set.gd")
const UiKit := preload("res://scenes/ui/ui_kit.gd")

## 橫幅的高度（設計解析度的像素）。圖是 2560×720，在 16:9 的畫面上剛好縮成 1920×540。
const BAND_HEIGHT := 540.0
const ART_SIZE := Vector2(2560, 720)
## 橫幅中心在畫面高度的幾成：上方留給隊伍面板與敵方氣血，下方留給對話框。
const BAND_CENTER := 0.47
const ENTER := 0.16
const HOLD := 0.9
const LEAVE := 0.14
const DIM := 0.6
## 特寫每張停多久（秒）。
const FRAME_TIME := 0.083
const PUSH_IN := 1.05

signal finished

var _frames: Array[Texture2D] = []
var _art: TextureRect
var _time: float = 0.0


## 這一招有沒有美術交的特寫。
static func has_art(character_id: String, move_id: String) -> bool:
	return not FrameSet.load_cutin(_base(character_id, move_id)).is_empty()


static func _base(character_id: String, move_id: String) -> String:
	return "res://assets/characters/%s/cutin/%s" % [character_id, move_id]


## 播一次特寫，播完才返回（呼叫的一方用 await 等它）。
## from_left：出手的人在左邊（我方），橫幅從左邊滑進來；敵方相反。
func play(character_id: String, move_id: String, from_left: bool, color: Color, move_title: String, who_title: String) -> void:
	for child in get_children():
		child.queue_free()
	_frames = FrameSet.load_cutin(_base(character_id, move_id))
	_time = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen := get_viewport_rect().size
	size = screen
	position = Vector2.ZERO

	var dim := ColorRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0, 0, 0, DIM)
	dim.size = screen
	dim.modulate.a = 0.0
	add_child(dim)

	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.clip_contents = true
	band.size = Vector2(screen.x, BAND_HEIGHT)
	var band_y := screen.y * BAND_CENTER - BAND_HEIGHT / 2.0
	band.position = Vector2(-screen.x if from_left else screen.x, band_y)
	add_child(band)

	if _frames.is_empty():
		_build_placeholder(band, character_id, from_left, color)
	else:
		_build_art(band, from_left)
	_build_edges(band)
	_build_titles(band, from_left, color, move_title, who_title)

	set_process(not _frames.is_empty())
	var direction := 1.0 if from_left else -1.0
	var tween := create_tween()
	tween.tween_property(dim, "modulate:a", 1.0, ENTER)
	tween.parallel().tween_property(band, "position:x", 0.0, ENTER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _art:
		var zoom := create_tween()
		zoom.tween_property(_art, "scale", _art.scale * PUSH_IN, ENTER + HOLD + LEAVE)
	tween.tween_interval(HOLD)
	tween.tween_property(band, "position:x", screen.x * direction, LEAVE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(dim, "modulate:a", 0.0, LEAVE)
	await tween.finished
	set_process(false)
	visible = false
	for child in get_children():
		child.queue_free()
	_art = null
	finished.emit()


func _process(delta: float) -> void:
	if _frames.is_empty() or _art == null:
		return
	_time += delta
	_art.texture = _frames[int(_time / FRAME_TIME) % _frames.size()]


## 美術交的特寫：等比例放大到蓋滿橫幅，置中，超出的部分裁掉。
func _build_art(band: Control, from_left: bool) -> void:
	var first := _frames[0]
	var art_size := first.get_size()
	var scale_value := maxf(band.size.y / art_size.y, band.size.x / art_size.x)
	_art = TextureRect.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.texture = first
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.flip_h = not from_left
	_art.size = art_size
	_art.pivot_offset = art_size / 2.0
	_art.scale = Vector2.ONE * scale_value
	_art.position = band.size / 2.0 - art_size / 2.0
	band.add_child(_art)


## 還沒有特寫的圖：勁路顏色的橫幅、流光，加上頭像。
func _build_placeholder(band: Control, character_id: String, from_left: bool, color: Color) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, UiKit.INK)
	gradient.set_color(1, UiKit.INK.lerp(color, 0.55))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(1, 0) if from_left else Vector2(0, 0)
	fill.fill_to = Vector2(0, 0) if from_left else Vector2(1, 0)
	var background := TextureRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = fill
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.size = band.size
	band.add_child(background)

	# 流光：幾道細長的亮線，沿著出手的方向劃過
	var direction := 1.0 if from_left else -1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(character_id)
	for i in 14:
		var streak := ColorRect.new()
		streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
		streak.color = color.lerp(Color.WHITE, 0.5)
		streak.color.a = rng.randf_range(0.12, 0.32)
		streak.size = Vector2(rng.randf_range(260.0, 720.0), rng.randf_range(2.0, 5.0))
		var y := rng.randf_range(20.0, band.size.y - 20.0)
		var start_x := -streak.size.x if direction > 0 else band.size.x
		streak.position = Vector2(start_x + direction * rng.randf_range(0.0, band.size.x), y)
		band.add_child(streak)
		var run := create_tween()
		run.tween_property(streak, "position:x", streak.position.x + direction * band.size.x * 0.9, ENTER + HOLD + LEAVE)

	var head := UiKit.head_texture(character_id)
	if head:
		var portrait := TextureRect.new()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.texture = head
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.flip_h = not from_left
		var side := band.size.y * 0.92
		portrait.size = Vector2(side, side)
		var center_x := band.size.x * (0.3 if from_left else 0.7)
		portrait.position = Vector2(center_x - side / 2.0, band.size.y - side)
		portrait.pivot_offset = portrait.size / 2.0
		band.add_child(portrait)
		_art = portrait


func _build_edges(band: Control) -> void:
	for y: float in [0.0, band.size.y - 4.0]:
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = UiKit.BRONZE
		line.size = Vector2(band.size.x, 4.0)
		line.position = Vector2(0, y)
		band.add_child(line)


## 招式名寫在出手的人的另一側，免得蓋到臉。
func _build_titles(band: Control, from_left: bool, color: Color, move_title: String, who_title: String) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var who := UiKit.label(who_title, 40, UiKit.TEXT, 6)
	var title := UiKit.label(move_title, 104, color.lerp(Color.WHITE, 0.55), 10)
	for label: Label in [who, title]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if from_left else HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(label)
	band.add_child(box)
	box.reset_size()
	var width := maxf(box.size.x, 10.0)
	var margin := band.size.x * 0.08
	var x := band.size.x - margin - width if from_left else margin
	box.position = Vector2(x, band.size.y - box.size.y - 52.0)
