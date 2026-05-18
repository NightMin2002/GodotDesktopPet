# game_terminal_frame.gd — 街机 CRT 风格外壳渲染器
# 厚重直角边框 + 硬闪烁指示灯 + 点阵扫描遮罩
extends Control

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var hue = EventBus.ui_hue
	var w = size.x
	var h = size.y
	
	# 1. 街机厚重外直角外壳
	var border_w = 12.0
	var bg_col = Color(0.05, 0.05, 0.05, 0.98)
	var shell_col = Color.from_hsv(hue, 0.4, 0.3, 1.0)
	var shell_light = Color.from_hsv(hue, 0.4, 0.5, 1.0)
	var shell_dark = Color.from_hsv(hue, 0.4, 0.15, 1.0)
	
	# 画全黑底
	draw_rect(Rect2(0, 0, w, h), bg_col)
	
	# 画外壳阴影和底边框来做立体厚重感
	draw_rect(Rect2(0, 0, w, h), shell_dark, false, border_w * 2.0)
	draw_rect(Rect2(border_w/2, border_w/2, w - border_w, h - border_w), shell_col, false, border_w)
	
	# 顶部凸起亮边模拟立体面
	draw_line(Vector2(border_w, border_w/2), Vector2(w - border_w, border_w/2), shell_light, border_w/2)
	draw_line(Vector2(border_w/2, border_w), Vector2(border_w/2, h - border_w), shell_light, border_w/2)

	# 2. 内屏黑边框 (CRT 黑色死区)
	var screen_rect = Rect2(border_w, border_w, w - border_w*2, h - border_w*2)
	var inner_border = 4.0
	draw_rect(screen_rect, Color.BLACK, false, inner_border * 2.0)
	
	# 3. 街机硬闪烁录像指示灯 (Blinking REC 1Hz)
	var blink = int(_time * 2.0) % 2 == 0
	if blink:
		var rec_c = Color.RED
		draw_rect(Rect2(w - border_w - 24, border_w + 12, 10, 10), rec_c)
	
	# 4. CRT 点阵扫描暗纹覆盖 (隔行扫描纹理)
	var line_gap = 4.0
	var scan_c = Color(0, 0, 0, 0.25)
	var y = border_w + inner_border
	while y < h - border_w - inner_border:
		draw_line(Vector2(border_w + inner_border, y), Vector2(w - border_w - inner_border, y), scan_c, 1.0)
		y += line_gap
		
	# 5. 复古四角铆钉装饰区块
	var rivet_c = Color.from_hsv(hue, 0.2, 0.7, 1.0)
	var ri_off = border_w
	draw_rect(Rect2(ri_off, ri_off, 4, 4), rivet_c)
	draw_rect(Rect2(w - ri_off - 4, ri_off, 4, 4), rivet_c)
	draw_rect(Rect2(ri_off, h - ri_off - 4, 4, 4), rivet_c)
	draw_rect(Rect2(w - ri_off - 4, h - ri_off - 4, 4, 4), rivet_c)
