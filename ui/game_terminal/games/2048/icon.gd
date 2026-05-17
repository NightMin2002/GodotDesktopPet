# icon.gd — 2048 大厅图标
# 2x2 矩阵 + 高级数字 + 发光顶块
extends TerminalGameIcon

func _draw() -> void:
	var h = hue()
	var a = alphas()
	var alpha_hi = a[1]
	var w = size.x
	var ht = size.y
	var cx = w * 0.5
	var cy = ht * 0.5
	var t = _time

	var gs = minf(w, ht) * 0.65
	var cs = gs * 0.45
	var gap = gs * 0.06
	var ox = cx - gs * 0.5
	var oy = cy - gs * 0.5
	var tiles = [2, 64, 256, 2048]
	var colors = [
		Color(0.14, 0.20, 0.32, 0.55),
		Color(0.68, 0.22, 0.14, 0.7),
		Color(0.68, 0.58, 0.12, 0.75),
		Color(0.82, 0.78, 0.22, 0.85),
	]
	var font = ThemeDB.fallback_font
	for row in range(2):
		for col in range(2):
			var idx = row * 2 + col
			var rx = ox + col * (cs + gap)
			var ry = oy + row * (cs + gap)
			if tiles[idx] == 2048:
				var glow = sin(t * 2.0) * 0.1 + 0.15
				draw_rect(Rect2(rx - 2, ry - 2, cs + 4, cs + 4), Color(0.9, 0.85, 0.3, glow))
			draw_rect(Rect2(rx, ry, cs, cs), colors[idx])
			var txt = str(tiles[idx])
			var fs = 16 if tiles[idx] < 100 else (13 if tiles[idx] < 1000 else 11)
			var ts = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(font, Vector2(rx + (cs - ts.x) * 0.5, ry + cs * 0.5 + ts.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.9, 0.95, alpha_hi))
	var total = cs * 2 + gap
	draw_rect(Rect2(ox - 1, oy - 1, total + 2, total + 2), Color.from_hsv(h, 0.3, 0.55, 0.15), false, 1.0)
