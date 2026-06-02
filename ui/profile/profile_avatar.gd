# profile_avatar.gd — 宠物线稿头像 (正视大头像)
class_name ProfileAvatar
extends Control

var _hue: float = 0.537
var appearance_style: int = 1

func _ready() -> void:
	_hue = EventBus.ui_hue
	EventBus.ui_theme_changed.connect(func(h): _hue = h; queue_redraw())
	appearance_style = SettingsManager.get_int("appearance_style", 1)
	EventBus.appearance_changed.connect(func(val): appearance_style = val; queue_redraw())

func _draw() -> void:
	var cx = size.x * 0.5
	var cy = size.y * 0.5
	var R = minf(size.x, size.y) * 0.38
	var stroke_c = Color.from_hsv(_hue, 0.4, 0.85, 0.7)
	var stroke_dim = Color.from_hsv(_hue, 0.3, 0.6, 0.4)
	var highlight_c = Color.from_hsv(_hue, 0.2, 1.0, 0.85)
	var center = Vector2(cx, cy)
	var lw := 1.5

	# 1. 外壳与本体边框分流
	var border_r: float
	var base_r: float
	var sclera_r: float
	var iris_medium: float
	var iris_inner: float
	var pupil_inner: float
	var hl_offset_x: float
	var hl_offset_y: float
	var hl_radius: float

	if appearance_style == 0:
		# 经典紧凑设计
		border_r = R * 0.85
		base_r = R * 0.68
		sclera_r = R * 0.54
		iris_medium = R * 0.42
		iris_inner = R * 0.28
		pupil_inner = R * 0.16
		hl_offset_x = -0.08
		hl_offset_y = -0.10
		hl_radius = 0.06

		# 经典版的双层外壳描边
		draw_arc(center, R + 1.2, 0, TAU, 64, stroke_c, lw, true)
		draw_arc(center, R, 0, TAU, 64, stroke_c, lw, true)
		# 经典版的内部细环
		draw_arc(center, border_r, 0, TAU, 64, Color(stroke_c, 0.5), 1.0, true)
	else:
		# 现代饱满边框设计
		border_r = R
		base_r = R * 0.80
		sclera_r = R * 0.635
		iris_medium = R * 0.494
		iris_inner = R * 0.33
		pupil_inner = R * 0.19
		hl_offset_x = -0.09
		hl_offset_y = -0.11
		hl_radius = 0.07

		# 现代版的单层外壳描边
		draw_arc(center, R + 1.2, 0, TAU, 64, stroke_c, lw, true)
		# 现代版的外圈细环 (即本体边框)
		draw_arc(center, border_r, 0, TAU, 64, Color(stroke_c, 0.5), 1.0, true)

	# 3. 深色内圆
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
	draw_arc(center, sclera_r, 0, TAU, 48, stroke_c, lw, true)

	# 6. 虹膜三层
	draw_arc(center, iris_medium, 0, TAU, 40, stroke_c, lw, true)
	draw_arc(center, iris_inner, 0, TAU, 32, stroke_c, lw, true)
	draw_arc(center, pupil_inner, 0, TAU, 24, stroke_dim, lw, true)

	# 7. 高光点
	var hl_pos = center + Vector2(R * hl_offset_x, R * hl_offset_y)
	draw_circle(hl_pos, R * hl_radius, highlight_c)
