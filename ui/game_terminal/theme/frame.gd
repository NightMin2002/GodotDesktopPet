# game_terminal_frame.gd — 战术终端边框渲染器
# 对称八角切角 + 脉冲角标 + 靶向准星 + 扫描线 + 刻度线
# class_name GameTerminalFrame
extends Control

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var hue = EventBus.ui_hue
	var w = size.x
	var h = size.y

	# 1. 对称八角切角多边形 (四角全切)
	var c_l = 24.0
	var pts = PackedVector2Array()
	pts.append(Vector2(c_l, 0))
	pts.append(Vector2(w - c_l, 0))
	pts.append(Vector2(w, c_l))
	pts.append(Vector2(w, h - c_l))
	pts.append(Vector2(w - c_l, h))
	pts.append(Vector2(c_l, h))
	pts.append(Vector2(0, h - c_l))
	pts.append(Vector2(0, c_l))
	pts.append(Vector2(c_l, 0))

	# 2. 深色磨砂背景
	draw_polygon(pts, PackedColorArray([Color(0.025, 0.04, 0.08, 0.96)]))

	# 3. 主边界线
	draw_polyline(pts, Color.from_hsv(hue, 0.45, 0.65, 0.4), 1.2, true)

	# 4. 四角切角加持 (脉冲呼吸)
	var pulse = (sin(_time * 3.0) * 0.5 + 0.5) * 0.5 + 0.5
	var corner_c = Color.from_hsv(hue, 0.6, 0.9, 0.7 * pulse)
	var corner_lw = 2.5
	draw_line(pts[7], pts[0], corner_c, corner_lw, true)  # TL
	draw_line(pts[1], pts[2], corner_c, corner_lw, true)  # TR
	draw_line(pts[3], pts[4], corner_c, corner_lw, true)  # BR
	draw_line(pts[5], pts[6], corner_c, corner_lw, true)  # BL

	# 5. 靶向准星 (四角外侧十字线标记)
	var aim_c = Color.from_hsv(hue, 0.5, 0.85, 0.5 * pulse)
	var aim_len = 10.0
	var aim_gap = 4.0
	# TL
	var tl = Vector2(0, 0)
	draw_line(tl + Vector2(-aim_gap, c_l * 0.5), tl + Vector2(-aim_gap - aim_len, c_l * 0.5), aim_c, 1.0)
	draw_line(tl + Vector2(c_l * 0.5, -aim_gap), tl + Vector2(c_l * 0.5, -aim_gap - aim_len), aim_c, 1.0)
	# TR
	var tr = Vector2(w, 0)
	draw_line(tr + Vector2(aim_gap, c_l * 0.5), tr + Vector2(aim_gap + aim_len, c_l * 0.5), aim_c, 1.0)
	draw_line(tr + Vector2(-c_l * 0.5, -aim_gap), tr + Vector2(-c_l * 0.5, -aim_gap - aim_len), aim_c, 1.0)
	# BR
	var br = Vector2(w, h)
	draw_line(br + Vector2(aim_gap, -c_l * 0.5), br + Vector2(aim_gap + aim_len, -c_l * 0.5), aim_c, 1.0)
	draw_line(br + Vector2(-c_l * 0.5, aim_gap), br + Vector2(-c_l * 0.5, aim_gap + aim_len), aim_c, 1.0)
	# BL
	var bl = Vector2(0, h)
	draw_line(bl + Vector2(-aim_gap, -c_l * 0.5), bl + Vector2(-aim_gap - aim_len, -c_l * 0.5), aim_c, 1.0)
	draw_line(bl + Vector2(c_l * 0.5, aim_gap), bl + Vector2(c_l * 0.5, aim_gap + aim_len), aim_c, 1.0)

	# 6. 水平扫描线 (从上到下循环扫过)
	var scan_period = 4.0
	var scan_t = fmod(_time, scan_period) / scan_period
	var scan_y = lerpf(0, h, scan_t)
	var scan_alpha = 1.0 - absf(scan_t - 0.5) * 2.0
	var scan_glow = Color.from_hsv(hue, 0.5, 0.95, 0.04 * scan_alpha)
	var scan_c = Color.from_hsv(hue, 0.4, 0.95, 0.12 * scan_alpha)
	draw_line(Vector2(0, scan_y), Vector2(w, scan_y), scan_glow, 12.0)
	draw_line(Vector2(0, scan_y), Vector2(w, scan_y), scan_c, 1.5)

	# 7. 底部居中刻度线
	var tick_c = Color.from_hsv(hue, 0.4, 0.7, 0.25)
	var cx = w * 0.5
	for i in range(-20, 21):
		var tx = cx + i * 10.0
		var ty_len = 3.0 if i % 5 != 0 else 6.0
		if tx > c_l + 4 and tx < w - c_l - 4:
			draw_line(Vector2(tx, h), Vector2(tx, h - ty_len), tick_c, 1.0)

	# 8. 左侧居中刻度线
	var cy = h * 0.5
	for i in range(-12, 13):
		var ty = cy + i * 10.0
		var tx_len = 3.0 if i % 5 != 0 else 6.0
		if ty > c_l + 4 and ty < h - c_l - 4:
			draw_line(Vector2(0, ty), Vector2(tx_len, ty), tick_c, 1.0)
