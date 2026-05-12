# holo_mode_mail.gd — 全息屏邮件通知渲染模块
# 机能风信封 / 呼吸闪烁 / 新消息接收动画
class_name HoloModeMail extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 状态 ──
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = 0.55  # 提示色调 (略微偏蓝/青的提醒色)
	pet.draw_polygon(pts, [Color(0.02, 0.05, 0.08, alpha * 0.6)])
	
	var base_color = Color.from_hsv(hue, 0.6, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var c_uv = Vector2(0.5, 0.42)
	
	# ── 1. 背景波纹 (呼吸效果) ──
	var pulse = 0.5 + 0.5 * sin(time * 6.0)
	var bg_r = 0.18 + 0.02 * pulse
	var bg_pts = PackedVector2Array()
	for i in range(8):
		var a = i * TAU / 8.0 + PI/8.0
		bg_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*bg_r, c_uv.y + sin(a)*bg_r))
	pet.draw_polygon(bg_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15 * pulse)])
	pet.draw_polyline(bg_pts, Color(base_color.r, base_color.g, base_color.b, alpha * 0.3), 1.0, true)
	
	# ── 2. 信封主体 ──
	var env_w = 0.22
	var env_h = 0.16
	var env_y_offset = sin(time * 3.0) * 0.02  # 悬浮动画
	
	var tl = Vector2(c_uv.x - env_w, c_uv.y - env_h + env_y_offset)
	var tr = Vector2(c_uv.x + env_w, c_uv.y - env_h + env_y_offset)
	var br = Vector2(c_uv.x + env_w, c_uv.y + env_h + env_y_offset)
	var bl = Vector2(c_uv.x - env_w, c_uv.y + env_h + env_y_offset)
	var tc = Vector2(c_uv.x, c_uv.y + env_y_offset)  # 信封内心交点
	
	# 外框
	var env_outline = PackedVector2Array([
		screen._map_uv(pts, tl.x, tl.y),
		screen._map_uv(pts, tr.x, tr.y),
		screen._map_uv(pts, br.x, br.y),
		screen._map_uv(pts, bl.x, bl.y),
		screen._map_uv(pts, tl.x, tl.y)
	])
	
	# 画出发光外框
	pet.draw_polygon(env_outline, [Color(0.01, 0.02, 0.04, alpha * 0.8)])
	pet.draw_polyline(env_outline, Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * 0.8), 2.0, true)
	
	# 信封翻盖 (V字形)
	var flap_pts = PackedVector2Array([
		screen._map_uv(pts, tl.x, tl.y),
		screen._map_uv(pts, tc.x, tc.y),
		screen._map_uv(pts, tr.x, tr.y)
	])
	pet.draw_polyline(flap_pts, glow_color, 2.0, true)
	
	# 信封底部对角线
	var bottom_flap1 = PackedVector2Array([
		screen._map_uv(pts, bl.x, bl.y),
		screen._map_uv(pts, tc.x, tc.y + 0.02)
	])
	var bottom_flap2 = PackedVector2Array([
		screen._map_uv(pts, br.x, br.y),
		screen._map_uv(pts, tc.x, tc.y + 0.02)
	])
	pet.draw_polyline(bottom_flap1, Color(base_color.r, base_color.g, base_color.b, alpha * 0.6), 1.5, true)
	pet.draw_polyline(bottom_flap2, Color(base_color.r, base_color.g, base_color.b, alpha * 0.6), 1.5, true)
	
	# ── 3. 新消息提醒圆点 (右上角) ──
	var dot_active = int(time * 4.0) % 2 == 0
	if dot_active:
		var dot_uv = Vector2(tr.x + 0.02, tr.y - 0.02)
		var dot_center = screen._map_uv(pts, dot_uv.x, dot_uv.y)
		pet.draw_circle(dot_center, 4.0, Color.from_hsv(0.05, 0.8, 1.0, alpha)) # 红色警告点
	
	# ── 4. 底部滚动数据流 (模拟发件人/主题扫描) ──
	var bar_y = 0.8
	var bar_w = 0.5
	var bar_start = 0.5 - bar_w * 0.5
	var bar_end = 0.5 + bar_w * 0.5
	pet.draw_line(
		screen._map_uv(pts, bar_start, bar_y), 
		screen._map_uv(pts, bar_end, bar_y), 
		Color(base_color.r, base_color.g, base_color.b, alpha * 0.3), 
		2.0, true
	)
	
	# 数据块扫描 (机械卡顿感 + 碎裂离散块)
	var step_time = floor(time * 12.0) / 12.0
	var scan_prog = fmod(step_time * 0.5, 1.0)
	
	var blocks = PackedVector2Array()
	var block_count = 6
	for b in range(block_count):
		# 利用 hash 给每块固定的相对偏移和长度，并添加卡顿步进游走
		var rand_offset = float(hash(b)) / 2147483648.0
		var rand_len = 0.01 + float(hash(b + 10)) / 2147483648.0 * 0.04
		
		# 整体偏移
		var final_prog = fmod(scan_prog + rand_offset, 1.0)
		var block_x = bar_start + bar_w * final_prog
		
		# 剔除超出的部分
		if block_x >= bar_start and block_x + rand_len <= bar_end:
			blocks.append(screen._map_uv(pts, block_x, bar_y))
			blocks.append(screen._map_uv(pts, block_x + rand_len, bar_y))
			
	if blocks.size() > 0:
		pet.draw_multiline(blocks, glow_color, 2.5, true)
	
	# 两端角标
	pet.draw_line(
		screen._map_uv(pts, bar_start, bar_y - 0.03), 
		screen._map_uv(pts, bar_start, bar_y + 0.03), 
		base_color, 1.5, true
	)
	pet.draw_line(
		screen._map_uv(pts, bar_end, bar_y - 0.03), 
		screen._map_uv(pts, bar_end, bar_y + 0.03), 
		base_color, 1.5, true
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
