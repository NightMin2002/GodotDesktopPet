# holo_mode_warning.gd — 全息屏终端轻度警告渲染模块
# 极简细线风格，脉冲三角与轻量提示
class_name HoloModeWarning extends RefCounted

var screen: PetHoloScreen

var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = 0.12  # 黄色/琥珀色
	
	# 制造机械步进卡顿感
	var step_time = floor(time * 15.0) / 15.0
	
	var base_color = Color.from_hsv(hue, 0.8, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.9, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.7, 0.6, alpha * 0.4)
	
	# 背景微光
	pet.draw_polygon(pts, [Color(0.1, 0.08, 0.0, alpha * 0.3)])
	
	var c_uv = Vector2(0.5, 0.45)
	
	# ── 1. 极简三角框 (多层科幻细线) ──
	var r = 0.32  # 之前是0.22，大幅放大确保标识清晰
	var pulse = (sin(step_time * 3.0) * 0.5 + 0.5)
	
	var draw_triangle = func(radius: float, color: Color, line_width: float, offset_y: float = 0.0):
		var top = screen._map_uv(pts, c_uv.x, c_uv.y - radius + offset_y)
		var br = screen._map_uv(pts, c_uv.x + radius * 0.866, c_uv.y + radius * 0.5 + offset_y)
		var bl = screen._map_uv(pts, c_uv.x - radius * 0.866, c_uv.y + radius * 0.5 + offset_y)
		pet.draw_line(top, br, color, line_width, true)
		pet.draw_line(br, bl, color, line_width, true)
		pet.draw_line(bl, top, color, line_width, true)
	
	# 逆向辅助倒三角 (极细线，构成科幻层级感)
	var inv_r = r * 0.55
	var inv_color = glow_color
	inv_color.a *= 0.15
	var inv_top = screen._map_uv(pts, c_uv.x, c_uv.y + inv_r)
	var inv_tr = screen._map_uv(pts, c_uv.x + inv_r * 0.866, c_uv.y - inv_r * 0.5)
	var inv_tl = screen._map_uv(pts, c_uv.x - inv_r * 0.866, c_uv.y - inv_r * 0.5)
	pet.draw_line(inv_top, inv_tr, inv_color, 1.0, true)
	pet.draw_line(inv_tr, inv_tl, inv_color, 1.0, true)
	pet.draw_line(inv_tl, inv_top, inv_color, 1.0, true)

	# 边角切割点位 (在主三角形角上外延的小标记)
	for i in range(3):
		var angle = i * TAU / 3.0 - PI / 2.0
		var pt_corner = Vector2(c_uv.x + cos(angle)*r, c_uv.y + sin(angle)*r)
		var pt_out = Vector2(c_uv.x + cos(angle)*r*1.15, c_uv.y + sin(angle)*r*1.15)
		pet.draw_line(screen._map_uv(pts, pt_corner.x, pt_corner.y), screen._map_uv(pts, pt_out.x, pt_out.y), dim_color, 1.0, true)

	# 内层主三角 (线宽略增以保证辨识度)
	draw_triangle.call(r, glow_color, 1.5, 0.0)
	
	# 外层脉冲三角 (非常轻微的向外扩散消散波)
	var outer_r = r + 0.03 + pulse * 0.06
	var outer_color = glow_color
	outer_color.a *= (1.0 - pulse) * 0.6
	draw_triangle.call(outer_r, outer_color, 0.5, 0.0)
	
	# ── 2. 中心惊叹号 (随比例放大) ──
	var exclamation_top = screen._map_uv(pts, c_uv.x, c_uv.y - r * 0.4)
	var exclamation_bot = screen._map_uv(pts, c_uv.x, c_uv.y + r * 0.1)
	pet.draw_line(exclamation_top, exclamation_bot, glow_color, 2.0, true)
	
	var dot_pos = screen._map_uv(pts, c_uv.x, c_uv.y + r * 0.3)
	pet.draw_circle(dot_pos, 1.5, glow_color, true, -1.0, true)
	
	# ── 3. 旋转机能环 (步进旋转) ──
	var ring_r = r * 0.65
	var num_segments = 12
	var ring_step_time = floor(time * 8.0) / 8.0  # 环的卡顿感更明显
	for i in range(num_segments):
		var base_angle = i * TAU / num_segments + ring_step_time * 1.2
		var arc_len = TAU / num_segments * 0.4
		var r_pt1 = screen._map_uv(pts, c_uv.x + cos(base_angle)*ring_r, c_uv.y + sin(base_angle)*ring_r)
		var r_pt2 = screen._map_uv(pts, c_uv.x + cos(base_angle + arc_len)*ring_r, c_uv.y + sin(base_angle + arc_len)*ring_r)
		pet.draw_line(r_pt1, r_pt2, dim_color, 1.0, true)
	
	# ── 4. 底部极简文本标记 (代替粗警报条) ──
	var bar_y = 0.82
	var bar_w = 0.4
	
	var bar_left = screen._map_uv(pts, 0.5 - bar_w/2, bar_y)
	var bar_right = screen._map_uv(pts, 0.5 + bar_w/2, bar_y)
	
	# 底侧很细的边线
	pet.draw_line(bar_left, bar_right, dim_color, 0.5, true)
	
	# 两端的一点点强调标记
	pet.draw_line(bar_left, screen._map_uv(pts, 0.5 - bar_w/2, bar_y - 0.02), dim_color, 1.0, true)
	pet.draw_line(bar_right, screen._map_uv(pts, 0.5 + bar_w/2, bar_y - 0.02), dim_color, 1.0, true)
	
	# 扫描点 (在底线上移动)
	var scan_p = clampf(fmod(step_time * 1.5, 1.0), 0.0, 1.0)
	var px = 0.5 - bar_w/2 + bar_w * scan_p
	var scan_pos = screen._map_uv(pts, px, bar_y)
	# 绘制细小的光点
	pet.draw_circle(scan_pos, 1.5, glow_color, true, -1.0, true)
	# 光点的拖影
	var scan_tail = screen._map_uv(pts, px - 0.05, bar_y)
	pet.draw_line(scan_tail, scan_pos, glow_color, 0.5, true)
	
	# ── 5. 边框护甲与锚点 (与其他终端模式保持统一) ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
