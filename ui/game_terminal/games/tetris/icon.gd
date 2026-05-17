# icon.gd — 俄罗斯方块大厅图标
# 底部堆叠 + 下落 T 块 + ghost 投影
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

	var gs = minf(w, ht) * 0.75
	var cols_n = 6
	var rows_n = 8
	var cs = gs / maxf(cols_n, rows_n)
	var ox = cx - cols_n * cs * 0.5
	var oy = cy - rows_n * cs * 0.5 + cs
	# 预设底部堆叠
	var stack = [
		[1,1,0,0,1,1],
		[1,1,1,0,1,1],
		[1,1,1,1,1,1],
	]
	for row_i in range(stack.size()):
		var ry = rows_n - stack.size() + row_i
		for col_i in range(cols_n):
			if stack[row_i][col_i] == 1:
				var bx = ox + col_i * cs
				var by = oy + ry * cs
				var is_full_row = (row_i == stack.size() - 1)
				var flash = sin(t * 4.0) * 0.2 + 0.8 if is_full_row else 1.0
				var pc = Color.from_hsv(fmod(h + col_i * 0.08, 1.0), 0.35, 0.6 * flash, alpha_base * flash)
				draw_rect(Rect2(bx, by, cs - 1, cs - 1), pc)
	# 下落 T 块
	var t_cells = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]
	var fall_y = fmod(t * 0.6, 1.0) * (rows_n - 4)
	var t_pulse = sin(t * 3.0) * 0.1 + 0.9
	for c in t_cells:
		var bx = ox + (c.x + 1) * cs
		var by = oy + (c.y + fall_y) * cs
		var ghost_y = oy + (c.y + rows_n - 4) * cs
		draw_rect(Rect2(bx, ghost_y, cs - 1, cs - 1), Color.from_hsv(h, 0.3, 0.6, 0.08))
		var ac = Color.from_hsv(fmod(h + 0.16, 1.0), 0.55, 0.9 * t_pulse, alpha_hi)
		draw_rect(Rect2(bx, by, cs - 1, cs - 1), ac)
	# 网格点
	var grid_c = Color.from_hsv(h, 0.2, 0.5, 0.08)
	for gx in range(1, cols_n):
		for gy in range(1, rows_n):
			draw_circle(Vector2(ox + gx * cs, oy + gy * cs), 0.6, grid_c, true, -1.0, true)
	# 外框
	draw_rect(Rect2(ox, oy, cols_n * cs, rows_n * cs), Color.from_hsv(h, 0.4, 0.6, 0.15), false, 1.0)
