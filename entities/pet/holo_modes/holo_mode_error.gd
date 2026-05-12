# holo_mode_error.gd — 全息屏终端报错/阻断渲染模块
# 机能风警示叉号 / 故障毛刺闪烁 / 断裂警告波纹
class_name HoloModeError extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 状态 ──
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = 0.02  # 强制警示红 (Hue: 偏橙红)
	
	# 故障毛刺效果参数
	var is_glitching = (hash(int(time * 25.0)) % 10) > 7
	var glitch_offset = Vector2.ZERO
	if is_glitching:
		glitch_offset = Vector2(
			(float(hash(int(time * 30.0)) % 10000) / 10000.0 - 0.5) * 0.08,
			(float(hash(int(time * 30.0 + 10)) % 10000) / 10000.0 - 0.5) * 0.04
		)
		alpha *= 0.5 + 0.5 * (float(hash(int(time * 20.0)) % 10000) / 10000.0)
	
	pet.draw_polygon(pts, [Color(0.12, 0.01, 0.01, alpha * 0.6)])
	
	var base_color = Color.from_hsv(hue, 0.9, 0.8, alpha)
	var glow_color = Color.from_hsv(hue, 1.0, 1.0, alpha * 0.9)
	var c_uv = Vector2(0.5, 0.45) + glitch_offset
	
	# ── 1. 警告脉冲底纹 (八角形断裂警示环) ──
	var pulse = clampf(fmod(time * 2.0, 1.0), 0.0, 1.0)
	var bg_r = 0.18 + pulse * 0.12
	var bg_alpha = (1.0 - pulse) * alpha * 0.5
	var bg_color = Color(base_color.r, base_color.g, base_color.b, bg_alpha)
	
	for i in range(8):
		var a1 = i * TAU / 8.0 + PI/8.0
		var a2 = a1 + PI/16.0  # 只画一半的线段，形成断裂感
		var pt1 = screen._map_uv(pts, c_uv.x + cos(a1)*bg_r, c_uv.y + sin(a1)*bg_r)
		var pt2 = screen._map_uv(pts, c_uv.x + cos(a2)*bg_r, c_uv.y + sin(a2)*bg_r)
		pet.draw_line(pt1, pt2, bg_color, 2.0, true)

	# ── 2. 硬派故障叉号 ──
	var w = 0.18
	var h = 0.18
	
	# 组建大叉号的两条交线
	var line1_start = Vector2(c_uv.x - w, c_uv.y - h)
	var line1_end   = Vector2(c_uv.x + w, c_uv.y + h)
	
	var line2_start = Vector2(c_uv.x + w, c_uv.y - h)
	var line2_end   = Vector2(c_uv.x - w, c_uv.y + h)
	
	# 加入类似短路击穿的进度延迟
	var cross_prog1 = clampf(time * 6.0, 0.0, 1.0)
	var cross_prog2 = clampf(time * 6.0 - 0.4, 0.0, 1.0)
	
	# 绘制第一条对角线
	if cross_prog1 > 0.0:
		var p1 = screen._map_uv(pts, line1_start.x, line1_start.y)
		var p2 = screen._map_uv(pts, lerp(line1_start.x, line1_end.x, cross_prog1), lerp(line1_start.y, line1_end.y, cross_prog1))
		pet.draw_line(p1, p2, glow_color, 4.0, true)
		pet.draw_line(p1, p2, Color(base_color.r, base_color.g, base_color.b, alpha * 0.4), 10.0, true)
		
	# 绘制第二条对角线
	if cross_prog2 > 0.0:
		var p1 = screen._map_uv(pts, line2_start.x, line2_start.y)
		var p2 = screen._map_uv(pts, lerp(line2_start.x, line2_end.x, cross_prog2), lerp(line2_start.y, line2_end.y, cross_prog2))
		pet.draw_line(p1, p2, glow_color, 4.0, true)
		pet.draw_line(p1, p2, Color(base_color.r, base_color.g, base_color.b, alpha * 0.4), 10.0, true)
	
	# ── 3. 乱序跳动的错误代码层 ──
	var noise_y = c_uv.y + 0.25
	for b in range(5):
		var nx = c_uv.x - 0.2 + (float(hash(b + int(time * 5.0)) % 10000) / 10000.0) * 0.4
		var ny = noise_y + (float(hash(b * 3 + int(time * 5.0)) % 10000) / 10000.0 - 0.5) * 0.04
		var nw = 0.02 + (float(hash(b * 7 + int(time * 5.0)) % 10000) / 10000.0) * 0.06
		
		# 只在不闪烁的一瞬间绘制，表现出乱象
		if hash(b + int(time * 10.0)) % 2 == 0:
			var np1 = screen._map_uv(pts, nx, ny)
			var np2 = screen._map_uv(pts, nx + nw, ny)
			pet.draw_line(np1, np2, glow_color, 1.5, true)

	# ── 4. 底部警告条 (STATUS: ERROR / DENIED) ──
	# 使用底色快速高亮警报条
	var alert_flash = (int(time * 8.0) % 2 == 0)
	var bar_y = 0.82
	var bar_w = 0.6
	var bar_start = 0.5 - bar_w * 0.5
	var bar_end = 0.5 + bar_w * 0.5
	
	# 斑马警告纹理
	var stripe_pts = PackedVector2Array()
	var stripe_count = 14
	var total_w = bar_w
	var sw = total_w / stripe_count
	
	var stripe_color = glow_color if alert_flash else base_color
	stripe_color.a *= 0.8
	
	for i in range(stripe_count):
		# 斜纹进度
		var sx_top = bar_start + i * sw + sw * 0.2
		var sx_bot = bar_start + i * sw - sw * 0.2 + sw * 0.2
		
		# 把斜纹压成短竖线或斜块
		var pt1 = screen._map_uv(pts, sx_top, bar_y - 0.015)
		var pt2 = screen._map_uv(pts, sx_bot, bar_y + 0.015)
		pet.draw_line(pt1, pt2, stripe_color, 4.0, true)
	
	# 两端截断线
	pet.draw_line(
		screen._map_uv(pts, bar_start - 0.02, bar_y - 0.03), 
		screen._map_uv(pts, bar_start - 0.02, bar_y + 0.03), 
		glow_color, 2.0, true
	)
	pet.draw_line(
		screen._map_uv(pts, bar_end + 0.02, bar_y - 0.03), 
		screen._map_uv(pts, bar_end + 0.02, bar_y + 0.03), 
		glow_color, 2.0, true
	)

	# ── 5. 角落边框框定 ──
	var corner_len = 0.1 * deploy
	var c_color = Color(base_color.r, base_color.g, base_color.b, alpha * 0.6)
	for i in range(4):
		var cp = pts[i]
		var next_i = (i + 1) % 4
		var prev_i = (i + 3) % 4
		var to_next = (pts[next_i] - cp).normalized() * (pts[next_i] - cp).length() * corner_len
		var to_prev = (pts[prev_i] - cp).normalized() * (pts[prev_i] - cp).length() * corner_len
		pet.draw_line(cp, cp + to_next, c_color, 2.0, true)
		pet.draw_line(cp, cp + to_prev, c_color, 2.0, true)
		
	# 红色边缘警示闪动
	if alert_flash:
		for ei in range(4):
			pet.draw_line(pts[ei], pts[(ei + 1) % 4], Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.15), 1.0, true)
