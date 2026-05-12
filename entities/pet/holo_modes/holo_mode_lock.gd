# holo_mode_lock.gd — 全息屏终端锁定/隐私防卫渲染模块
# 极简机械锁扣下落、虚拟链条封锁、静谧的系统守卫状态
class_name HoloModeLock extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue
	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.3)

	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])
	
	# lock_prog 控制锁死全过程: 0=全开, 1=卡死
	var lock_prog = clampf(time * 2.5 - 0.2, 0.0, 1.0)
	
	# ── 1. 背景交叉数据铁链 (新增，带有淡入透明度，更具象征味道) ──
	var draw_chain = func(p1: Vector2, p2: Vector2, c_alpha: float):
		var num_links = 11
		var total_len = p1.distance_to(p2)
		var dir = (p2 - p1).normalized()
		var perp = Vector2(-dir.y, dir.x)
		var link_w = 0.022 # 环的粗细
		var link_l = total_len / float(num_links) * 0.65 # 单个链扣占全长的比
		var c = Color(dim_color.r, dim_color.g, dim_color.b, alpha * c_alpha)
		
		for i in range(num_links):
			var center = p1.lerp(p2, (i + 0.5) / float(num_links))
			if i % 2 == 0:
				# 宽的、正向面对准星的铁链环 (长方形边框)
				var cp1 = center - dir * link_l * 0.5 - perp * link_w * 0.5
				var cp2 = center + dir * link_l * 0.5 - perp * link_w * 0.5
				var cp3 = center + dir * link_l * 0.5 + perp * link_w * 0.5
				var cp4 = center - dir * link_l * 0.5 + perp * link_w * 0.5
				pet.draw_polyline(PackedVector2Array([cp1, cp2, cp3, cp4, cp1]), c, 2.0, true)
			# 删除了纵向的小链扣，仅保留一个中央粗轴点串联，使其更像单条高科数据锁定链
			else:
				var cp1 = center - dir * link_l * 0.3
				var cp2 = center + dir * link_l * 0.3
				pet.draw_line(cp1, cp2, Color(c.r, c.g, c.b, c.a * 1.5), 3.5, true)

	if lock_prog > 0.3:
		# 当锁扣降落时，最底层的锁链渐渐浮出透明的实体线框
		var chain_a = (lock_prog - 0.3) / 0.7 * 0.25 # 最高亮度被死死压在极度朦胧的0.25
		
		# 第一根斜向锁链: 粗犷的非对等角度 (左偏上至偏右下)
		var c1_start = screen._map_uv(pts, 0.05, 0.20)
		var c1_end = screen._map_uv(pts, 0.95, 0.85)
		draw_chain.call(c1_start, c1_end, chain_a)
		
		# 第二根斜向锁链: 对抗错位角度 (左下至上)
		var c2_start = screen._map_uv(pts, 0.10, 0.90)
		var c2_end = screen._map_uv(pts, 0.85, 0.05)
		draw_chain.call(c2_start, c2_end, chain_a)


	# 中心原件坐标
	var c_uv = Vector2(0.5, 0.45) 
	
	# ── 2. 锁扣的动画 (放大后的 U 型锁臂) ──
	var shackle_r = 0.09 # (相比之前的 0.06 暴增了50% 的尺寸)
	var shackle_base_y = c_uv.y - 0.05
	# 锁梁随着进度下压插死槽孔
	var drop_y = shackle_base_y - (1.0 - lock_prog) * 0.12  
	
	var arc_pts = PackedVector2Array()
	var segments = 16
	for i in range(segments + 1):
		var a = PI + (i / float(segments)) * PI
		arc_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*shackle_r, drop_y + sin(a)*shackle_r))

	# 画粗壮的弧形锁梁（2.5 提到 3.5 巨厚重感）
	pet.draw_polyline(arc_pts, glow_color, 3.5, true)
	
	# 有根底座直插的右臂
	pet.draw_line(arc_pts[segments], screen._map_uv(pts, c_uv.x + shackle_r, shackle_base_y + 0.02), glow_color, 3.5, true)
	# 断联并动态降落的左臂插销
	var left_foot = screen._map_uv(pts, c_uv.x - shackle_r, drop_y)
	var left_hole = screen._map_uv(pts, c_uv.x - shackle_r, shackle_base_y)
	pet.draw_line(arc_pts[0], left_foot, glow_color, 3.5, true)
	
	# 显示底部准备被捅入的虚拟空洞插槽
	if lock_prog < 1.0:
		pet.draw_circle(left_hole, 2.5, dim_color, true, -1.0, true) 

	# ── 3. 大体量的数据匣大锁体 ──
	var body_w = 0.17 # (0.12 涨到 0.17)
	var body_h = 0.12 # (0.08 涨到 0.12)
	var body_pts = PackedVector2Array([
		screen._map_uv(pts, c_uv.x - body_w, c_uv.y),
		screen._map_uv(pts, c_uv.x + body_w, c_uv.y),
		screen._map_uv(pts, c_uv.x + body_w, c_uv.y + body_h * 2.0),
		screen._map_uv(pts, c_uv.x - body_w, c_uv.y + body_h * 2.0)
	])
	
	# 加入了半透明填充质地，保证主体锁能盖过背后铁链的杂乱感，突出视觉中心点
	pet.draw_polygon(body_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.4)])
	pet.draw_polyline(PackedVector2Array([body_pts[0], body_pts[1], body_pts[2], body_pts[3], body_pts[0]]), dim_color, 2.5, true)
	
	# 粗实静默的指纹识别核心内环孔
	var hole_y = c_uv.y + body_h
	pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), 0.045, dim_color, false, 2.0, true)
	if lock_prog >= 1.0: # 闭合锁定时启动高光验证标志
		pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), 3.0, glow_color, true, -1.0, true)

	# 锁死之后的防御扩容涟漪表现
	if lock_prog >= 1.0:
		var wave_prog = fmod(time - 0.5, 2.0) 
		if wave_prog < 1.0 and wave_prog > 0.0:
			var wr = body_w * 1.5 + wave_prog * 0.2
			var wa = (1.0 - wave_prog) * alpha
			pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), wr, Color(glow_color.r, glow_color.g, glow_color.b, wa), false, 2.0, true)

	# ── 4. 底部身份核验状态条 ──
	var bar_y = 0.85 # 为了照顾大锁稍稍偏下放置
	var bar_w = 0.5
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	
	# 静默闭环测算点排布
	var dot_count = 5
	var space = bar_w * 0.6 / dot_count
	for i in range(dot_count):
		var dx = 0.5 - bar_w*0.3 + i * space
		var b_prog = clampf((lock_prog * 1.5) - (i * 0.1), 0.0, 1.0)
		var c = dim_color.lerp(glow_color, b_prog)
		var p1 = screen._map_uv(pts, dx - 0.015, bar_y + 0.01)
		var p2 = screen._map_uv(pts, dx + 0.015, bar_y - 0.01)
		pet.draw_line(p1, p2, c, 2.0, true)

	# ── 5. 常规四角防卫边框 ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)

