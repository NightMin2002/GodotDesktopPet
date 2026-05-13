# profile_avatar.gd — 宠物线稿头像 (正视大头像)
class_name ProfileAvatar
extends Control

var _hue: float = 0.537

func _ready() -> void:
	_hue = EventBus.ui_hue
	EventBus.ui_theme_changed.connect(func(h): _hue = h; queue_redraw())

func _draw() -> void:
	var cx = size.x * 0.5
	var cy = size.y * 0.5
	var R = minf(size.x, size.y) * 0.38
	var stroke_c = Color.from_hsv(_hue, 0.4, 0.85, 0.7)
	var stroke_dim = Color.from_hsv(_hue, 0.3, 0.6, 0.4)
	var highlight_c = Color.from_hsv(_hue, 0.2, 1.0, 0.85)
	var center = Vector2(cx, cy)
	var lw := 1.5

	# 1. 外壳 (双层描边)
	draw_arc(center, R + 1.2, 0, TAU, 64, stroke_c, lw, true)
	draw_arc(center, R, 0, TAU, 64, stroke_c, lw, true)

	# 2. 内部细环
	var border_r = R * 0.85
	draw_arc(center, border_r, 0, TAU, 64, Color(stroke_c, 0.5), 1.0, true)

	# 3. 深色内圆
	var base_r = R * 0.68
	draw_arc(center, base_r, 0, TAU, 48, stroke_dim, lw, true)

	# 4. 四个三角翼 (十字方向)
	var tip_dist = border_r - 1.0
	for i in range(4):
		var angle = float(i) * PI / 2.0 + PI / 4.0
		var tip = center + Vector2(cos(angle), sin(angle)) * tip_dist
		var half_hw = PI / 10.0
		var left_b = center + Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
		var right_b = center + Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
		draw_polyline(PackedVector2Array([left_b, tip, right_b]), stroke_dim, lw, true)

	# 5. 巩膜圆
	var sclera_r = R * 0.54
	draw_arc(center, sclera_r, 0, TAU, 48, stroke_c, lw, true)

	# 6. 虹膜三层
	draw_arc(center, R * 0.42, 0, TAU, 40, stroke_c, lw, true)
	draw_arc(center, R * 0.28, 0, TAU, 32, stroke_c, lw, true)
	draw_arc(center, R * 0.16, 0, TAU, 24, stroke_dim, lw, true)

	# 7. 高光点
	var hl_pos = center + Vector2(-R * 0.08, -R * 0.10)
	draw_circle(hl_pos, R * 0.06, highlight_c)
