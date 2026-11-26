extends RefCounted
## 介面共用的顏色、底圖與小零件。
## 顏色與九宮格邊距都取自風格指南（assets/style/guide.md）。

# 主色
const INK := Color("#172C34")  # 墨靛：面板
const TEAL := Color("#31565B")  # 青黛：按鈕漆面
const PINE := Color("#527870")  # 松煙綠
const JADE := Color("#AAD0C3")  # 霧玉
const PAPER := Color("#EAE3CF")  # 練白：深底上的文字
const BRONZE := Color("#B89A66")  # 舊銅：護角、細線
const OCHRE := Color("#A14F44")  # 赭朱

# 戰鬥識別色
const FORCE_COLOR := {
	"gang": Color("#E0A14F"),
	"rou": Color("#72BCA7"),
	"kuai": Color("#B2A3EB"),
}
const PARTY := Color("#72ABE3")
const ENEMY := Color("#EC8174")
const HP := Color("#C65E50")

# 指南還沒有定的顏色，先由程式暫定
const MP := Color("#5F93B8")
const GAUGE := Color("#D9B872")
const TEXT := PAPER
const TEXT_DIM := Color("#8FA3A0")
const HIGHLIGHT := Color("#F3D58E")
const DAMAGE := Color("#FF8A75")
const HEAL := Color("#93E6B5")
const SHADE := Color(0.035, 0.07, 0.085)

const PANEL_TEXTURE := preload("res://assets/ui/panel.png")
const BUTTON_TEXTURE := preload("res://assets/ui/button.png")
const HP_TRACK_TEXTURE := preload("res://assets/ui/hp_track.png")
const HP_FILL_TEXTURE := preload("res://assets/ui/hp_fill.png")

const PANEL_SLICE := 48
const BUTTON_SLICE := 28


## 面板底框。pad 是內容離邊框的距離。
static func panel_style(pad_x: float = 28.0, pad_y: float = 20.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL_TEXTURE
	style.set_texture_margin_all(PANEL_SLICE)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


static func button_style(tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BUTTON_TEXTURE
	style.set_texture_margin_all(BUTTON_SLICE)
	style.modulate_color = tint
	# 內容邊距要另外設小一點；不設的話會沿用九宮格的邊（28），按鈕就不能做得比 108 矮
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## 把按鈕換成樣張的外觀。目前只有「一般」一張圖，其他狀態先用明暗變化代替。
static func style_button(button: Button, font_size: int) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", button_style())
	button.add_theme_stylebox_override("hover", button_style(Color(1.18, 1.18, 1.14)))
	button.add_theme_stylebox_override("pressed", button_style(Color(0.8, 0.8, 0.78)))
	button.add_theme_stylebox_override("disabled", button_style(Color(0.5, 0.52, 0.55, 0.92)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", HIGHLIGHT)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)


## 一般文字。outline 大於 0 時加深色描邊，直接疊在場景上的字要用。
static func label(text: String, font_size: int, color: Color = TEXT, outline: int = 0) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if outline > 0:
		node.add_theme_color_override("font_outline_color", Color(SHADE, 0.95))
		node.add_theme_constant_override("outline_size", outline)
	return node


## 深色的平塗小底框，給貼在場景上的小標籤用（招式名、蓄招、狀態）。
static func tag_style(border: Color = BRONZE, alpha: float = 0.9) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, alpha)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## 角色頭像的路徑；沒有圖時回傳 null。
static func head_texture(character_id: String) -> Texture2D:
	var path := "res://assets/characters/%s/portrait/head.png" % character_id
	if ResourceLoader.exists(path):
		return load(path)
	return null
