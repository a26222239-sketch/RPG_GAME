extends Node2D
## 程式畫的暫用特效：刀光、氣勁、治療。播完自己消失。
## 正式的特效圖（設計文件 15.9）交付之後，由逐格圖取代。

var kind: String = "slash"
var color: Color = Color.WHITE
var radius: float = 120.0
var duration: float = 0.3
## 朝向：1 是由左往右出手，-1 相反。
var direction: float = 1.0

var _t: float = 0.0


static func spawn(parent: Node, at: Vector2, fx_kind: String, fx_color: Color, fx_radius: float, fx_direction: float = 1.0) -> void:
	var fx := new()
	fx.kind = fx_kind
	fx.color = fx_color
	fx.radius = fx_radius
	fx.direction = fx_direction
	fx.duration = float({"heal": 0.75, "burst": 0.42, "slash_heavy": 0.5}.get(fx_kind, 0.32))
	fx.position = at
	parent.add_child(fx)


func _process(delta: float) -> void:
	_t += delta / duration
	if _t >= 1.0:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var fade := 1.0 - _t
	var eased := 1.0 - pow(1.0 - _t, 3.0)
	match kind:
		"slash":
			# 一道斜斜劃過的光
			_draw_slash(_t, 0.57)
		"slash_heavy":
			# 重招：交叉的兩道，第二道晚一點出現
			_draw_slash(minf(1.0, _t * 1.5), 0.57)
			if _t > 0.28:
				_draw_slash((_t - 0.28) / 0.72, -0.5)
		"burst":
			# 一圈向外擴散的氣勁：先亮一下，再化成一圈光，外緣帶幾道短的放射線
			var r := radius * (0.3 + 0.85 * eased)
			draw_circle(Vector2.ZERO, r * 0.8, Color(color, 0.3 * fade * fade), true, -1.0, true)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color, fade * 0.85), 14.0 * fade + 3.0, true)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, fade * 0.8), 4.0 * fade + 1.0, true)
			for i in 10:
				var dir := Vector2.from_angle(TAU * float(i) / 10.0 + 0.3)
				draw_line(dir * r * 1.1, dir * r * (1.22 + 0.2 * fade), Color(1, 1, 1, fade * 0.75), 4.0 * fade + 1.0, true)
		"heal":
			# 一圈往上升的光環，加上幾點光
			var lift := -radius * 1.3 * eased
			for i in 3:
				var y := lift * (1.0 - 0.28 * i) + radius * 0.4
				var a := fade * (0.9 - 0.22 * i)
				_draw_ellipse(Vector2(0, y), Vector2(radius * 0.62, radius * 0.16), Color(color, a), 7.0 * fade + 2.0)
			for i in 6:
				var x := radius * 0.55 * sin(float(i) * 2.4)
				var y := radius * 0.5 - radius * 1.6 * fmod(_t * 1.2 + float(i) * 0.17, 1.0)
				draw_circle(Vector2(x, y), 5.0 * fade + 1.5, Color(1, 1, 1, fade * 0.9), true, -1.0, true)


## 一道由出手的一方斜向劃過的光：很快伸長，再變細消失。外層帶勁路的顏色，中心是白的。
## tilt 是往下（正）或往上（負）斜的程度。
func _draw_slash(t: float, tilt: float) -> void:
	var fade := 1.0 - t
	var grow := minf(1.0, t * 3.5)
	var along := Vector2(direction, tilt).normalized()
	var across := Vector2(-along.y, along.x)
	var center := along * radius * 0.5 * (t - 0.4)
	var half_length := radius * 1.3 * (0.3 + 0.7 * grow)
	_draw_streak(center, along, across, half_length, radius * 0.2 * fade, Color(color, 0.55 * fade))
	_draw_streak(center, along, across, half_length * 0.96, radius * 0.1 * fade, Color(color.lightened(0.35), 0.9 * fade))
	_draw_streak(center, along, across, half_length * 0.9, radius * 0.04 * fade, Color(1, 1, 1, fade))


## 兩頭尖、中間寬的一筆。
func _draw_streak(center: Vector2, along: Vector2, across: Vector2, half_length: float, half_width: float, streak_color: Color) -> void:
	if half_width < 0.6 or half_length < 2.0:
		return
	var points := PackedVector2Array([
		center - along * half_length,
		center + across * half_width,
		center + along * half_length,
		center - across * half_width,
	])
	draw_colored_polygon(points, streak_color)
	points.append(points[0])
	draw_polyline(points, streak_color, 1.5, true)


func _draw_ellipse(center: Vector2, half: Vector2, line_color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var angle := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	draw_polyline(points, line_color, width, true)
