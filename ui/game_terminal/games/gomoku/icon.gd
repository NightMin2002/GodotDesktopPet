# icon.gd — 五子棋大厅图标
extends TerminalGameIcon

func _draw() -> void:
	var w = size.x
	var h = size.y
	var a = alphas()
	var cx = w * 0.5
	var cy = h * 0.5
	var s = minf(w, h) * 0.35

	# 简化网格 (3x3)
	var lc = line_color()
	lc.a = a[0] * 0.3
	for i in range(3):
		var offset = -s + s * i
		draw_line(Vector2(cx - s, cy + offset), Vector2(cx + s, cy + offset), lc, 1.0, true)
		draw_line(Vector2(cx + offset, cy - s), Vector2(cx + offset, cy + s), lc, 1.0, true)

	# 棋子
	var r = s * 0.22
	var pc = accent_color(); pc.a = a[1]
	var ac = Color.from_hsv(fmod(hue() + 0.45, 1.0), 0.4, 0.9, a[1])
	# 五子连珠暗示 (对角线三子)
	draw_circle(Vector2(cx, cy), r, pc, true, -1.0, true)
	draw_circle(Vector2(cx - s * 0.7, cy - s * 0.7), r * 0.85, pc, true, -1.0, true)
	draw_circle(Vector2(cx + s * 0.7, cy + s * 0.7), r * 0.85, pc, true, -1.0, true)
	# AI棋子
	draw_circle(Vector2(cx + s * 0.65, cy - s * 0.35), r * 0.85, ac, true, -1.0, true)
	draw_circle(Vector2(cx - s * 0.35, cy + s * 0.65), r * 0.85, ac, true, -1.0, true)
