# holo_mode_alarm.gd — 全息屏终端日程/闹钟渲染模块
# 机能风震动悬浮钟形、脉冲声波、日程倒查
class_name HoloModeAlarm extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue  # 使用宠物系统默认的主题色，表示日程属于日常功能
	
	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.4)
	
	# 背景微光
	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])
	
	var c_uv = Vector2(0.5, 0.43)
	
	# ── 1. 震动的机能风小铃铛 / 闹钟 ──
	# 制造急促的左右震动位移
	var shake = sin(time * 50.0) * 0.015
	# 每隔一阵子震动停一下，造成“叮铃铃~停~叮铃铃~”的节奏
	if fmod(time * 1.5, 1.0) < 0.3:
		shake = 0.0
		
	var bell_c = Vector2(c_uv.x + shake, c_uv.y)
	
	# 绘制铃铛上半圆壳
	var r = 0.12
	var bell_pts = PackedVector2Array()
	var sides = 12
	for i in range(sides + 1):
		var a = PI + (i / float(sides)) * PI
		bell_pts.append(screen._map_uv(pts, bell_c.x + cos(a)*r, bell_c.y + sin(a)*r))
	
	# 向下延伸成裙边
	var p_right_base = Vector2(bell_c.x + r, bell_c.y + r*0.4)
	var p_left_base  = Vector2(bell_c.x - r, bell_c.y + r*0.4)
	var p_right_lip = Vector2(bell_c.x + r*1.3, bell_c.y + r*0.6)
	var p_left_lip  = Vector2(bell_c.x - r*1.3, bell_c.y + r*0.6)
	
	bell_pts.append(screen._map_uv(pts, p_right_base.x, p_right_base.y))
	bell_pts.append(screen._map_uv(pts, p_right_lip.x, p_right_lip.y))
	bell_pts.append(screen._map_uv(pts, p_left_lip.x, p_left_lip.y))
	bell_pts.append(screen._map_uv(pts, p_left_base.x, p_left_base.y))
	bell_pts.append(screen._map_uv(pts, bell_c.x - r, bell_c.y)) # 闭合
	
	# 填充底色发光与轮廓
	pet.draw_polygon(bell_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.4)])
	pet.draw_polyline(bell_pts, glow_color, 2.0, true)
	
	# 铃铛顶部的把手环
	var ring_pts = PackedVector2Array()
	var ring_r = r * 0.4
	var ring_c = Vector2(bell_c.x, bell_c.y - r - ring_r*0.4)
	for i in range(9):
		var a = PI + (i/8.0)*PI
		ring_pts.append(screen._map_uv(pts, ring_c.x + cos(a)*ring_r, ring_c.y + sin(a)*ring_r))
	pet.draw_polyline(ring_pts, glow_color, 1.5, true)
	
	# 铃铛下侧中间的“摇锤”
	# 摇锤跟本体有少许反向延迟震动
	var clapper_c = Vector2(bell_c.x - shake*1.5, bell_c.y + r*0.8)
	pet.draw_circle(screen._map_uv(pts, clapper_c.x, clapper_c.y), 3.0, glow_color, true, -1.0, true)
	pet.draw_line(screen._map_uv(pts, bell_c.x, bell_c.y + r*0.5), screen._map_uv(pts, clapper_c.x, clapper_c.y), glow_color, 1.5, true)

	# ── 2. 声波脉冲圈 (扩音震动效果) ──
	# 根据震动幅度决定波纹是否扩展
	if shake != 0.0:
		var wave_count = 3
		for i in range(wave_count):
			var wave_time = fmod(time * 3.0 - i * 0.33, 1.0)
			if wave_time >= 0.0:
				var wr = r * 1.5 + wave_time * 0.35
				var w_alpha = (1.0 - wave_time) * alpha
				var w_color = Color(glow_color.r, glow_color.g, glow_color.b, w_alpha)
				
				# 画左右两边的弧线声波
				var l_pts = PackedVector2Array()
				var r_pts = PackedVector2Array()
				for a_i in range(5):
					var a1 = PI*0.8 + (a_i/4.0)*PI*0.4
					var a2 = -PI*0.2 + (a_i/4.0)*PI*0.4
					l_pts.append(screen._map_uv(pts, bell_c.x + cos(a1)*wr, bell_c.y + sin(a1)*wr))
					r_pts.append(screen._map_uv(pts, bell_c.x + cos(a2)*wr, bell_c.y + sin(a2)*wr))
				pet.draw_polyline(l_pts, w_color, 1.5, true)
				pet.draw_polyline(r_pts, w_color, 1.5, true)
	
	# ── 3. 倒计时脉冲点阵 (环绕时钟刻度感) ──
	var dot_dist = r * 2.1
	var steps = 12
	# 走针表现出明显的滴答秒针感
	var active_step = int(time * 3.0) % steps
	for i in range(steps):
		var a = i * TAU / steps - PI/2.0
		var dp = Vector2(c_uv.x + cos(a)*dot_dist, c_uv.y + sin(a)*dot_dist)
		if i == active_step:
			pet.draw_circle(screen._map_uv(pts, dp.x, dp.y), 2.0, glow_color, true, -1.0, true)
		else:
			pet.draw_circle(screen._map_uv(pts, dp.x, dp.y), 1.0, dim_color, true, -1.0, true)

	# ── 4. 底部提醒事件信息条 ──
	var bar_y = 0.82
	var bar_w = 0.5
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.025),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.025),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.025),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.025)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	pet.draw_polyline(bar_pts, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.6), 1.0, true)
	
	# EVENT: ! 的前缀闪动提示符号
	var label_x = 0.5 - bar_w*0.5 + 0.03
	if fmod(time * 1.5, 1.0) < 0.7:
		pet.draw_line(screen._map_uv(pts, label_x, bar_y - 0.01), screen._map_uv(pts, label_x, bar_y + 0.005), glow_color, 1.5, true)
		pet.draw_circle(screen._map_uv(pts, label_x, bar_y + 0.012), 1.0, glow_color, true, -1.0, true)

	# 匀速滑动的数据短块代码，代表"日程载入提示文本"
	var text_start_x = label_x + 0.04
	for i in range(4):
		var scroll_x = fmod(time * 0.4 + i * 0.25, 1.0)
		var bx = text_start_x + scroll_x * (bar_w - 0.08)
		if bx < (0.5 + bar_w*0.48):
			var b_width = 0.02 + (i%2) * 0.03 # 长短错落的方块
			var p1 = screen._map_uv(pts, bx, bar_y)
			var p2 = screen._map_uv(pts, bx + b_width, bar_y)
			pet.draw_line(p1, p2, glow_color, 3.0, true)

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
