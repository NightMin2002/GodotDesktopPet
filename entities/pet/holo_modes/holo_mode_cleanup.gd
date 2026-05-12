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

	# ── 1. 经典回收站 (位于偏下位置) ──
	var bin_c = Vector2(0.5, 0.65)
	var bin_w_top = 0.14
	var bin_w_bot = 0.10
	var bin_h = 0.14
	
	# 画垃圾桶主体 (倒梯形)
	var bin_pts = PackedVector2Array([
		screen._map_uv(pts, bin_c.x - bin_w_top, bin_c.y - bin_h + 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_top, bin_c.y - bin_h + 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_bot, bin_c.y + bin_h),
		screen._map_uv(pts, bin_c.x - bin_w_bot, bin_c.y + bin_h),
	])
	pet.draw_polygon(bin_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.1)])
	pet.draw_polyline(PackedVector2Array([bin_pts[0], bin_pts[1], bin_pts[2], bin_pts[3], bin_pts[0]]), dim_color, 1.5, true)
	
	# 垃圾桶上的经典回收竖线条纹
	for i in range(1, 4):
		var lx1 = bin_c.x - bin_w_top + (2.0 * bin_w_top * i / 4.0)
		var lx2 = bin_c.x - bin_w_bot + (2.0 * bin_w_bot * i / 4.0)
		pet.draw_line(screen._map_uv(pts, lx1, bin_c.y - bin_h + 0.05), screen._map_uv(pts, lx2, bin_c.y + bin_h - 0.03), dim_color, 1.0, true)
	
	# 垃圾桶盖子 (即粉碎机入口)
	# 工作时不间断微震动，表达强力的机械粉碎感
	var lid_y = bin_c.y - bin_h - 0.01 + (sin(time * 40.0) * 0.005 if fmod(time * 0.6, 1.0) < 0.8 else 0.0)
	var lid_pts = PackedVector2Array([
		screen._map_uv(pts, bin_c.x - bin_w_top - 0.02, lid_y - 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_top + 0.02, lid_y - 0.02),
		screen._map_uv(pts, bin_c.x + bin_w_top + 0.02, lid_y + 0.02),
		screen._map_uv(pts, bin_c.x - bin_w_top - 0.02, lid_y + 0.02)
	])
	pet.draw_polygon(lid_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.4)])
	pet.draw_polyline(PackedVector2Array([lid_pts[0], lid_pts[1], lid_pts[2], lid_pts[3], lid_pts[0]]), glow_color, 2.0, true)
	# 粉碎口黑色长槽，深度感
	pet.draw_line(screen._map_uv(pts, bin_c.x - bin_w_top, lid_y), screen._map_uv(pts, bin_c.x + bin_w_top, lid_y), Color(0,0,0,alpha*0.6), 3.0, true)

	# ── 2. 连续下坠待销毁文档的生命周期 ──
	var doc_count = 3
	var slot_y = lid_y # 粉碎切割线面
	for i in range(doc_count):
		# 错开下落的时间点
		var cycle_time = fmod(time * 0.6 + i * 0.33, 1.0) 
		var doc_w = 0.06
		var doc_h = 0.08
		
		# 文件从高处滑落入桶
		var current_y = -0.05 + cycle_time * 1.2
		var top_edge_y = current_y - doc_h
		var bot_edge_y = current_y + doc_h
		var limit_y = bin_c.y + bin_h - 0.02 # 桶底上限
		
		if bot_edge_y < slot_y:
			# 【完全完好阶段】
			var d_pts = PackedVector2Array([
				screen._map_uv(pts, 0.5 - doc_w, top_edge_y),
				screen._map_uv(pts, 0.5 + doc_w, top_edge_y),
				screen._map_uv(pts, 0.5 + doc_w, bot_edge_y),
				screen._map_uv(pts, 0.5 - doc_w, bot_edge_y)
			])
			pet.draw_polygon(d_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.6)])
			pet.draw_polyline(PackedVector2Array([d_pts[0], d_pts[1], d_pts[2], d_pts[3], d_pts[0]]), glow_color, 1.5, true)
			# 文档假文本线条
			pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.6, current_y - doc_h*0.4), screen._map_uv(pts, 0.5 + doc_w*0.6, current_y - doc_h*0.4), dim_color, 1.0, true)
			pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.6, current_y), screen._map_uv(pts, 0.5 + doc_w*0.3, current_y), dim_color, 1.0, true)
			pet.draw_line(screen._map_uv(pts, 0.5 - doc_w*0.6, current_y + doc_h*0.4), screen._map_uv(pts, 0.5 + doc_w*0.5, current_y + doc_h*0.4), dim_color, 1.0, true)
			
		elif top_edge_y < slot_y:
			# 【进入粉碎口交界阶段：上截完好，下截变碎纸条】
			var d_pts = PackedVector2Array([
				screen._map_uv(pts, 0.5 - doc_w, top_edge_y),
				screen._map_uv(pts, 0.5 + doc_w, top_edge_y),
				screen._map_uv(pts, 0.5 + doc_w, slot_y),
				screen._map_uv(pts, 0.5 - doc_w, slot_y)
			])
			pet.draw_polygon(d_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.6)])
			pet.draw_polyline(PackedVector2Array([d_pts[0], d_pts[1], d_pts[2], d_pts[3], d_pts[0]]), glow_color, 1.5, true)
			
			# 下面的碎发纸条
			var shred_count = 6
			for s in range(shred_count):
				var sx = 0.5 - doc_w + (s+0.5) * (doc_w * 2.0 / shred_count)
				# 加上少许波浪表现摇曳感
				var s_bot_y = slot_y + (bot_edge_y - slot_y) * (0.8 + 0.2*sin(s * 10.0 + time * 5.0))
				if s_bot_y > slot_y:
					pet.draw_line(screen._map_uv(pts, sx, slot_y), screen._map_uv(pts, sx, min(s_bot_y, limit_y)), glow_color, 1.5, true)
					
		else:
			# 【完全粉碎完成，自由掉落到底部消失阶段】
			var shred_count = 6
			for s in range(shred_count):
				var sx = 0.5 - doc_w + (s+0.5) * (doc_w * 2.0 / shred_count)
				var s_top = max(top_edge_y, slot_y)
				var s_bot = min(bot_edge_y, limit_y)
				if s_bot > s_top:
					# 掉落中光色变暗淡，即将销毁的感觉
					pet.draw_line(screen._map_uv(pts, sx, s_top), screen._map_uv(pts, sx, s_bot), dim_color, 1.0, true)

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
