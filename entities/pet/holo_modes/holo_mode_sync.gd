# holo_mode_sync.gd — 全息屏终端网络连线/信号同步渲染模块
# 机能放大版扇形波雷达、阶段连结动画、数据发射光束
class_name HoloModeSync extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue  # 遵循系统原生通信色
	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.3)

	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])

	# 中心原点大幅度下移，以腾出上方开阔空间绘制最经典的巨大的半圆扇形通讯信号
	var c_uv = Vector2(0.5, 0.70)
	
	# 根据时间判断4级涟漪周期扫描波：中心点(0类), 第一圈(1类) ... 
	# 留0.4秒空载期表现脉冲周期
	var phase_time = fmod(time * 1.5, 1.4) 
	
	# ── 1. 底部巨型握手基站中心点 ──
	var dot_on = (phase_time > 0.0 and phase_time < 0.9)
	var dot_r = 0.035
	var center_pt = screen._map_uv(pts, c_uv.x, c_uv.y)
	pet.draw_circle(center_pt, dot_r, glow_color if dot_on else dim_color, true, -1.0, true)
	if dot_on: # 中心产生震波持续扩散
		var rip_r = dot_r + fmod(time * 3.0, 1.0) * 0.05
		pet.draw_circle(center_pt, rip_r, Color(glow_color.r, glow_color.g, glow_color.b, alpha*(1.0-fmod(time*3.0,1.0))), false, 1.5, true)
	
	# ── 2. 向外逐渐扩散的超大断点式 WIFI 扇形波 ──
	var rings = 3
	var base_R = 0.16
	for i in range(rings):
		var r = base_R + i * 0.16 # 每一环间距很大，直接满铺上方屏幕
		# 判断当前环是否处于被脉冲波及的高亮波段 (类似流水灯向外扫)
		var threshold = 0.2 + i * 0.25
		var is_active = (phase_time > threshold and phase_time < threshold + 0.45)
		
		var ring_c = glow_color if is_active else dim_color
		if not is_active: ring_c.a *= 0.5
		
		# 将原本平滑的弧线切分为科技感断裂段落
		var segments = 9 + i * 6
		var start_angle = -PI * 0.82
		var end_angle = -PI * 0.18
		var total_angle = end_angle - start_angle
		
		# 越靠外的信号环线越发宽厚，充满磅礴的硬核机能风
		var line_w = 4.0 + i * 2.0
		for s in range(segments):
			var a1 = start_angle + (s / float(segments)) * total_angle
			var a2 = start_angle + ((s + 0.65) / float(segments)) * total_angle # 空留 35% 间隙做断开点
			var p1 = screen._map_uv(pts, c_uv.x + cos(a1)*r, c_uv.y + sin(a1)*r)
			var p2 = screen._map_uv(pts, c_uv.x + cos(a2)*r, c_uv.y + sin(a2)*r)
			pet.draw_line(p1, p2, ring_c, line_w, true)
			
			# 特写光晕：如果被激活，在当前波纹上方额外衍生出一圈极度虚化的超细幻影波增加立体深度感
			if is_active and (s % 2 == 0):
				var outer_r = r + 0.025
				var op1 = screen._map_uv(pts, c_uv.x + cos(a1)*outer_r, c_uv.y + sin(a1)*outer_r)
				var op2 = screen._map_uv(pts, c_uv.x + cos(a2)*outer_r, c_uv.y + sin(a2)*outer_r)
				pet.draw_line(op1, op2, Color(glow_color.r, glow_color.g, glow_color.b, alpha*0.4), 1.0, true)

	# ── 3. 数据包发射粒子 (模拟握手协议发射激光短箭) ──
	# 当脉冲刚越过原点时，发射高亮数据粒子从内向外刺破信号波
	if phase_time > 0.2 and phase_time < 0.95:
		var pack_r = base_R + (phase_time - 0.2) * 1.1 
		# 正左上，正上，正右上 三个主流通信发射朝向
		for dir_a in [-PI*0.5, -PI*0.7, -PI*0.3]:
			var pack_pt = screen._map_uv(pts, c_uv.x + cos(dir_a)*pack_r, c_uv.y + sin(dir_a)*pack_r)
			pet.draw_circle(pack_pt, 2.5, Color.WHITE, true, -1.0, true)
			# 发射拖尾拉丝
			var tail_r = max(pack_r - 0.08, dot_r)
			var tail_pt = screen._map_uv(pts, c_uv.x + cos(dir_a)*tail_r, c_uv.y + sin(dir_a)*tail_r)
			pet.draw_line(pack_pt, tail_pt, glow_color, 2.0, true)

	# ── 4. 底部局域网 MAC地址 / IP 地址同步验证读取条 ──
	var bar_y = 0.88
	var bar_w = 0.45
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	
	# 模拟类似 [ / / / / / / / / / / ] 的高频测算闪烁数字位
	for i in range(8):
		var char_w = 0.03
		var char_x = 0.5 - bar_w*0.4 + i * 0.05
		var p1 = screen._map_uv(pts, char_x - char_w*0.5, bar_y + 0.01)
		var p2 = screen._map_uv(pts, char_x + char_w*0.5, bar_y - 0.01) 
		# 若在周期的停转期，则全部归位暗淡状态；否则产生高速破解般的数据验证闪光感
		var is_flash = phase_time < 1.05 and (hash(i + int(time*18.0)) % 10 > 3)
		var c = glow_color if is_flash else dim_color
		pet.draw_line(p1, p2, c, 2.0, true)
		
	# ── 5. 保持整个宠物个人终端所有应用都强致划一的四角护甲边框 ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
