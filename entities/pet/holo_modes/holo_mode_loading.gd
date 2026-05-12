# holo_mode_loading.gd — 全息屏终端引导序列渲染模块
# 机械步进旋转 / 数据核心 / 条码闪烁 / 离散进度条
class_name HoloModeLoading extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 加载状态 ──
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.6
	pet.draw_polygon(pts, [Color(0.02, 0.04, 0.08, alpha)])
	var ca = alpha * deploy
	var base_color = Color.from_hsv(hue, 0.5, 0.9, ca)

	# ── 中心数据核心 (呼吸十字与扫描场) ──
	var pulse = 0.5 + 0.5 * sin(time * 8.0)
	var core_size = 0.03 + 0.01 * pulse
	var c_uv = Vector2(0.5, 0.42)
	var core_pts = PackedVector2Array([
		screen._map_uv(pts, c_uv.x, c_uv.y - core_size),
		screen._map_uv(pts, c_uv.x + core_size, c_uv.y),
		screen._map_uv(pts, c_uv.x, c_uv.y + core_size),
		screen._map_uv(pts, c_uv.x - core_size, c_uv.y)
	])
	pet.draw_polygon(core_pts, [Color(base_color.r, base_color.g, base_color.b, ca * (0.4 + 0.4*pulse))])

	# ── 内圈数据流 (连续旋转多边形) ──
	var inner_r = 0.14
	var inner_spin = -time * TAU * 0.25
	var inner_lines = PackedVector2Array()
	var sides = 6
	for i in range(sides + 1):
		var a = inner_spin + float(i % sides) / sides * TAU
		inner_lines.append(screen._map_uv(pts, c_uv.x + cos(a)*inner_r, c_uv.y + sin(a)*inner_r))
	pet.draw_polyline(inner_lines, Color(base_color.r, base_color.g, base_color.b, ca * 0.4), 1.0, true)

	# ── 外圈引导刻度 (机械卡顿步进旋转) ──
	var outer_r = 0.26
	var step_time = floor(time * 8.0) / 8.0
	var outer_spin = step_time * TAU * 0.2
	var dashes = PackedVector2Array()
	var dash_count = 18
	var dash_fill = 0.6
	for i in range(dash_count):
		var a1 = outer_spin + float(i) / dash_count * TAU
		var a2 = a1 + (TAU / dash_count) * dash_fill
		dashes.append(screen._map_uv(pts, c_uv.x + cos(a1)*outer_r, c_uv.y + sin(a1)*outer_r))
		dashes.append(screen._map_uv(pts, c_uv.x + cos(a2)*outer_r, c_uv.y + sin(a2)*outer_r))
	if dashes.size() > 0:
		pet.draw_multiline(dashes, Color(base_color.r, base_color.g, base_color.b, ca * 0.7), 2.0, true)

	# ── 右侧高频随机数据流 (模拟读取区块) ──
	var barcode_start_u = 0.9
	var barcode_v = 0.2
	var bars = PackedVector2Array()
	for i in range(6):
		var is_active = (hash(i + int(time * 15.0)) % 10) > 4
		if is_active:
			var bu = barcode_start_u + (float(i) / 6) * 0.05
			var b_height = 0.02 + (hash(i * 3 + int(time * 5.0)) % 10) * 0.01
			bars.append(screen._map_uv(pts, bu, barcode_v))
			bars.append(screen._map_uv(pts, bu, barcode_v + b_height))
	if bars.size() > 0:
		pet.draw_multiline(bars, Color(base_color.r, base_color.g, base_color.b, ca * 0.8), 1.5, true)

	# ── 扇区扫描指针 ──
	var pointer_a = outer_spin + PI
	var p_start = screen._map_uv(pts, c_uv.x + cos(pointer_a)*(inner_r+0.02), c_uv.y + sin(pointer_a)*(inner_r+0.02))
	var p_end = screen._map_uv(pts, c_uv.x + cos(pointer_a)*(outer_r-0.02), c_uv.y + sin(pointer_a)*(outer_r-0.02))
	pet.draw_line(p_start, p_end, Color(base_color.r, base_color.g, base_color.b, ca * 0.9), 1.5, true)

	# ── 底侧刻度和进度条 ──
	var bar_y = 0.82
	var bar_w = 0.64
	var bar_start = 0.5 - bar_w * 0.5
	var bar_end = 0.5 + bar_w * 0.5

	# 刻度点
	var dots = PackedVector2Array()
	for d in range(13):
		var dx = bar_start + (float(d) / 12) * bar_w
		dots.append(screen._map_uv(pts, dx, bar_y - 0.03))
		dots.append(screen._map_uv(pts, dx, bar_y - 0.01))
		dots.append(screen._map_uv(pts, dx, bar_y + 0.03))
		dots.append(screen._map_uv(pts, dx, bar_y + 0.05))
	if dots.size() > 0:
		pet.draw_multiline(dots, Color(base_color.r, base_color.g, base_color.b, ca * 0.25), 1.0, true)

	# 进度槽背景
	pet.draw_line(screen._map_uv(pts, bar_start, bar_y), screen._map_uv(pts, bar_end, bar_y), Color(base_color.r, base_color.g, base_color.b, ca * 0.15), 3.0, true)

	# 进度条填充 (非线性+离散化)
	var prog = fmod(pow(fmod(time * 0.35, 1.0), 1.5), 1.0)
	prog = floor(prog * 25.0) / 25.0
	var fill_end = bar_start + bar_w * prog
	if fill_end > bar_start + 0.01:
		pet.draw_line(screen._map_uv(pts, bar_start, bar_y), screen._map_uv(pts, fill_end, bar_y), base_color, 2.5, true)

	# 两端锚向
	pet.draw_line(screen._map_uv(pts, bar_start, bar_y - 0.05), screen._map_uv(pts, bar_start, bar_y + 0.05), base_color, 2.0, true)
	pet.draw_line(screen._map_uv(pts, bar_start - 0.02, bar_y - 0.02), screen._map_uv(pts, bar_start - 0.02, bar_y + 0.02), base_color, 1.0, true)
	pet.draw_line(screen._map_uv(pts, bar_end, bar_y - 0.05), screen._map_uv(pts, bar_end, bar_y + 0.05), base_color, 2.0, true)
	pet.draw_line(screen._map_uv(pts, bar_end + 0.02, bar_y - 0.02), screen._map_uv(pts, bar_end + 0.02, bar_y + 0.02), base_color, 1.0, true)

	# ── 角落装饰线 + 边框 ──
	var corner_len_f = 0.12
	var corner_color = Color.from_hsv(hue, 0.3, 0.7, ca * 0.3)
	for ci in range(4):
		var cp = pts[ci]
		var next_i = (ci + 1) % 4
		var prev_i = (ci + 3) % 4
		var to_next = (pts[next_i] - cp).normalized() * (pts[next_i] - cp).length() * corner_len_f
		var to_prev = (pts[prev_i] - cp).normalized() * (pts[prev_i] - cp).length() * corner_len_f
		pet.draw_line(cp, cp + to_next, corner_color, 0.5, true)
		pet.draw_line(cp, cp + to_prev, corner_color, 0.5, true)
	var border_color = Color.from_hsv(hue, 0.35, 0.75, ca * 0.2)
	for ei in range(4):
		pet.draw_line(pts[ei], pts[(ei + 1) % 4], border_color, 0.5, true)
