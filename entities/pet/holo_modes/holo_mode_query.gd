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
	
	# ── 1. 六边形拓扑检索网 ──
	var bg_r = 0.28
	var bg_pts = PackedVector2Array()
	for i in range(7): # 闭合六边形
		var a = i * TAU / 6.0
		bg_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*bg_r, c_uv.y + sin(a)*bg_r))
	
	# 绘制六边形线框，脉冲亮度
	var pulse = (sin(step_time * 2.0) * 0.5 + 0.5)
	pet.draw_polyline(bg_pts, Color(dim_color.r, dim_color.g, dim_color.b, dim_color.a * (0.5 + 0.5*pulse)), 1.0, true)
	
	# 寻址探针 (取代老套的上下扫描线，改为数据在六边形拓扑边缘极速穿梭)
	var edge_count = 6
	for j in range(3):
		var t_speed = 3.0 + j * 1.5
		var t_offset = j * 2.5
		var traverse_time = time * t_speed + t_offset
		var dir = 1 if j % 2 == 0 else -1
		
		# 计算当前段和段内进度
		var seg_idx = int(traverse_time) % edge_count
		if dir == -1:
			seg_idx = (edge_count - 1) - seg_idx
			
		var seg_prog = fmod(traverse_time, 1.0)
		var p_start = bg_pts[seg_idx]
		var p_end = bg_pts[(seg_idx + 1) % edge_count] if dir == 1 else bg_pts[seg_idx - 1] if seg_idx > 0 else bg_pts[5]
		
		# 为了让闭环正确连接处理逆向的坐标获取
		if dir == -1:
			var s_tmp = bg_pts[(seg_idx + 1) % edge_count]
			var e_tmp = bg_pts[seg_idx]
			p_start = s_tmp
			p_end = e_tmp
			
		var probe_pos = p_start.lerp(p_end, seg_prog)
		
		# 绘制探针核心
		pet.draw_circle(probe_pos, 1.5 + j * 0.5, glow_color, true, -1.0, true)
		# 绘制探针拖尾闪电
		var tail_len = clampf(seg_prog - 0.1, 0.0, 1.0)
		var tail_pos = p_start.lerp(p_end, tail_len)
		pet.draw_line(probe_pos, tail_pos, glow_color, 1.0, true)
	
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

	# ── 4. 底部检索状态条 (高速查阅中) ──
	var bar_y = 0.82
	var bar_w = 0.5
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.025),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.025),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.025),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.025)
	])
	# 绘制明显的底线框
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	pet.draw_polyline(bar_pts, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.6), 1.0, true)
	
	# 左侧的 "指令符" 输入光标闪烁方块
	var cursor_x = 0.5 - bar_w*0.5 + 0.03
	if fmod(time * 2.0, 1.0) < 0.6:
		var sq_pts = PackedVector2Array([
			screen._map_uv(pts, cursor_x, bar_y - 0.012),
			screen._map_uv(pts, cursor_x + 0.02, bar_y - 0.012),
			screen._map_uv(pts, cursor_x + 0.015, bar_y + 0.012),
			screen._map_uv(pts, cursor_x - 0.005, bar_y + 0.012)
		])
		pet.draw_polygon(sq_pts, [glow_color])

	# 右侧高速跳动的数据乱码块 (模拟穷举搜索比对)
	var data_start_x = cursor_x + 0.04
	var data_w = bar_w - 0.09
	var block_count = 14
	var block_w = data_w / block_count
	
	# 每秒 20 次的高速离散刷新
	var search_step = floor(time * 20.0)
	for i in range(block_count):
		# 让每个格子一半几率显示亮色，一半几率暗色，表现高速密集数据运算
		var b_active = (hash(int(search_step) + i * 7) % 10) > 4
		if b_active:
			var bx = data_start_x + i * block_w
			var b_color = glow_color if (hash(int(search_step) + i * 3) % 10) > 7 else base_color
			b_color.a *= 0.8
			
			var pt_top = screen._map_uv(pts, bx, bar_y - 0.008)
			var pt_bot = screen._map_uv(pts, bx - 0.005, bar_y + 0.008)
			# 斜短线，构成类似条形码/加载段的感觉
			pet.draw_line(pt_top, pt_bot, b_color, 2.0, true)

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
