# holo_mode_done.gd — 全息屏终端状态确认渲染模块
# 机能风对勾 / 光晕 / 确认波纹扩散
class_name HoloModeDone extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 状态 ──
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = 0.45  # 强制绿色调表示正确/完成 (Hue: ~160度)
	pet.draw_polygon(pts, [Color(0.02, 0.08, 0.04, alpha * 0.6)])
	
	var base_color = Color.from_hsv(hue, 0.6, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.8)
	var c_uv = Vector2(0.5, 0.45)
	var center_pt = screen._map_uv(pts, c_uv.x, c_uv.y)
	
	# ── 1. 扩散外圈波纹 (机械感) ──
	var ripple_prog = clampf(time * 2.0, 0.0, 1.0)
	if ripple_prog > 0.0 and ripple_prog < 1.0:
		var ripple_r = 0.2 + ripple_prog * 0.15
		var ripple_alpha = (1.0 - ripple_prog) * alpha * 0.5
		var r_color = Color(base_color.r, base_color.g, base_color.b, ripple_alpha)
		var r_pts = PackedVector2Array()
		for i in range(33):
			var a = i * TAU / 32.0
			r_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*ripple_r, c_uv.y + sin(a)*ripple_r))
		pet.draw_polyline(r_pts, r_color, 2.0, true)

	# ── 2. 多边形背板 ──
	var bg_r = 0.22
	var bg_pts = PackedVector2Array()
	for i in range(7): # 六边形
		var a = i * TAU / 6.0 + PI/6.0
		bg_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*bg_r, c_uv.y + sin(a)*bg_r))
	pet.draw_polygon(bg_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	pet.draw_polyline(bg_pts, Color(base_color.r, base_color.g, base_color.b, alpha * 0.4), 1.0, true)

	# ── 3. 动态绘制核心对勾 (带有弹性放大) ──
	var check_prog = clampf(time * 3.0 - 0.2, 0.0, 1.0)
	if check_prog > 0.0:
		# 加入类似弹簧效果
		var check_scale = 1.0
		if check_prog < 1.0:
			var t = check_prog
			check_scale = 1.0 + sin(t * PI) * 0.3
			
		var check_color = Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * minf(check_prog * 2.0, 1.0))
		var w = 0.25 * check_scale
		var h = 0.25 * check_scale
		
		# 设计硬派机能风的折线对勾 (三点)
		# 映射到 UV 空间，保持一致的透视
		var p1_uv = Vector2(c_uv.x - w * 0.45, c_uv.y - h * 0.05)
		var p2_uv = Vector2(c_uv.x - w * 0.1,  c_uv.y + h * 0.3)
		var p3_uv = Vector2(c_uv.x + w * 0.5,  c_uv.y - h * 0.4)
		
		# 根据进度动态截断线段 (实现绘画效果)
		var pt1 = screen._map_uv(pts, p1_uv.x, p1_uv.y)
		var pt2 = screen._map_uv(pts, p2_uv.x, p2_uv.y)
		var pt3 = screen._map_uv(pts, p3_uv.x, p3_uv.y)
		
		var draw_pts = PackedVector2Array()
		draw_pts.append(pt1)
		
		if check_prog < 0.5:
			# 画第一段
			var t1 = check_prog * 2.0
			draw_pts.append(pt1.lerp(pt2, t1))
		else:
			# 第一段完成，画第二段
			draw_pts.append(pt2)
			var t2 = (check_prog - 0.5) * 2.0
			draw_pts.append(pt2.lerp(pt3, t2))
			
		if draw_pts.size() >= 2:
			# 发光模糊层，增加光晕
			pet.draw_polyline(draw_pts, Color(check_color.r, check_color.g, check_color.b, check_color.a * 0.3), 8.0, true)
			# 实心内芯
			pet.draw_polyline(draw_pts, check_color, 4.0, true)
	
	# ── 4. 底部状态条 (STATUS: CONFIRMED，机械步进卡顿感) ──
	var step_time = floor(time * 15.0) / 15.0
	var bar_prog = clampf(step_time * 2.5 - 0.4, 0.0, 1.0)
	if bar_prog > 0.0:
		# 使宽度呈现格栅式的离散增长 (分 12 格)
		var quantized_prog = floor(bar_prog * 12.0) / 12.0
		var bar_y = 0.8
		var bar_w = 0.6 * quantized_prog
		var bar_start = 0.5 - bar_w * 0.5
		var bar_end = 0.5 + bar_w * 0.5
		
		# 将实线打断为刻度断线 (数据块连缀感)
		var bar_pts = PackedVector2Array()
		var segment_count = max(1, floor(quantized_prog * 12.0))
		for i in range(segment_count):
			var seg_w = 0.6 / 12.0
			var seg_start = 0.5 - (0.6 * quantized_prog) * 0.5 + i * seg_w
			var seg_end = seg_start + seg_w * 0.7  # 留 30% 空隙
			bar_pts.append(screen._map_uv(pts, seg_start, bar_y))
			bar_pts.append(screen._map_uv(pts, seg_end, bar_y))
			
		pet.draw_multiline(
			bar_pts, 
			Color(base_color.r, base_color.g, base_color.b, alpha * 0.7), 
			3.5, true
		)
		# 装饰性小竖线
		pet.draw_line(
			screen._map_uv(pts, bar_start, bar_y - 0.03), 
			screen._map_uv(pts, bar_start, bar_y + 0.03), 
			base_color, 2.0, true
		)
		pet.draw_line(
			screen._map_uv(pts, bar_end, bar_y - 0.03), 
			screen._map_uv(pts, bar_end, bar_y + 0.03), 
			base_color, 2.0, true
		)

	# ── 5. 角落边框框定 ──
	var corner_len = 0.1 * deploy
	var c_color = Color(base_color.r, base_color.g, base_color.b, alpha * 0.4)
	for i in range(4):
		var cp = pts[i]
		var next_i = (i + 1) % 4
		var prev_i = (i + 3) % 4
		var to_next = (pts[next_i] - cp).normalized() * (pts[next_i] - cp).length() * corner_len
		var to_prev = (pts[prev_i] - cp).normalized() * (pts[prev_i] - cp).length() * corner_len
		pet.draw_line(cp, cp + to_next, c_color, 1.5, true)
		pet.draw_line(cp, cp + to_prev, c_color, 1.5, true)
