# frame_minimal.gd — 极简科幻风边框渲染器
# 对称八角切角 + 脉冲角标 + 靶向准星 + 水平扫描线 + 刻度标尺
extends Control

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var hue = EventBus.ui_hue
	var w = size.x
	var h = size.y

	# ── 1. 八角切角多边形轮廓 ──
	var cut = 24.0
	var pts = PackedVector2Array([
		Vector2(cut, 0), Vector2(w - cut, 0),
		Vector2(w, cut), Vector2(w, h - cut),
		Vector2(w - cut, h), Vector2(cut, h),
		Vector2(0, h - cut), Vector2(0, cut),
		Vector2(cut, 0),  # 闭合
	])

	# ── 2. 深色磨砂背景填充 ──
	draw_polygon(pts, PackedColorArray([Color(0.025, 0.04, 0.08, 0.96)]))

	# ── 3. 主边界描边 ──
	draw_polyline(pts, Color.from_hsv(hue, 0.45, 0.65, 0.4), 1.2, true)

	# ── 4. 切角高亮 (脉冲呼吸) ──
	var pulse = (sin(_time * 3.0) * 0.5 + 0.5) * 0.5 + 0.5
	var corner_c = Color.from_hsv(hue, 0.6, 0.9, 0.7 * pulse)
	var corner_lw = 2.5
	draw_line(pts[7], pts[0], corner_c, corner_lw, true)  # 左上
	draw_line(pts[1], pts[2], corner_c, corner_lw, true)  # 右上
	draw_line(pts[3], pts[4], corner_c, corner_lw, true)  # 右下
	draw_line(pts[5], pts[6], corner_c, corner_lw, true)  # 左下

	# ── 5. 靶向准星 (四角外侧十字线) ──
	var aim_c = Color.from_hsv(hue, 0.5, 0.85, 0.5 * pulse)
	var aim_len = 10.0
	var aim_gap = 4.0
	var half_cut = cut * 0.5
	# 左上
	draw_line(Vector2(-aim_gap, half_cut), Vector2(-aim_gap - aim_len, half_cut), aim_c, 1.0)
	draw_line(Vector2(half_cut, -aim_gap), Vector2(half_cut, -aim_gap - aim_len), aim_c, 1.0)
	# 右上
	draw_line(Vector2(w + aim_gap, half_cut), Vector2(w + aim_gap + aim_len, half_cut), aim_c, 1.0)
	draw_line(Vector2(w - half_cut, -aim_gap), Vector2(w - half_cut, -aim_gap - aim_len), aim_c, 1.0)
	# 右下
	draw_line(Vector2(w + aim_gap, h - half_cut), Vector2(w + aim_gap + aim_len, h - half_cut), aim_c, 1.0)
	draw_line(Vector2(w - half_cut, h + aim_gap), Vector2(w - half_cut, h + aim_gap + aim_len), aim_c, 1.0)
	# 左下
	draw_line(Vector2(-aim_gap, h - half_cut), Vector2(-aim_gap - aim_len, h - half_cut), aim_c, 1.0)
	draw_line(Vector2(half_cut, h + aim_gap), Vector2(half_cut, h + aim_gap + aim_len), aim_c, 1.0)

	# ── 6. 水平扫描线 (周期上下扫过) ──
	var scan_period = 4.0
	var scan_t = fmod(_time, scan_period) / scan_period
	var scan_y = lerpf(0, h, scan_t)
	var scan_alpha = 1.0 - absf(scan_t - 0.5) * 2.0
	draw_line(Vector2(0, scan_y), Vector2(w, scan_y),
		Color.from_hsv(hue, 0.5, 0.95, 0.04 * scan_alpha), 12.0)
	draw_line(Vector2(0, scan_y), Vector2(w, scan_y),
		Color.from_hsv(hue, 0.4, 0.95, 0.12 * scan_alpha), 1.5)

	# ── 7. 底部刻度标尺 ──
	var tick_c = Color.from_hsv(hue, 0.4, 0.7, 0.25)
	var cx = w * 0.5
	var safe_l = cut + 4.0
	var safe_r = w - cut - 4.0
	for i in range(-20, 21):
		var tx = cx + i * 10.0
		if tx > safe_l and tx < safe_r:
			var ty_len = 6.0 if i % 5 == 0 else 3.0
			draw_line(Vector2(tx, h), Vector2(tx, h - ty_len), tick_c, 1.0)

	# ── 8. 左侧刻度标尺 ──
	var cy = h * 0.5
	var safe_t = cut + 4.0
	var safe_b = h - cut - 4.0
	for i in range(-12, 13):
		var ty = cy + i * 10.0
		if ty > safe_t and ty < safe_b:
			var tx_len = 6.0 if i % 5 == 0 else 3.0
			draw_line(Vector2(0, ty), Vector2(tx_len, ty), tick_c, 1.0)
