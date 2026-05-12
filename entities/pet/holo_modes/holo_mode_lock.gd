# holo_mode_lock.gd — 全息屏终端锁定/隐私防卫渲染模块
# 极简机械锁扣下落、屏障栅栏封锁线、静谧的系统守卫状态
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
	
	var c_uv = Vector2(0.5, 0.40)
	
	# ── 1. 锁扣的动画 (模拟 U 型锁梁的下落咬合) ──
	# lock_prog 控制锁死全过程: 0=全开, 1=卡死
	var lock_prog = clampf(time * 2.5 - 0.2, 0.0, 1.0)
	
	var shackle_r = 0.06
	var shackle_base_y = c_uv.y - 0.05
	# 锁梁随着进度从上面往下降落并彻底锁死
	var drop_y = shackle_base_y - (1.0 - lock_prog) * 0.08  
	
	var arc_pts = PackedVector2Array()
	var segments = 12
	# 画上半部的弧形 U 锁梁
	for i in range(segments + 1):
		var a = PI + (i / float(segments)) * PI # 从左到右的顶部半圆
		arc_pts.append(screen._map_uv(pts, c_uv.x + cos(a)*shackle_r, drop_y + sin(a)*shackle_r))

	# 锁梁弧顶
	pet.draw_polyline(arc_pts, glow_color, 2.5, true)
	
	# 右侧支角（一直插在身体里，跟着 drop_y 下移或保持一定长度）
	pet.draw_line(arc_pts[segments], screen._map_uv(pts, c_uv.x + shackle_r, shackle_base_y + 0.02), glow_color, 2.5, true)
	
	# 左侧支角（插销部）
	var left_foot = screen._map_uv(pts, c_uv.x - shackle_r, drop_y)
	var left_hole = screen._map_uv(pts, c_uv.x - shackle_r, shackle_base_y)
	pet.draw_line(arc_pts[0], left_foot, glow_color, 2.5, true)
	
	# 如果没锁到底，底部画个孔暗示它还没插进去
	if lock_prog < 1.0:
		pet.draw_circle(left_hole, 2.0, dim_color, true, -1.0, true) 

	# ── 2. 行李箱/数据匣锁体 (极简线框保护壳) ──
	var body_w = 0.12
	var body_h = 0.08
	var body_pts = PackedVector2Array([
		screen._map_uv(pts, c_uv.x - body_w, c_uv.y),
		screen._map_uv(pts, c_uv.x + body_w, c_uv.y),
		screen._map_uv(pts, c_uv.x + body_w, c_uv.y + body_h * 2.0),
		screen._map_uv(pts, c_uv.x - body_w, c_uv.y + body_h * 2.0)
	])
	pet.draw_polygon(body_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.3)])
	pet.draw_polyline(PackedVector2Array([body_pts[0], body_pts[1], body_pts[2], body_pts[3], body_pts[0]]), dim_color, 2.0, true)
	
	# 中心授权扫描孔 (钥匙孔/虹膜口抽象)
	var hole_y = c_uv.y + body_h
	pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), 0.03, glow_color, false, 2.0, true)
	# 锁死后，中心显示已激活的高亮小实心圆
	if lock_prog >= 1.0:
		pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), 1.5, glow_color, true, -1.0, true)

	# ── 3. 锁定成功后的涟漪与封锁线阵列 ──
	if lock_prog >= 1.0:
		# 定期扩散的守护波动
		var wave_prog = fmod(time - 0.5, 2.0) 
		if wave_prog < 1.0 and wave_prog > 0.0:
			var wr = body_w * 1.5 + wave_prog * 0.2
			var wa = (1.0 - wave_prog) * alpha
			pet.draw_circle(screen._map_uv(pts, c_uv.x, hole_y), wr, Color(glow_color.r, glow_color.g, glow_color.b, wa), false, 1.5, true)

	# 在背景绘制冷淡的对角斜线，暗示区域已经进行物理隔绝/静默
	if lock_prog > 0.5:
		var fence_alpha = (lock_prog - 0.5) * 2.0 * alpha * 0.15
		for i in range(-6, 7):
			var px = 0.5 + i * 0.15
			var line_top = screen._map_uv(pts, px - 0.15, 0.0)
			var line_bot = screen._map_uv(pts, px + 0.15, 1.0)
			pet.draw_line(line_top, line_bot, Color(dim_color.r, dim_color.g, dim_color.b, fence_alpha), 1.0, true)

	# ── 4. 底部身份核验状态条 ──
	var bar_y = 0.82
	var bar_w = 0.5
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	
	# 不再高速乱闪，而是展现出稳定、封闭的占位色块，表达已上锁
	var dot_count = 5
	var space = bar_w * 0.6 / dot_count
	for i in range(dot_count):
		var dx = 0.5 - bar_w*0.3 + i * space
		# 锁扣落下后，从左到右依次落锁变色
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
