extends Sprite2D
## 播一組特效圖（設計文件 15.9）。
##
## 特效圖是 assets/vfx/{識別碼}.png：橫排的逐格圖，由左到右是播放順序，每格是正方形。
## 也可以一格一個檔（{識別碼}_01.png 起）。黑底或透明底都可以，這裡用加亮的方式疊上去，黑色會自動消失。
## 圖是美術交的；怎麼對位、播多快、染什麼顏色寫在 data/vfx.json，是程式這一邊的設定。
## 美術想指定每秒幾格、第幾格是命中的瞬間，寫在 assets/vfx/meta.json：
##   { "slash_sword": { "impact_frame": 3, "fps": 16 } }
##
## 某一組特效還沒有圖的時候 exists() 回傳 false，由呼叫的一方改用程式畫的暫用特效（battle_fx.gd）。

const FrameStrip := preload("res://core/art/frame_strip.gd")
const FrameSet := preload("res://scenes/battle/frame_set.gd")
const JsonLoader := preload("res://core/data/json_loader.gd")

const VFX_DIR := "res://assets/vfx/"
## 套在人身上的特效是照 512 的角色格子畫的：腳底在離格子底邊十六分之一的線上。
const BODY_FRAME := 512.0
const FEET_RATIO := 1.0 / 16.0

static var _cache: Dictionary = {}
static var _meta: Dictionary = {}
static var _meta_loaded: bool = false
static var _material: CanvasItemMaterial

var _info: Dictionary = {}
var _time: float = 0.0


## 這組特效有沒有圖可以播。
static func exists(fx_id: String) -> bool:
	return not info(fx_id).is_empty()


## 這組特效的圖與播放設定；沒有圖、圖不合規格、或設定檔沒有這一組時回傳空字典。
static func info(fx_id: String) -> Dictionary:
	if _cache.has(fx_id):
		return _cache[fx_id]
	_cache[fx_id] = _load(fx_id)
	return _cache[fx_id]


## 從開始播到「命中」那一格要幾秒。出手的動作要提早這麼久開始播特效，兩邊的命中才會對上。
static func lead_time(fx_id: String) -> float:
	return float(info(fx_id).get("impact", 0.0))


## 在 parent 底下播一組特效。
## at：hit 對位的是命中點；body 對位的是那個人的腳底。
## force_color：招式勁路的顏色，設定是 tint: force 的特效會染成這個顏色。
## direction：1 是由左往右出手，-1 相反。
## owner_frame：套在人身上時，那個人的格子邊長（512 或 768）。
## 沒有圖時回傳 null。
static func spawn(parent: Node, fx_id: String, at: Vector2, force_color: Color = Color.WHITE, direction: float = 1.0, owner_frame: float = BODY_FRAME) -> Node:
	var data := info(fx_id)
	if data.is_empty():
		return null
	var fx := new()
	fx._setup(data, at, force_color, direction, owner_frame)
	parent.add_child(fx)
	return fx


## 換了圖之後（測試用）清掉記住的結果。
static func forget() -> void:
	_cache.clear()
	_meta.clear()
	_meta_loaded = false


static func _load(fx_id: String) -> Dictionary:
	var settings: Variant = Game.data.vfx.get(fx_id)
	if not settings is Dictionary:
		return {}
	var frames := FrameSet.load_frames(VFX_DIR + fx_id)
	if frames.is_empty():
		return {}
	if not _meta_loaded:
		_meta_loaded = true
		var meta: Variant = JsonLoader.load_file(VFX_DIR + "meta.json")
		if meta is Dictionary:
			_meta = meta
	var written: Dictionary = {}
	if settings.has("impact_frame"):
		written["impact_frame"] = settings["impact_frame"]
	if _meta.get(fx_id) is Dictionary:
		written.merge(_meta[fx_id], true)
	var data := FrameStrip.timing(frames.size(), float(settings["length"]), 0.0, written)
	data["frames"] = frames
	data["settings"] = settings
	return data


func _setup(data: Dictionary, at: Vector2, force_color: Color, direction: float, owner_frame: float) -> void:
	_info = data
	var settings: Dictionary = data["settings"]
	texture = (data["frames"] as Array)[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flip_h = direction < 0.0
	material = _additive()
	var tint := str(settings.get("tint", "none"))
	if tint == "force":
		modulate = force_color
	elif tint != "none":
		modulate = Color(tint)
	var side := float(settings["frame"])
	if str(settings["anchor"]) == "body":
		if not bool(settings.get("own_size", false)):
			side *= owner_frame / BODY_FRAME
		centered = false
		position = at + Vector2(-side / 2.0, -side * (1.0 - FEET_RATIO))
	else:
		centered = true
		position = at
	scale = Vector2.ONE * (side / float(texture.get_height()))


func _process(delta: float) -> void:
	_time += delta
	var looping := bool((_info["settings"] as Dictionary).get("loop", false))
	if not looping and _time >= float(_info["length"]):
		queue_free()
		return
	var frames: Array = _info["frames"]
	texture = frames[FrameStrip.frame_at(_time, float(_info["fps"]), frames.size(), FrameStrip.LOOP if looping else FrameStrip.HOLD)]


static func _additive() -> CanvasItemMaterial:
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _material
