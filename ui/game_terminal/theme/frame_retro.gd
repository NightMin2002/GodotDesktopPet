# frame_retro.gd — 街机 CRT 风格外壳渲染器
# 厚重直角边框 + 立体面高光 + CRT 内屏 + 隔行扫描纹 + REC 指示灯 + 铆钉
extends Control

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var hue = EventBus.ui_hue
	var w = size.x
	var h = size.y
	var bw = 12.0  # 外壳厚度

	# ── 1. 全黑底 ──
	draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.05, 0.05, 0.98))

	# ── 2. 外壳框体 (暗边 + 主色 + 亮边 → 立体感) ──
	var shell_dark = Color.from_hsv(hue, 0.4, 0.15, 1.0)
	var shell_main = Color.from_hsv(hue, 0.4, 0.3, 1.0)
	var shell_light = Color.from_hsv(hue, 0.4, 0.5, 1.0)
	draw_rect(Rect2(0, 0, w, h), shell_dark, false, bw * 2.0)
	draw_rect(Rect2(bw / 2, bw / 2, w - bw, h - bw), shell_main, false, bw)
	# 顶部 + 左侧亮边
	draw_line(Vector2(bw, bw / 2), Vector2(w - bw, bw / 2), shell_light, bw / 2)
	draw_line(Vector2(bw / 2, bw), Vector2(bw / 2, h - bw), shell_light, bw / 2)

	# ── 3. CRT 内屏死区 (纯黑粗边) ──
	var inner_bw = 4.0
	draw_rect(Rect2(bw, bw, w - bw * 2, h - bw * 2), Color.BLACK, false, inner_bw * 2.0)

	# ── 4. REC 指示灯 (1Hz 硬闪烁) ──
	if int(_time * 2.0) % 2 == 0:
		draw_rect(Rect2(w - bw - 24, bw + 12, 10, 10), Color.RED)

	# ── 5. CRT 隔行扫描暗纹 ──
	var scan_c = Color(0, 0, 0, 0.25)
	var scan_gap = 4.0
	var scan_start = bw + inner_bw
	var scan_end = h - bw - inner_bw
	var y = scan_start
	while y < scan_end:
		draw_line(
			Vector2(bw + inner_bw, y),
			Vector2(w - bw - inner_bw, y),
			scan_c, 1.0)
		y += scan_gap

	# ── 6. 四角铆钉 ──
	var rivet_c = Color.from_hsv(hue, 0.2, 0.7, 1.0)
	var ri = 4.0  # 铆钉尺寸
	draw_rect(Rect2(bw, bw, ri, ri), rivet_c)
	draw_rect(Rect2(w - bw - ri, bw, ri, ri), rivet_c)
	draw_rect(Rect2(bw, h - bw - ri, ri, ri), rivet_c)
	draw_rect(Rect2(w - bw - ri, h - bw - ri, ri, ri), rivet_c)
