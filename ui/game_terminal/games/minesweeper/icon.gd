# icon.gd — 扫雷大厅图标
# 放大网格 + 脉冲雷芯 + 辐射刺 + 旗帜
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

	var gs = minf(w, ht) * 0.7
	var cs = gs / 3.0
	var ox = cx - gs * 0.5
	var oy = cy - gs * 0.5
	# 网格
	for i in range(4):
		draw_line(Vector2(ox + i * cs, oy), Vector2(ox + i * cs, oy + gs), line_c, 0.5)
		draw_line(Vector2(ox, oy + i * cs), Vector2(ox + gs, oy + i * cs), line_c, 0.5)
	# 雷芯 — 脉冲 + 泛光 + 十字/对角刺
	var mc = Vector2(ox + cs * 1.5, oy + cs * 1.5)
	var mine_pulse = sin(t * 3.0) * 0.12 + 0.88
	var mr = cs * 0.3 * mine_pulse
	draw_circle(mc, mr + 4, Color(0.9, 0.2, 0.15, 0.1 * mine_pulse), true, -1.0, true)
	draw_circle(mc, mr, Color(0.9, 0.25, 0.2, alpha_hi), true, -1.0, true)
	var spike_c = Color(0.95, 0.3, 0.25, 0.55 * mine_pulse)
	var sl = mr * 1.6
	draw_line(mc - Vector2(sl, 0), mc + Vector2(sl, 0), spike_c, 1.5, true)
	draw_line(mc - Vector2(0, sl), mc + Vector2(0, sl), spike_c, 1.5, true)
	var dsl = sl * 0.7
	draw_line(mc - Vector2(dsl, dsl), mc + Vector2(dsl, dsl), spike_c, 1.0, true)
	draw_line(mc - Vector2(dsl, -dsl), mc + Vector2(dsl, -dsl), spike_c, 1.0, true)
	# 高光点
	draw_circle(mc + Vector2(-mr * 0.3, -mr * 0.3), mr * 0.18, Color(1.0, 0.6, 0.5, 0.5), true, -1.0, true)
	# 旗帜 at [0,0]
	var fc = Vector2(ox + cs * 0.5, oy + cs * 0.5)
	draw_line(fc + Vector2(0, -cs * 0.35), fc + Vector2(0, cs * 0.25), Color(0.7, 0.8, 0.9, alpha_base), 1.5, true)
	var flag_pts = PackedVector2Array([
		fc + Vector2(0, -cs * 0.35),
		fc + Vector2(cs * 0.32, -cs * 0.17),
		fc + Vector2(0, 0),
	])
	draw_colored_polygon(flag_pts, accent_c)
	# 数字 "2"
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(ox + cs * 2.12, oy + cs * 0.72), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.65), Color(0.2, 0.75, 0.3, alpha_hi))
