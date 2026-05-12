# holo_mode_query.gd — 全息屏终端查询/未知渲染模块
# 动态重组的问号、扫描探测网、悬浮碎片。使用系统UI主题色。
class_name HoloModeQuery extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue  # 使用宠物系统当前的主题色，不做强制颜色覆盖

	# 引入机械步进卡顿感
	var step_time = floor(time * 12.0) / 12.0

	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.4)
	
	# 背景微光
	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])
	
	var c_uv = Vector2(0.5, 0.42)
	
	# ── 1. 六边形雷达探测网 ──
	var bg_r = 0.28
	var bg_pts = PackedVector2Array()
	for i in range(7): # 闭合六边形
		var a = i * TAU / 6.0
		bg_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*bg_r, c_uv.y + sin(a)*bg_r))
	
	# 绘制六边形线框，脉冲亮度
	var pulse = (sin(step_time * 2.0) * 0.5 + 0.5)
	pet.draw_polyline(bg_pts, Color(dim_color.r, dim_color.g, dim_color.b, dim_color.a * (0.5 + 0.5*pulse)), 1.0, true)
	
	# 网格扫描线 (从上到下一个来回)
	var scan_y = c_uv.y - bg_r + (sin(time * 1.5) * 0.5 + 0.5) * bg_r * 2.0
	var scan_w = bg_r * 1.2
	var p_left = screen._map_uv(pts, c_uv.x - scan_w, scan_y)
	var p_right = screen._map_uv(pts, c_uv.x + scan_w, scan_y)
	pet.draw_line(p_left, p_right, Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.5), 1.5, true)
	
	# ── 2. 方块像素风拼成的「？」 ──
	# 带有闪烁重组感
	var q_color = glow_color
	# 每次极小幅度透明度闪烁
	q_color.a *= 0.7 + 0.3 * (float(hash(int(time * 15.0)) % 100) / 100.0)
	
	var w_base = 0.04
	var h_base = 0.04
	
	var draw_block = func(ux: float, uy: float, uw: float, uh: float):
		var b_pts = PackedVector2Array([
			screen._map_uv(pts, c_uv.x + ux, c_uv.y + uy),
			screen._map_uv(pts, c_uv.x + ux + uw, c_uv.y + uy),
			screen._map_uv(pts, c_uv.x + ux + uw, c_uv.y + uy + uh),
			screen._map_uv(pts, c_uv.x + ux, c_uv.y + uy + uh)
		])
		pet.draw_polygon(b_pts, [q_color])
	
	# 如果正在随机闪烁，则产生几块轻微错位
	var offset = 0.0
	if hash(int(time * 10.0)) % 10 > 8:
		offset = 0.03
	
	# 用几个矩形块拼出问号 (?)
	# 顶部横条
	draw_block.call(-w_base*2.0 + offset, -h_base*4, w_base*4.0, h_base*1.2)
	# 左上竖条
	draw_block.call(-w_base*2.5, -h_base*3, w_base*1.2, h_base*2.0)
	# 右上竖条
	draw_block.call(w_base*1.5 - offset, -h_base*3, w_base*1.2, h_base*3.0)
	# 中间横条
	draw_block.call(-w_base*0.5, -h_base*1, w_base*2.5, h_base*1.2)
	# 下方竖条
	draw_block.call(-w_base*0.5 + offset*0.5, h_base*0.5, w_base*1.2, h_base*1.5)
	
	# 底部点
	if hash(int(time * 8.0)) % 5 != 0:
		draw_block.call(-w_base*0.5, h_base*3, w_base*1.2, h_base*1.2)

	# ── 3. 悬浮的 01 数据碎片 ──
	for i in range(5):
		# 让碎片在一定范围内随机移动
		var rx = (float(hash(i * 10) % 100) / 100.0) - 0.5
		var ry = (float(hash(i * 20) % 100) / 100.0) - 0.5
		var frag_x = c_uv.x + rx * 0.7
		var frag_y = c_uv.y + ry * 0.7 + sin(time * 2.0 + i) * 0.05
		var frag_pt = screen._map_uv(pts, frag_x, frag_y)
		
		# 时隐时现
		if fmod(time * 1.5 + i * 0.3, 1.0) > 0.2:
			pet.draw_line(frag_pt, screen._map_uv(pts, frag_x + 0.02, frag_y), base_color, 1.0, true)
			if i % 2 == 0:
				pet.draw_line(screen._map_uv(pts, frag_x, frag_y + 0.02), screen._map_uv(pts, frag_x + 0.02, frag_y + 0.02), dim_color, 1.0, true)

	# ── 4. 底部检索文字遮罩条 ──
	var bar_y = 0.82
	var bar_w = 0.45
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.2)])
	
	# 左侧类似 "查找" 的闪烁方块
	if fmod(time * 2.0, 1.0) < 0.5:
		var sq_pts = PackedVector2Array([
			screen._map_uv(pts, 0.5 - bar_w*0.5 + 0.02, bar_y - 0.01),
			screen._map_uv(pts, 0.5 - bar_w*0.5 + 0.04, bar_y - 0.01),
			screen._map_uv(pts, 0.5 - bar_w*0.5 + 0.035, bar_y + 0.01),
			screen._map_uv(pts, 0.5 - bar_w*0.5 + 0.015, bar_y + 0.01)
		])
		pet.draw_polygon(sq_pts, [glow_color])

	# ── 5. 边框护甲与锚点 (保持终端统一) ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
