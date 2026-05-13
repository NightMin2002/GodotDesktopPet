# blackboard_chalk.gd — 黑板与粉笔 (升级版)
# 拥有真实的木纹边框、动态粉笔时钟、右侧专属涂鸦区以及底部的立体板擦
class_name TodoThemeBlackboardChalk extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.15, 0.25, 0.19),   # base: 极深墨绿色黑板
		Color(0.96, 0.96, 0.92),   # text: 白粉笔
		Color(0.95, 0.85, 0.35),   # accent: 黄粉笔
		Color(0.95, 0.45, 0.45),   # danger: 红粉笔
		1.0                        # alpha: 实体黑板完全不透明
	)
	
	card_corner = 2
	input_corner = 2
	list_spacing = 10
	checkbox_size_px = Vector2(28, 28)
	
	# 右侧留出 140px 给专属手绘涂鸦区和动态时钟
	panel_margins = [32, 28, 140, 36]
	
	bg_card_sel = Color.TRANSPARENT
	bd_select = accent

# ═══════════════════════════════════════════════
#  自定义边框面板: 木制边框木纹理 + 动态时钟 + 物理板擦
# ═══════════════════════════════════════════════

class _BlackboardPanel extends PanelContainer:
	var _t: TodoThemeBase
	var _time: float = 0.0
	
	func _init(t: TodoThemeBase) -> void: 
		_t = t
		
	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)
		
	func _process(delta: float) -> void:
		if not visible: return
		_time += delta
		queue_redraw()
		
	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# 1. 绘制木制边框底色
		var bs := 18.0 # 极宽的边框厚度
		var wood_c = Color(0.32, 0.18, 0.12)
		draw_rect(r, wood_c)
		
		# 2. 内切深墨绿黑板
		var board_r = r.grow(-bs)
		draw_rect(board_r, _t.bg_main)
		
		# 3. 极简程序化木纹 (Wood Grain Procedure)
		var rng = RandomNumberGenerator.new()
		rng.seed = 2077
		var grain_c = Color(0.15, 0.08, 0.05, 0.4)
		# 绘制四条边的波浪木纹
		for y in range(0, int(bs), 3):
			var pts_t = PackedVector2Array(); var pts_b = PackedVector2Array()
			for x in range(0, int(r.size.x), 20):
				var j = sin(x * 0.04 + rng.randf()*3.0) * 2.0
				pts_t.append(Vector2(x, y + j))
				pts_b.append(Vector2(x, r.size.y - bs + y + j))
			draw_polyline(pts_t, grain_c, 1.5)
			draw_polyline(pts_b, grain_c, 1.5)
		for x in range(0, int(bs), 3):
			var pts_l = PackedVector2Array(); var pts_r = PackedVector2Array()
			for y in range(0, int(r.size.y), 20):
				var j = sin(y * 0.04 + rng.randf()*3.0) * 2.0
				pts_l.append(Vector2(x + j, y))
				pts_r.append(Vector2(r.size.x - bs + x + j, y))
			draw_polyline(pts_l, grain_c, 1.5)
			draw_polyline(pts_r, grain_c, 1.5)
			
		# 木框立体切割拼接阴影与高光
		draw_line(Vector2(bs, bs), Vector2(r.size.x - bs, bs), Color(0,0,0, 0.7), 3.0)
		draw_line(Vector2(bs, bs), Vector2(bs, r.size.y - bs), Color(0,0,0, 0.7), 3.0)
		draw_line(Vector2(bs, r.size.y - bs), Vector2(r.size.x - bs, r.size.y - bs), Color(1,1,1, 0.2), 2.0)
		draw_line(Vector2(r.size.x - bs, bs), Vector2(r.size.x - bs, r.size.y - bs), Color(1,1,1, 0.2), 2.0)
		
		# 斜切角接缝线
		draw_line(Vector2(0,0), Vector2(bs, bs), Color(0,0,0, 0.8), 2.0)
		draw_line(Vector2(size.x,0), Vector2(size.x-bs, bs), Color(0,0,0, 0.8), 2.0)
		draw_line(Vector2(0,size.y), Vector2(bs, size.y-bs), Color(0,0,0, 0.8), 2.0)
		draw_line(Vector2(size.x,size.y), Vector2(size.x-bs, size.y-bs), Color(0,0,0, 0.8), 2.0)

		# 4. 粉笔残留擦痕 (白灰涂抹)
		rng.seed = 8848
		var dust_c = Color(_t.tx_primary, 0.015)
		for i in range(25):
			var cx = rng.randf_range(bs, r.size.x - bs)
			var cy = rng.randf_range(bs, r.size.y - bs)
			var rad = rng.randf_range(30, 90)
			var pts = PackedVector2Array()
			var a_c = rng.randf_range(0.6, 1.8) 
			for ang in range(0, 360, 30):
				var rad_ang = deg_to_rad(ang)
				pts.append(Vector2(cx + cos(rad_ang) * rad * a_c, cy + sin(rad_ang) * rad))
			draw_polygon(pts, PackedColorArray([dust_c]))
			
		# 5. 零散涂鸦与彩蛋
		var dc = Color(_t.tx_primary, 0.12)
		# 涂鸦 A：左下角的杂乱算式
		var cx2 = 30.0 + bs
		var cy2 = r.size.y - bs - 50.0
		var p2 = PackedVector2Array([
			Vector2(cx2+5, cy2-35), Vector2(cx2-12, cy2+20), Vector2(cx2-5, cy2+28),
			Vector2(cx2+45, cy2-25), Vector2(cx2+40, cy2-30), Vector2(cx2+25, cy2+8)
		])
		draw_polyline(p2, dc, 3.0)
		draw_line(Vector2(cx2+60, cy2-8), Vector2(cx2+80, cy2-8), dc, 2.5)
		draw_line(Vector2(cx2+60, cy2+2), Vector2(cx2+80, cy2+2), dc, 2.5)
		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(cx2+90, cy2+8), "mc² = E", 0, -1, 16, dc)

		# 涂鸦 B：右下方涂鸦区的井字棋
		var tl = Vector2(r.size.x - 70, r.size.y - bs - 100)
		var l3 = 35.0
		var p3_lines = [
			[Vector2(-l3, -12), Vector2(l3, -8)], [Vector2(-l3, 16), Vector2(l3, 18)],
			[Vector2(-15, -l3), Vector2(-12, l3)], [Vector2(16, -l3), Vector2(18, l3)]
		]
		for L in p3_lines: draw_line(tl + L[0], tl + L[1], dc, 3.0)
		var p3c = PackedVector2Array() 
		for a in range(0, 380, 20): p3c.append(tl + Vector2(25, -22) + Vector2(cos(deg_to_rad(a))*12, sin(deg_to_rad(a))*14))
		draw_polyline(p3c, dc, 2.5)
		draw_line(tl + Vector2(-35, -35), tl + Vector2(-5, -5), dc, 2.5)
		draw_line(tl + Vector2(-10, -35), tl + Vector2(-40, -5), dc, 2.5)
			
		# 6. 右侧边缘：手绘 3D 正方体透视教学
		var cube_orig = Vector2(r.size.x - 75, r.size.y * 0.5)
		var cv1 = cube_orig + Vector2(0, 0); var cv2 = cube_orig + Vector2(20, -5); 
		var cv3 = cube_orig + Vector2(20, 15); var cv4 = cube_orig + Vector2(0, 20)
		var d = Vector2(-10, -15)
		draw_polyline(PackedVector2Array([cv1, cv2, cv3, cv4, cv1]), dc, 2.0)
		draw_polyline(PackedVector2Array([cv1+d, cv2+d, cv3+d, cv4+d, cv1+d]), dc, 2.0) # 背面
		draw_line(cv1, cv1+d, dc, 2.0); draw_line(cv2, cv2+d, dc, 2.0)
		draw_line(cv3, cv3+d, dc, 2.0); draw_line(cv4, cv4+d, dc, 2.0)
		
		# 7. 实时粉笔时钟 (右上角专属空间)!
		var time_dict = Time.get_time_dict_from_system()
		var hr = time_dict.hour % 12
		var mi = time_dict.minute
		var se = time_dict.second
		var clock_c = Vector2(r.size.x - 70, bs + 60)
		var cr = 40.0
		var c_chalk = Color(_t.tx_primary, 0.8)
		
		# 两圈错乱重叠的圆圈作为表盘
		var c_pts1 = PackedVector2Array(); var c_pts2 = PackedVector2Array()
		for a in range(0, 365, 10):
			var rr = deg_to_rad(a)
			var jitter1 = rng.randf_range(-1.5, 1.5)
			var jitter2 = rng.randf_range(-2.0, 2.0)
			c_pts1.append(clock_c + Vector2(cos(rr), sin(rr)) * (cr + jitter1))
			c_pts2.append(clock_c + Vector2(cos(rr), sin(rr)) * (cr - 3 + jitter2))
		draw_polyline(c_pts1, c_chalk, 2.0)
		draw_polyline(c_pts2, Color(c_chalk, 0.4), 1.5)
		
		# 画表盘刻度
		for a in range(0, 360, 30):
			var rr = deg_to_rad(a)
			var tick_len = 6.0 if a % 90 == 0 else 3.0
			draw_line(clock_c + Vector2(cos(rr), sin(rr))*(cr-1), clock_c + Vector2(cos(rr), sin(rr))*(cr-1-tick_len), c_chalk, 2.0)
			
		# 根据现实时间计算旋转角
		var hr_ang = (hr + mi/60.0) * PI/6.0 - PI/2.0
		var mi_ang = (mi + se/60.0) * PI/30.0 - PI/2.0
		var se_ang = se * PI/30.0 - PI/2.0
		# 极其粗糙的手绘指针
		draw_line(clock_c, clock_c + Vector2(cos(hr_ang), sin(hr_ang)) * (cr * 0.45), c_chalk, 4.0)
		draw_line(clock_c, clock_c + Vector2(cos(mi_ang), sin(mi_ang)) * (cr * 0.75), c_chalk, 2.5)
		draw_line(clock_c, clock_c + Vector2(cos(se_ang), sin(se_ang)) * (cr * 0.85), Color(_t.danger, 0.8), 1.5)
		draw_circle(clock_c, 3.0, c_chalk) # 表盘轴心

		# 8. 立体黑板擦 (静静地放置在底部右下角木方边框上)
		var eraser_x = r.size.x - 170
		var eraser_y = r.size.y - bs - 10
		# 下方木条在木框内，产生一点阴影
		draw_rect(Rect2(eraser_x + 6, eraser_y + 10, 48, 6), Color(0,0,0, 0.4)) 
		# 蓝色厚实耐用的毡布海绵层
		draw_rect(Rect2(eraser_x, eraser_y, 48, 10), Color(0.18, 0.28, 0.38))
		# 黑色沉重的塑料壳/木壳把手
		draw_rect(Rect2(eraser_x, eraser_y - 12, 48, 12), Color(0.1, 0.08, 0.05))
		# 塑料壳高光线
		draw_line(Vector2(eraser_x, eraser_y - 12), Vector2(eraser_x + 48, eraser_y - 12), Color(1,1,1,0.2), 2.0)
		draw_line(Vector2(eraser_x, eraser_y), Vector2(eraser_x + 48, eraser_y), Color(1,1,1,0.2), 1.0)
		
		# 9. 手绘感标题栏直线
		var ty = bs + _t.title_bar_height
		var chalk_l_c = Color(_t.tx_primary, 0.5)
		draw_line(Vector2(bs + 10, ty - 1.5), Vector2(r.size.x - bs - 140, ty + 1.5), chalk_l_c, 2.0)
		draw_line(Vector2(bs + 8, ty + 1.0), Vector2(r.size.x - bs - 144, ty - 1.0), chalk_l_c, 1.5)

func create_panel() -> PanelContainer:
	return _BlackboardPanel.new(self)

# ═══════════════════════════════════════════════
#  组件覆写：粉笔颗粒堆叠与强手绘感
# ═══════════════════════════════════════════════

class _ChalkProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0; var _total: int = 0
	var _rng := RandomNumberGenerator.new()

	func _init(t: TodoThemeBase) -> void:
		_t = t; mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 26)

	func update(done: int, total: int) -> void:
		_done = done; _total = total; queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		var chalk = _t.accent if _done >= _total else Color(_t.tx_primary, 0.8)
		var ratio = float(_done) / float(_total)

		var bx := 20.0; var bar_h := 16.0; var by := (size.y - bar_h) * 0.5
		var bar_w := size.x - bx * 2
		_rng.seed = 99

		# 多层歪斜线绘制粗糙边框
		for layer in range(3):
			var a = [0.2, 0.35, 0.55][layer]
			var w = [2.5, 2.0, 1.0][layer]
			var lc = Color(chalk, a)
			_c_line(Vector2(bx - 2, by), Vector2(bx + bar_w + 2, by), lc, w)
			_c_line(Vector2(bx - 1, by + bar_h), Vector2(bx + bar_w + 1, by + bar_h), lc, w)
			_c_line(Vector2(bx, by - 1), Vector2(bx, by + bar_h + 1), lc, w)
			_c_line(Vector2(bx + bar_w, by - 1), Vector2(bx + bar_w, by + bar_h + 1), lc, w)

		# 涂鸦状对角线填充式进度
		var fill_w = bar_w * ratio
		if fill_w > 2:
			var x = bx + 2
			while x < bx + fill_w - 2:
				var dy = _rng.randf_range(-1, 1)
				draw_line(Vector2(x, by + 2 + dy), Vector2(x + 4, by + bar_h - 2 + dy), Color(chalk, 0.4), 2.5)
				x += 4.5
			draw_rect(Rect2(bx + 1, by + 1, fill_w - 2, bar_h - 2), Color(chalk, 0.12))

		# 掉落粉末特效
		_rng.seed = 234
		for i in range(25):
			var px = _rng.randf_range(bx - 6, bx + bar_w + 6)
			var py = _rng.randf_range(by - 5, by + bar_h + 5)
			if absf(py - by) < 4 or absf(py - by - bar_h) < 4 or absf(px - bx) < 4 or absf(px - bx - bar_w) < 4:
				draw_circle(Vector2(px, py), _rng.randf_range(0.5, 1.2), Color(chalk, _rng.randf_range(0.1, 0.4)))

		# 分数文本及其擦拭底霜
		var font = ThemeDB.fallback_font
		var text = "%d / %d" % [_done, _total]
		var ts = font.get_string_size(text, 0, -1, 12)
		var tx = (size.x - ts.x) * 0.5
		var ty = (size.y + ts.y * 0.5) * 0.5
		
		# 模拟先擦干再写入
		var cx = size.x * 0.5
		var cy = ty - ts.y * 0.3
		var board_c = Color(_t.bg_main, 0.8)
		for i in range(4):
			var rx = ts.x * 0.5 + _rng.randf_range(6, 12)
			var ry = _rng.randf_range(6, 10)
			var pts = PackedVector2Array()
			for ang in range(0, 360, 30):
				pts.append(Vector2(cx + cos(deg_to_rad(ang))*rx, cy + sin(deg_to_rad(ang))*ry + _rng.randf_range(-2,2)))
			draw_polygon(pts, PackedColorArray([board_c]))

		_rng.seed = 55
		for i in range(3):
			draw_string(font, Vector2(tx + _rng.randf_range(-1, 1), ty + _rng.randf_range(-1, 1)), text, 0, -1, 12, Color(chalk, 0.25))
		draw_string(font, Vector2(tx, ty), text, 0, -1, 12, chalk)

	func _c_line(from: Vector2, to: Vector2, c: Color, w: float) -> void:
		draw_line(from + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)), to + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)), c, w)

func make_progress_indicator() -> Control:
	return _ChalkProgress.new(self)

func update_progress_indicator(c: Control, d: int, t: int) -> void:
	if c and c.has_method("update"): c.update(d, t)

# 复选框：从原先的空隙变轨为厚重的粗暴粉笔填涂
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(1)
	s.bg_color = Color.TRANSPARENT
	
	if is_done:
		s.set_border_width_all(2)
		s.border_color = Color(tx_primary, 0.1) # 变暗淡
		
		# 极其奔放的“突破方框”粉笔大对勾
		var cx = accent
		btn.draw.connect(func():
			# 起点：框内偏左
			var p1 = Vector2(-2, 14)
			# 底端：跌穿方框下方
			var p2 = Vector2(8, 30)
			# 终点：往右上飞离方框控制
			var p3 = Vector2(34, -8)

			# 主体笔触
			btn.draw_line(p1, p2, cx, 3.5)
			btn.draw_line(p2, p3, cx, 4.0)
			
			# 粉笔双刀和抖动痕迹 (重影副线)
			btn.draw_line(p1 + Vector2(1, -2), p2 + Vector2(2, 0), Color(cx, 0.5), 1.5)
			btn.draw_line(p2 + Vector2(2, 0), p3 + Vector2(-1, 1), Color(cx, 0.7), 2.5)
			
			# 散落粉末 (保证点位固定不变)
			var rng = RandomNumberGenerator.new()
			rng.seed = btn.get_instance_id() 
			for i in range(8):
				btn.draw_circle(Vector2(rng.randf_range(-6, 38), rng.randf_range(-6, 32)), rng.randf_range(0.8, 2.0), Color(cx, rng.randf_range(0.2, 0.8)))
		)
	else:
		s.set_border_width_all(2)
		s.border_color = Color(tx_primary, 0.6)
		# 添加底色白灰感，像刚擦过
		s.bg_color = Color(tx_primary, 0.03)
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(accent, 0.08) if is_done else Color(tx_primary, 0.1)
	h.border_color = tx_primary
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 卡片：取消系统自带渲染，纯以自绘手写圈取代
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.bg_color = Color.TRANSPARENT
	
	if is_selected:
		s.border_color = accent
		s.border_width_bottom = 4
		s.border_width_left = 3
		s.border_width_top = 0
		s.border_width_right = 0
	elif is_done:
		s.bg_color = Color(tx_primary, 0.04) 
		s.set_border_width_all(0)
	else:
		s.set_border_width_all(0)
		
	return s

# 粉笔极简手画空心圈按钮
func _chalk_btn(text: String, c: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", c.lightened(0.2))
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color(c, 0.65)
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(c, 0.15)
	h.border_color = c
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	
	return btn

func make_add_button(text: String) -> Button: return _chalk_btn("+" + text, tx_primary)
func make_close_button(text: String) -> Button: return _chalk_btn(text, danger)
func make_theme_button(text: String) -> Button: return _chalk_btn(text, accent)

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.bg_color = Color(tx_primary, 0.04)
		f.set_border_width_all(1)
		f.border_color = Color(tx_primary, 0.3)

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done: 
		label.add_theme_color_override("font_color", Color(tx_primary, 0.35))
	else: 
		label.add_theme_color_override("font_color", tx_primary)

# ==========================================
# 自定义滚动条：粉笔痕与粉笔灰
# ==========================================
class _ChalkScrollbar extends TodoScrollbar:
	var _rng := RandomNumberGenerator.new()

	func _draw_track(track: Rect2) -> void:
		_rng.seed = 333
		var c = Color(_t.tx_primary, 0.15)
		var cx = track.position.x + track.size.x * 0.5
		# 粗糙的粉笔痕迹垂直线
		for i in range(2):
			var pts = PackedVector2Array()
			var y = track.position.y
			while y <= track.end.y:
				pts.append(Vector2(cx + _rng.randf_range(-1.5, 1.5), y))
				y += 10.0
			pts.append(Vector2(cx, track.end.y))
			draw_polyline(pts, c, 1.5)

	func _draw_thumb(thumb: Rect2) -> void:
		_rng.seed = int(thumb.position.y) * 10
		var chalk_c = Color(_t.tx_primary, 0.8)
		if _dragging: chalk_c = _t.accent
		# 画一堆密集的粉笔灰颗粒形成拇指块
		for i in range(25):
			var p = thumb.position + Vector2(_rng.randf_range(2, thumb.size.x-2), _rng.randf_range(2, thumb.size.y-2))
			var r = _rng.randf_range(1.0, 3.0)
			var a = _rng.randf_range(0.3, 0.9) if not _dragging else 1.0
			draw_circle(p, r, Color(chalk_c, a))

func make_scrollbar() -> Control:
	return _ChalkScrollbar.new(self)
