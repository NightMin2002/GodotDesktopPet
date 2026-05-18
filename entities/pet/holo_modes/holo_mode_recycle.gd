# holo_mode_recycle.gd — 全息屏回收归档渲染模块
# 回收站容器 + 文件温和滑入 + 循环回收符号
# 和 CLEANUP 区别: 没有激光粉碎, 文件完整落入容器
class_name HoloModeRecycle extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	# 暖橙色调, 区别于 CLEANUP 的主题色
	var hue = 0.10
	var base_color = Color.from_hsv(hue, 0.6, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.7, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.4, 0.6, alpha * 0.4)

	# 背景
	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.5, 0.08, alpha * 0.35)])

	# ── 1. 回收站容器 (和 CLEANUP 类似的倒梯形桶, 但没有激光槽) ──
	var bin_cx = 0.5
	var bin_cy = 0.58
	var bin_w_top = 0.22
	var bin_w_bot = 0.14
	var bin_h = 0.16

	# 桶身
	var bin_pts = PackedVector2Array([
		screen._map_uv(pts, bin_cx - bin_w_top, bin_cy - bin_h),
		screen._map_uv(pts, bin_cx + bin_w_top, bin_cy - bin_h),
		screen._map_uv(pts, bin_cx + bin_w_bot, bin_cy + bin_h),
		screen._map_uv(pts, bin_cx - bin_w_bot, bin_cy + bin_h),
	])
	pet.draw_polygon(bin_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.12)])
	pet.draw_polyline(PackedVector2Array([bin_pts[0], bin_pts[1], bin_pts[2], bin_pts[3], bin_pts[0]]), dim_color, 1.5, true)

	# 桶身装甲线
	for i in range(1, 5):
		var lx1 = bin_cx - bin_w_top + (2.0 * bin_w_top * i / 5.0)
		var lx2 = bin_cx - bin_w_bot + (2.0 * bin_w_bot * i / 5.0)
		var p_top = screen._map_uv(pts, lx1, bin_cy - bin_h + 0.03)
		var p_bot = screen._map_uv(pts, lx2, bin_cy + bin_h - 0.03)
		pet.draw_line(p_top, p_bot, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.25), 1.0, true)

	# 桶口盖板 (简洁平板, 不是激光槽)
	var lid_y = bin_cy - bin_h - 0.01
	var lid_pts = PackedVector2Array([
		screen._map_uv(pts, bin_cx - bin_w_top - 0.02, lid_y - 0.025),
		screen._map_uv(pts, bin_cx + bin_w_top + 0.02, lid_y - 0.025),
		screen._map_uv(pts, bin_cx + bin_w_top + 0.02, lid_y + 0.015),
		screen._map_uv(pts, bin_cx - bin_w_top - 0.02, lid_y + 0.015),
	])
	pet.draw_polygon(lid_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.4)])
	pet.draw_polyline(PackedVector2Array([lid_pts[0], lid_pts[1], lid_pts[2], lid_pts[3], lid_pts[0]]), dim_color, 1.5, true)

	# ── 2. 回收符号 (桶身中央, 三个弯箭头旋转) ──
	var sym_cx = bin_cx
	var sym_cy = bin_cy + 0.02
	var sym_r = 0.08
	var sym_spin = time * 0.8
	var sym_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.5)

	for i in range(3):
		var a_start = sym_spin + i * TAU / 3.0
		var a_end = a_start + TAU / 3.0 * 0.6  # 每段弧约 72 度
		var arc_pts = PackedVector2Array()
		for s in range(9):
			var t = float(s) / 8.0
			var a = a_start + (a_end - a_start) * t
			arc_pts.append(screen._map_uv(pts, sym_cx + cos(a) * sym_r, sym_cy + sin(a) * sym_r))
		pet.draw_polyline(arc_pts, sym_color, 2.0, true)
		# 箭头头部
		if arc_pts.size() > 1:
			var tip = arc_pts[-1]
			var dir_a = a_end + 0.3
			var arr1 = screen._map_uv(pts, sym_cx + cos(dir_a) * sym_r * 0.7, sym_cy + sin(dir_a) * sym_r * 0.7)
			pet.draw_line(tip, arr1, sym_color, 2.0, true)

	# ── 3. 文件温和滑入 (完整下落, 不粉碎) ──
	var doc_count = 2
	for i in range(doc_count):
		var cycle = fmod(time * 0.4 + i * 0.5, 1.0)
		var doc_w = 0.10
		var doc_h = 0.12

		# 从上方下落到桶口, 然后在桶内淡出
		var fall_y: float
		var doc_alpha: float
		var limit_top = -0.1
		var limit_enter = lid_y
		var limit_bot = bin_cy + bin_h - 0.03

		if cycle < 0.6:
			# 下落阶段: 从上方到桶口
			var t = cycle / 0.6
			fall_y = limit_top + t * (limit_enter - limit_top)
			doc_alpha = alpha * 0.7
		else:
			# 进入桶内: 继续下落 + 淡出
			var t = (cycle - 0.6) / 0.4
			fall_y = limit_enter + t * (limit_bot - limit_enter)
			doc_alpha = alpha * 0.7 * (1.0 - t)

		# 文件矩形
		var d_pts = PackedVector2Array([
			screen._map_uv(pts, 0.5 - doc_w, fall_y - doc_h),
			screen._map_uv(pts, 0.5 + doc_w, fall_y - doc_h),
			screen._map_uv(pts, 0.5 + doc_w, fall_y + doc_h),
			screen._map_uv(pts, 0.5 - doc_w, fall_y + doc_h),
		])
		var doc_fill = Color(base_color.r, base_color.g, base_color.b, doc_alpha * 0.5)
		var doc_border = Color(glow_color.r, glow_color.g, glow_color.b, doc_alpha)
		pet.draw_polygon(d_pts, [doc_fill])
		pet.draw_polyline(PackedVector2Array([d_pts[0], d_pts[1], d_pts[2], d_pts[3], d_pts[0]]), doc_border, 1.5, true)

		# 假文本行
		if doc_alpha > 0.1:
			for li in range(3):
				var ly = fall_y - doc_h * 0.5 + (li + 0.5) * doc_h * 2.0 / 3.0
				var lw = doc_w * (0.7 - li * 0.1)
				pet.draw_line(
					screen._map_uv(pts, 0.5 - lw, ly),
					screen._map_uv(pts, 0.5 + lw, ly),
					Color(dim_color.r, dim_color.g, dim_color.b, doc_alpha * 0.5),
					1.5, true
				)

	# ── 4. 底部状态文本模拟 ──
	var bar_y = 0.9
	var bar_w = 0.35
	# 闪烁的格子进度
	var max_blocks = 6
	var prog = fmod(time * 0.3, 1.0)
	var active = int(prog * max_blocks)
	for k in range(max_blocks):
		var bx = 0.5 - bar_w * 0.5 + k * (bar_w / max_blocks)
		var bw = bar_w / max_blocks * 0.7
		var p1 = screen._map_uv(pts, bx, bar_y - 0.015)
		var p2 = screen._map_uv(pts, bx + bw, bar_y + 0.015)
		var c = glow_color if k < active else Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.15)
		pet.draw_rect(Rect2(p1, p2 - p1), c, true)

	# ── 5. 边框 ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)
