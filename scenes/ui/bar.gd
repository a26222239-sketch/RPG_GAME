extends Control
## 橫條：底槽加上會伸縮的填充。
## 氣血用樣張的貼圖（底槽與填充各一張，左右兩端是尖角，中段可以拉長）；
## 內力、行動、蓄招還沒有貼圖，先用純色。

const UiKit := preload("res://scenes/ui/ui_kit.gd")

## 貼圖左右兩端不拉伸的寬度，以及填充離底槽兩端的距離（原圖像素）。
const END_CAP := 20
const FILL_INSET := 10.0

var _clip: Control
var _inset: float = 0.0
var _ratio: float = 1.0
var _tween: Tween


## 氣血條。高度不是 36 時，貼圖會上下等比例壓扁。
func setup_textured(bar_size: Vector2) -> void:
	_begin(bar_size)
	_inset = FILL_INSET
	add_child(_patch(UiKit.HP_TRACK_TEXTURE, bar_size))
	_clip = _make_clip(bar_size)
	_clip.add_child(_patch(UiKit.HP_FILL_TEXTURE, bar_size))
	set_ratio(1.0, false)


## 純色的條。
func setup_flat(bar_size: Vector2, fill: Color, back: Color = Color(UiKit.SHADE, 0.85)) -> void:
	_begin(bar_size)
	_inset = 0.0
	var track := ColorRect.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.color = back
	track.size = bar_size
	add_child(track)
	_clip = _make_clip(bar_size)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = fill
	rect.size = bar_size
	_clip.add_child(rect)
	set_ratio(1.0, false)


func ratio() -> float:
	return _ratio


## 設定比例（0 到 1）。回傳正在跑的補間；不做動畫時回傳 null。
## steady 為真時等速前進（倒數用）；否則先快後慢（氣血增減用）。
func set_ratio(value: float, animate: bool = true, duration: float = 0.45, steady: bool = false) -> Tween:
	_ratio = clampf(value, 0.0, 1.0)
	var width := 0.0 if _ratio <= 0.0 else _inset + (size.x - _inset * 2.0) * _ratio
	if _tween:
		_tween.kill()
		_tween = null
	if not animate or duration <= 0.0:
		_clip.size.x = width
		return null
	_tween = create_tween()
	var tweener := _tween.tween_property(_clip, "size:x", width, duration)
	if not steady:
		tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return _tween


func _begin(bar_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = bar_size
	size = bar_size


func _make_clip(bar_size: Vector2) -> Control:
	var clip := Control.new()
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.size = bar_size
	add_child(clip)
	return clip


func _patch(texture: Texture2D, bar_size: Vector2) -> NinePatchRect:
	var patch := NinePatchRect.new()
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.texture = texture
	patch.patch_margin_left = END_CAP
	patch.patch_margin_right = END_CAP
	patch.size = bar_size
	return patch
