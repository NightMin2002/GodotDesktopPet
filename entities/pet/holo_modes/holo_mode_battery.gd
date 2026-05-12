# holo_mode_battery.gd — 全息屏电源状态监控渲染模块
# 横向电池外框 / 分段充能指示灯 / 脉冲电流波形 / 机能角标
class_name HoloModeBattery extends RefCounted

var screen: PetHoloScreen  # 由主控制器注入

# ── 电池状态 ──
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.6
	pet.draw_polygon(pts, [Color(0.02, 0.04, 0.08, alpha)])
	var ca = alpha * deploy
	var base_color = Color.from_hsv(hue, 0.5, 0.9, ca)

	var center_u = 0.5
	var center_v = 0.42

	# ── 电池外框 (横向) ──
	var bw = 0.22
	var bh = 0.12
	var rect_pts = PackedVector2Array([
		screen._map_uv(pts, center_u - bw, center_v - bh),
		screen._map_uv(pts, center_u + bw, center_v - bh),
		screen._map_uv(pts, center_u + bw, center_v + bh),
		screen._map_uv(pts, center_u - bw, center_v + bh),
		screen._map_uv(pts, center_u - bw, center_v - bh)
	])
	pet.draw_polyline(rect_pts, base_color, 2.0, true)

	# ── 正极凸起 ──
	var nub_w = 0.03
	var nub_h = 0.05
	var nub_pts = PackedVector2Array([
		screen._map_uv(pts, center_u + bw, center_v - nub_h),
		screen._map_uv(pts, center_u + bw + nub_w, center_v - nub_h),
		screen._map_uv(pts, center_u + bw + nub_w, center_v + nub_h),
		screen._map_uv(pts, center_u + bw, center_v + nub_h)
	])
	pet.draw_polygon(nub_pts, [base_color])

	# ── 充电进度条 (脉冲分块) ──
	var blocks = 5
	var fill_pct = 0.25 + sin(time * TAU / 4.0) * 0.25
	var active_blocks = int(fill_pct * blocks) + 1
	var pad_u = 0.03
	var pad_v = 0.04
	var block_w = ((bw - pad_u) * 2.0) / blocks

	for i in range(blocks):
		var alpha_mult = 1.0 if i < active_blocks else 0.15
		if i == active_blocks - 1:
			alpha_mult = 0.4 + 0.6 * abs(sin(time * 8.0))
		var b_start_u = center_u - bw + pad_u + i * block_w + 0.01
		var b_end_u = b_start_u + block_w - 0.02
		var b_pts = PackedVector2Array([
			screen._map_uv(pts, b_start_u, center_v - bh + pad_v),
			screen._map_uv(pts, b_end_u, center_v - bh + pad_v),
			screen._map_uv(pts, b_end_u, center_v + bh - pad_v),
			screen._map_uv(pts, b_start_u, center_v + bh - pad_v)
		])
		pet.draw_polygon(b_pts, [Color.from_hsv(hue, 0.4, 0.9, ca * alpha_mult)])

	# ── 底部大电流波形 ──
	var wave_v = 0.78
	var wave_pts = PackedVector2Array()
	for i in range(41):
		var u = 0.1 + (float(i) / 40) * 0.8
		var amp = 0.08 * sin(time * 12.0 + u * 25.0) * (1.0 - abs(u - 0.5)*2.0)
		wave_pts.append(screen._map_uv(pts, u, wave_v + amp))
	pet.draw_polyline(wave_pts, Color.from_hsv(hue, 0.4, 0.9, ca * 0.6), 1.5, true)
	pet.draw_line(screen._map_uv(pts, 0.1, wave_v), screen._map_uv(pts, 0.9, wave_v), Color.from_hsv(hue, 0.3, 0.7, ca * 0.2), 1.0, true)

	# ── 外围机能角标 ──
	var corner_len_f = 0.12
	var corner_color = Color.from_hsv(hue, 0.3, 0.7, ca * 0.4)
	for ci in range(4):
		var cp = pts[ci]
		var next_i = (ci + 1) % 4
		var prev_i = (ci + 3) % 4
		var to_next = (pts[next_i] - cp).normalized() * (pts[next_i] - cp).length() * corner_len_f
		var to_prev = (pts[prev_i] - cp).normalized() * (pts[prev_i] - cp).length() * corner_len_f
		pet.draw_line(cp, cp + to_next, corner_color, 1.0, true)
		pet.draw_line(cp, cp + to_prev, corner_color, 1.0, true)
	var border_color = Color.from_hsv(hue, 0.35, 0.75, ca * 0.2)
	for ei in range(4):
		pet.draw_line(pts[ei], pts[(ei + 1) % 4], border_color, 0.8, true)
