# icon.gd — 井字棋大厅图标
# 放大网格 + 脉冲标记 + 扫描线
extends TerminalGameIcon

func _draw() -> void:
	var h = hue()
	var a = alphas()
	var alpha_base = a[0]
	var alpha_hi = a[1]
	var w = size.x
	var ht = size.y
	var cx = w * 0.5
	var cy = ht * 0.5
	var t = _time
	var line_c = line_color()
	var accent_c = accent_color()

	var gs = minf(w, ht) * 0.75
	var cs = gs / 3.0
	var ox = cx - gs * 0.5
	var oy = cy - gs * 0.5
	# 网格线
	for i in range(1, 3):
		draw_line(Vector2(ox + i * cs, oy + 3), Vector2(ox + i * cs, oy + gs - 3), line_c, 1.0)
		draw_line(Vector2(ox + 3, oy + i * cs), Vector2(ox + gs - 3, oy + i * cs), line_c, 1.0)
	# 十字瞄准节点 (网格交叉点)
	var cross_c = Color.from_hsv(h, 0.3, 0.7, alpha_base * 0.7)
	for gx in range(1, 3):
		for gy in range(1, 3):
			var px = ox + cs * gx
			var py = oy + cs * gy
			draw_line(Vector2(px - 3, py), Vector2(px + 3, py), cross_c, 1.0, true)
			draw_line(Vector2(px, py - 3), Vector2(px, py + 3), cross_c, 1.0, true)
	# X at [0,0] — 分离线段 + 脉冲
	var x_pulse = sin(t * 2.0) * 0.12 + 0.88
	var x_c = Color.from_hsv(h, 0.3, 0.9, alpha_hi * x_pulse)
	var gap_x = cs * 0.06
	var arm = cs * 0.5 - cs * 0.22
	var c00 = Vector2(ox + cs * 0.5, oy + cs * 0.5)
	draw_line(c00 + Vector2(-gap_x, -gap_x), c00 + Vector2(-gap_x - arm, -gap_x - arm), x_c, 2.0, true)
	draw_line(c00 + Vector2(gap_x, gap_x), c00 + Vector2(gap_x + arm, gap_x + arm), x_c, 2.0, true)
	draw_line(c00 + Vector2(gap_x, -gap_x), c00 + Vector2(gap_x + arm, -gap_x - arm), x_c, 2.0, true)
	draw_line(c00 + Vector2(-gap_x, gap_x), c00 + Vector2(-gap_x - arm, gap_x + arm), x_c, 2.0, true)
	# O at [1,1] — 留缺口圆弧 + 脉冲
	var o_pulse = sin(t * 2.5 + 1.0) * 0.08 + 0.92
	var o_r = cs * 0.32 * o_pulse
	var o_c = Color(0.9, 0.55, 0.3, alpha_hi)
	draw_arc(Vector2(ox + cs * 1.5, oy + cs * 1.5), o_r, -PI * 0.48 + 0.12, PI * 1.52 - 0.12, 28, o_c, 2.0, true)
	# X at [2,0]
	var c20 = Vector2(ox + cs * 2.5, oy + cs * 0.5)
	draw_line(c20 + Vector2(-gap_x, -gap_x), c20 + Vector2(-gap_x - arm, -gap_x - arm), x_c, 2.0, true)
	draw_line(c20 + Vector2(gap_x, gap_x), c20 + Vector2(gap_x + arm, gap_x + arm), x_c, 2.0, true)
	draw_line(c20 + Vector2(gap_x, -gap_x), c20 + Vector2(gap_x + arm, -gap_x - arm), x_c, 2.0, true)
	draw_line(c20 + Vector2(-gap_x, gap_x), c20 + Vector2(-gap_x - arm, gap_x + arm), x_c, 2.0, true)
	# 扫描线
	var scan_y = oy + fmod(t * 30.0, gs)
	draw_line(Vector2(ox, scan_y), Vector2(ox + gs, scan_y), Color.from_hsv(h, 0.3, 0.8, 0.1), 1.0)
