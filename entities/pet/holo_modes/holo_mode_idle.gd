# holo_mode_idle.gd — 全息屏待机屏保渲染模块
# 透视网格 / 神经数据流 / 雷达准星 / 心电波形 / 边框护甲
class_name HoloModeIdle extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 屏保状态 ──
var time: float = 0.0
var data_lines: Array[float] = []

func init() -> void:
	time = 0.0
	data_lines.clear()
	for i in range(8):
		data_lines.append(randf())

func render(pts: PackedVector2Array, hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.55
	pet.draw_polygon(pts, [Color(0.02, 0.04, 0.08, alpha)])
	var ca = alpha * deploy  # content_alpha

	# ── 1. 背景标定网格 (透视点阵十字) ──
	var crosses = PackedVector2Array()
	var cx_size = 0.01
	var cy_size = 0.015
	for gx in range(1, 10):
		for gy in range(1, 10):
			var u = gx * 0.1
			var v = gy * 0.1
			crosses.append(screen._map_uv(pts, u - cx_size, v))
			crosses.append(screen._map_uv(pts, u + cx_size, v))
			crosses.append(screen._map_uv(pts, u, v - cy_size))
			crosses.append(screen._map_uv(pts, u, v + cy_size))
	if crosses.size() > 0:
		pet.draw_multiline(crosses, Color.from_hsv(hue, 0.3, 0.9, ca * 0.12), 0.8, true)

	# ── 2. 水平扫描仪 (带拖尾透视) ──
	var scan_v = fmod(time * 0.5, 1.0)
	pet.draw_line(screen._map_uv(pts, 0.0, scan_v), screen._map_uv(pts, 1.0, scan_v), Color.from_hsv(hue, 0.4, 0.9, ca * 0.6), 1.2, true)
	for i in range(1, 6):
		var tv = scan_v - float(i) * 0.02
		if tv > 0.0:
			var tail_a = ca * 0.2 * (1.0 - float(i) / 6.0)
			pet.draw_line(screen._map_uv(pts, 0.0, tv), screen._map_uv(pts, 1.0, tv), Color.from_hsv(hue, 0.3, 0.8, tail_a), 0.8, true)

	# ── 3. 垂直神经数据流 (流星雨刻度) ──
	var u_step = 1.0 / (data_lines.size() + 1.0)
	for i in range(data_lines.size()):
		var u = u_step * (i + 1)
		var speed = 0.4 + data_lines[i] * 0.6
		var phase = data_lines[i] * TAU
		var progress = fmod(time * speed + phase, 1.0)
		var length = 0.15 + data_lines[i] * 0.1
		var top_v = progress
		if top_v < 1.0:
			var render_bot_v = minf(top_v + length, 1.0)
			var line_alpha = ca * 0.4 * (0.5 + 0.5 * sin(time * 2.0 + phase))
			if line_alpha > 0.05:
				var p1 = screen._map_uv(pts, u, top_v)
				var p2 = screen._map_uv(pts, u, render_bot_v)
				pet.draw_line(p1, p2, Color.from_hsv(hue, 0.25, 0.7, line_alpha), 1.2, true)
				if render_bot_v < 0.99:
					pet.draw_circle(p2, 1.5, Color.from_hsv(hue, 0.4, 0.9, line_alpha * 1.5), true, -1.0, true)

	# ── 4. 焦点雷达 / 核心心跳 ──
	var center_u = 0.5
	var center_v = 0.45
	var pulse = (sin(time * 3.0) + 1.0) * 0.5
	var r_u = 0.06 + pulse * 0.015
	var r_v = 0.09 + pulse * 0.02
	var cross = PackedVector2Array([
		screen._map_uv(pts, center_u - r_u * 1.2, center_v), screen._map_uv(pts, center_u + r_u * 1.2, center_v),
		screen._map_uv(pts, center_u, center_v - r_v * 1.2), screen._map_uv(pts, center_u, center_v + r_v * 1.2)
	])
	pet.draw_multiline(cross, Color.from_hsv(hue, 0.35, 0.85, ca * 0.5), 1.0, true)
	var diamond = PackedVector2Array([
		screen._map_uv(pts, center_u, center_v - r_v * 0.8),
		screen._map_uv(pts, center_u + r_u * 0.8, center_v),
		screen._map_uv(pts, center_u, center_v + r_v * 0.8),
		screen._map_uv(pts, center_u - r_u * 0.8, center_v),
		screen._map_uv(pts, center_u, center_v - r_v * 0.8)
	])
	pet.draw_polyline(diamond, Color.from_hsv(hue, 0.5, 0.9, ca * 0.3 * (0.5 + pulse*0.5)), 1.2, true)

	# ── 5. 底侧状态波形 (心电频段) ──
	var wave_v = 0.85
	var wave_pts = PackedVector2Array()
	for i in range(41):
		var wu = 0.05 + (i / 40.0) * 0.9
		var dist_to_center = abs(wu - 0.5) * 2.0
		var amp = 0.0
		if dist_to_center < 0.35:
			var activity = sin(time * 4.0 + wu * 15.0) * sin(time * 15.0)
			amp = 0.08 * (1.0 - dist_to_center / 0.35) * activity
		else:
			amp = 0.01 * sin(time * 2.0 + wu * 18.0)
		wave_pts.append(screen._map_uv(pts, wu, wave_v + amp))
	pet.draw_polyline(wave_pts, Color.from_hsv(hue, 0.4, 0.9, ca * 0.6), 1.5, true)
	pet.draw_line(screen._map_uv(pts, 0.05, wave_v), screen._map_uv(pts, 0.95, wave_v), Color.from_hsv(hue, 0.3, 0.7, ca * 0.2), 1.0, true)

	# ── 6. 边框护甲与锚点 ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color.from_hsv(hue, 0.35, 0.75, ca * 0.3), 1.5, true)
	var cc = Color.from_hsv(hue, 0.4, 0.9, ca * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
