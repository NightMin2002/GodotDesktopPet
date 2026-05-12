# holo_mode_cleanup.gd — 全息屏终端数据清理/回收站渲染模块
# 文件垂直下落、经过粉碎机裂解、落入经典回收站
class_name HoloModeCleanup extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue  # 使用主题色，因为也是系统原生功能
	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.4)

	# 背景微光
	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])

	# ── 1. 扩容与升级质感后的回收站主体 ──
	var bin_c = Vector2(0.5, 0.60)  # 中心提至稍高，为下方保留空间
	var bin_w_top = 0.24  # 大幅拉宽桶口
	var bin_w_bot = 0.16  # 大幅拉宽桶底
	var bin_h = 0.18  # 增加高度
	
	# 画垃圾桶主体 (倒梯形)
	var bin_pts = PackedVector2Array([
		screen._map_uv(pts, bin_c.x - bin_w_top, bin_c.y - bin_h + 0.01),
		screen._map_uv(pts, bin_c.x + bin_w_top, bin_c.y - bin_h + 0.01),
		screen._map_uv(pts, bin_c.x + bin_w_bot, bin_c.y + bin_h),
		screen._map_uv(pts, bin_c.x - bin_w_bot, bin_c.y + bin_h),
	])
	pet.draw_polygon(bin_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	pet.draw_polyline(PackedVector2Array([bin_pts[0], bin_pts[1], bin_pts[2], bin_pts[3], bin_pts[0]]), dim_color, 2.0, true)
	
	# 桶身上的科技方格装甲骨架
	for i in range(1, 6):
		var lx1 = bin_c.x - bin_w_top + (2.0 * bin_w_top * i / 6.0)
		var lx2 = bin_c.x - bin_w_bot + (2.0 * bin_w_bot * i / 6.0)
		# 描画骨架线并且在线条中间断开增加空灵感
		var p_top = screen._map_uv(pts, lx1, bin_c.y - bin_h + 0.05)
		var p_mid_u = screen._map_uv(pts, (lx1+lx2)*0.5, bin_c.y - 0.02)
		var p_mid_d = screen._map_uv(pts, (lx1+lx2)*0.5, bin_c.y + 0.02)
		var p_bot = screen._map_uv(pts, lx2, bin_c.y + bin_h - 0.03)
		var d_color = dim_color
		d_color.a *= 0.7
		pet.draw_line(p_top, p_mid_u, d_color, 1.5, true)
		pet.draw_line(p_mid_d, p_bot, d_color, 1.5, true)
	
	# 桶内的数据波动液面 (容量探测波动)
	var fill_y = bin_c.y + bin_h - 0.05 - (fmod(time * 0.3, 1.0) * (bin_h * 2.0 - 0.1))
	pet.draw_line(screen._map_uv(pts, bin_c.x - bin_w_top*0.8, fill_y), screen._map_uv(pts, bin_c.x + bin_w_top*0.8, fill_y), Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.3), 3.0, true)

	# 激光切割槽 (取代原先的盖子)
	# 工作时不仅微震，还会发出耀眼激光光束
	var slot_y = bin_c.y - bin_h - 0.02 + (sin(time * 60.0) * 0.003 if fmod(time * 0.6, 1.0) < 0.9 else 0.0)
	var lid_pts = PackedVector2Array([
		screen._map_uv(pts, bin_c.x - bin_w_top - 0.03, slot_y - 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_top + 0.03, slot_y - 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_top + 0.03, slot_y + 0.02),
		screen._map_uv(pts, bin_c.x - bin_w_top - 0.03, slot_y + 0.02)
	])
	pet.draw_polygon(lid_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.6)])
	pet.draw_polyline(PackedVector2Array([lid_pts[0], lid_pts[1], lid_pts[2], lid_pts[3], lid_pts[0]]), dim_color, 2.0, true)
	
	# 极度高亮的激光粉碎切割线
	var laser_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha)
	pet.draw_line(screen._map_uv(pts, bin_c.x - bin_w_top - 0.04, slot_y), screen._map_uv(pts, bin_c.x + bin_w_top + 0.04, slot_y), laser_c, 3.0, true)
	pet.draw_line(screen._map_uv(pts, bin_c.x - bin_w_top - 0.02, slot_y), screen._map_uv(pts, bin_c.x + bin_w_top + 0.02, slot_y), Color(1, 1, 1, alpha), 1.0, true)
	
	# 激光散发出的微光粉尘颗粒
	for i in range(4):
		if hash(int(time * 20.0) + i) % 2 == 0:
			var flare_x = bin_c.x + (float(hash(int(time * 15.0) + i) % 100) / 50.0 - 1.0) * bin_w_top
			var flare_y = slot_y - 0.02 + float(hash(i*3)%10)/50.0
			pet.draw_circle(screen._map_uv(pts, flare_x, flare_y), 1.5, Color(1, 1, 1, alpha), true, -1.0, true)


	# ── 2. 数字碎片化裂解演出 (放大的文档尺寸与高精度碎片) ──
	var doc_count = 3
	for i in range(doc_count):
		# 错开下落的时间点
		var cycle_time = fmod(time * 0.5 + i * 0.33, 1.0) 
		var doc_w = 0.12  # 文档宽度提升一倍
		var doc_h = 0.14  # 文档高度提升一倍
		
		# 文件从高处滑落入桶
		var current_y = -0.15 + cycle_time * 1.5
		var top_edge_y = current_y - doc_h
		var bot_edge_y = current_y + doc_h
		var limit_y = bin_c.y + bin_h - 0.04 # 桶底上限
		
		# 文档内容绘制Lambda，复用逻辑
		var draw_doc_content = func(doc_top, doc_bot, is_full):
			var d_pts = PackedVector2Array([
				screen._map_uv(pts, 0.5 - doc_w, doc_top),
				screen._map_uv(pts, 0.5 + doc_w, doc_top),
				screen._map_uv(pts, 0.5 + doc_w, doc_bot),
				screen._map_uv(pts, 0.5 - doc_w, doc_bot)
			])
			pet.draw_polygon(d_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.7)])
			pet.draw_polyline(PackedVector2Array([d_pts[0], d_pts[1], d_pts[2], d_pts[3], d_pts[0]]), glow_color, 2.0, true)
			# 画骨架排版线 (假文本)
			if is_full or current_y - doc_h*0.5 > doc_top:
				var line_y = current_y - doc_h*0.5
				if line_y < slot_y: pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.7, line_y), screen._map_uv(pts, 0.5 + doc_w*0.7, line_y), dim_color, 2.0, true)
			if is_full or current_y > doc_top:
				var line_y = current_y
				if line_y < slot_y: pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.7, line_y), screen._map_uv(pts, 0.5 + doc_w*0.3, line_y), dim_color, 2.0, true)
			if is_full or current_y + doc_h*0.5 > doc_top:
				var line_y = current_y + doc_h*0.5
				if line_y < slot_y: pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.7, line_y), screen._map_uv(pts, 0.5 + doc_w*0.5, line_y), dim_color, 2.0, true)

		if bot_edge_y < slot_y:
			# 【完全完好阶段】
			draw_doc_content.call(top_edge_y, bot_edge_y, true)
			
		elif top_edge_y < slot_y:
			# 【进入粉碎口交界阶段：上截完好，下截被激光转化为极细数据碎片阵列】
			draw_doc_content.call(top_edge_y, slot_y, false)
			
			# 下面的高精度碎纸条/数字条带
			var shred_count = 14
			for s in range(shred_count):
				var sx = 0.5 - doc_w + (s+0.5) * (doc_w * 2.0 / shred_count)
				# 数据流下垂错落感
				var len_mult = 0.5 + 0.5 * sin(s * 13.0 + time * 10.0)
				var s_bot_y = slot_y + (bot_edge_y - slot_y) * len_mult
				if s_bot_y > slot_y:
					var s_color = glow_color if (hash(s * 7) % 2 == 0) else dim_color
					# 用稍微有些小豁口的分段画法，增加数据撕裂感
					pet.draw_line(screen._map_uv(pts, sx, slot_y), screen._map_uv(pts, sx, min(s_bot_y, limit_y)), s_color, 2.0, true)
					
		else:
			# 【完全粉碎完成，自由掉落到底部消失阶段】
			var shred_count = 14
			for s in range(shred_count):
				var sx = 0.5 - doc_w + (s+0.5) * (doc_w * 2.0 / shred_count)
				var s_top = max(top_edge_y, slot_y)
				var s_bot = min(bot_edge_y, limit_y)
				# 加上随机滑落漂移偏移，模拟碎纸在空中乱飞打旋
				var drift_x = sin(current_y * 15.0 + s * 2.0) * 0.02
				if s_bot > s_top:
					# 掉落中光色变暗淡且高度剥离
					var c = dim_color
					c.a *= max(0.0, (limit_y - s_top) / (limit_y - slot_y)) # 越接近底部越隐形透明
					pet.draw_line(screen._map_uv(pts, sx + drift_x, s_top), screen._map_uv(pts, sx + drift_x*1.5, s_bot), c, 1.5, true)

	# ── 3. 底部进度读取文案框 (CLEANING...) ──
	var bar_y = 0.88
	var bar_w = 0.4
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	pet.draw_polyline(bar_pts, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.6), 1.0, true)
	
	# 用阶梯线段去填满格子模拟加载进度
	var max_blocks = 8
	var b_w = (bar_w - 0.04) / max_blocks
	var prog = fmod(time * 0.4, 1.0)
	var act_blocks = int(prog * max_blocks)
	for k in range(max_blocks):
		var kx = 0.5 - bar_w*0.5 + 0.02 + k * b_w
		var p1 = screen._map_uv(pts, kx + 0.005, bar_y + 0.01)
		var p2 = screen._map_uv(pts, kx + b_w - 0.005, bar_y - 0.01)
		if k <= act_blocks:
			pet.draw_line(p1, p2, glow_color, 2.5, true)
		else:
			pet.draw_line(p1, p2, dim_color, 1.0, true)

	# ── 4. 边框护甲与锚点 (保持终端统一) ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
