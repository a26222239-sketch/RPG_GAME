extends Control
## 識別用的小記號。風格指南規定每種識別色都要搭配一個形狀，不能只靠顏色分辨：
## 我方圓點、敵方菱形、剛方印、柔雙弧、快雙斜筆。

var kind: String = "dot":
	set(value):
		kind = value
		queue_redraw()
var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _init(glyph_kind: String = "dot", glyph_color: Color = Color.WHITE, glyph_size: float = 28.0) -> void:
	kind = glyph_kind
	color = glyph_color
	custom_minimum_size = Vector2(glyph_size, glyph_size)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	match kind:
		"dot":
			draw_circle(c, r * 0.55, color, true, -1.0, true)
		"diamond":
			var d := r * 0.8
			draw_colored_polygon([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)], color)
		"gang":
			# 方印：方框裡一個實心小方塊
			var half := r * 0.72
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), color, false, maxf(2.0, r * 0.2), true)
			var core := r * 0.3
			draw_rect(Rect2(c - Vector2(core, core), Vector2(core, core) * 2.0), color)
		"rou":
			# 雙弧：兩道同向的弧線
			var width := maxf(2.0, r * 0.2)
			draw_arc(c + Vector2(-r * 0.25, r * 0.1), r * 0.62, -PI * 0.42, PI * 0.42, 16, color, width, true)
			draw_arc(c + Vector2(r * 0.2, r * 0.1), r * 0.62, -PI * 0.42, PI * 0.42, 16, color, width, true)
		"kuai":
			# 雙斜筆：兩道平行的斜線
			var width := maxf(2.0, r * 0.22)
			for shift: float in [-r * 0.32, r * 0.32]:
				draw_line(c + Vector2(shift - r * 0.3, r * 0.7), c + Vector2(shift + r * 0.3, -r * 0.7), color, width, true)
